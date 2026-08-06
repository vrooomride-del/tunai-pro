import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:tunai_pro/core/transport/dsp_transport.dart';
import 'package:tunai_pro/core/transport/icp5_bluetooth_driver.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

const identityRx = <int>[
  0x55,
  0x18,
  0xE0,
  0,
  0,
  0,
  0,
  0,
  0x44,
  0x53,
  0x50,
  0x31,
  0x37,
  0x30,
  0x31,
  0x2E,
  0x31,
  0x30,
  0x30,
  0x2E,
  0x30,
  0x30,
  0x2E,
  0x30,
  0x31,
  0xD9,
];
const volumeAck = <int>[0x55, 0x07, 0xE1, 0, 0, 0, 0x10, 0, 0x4D];

class _FakeGattConnection implements Icp5SerialConnection {
  final _controller = StreamController<List<int>>.broadcast(sync: true);
  bool _closed = false;
  final writes = <List<int>>[];
  final void Function(_FakeGattConnection connection, int call, List<int> bytes)
      onWrite;
  // Simulates real BLE write(withoutResponse:false) latency -- write()
  // awaiting the ATT Write Response takes real time on real hardware
  // (measured up to ~2.56 s on a first connection per
  // Icp5BluetoothTransport's own class doc). Zero by default so every
  // existing test using this fixture is unaffected.
  final Duration writeDelay;

  _FakeGattConnection(this.onWrite, {this.writeDelay = Duration.zero});

  @override
  Stream<List<int>> get bytes => _controller.stream;

  // Guard against Future.delayed callbacks that fire after close() — a
  // delayed notification in a timeout-failure test should be a no-op, not a
  // "test failed after it already completed" error.
  void notify(List<int> bytes) {
    if (!_closed) _controller.add(bytes);
  }

  void disconnectNotify() {
    if (!_closed) {
      _controller.addError(StateError('ICP5 BLE Notify disconnected.'));
    }
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    writes.add(List<int>.of(bytes));
    onWrite(this, writes.length, bytes);
    return bytes.length;
  }

  @override
  Future<void> close() async {
    _closed = true;
    return _controller.close();
  }
}

class _FakeGattDriver implements Icp5SerialDriver {
  final _FakeGattConnection connection;
  int discoverCalls = 0;
  String? openedPort;
  _FakeGattDriver(this.connection);

  @override
  bool get platformSupported => true;

  @override
  Future<Icp5DiscoveryResult> discover() async {
    discoverCalls++;
    return const Icp5DiscoveryResult(source: 'fake FFF0', allPorts: [
      Icp5SerialDevice(portName: 'ble-device'),
      Icp5SerialDevice(portName: 'ble-selected')
    ], matches: [
      Icp5SerialDevice(portName: 'ble-device'),
      Icp5SerialDevice(portName: 'ble-selected')
    ]);
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    openedPort = portName;
    return connection;
  }
}

// Driver variant that returns successive connections on each open() call,
// needed for reconnect-after-disconnect tests.
class _MultiOpenFakeDriver implements Icp5SerialDriver {
  final List<_FakeGattConnection> _connections;
  int _openIndex = 0;

  _MultiOpenFakeDriver(this._connections);

  @override
  bool get platformSupported => true;

  @override
  Future<Icp5DiscoveryResult> discover() async => const Icp5DiscoveryResult(
      source: 'fake FFF0',
      allPorts: [Icp5SerialDevice(portName: 'ble-device')],
      matches: [Icp5SerialDevice(portName: 'ble-device')]);

  @override
  Future<Icp5SerialConnection> open(String portName) async =>
      _connections[_openIndex++];
}

