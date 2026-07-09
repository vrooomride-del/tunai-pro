// TUNAI PRO — Phase P: SigmaStudio Mapping Reference tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_sigma_mapping_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';

SigmaMappingReference _adau1466Reference() => SigmaMappingReference(
  id: 'test_ref',
  platform: DspTargetPlatform.adau1466,
  mappings: [
    const SigmaParameterMapping(
      id: 'mv_l',
      platform: DspTargetPlatform.adau1466,
      blockKind: SigmaBlockKind.masterVolume,
      logicalName: 'Master Volume L',
      addressId: 'adau1466_master_vol_l',
      addressHex: '0x67',
      mappingStatus: SigmaMappingStatus.mappedVerified,
      sourceNote: 'Verified from direct-write/capture.',
    ),
    const SigmaParameterMapping(
      id: 'mv_r',
      platform: DspTargetPlatform.adau1466,
      blockKind: SigmaBlockKind.masterVolume,
      logicalName: 'Master Volume R',
      addressId: 'adau1466_master_vol_r',
      addressHex: '0x64',
      mappingStatus: SigmaMappingStatus.mappedVerified,
      sourceNote: 'Verified from direct-write/capture.',
    ),
    const SigmaParameterMapping(
      id: 'peq_all',
      platform: DspTargetPlatform.adau1466,
      blockKind: SigmaBlockKind.peq,
      logicalName: 'PEQ (all channels)',
      mappingStatus: SigmaMappingStatus.requiresCapture,
      warning: 'Address unknown — requires SigmaStudio Export/Capture.',
    ),
  ],
  warnings: ['All unverified mappings require SigmaStudio Export/Capture.'],
  summary: '3 blocks. 2 verified. 1 requires capture.',
  status: SigmaMappingStatus.partiallyMapped,
);

SigmaMappingReference _adau1701Reference() => SigmaMappingReference(
  id: 'test_1701',
  platform: DspTargetPlatform.adau1701,
  mappings: [
    const SigmaParameterMapping(
      id: 'peq_1701',
      platform: DspTargetPlatform.adau1701,
      blockKind: SigmaBlockKind.peq,
      logicalName: 'PEQ (all channels)',
      mappingStatus: SigmaMappingStatus.requiresCapture,
      warning: 'No verified ADAU1701 addresses. Requires SigmaStudio Export/Capture.',
    ),
  ],
  warnings: ['No verified ADAU1701 addresses available.'],
  summary: '1 block. 0 verified. 1 requires capture.',
  status: SigmaMappingStatus.requiresCapture,
);

void main() {
  group('SigmaMappingReference — ADAU1466', () {
    late SigmaMappingReference ref;
    setUp(() => ref = _adau1466Reference());

    test('ADAU1466 reference includes verified Master Volume L mapping', () {
      final mv = ref.mappings
          .where((m) =>
              m.blockKind == SigmaBlockKind.masterVolume &&
              m.logicalName == 'Master Volume L')
          .firstOrNull;
      expect(mv, isNotNull);
      expect(mv!.mappingStatus, SigmaMappingStatus.mappedVerified);
      expect(mv.addressHex, '0x67');
    });

    test('ADAU1466 reference includes verified Master Volume R mapping', () {
      final mv = ref.mappings
          .where((m) =>
              m.blockKind == SigmaBlockKind.masterVolume &&
              m.logicalName == 'Master Volume R')
          .firstOrNull;
      expect(mv, isNotNull);
      expect(mv!.mappingStatus, SigmaMappingStatus.mappedVerified);
      expect(mv.addressHex, '0x64');
    });

    test('unverified PEQ mapping requires capture', () {
      final peq = ref.mappings
          .where((m) => m.blockKind == SigmaBlockKind.peq)
          .firstOrNull;
      expect(peq, isNotNull);
      expect(peq!.mappingStatus, SigmaMappingStatus.requiresCapture);
    });

    test('verifiedMappedCount is 2 (L and R)', () {
      expect(ref.verifiedMappedCount, 2);
    });

    test('requiresCaptureCount is 1', () {
      expect(ref.requiresCaptureCount, 1);
    });

    test('mappedCount includes verified + unverified mapped', () {
      expect(ref.mappedCount, 2);
    });
  });

  group('SigmaMappingReference — ADAU1701', () {
    late SigmaMappingReference ref;
    setUp(() => ref = _adau1701Reference());

    test('ADAU1701 default mapping requires capture', () {
      for (final m in ref.mappings) {
        expect(m.mappingStatus, SigmaMappingStatus.requiresCapture,
            reason: '${m.logicalName} must require capture for ADAU1701');
      }
    });

    test('status is requiresCapture', () {
      expect(ref.status, SigmaMappingStatus.requiresCapture);
    });
  });

  group('SigmaMappingReference — JSON', () {
    test('JSON round-trip works', () {
      final ref = _adau1466Reference();
      final json = ref.toJson();
      final restored = SigmaMappingReference.fromJson(json);

      expect(restored.mappings.length, ref.mappings.length);
      expect(restored.verifiedMappedCount, ref.verifiedMappedCount);
      expect(restored.requiresCaptureCount, ref.requiresCaptureCount);
      expect(restored.platform, DspTargetPlatform.adau1466);
      expect(restored.status, SigmaMappingStatus.partiallyMapped);
    });

    test('JSON contains no hardware write instruction fields', () {
      final ref = _adau1466Reference();
      final json = ref.toJson().toString();
      expect(json.toLowerCase(), isNot(contains('safeload')));
      expect(json.toLowerCase(), isNot(contains('eeprom')));
      expect(json.toLowerCase(), isNot(contains('selfboot')));
      expect(json.toLowerCase(), isNot(contains('usbi')));
      // 'directWriteValidated' and 'direct-write' are legitimate source labels — not instructions
    });

    test('SigmaParameterMapping JSON round-trip', () {
      const m = SigmaParameterMapping(
        id: 'test',
        platform: DspTargetPlatform.adau1466,
        blockKind: SigmaBlockKind.masterVolume,
        logicalName: 'Master Volume L',
        addressHex: '0x67',
        mappingStatus: SigmaMappingStatus.mappedVerified,
      );
      final restored = SigmaParameterMapping.fromJson(m.toJson());
      expect(restored.logicalName, 'Master Volume L');
      expect(restored.addressHex, '0x67');
      expect(restored.mappingStatus, SigmaMappingStatus.mappedVerified);
      expect(restored.blockKind, SigmaBlockKind.masterVolume);
    });
  });

  group('SigmaMappingStatus enum', () {
    test('toJson/fromJson round-trip', () {
      for (final s in SigmaMappingStatus.values) {
        expect(SigmaMappingStatus.fromJson(s.toJson()), s);
      }
    });
  });

  group('SigmaBlockKind enum', () {
    test('toJson/fromJson round-trip', () {
      for (final k in SigmaBlockKind.values) {
        expect(SigmaBlockKind.fromJson(k.toJson()), k);
      }
    });
  });
}
