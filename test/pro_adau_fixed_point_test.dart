// TUNAI PRO — Phase P: ADAU Fixed-Point conversion tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau_fixed_point.dart';

void main() {
  group('AdauFixedPointConverter 8.24', () {
    test('1.0 converts to expected 8.24 raw value (2^24)', () {
      final result = AdauFixedPointConverter.to824(1.0);
      expect(result.rawInt, 16777216); // 2^24
      expect(result.format, AdauFixedPointFormat.format824);
    });

    test('1.0 hex is 0x01000000', () {
      final result = AdauFixedPointConverter.to824(1.0);
      expect(result.hex, '0x01000000');
    });

    test('0.0 converts to raw 0', () {
      final result = AdauFixedPointConverter.to824(0.0);
      expect(result.rawInt, 0);
      expect(result.hex, '0x00000000');
    });

    test('0.5 converts to expected raw (2^23)', () {
      final result = AdauFixedPointConverter.to824(0.5);
      expect(result.rawInt, 8388608); // 2^23
    });

    test('negative value converts safely', () {
      final result = AdauFixedPointConverter.to824(-1.0);
      expect(result.rawInt, -16777216);
      expect(result.status, isNot(AdauCoefficientStatus.notConverted));
    });

    test('conversion status is convertedDraft for normal values', () {
      final result = AdauFixedPointConverter.to824(0.5);
      expect(result.status, AdauCoefficientStatus.convertedDraft);
    });

    test('overflow value sets requiresVerification status', () {
      final result = AdauFixedPointConverter.to824(1000.0);
      expect(result.status, AdauCoefficientStatus.requiresVerification);
    });

    test('warning includes draft verification wording', () {
      final result = AdauFixedPointConverter.to824(0.5);
      expect(result.warning, isNotNull);
      expect(result.warning!.toLowerCase(), contains('draft'));
      expect(result.warning!.toLowerCase(), contains('verif'));
    });

    test('non-finite input returns requiresVerification', () {
      final nanResult = AdauFixedPointConverter.to824(double.nan);
      expect(nanResult.status, AdauCoefficientStatus.requiresVerification);
      final infResult = AdauFixedPointConverter.to824(double.infinity);
      expect(infResult.status, AdauCoefficientStatus.requiresVerification);
    });

    test('result contains no hardware address fields', () {
      final result = AdauFixedPointConverter.to824(0.5);
      final json = result.toJson();
      expect(json.containsKey('address'), isFalse);
      expect(json.containsKey('register'), isFalse);
      expect(json.containsKey('safeload'), isFalse);
      expect(json.containsKey('eeprom'), isFalse);
    });

    test('JSON round-trip preserves values', () {
      final result = AdauFixedPointConverter.to824(0.75);
      final restored = AdauFixedPointValue.fromJson(result.toJson());
      expect(restored.rawInt, result.rawInt);
      expect(restored.hex, result.hex);
      expect(restored.status, result.status);
      expect(restored.format, AdauFixedPointFormat.format824);
    });

    test('biquadCoefficients824 converts list correctly', () {
      final coeffs = [1.0, -1.5, 0.75, -0.5, 0.25];
      final results = AdauFixedPointConverter.biquadCoefficients824(coeffs);
      expect(results.length, 5);
      for (final r in results) {
        expect(r.format, AdauFixedPointFormat.format824);
      }
    });
  });

  group('AdauFixedPointConverter other formats', () {
    test('to528 returns unsupported', () {
      final result = AdauFixedPointConverter.to528(1.0);
      expect(result.status, AdauCoefficientStatus.unsupported);
      expect(result.format, AdauFixedPointFormat.format528);
    });

    test('to1616 returns unsupported', () {
      final result = AdauFixedPointConverter.to1616(1.0);
      expect(result.status, AdauCoefficientStatus.unsupported);
      expect(result.format, AdauFixedPointFormat.format1616);
    });
  });

  group('AdauFixedPointFormat', () {
    test('toJson/fromJson round-trip', () {
      for (final f in AdauFixedPointFormat.values) {
        expect(AdauFixedPointFormat.fromJson(f.toJson()), f);
      }
    });
  });

  group('AdauCoefficientStatus', () {
    test('toJson/fromJson round-trip', () {
      for (final s in AdauCoefficientStatus.values) {
        expect(AdauCoefficientStatus.fromJson(s.toJson()), s);
      }
    });
  });
}
