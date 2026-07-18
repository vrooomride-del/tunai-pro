import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/adau1701_peq_preset.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';

void main() {
  group('Adau1701PeqPreset', () {
    test('selectable presets exclude custom; custom has no curve', () {
      expect(Adau1701PeqPresets.selectable, const [
        Adau1701PeqPreset.flat,
        Adau1701PeqPreset.neutral,
        Adau1701PeqPreset.warm,
        Adau1701PeqPreset.studioMonitor,
      ]);
      expect(Adau1701PeqPreset.custom.hasCurve, isFalse);
      for (final p in Adau1701PeqPresets.selectable) {
        expect(p.hasCurve, isTrue);
      }
    });

    test('labels', () {
      expect(Adau1701PeqPreset.flat.label, 'Flat');
      expect(Adau1701PeqPreset.neutral.label, 'Neutral');
      expect(Adau1701PeqPreset.warm.label, 'Warm');
      expect(Adau1701PeqPreset.studioMonitor.label, 'Studio Monitor');
      expect(Adau1701PeqPreset.custom.label, 'Custom');
    });

    test('custom throws (no fixed curve)', () {
      expect(() => Adau1701PeqPresets.bandsFor(Adau1701PeqPreset.custom),
          throwsArgumentError);
    });

    test('every preset yields exactly 10 fixed slots', () {
      for (final p in Adau1701PeqPresets.selectable) {
        expect(Adau1701PeqPresets.bandsFor(p), hasLength(10));
      }
    });

    test('Flat is all disabled / 0 dB', () {
      final bands = Adau1701PeqPresets.bandsFor(Adau1701PeqPreset.flat);
      expect(bands.every((b) => !b.enabled), isTrue);
      expect(Adau1701PeqResponse.enabledCount(bands), 0);
    });

    test('Neutral is a single very subtle correction', () {
      final bands = Adau1701PeqPresets.bandsFor(Adau1701PeqPreset.neutral);
      expect(Adau1701PeqResponse.enabledCount(bands), 1);
      final b = bands.firstWhere((b) => b.enabled);
      expect(b.gainDb.abs(), lessThanOrEqualTo(1.0));
    });

    test('Warm boosts lows and cuts upper treble', () {
      final bands = Adau1701PeqPresets.bandsFor(Adau1701PeqPreset.warm);
      final enabled = bands.where((b) => b.enabled).toList();
      expect(enabled.length, 3);
      // A low-frequency boost exists.
      expect(enabled.any((b) => b.frequencyHz < 300 && b.gainDb > 0), isTrue);
      // An upper-treble cut exists.
      expect(enabled.any((b) => b.frequencyHz >= 5000 && b.gainDb < 0), isTrue);
    });

    test('Studio Monitor adds presence/air', () {
      final bands =
          Adau1701PeqPresets.bandsFor(Adau1701PeqPreset.studioMonitor);
      final enabled = bands.where((b) => b.enabled).toList();
      expect(enabled.length, 3);
      expect(enabled.any((b) => b.frequencyHz >= 10000 && b.gainDb > 0), isTrue);
    });

    test('all preset bands stay within the conservative envelope', () {
      for (final p in Adau1701PeqPresets.selectable) {
        for (final b in Adau1701PeqPresets.bandsFor(p)) {
          expect(b.gainDb, inInclusiveRange(-3.0, 3.0),
              reason: '${p.label} gain out of ±3 dB');
          if (b.enabled) {
            expect(b.q, inInclusiveRange(0.7, 2.0),
                reason: '${p.label} Q out of 0.7..2.0');
          }
        }
      }
    });
  });
}
