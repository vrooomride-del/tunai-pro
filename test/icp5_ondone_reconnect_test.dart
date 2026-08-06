// P1 fix regression guard: _onConnectionClosed (the stream's onDone
// callback) must perform the same full state reset as _onConnectionError,
// so a link drop that surfaces as a clean remote close (rather than an
// error) does not leave the transport stuck reporting isConnected=true with
// no way to reopen short of an app restart.
//
// Covers the shared Icp5UsbTransport lifecycle (USB serial, exercised
// identically on macOS/Windows via driver injection) and the
// Icp5BluetoothTransport override (heartbeat teardown on onDone, mirroring
// the existing onError override).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// A successful-identity-frame byte sequence (DSP1701.100.00.01), identical to
// the one used in consumer_ble_service_test.dart / other transport tests.
const _identity = <int>[
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

/// A connection whose RX stream can be driven manually: the first write
/// (the identification request) triggers a successful identity response, and
/// the test can later trigger a clean remote close (onDone) or a stream
/// error (onError) at will.
class _ControllableConnection implements Icp5SerialConnection {
  final StreamController<List<int>> _rx = StreamController<List<int>>();
  int listenCount = 0;
  int closeCount = 0;
  int writeCount = 0;

  @override
  Stream<List<int>> get bytes {
    _rx.onListen = () => listenCount++;
    return _rx.stream;
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    writeCount++;
    if (writeCount == 1) {
      // Respond to the identification handshake synchronously, mirroring the
      // real driver's behavior and the existing consumer_ble_service_test.dart
      // fake.
      _rx.add(_identity);
    }
    return bytes.length;
  }

  @override
  Future<void> close() async {
    closeCount++;
    if (!_rx.isClosed) await _rx.close();
  }

  /// Simulates the remote/peripheral cleanly closing the link -- the
  /// stream's onDone callback fires, no onError.
  Future<void> emitRemoteDone() async {
    if (!_rx.isClosed) await _rx.close();
  }

  /// Simulates the remote/peripheral dropping the link with an error --
  /// the stream's onError callback fires.
  void emitRemoteError(Object error) {
    if (!_rx.isClosed) _rx.addError(error);
  }
}

class _FakeDriver implements Icp5SerialDriver {
  final List<_ControllableConnection> opened = [];
  int discoverCount = 0;

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
    );
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    final c = _ControllableConnection();
    opened.add(c);
    return c;
  }
}

Icp5UsbTransport _usbTransport(_FakeDriver driver) => Icp5UsbTransport(
      driver: driver,
      readTimeout: const Duration(milliseconds: 200),
      writeTimeout: const Duration(milliseconds: 200),
    );

void main() {
  group('Icp5UsbTransport onDone (shared USB/macOS/Windows lifecycle)', () {
    test(
        'handshake succeeds, then remote onDone -> full state reset '
        '(isConnected=false, handshakeComplete=false)', () async {
      final driver = _FakeDriver();
      final transport = _usbTransport(driver);

      final r1 = await transport.open();
      expect(r1.success, isTrue);
      expect(transport.isConnected, isTrue);
      expect(transport.handshakeComplete, isTrue);

      await driver.opened.single.emitRemoteDone();
      // Let the onDone callback (and its microtasks) run.
      await Future<void>.delayed(Duration.zero);

      expect(transport.isConnected, isFalse,
          reason: 'onDone must reset _state, not leave it stuck connected');
      expect(transport.handshakeComplete, isFalse);
    });

    test('reopen on the same transport instance succeeds after onDone',
        () async {
      final driver = _FakeDriver();
      final transport = _usbTransport(driver);

      await transport.open();
      await driver.opened.single.emitRemoteDone();
      await Future<void>.delayed(Duration.zero);

      final r2 = await transport.open();
      expect(r2.success, isTrue,
          reason:
              'A stale "already exclusively owned" guard must not block reopen');
      expect(transport.isConnected, isTrue);
      expect(driver.opened, hasLength(2),
          reason: 'a fresh connection was opened');

      await transport.close();
    });

    test(
        'user close() racing a remote onDone for the same drop does not '
        'double-close the underlying connection', () async {
      final driver = _FakeDriver();
      final transport = _usbTransport(driver);
      await transport.open();
      final conn = driver.opened.single;

      // Remote closes first (fires onDone -> full reset, including
      // conn.close().ignore()); the app-level close() call arrives after.
      await conn.emitRemoteDone();
      await Future<void>.delayed(Duration.zero);
      await transport.close();

      expect(conn.closeCount, 1,
          reason: 'the underlying connection must be closed exactly once '
              'even if onDone and an explicit close() both run for it');
    });

    test(
        'a successful handshake then onError performs the same full reset '
        '(symmetry with onDone)', () async {
      final driver = _FakeDriver();
      final transport = _usbTransport(driver);

      await transport.open();
      driver.opened.single.emitRemoteError(StateError('link dropped'));
      await Future<void>.delayed(Duration.zero);

      expect(transport.isConnected, isFalse);
      expect(transport.handshakeComplete, isFalse);

      final r2 = await transport.open();
      expect(r2.success, isTrue);
    });
  });

  group('Icp5BluetoothTransport onDone heartbeat teardown', () {
    test('heartbeat stops on remote onDone, mirroring the onError override',
        () async {
      final driver = _FakeDriver();
      final transport = Icp5BluetoothTransport(
        driver: driver,
        readTimeout: const Duration(milliseconds: 200),
        writeTimeout: const Duration(milliseconds: 200),
        heartbeatInterval: const Duration(milliseconds: 500),
      );

      await transport.discover();
      final r = await transport.open();
      expect(r.success, isTrue);
      expect(transport.heartbeatActive, isTrue);

      await driver.opened.single.emitRemoteDone();
      await Future<void>.delayed(Duration.zero);

      expect(transport.heartbeatActive, isFalse,
          reason: 'onDone must stop the heartbeat timer just like onError, '
              'or a periodic timer leaks against a dead connection');
      expect(transport.isConnected, isFalse);
    });
  });
}
