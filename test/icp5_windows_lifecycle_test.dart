import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// Connection whose RX stream never emits an identity frame (handshake times
// out). Counts close() calls to prove idempotency / single teardown — the
// Windows-crash-relevant contract.
class _CountingConnection implements Icp5SerialConnection {
  final StreamController<List<int>> _rx = StreamController<List<int>>();
  int listenCount = 0;
  int closeCount = 0;

  @override
  Stream<List<int>> get bytes {
    _rx.onListen = () => listenCount++;
    return _rx.stream;
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async => bytes.length;

  @override
  Future<void> close() async {
    closeCount++;
    if (!_rx.isClosed) await _rx.close();
  }
}

class _FakeWinDriver implements Icp5SerialDriver {
  final List<_CountingConnection> opened = [];
  int discoverCount = 0;

  static const _device = Icp5SerialDevice(
    portName: 'COM3',
    vendorId: 0x1A86,
    productId: 0x55D6,
    enumerationSource: 'fake-win',
  );

  @override
  bool get platformSupported => true;

  @override
  Future<Icp5DiscoveryResult> discover() async {
    discoverCount++;
    return const Icp5DiscoveryResult(
        source: 'fake-win', allPorts: [_device], matches: [_device]);
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    final c = _CountingConnection();
    opened.add(c);
    return c;
  }
}

Icp5UsbTransport _transport(_FakeWinDriver driver) => Icp5UsbTransport(
      driver: driver,
      readTimeout: const Duration(milliseconds: 40),
      writeTimeout: const Duration(milliseconds: 40),
    );

void main() {
  test('handshake timeout closes the connection exactly once (no double close)',
      () async {
    final driver = _FakeWinDriver();
    final transport = _transport(driver);

    final r = await transport.open();
    expect(r.success, isFalse);
    expect(r.message.toLowerCase(), contains('timed out'));
    expect(driver.opened, hasLength(1));
    expect(driver.opened[0].closeCount, 1);
    expect(driver.opened[0].listenCount, 1); // single reader listener

    // A redundant close (e.g. panel dispose after a timeout-close) is safe and
    // does not re-close the already-released connection.
    await transport.close();
    expect(driver.opened[0].closeCount, 1);
  });

  test('three timeout/reconnect cycles remain stable', () async {
    final driver = _FakeWinDriver();
    final transport = _transport(driver);

    for (var i = 0; i < 3; i++) {
      final r = await transport.open();
      expect(r.success, isFalse);
    }

    expect(driver.opened, hasLength(3)); // fresh connection each cycle
    expect(driver.discoverCount, 3);
    for (final c in driver.opened) {
      expect(c.closeCount, 1); // each closed exactly once
      expect(c.listenCount, 1);
    }
    await transport.close();
  });

  test('reopen after a clean close succeeds', () async {
    final driver = _FakeWinDriver();
    final transport = _transport(driver);

    await transport.open(); // times out, closes
    await transport.close(); // idempotent
    final r2 = await transport.open(); // reopen works
    expect(r2.success, isFalse); // still times out (fake), but no crash/leak
    expect(driver.opened, hasLength(2));
  });
}
