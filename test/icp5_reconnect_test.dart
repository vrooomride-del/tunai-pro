import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// A serial connection whose byte stream never emits an identity frame, so the
// ICP5 handshake always times out. Tracks listener/close counts to catch
// duplicate listeners or missing/duplicate disposal on reconnect.
class _SilentConnection implements Icp5SerialConnection {
  final StreamController<List<int>> _controller =
      StreamController<List<int>>();
  int listenCount = 0;
  int closeCount = 0;

  @override
  Stream<List<int>> get bytes {
    _controller.onListen = () => listenCount++;
    return _controller.stream;
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async => bytes.length;

  @override
  Future<void> close() async {
    closeCount++;
    if (!_controller.isClosed) await _controller.close();
  }
}

class _FakeDriver implements Icp5SerialDriver {
  final List<_SilentConnection> opened = [];
  int discoverCount = 0;
  int openCount = 0;

  static const _device = Icp5SerialDevice(
    portName: '/dev/cu.fakeicp5',
    vendorId: 0x1A86,
    productId: 0x55D6,
    enumerationSource: 'fake',
  );

  @override
  bool get platformSupported => true;

  @override
  Future<Icp5DiscoveryResult> discover() async {
    discoverCount++;
    return const Icp5DiscoveryResult(
      source: 'fake',
      allPorts: [_device],
      matches: [_device],
      error: null,
    );
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    openCount++;
    final conn = _SilentConnection();
    opened.add(conn);
    return conn;
  }
}

void main() {
  test('open → handshake timeout → close → open again does not crash and '
      'fails cleanly each time', () async {
    final driver = _FakeDriver();
    final transport = Icp5UsbTransport(
      driver: driver,
      readTimeout: const Duration(milliseconds: 40),
      writeTimeout: const Duration(milliseconds: 40),
    );

    // First attempt → handshake times out.
    final r1 = await transport.open();
    expect(r1.success, isFalse);
    expect(r1.message.toLowerCase(), contains('timed out'));
    expect(transport.isConnected, isFalse);
    expect(transport.handshakeComplete, isFalse);

    // The first connection was opened and cleanly closed exactly once.
    expect(driver.opened, hasLength(1));
    expect(driver.opened[0].closeCount, 1);
    expect(driver.opened[0].listenCount, 1); // no duplicate listeners

    // Second attempt → a fresh connection, times out again, no crash.
    final r2 = await transport.open();
    expect(r2.success, isFalse);
    expect(r2.message.toLowerCase(), contains('timed out'));

    // A brand-new connection was created (not the stale one reused).
    expect(driver.opened, hasLength(2));
    expect(driver.openCount, 2);
    expect(driver.discoverCount, 2);
    expect(driver.opened[1].closeCount, 1);
    expect(driver.opened[1].listenCount, 1);

    // Both connections ended disposed; transport is back to a clean state.
    expect(transport.isConnected, isFalse);

    // A third cycle still works and fails closed.
    final r3 = await transport.open();
    expect(r3.success, isFalse);
    expect(driver.opened, hasLength(3));

    await transport.close();
  });
}
