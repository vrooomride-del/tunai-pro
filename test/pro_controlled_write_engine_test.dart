// TUNAI PRO — Phase T: Controlled Write Engine tests
//
// Verifies safety guarantees:
//   - Only addresses 0x67 and 0x64 are ever generated
//   - Out-of-range values are blocked
//   - User confirmation is required
//   - Disconnected transport blocks write
//   - No EEPROM/Selfboot/SafeLoad fields
//   - No Write-All path

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_hardware_write_data.dart';
import 'package:tunai_pro/core/pro_controlled_write_engine.dart';
import 'package:tunai_pro/core/pro_usbi_transport.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

ProUsbiTransport _transport() => ProUsbiTransport();

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('createMasterVolumeWriteRequests — addresses', () {
    test('only generates address 0x67 for left channel', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.8, rightVolume: 0.8);
      final left = reqs.firstWhere(
          (r) => r.target == HardwareWriteTarget.adau1466MasterVolumeL);
      expect(left.addressInt, 0x67);
      expect(left.addressHex, '0x67');
    });

    test('only generates address 0x64 for right channel', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.8, rightVolume: 0.8);
      final right = reqs.firstWhere(
          (r) => r.target == HardwareWriteTarget.adau1466MasterVolumeR);
      expect(right.addressInt, 0x64);
      expect(right.addressHex, '0x64');
    });

    test('generates exactly 2 requests (L and R)', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.5, rightVolume: 0.5);
      expect(reqs.length, 2);
      final targets = reqs.map((r) => r.target).toSet();
      expect(targets, {
        HardwareWriteTarget.adau1466MasterVolumeL,
        HardwareWriteTarget.adau1466MasterVolumeR,
      });
    });

    test('all requests are marked dryRunOnly', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.5, rightVolume: 0.5);
      for (final r in reqs) {
        expect(r.dryRunOnly, isTrue,
            reason: '${r.target.label} should be dryRunOnly');
      }
    });
  });

  group('createMasterVolumeWriteRequests — value validation', () {
    test('value 0.0 is allowed', () {
      expect(() => createMasterVolumeWriteRequests(
              leftVolume: 0.0, rightVolume: 0.0),
          returnsNormally);
    });

    test('value 1.0 is allowed', () {
      expect(() => createMasterVolumeWriteRequests(
              leftVolume: 1.0, rightVolume: 1.0),
          returnsNormally);
    });

    test('value above 1.0 is blocked (left)', () {
      expect(() => createMasterVolumeWriteRequests(
              leftVolume: 1.01, rightVolume: 0.5),
          throwsArgumentError);
    });

    test('value above 1.0 is blocked (right)', () {
      expect(() => createMasterVolumeWriteRequests(
              leftVolume: 0.5, rightVolume: 1.1),
          throwsArgumentError);
    });

    test('negative value is blocked (left)', () {
      expect(() => createMasterVolumeWriteRequests(
              leftVolume: -0.01, rightVolume: 0.5),
          throwsArgumentError);
    });

    test('negative value is blocked (right)', () {
      expect(() => createMasterVolumeWriteRequests(
              leftVolume: 0.5, rightVolume: -1.0),
          throwsArgumentError);
    });
  });

  group('createMasterVolumeWriteRequests — fixed-point encoding', () {
    test('0.0 encodes to all-zero bytes', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.0, rightVolume: 0.0);
      final left = reqs.first;
      expect(left.rawBytes, [0, 0, 0, 0]);
      expect(left.fixedPointHex, '0x00000000');
    });

    test('1.0 encodes to 0x00800000 (5.23 full scale)', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 1.0, rightVolume: 1.0);
      final left = reqs.first;
      // 1.0 * 2^23 = 8388608 = 0x800000
      expect(left.rawBytes, [0x00, 0x80, 0x00, 0x00]);
      expect(left.fixedPointHex, '0x00800000');
    });

    test('rawBytes are 4 bytes long for every request', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.75, rightVolume: 0.5);
      for (final r in reqs) {
        expect(r.rawBytes.length, 4);
      }
    });

    test('all rawBytes are in 0–255 range', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.333, rightVolume: 0.666);
      for (final r in reqs) {
        for (final b in r.rawBytes) {
          expect(b, inInclusiveRange(0, 255));
        }
      }
    });
  });

  group('createMasterVolumeWriteRequests — JSON round-trip', () {
    test('request serializes and deserializes', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.7, rightVolume: 0.6);
      for (final req in reqs) {
        final json = req.toJson();
        final restored = HardwareWriteRequest.fromJson(
            Map<String, dynamic>.from(json));
        expect(restored.addressInt, req.addressInt);
        expect(restored.valueDouble, req.valueDouble);
        expect(restored.rawBytes, req.rawBytes);
        expect(restored.dryRunOnly, isTrue);
      }
    });

    test('JSON includes safetyNote with no-EEPROM language', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.5, rightVolume: 0.5);
      for (final req in reqs) {
        final json = req.toJson();
        expect(json.containsKey('safetyNote'), isTrue);
        expect((json['safetyNote'] as String).toLowerCase(),
            contains('no eeprom'));
      }
    });

    test('JSON does not contain EEPROM/Selfboot/SafeLoad/WriteAll action keys', () {
      final reqs = createMasterVolumeWriteRequests(
          leftVolume: 0.5, rightVolume: 0.5);
      for (final req in reqs) {
        final keys = req.toJson().keys.toList();
        expect(keys, isNot(contains('eepromWrite')));
        expect(keys, isNot(contains('selfbootWrite')));
        expect(keys, isNot(contains('safeLoadExecute')));
        expect(keys, isNot(contains('writeAll')));
        expect(keys, isNot(contains('bulkWrite')));
      }
    });
  });

  group('performControlledMasterVolumeWrite — guards', () {
    test('blocked without user confirmation', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   0.5,
        userConfirmed: false,
        transport:     _transport(),
      );
      expect(log.result?.status, HardwareWriteStatus.blocked);
      expect(log.result?.wasActualWrite, isFalse);
      expect(log.result?.errorMessage?.toLowerCase(),
          contains('confirmation'));
    });

    test('blocked when transport is disconnected (placeholder)', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   0.5,
        userConfirmed: true,
        transport:     _transport(), // placeholder — always disconnected
      );
      // Transport is a placeholder → not connected → blocked
      expect(log.result?.status, HardwareWriteStatus.blocked);
      expect(log.result?.wasActualWrite, isFalse);
    });

    test('blocked with disabled permission', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   0.5,
        userConfirmed: true,
        transport:     _transport(),
        permission:    HardwareWritePermission.disabled,
      );
      expect(log.result?.status, HardwareWriteStatus.blocked);
      expect(log.result?.wasActualWrite, isFalse);
    });

    test('blocked with dryRunOnly permission', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   0.5,
        userConfirmed: true,
        transport:     _transport(),
        permission:    HardwareWritePermission.dryRunOnly,
      );
      expect(log.result?.status, HardwareWriteStatus.blocked);
      expect(log.result?.wasActualWrite, isFalse);
    });

    test('wasActualWrite is always false in Phase T', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   0.5,
        userConfirmed: true,
        transport:     _transport(),
      );
      expect(log.result?.wasActualWrite, isFalse);
      expect(log.wasActualWrite, isFalse);
    });

    test('log always has a result', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   0.5,
        userConfirmed: false,
        transport:     _transport(),
      );
      expect(log.result, isNotNull);
      expect(log.id, isNotEmpty);
    });
  });

  group('performControlledMasterVolumeWrite — value guards', () {
    test('left volume > 1.0 is blocked (clamped by guard)', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    1.5,
        rightVolume:   0.5,
        userConfirmed: true,
        transport:     _transport(),
      );
      expect(log.result?.status, HardwareWriteStatus.blocked);
      expect(log.result?.wasActualWrite, isFalse);
    });

    test('negative left volume is blocked', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    -0.1,
        rightVolume:   0.5,
        userConfirmed: true,
        transport:     _transport(),
      );
      expect(log.result?.status, HardwareWriteStatus.blocked);
    });

    test('negative right volume is blocked', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   -0.5,
        userConfirmed: true,
        transport:     _transport(),
      );
      expect(log.result?.status, HardwareWriteStatus.blocked);
    });
  });

  group('HardwareWriteLog — JSON round-trip', () {
    test('log serializes to JSON without error', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   0.5,
        userConfirmed: false,
        transport:     _transport(),
      );
      expect(() => log.toJson(), returnsNormally);
    });

    test('log JSON includes safetyNote with no-EEPROM language', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   0.5,
        userConfirmed: false,
        transport:     _transport(),
      );
      final json = log.toJson();
      expect(json.containsKey('safetyNote'), isTrue);
      expect((json['safetyNote'] as String).toLowerCase(),
          contains('no eeprom'));
    });

    test('log JSON does not contain EEPROM/Selfboot/SafeLoad/WriteAll action keys', () async {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    0.5,
        rightVolume:   0.5,
        userConfirmed: false,
        transport:     _transport(),
      );
      // Check for dangerous ACTION keys (not prose in safety notes)
      final keys = log.toJson().keys.toList();
      expect(keys, isNot(contains('eepromWrite')));
      expect(keys, isNot(contains('selfbootWrite')));
      expect(keys, isNot(contains('safeLoadExecute')));
      expect(keys, isNot(contains('writeAll')));
      expect(keys, isNot(contains('bulkWrite')));
    });
  });

  group('ProUsbiTransport — placeholder guards', () {
    test('isPlaceholder is always true in Phase T', () {
      expect(ProUsbiTransport.isPlaceholder, isTrue);
    });

    test('isConnected is false when placeholder', () {
      expect(_transport().isConnected, isFalse);
    });

    test('detectDevices returns empty list', () async {
      final devices = await _transport().detectDevices();
      expect(devices, isEmpty);
    });

    test('open() returns false', () async {
      final result = await _transport().open();
      expect(result, isFalse);
    });

    test('writeParameter returns wasActualWrite: false', () async {
      final outcome = await _transport().writeParameter(0x67, [0, 0x80, 0, 0]);
      expect(outcome.wasActualWrite, isFalse);
      expect(outcome.success, isFalse);
    });

    test('writeParameter does not succeed even with correct address', () async {
      final outcome = await _transport().writeParameter(0x67, [0, 0x80, 0, 0]);
      expect(outcome.success, isFalse);
      expect(outcome.errorMessage, isNotNull);
    });
  });

  group('HardwareWriteTarget — verified addresses', () {
    test('MasterVolumeL address is 0x67', () {
      expect(HardwareWriteTarget.adau1466MasterVolumeL.verifiedAddressInt, 0x67);
      expect(HardwareWriteTarget.adau1466MasterVolumeL.verifiedAddressHex, '0x67');
    });

    test('MasterVolumeR address is 0x64', () {
      expect(HardwareWriteTarget.adau1466MasterVolumeR.verifiedAddressInt, 0x64);
      expect(HardwareWriteTarget.adau1466MasterVolumeR.verifiedAddressHex, '0x64');
    });

    test('enum round-trips JSON', () {
      for (final t in HardwareWriteTarget.values) {
        expect(HardwareWriteTarget.fromJson(t.toJson()), t);
      }
    });
  });

  group('HardwareWritePermission — enum', () {
    test('disabled does not allowsWrite', () {
      expect(HardwareWritePermission.disabled.allowsWrite, isFalse);
    });

    test('dryRunOnly does not allowsWrite', () {
      expect(HardwareWritePermission.dryRunOnly.allowsWrite, isFalse);
    });

    test('controlledMasterVolumeOnly allowsWrite', () {
      expect(
          HardwareWritePermission.controlledMasterVolumeOnly.allowsWrite,
          isTrue);
    });

    test('enum round-trips JSON', () {
      for (final p in HardwareWritePermission.values) {
        expect(HardwareWritePermission.fromJson(p.toJson()), p);
      }
    });
  });

  group('HardwareWriteStatus — enum', () {
    test('success is terminal', () {
      expect(HardwareWriteStatus.success.isTerminal, isTrue);
    });

    test('failed is terminal', () {
      expect(HardwareWriteStatus.failed.isTerminal, isTrue);
    });

    test('blocked is terminal', () {
      expect(HardwareWriteStatus.blocked.isTerminal, isTrue);
    });

    test('writing is active', () {
      expect(HardwareWriteStatus.writing.isActive, isTrue);
    });

    test('notStarted is not active', () {
      expect(HardwareWriteStatus.notStarted.isActive, isFalse);
    });

    test('enum round-trips JSON', () {
      for (final s in HardwareWriteStatus.values) {
        expect(HardwareWriteStatus.fromJson(s.toJson()), s);
      }
    });
  });
}
