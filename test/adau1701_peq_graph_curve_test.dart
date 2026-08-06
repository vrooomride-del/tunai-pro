// ADAU1701 PEQ graph curve calculation tests.
//
// Verifies the three graph modes against the MiUMAX Tweeter L reference:
//   Band7: 11000 Hz / -0.8 dB / Q0.8
//   Band8: 14500 Hz / -0.3 dB / Q0.8  (all other bands: gainDb=0.0 → flat)
//
// Groups:
//   1. peakingMagnitudeDb (negative gain / cut)
//   2. combinedCurve — Tweeter L reference produces a dip at 11 kHz / 14.5 kHz
//   3. Compare Difference — readback_dB − reference_dB via PeqGraphOverlayMath
//   4. peqReferenceToBands — curve input is populated from the reference definition

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_peq_reference.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_dsp_state_read_card.dart';
import 'package:tunai_pro/features/workbench/widgets/graph_overlay_models.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

PeqResponseBand _band(double freqHz, double gainDb, double q) =>
    PeqResponseBand(frequencyHz: freqHz, gainDb: gainDb, q: q, enabled: true);

List<double> _freqs(int count) =>
    Adau1701PeqResponse.logFrequencyPoints(count: count);

// Tweeter L reference converted to PeqResponseBands (same path the card uses).
List<PeqResponseBand> _tweeterLRefBands() =>
    peqReferenceToBands(Adau1701MiuMaxPeqReference.ch0Bands);

