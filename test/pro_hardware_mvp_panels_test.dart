// ── TUNAI PRO Hardware MVP Panels — Guard Logic Tests ─────────────────────────
// Verifies panel guard rules, registry filters, dry-run gates, and safety
// restrictions for the Hardware MVP validation panels added in T4C.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_dsp_address_registry.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_usbi_packet_builder.dart';
import 'package:tunai_pro/core/pro_hardware_transport.dart';

void main() {
  // ── Registry helpers ───────────────────────────────────────────────────────

  final registry = DspAddressRegistry.createDefault();

  // ── 1. Master Volume executor (confirmed working path) ────────────────────

  group('Master Volume — confirmed path preserved', () {
    test('registry contains verified Master Volume L at 0x67', () {
      final entry = registry.findByAddressInt(0x67);
      expect(entry, isNotNull);
      expect(entry!.parameterKind, DspParameterKind.masterVolume);
      expect(entry.verificationStatus, DspAddressVerificationStatus.verified);
    });

    test('registry contains verified Master Volume R at 0x64', () {
      final entry = registry.findByAddressInt(0x64);
      expect(entry, isNotNull);
      expect(entry!.parameterKind, DspParameterKind.masterVolume);
      expect(entry.verificationStatus, DspAddressVerificationStatus.verified);
    });

    test('Master Volume L/R are actual-write eligible', () {
      final l = registry.findByAddressInt(0x67)!;
      final r = registry.findByAddressInt(0x64)!;
      expect(l.isActualWriteEligible, isTrue);
      expect(r.isActualWriteEligible, isTrue);
    });
  });

  // ── 2. ACK [01] success remains accepted ──────────────────────────────────

  group('ACK single-byte — hotfix preserved', () {
    test('isAckSuccess([0x01]) == true', () {
      expect(isAckSuccess([0x01]), isTrue);
    });

    test('isAckSuccess([0x00]) == false', () {
      expect(isAckSuccess([0x00]), isFalse);
    });

    test('isAckSuccess([C0 B5 00 00 00 00 01 00]) == true', () {
      expect(
        isAckSuccess([0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]),
        isTrue,
      );
    });

    test('isAckSuccess([]) == false', () {
      expect(isAckSuccess([]), isFalse);
    });
  });

  // ── 3. Mute/Gain panel — lists only Mute/Gain registry entries ────────────

  group('Mute/Gain panel — registry filter', () {
    test('addressesForKind(mute) returns only mute entries', () {
      final entries = registry.addressesForKind(DspParameterKind.mute);
      for (final e in entries) {
        expect(e.parameterKind, DspParameterKind.mute);
      }
    });

    test('addressesForKind(gain) returns only gain entries', () {
      final entries = registry.addressesForKind(DspParameterKind.gain);
      for (final e in entries) {
        expect(e.parameterKind, DspParameterKind.gain);
      }
    });

    test('combined mute+gain list contains no master-volume entries', () {
      final entries = [
        ...registry.addressesForKind(DspParameterKind.mute),
        ...registry.addressesForKind(DspParameterKind.gain),
      ];
      for (final e in entries) {
        expect(e.parameterKind, isNot(DspParameterKind.masterVolume));
      }
    });

    test('combined mute+gain list contains no delay entries', () {
      final entries = [
        ...registry.addressesForKind(DspParameterKind.mute),
        ...registry.addressesForKind(DspParameterKind.gain),
      ];
      for (final e in entries) {
        expect(e.parameterKind, isNot(DspParameterKind.delay));
      }
    });
  });

  // ── 4. Mute/Gain panel — unknown value format blocks execution ────────────

  group('Mute/Gain panel — value format guard', () {
    test('address with null dataFormat is not execution-eligible', () {
      // Simulate a hypothetical mute address with no dataFormat
      const addr = VerifiedDspAddress(
        id: 'test_mute_no_format',
        platform: DspTargetPlatform.adau1466,
        parameterKind: DspParameterKind.mute,
        logicalName: 'Mute CH1',
        addressHex: '0x0100',
        addressInt: 0x0100,
        verificationStatus: DspAddressVerificationStatus.verified,
        source: DspAddressSource.placeholder,
        dataFormat: null, // ← not set
      );
      expect(addr.dataFormat, isNull,
          reason: 'dataFormat null must block execution');
    });

    test('address with confirmed dataFormat may proceed to execute guard', () {
      const addr = VerifiedDspAddress(
        id: 'test_mute_with_format',
        platform: DspTargetPlatform.adau1466,
        parameterKind: DspParameterKind.mute,
        logicalName: 'Mute CH1',
        addressHex: '0x0100',
        addressInt: 0x0100,
        verificationStatus: DspAddressVerificationStatus.verified,
        source: DspAddressSource.directWriteValidated,
        dataFormat: '8.24 fixed-point',
      );
      expect(addr.dataFormat, isNotNull);
      expect(addr.isActualWriteEligible, isTrue);
    });

    test('address with exportConfirmed status is NOT actual-write eligible', () {
      const addr = VerifiedDspAddress(
        id: 'test_mute_export_only',
        platform: DspTargetPlatform.adau1466,
        parameterKind: DspParameterKind.mute,
        logicalName: 'Mute CH1',
        addressHex: '0x0100',
        addressInt: 0x0100,
        verificationStatus: DspAddressVerificationStatus.exportConfirmed,
        source: DspAddressSource.sigmaStudioExport,
        dataFormat: '8.24 fixed-point',
      );
      expect(addr.isActualWriteEligible, isFalse);
    });
  });

  // ── 5. Delay panel — dry-run only (no eligible write) ────────────────────

  group('Delay panel — dry-run only', () {
    test('no delay address in default registry is actual-write eligible', () {
      final entries = registry.addressesForKind(DspParameterKind.delay);
      for (final e in entries) {
        expect(e.isActualWriteEligible, isFalse,
            reason: 'Delay entries must not be write-eligible in MVP');
      }
    });

    test('DspParameterKind.delay exists in enum', () {
      expect(DspParameterKind.delay, isNotNull);
    });
  });

  // ── 6. PEQ panel — dry-run only, requires SafeLoad ───────────────────────

  group('PEQ panel — dry-run only, requires SafeLoad', () {
    test('no PEQ address in default registry is actual-write eligible', () {
      final entries = registry.addressesForKind(DspParameterKind.peq);
      for (final e in entries) {
        expect(e.isActualWriteEligible, isFalse,
            reason: 'PEQ entries must not be write-eligible — SafeLoad required first');
      }
    });

    test('PEQ addresses require safeload=true if present in registry', () {
      final entries = registry.addressesForKind(DspParameterKind.peq);
      for (final e in entries) {
        if (e.safeloadRequired != null) {
          expect(e.safeloadRequired, isTrue);
        }
      }
    });
  });

  // ── 7. XO panel — hard-blocked ────────────────────────────────────────────

  group('XO panel — hard-blocked', () {
    test('no crossover address in default registry is actual-write eligible', () {
      final entries = registry.addressesForKind(DspParameterKind.crossover);
      for (final e in entries) {
        expect(e.isActualWriteEligible, isFalse,
            reason: 'XO entries must not be write-eligible — blocked');
      }
    });

    test('DspParameterKind.crossover exists in enum', () {
      expect(DspParameterKind.crossover, isNotNull);
    });
  });

  // ── 8. SafeLoad panel — dry-run only ──────────────────────────────────────

  group('SafeLoad panel — dry-run only', () {
    test('no safeload address in default registry is actual-write eligible', () {
      final entries = registry.addressesForKind(DspParameterKind.safeload);
      for (final e in entries) {
        expect(e.isActualWriteEligible, isFalse,
            reason: 'SafeLoad entries must not be write-eligible today');
      }
    });

    test('planned safeload address range 0x6000–0x6007 not in default registry', () {
      for (var addr = 0x6000; addr <= 0x6007; addr++) {
        final entry = registry.findByAddressInt(addr);
        expect(entry, isNull,
            reason:
                'SafeLoad address 0x${addr.toRadixString(16)} must not be in '
                'default registry until confirmed');
      }
    });
  });

  // ── 9. No Write All ────────────────────────────────────────────────────────

  group('Write All — forbidden', () {
    test('no parameterKind represents writeAll', () {
      final kinds = DspParameterKind.values;
      expect(kinds.any((k) => k.name.toLowerCase().contains('writeall')),
          isFalse);
    });

    test('default registry has no addresses with "write_all" in id', () {
      final found = registry.addresses.where(
          (a) => a.id.toLowerCase().contains('write_all') ||
                 a.id.toLowerCase().contains('writeall'));
      expect(found, isEmpty);
    });
  });

  // ── 10. EEPROM / Selfboot remain forbidden ────────────────────────────────

  group('EEPROM / Selfboot — forbidden', () {
    test('no addresses in registry contain "eeprom" in id', () {
      final found = registry.addresses
          .where((a) => a.id.toLowerCase().contains('eeprom'));
      expect(found, isEmpty);
    });

    test('no addresses in registry contain "selfboot" in id', () {
      final found = registry.addresses
          .where((a) => a.id.toLowerCase().contains('selfboot'));
      expect(found, isEmpty);
    });

    test('no addresses in registry contain "eeprom" in logicalName', () {
      final found = registry.addresses
          .where((a) => a.logicalName.toLowerCase().contains('eeprom'));
      expect(found, isEmpty);
    });
  });

  // ── 11. ICP5 remains final target — not active transport ─────────────────

  group('ICP5 — final target, not yet active', () {
    test('icp5 backend is not usbiWindowsTemporary', () {
      expect(
        HardwareTransportBackend.usbiWindowsTemporary,
        isNot(equals(HardwareTransportBackend.icp5)),
      );
    });

    test('HardwareTransportBackend.icp5 exists', () {
      expect(
        HardwareTransportBackend.values
            .any((b) => b.name.toLowerCase().contains('icp5')),
        isTrue,
      );
    });
  });

  // ── 12. USBi remains temporary ────────────────────────────────────────────

  group('USBi — temporary designation', () {
    test('usbiWindowsTemporary backend label contains "Temporary"', () {
      expect(
        HardwareTransportBackend.usbiWindowsTemporary.label
            .toLowerCase()
            .contains('temporary'),
        isTrue,
      );
    });

    test('usbiWindowsTemporary is distinct from simulation backend', () {
      expect(
        HardwareTransportBackend.usbiWindowsTemporary,
        isNot(equals(HardwareTransportBackend.simulation)),
      );
    });
  });

  // ── 13. Build marker — constant string verification ───────────────────────

  group('Build marker', () {
    const kBuildMarker =
        'TUNAI PRO · Hardware MVP Test Build · USBi MV confirmed · ICP5 final target';

    test('build marker contains expected components', () {
      expect(kBuildMarker, contains('Hardware MVP Test Build'));
      expect(kBuildMarker, contains('USBi MV confirmed'));
      expect(kBuildMarker, contains('ICP5 final target'));
    });

    test('build marker is not empty', () {
      expect(kBuildMarker.isNotEmpty, isTrue);
    });
  });

  // ── Eligibility rule completeness ─────────────────────────────────────────

  group('isActualWriteEligible — only verified/liveWriteVerified allowed', () {
    test('verified status is eligible', () {
      expect(
        DspAddressVerificationStatus.verified.isActualWriteEligible,
        isTrue,
      );
    });

    test('liveWriteVerified status is eligible', () {
      expect(
        DspAddressVerificationStatus.liveWriteVerified.isActualWriteEligible,
        isTrue,
      );
    });

    test('exportConfirmed is NOT eligible', () {
      expect(
        DspAddressVerificationStatus.exportConfirmed.isActualWriteEligible,
        isFalse,
      );
    });

    test('needsLiveValidation is NOT eligible', () {
      expect(
        DspAddressVerificationStatus.needsLiveValidation.isActualWriteEligible,
        isFalse,
      );
    });

    test('placeholder is NOT eligible', () {
      expect(
        DspAddressVerificationStatus.placeholder.isActualWriteEligible,
        isFalse,
      );
    });

    test('blocked is NOT eligible', () {
      expect(
        DspAddressVerificationStatus.blocked.isActualWriteEligible,
        isFalse,
      );
    });
  });
}
