import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';

void main() {
  group('logFrequencyPoints', () {
    test('spans 20 Hz .. 20 kHz inclusive and is monotonic', () {
      final pts = Adau1701PeqResponse.logFrequencyPoints(count: 128);
      expect(pts.first, closeTo(20, 1e-6));
      expect(pts.last, closeTo(20000, 1e-6));
      for (var i = 1; i < pts.length; i++) {
        expect(pts[i], greaterThan(pts[i - 1]));
      }
    });
  });

  group('peakingMagnitudeDb', () {
    test('peaks near the band gain at the centre frequency', () {
      const band =
          PeqResponseBand(frequencyHz: 1000, gainDb: 6, q: 2, enabled: true);
      final atCentre = Adau1701PeqResponse.peakingMagnitudeDb(band, 1000);
      expect(atCentre, closeTo(6.0, 0.3));
    });

    test('is ~0 dB far from the centre frequency', () {
      const band =
          PeqResponseBand(frequencyHz: 1000, gainDb: 6, q: 4, enabled: true);
      expect(Adau1701PeqResponse.peakingMagnitudeDb(band, 40).abs(),
          lessThan(1.0));
      expect(Adau1701PeqResponse.peakingMagnitudeDb(band, 16000).abs(),
          lessThan(1.5));
    });

    test('a disabled band contributes 0 dB', () {
      const band =
          PeqResponseBand(frequencyHz: 1000, gainDb: 6, q: 2, enabled: false);
      expect(Adau1701PeqResponse.peakingMagnitudeDb(band, 1000), 0);
    });
  });

  group('combinedMagnitudeDb / combinedCurve', () {
    final freqs = Adau1701PeqResponse.logFrequencyPoints(count: 200);

    test('0 active bands → flat 0 dB everywhere', () {
      final bands = [
        for (var i = 0; i < 10; i++)
          const PeqResponseBand(
              frequencyHz: 1000, gainDb: 6, q: 2, enabled: false),
      ];
      expect(Adau1701PeqResponse.enabledCount(bands), 0);
      final curve = Adau1701PeqResponse.combinedCurve(bands, freqs);
      expect(curve.length, freqs.length);
      expect(curve.every((db) => db == 0), isTrue);
    });

    test('1 active band → single peak at its centre', () {
      final bands = [
        const PeqResponseBand(
            frequencyHz: 1000, gainDb: 6, q: 3, enabled: true),
        for (var i = 0; i < 9; i++)
          const PeqResponseBand(
              frequencyHz: 500, gainDb: 4, q: 2, enabled: false),
      ];
      expect(Adau1701PeqResponse.enabledCount(bands), 1);
      final peak = Adau1701PeqResponse.combinedMagnitudeDb(bands, 1000);
      expect(peak, closeTo(6.0, 0.3));
      // The disabled 500 Hz bands do not contribute.
      expect(Adau1701PeqResponse.combinedMagnitudeDb(bands, 500).abs(),
          lessThan(2.0));
    });

    test('multiple active bands sum at a shared centre', () {
      final bands = [
        const PeqResponseBand(
            frequencyHz: 1000, gainDb: 4, q: 2, enabled: true),
        const PeqResponseBand(
            frequencyHz: 1000, gainDb: 4, q: 2, enabled: true),
      ];
      expect(Adau1701PeqResponse.enabledCount(bands), 2);
      final peak = Adau1701PeqResponse.combinedMagnitudeDb(bands, 1000);
      expect(peak, closeTo(8.0, 0.6)); // ~4 + 4 dB
    });

    test('disabled bands are excluded from the combined curve', () {
      final enabled = [
        const PeqResponseBand(
            frequencyHz: 1000, gainDb: 6, q: 2, enabled: true),
      ];
      final withDisabledExtra = [
        ...enabled,
        const PeqResponseBand(
            frequencyHz: 1000, gainDb: 6, q: 2, enabled: false),
      ];
      // Adding a disabled band must not change the curve at all.
      final a = Adau1701PeqResponse.combinedCurve(enabled, freqs);
      final b = Adau1701PeqResponse.combinedCurve(withDisabledExtra, freqs);
      for (var i = 0; i < a.length; i++) {
        expect(b[i], a[i]);
      }
    });
  });

  group('autoScaleDbRange (Y-axis symmetric range)', () {
    test('a flat/small curve uses the tight ±6 dB default', () {
      expect(Adau1701PeqResponse.autoScaleDbRange(const [0, 0, 0]), 6);
      expect(Adau1701PeqResponse.autoScaleDbRange(const [3.5, -2.0, 0]), 6);
      expect(Adau1701PeqResponse.autoScaleDbRange(const [6, -6]), 6);
    });

    test('widens to ±9 dB only when the peak exceeds 6 dB', () {
      expect(Adau1701PeqResponse.autoScaleDbRange(const [6.1]), 9);
      expect(Adau1701PeqResponse.autoScaleDbRange(const [-8.5, 2]), 9);
      expect(Adau1701PeqResponse.autoScaleDbRange(const [9, -9]), 9);
    });

    test('widens to ±12 dB for larger swings and caps there', () {
      expect(Adau1701PeqResponse.autoScaleDbRange(const [9.1]), 12);
      expect(Adau1701PeqResponse.autoScaleDbRange(const [-11]), 12);
      expect(Adau1701PeqResponse.autoScaleDbRange(const [20, -30]), 12);
    });

    test('is symmetric about 0 (uses magnitude of both boost and cut)', () {
      expect(Adau1701PeqResponse.autoScaleDbRange(const [-7]), 9);
      expect(Adau1701PeqResponse.autoScaleDbRange(const [7]), 9);
    });

    test('a real two-band example (80 Hz +3.5, 350 Hz -2.0) stays at ±6', () {
      final bands = [
        const PeqResponseBand(
            frequencyHz: 80, gainDb: 3.5, q: 1.0, enabled: true),
        const PeqResponseBand(
            frequencyHz: 350, gainDb: -2.0, q: 1.0, enabled: true),
      ];
      final curve = Adau1701PeqResponse.combinedCurve(
          bands, Adau1701PeqResponse.logFrequencyPoints(count: 200));
      expect(Adau1701PeqResponse.autoScaleDbRange(curve), 6);
    });
  });
}