// 10 flat bands (0 dB gain) simulating a hardware readback with no EQ applied.
List<PeqResponseBand> _flatBands() => [
      for (var i = 0; i < 10; i++)
        _band(1000, 0.0, 1.0),
    ];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Group 1: peakingMagnitudeDb — negative gain (cut) ─────────────────────

  group('peakingMagnitudeDb — cut bands', () {
    test('Band7 −0.8 dB at 11000 Hz Q0.8 produces ≈ −0.8 dB at center', () {
      final band = _band(11000, -0.8, 0.8);
      final result = Adau1701PeqResponse.peakingMagnitudeDb(band, 11000);
      expect(result, closeTo(-0.8, 0.05));
    });

    test('Band8 −0.3 dB at 14500 Hz Q0.8 produces ≈ −0.3 dB at center', () {
      final band = _band(14500, -0.3, 0.8);
      final result = Adau1701PeqResponse.peakingMagnitudeDb(band, 14500);
      expect(result, closeTo(-0.3, 0.05));
    });

    test('Band7 cut is near-zero far from center (1000 Hz)', () {
      final band = _band(11000, -0.8, 0.8);
      final atLow = Adau1701PeqResponse.peakingMagnitudeDb(band, 1000).abs();
      expect(atLow, lessThan(0.1));
    });

    test('0 dB gain band returns exactly 0 (passthrough)', () {
      final band = _band(11000, 0.0, 0.8);
      expect(Adau1701PeqResponse.peakingMagnitudeDb(band, 11000), 0.0);
    });
  });

  // ── Group 2: combinedCurve — Tweeter L reference dips ─────────────────────

  group('combinedCurve — Tweeter L reference', () {
    final refBands = _tweeterLRefBands();
    final freqs = _freqs(200);

    test('Band7 (11000 Hz −0.8 dB) produces a negative dip at 11 kHz', () {
      final db = Adau1701PeqResponse.combinedMagnitudeDb(refBands, 11000);
      // Band8 (14500 Hz) tail also contributes; total is ~ −1 dB, not exactly −0.8.
      // The key assertion: the response is significantly negative (below −0.5 dB).
      expect(db, lessThan(-0.5));
    });

    test('Band8 (14500 Hz −0.3 dB) leaves the response negative at 14.5 kHz', () {
      final db = Adau1701PeqResponse.combinedMagnitudeDb(refBands, 14500);
      // Band7 (11000 Hz) tail also contributes; total is ~ −0.8 dB, not exactly −0.3.
      expect(db, lessThan(-0.2));
    });

    test('curve is close to 0 dB at 1000 Hz (no active band near this freq)', () {
      final db = Adau1701PeqResponse.combinedMagnitudeDb(refBands, 1000).abs();
      expect(db, lessThan(0.3));
    });

    test('curve has 200 points over the 20 Hz .. 20 kHz grid', () {
      final curve = Adau1701PeqResponse.combinedCurve(refBands, freqs);
      expect(curve.length, 200);
    });

    test('minimum of the curve is negative (a dip exists)', () {
      final curve = Adau1701PeqResponse.combinedCurve(refBands, freqs);
      expect(curve.reduce((a, b) => a < b ? a : b), lessThan(-0.1));
    });
  });

  // ── Group 3: Compare Difference — readback_dB − reference_dB ──────────────

  group('Compare Difference math (readback − reference)', () {
    final freqs = _freqs(200);

    test('flat readback vs Tweeter L ref: diff is positive at 11 kHz', () {
      // Readback is flat (0 dB). Reference has a cut at 11 kHz (−0.8 dB).
      // Difference = readback − reference = 0 − (negative) = positive.
      // Band8 tail also contributes so the exact value is ~ +0.99, not +0.8.
      final readbackCurve = Adau1701PeqResponse.combinedCurve(_flatBands(), freqs);
      final refCurve = Adau1701PeqResponse.combinedCurve(_tweeterLRefBands(), freqs);

      final diff = PeqGraphOverlayMath.difference(readbackCurve, refCurve)!;
      expect(diff.length, freqs.length);

      // Find a point near 11 kHz.
      final idx11k = freqs.indexWhere((f) => f >= 10500 && f <= 11500);
      expect(idx11k, isNot(-1), reason: 'no frequency point near 11000 Hz');
      // The diff must be positive (flat readback sounds louder than the cut reference).
      expect(diff[idx11k], greaterThan(0.5));
    });

    test('flat readback vs Tweeter L ref: diff is positive at 14.5 kHz', () {
      final readbackCurve = Adau1701PeqResponse.combinedCurve(_flatBands(), freqs);
      final refCurve = Adau1701PeqResponse.combinedCurve(_tweeterLRefBands(), freqs);
      final diff = PeqGraphOverlayMath.difference(readbackCurve, refCurve)!;

      // Any point in the 14–15 kHz region should show positive diff
      // (Band7 + Band8 both cut the reference there).
      final regionPoints = freqs
          .asMap()
          .entries
          .where((e) => e.value >= 14000 && e.value <= 15000)
          .map((e) => diff[e.key])
          .toList();
      expect(regionPoints, isNotEmpty);
      expect(regionPoints.every((d) => d > 0.2), isTrue,
          reason: 'expected positive diff in 14–15 kHz region');
    });

    test('readback equals reference → diff is ~0 everywhere', () {
      final refBands = _tweeterLRefBands();
      final curve = Adau1701PeqResponse.combinedCurve(refBands, freqs);
      final diff = PeqGraphOverlayMath.difference(curve, curve)!;
      for (final d in diff) {
        expect(d.abs(), lessThan(1e-10));
      }
    });

    test('difference returns null for mismatched curve lengths', () {
      final a = [0.0, 0.0, 0.0];
      final b = [0.0, 0.0];
      expect(PeqGraphOverlayMath.difference(a, b), isNull);
    });

    test('difference returns null for empty curves', () {
      expect(PeqGraphOverlayMath.difference([], []), isNull);
    });
  });

  // ── Group 4: peqReferenceToBands ─────────────────────────────────────────

  group('peqReferenceToBands — curve input from reference definition', () {
    test('Ch0 produces 10 enabled bands', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch0Bands);
      expect(bands.length, 10);
      expect(bands.every((b) => b.enabled), isTrue);
    });

    test('Ch0 Band7 (index 6) is 11000 Hz / −0.8 dB / Q0.8', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch0Bands);
      final b = bands[6];
      expect(b.frequencyHz, closeTo(11000.0, 0.1));
      expect(b.gainDb, closeTo(-0.8, 0.001));
      expect(b.q, closeTo(0.8, 0.001));
    });

    test('Ch0 Band8 (index 7) is 14500 Hz / −0.3 dB / Q0.8', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch0Bands);
      final b = bands[7];
      expect(b.frequencyHz, closeTo(14500.0, 0.1));
      expect(b.gainDb, closeTo(-0.3, 0.001));
      expect(b.q, closeTo(0.8, 0.001));
    });

    test('Ch0 bands with 0.0 dB gain contribute 0 to the curve', () {
      // Bands 1 (2500 Hz +1.0 dB), 6 (11000 Hz -0.8 dB), 7 (14500 Hz -0.3 dB)
      // have non-zero gain; all others must be flat.
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch0Bands);
      for (var i = 0; i < bands.length; i++) {
        if (i != 1 && i != 6 && i != 7) {
          expect(bands[i].gainDb, 0.0,
              reason: 'Ch0 band $i should have 0 dB gain');
        }
      }
    });
  });
}
