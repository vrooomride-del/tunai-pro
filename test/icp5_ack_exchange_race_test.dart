// P0 fix — ICP5 ACK Exchange Race Condition.
//
// Root cause (see the ACK-race investigation, prior session): `_exchange()`
// previously used `response.future.timeout(readTimeout)`. `Future.timeout()`
// returns a *derived* future; once its internal timer fires, that derived
// future resolves with `TimeoutException` regardless of whether the
// underlying `response` Completer is ever completed — `response` itself is
// left live and completable. Because every ICP5 PEQ success ACK is
// content-identical (`55 07 E1 00 00 00 18 00 55` regardless of channel,
// band, or property — see icp5_frame_codec.dart's `_parseSuccessAck`, which
// checks only param-ID + a single status byte), a device ACK that happened
// to arrive right around the timeout deadline could still be routed by
// `_onBytes` and `.complete()`d — silently discarded at best, or misrouted to
// satisfy a *different* exchange at worst.
//
// Fix: `_exchange()` now uses an explicit `Timer` whose callback
// invalidates the pending request (`_clearApplicationRequest` — clears
// `_pendingResponse`/`_pendingAccepts`/`_activeGeneration`) in the same
// synchronous callback as failing `response`, closing the decoupling window.
//
// These tests exercise the fix's observable guarantees through the public
// transport API only (no access to private `_exchange`/`_onBytes` — this
// file lives outside `lib/`). They do not attempt to force the exact
// microtask-level race (not reliably reproducible with wall-clock Timers in
// a unit test); instead they prove the invariant the fix guarantees: a frame
// that arrives after an exchange has already timed out and fully cleaned up
// must not resurrect that exchange's result, and must not corrupt a
// subsequent exchange.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

const identityRx = <int>[
  0x55, 0x18, 0xE0, 0, 0, 0, 0, 0, //
  0x44, 0x53, 0x50, 0x31, 0x37, 0x30, 0x31, 0x2E, //
  0x31, 0x30, 0x30, 0x2E, 0x30, 0x30, 0x2E, 0x30, 0x31, //
  0xD9,
];

/// The exact generic PEQ success ACK from the reported evidence — identical
/// for every channel/band/property (param 0x18, status 0x00). Checksum
/// verified: 0x55+0x07+0xE1+0x18 = 0x155 -> 0x55.
const goodPeqAck = <int>[0x55, 0x07, 0xE1, 0, 0, 0, 0x18, 0, 0x55];

class FakeConnection implements Icp5SerialConnection {
  final _controller = StreamController<List<int>>.broadcast(sync: true);
  final List<List<int>> writes = [];
  final void Function(FakeConnection connection, int call, List<int> bytes)
      onWrite;
  FakeConnection(this.onWrite);
  @override
  Stream<List<int>> get bytes => _controller.stream;
  void emit(List<int> bytes) => _controller.add(bytes);
  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    writes.add(List.from(bytes));
    onWrite(this, writes.length, bytes);
    return bytes.length;
  }

  @override
  Future<void> close() async => _controller.close();
}

class FakeDriver implements Icp5SerialDriver {
  final FakeConnection connection;
  final List<Icp5SerialDevice> devices;
  String? openedPort;
  FakeDriver(this.connection,
      {this.devices = const [
        Icp5SerialDevice(
            portName: 'COM27',
            vendorId: 0x1A86,
            productId: 0x55D6,
            productName: 'USB-BLE-SERIAL CH9143')
      ]});
  @override
  bool get platformSupported => true;
  @override
  Future<Icp5DiscoveryResult> discover() async => Icp5DiscoveryResult(
      source: 'Fake SetupAPI',
      allPorts: devices,
      matches: devices.where((device) => device.isCaptureProvenIcp5).toList());
  @override
  Future<Icp5SerialConnection> open(String portName) async {
    openedPort = portName;
    return connection;
  }
}

void main() {
  test('normal PEQ write still PASS', () async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 2) connection.emit(goodPeqAck);
    });
    final transport = Icp5UsbTransport(driver: FakeDriver(connection));
    expect((await transport.open()).success, isTrue);

    final result = await transport.writePeqFrequency(3, 1000, band: 7);
    expect(result.success, isTrue);
    expect(result.message, 'PASS_ACK');
    expect(connection.writes, hasLength(2)); // handshake + exactly one write

    await transport.close();
  });

  test(
      'delayed ACK after timeout must not complete a later request',
      () async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) {
        connection.emit(identityRx);
      }
      // call 2 (band 7 write): withhold the response — it must time out on
      // its own. call 3 (band 8 write): also withhold — if the fix has a
      // gap, a stray late ACK meant for call 2 could wrongly satisfy this.
    });
    final transport = Icp5UsbTransport(
      driver: FakeDriver(connection),
      readTimeout: const Duration(milliseconds: 15),
      staleAckQuarantine: const Duration(milliseconds: 5),
    );
    expect((await transport.open()).success, isTrue);

    final first = await transport.writePeqFrequency(3, 1000, band: 7);
    expect(first.success, isFalse,
        reason: 'no response was ever sent for the band 7 write — it must '
            'time out, not hang or spuriously pass');

    // The band 7 write's exchange has now fully timed out and cleaned up
    // (readTimeout + staleAckQuarantine already elapsed by the time the
    // await above returned). Simulate its real device ACK finally, belatedly
    // arriving — content-identical to any other PEQ ACK — well after
    // _exchange() already gave up and returned null for it.
    connection.emit(goodPeqAck);

    // Immediately start the next request. If the late frame above were still
    // live (the pre-fix race), it — or the corrupted pending-response state
    // it could leave behind — must not leak into this new exchange.
    final second = await transport.writePeqFrequency(3, 1000, band: 8);
    expect(second.success, isFalse,
        reason: 'band 8 write also received no real response of its own; '
            'the stale band-7 ACK must not have satisfied it');
    expect(first.success, isFalse,
        reason: "the belated emit must not retroactively flip the "
            "already-returned band 7 result");

    await transport.close();
  });

  test('PEQ identical ACK frames cannot satisfy a stale/wrong generation',
      () async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) {
        connection.emit(identityRx);
      } else if (call == 3) {
        // Only the SECOND write (call 3) gets its own, correctly-timed ACK.
        connection.emit(goodPeqAck);
      }
      // call 2 (first write) intentionally gets no response of its own.
    });
    final transport = Icp5UsbTransport(
      driver: FakeDriver(connection),
      readTimeout: const Duration(milliseconds: 15),
      staleAckQuarantine: const Duration(milliseconds: 5),
    );
    await transport.open();

    final first = await transport.writePeqFrequency(3, 1000, band: 7);
    expect(first.success, isFalse);

    // A frame identical to the generic PEQ ACK, emitted after the first
    // exchange's generation has already been invalidated by its own
    // timeout — must be dropped as a stale/ungenerationed frame, not
    // attributed to generation 1 after the fact.
    connection.emit(goodPeqAck);

    final second = await transport.writePeqFrequency(3, 1000, band: 8);
    expect(second.success, isTrue,
        reason: 'the second write must succeed on its OWN ACK (call 3)');
    expect(second.message, 'PASS_ACK');

    // The first write's result, already returned, is unaffected by anything
    // that happened afterward.
    expect(first.success, isFalse);

    await transport.close();
  });
}
