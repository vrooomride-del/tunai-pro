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
  bool hangScan;

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
    this.hangScan = false,
  });

  @override
  Future<bool> isAdapterOn() async => adapterOn;

  @override
  Future<List<WinBleDevice>> scan(Duration timeout) {
    if (hangScan) return Completer<List<WinBleDevice>>().future; // never completes
    return Future.value(devices);
  }

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
    test('lists all devices sorted by RSSI; ICP5 is the auto-selected match',
        () async {
      final backend = _FakeBackend(devices: const [
        WinBleDevice(id: 'AA', name: 'Wondom ICP5', rssi: -70),
        WinBleDevice(id: 'BB', name: 'Other', rssi: -40),
        WinBleDevice(id: 'CC', name: 'NonConn', connectable: false),
      ]);
      final result = await _driver(backend).discover();
      // All devices shown, strongest RSSI first (null RSSI last).
      expect(result.allPorts.map((d) => d.portName), ['BB', 'AA', 'CC']);
      // Only the single WONDOM/ICP5 device is auto-selected.
      expect(result.matches.map((d) => d.portName), ['AA']);
      expect(result.error, isNull);
      expect(result.source, contains('Windows'));
    });

    test('adapter off → fail closed', () async {
      final result = await _driver(_FakeBackend(adapterOn: false)).discover();
      expect(result.matches, isEmpty);
      expect(result.error, contains('adapter is not on'));
    });

    test('a non-connectable non-ICP5 device is still listed, none auto-selected',
        () async {
      final result = await _driver(_FakeBackend(devices: const [
        WinBleDevice(id: 'CC', connectable: false),
      ])).discover();
      expect(result.allPorts, hasLength(1)); // listed (connectable is advisory)
      expect(result.matches, isEmpty); // not ICP5 → no auto-select
      expect(result.error, isNull);
    });

    test('a hung native scan still completes with a timeout error (UI recovers)',
        () async {
      final driver = WindowsIcp5BluetoothDriver(
        backend: _FakeBackend(hangScan: true),
        isWindowsOverride: () => true,
        scanTimeout: const Duration(milliseconds: 20),
      );
      // Must resolve well within the 2 s guard margin — never hang forever.
      final result = await driver.discover().timeout(
          const Duration(seconds: 4),
          onTimeout: () =>
              throw StateError('discover() did not complete — UI would stick'));
      expect(result.matches, isEmpty);
      expect(result.error, contains('timed out'));
    });

    test('empty scan yields a clear no-devices message, not a hang', () async {
      final result = await _driver(_FakeBackend(devices: const [])).discover();
      expect(result.matches, isEmpty);
      expect(result.error, contains('No BLE devices found'));
    });
  });

  group('scan result → selection', () {
    test('all scanned devices are listed even if connectable=false', () async {
      final result = await _driver(_FakeBackend(devices: const [
        WinBleDevice(id: 'AA', name: 'WONDOM ICP5', rssi: -60),
        WinBleDevice(id: 'BB', name: 'Random', rssi: -50, connectable: false),
      ])).discover();
      // Both appear in the selector (allPorts), not filtered on connectable.
      expect(result.allPorts.map((d) => d.portName), containsAll(['AA', 'BB']));
    });

    test('exactly one WONDOM match is auto-selected', () async {
      final result = await _driver(_FakeBackend(devices: const [
        WinBleDevice(id: 'AA', name: 'WONDOM ICP5', rssi: -60),
        WinBleDevice(id: 'BB', name: 'Some Speaker', rssi: -40),
      ])).discover();
      expect(result.matches, hasLength(1));
      expect(result.matches.single.portName, 'AA');
      expect(result.matches.single.friendlyName, 'WONDOM ICP5');
    });

    test('multiple ICP5 matches → no auto-select (manual required)', () async {
      final result = await _driver(_FakeBackend(devices: const [
        WinBleDevice(id: 'AA', name: 'WONDOM ICP5'),
        WinBleDevice(id: 'BB', name: 'ICP5 spare'),
      ])).discover();
      expect(result.allPorts, hasLength(2));
      expect(result.matches, isEmpty); // ambiguous → do not auto-select
    });

    test('no ICP5 match → devices listed but none auto-selected', () async {
      final result = await _driver(_FakeBackend(devices: const [
        WinBleDevice(id: 'AA', name: 'Mouse'),
        WinBleDevice(id: 'BB', name: 'Keyboard'),
      ])).discover();
      expect(result.allPorts, hasLength(2));
      expect(result.matches, isEmpty);
    });

    test('display name priority uses advertised name when not ICP5', () async {
      final result = await _driver(_FakeBackend(devices: const [
        WinBleDevice(id: 'AA', name: '', advertisedName: 'JAB4-BLE'),
      ])).discover();
      expect(result.allPorts.single.friendlyName, 'JAB4-BLE');
    });
  });

  group('connect guard', () {
    test('open() with empty deviceId fails closed (no native connect)',
        () async {
      final backend = _FakeBackend();
      await expectLater(
          _driver(backend).open(''), throwsA(isA<StateError>()));
      await expectLater(
          _driver(backend).open('   '), throwsA(isA<StateError>()));
      expect(backend.connects, 0);
    });
  });

  group('retry after service-discovery failure', () {
    test('FFF0-missing connect fails, selection re-selectable for retry',
        () async {
      final backend = _FakeBackend(
        devices: const [WinBleDevice(id: 'AA', name: 'WONDOM ICP5')],
        // Connected but no FFF0 service → open() throws "FFF0 not found".
        profileFor: (id) => const WinBleGattProfile(
            deviceId: 'AA', serviceUuids: ['1800'], characteristics: []),
      );
      final driver = WindowsIcp5BluetoothDriver(
        backend: backend,
        isWindowsOverride: () => true,
        scanTimeout: const Duration(milliseconds: 20),
        connectTimeout: const Duration(milliseconds: 20),
      );
      final transport = Icp5BluetoothTransport(
        driver: driver,
        readTimeout: const Duration(milliseconds: 40),
        writeTimeout: const Duration(milliseconds: 40),
      );

      await transport.discover();
      expect(transport.selectedPort, 'AA'); // single WONDOM auto-selected

      final r = await transport.open();
      expect(r.success, isFalse); // FFF0 missing → connect fails, no crash
      expect(transport.selectedPort, isNull); // close() cleared it

      // The device is still enumerated, so a retry selection re-arms Connect.
      expect(transport.selectEnumeratedPort('AA'), isTrue);
      expect(transport.selectedPort, 'AA');
      await transport.close();
    });
  });

  group('parser schema', () {
    test('WinBleDevice accepts deviceId+advertisedName and legacy id+name', () {
      // deviceId/advertisedName schema
      const a = WinBleDevice(
          id: 'X', name: 'WONDOM ICP5', advertisedName: 'WONDOM ICP5', rssi: -50);
      expect(a.id, 'X');
      expect(a.advertisedName, 'WONDOM ICP5');
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
