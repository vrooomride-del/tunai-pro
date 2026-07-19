import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// Counts lifecycle events so we can assert exactly-once disposal and no
// duplicate listeners across reconnect cycles.
class _CountingConn implements Icp5SerialConnection {
  final StreamController<List<int>> _ctrl = StreamController<List<int>>();
  int listens = 0;
  int closes = 0;

  @override
  Stream<List<int>> get bytes {
    _ctrl.onListen = () => listens++;
    return _ctrl.stream; // never emits → ICP5 handshake times out
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async => bytes.length;

  @override
  Future<void> close() async {
    closes++;
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}

const _icp5Device = Icp5SerialDevice(
  portName: '/dev/cu.wchusbserialWCH0642C2TS11',
  vendorId: 0x1A86,
  productId: 0x55D6,
  enumerationSource: 'test',
);

MacIcp5SerialDriver _macDriver({
  bool throwOnOpen = false,
  List<_CountingConn>? sink,
}) =>
    MacIcp5SerialDriver(
      isMacOsOverride: () => true,
      enumeratePorts: () => const [_icp5Device],
      openPort: (portName) async {
        if (throwOnOpen) throw StateError('open denied');
        final conn = _CountingConn();
        sink?.add(conn);
        return conn;
      },
    );

Icp5UsbTransport _transport(MacIcp5SerialDriver driver) => Icp5UsbTransport(
      driver: driver,
      readTimeout: const Duration(milliseconds: 40),
      writeTimeout: const Duration(milliseconds: 40),
    );

void main() {
  test('open failure: driver.open throws and does not leak/return a conn',
      () async {
    final driver = _macDriver(throwOnOpen: true);
    await expectLater(
      driver.open('/dev/cu.x'),
      throwsA(isA<StateError>()),
    );
  });

  test('open failure via transport is reported; close after failed open is safe',
      () async {
    final driver = _macDriver(throwOnOpen: true);
    final transport = _transport(driver);

    final r1 = await transport.open();
    expect(r1.success, isFalse);
    expect(transport.isConnected, isFalse);

    // close() after a failed open must not throw / double-dispose.
    await transport.close();

    // A subsequent attempt still fails cleanly (no stale state).
    final r2 = await transport.open();
    expect(r2.success, isFalse);
  });

  test('handshake timeout closes the connection exactly once', () async {
    final conns = <_CountingConn>[];
    final transport = _transport(_macDriver(sink: conns));

    final r = await transport.open();
    expect(r.success, isFalse);
    expect(r.message.toLowerCase(), contains('timed out'));

    expect(conns, hasLength(1));
    expect(conns[0].closes, 1); // no duplicate dispose
    expect(conns[0].listens, 1); // no duplicate listeners
  });

  test('reconnect 3 cycles: fresh connection each time, disposed exactly once',
      () async {
    final conns = <_CountingConn>[];
    final transport = _transport(_macDriver(sink: conns));

    for (var i = 0; i < 3; i++) {
      final r = await transport.open();
      expect(r.success, isFalse, reason: 'cycle $i should fail (timeout)');
      expect(r.message.toLowerCase(), contains('timed out'));
    }

    expect(conns, hasLength(3)); // a new connection per cycle, no reuse
    for (final c in conns) {
      expect(c.closes, 1); // no duplicate dispose across reconnects
      expect(c.listens, 1); // no duplicate listeners
    }

    await transport.close();
    expect(transport.isConnected, isFalse);
  });
}
