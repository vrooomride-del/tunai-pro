import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';

/// A permissive policy for exercising the math: no required metric, all weights,
/// evidence-backed 6 dB ceiling, minimal bin gate.
const _allMetrics = MeasurementConfidencePolicy(
  id: 'test_all',
  version: 7,
  requiredMetrics: {},
  minValidBinCount: 1,
  minValidBandCoverage: 0.0,
  repeatabilityCeilingDb: 6.0,
  repeatabilityThreshold: 0.5,
  snrScoreCeilingDb: 20.0,
  clippingCeilingRatio: 0.01,
  weights: {
    ConfidenceMetric.repeatability: 0.5,
    ConfidenceMetric.validBandCoverage: 0.3,
    ConfidenceMetric.snr: 0.15,
    ConfidenceMetric.clipping: 0.05,
  },
  gradeThresholds: ConfidenceGradeThresholds(
      excellentMin: 0.85, goodMin: 0.70, usableMin: 0.50),
);

/// A grid of [count] ascending frequencies inside 20–300 Hz.
List<double> _grid(int count) =>
    [for (var i = 0; i < count; i++) 30.0 + i * 20.0];

MeasurementConfidenceMetrics _metrics({
  required List<double> freqs,
  required List<List<double>> spectraDb,
  double minBandHz = 20,
  double maxBandHz = 300,
  double? signalPower,
  double? noisePower,
  int? clippedSamples,
  int? totalSamples,
}) =>
    MeasurementConfidenceMetrics(
      frequencies: freqs,
      spectraDb: spectraDb,
      minBandHz: minBandHz,
      maxBandHz: maxBandHz,
      signalPower: signalPower,
      noisePower: noisePower,
      clippedSamples: clippedSamples,
      totalSamples: totalSamples,
    );

double _db(double linear) => 10 * math.log(linear) / math.ln10;

/// Reference reimplementation of the Consumer split-half arithmetic, to prove
/// equivalence (NOT a copy of the engine under test).
double _consumerAgreement(
    List<double> powerA, List<double> powerB, List<double> freqs) {
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < freqs.length; i++) {
    final f = freqs[i];
    if (f < 20 || f > 300) continue;
    final a = powerA[i];
    final b = powerB[i];
    if (a <= 0 || b <= 0) continue;
    sum += (10 * math.log(a) / math.ln10 - 10 * math.log(b) / math.ln10).abs();
    count++;
  }
  if (count == 0) return 0;
  return (1 - (sum / count) / 6.0).clamp(0.0, 1.0);
}

