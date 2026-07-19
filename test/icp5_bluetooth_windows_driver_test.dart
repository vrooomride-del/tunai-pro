import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_bluetooth_windows_driver.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// ── Fake BLE backend ──────────────────────────────────────────────────────────

class _FakeBackend implements WindowsBleBackend {
  bool adapterOn;
  List<WinBleDevice> devices;
  WinBleGattProfile Function(String id)? profileFor;
  Object? connectError;

  int connects = 0;
  int disconnects = 0;
  int enableNotifyCount = 0;
  final List<List<int>> writes = [];
  final StreamController<List<int>> notify =
      StreamController<List<int>>.broadcast();

  _FakeBackend({
    this.adapterOn = true,
    this.devices = const [],
    this.profileFor,
    this.connectError,
  });

  @override
  Future<bool> isAdapterOn() async => adapterOn;

  @override
  Future<List<WinBleDevice>> scan(Duration timeout) async => devices;

  @override
  Future<WinBleGattProfile> connect(String deviceId, Duration timeout) async {
    connects++;
    if (connectError != null) throw connectError!;
    return (profileFor ?? _defaultProfile)(deviceId);
  }

  @override
  Future<void> enableNotify(String deviceId, WinBleCharacteristic rx) async {
    enableNotifyCount++;
  }

  @override
  Stream<List<int>> notifyStream(String deviceId, WinBleCharacteristic rx) =>
      notify.stream;

  @override
  Future<int> writeValue(String deviceId, WinBleCharacteristic tx,
      List<int> data, Duration timeout) async {
    writes.add(data);
    return data.length;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnects++;
  }
}

// Full FFF0 / FFF2(write) / FFF1(notify) profile.
WinBleGattProfile _defaultProfile(String id) => WinBleGattProfile(
      deviceId: id,
      serviceUuids: const ['fff0'],
      characteristics: const [
        WinBleCharacteristic(
            serviceUuid: 'fff0', uuid: 'fff2', canWrite: true, canNotify: false),
        WinBleCharacteristic(
            serviceUuid: 'fff0', uuid: 'fff1', canWrite: false, canNotify: true),
      ],
    );

WindowsIcp5BluetoothDriver _driver(_FakeBackend backend) =>
    WindowsIcp5BluetoothDriver(
      backend: backend,
      isWindowsOverride: () => true,
      scanTimeout: const Duration(milliseconds: 20),
      connectTimeout: const Duration(milliseconds: 20),
    );

Icp5UsbTransport _transport(WindowsIcp5BluetoothDriver driver) =>
    Icp5UsbTransport(
      driver: driver,
      readTimeout: const Duration(milliseconds: 40),
      writeTimeout: const Duration(milliseconds: 40),
    );