void main() {
  group('Icp5BluetoothGattDriver scan accumulation', () {
    test('ICP5 remains discoverable when connectable toggles true → false', () {
      final accumulated = <String, Icp5SerialDevice>{};
      const id = 'AA:BB:CC:DD:EE:FF';
      const source = 'test';

      // Emission 1: ICP5 seen (connectable=true in real BLE packet)
      Icp5BluetoothGattDriver.accumulateRawResult(
          accumulated, id, 'WONDOM ICP5', -70, source);
      expect(accumulated, hasLength(1));

      // Emission 2: same device re-emitted with connectable=false in real BLE.
      // Old code filtered this; new code keeps and updates RSSI.
      Icp5BluetoothGattDriver.accumulateRawResult(
          accumulated, id, 'WONDOM ICP5', -65, source);
      expect(accumulated, hasLength(1));
      expect(accumulated[id]?.friendlyName, 'WONDOM ICP5');
      expect(accumulated[id]?.rssi, -65);
    });

    test('results from multiple scan emissions accumulate by identifier', () {
      final accumulated = <String, Icp5SerialDevice>{};
      const source = 'test';

      // Emission 1: device A and ICP5
      Icp5BluetoothGattDriver.accumulateRawResult(
          accumulated, 'id-a', 'Device A', -80, source);
      Icp5BluetoothGattDriver.accumulateRawResult(
          accumulated, 'id-icp5', 'WONDOM ICP5', -72, source);

      // Emission 2: device B and ICP5 again (different RSSI)
      Icp5BluetoothGattDriver.accumulateRawResult(
          accumulated, 'id-b', 'Device B', -90, source);
      Icp5BluetoothGattDriver.accumulateRawResult(
          accumulated, 'id-icp5', 'WONDOM ICP5', -68, source);

      expect(accumulated, hasLength(3));
      expect(accumulated['id-a']?.friendlyName, 'Device A');
      expect(accumulated['id-b']?.friendlyName, 'Device B');
      expect(accumulated['id-icp5']?.friendlyName, 'WONDOM ICP5');
      expect(accumulated['id-icp5']?.rssi, -68); // latest RSSI overwrites
    });
  });

  test(
      'BLE transport defaults to a 250ms stale-ACK quarantine, not the USB '
      '50ms default (deploy-stability fix)', () {
    final defaultTransport = Icp5BluetoothTransport();
    expect(
        defaultTransport.staleAckQuarantine, const Duration(milliseconds: 250));

    // Still explicitly overridable — callers/tests keep full control.
    final overridden = Icp5BluetoothTransport(
        staleAckQuarantine: const Duration(milliseconds: 400));
    expect(overridden.staleAckQuarantine, const Duration(milliseconds: 400));
  });

  test(
      'BLE transport defaults to a 3s read timeout, not the USB 1s default '
      '(first-connect stability fix)', () {
    final defaultTransport = Icp5BluetoothTransport();
    expect(defaultTransport.readTimeout, const Duration(seconds: 3));

    // Still explicitly overridable — callers/tests keep full control.
    final overridden =
        Icp5BluetoothTransport(readTimeout: const Duration(seconds: 5));
    expect(overridden.readTimeout, const Duration(seconds: 5));
  });

  test(
      'BLE handshake succeeds when device response arrives after >1 s '
      '(USB 1s timeout would fail; BLE 3s default accommodates first-connect '
      'connection-interval latency)', () async {
    // Simulate a slow first-connect: identity response arrives 1.2 s after
    // the write — just beyond the USB 1 s default, but well within BLE's 3 s.
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((conn, call, bytes) {
      if (call == 1) {
        Future.delayed(
            const Duration(milliseconds: 1200), () => conn.notify(identityRx));
      }
    });
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection)); // uses 3s BLE default

    await transport.discover();
    final result = await transport.open();

    expect(result.success, isTrue);
    expect(transport.handshakeComplete, isTrue);
    expect(transport.detectedProfile, Icp5FrameCodec.expectedProfile);
    await transport.close();
  });

  test(
      'P1 regression: handshake succeeds when write() itself (BLE ATT Write '
      'Response) is slow, not just the response after it -- readTimeout must '
      'be armed AFTER write() returns, not before', () async {
    // Real BLE write(withoutResponse:false) awaits the ATT Write Response,
    // which the Icp5BluetoothTransport class doc measures at up to ~2.56 s
    // on a first connection (connection-interval negotiation). The bug: an
    // earlier _open() implementation attached `.timeout(readTimeout)` to the
    // handshake completer's future BEFORE calling write(), so the 3 s clock
    // started ticking during the write itself -- on real hardware this could
    // consume most of the budget before the identity response even had a
    // chance to arrive, timing the handshake out despite readTimeout
    // nominally being "3 s". This scenario (2.0 s write latency + 1.5 s
    // response latency = 3.5 s total, exceeding a "clock starts at write
    // start" 3 s budget but well within a "clock starts after write
    // returns" 3 s budget) reproduces that regression: the old code would
    // fail this test, the fixed code passes it.
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((conn, call, bytes) {
      if (call == 1) {
        Future.delayed(
            const Duration(milliseconds: 1500), () => conn.notify(identityRx));
      }
    }, writeDelay: const Duration(milliseconds: 2000));
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection)); // uses 3s BLE default

    await transport.discover();
    final result = await transport.open();

    expect(result.success, isTrue,
        reason: 'readTimeout must not start counting until write() returns');
    expect(transport.handshakeComplete, isTrue);
    expect(transport.detectedProfile, Icp5FrameCodec.expectedProfile);
    await transport.close();
  });

  test('wrong profile in an otherwise well-formed identity frame fails closed',
      () async {
    // Valid envelope/checksum, but the ASCII profile string does not match
    // Icp5FrameCodec.expectedProfile -- parseIdentity() must return null and
    // _open() must not report success or set handshakeComplete/detectedProfile.
    final wrongProfile = List<int>.of(identityRx);
    wrongProfile[8] =
        0x58; // 'X' in place of 'D' -- corrupts the profile string
    final body = wrongProfile.sublist(0, wrongProfile.length - 1);
    wrongProfile[wrongProfile.length - 1] = Icp5FrameCodec.checksum(body);

    late _FakeGattConnection connection;
    connection = _FakeGattConnection((conn, call, bytes) {
      if (call == 1) conn.notify(wrongProfile);
    });
    final transport =
        Icp5BluetoothTransport(driver: _FakeGattDriver(connection));

    await transport.discover();
    final result = await transport.open();

    expect(result.success, isFalse);
    expect(transport.handshakeComplete, isFalse);
    expect(transport.detectedProfile, isNull);
  });

  test('no heartbeat frame is sent before the handshake completes', () async {
    // Heartbeat must only start after open() resolves successfully
    // (Icp5BluetoothTransport.open() calls _startHeartbeat() only when
    // result.success). Hold the identity response indefinitely (never call
    // notify) and confirm zero additional writes happen beyond the single
    // handshake request while _open() is still awaiting it.
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((conn, call, bytes) {
      // Deliberately never respond -- forces a handshake timeout, giving a
      // window to observe writes during the wait.
    });
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(milliseconds: 100),
        writeTimeout: const Duration(milliseconds: 100));

    await transport.discover();
    expect(transport.heartbeatActive, isFalse);
    final result = await transport.open();

    expect(result.success, isFalse);
    expect(transport.heartbeatActive, isFalse,
        reason: 'a failed handshake must never start the heartbeat');
    // Exactly the one handshake identification write -- no heartbeat
    // identity-read frame was queued while the handshake was pending.
    expect(connection.writes.length, 1);
    expect(connection.writes.single, Icp5FrameCodec.identificationRequest);
  });

  test(
      'a late notify on an abandoned prior-generation connection does not '
      'affect or complete the current handshake', () async {
    // First attempt: connection A never responds -> handshake times out and
    // close() runs, tearing down the subscription to A. Second attempt:
    // connection B responds normally and the handshake succeeds. A late
    // notify delivered to the now-abandoned connection A afterwards must not
    // be observable through the transport (no listener remains attached to
    // A's stream) and must not disturb B's already-completed state.
    late _FakeGattConnection connectionA;
    connectionA = _FakeGattConnection((conn, call, bytes) {});
    late _FakeGattConnection connectionB;
    connectionB = _FakeGattConnection((conn, call, bytes) {
      if (call == 1) conn.notify(identityRx);
    });
    final driver = _MultiOpenFakeDriver([connectionA, connectionB]);
    final transport = Icp5BluetoothTransport(
        driver: driver,
        readTimeout: const Duration(milliseconds: 50),
        writeTimeout: const Duration(milliseconds: 50));

    await transport.discover();
    final r1 = await transport.open();
    expect(r1.success, isFalse);
    expect(transport.handshakeComplete, isFalse);

    // Icp5BluetoothTransport.open() deliberately does not rescan
    // (discoverFirst: false, so it never silently substitutes a different
    // peripheral) -- close() (run on the failed attempt) also clears
    // _selectedPort, so a real reconnect re-selects the same already-known
    // device first. This mirrors TransportConnectionPanel._connectBluetooth,
    // which remembers and re-applies the selection after a failed attempt.
    expect(transport.selectEnumeratedPort('ble-device'), isTrue);
    final r2 = await transport.open();
    expect(r2.success, isTrue);
    expect(transport.handshakeComplete, isTrue);
    expect(transport.detectedProfile, Icp5FrameCodec.expectedProfile);

    // A stale frame delivered to the abandoned first connection -- must not
    // throw and must not alter the now-connected transport's state.
    connectionA.notify(identityRx);
    await Future<void>.delayed(Duration.zero);

    expect(transport.handshakeComplete, isTrue);
    expect(transport.detectedProfile, Icp5FrameCodec.expectedProfile);
    await transport.close();
  });

  test(
      'explicit USB-like 1s read timeout fails when response arrives after '
      '1.2 s (confirms 3s BLE default is necessary)', () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((conn, call, bytes) {
      if (call == 1) {
        Future.delayed(
            const Duration(milliseconds: 1200), () => conn.notify(identityRx));
      }
    });
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(seconds: 1)); // USB-like override

    await transport.discover();
    final result = await transport.open();

    expect(result.success, isFalse);
    expect(transport.handshakeComplete, isFalse);
  });

  test('BLE GATT UUIDs are capture locked', () {
    expect(Icp5BluetoothGattDriver.serviceUuid, 'fff0');
    expect(Icp5BluetoothGattDriver.txCharacteristicUuid, 'fff2');
    expect(Icp5BluetoothGattDriver.rxCharacteristicUuid, 'fff1');
  });

  test('BLE scan source does not claim FFF0 advertisement filtering', () {
    const source = Icp5BluetoothGattDriver.discoverySource;
    expect(source, isNot(contains('advertised service FFF0')));
    expect(source, contains('verified after connect'));
  });

  test('short and Bluetooth Base FFF0 UUIDs match exactly', () {
    expect(
        Icp5BluetoothGattDriver.isExpectedUuid(Guid('fff0'), 'fff0'), isTrue);
    expect(
        Icp5BluetoothGattDriver.isExpectedUuid(
            Guid('0000fff0-0000-1000-8000-00805f9b34fb'), 'fff0'),
        isTrue);
    expect(
        Icp5BluetoothGattDriver.isExpectedUuid(Guid('fff1'), 'fff0'), isFalse);
    expect(
        Icp5BluetoothGattDriver.isExpectedUuid(
            Guid('1234fff0-1111-2222-3333-444455556666'), 'fff0'),
        isFalse);
  });

  test('selected and connecting identifiers must match exactly', () {
    expect(
        Icp5BluetoothGattDriver.identifiersMatch('ABC-123', 'ABC-123'), isTrue);
    expect(Icp5BluetoothGattDriver.identifiersMatch('ABC-123', 'DEF-456'),
        isFalse);
    expect(Icp5BluetoothGattDriver.identifiersMatch('ABC-123', 'abc-123'),
        isFalse);
  });

  test('BLE open preserves selection and does not rescan', () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) connection.notify(identityRx);
    });
    final driver = _FakeGattDriver(connection);
    final transport = Icp5BluetoothTransport(
        driver: driver, readTimeout: const Duration(milliseconds: 50));

    await transport.discover();
    expect(transport.selectEnumeratedPort('ble-selected'), isTrue);
    final result = await transport.open();

    expect(result.success, isTrue);
    expect(driver.discoverCalls, 1);
    expect(driver.openedPort, 'ble-selected');
    await transport.close();
  });

  test('missing exact BLE selection fails closed without substitute', () async {
    final driver = _FakeGattDriver(_FakeGattConnection((_, __, ___) {}));
    final transport = Icp5BluetoothTransport(driver: driver);

    final result = await transport.open();

    expect(result.success, isFalse);
    expect(driver.discoverCalls, 0);
    expect(driver.openedPort, isNull);
  });

  test('BLE uses unchanged handshake codec and reassembles Notify chunks',
      () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) {
        connection.notify(identityRx.sublist(0, 6));
        connection.notify(identityRx.sublist(6));
      }
    });
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(milliseconds: 50));

    await transport.discover();
    final result = await transport.open();

    expect(result.success, isTrue);
    expect(transport.identity, DspTransportIdentity.icp5Bluetooth);
    expect(transport.handshakeComplete, isTrue);
    expect(transport.detectedProfile, Icp5FrameCodec.expectedProfile);
    expect(connection.writes.single, Icp5FrameCodec.identificationRequest);
    await transport.close();
  });

  test('BLE diagnostics reuse ACK-gated transaction logic unchanged', () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) connection.notify(identityRx);
      if (call == 2) connection.notify(volumeAck);
    });
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(milliseconds: 50));
    await transport.discover();
    await transport.open();

    final result = await transport.writeCapturedMasterVolume(5.9);

    expect(result.success, isTrue);
    expect(result.message, 'PASS_ACK');
    expect(connection.writes[1], Icp5FrameCodec.buildMasterVolumeWrite(5.9));
    await transport.close();
  });

  test('all approved diagnostics use exact frames through BLE only', () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) {
        connection.notify(identityRx);
      } else {
        final ack = <int>[0x55, 0x07, 0xE1, 0, 0, 0, bytes[6], 0];
        ack.add(Icp5FrameCodec.checksum(ack));
        connection.notify(ack);
      }
    });
    final driver = _FakeGattDriver(connection);
    final transport = Icp5BluetoothTransport(
        driver: driver, readTimeout: const Duration(milliseconds: 50));
    await transport.discover();
    expect((await transport.open()).success, isTrue);

    expect((await transport.writeCapturedMasterVolume(5.9)).success, isTrue);
    expect((await transport.writeCapturedMasterVolume(6.0)).success, isTrue);
    expect((await transport.writeCapturedMasterMuteState(1)).success, isTrue);
    expect((await transport.writeCapturedMasterMuteState(0)).success, isTrue);
    for (var channel = 0; channel < 4; channel++) {
      expect((await transport.runOutputGainTest(channel)).test.success, isTrue);
      expect((await transport.restoreOutputGain(channel)).success, isTrue);
      expect(
          (await transport.runFilterCutoffTest(channel)).test.success, isTrue);
      expect((await transport.restoreFilterCutoff(channel)).success, isTrue);
      expect(
          (await transport.runPeqBand1GainTest(channel)).test.success, isTrue);
      expect((await transport.restorePeqBand1Gain(channel)).success, isTrue);
    }

    final expected = <List<int>>[
      Icp5FrameCodec.identificationRequest,
      Icp5FrameCodec.buildMasterVolumeWrite(5.9),
      Icp5FrameCodec.buildMasterVolumeWrite(6.0),
      Icp5FrameCodec.buildMasterMuteWrite(1),
      Icp5FrameCodec.buildMasterMuteWrite(0),
      for (var channel = 0; channel < 4; channel++) ...[
        Icp5FrameCodec.buildOutputGainWrite(
            channel,
            switch (channel) {
              0 => -4.9,
              1 => -4.8,
              _ => -0.16666946,
            }),
        Icp5FrameCodec.buildOutputGainWrite(
            channel,
            switch (channel) {
              0 => -4.8,
              1 => -4.7,
              _ => -0.06666946,
            }),
        Icp5FrameCodec.buildFilterCutoffWrite(channel, channel < 2 ? 2001 : 21),
        Icp5FrameCodec.buildFilterCutoffWrite(channel, channel < 2 ? 2000 : 20),
        Icp5FrameCodec.buildPeqBand1GainWrite(
            channel,
            switch (channel) {
              0 => -0.9,
              1 => 4.2,
              2 => -1.0,
              _ => 2.1,
            }),
        Icp5FrameCodec.buildPeqBand1GainWrite(
            channel,
            switch (channel) {
              0 => -1.0,
              1 => 4.1,
              2 => -2.0,
              _ => 2.0,
            }),
      ],
    ];
    expect(connection.writes, expected);
    expect(driver.openedPort, 'ble-device');
    expect(driver.discoverCalls, 1);
    await transport.close();
  });

  test('BLE Notify disconnect during write fails the write immediately',
      () async {
    // With the peripheral-disconnect cleanup fix, _onConnectionError completes
    // _pendingResponse immediately with a StateError rather than leaving it to
    // time out.  The write fails fast with a disconnect message.
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) connection.notify(identityRx);
      if (call == 2) connection.disconnectNotify();
    });
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(milliseconds: 10));
    await transport.discover();
    await transport.open();

    final result = await transport.writeCapturedMasterVolume(5.9);

    expect(result.success, isFalse);
    expect(result.writeMayHaveReachedDevice, isTrue);
    expect(result.message,
        anyOf(contains('timeout'), contains('ACK'), contains('disconnected')));
    await transport.close();
  });

  test('BLE reuses guarded restore and shared STOP after ACK timeouts',
      () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) connection.notify(identityRx);
    });
    final warnings = <String>[];
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(milliseconds: 10),
        onDspWriteStop: warnings.add);
    await transport.discover();
    await transport.open();

    final outcome = await transport.runTestWithGuardedRestore();

    expect(outcome.test.success, isFalse);
    expect(outcome.restore?.success, isFalse);
    expect(outcome.stopActivated, isTrue);
    expect(transport.stopped, isTrue);
    expect(connection.writes[1], Icp5FrameCodec.buildMasterVolumeWrite(5.9));
    expect(connection.writes[2], Icp5FrameCodec.buildMasterVolumeWrite(6.0));
    expect(warnings.single, contains('shared DSP STOP'));
    await transport.close();
  });

  // ── BLE heartbeat ────────────────────────────────────────────────────────
  //
  // WONDOM ICP5 firmware drops the BLE link after ~6 s idle. The heartbeat
  // re-reads the identity block every 3 s to reset the firmware's idle timer.
  // Tests confirm lifecycle coupling (start/stop) and busy-skip without
  // touching Icp5UsbTransport or the handshake protocol.

  group('BLE heartbeat', () {
    test('heartbeat timer is active after successful handshake', () async {
      late _FakeGattConnection connection;
      connection = _FakeGattConnection((conn, call, _) {
        if (call == 1) conn.notify(identityRx);
      });
      final transport = Icp5BluetoothTransport(
          driver: _FakeGattDriver(connection),
          readTimeout: const Duration(milliseconds: 50));
      await transport.discover();
      await transport.open();

      expect(transport.heartbeatActive, isTrue,
          reason: 'timer must be armed after HANDSHAKE_PASS');

      await transport.close();
    });

    test('heartbeat timer is cancelled after close()', () async {
      late _FakeGattConnection connection;
      connection = _FakeGattConnection((conn, call, _) {
        if (call == 1) conn.notify(identityRx);
      });
      final transport = Icp5BluetoothTransport(
          driver: _FakeGattDriver(connection),
          readTimeout: const Duration(milliseconds: 50));
      await transport.discover();
      await transport.open();
      expect(transport.heartbeatActive, isTrue);

      await transport.close();

      expect(transport.heartbeatActive, isFalse,
          reason: 'close() must cancel the heartbeat timer');
    });

    test('heartbeat timer is cancelled after peripheral-initiated disconnect',
        () async {
      late _FakeGattConnection connection;
      connection = _FakeGattConnection((conn, call, _) {
        if (call == 1) conn.notify(identityRx);
      });
      final transport = Icp5BluetoothTransport(
          driver: _FakeGattDriver(connection),
          readTimeout: const Duration(milliseconds: 50));
      await transport.discover();
      await transport.open();
      expect(transport.heartbeatActive, isTrue);

      connection.disconnectNotify();
      await Future<void>.delayed(Duration.zero);

      expect(transport.heartbeatActive, isFalse,
          reason: '_onConnectionError must cancel the heartbeat timer');
    });

    test('heartbeat sends identity read frame when not busy', () async {
      late _FakeGattConnection connection;
      connection = _FakeGattConnection((conn, call, _) {
        // Respond to every write with identityRx (handshake + heartbeat).
        conn.notify(identityRx);
      });
      final transport = Icp5BluetoothTransport(
          driver: _FakeGattDriver(connection),
          readTimeout: const Duration(milliseconds: 50));
      await transport.discover();
      await transport.open();
      final writesAfterOpen = connection.writes.length; // = 1 (handshake)

      await transport.triggerHeartbeatForTest();

      expect(connection.writes.length, equals(writesAfterOpen + 1),
          reason: 'heartbeat must send exactly one frame');
      expect(connection.writes.last, Icp5FrameCodec.identificationRequest,
          reason: 'heartbeat frame must be the identity read');
      await transport.close();
    });

    test('heartbeat skips without sending when a command is in progress',
        () async {
      late _FakeGattConnection connection;
      // Only respond to the handshake (call 1); leave call 2 (volume write)
      // unanswered so _busy stays true while the heartbeat is triggered.
      connection = _FakeGattConnection((conn, call, _) {
        if (call == 1) conn.notify(identityRx);
      });
      final transport = Icp5BluetoothTransport(
          driver: _FakeGattDriver(connection),
          readTimeout: const Duration(milliseconds: 100));
      await transport.discover();
      await transport.open();

      // Start a write that will not receive an ACK — keeps _busy = true.
      final writeFuture = transport.writeCapturedMasterVolume(5.9);
      // Yield once so _exchange() advances to its await inside the write.
      await Future<void>.delayed(Duration.zero);

      final writeCountBeforeHeartbeat = connection.writes.length;
      await transport.triggerHeartbeatForTest();

      expect(connection.writes.length, equals(writeCountBeforeHeartbeat),
          reason: 'heartbeat must skip (HEARTBEAT_SKIP_BUSY) while _busy');

      // Let the pending write time out so the test can exit cleanly.
      await writeFuture;
      await transport.close();
    });

    test('Icp5UsbTransport is unaffected — heartbeat is BLE-only', () {
      // heartbeatActive is not a member of Icp5UsbTransport; it exists only on
      // Icp5BluetoothTransport. Confirm the class boundary is intact.
      final ble = Icp5BluetoothTransport();
      expect(ble, isA<Icp5BluetoothTransport>());
      expect(ble.heartbeatActive, isFalse,
          reason: 'timer not yet started (no open() call)');

      final usb = Icp5UsbTransport(
          driver: _FakeGattDriver(_FakeGattConnection((_, __, ___) {})));
      expect(usb, isNot(isA<Icp5BluetoothTransport>()),
          reason: 'Icp5UsbTransport must not carry heartbeat behaviour');
    });
  });

  // ── Peripheral-initiated disconnect cleanup ───────────────────────────────
  //
  // Verifies that _onConnectionError performs the same state reset as close()
  // so that a peripheral-dropped link does not leave stale references that
  // block the next open() call.

  group('peripheral-initiated disconnect cleanup', () {
    test(
        'all transport state is reset after peripheral disconnect '
        '(post-handshake idle)', () async {
      late _FakeGattConnection connection;
      connection = _FakeGattConnection((conn, call, _) {
        if (call == 1) conn.notify(identityRx);
      });
      final transport = Icp5BluetoothTransport(
          driver: _FakeGattDriver(connection),
          readTimeout: const Duration(milliseconds: 50));
      await transport.discover();
      await transport.open();
      expect(transport.handshakeComplete, isTrue);
      expect(transport.connectionState, DspConnectionState.connected);

      // Simulate the peripheral dropping the BLE link (idle timeout, firmware
      // reset, out-of-range, etc.) with no command in flight.
      connection.disconnectNotify();
      await Future<void>.delayed(Duration.zero);

      expect(transport.handshakeComplete, isFalse,
          reason: '_handshakeComplete must be cleared');
      expect(transport.isConnected, isFalse,
          reason: 'isConnected must be false after peripheral disconnect');
      expect(transport.connectionState, DspConnectionState.disconnected,
          reason: 'state must be disconnected, not error');
      expect(transport.selectedPort, isNull,
          reason: '_selectedPort must be cleared (mirrors close())');
      expect(transport.detectedProfile, isNull,
          reason: '_profile must be cleared');
    });

    test('reconnect succeeds after peripheral-initiated disconnect', () async {
      final conn1 = _FakeGattConnection((conn, call, _) {
        if (call == 1) conn.notify(identityRx);
      });
      final conn2 = _FakeGattConnection((conn, call, _) {
        if (call == 1) conn.notify(identityRx);
      });
      final transport = Icp5BluetoothTransport(
          driver: _MultiOpenFakeDriver([conn1, conn2]),
          readTimeout: const Duration(milliseconds: 50));

      await transport.discover();
      await transport.open();
      expect(transport.handshakeComplete, isTrue);

      conn1.disconnectNotify();
      await Future<void>.delayed(Duration.zero);
      expect(transport.connectionState, DspConnectionState.disconnected);

      // Re-arm selectedPort (UI would call discover() before reconnect).
      await transport.discover();
      final result = await transport.open();

      expect(result.success, isTrue,
          reason: 'second open() must succeed after peripheral disconnect');
      expect(transport.handshakeComplete, isTrue);
      await transport.close();
    });

    test(
        'open() is not blocked by stale _connection after peripheral disconnect',
        () async {
      late _FakeGattConnection connection;
      connection = _FakeGattConnection((conn, call, _) {
        if (call == 1) conn.notify(identityRx);
      });
      final transport = Icp5BluetoothTransport(
          driver: _FakeGattDriver(connection),
          readTimeout: const Duration(milliseconds: 50));
      await transport.discover();
      await transport.open();

      connection.disconnectNotify();
      await Future<void>.delayed(Duration.zero);

      // Re-arm port, then try to open again.
      await transport.discover();
      final result = await transport.open();

      // The fake driver reuses the same closed connection so the result may not
      // be success, but the failure must NOT be the stale-lock "unavailable"
      // error that would have occurred without the cleanup fix.
      expect(result.failure, isNot(DspTransportFailure.unavailable),
          reason: '"already exclusively owned" must not occur after cleanup');
      expect(result.message, isNot(contains('already exclusively owned')));
    });
  });
}
