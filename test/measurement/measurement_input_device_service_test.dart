// Phase 3-D1 — MeasurementInputDeviceService: adapter-level tests using a
// fake MeasurementInputDeviceApi (no real platform channel / record plugin
// involved).

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';

class _FakeApi implements MeasurementInputDeviceApi {
  bool permissionGranted = true;
  List<MeasurementInputDeviceDescriptor> devices = const [];
  int listCallCount = 0;

  @override
  Future<bool> hasPermission({bool request = true}) async => permissionGranted;

  @override
  Future<List<MeasurementInputDeviceDescriptor>> listInputDevices() async {
    listCallCount++;
    return devices;
  }
}

void main() {
  group('MeasurementInputDeviceService', () {
    test('hasPermission delegates to the api', () async {
      final api = _FakeApi()..permissionGranted = false;
      final service = MeasurementInputDeviceService(api);
      expect(await service.hasPermission(), isFalse);
    });

    test('permission denied surfaces as-is (enumeration test)', () async {
      final api = _FakeApi()..permissionGranted = true;
      final service = MeasurementInputDeviceService(api);
      expect(await service.hasPermission(), isTrue);
    });

    test('listAvailableDevices returns the api\'s current list', () async {
      final api = _FakeApi()
        ..devices = const [
          MeasurementInputDeviceDescriptor(id: 'dev1', label: 'USB Mic'),
        ];
      final service = MeasurementInputDeviceService(api);
      final devices = await service.listAvailableDevices();
      expect(devices.map((d) => d.id), ['dev1']);
    });

    test('enumeration failure (empty list) is surfaced, not swallowed',
        () async {
      final api = _FakeApi()..devices = const [];
      final service = MeasurementInputDeviceService(api);
      expect(await service.listAvailableDevices(), isEmpty);
    });

    test('resolveForRecording re-enumerates fresh every call (never caches)',
        () async {
      final api = _FakeApi()
        ..devices = const [
          MeasurementInputDeviceDescriptor(id: 'dev1', label: 'USB Mic'),
        ];
      final service = MeasurementInputDeviceService(api);
      final selection = MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev1',
          labelSnapshot: 'USB Mic',
          selectedAt: DateTime.now());

      await service.resolveForRecording(selection);
      await service.resolveForRecording(selection);
      expect(api.listCallCount, 2,
          reason: 'each resolve must re-check availability, not reuse a '
              'cached enumeration');
    });

    test(
        'resolveForRecording throws when the selected device vanished '
        'between selection time and now', () async {
      final api = _FakeApi()..devices = const []; // device no longer present
      final service = MeasurementInputDeviceService(api);
      final selection = MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev1',
          labelSnapshot: 'USB Mic',
          selectedAt: DateTime.now());

      expect(() => service.resolveForRecording(selection),
          throwsA(isA<MeasurementInputDeviceUnavailable>()));
    });

    test(
        'unplug then reconnect: a call while absent throws, a later call '
        'once the SAME device id reappears in enumeration resolves to it '
        'again — no stale caching in either direction', () async {
      final api = _FakeApi()
        ..devices = const [
          MeasurementInputDeviceDescriptor(id: 'umik-1', label: 'UMIK-1'),
        ];
      final service = MeasurementInputDeviceService(api);
      final selection = MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'umik-1', labelSnapshot: 'UMIK-1', selectedAt: DateTime.now());

      // Present: resolves normally.
      final first = await service.resolveForRecording(selection);
      expect(first?.id, 'umik-1');

      // Unplugged: the very next call must fail-closed, not reuse the
      // earlier successful resolution.
      api.devices = const [];
      expect(() => service.resolveForRecording(selection),
          throwsA(isA<MeasurementInputDeviceUnavailable>()));

      // Reconnected: the next call after that must resolve to the exact
      // same device again, proving nothing latched onto a "known bad"
      // state either.
      api.devices = const [
        MeasurementInputDeviceDescriptor(id: 'umik-1', label: 'UMIK-1'),
      ];
      final third = await service.resolveForRecording(selection);
      expect(third?.id, 'umik-1');
    });

    test(
        'resolveForRecording resolves system default to null without '
        'requiring any devices to be present', () async {
      final api = _FakeApi()..devices = const [];
      final service = MeasurementInputDeviceService(api);
      final selection = MeasurementInputDeviceSelection.systemDefault(
          selectedAt: DateTime.now());

      final resolved = await service.resolveForRecording(selection);
      expect(resolved, isNull);
    });
  });

  group('MeasurementInputDeviceService.toRecordConfigDevice', () {
    test('null resolved descriptor maps to null (system default)', () {
      expect(MeasurementInputDeviceService.toRecordConfigDevice(null), isNull);
    });

    test(
        'a resolved descriptor maps to a record InputDevice with the same '
        'id/label', () {
      const descriptor =
          MeasurementInputDeviceDescriptor(id: 'dev1', label: 'USB Mic');
      final device =
          MeasurementInputDeviceService.toRecordConfigDevice(descriptor);
      expect(device, isNotNull);
      expect(device!.id, 'dev1');
      expect(device.label, 'USB Mic');
    });
  });
}