void main() {
  group('Consumer equivalence', () {
    test('1. matches the Consumer split-half formula on the same fixture', () {
      final freqs = _grid(10);
      final powerA = [for (var i = 0; i < 10; i++) 1.0 + i * 0.1];
      final powerB = [for (var i = 0; i < 10; i++) 1.0 + i * 0.1 + 0.3];
      final expected = _consumerAgreement(powerA, powerB, freqs);

      final r = MeasurementConfidenceEngine.evaluate(
        _metrics(
          freqs: freqs,
          spectraDb: [
            [for (final p in powerA) _db(p)],
            [for (final p in powerB) _db(p)],
          ],
        ),
        _allMetrics,
      );
      expect(r.repeatability.isAvailable, isTrue);
      expect(r.repeatability.score!, closeTo(expected, 1e-9));
    });

    test('2. identical spectra → repeatability 1.0', () {
      final freqs = _grid(10);
      final s = [for (var i = 0; i < 10; i++) -3.0 - i];
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: freqs, spectraDb: [s, List.of(s)]), _allMetrics);
      expect(r.repeatability.score, 1.0);
      expect(r.repeatability.rawValue, 0.0);
    });

    test('3. widely different spectra → low repeatability', () {
      final freqs = _grid(10);
      final a = [for (var i = 0; i < 10; i++) 0.0];
      final b = [for (var i = 0; i < 10; i++) 10.0]; // 10 dB apart > 6 ceiling
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: freqs, spectraDb: [a, b]), _allMetrics);
      expect(r.repeatability.score, 0.0);
    });

    test('4. Consumer band edges (20/300) are respected', () {
      // Bins outside 20–300 must not contribute; put a huge disagreement above
      // 300 Hz and confirm it is ignored.
      final freqs = [50.0, 100.0, 200.0, 5000.0];
      final a = [0.0, 0.0, 0.0, 0.0];
      final b = [0.0, 0.0, 0.0, 100.0]; // only the 5 kHz bin differs
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: freqs, spectraDb: [a, b], minBandHz: 20, maxBandHz: 300),
          _allMetrics);
      expect(r.repeatability.score, 1.0); // in-band bins are identical
    });
  });

  group('SNR', () {
    test('5. known signal/noise → expected dB and score', () {
      final r = MeasurementConfidenceEngine.evaluate(
        _metrics(
            freqs: _grid(10),
            spectraDb: [for (var k = 0; k < 2; k++) List.filled(10, 0.0)],
            signalPower: 100.0,
            noisePower: 1.0),
        _allMetrics,
      );
      expect(r.snr.isAvailable, isTrue);
      expect(r.snr.rawValue!, closeTo(20.0, 1e-9));
      expect(r.snr.score, 1.0); // 20 dB == ceiling
    });
    test('6. noisePower = 0 → SNR unavailable (not invented)', () {
      final r = MeasurementConfidenceEngine.evaluate(
        _metrics(
            freqs: _grid(10),
            spectraDb: [for (var k = 0; k < 2; k++) List.filled(10, 0.0)],
            signalPower: 100.0,
            noisePower: 0.0),
        _allMetrics,
      );
      expect(r.snr.status, MetricStatus.unavailable);
      expect(r.snr.score, isNull);
    });
    test('7. no signal/noise → SNR unavailable', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: _grid(10),
              spectraDb: [for (var k = 0; k < 2; k++) List.filled(10, 0.0)]),
          _allMetrics);
      expect(r.snr.status, MetricStatus.unavailable);
      expect(r.unavailableMetrics, contains(ConfidenceMetric.snr));
    });
  });

  group('Coverage / invalid data', () {
    test('9. all finite in-band bins → coverage 1.0', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: _grid(10),
              spectraDb: [for (var k = 0; k < 2; k++) List.filled(10, 0.0)]),
          _allMetrics);
      expect(r.validBandCoverage.score, 1.0);
      expect(r.validBinCount, 10);
    });
    test('10. NaN/Infinity bins are excluded from coverage', () {
      final freqs = _grid(10);
      final a = List.filled(10, 0.0);
      final b = List.filled(10, 0.0);
      a[3] = double.nan;
      b[7] = double.infinity;
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: freqs, spectraDb: [a, b]), _allMetrics);
      expect(r.validBinCount, 8);
      expect(r.validBandCoverage.rawValue, closeTo(0.8, 1e-9));
    });
    test('11. too few valid bins → insufficientEvidence', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: _grid(10),
              spectraDb: [for (var k = 0; k < 2; k++) List.filled(10, 0.0)]),
          MeasurementConfidencePolicy.proProvisional()); // minValidBinCount 8
      // grid(10) all valid → 10 ≥ 8, so instead shrink: use a 3-bin grid.
      final r2 = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: _grid(3),
              spectraDb: [for (var k = 0; k < 2; k++) List.filled(3, 0.0)]),
          MeasurementConfidencePolicy.proProvisional());
      expect(r.status, isNot(ConfidenceStatus.invalid));
      expect(r2.status, ConfidenceStatus.insufficientEvidence);
    });
    test('12. grid/spectrum length mismatch → invalid', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: _grid(10), spectraDb: [
            List.filled(10, 0.0),
            List.filled(9, 0.0),
          ]),
          _allMetrics);
      expect(r.status, ConfidenceStatus.invalid);
    });
    test('13. non-ascending (or duplicate) grid → invalid', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: [
            50,
            40,
            60
          ], spectraDb: [
            [0, 0, 0],
            [0, 0, 0]
          ]),
          _allMetrics);
      expect(r.status, ConfidenceStatus.invalid);
    });
    test('14. zero/negative frequency → invalid', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: [
            0,
            50,
            100
          ], spectraDb: [
            [0, 0, 0],
            [0, 0, 0]
          ]),
          _allMetrics);
      expect(r.status, ConfidenceStatus.invalid);
    });
    test('15. empty input → invalid', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: const [], spectraDb: const []), _allMetrics);
      expect(r.status, ConfidenceStatus.invalid);
    });
  });

  group('Clipping', () {
    test('16. known clipped/total → ratio and score', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: _grid(10),
              spectraDb: [for (var k = 0; k < 2; k++) List.filled(10, 0.0)],
              clippedSamples: 1,
              totalSamples: 100),
          _allMetrics);
      expect(r.clipping.rawValue, closeTo(0.01, 1e-12));
      expect(r.clipping.score, 0.0); // ratio == ceiling
    });
    test('17. clipping counts absent → unavailable', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: _grid(10),
              spectraDb: [for (var k = 0; k < 2; k++) List.filled(10, 0.0)]),
          _allMetrics);
      expect(r.clipping.status, MetricStatus.unavailable);
    });
    test('18. clipped > total → invalid', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: _grid(10),
              spectraDb: [for (var k = 0; k < 2; k++) List.filled(10, 0.0)],
              clippedSamples: 200,
              totalSamples: 100),
          _allMetrics);
      expect(r.status, ConfidenceStatus.invalid);
    });
    test('19. total = 0 → invalid', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: _grid(10),
              spectraDb: [for (var k = 0; k < 2; k++) List.filled(10, 0.0)],
              clippedSamples: 0,
              totalSamples: 0),
          _allMetrics);
      expect(r.status, ConfidenceStatus.invalid);
    });
  });

  group('Policy / scoring', () {
    test('20. required metric missing → insufficientEvidence', () {
      // proProvisional requires repeatability; a single spectrum lacks it.
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: _grid(10), spectraDb: [List.filled(10, 0.0)]),
          MeasurementConfidencePolicy.proProvisional());
      expect(r.status, ConfidenceStatus.insufficientEvidence);
      expect(r.overallScore, isNull);
      expect(r.grade, ConfidenceGrade.unavailable);
    });
    test('21. optional metric missing → remaining weights renormalised', () {
      // No SNR, no clipping → only repeatability(0.5) + coverage(0.3) present.
      final freqs = _grid(10);
      final a = List.filled(10, 0.0);
      final b = List.filled(10, 0.0); // identical → repeatability 1.0
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: freqs, spectraDb: [a, b]), _allMetrics);
      // (0.5*1.0 + 0.3*1.0) / (0.5+0.3) = 1.0
      expect(r.overallScore, closeTo(1.0, 1e-9));
      expect(r.status, ConfidenceStatus.valid);
    });
    test('22. no weighted metric available → unavailable/insufficient', () {
      const snrOnly = MeasurementConfidencePolicy(
        id: 'snr_only',
        version: 1,
        requiredMetrics: {},
        minValidBinCount: 1,
        minValidBandCoverage: 0.0,
        repeatabilityCeilingDb: 6.0,
        repeatabilityThreshold: 0.5,
        snrScoreCeilingDb: 20.0,
        clippingCeilingRatio: 0.01,
        weights: {ConfidenceMetric.snr: 1.0}, // only SNR weighted
        gradeThresholds: ConfidenceGradeThresholds(
            excellentMin: 0.85, goodMin: 0.7, usableMin: 0.5),
      );
      // Single spectrum, no SNR provided → SNR unavailable → weightSum 0.
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: _grid(10), spectraDb: [List.filled(10, 0.0)]),
          snrOnly);
      expect(r.overallScore, isNull);
      expect(r.grade, ConfidenceGrade.unavailable);
      expect(r.status, ConfidenceStatus.insufficientEvidence);
    });
    test('23. overall score is within 0..1', () {
      final freqs = _grid(10);
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: freqs,
              spectraDb: [
                List.filled(10, 0.0),
                [for (var i = 0; i < 10; i++) 2.0]
              ],
              signalPower: 50,
              noisePower: 1,
              clippedSamples: 0,
              totalSamples: 1000),
          _allMetrics);
      expect(r.overallScore, isNotNull);
      expect(r.overallScore! >= 0 && r.overallScore! <= 1, isTrue);
    });
    test('24. grade thresholds map at the boundaries', () {
      const t = ConfidenceGradeThresholds(
          excellentMin: 0.85, goodMin: 0.70, usableMin: 0.50);
      expect(t.gradeFor(0.85), ConfidenceGrade.excellent);
      expect(t.gradeFor(0.70), ConfidenceGrade.good);
      expect(t.gradeFor(0.50), ConfidenceGrade.usable);
      expect(t.gradeFor(0.4999), ConfidenceGrade.poor);
    });
    test('25. reasons/warnings are populated', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(freqs: _grid(10), spectraDb: [
            List.filled(10, 0.0),
            [for (var i = 0; i < 10; i++) 4.0] // repeatability below 0.5
          ]),
          _allMetrics);
      expect(r.reasons, isNotEmpty);
      expect(r.warnings, isNotEmpty); // repeatability + SNR/clipping notes
    });
    test('26. policy id/version are preserved', () {
      final r = MeasurementConfidenceEngine.evaluate(
          _metrics(
              freqs: _grid(10),
              spectraDb: [List.filled(10, 0.0), List.filled(10, 0.0)]),
          _allMetrics);
      expect(r.policyId, 'test_all');
      expect(r.policyVersion, 7);
    });
  });

  group('Determinism / output safety', () {
    MeasurementConfidenceResult run() => MeasurementConfidenceEngine.evaluate(
        _metrics(
            freqs: _grid(10),
            spectraDb: [
              List.filled(10, 0.0),
              [for (var i = 0; i < 10; i++) 1.5]
            ],
            signalPower: 40,
            noisePower: 2,
            clippedSamples: 3,
            totalSamples: 5000),
        _allMetrics);

    test('27/28. identical input → identical result (no time/random)', () {
      final a = run();
      final b = run();
      expect(a.overallScore, b.overallScore);
      expect(a.grade, b.grade);
      expect(a.repeatability.score, b.repeatability.score);
      expect(a.snr.rawValue, b.snr.rawValue);
      expect(a.clipping.rawValue, b.clipping.rawValue);
    });
    test('29. no NaN/Infinity in outputs', () {
      final r = run();
      expect(r.overallScore!.isFinite, isTrue);
      for (final m in [
        r.repeatability,
        r.snr,
        r.validBandCoverage,
        r.clipping
      ]) {
        if (m.isAvailable) {
          expect(m.score!.isFinite, isTrue);
          expect(m.rawValue!.isFinite, isTrue);
        }
      }
    });
  });
}
