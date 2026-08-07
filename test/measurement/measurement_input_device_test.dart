// Phase 3-D1 — measurement_input_device.dart pure model/resolver tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';

void main() {
  group('MeasurementInputDeviceSelection construction', () {
    test('specificDevice sets deviceId, useSystemDefault=false', () {
      final now = DateTime.utc(2026, 1, 1);
      final s = MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev1', labelSnapshot: 'USB Mic', selectedAt: now);
      expect(s.deviceId, 'dev1');
      expect(s.useSystemDefault, isFalse);
      expect(s.labelSnapshot, 'USB Mic');
    });

    test('systemDefault sets deviceId=null, useSystemDefault=true', () {
      final now = DateTime.utc(2026, 1, 1);
      final s = MeasurementInputDeviceSelection.systemDefault(selectedAt: now);
      expect(s.deviceId, isNull);
      expect(s.useSystemDefault, isTrue);
    });
  });

  group('MeasurementInputDeviceSelection JSON round-trip', () {
    test('specific device round-trips', () {
      final now = DateTime.utc(2026, 1, 1);
      final s = MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev1', labelSnapshot: 'USB Mic', selectedAt: now);
      final decoded = MeasurementInputDeviceSelection.fromJson(s.toJson());
      expect(decoded.deviceId, 'dev1');
      expect(decoded.useSystemDefault, isFalse);
      expect(decoded.labelSnapshot, 'USB Mic');
    });

    test('system default round-trips', () {
      final now = DateTime.utc(2026, 1, 1);
      final s = MeasurementInputDeviceSelection.systemDefault(selectedAt: now);
      final decoded = MeasurementInputDeviceSelection.fromJson(s.toJson());
      expect(decoded.deviceId, isNull);
      expect(decoded.useSystemDefault, isTrue);
    });

    test('malformed JSON (neither flag) throws FormatException', () {
      expect(
          () => MeasurementInputDeviceSelection.fromJson(
              {'labelSnapshot': 'x', 'selectedAt': '2026-01-01T00:00:00Z'}),
          throwsFormatException);
    });
  });

  group('MeasurementInputDeviceSnapshot JSON round-trip', () {
    test('round-trips including actual sample rate/channel count', () {
      final now = DateTime.utc(2026, 1, 1);
      final snap = MeasurementInputDeviceSnapshot(
        deviceId: 'dev1',
        label: 'USB Mic',
        isSystemDefault: false,
        platform: 'macos',
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: now,
      );
      final decoded = MeasurementInputDeviceSnapshot.fromJson(snap.toJson());
      expect(decoded.deviceId, 'dev1');
      expect(decoded.actualSampleRate, 48000);
      expect(decoded.actualChannelCount, 1);
      expect(decoded.platform, 'macos');
    });

    test(
        'null deviceId/actual values round-trip as null (malformed '
        'capture case)', () {
      final now = DateTime.utc(2026, 1, 1);
      final snap = MeasurementInputDeviceSnapshot(
        deviceId: null,
        label: 'System Default',
        isSystemDefault: true,
        platform: 'macos',
        actualSampleRate: null,
        actualChannelCount: null,
        capturedAt: now,
      );
      final decoded = MeasurementInputDeviceSnapshot.fromJson(snap.toJson());
      expect(decoded.deviceId, isNull);
      expect(decoded.actualSampleRate, isNull);
      expect(decoded.actualChannelCount, isNull);
    });
  });

  group('MeasurementInputDeviceResolver.resolve', () {
    final devices = [
      const MeasurementInputDeviceDescriptor(id: 'dev1', label: 'USB Mic'),
      const MeasurementInputDeviceDescriptor(id: 'dev2', label: 'Built-in Mic'),
    ];

    test('system default resolves to null regardless of available list', () {
      final selection = MeasurementInputDeviceSelection.systemDefault(
          selectedAt: DateTime.utc(2026, 1, 1));
      final resolved = MeasurementInputDeviceResolver.resolve(
          selection: selection, available: devices);
      expect(resolved, isNull);
    });

    test('a present specific device resolves to its descriptor', () {
      final selection = MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev2',
          labelSnapshot: 'Built-in Mic',
          selectedAt: DateTime.utc(2026, 1, 1));
      final resolved = MeasurementInputDeviceResolver.resolve(
          selection: selection, available: devices);
      expect(resolved?.id, 'dev2');
    });

    test(
        'a vanished specific device throws '
        'MeasurementInputDeviceUnavailable — never silently falls back', () {
      final selection = MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev-gone',
          labelSnapshot: 'Unplugged Mic',
          selectedAt: DateTime.utc(2026, 1, 1));
      expect(
          () => MeasurementInputDeviceResolver.resolve(
              selection: selection, available: devices),
          throwsA(isA<MeasurementInputDeviceUnavailable>()));
    });

    test(
        'label-only match is never accepted — device identity is by id '
        'only', () {
      final selection = MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev-different-id',
          labelSnapshot: 'USB Mic', // same label as devices[0], different id
          selectedAt: DateTime.utc(2026, 1, 1));
      expect(
          () => MeasurementInputDeviceResolver.resolve(
              selection: selection, available: devices),
          throwsA(isA<MeasurementInputDeviceUnavailable>()));
    });

    test('empty available list still resolves system default to null', () {
      final selection = MeasurementInputDeviceSelection.systemDefault(
          selectedAt: DateTime.utc(2026, 1, 1));
      final resolved = MeasurementInputDeviceResolver.resolve(
          selection: selection, available: const []);
      expect(resolved, isNull);
    });
  });
}
