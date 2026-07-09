// TUNAI PRO — Phase P: DSP Address Registry tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_dsp_address_registry.dart';
import 'package:tunai_pro/core/pro_export_data.dart';

void main() {
  group('DspAddressRegistry — default', () {
    late DspAddressRegistry registry;

    setUp(() => registry = DspAddressRegistry.createDefault());

    test('default registry contains ADAU1466 Master Volume L 0x67', () {
      final addr = registry.findByLogicalName('Master Volume L');
      expect(addr, isNotNull);
      expect(addr!.platform, DspTargetPlatform.adau1466);
      expect(addr.addressHex, '0x67');
      expect(addr.addressInt, 0x67);
    });

    test('default registry contains ADAU1466 Master Volume R 0x64', () {
      final addr = registry.findByLogicalName('Master Volume R');
      expect(addr, isNotNull);
      expect(addr!.platform, DspTargetPlatform.adau1466);
      expect(addr.addressHex, '0x64');
      expect(addr.addressInt, 0x64);
    });

    test('master volume addresses are verified', () {
      for (final addr in registry.addresses) {
        if (addr.parameterKind == DspParameterKind.masterVolume) {
          expect(addr.verificationStatus,
              DspAddressVerificationStatus.verified,
              reason: '${addr.logicalName} must be verified');
        }
      }
    });

    test('hasVerifiedMasterVolume1466 returns true', () {
      expect(registry.hasVerifiedMasterVolume1466, isTrue);
    });

    test('verifiedCount reflects 2 known addresses', () {
      expect(registry.verifiedCount, 2);
    });

    test('no PEQ/XO/Gain/Delay/Mute addresses are invented in default registry', () {
      final forbidden = [
        DspParameterKind.peq,
        DspParameterKind.crossover,
        DspParameterKind.gain,
        DspParameterKind.delay,
        DspParameterKind.mute,
        DspParameterKind.safeload,
      ];
      for (final addr in registry.addresses) {
        expect(forbidden, isNot(contains(addr.parameterKind)),
            reason: 'Only master volume addresses are allowed in default registry; '
                'found ${addr.parameterKind.name}');
      }
    });

    test('addressesForPlatform filters correctly', () {
      final adau1466 = registry.addressesForPlatform(DspTargetPlatform.adau1466);
      expect(adau1466.length, 2);
      final adau1701 = registry.addressesForPlatform(DspTargetPlatform.adau1701);
      expect(adau1701.isEmpty, isTrue);
    });

    test('JSON round-trip preserves addresses', () {
      final json = registry.toJson();
      final restored = DspAddressRegistry.fromJson(json);

      expect(restored.addresses.length, registry.addresses.length);
      expect(restored.verifiedCount, registry.verifiedCount);

      final l = restored.findByLogicalName('Master Volume L');
      expect(l!.addressHex, '0x67');
      expect(l.verificationStatus, DspAddressVerificationStatus.verified);

      final r = restored.findByLogicalName('Master Volume R');
      expect(r!.addressHex, '0x64');
      expect(r.verificationStatus, DspAddressVerificationStatus.verified);
    });

    test('toJson contains no hardware write instructions', () {
      final json = registry.toJson().toString();
      expect(json.toLowerCase(), isNot(contains('safeload')));
      expect(json.toLowerCase(), isNot(contains('eeprom')));
      expect(json.toLowerCase(), isNot(contains('selfboot')));
      expect(json.toLowerCase(), isNot(contains('usbi')));
    });
  });

  group('DspAddressVerificationStatus', () {
    test('toJson/fromJson round-trip', () {
      for (final s in DspAddressVerificationStatus.values) {
        expect(DspAddressVerificationStatus.fromJson(s.toJson()), s);
      }
    });
  });

  group('DspAddressSource', () {
    test('toJson/fromJson round-trip', () {
      for (final s in DspAddressSource.values) {
        expect(DspAddressSource.fromJson(s.toJson()), s);
      }
    });
  });

  group('DspParameterKind', () {
    test('toJson/fromJson round-trip', () {
      for (final k in DspParameterKind.values) {
        expect(DspParameterKind.fromJson(k.toJson()), k);
      }
    });
  });
}
