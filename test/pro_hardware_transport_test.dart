// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_hardware_transport.dart';
import 'package:tunai_pro/core/pro_ble_transport.dart';
import 'package:tunai_pro/core/pro_icp5_transport.dart';
import 'package:tunai_pro/core/pro_usbi_transport.dart';

void main() {
  // ── Default transport catalogue ─────────────────────────────────────────────
  group('default transport catalogue', () {
    test('includes BLE macOS', () {
      final t = HardwareTransportInfo.defaultBleMacos;
      expect(t.backend, HardwareTransportBackend.bleMacos);
      expect(t.platformHint, contains('macOS'));
    });

    test('includes USBi Windows temporary', () {
      final t = HardwareTransportInfo.defaultUsbiWindowsTemporary;
      expect(t.backend, HardwareTransportBackend.usbiWindowsTemporary);
      expect(t.platformHint.toLowerCase(), contains('windows'));
    });

    test('includes ICP5 final target', () {
      final t = HardwareTransportInfo.defaultIcp5;
      expect(t.backend, HardwareTransportBackend.icp5);
      expect(t.backend.isFinalTarget, isTrue);
    });

    test('includes Simulation', () {
      final t = HardwareTransportInfo.defaultSimulation;
      expect(t.backend, HardwareTransportBackend.simulation);
      expect(t.backend.isSimulation, isTrue);
    });

    test('defaultAvailableTransports has 4 entries', () {
      expect(HardwareTransportInfo.defaultAvailableTransports, hasLength(4));
    });
  });

  // ── isWriteEnabled safety lock ──────────────────────────────────────────────
  group('isWriteEnabled always false in Phase T2', () {
    test('BLE macOS write disabled', () {
      expect(HardwareTransportInfo.defaultBleMacos.isWriteEnabled, isFalse);
    });

    test('USBi Windows temporary write disabled', () {
      expect(HardwareTransportInfo.defaultUsbiWindowsTemporary.isWriteEnabled,
          isFalse);
    });

    test('ICP5 write disabled', () {
      expect(HardwareTransportInfo.defaultIcp5.isWriteEnabled, isFalse);
    });

    test('Simulation write disabled', () {
      expect(HardwareTransportInfo.defaultSimulation.isWriteEnabled, isFalse);
    });

    test('copyWith preserves isWriteEnabled=false', () {
      final t = HardwareTransportInfo.defaultBleMacos.copyWith(
          readinessStatus: TransportReadinessStatus.detected);
      expect(t.isWriteEnabled, isFalse);
    });

    test('all default transports have isWriteEnabled=false', () {
      for (final t in HardwareTransportInfo.defaultAvailableTransports) {
        expect(t.isWriteEnabled, isFalse,
            reason: '${t.backend} should not be write-enabled');
      }
    });
  });

  // ── Transport labelling ─────────────────────────────────────────────────────
  group('transport labelling', () {
    test('USBi is labelled temporary', () {
      expect(HardwareTransportBackend.usbiWindowsTemporary.isTemporary, isTrue);
      expect(HardwareTransportBackend.bleMacos.isTemporary, isFalse);
      expect(HardwareTransportBackend.icp5.isTemporary, isFalse);
    });

    test('ICP5 is labelled final target', () {
      expect(HardwareTransportBackend.icp5.isFinalTarget, isTrue);
      expect(HardwareTransportBackend.usbiWindowsTemporary.isFinalTarget,
          isFalse);
    });

    test('BLE is macOS path', () {
      expect(HardwareTransportBackend.bleMacos.platformHint,
          contains('macOS'));
    });

    test('USBi platform hint mentions Windows', () {
      expect(HardwareTransportBackend.usbiWindowsTemporary.platformHint
          .toLowerCase(), contains('windows'));
    });

    test('ICP5 label contains final target', () {
      final label = HardwareTransportBackend.icp5.label.toLowerCase();
      expect(label, contains('final'));
    });
  });

  // ── Write capability remains dry-run only ───────────────────────────────────
  group('write capability', () {
    test('all Phase T2 transports have dryRunOnly or none capability', () {
      for (final t in HardwareTransportInfo.defaultAvailableTransports) {
        expect(
          t.writeCapability == TransportWriteCapability.dryRunOnly ||
              t.writeCapability == TransportWriteCapability.none,
          isTrue,
          reason:
              '${t.backend} must have dryRunOnly or none capability in Phase T2',
        );
      }
    });

    test('selecting transport does not change write capability', () {
      final original = HardwareTransportInfo.defaultBleMacos;
      final updated = original.copyWith(
          readinessStatus: TransportReadinessStatus.detected);
      expect(updated.writeCapability, original.writeCapability);
      expect(updated.isWriteEnabled, isFalse);
    });
  });

  // ── Placeholder and detectionOnly flags ─────────────────────────────────────
  group('placeholder and detectionOnly', () {
    test('BLE is placeholder and detectionOnly', () {
      final t = HardwareTransportInfo.defaultBleMacos;
      expect(t.isPlaceholder, isTrue);
      expect(t.isDetectionOnly, isTrue);
    });

    test('USBi is placeholder and detectionOnly', () {
      final t = HardwareTransportInfo.defaultUsbiWindowsTemporary;
      expect(t.isPlaceholder, isTrue);
      expect(t.isDetectionOnly, isTrue);
    });

    test('ICP5 is placeholder and detectionOnly', () {
      final t = HardwareTransportInfo.defaultIcp5;
      expect(t.isPlaceholder, isTrue);
      expect(t.isDetectionOnly, isTrue);
    });
  });

  // ── JSON round-trips ────────────────────────────────────────────────────────
  group('JSON round-trips', () {
    test('HardwareTransportInfo round-trip', () {
      for (final t in HardwareTransportInfo.defaultAvailableTransports) {
        final json = t.toJson();
        final restored = HardwareTransportInfo.fromJson(json);
        expect(restored.backend, t.backend);
        expect(restored.readinessStatus, t.readinessStatus);
        expect(restored.writeCapability, t.writeCapability);
        expect(restored.isWriteEnabled, isFalse);
        expect(restored.isPlaceholder, t.isPlaceholder);
      }
    });

    test('toJson does not include write packet fields', () {
      for (final t in HardwareTransportInfo.defaultAvailableTransports) {
        final json = t.toJson();
        expect(json.containsKey('writePacket'), isFalse);
        expect(json.containsKey('addressWrite'), isFalse);
        expect(json.containsKey('eeprom'), isFalse);
        expect(json.containsKey('safeload'), isFalse);
      }
    });

    test('isWriteEnabled always serialises as false', () {
      for (final t in HardwareTransportInfo.defaultAvailableTransports) {
        expect(t.toJson()['isWriteEnabled'], isFalse);
      }
    });

    test('HardwareTransportBackend enum round-trip', () {
      for (final b in HardwareTransportBackend.values) {
        expect(HardwareTransportBackend.fromJson(b.toJson()), b);
      }
    });

    test('TransportReadinessStatus enum round-trip', () {
      for (final s in TransportReadinessStatus.values) {
        expect(TransportReadinessStatus.fromJson(s.toJson()), s);
      }
    });

    test('TransportWriteCapability enum round-trip', () {
      for (final c in TransportWriteCapability.values) {
        expect(TransportWriteCapability.fromJson(c.toJson()), c);
      }
    });
  });

  // ── BLE transport placeholder ────────────────────────────────────────────────
  group('ProBleTransport', () {
    final ble = ProBleTransport();

    test('isPlaceholder true', () => expect(ProBleTransport.isPlaceholder, isTrue));
    test('isWriteEnabled false', () => expect(ProBleTransport.isWriteEnabled, isFalse));
    test('isDetectionOnly true', () => expect(ProBleTransport.isDetectionOnly, isTrue));

    test('checkReadiness returns BLE info with lastCheckedAt', () async {
      final info = await ble.checkReadiness();
      expect(info.backend, HardwareTransportBackend.bleMacos);
      expect(info.isWriteEnabled, isFalse);
      expect(info.lastCheckedAt, isNotNull);
    });

    test('statusJson has no write packet fields', () {
      final json = ble.toStatusJson();
      expect(json['isWriteEnabled'], isFalse);
      expect(json.containsKey('writePacket'), isFalse);
    });
  });

  // ── ICP5 transport placeholder ───────────────────────────────────────────────
  group('ProIcp5Transport', () {
    final icp5 = ProIcp5Transport();

    test('isPlaceholder true', () => expect(ProIcp5Transport.isPlaceholder, isTrue));
    test('isWriteEnabled false', () => expect(ProIcp5Transport.isWriteEnabled, isFalse));
    test('isDetectionOnly true', () => expect(ProIcp5Transport.isDetectionOnly, isTrue));

    test('checkReadiness returns ICP5 info', () async {
      final info = await icp5.checkReadiness();
      expect(info.backend, HardwareTransportBackend.icp5);
      expect(info.isWriteEnabled, isFalse);
      expect(info.lastCheckedAt, isNotNull);
    });

    test('statusJson has no write packet fields', () {
      final json = icp5.toStatusJson();
      expect(json['isWriteEnabled'], isFalse);
      expect(json.containsKey('writePacket'), isFalse);
      expect(json.containsKey('addressWrite'), isFalse);
    });
  });

  // ── USBi transport (Windows temporary) ──────────────────────────────────────
  group('ProUsbiTransport (Windows temporary)', () {
    final usbi = ProUsbiTransport();

    test('isPlaceholder true', () => expect(ProUsbiTransport.isPlaceholder, isTrue));
    test('isWriteBackendEnabled false',
        () => expect(ProUsbiTransport.isWriteBackendEnabled, isFalse));
    test('isDetectionOnly true',
        () => expect(ProUsbiTransport.isDetectionOnly, isTrue));

    test('writeParameter always returns wasActualWrite=false', () async {
      final result = await usbi.writeParameter(0x0067, [0, 0, 0, 0]);
      expect(result.wasActualWrite, isFalse);
      expect(result.success, isFalse);
    });

    test('detectDevices returns empty list in Phase T2', () async {
      final devices = await usbi.detectDevices();
      expect(devices, isEmpty);
    });

    test('statusJson has isWriteBackendEnabled=false', () {
      final json = usbi.toStatusJson();
      expect(json['isWriteBackendEnabled'], isFalse);
    });
  });

  // ── Description notes ────────────────────────────────────────────────────────
  group('description notes', () {
    test('BLE description mentions macOS', () {
      expect(HardwareTransportBackend.bleMacos.descriptionNote
          .toLowerCase(), contains('macos'));
    });

    test('USBi description mentions temporary', () {
      expect(HardwareTransportBackend.usbiWindowsTemporary.descriptionNote
          .toLowerCase(), contains('temporary'));
    });

    test('ICP5 description mentions pending', () {
      expect(HardwareTransportBackend.icp5.descriptionNote
          .toLowerCase(), contains('pending'));
    });
  });

  // ── Safety invariants ────────────────────────────────────────────────────────
  group('safety invariants', () {
    test('no transport has write packet fields in JSON', () {
      for (final t in HardwareTransportInfo.defaultAvailableTransports) {
        final json = t.toJson();
        final forbidden = ['writePacket', 'safeload', 'eeprom', 'selfboot',
            'addressWrite', 'controlTransfer', 'blePacket', 'icp5Packet'];
        for (final key in forbidden) {
          expect(json.containsKey(key), isFalse,
              reason: '${t.backend} JSON must not contain "$key"');
        }
      }
    });

    test('ProBleTransport has no write packet fields in status', () {
      final json = ProBleTransport().toStatusJson();
      expect(json.containsKey('writePacket'), isFalse);
      expect(json.containsKey('blePacket'), isFalse);
    });

    test('ProIcp5Transport has no packet fields in status', () {
      final json = ProIcp5Transport().toStatusJson();
      expect(json.containsKey('icp5Packet'), isFalse);
      expect(json.containsKey('writePacket'), isFalse);
    });
  });
}