void main() {
  group('discovery', () {
    test('lists connectable devices, sorted by RSSI', () async {
      final backend = _FakeBackend(devices: const [
        WinBleDevice(id: 'AA', name: 'Wondom ICP5', rssi: -70),
        WinBleDevice(id: 'BB', name: 'Other', rssi: -40),
        WinBleDevice(id: 'CC', name: 'NonConn', connectable: false),
      ]);
      final result = await _driver(backend).discover();
      expect(result.matches.map((d) => d.portName), ['BB', 'AA']); // -40 first
      expect(result.error, isNull);
      expect(result.source, contains('Windows'));
    });

    test('adapter off → fail closed', () async {
      final result = await _driver(_FakeBackend(adapterOn: false)).discover();
      expect(result.matches, isEmpty);
      expect(result.error, contains('adapter is not on'));
    });

    test('no connectable devices → fail closed', () async {
      final result = await _driver(_FakeBackend(devices: const [
        WinBleDevice(id: 'CC', connectable: false),
      ])).discover();
      expect(result.matches, isEmpty);
      expect(result.error, contains('No connectable'));
    });
  });

  group('UUID matching', () {
    test('short and full 128-bit forms match; others do not', () {
      expect(WindowsIcp5BluetoothDriver.uuidMatches('fff0', 'fff0'), isTrue);
      expect(WindowsIcp5BluetoothDriver.uuidMatches('FFF0', 'fff0'), isTrue);
      expect(
          WindowsIcp5BluetoothDriver.uuidMatches(
              '0000fff0-0000-1000-8000-00805f9b34fb', 'fff0'),
          isTrue);
      expect(WindowsIcp5BluetoothDriver.uuidMatches('fff1', 'fff0'), isFalse);
    });
  });

  group('TX/RX characteristic mapping', () {
    test('binds FFF2(write) + FFF1(notify), subscribes, returns a connection',
        () async {
      final backend = _FakeBackend();
      final conn = await _driver(backend).open('AA');
      expect(conn, isA<Icp5SerialConnection>());
      expect(backend.enableNotifyCount, 1);
      // write goes to FFF2
      await conn.write([1, 2, 3], const Duration(milliseconds: 20));
      expect(backend.writes, [[1, 2, 3]]);
      await conn.close();
      expect(backend.disconnects, greaterThanOrEqualTo(1));
    });

    test('missing FFF0 service → fail closed + disconnect', () async {
      final backend = _FakeBackend(
        profileFor: (id) => const WinBleGattProfile(
            deviceId: 'AA', serviceUuids: ['1800'], characteristics: []),
      );
      await expectLater(
          _driver(backend).open('AA'), throwsA(isA<StateError>()));
      expect(backend.disconnects, 1);
    });

    test('missing writable FFF2 → fail closed', () async {
      final backend = _FakeBackend(
        profileFor: (id) => const WinBleGattProfile(
          deviceId: 'AA',
          serviceUuids: ['fff0'],
          characteristics: [
            WinBleCharacteristic(
                serviceUuid: 'fff0', uuid: 'fff1', canWrite: false, canNotify: true),
          ],
        ),
      );
      await expectLater(
          _driver(backend).open('AA'), throwsA(isA<StateError>()));
      expect(backend.disconnects, 1);
    });

    test('missing notifiable FFF1 → fail closed', () async {
      final backend = _FakeBackend(
        profileFor: (id) => const WinBleGattProfile(
          deviceId: 'AA',
          serviceUuids: ['fff0'],
          characteristics: [
            WinBleCharacteristic(
                serviceUuid: 'fff0', uuid: 'fff2', canWrite: true, canNotify: false),
          ],
        ),
      );
      await expectLater(
          _driver(backend).open('AA'), throwsA(isA<StateError>()));
      expect(backend.disconnects, 1);
    });
  });

  group('fail closed platform / connect', () {
    test('non-Windows platform: discovery errors, open throws', () async {
      final driver = WindowsIcp5BluetoothDriver(
        backend: _FakeBackend(),
        isWindowsOverride: () => false,
      );
      expect(driver.platformSupported, isFalse);
      final result = await driver.discover();
      expect(result.error, contains('unavailable on this platform'));
      await expectLater(driver.open('AA'), throwsA(isA<UnsupportedError>()));
    });

    test('backend connect failure surfaces as open error', () async {
      final backend = _FakeBackend(connectError: StateError('connect denied'));
      await expectLater(
          _driver(backend).open('AA'), throwsA(isA<StateError>()));
    });
  });

  group('transport handshake + reconnect (frame codec reused)', () {
    test('handshake times out (notify never emits identity)', () async {
      final backend = _FakeBackend(
          devices: const [WinBleDevice(id: 'AA', name: 'Wondom ICP5')]);
      final transport = _transport(_driver(backend));
      final r = await transport.open();
      expect(r.success, isFalse);
      expect(r.message.toLowerCase(), contains('timed out'));
      expect(backend.connects, 1);
      expect(backend.disconnects, greaterThanOrEqualTo(1)); // cleaned up
    });

    test('reconnect 3 cycles: connects and disconnects each time, no crash',
        () async {
      final backend = _FakeBackend(
          devices: const [WinBleDevice(id: 'AA', name: 'Wondom ICP5')]);
      final transport = _transport(_driver(backend));
      for (var i = 0; i < 3; i++) {
        final r = await transport.open();
        expect(r.success, isFalse);
      }
      expect(backend.connects, 3);
      expect(backend.disconnects, 3);
      await transport.close();
    });
  });
}
