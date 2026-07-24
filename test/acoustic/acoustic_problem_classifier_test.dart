import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_classification_policy.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';
import 'package:tunai_pro/core/acoustic/measurement_evidence.dart';

final _policy = AcousticClassificationPolicy.proProvisional();

double _l2(double f) => math.log(f) / math.ln2;

List<double> _logGrid({double f0 = 20, double f1 = 20000, int perOct = 12}) {
  final out = <double>[];
  var f = f0;
  final r = math.pow(2, 1 / perOct).toDouble();
  while (f <= f1) {
    out.add(double.parse(f.toStringAsFixed(4)));
    f *= r;
  }
  return out;
}

List<double> _flat(List<double> f, [double level = 80]) =>
    [for (final _ in f) level];

/// Flat 80 dB target plus a Gaussian bump (dB) centered at [fc].
List<double> _bump(List<double> f,
        {required double fc,
        required double amp,
        required double sigmaOct,
        double level = 80}) =>
    [
      for (final x in f)
        level +
            amp *
                math.exp(
                    -math.pow(_l2(x) - _l2(fc), 2) / (2 * sigmaOct * sigmaOct))
    ];

List<double> _trend(List<double> f, double slopeDbPerOct,
        [double level = 80]) =>
    [for (final x in f) level + slopeDbPerOct * (_l2(x) - _l2(f.first))];

MetricOutcome _un(ConfidenceMetric m) => MetricOutcome.unavailable(m);

MeasurementConfidenceResult _conf({
  ConfidenceStatus status = ConfidenceStatus.valid,
  ConfidenceGrade grade = ConfidenceGrade.excellent,
  double? score = 0.9,
}) =>
    MeasurementConfidenceResult(
      status: status,
      grade: grade,
      overallScore: status == ConfidenceStatus.valid ? score : null,
      repeatability: _un(ConfidenceMetric.repeatability),
      snr: _un(ConfidenceMetric.snr),
      validBandCoverage: _un(ConfidenceMetric.validBandCoverage),
      clipping: _un(ConfidenceMetric.clipping),
      validBinCount: 10,
      requestedBinCount: 10,
      usableMinHz: 20,
      usableMaxHz: 300,
      reasons: const [],
      warnings: const [],
      unavailableMetrics: const [],
      policyId: 't',
      policyVersion: 1,
    );

AcousticClassificationInput _input(
  List<double> f,
  List<double> measured, {
  List<double>? target,
  MeasurementConfidenceResult? conf,
  MeasurementSource source = MeasurementSource.importedFrd,
  MeasurementDomain domain = MeasurementDomain.acousticResponse,
}) =>
    AcousticClassificationInput(
      frequenciesHz: f,
      measuredMagnitudeDb: measured,
      targetMagnitudeDb: target ?? _flat(f),
      measurementConfidence: conf ?? _conf(),
      measurementSource: source,
      measurementDomain: domain,
      evidenceRefs: const ['ev1'],
    );

AcousticClassificationResult _run(AcousticClassificationInput i) =>
    AcousticProblemClassifier.classify(i, _policy);

bool _has(AcousticClassificationResult r, AcousticFeatureType t) =>
    r.observedFeatures.any((f) => f.type == t);

void main() {
  final grid = _logGrid();

  group('input / invalid', () {
    test('1. flat response → no features', () {
      final r = _run(_input(grid, _flat(grid)));
      expect(r.status, AcousticClassificationStatus.ok);
      expect(r.observedFeatures, isEmpty);
    });
    test('2. measured == target → no features', () {
      final m = _flat(grid, 77);
      final r = _run(_input(grid, m, target: m));
      expect(r.observedFeatures, isEmpty);
    });
    test('3. non-ascending grid → invalidMeasurement', () {
      final r = _run(_input(<double>[100, 90, 110], <double>[80, 80, 80]));
      expect(r.status, AcousticClassificationStatus.invalidMeasurement);
    });
    test('4. length mismatch → invalidMeasurement', () {
      final r = _run(AcousticClassificationInput(
        frequenciesHz: const <double>[100, 200, 400],
        measuredMagnitudeDb: const <double>[80, 80],
        targetMagnitudeDb: const <double>[80, 80, 80],
        measurementConfidence: _conf(),
        measurementSource: MeasurementSource.importedFrd,
        measurementDomain: MeasurementDomain.acousticResponse,
      ));
      expect(r.status, AcousticClassificationStatus.invalidMeasurement);
    });
    test('5. NaN/Infinity → invalidMeasurement', () {
      final m = _flat(grid);
      m[5] = double.nan;
      expect(_run(_input(grid, m)).status,
          AcousticClassificationStatus.invalidMeasurement);
    });
    test('6. impedance domain / ZMA rejected', () {
      expect(
          _run(_input(grid, _flat(grid), domain: MeasurementDomain.impedance))
              .status,
          AcousticClassificationStatus.invalidMeasurement);
      expect(
          _run(_input(grid, _flat(grid), source: MeasurementSource.importedZma))
              .status,
          AcousticClassificationStatus.invalidMeasurement);
    });
    test('7. coverage too low → insufficientEvidence', () {
      final f = <double>[100, 150, 220, 330, 500]; // < minimumBins (8)
      final r = _run(_input(f, _flat(f)));
      expect(r.status, AcousticClassificationStatus.insufficientEvidence);
    });
  });

  group('features', () {
    test('9. narrow peak', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08)));
      expect(_has(r, AcousticFeatureType.narrowPeak), isTrue);
    });
    test('10. broad peak', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.6)));
      expect(_has(r, AcousticFeatureType.broadPeak), isTrue);
    });
    test('11. narrow dip', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: -6, sigmaOct: 0.08)));
      expect(_has(r, AcousticFeatureType.narrowDip), isTrue);
    });
    test('12. broad dip', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: -6, sigmaOct: 0.6)));
      expect(_has(r, AcousticFeatureType.broadDip), isTrue);
    });
    test('13. deep null', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: -16, sigmaOct: 0.15)));
      expect(_has(r, AcousticFeatureType.deepNull), isTrue);
    });
    test('14. rising trend', () {
      final r = _run(_input(grid, _trend(grid, 2.0)));
      expect(_has(r, AcousticFeatureType.risingTrend), isTrue);
      expect(_has(r, AcousticFeatureType.fallingTrend), isFalse);
    });
    test('15. falling trend', () {
      final r = _run(_input(grid, _trend(grid, -2.0)));
      expect(_has(r, AcousticFeatureType.fallingTrend), isTrue);
    });
    test('16. narrow peak on a trend is separated from the trend', () {
      final base = _trend(grid, 2.0);
      final peak = _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08, level: 0);
      final m = [for (var i = 0; i < grid.length; i++) base[i] + peak[i]];
      final r = _run(_input(grid, m));
      expect(_has(r, AcousticFeatureType.risingTrend), isTrue);
      expect(_has(r, AcousticFeatureType.narrowPeak), isTrue);
    });
    test('17. a single bump is not double-reported as narrow AND broad', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08)));
      final peaks = r.observedFeatures.where((f) =>
          f.type == AcousticFeatureType.narrowPeak ||
          f.type == AcousticFeatureType.broadPeak);
      expect(peaks.length, 1);
    });
    test('19. feature bandwidth/Q are populated and finite', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08)));
      final feat = r.observedFeatures
          .firstWhere((f) => f.type == AcousticFeatureType.narrowPeak);
      expect(feat.bandwidthOctaves > 0, isTrue);
      expect(feat.estimatedQ.isFinite, isTrue);
      expect(feat.centerHz, closeTo(1000, 200));
    });
    test('20/21. irregular / coarser grid → same feature type', () {
      final coarse = _logGrid(perOct: 6);
      final r =
          _run(_input(coarse, _bump(coarse, fc: 1000, amp: 6, sigmaOct: 0.12)));
      expect(
          _has(r, AcousticFeatureType.narrowPeak) ||
              _has(r, AcousticFeatureType.broadPeak),
          isTrue);
    });
  });

  group('actionability / confidence', () {
    test('22. narrow peak + good confidence → cut candidate', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08)));
      final feat = r.observedFeatures
          .firstWhere((f) => f.type == AcousticFeatureType.narrowPeak);
      expect(feat.actionability, AcousticActionability.safePeqCutCandidate);
    });
    test('23. narrow dip is not a boost candidate', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: -6, sigmaOct: 0.08)));
      final feat = r.observedFeatures
          .firstWhere((f) => f.type == AcousticFeatureType.narrowDip);
      expect(
          feat.actionability, isNot(AcousticActionability.safePeqCutCandidate));
      expect(feat.actionability,
          isNot(AcousticActionability.cautiousBroadCorrection));
    });
    test('24. deep null → doNotBoost', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: -16, sigmaOct: 0.15)));
      final feat = r.observedFeatures
          .firstWhere((f) => f.type == AcousticFeatureType.deepNull);
      expect(feat.actionability, AcousticActionability.doNotBoost);
      expect(r.blockedAutomaticCorrections,
          contains(AcousticFeatureType.deepNull));
    });
    test('25. insufficientEvidence → analysis ok, no auto correction', () {
      final r = _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08),
          conf: _conf(status: ConfidenceStatus.insufficientEvidence)));
      expect(r.status, AcousticClassificationStatus.ok);
      expect(r.confidenceInterpretation,
          MeasurementConfidenceInterpretation.analysisOnly);
      final feat = r.observedFeatures
          .firstWhere((f) => f.type == AcousticFeatureType.narrowPeak);
      expect(feat.actionability, AcousticActionability.noAutomaticCorrection);
    });
    test('26. invalid confidence → remeasure', () {
      final r = _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08),
          conf: _conf(status: ConfidenceStatus.invalid)));
      expect(r.confidenceInterpretation,
          MeasurementConfidenceInterpretation.remeasure);
      final feat = r.observedFeatures.first;
      expect(feat.actionability, AcousticActionability.remeasureRequired);
    });
    test('27. poor confidence → conservative (no plain cut candidate)', () {
      final r = _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08),
          conf: _conf(grade: ConfidenceGrade.poor, score: 0.4)));
      expect(r.confidenceInterpretation,
          MeasurementConfidenceInterpretation.conservative);
      final feat = r.observedFeatures
          .firstWhere((f) => f.type == AcousticFeatureType.narrowPeak);
      expect(feat.actionability, AcousticActionability.cautiousBroadCorrection);
    });
    test('28. imported single FRD (insufficient) → features but no auto', () {
      final r = _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08),
          conf: _conf(status: ConfidenceStatus.insufficientEvidence)));
      expect(r.observedFeatures, isNotEmpty);
      expect(
          r.observedFeatures.every((f) =>
              f.actionability != AcousticActionability.safePeqCutCandidate),
          isTrue);
    });
  });

  group('determinism / boundary', () {
    test('29/30. same input+policy → identical result and ids', () {
      final a =
          _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08)));
      final b =
          _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08)));
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
      expect(a.observedFeatures.map((f) => f.featureId),
          b.observedFeatures.map((f) => f.featureId));
    });
    test('31/32. no DSP gain/Q/coefficient/address/payload in output', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08)));
      final json = jsonEncode(r.toJson()).toLowerCase();
      for (final t in [
        'proposedgain',
        'gaindb',
        'correctionq',
        'biquad',
        'coefficient',
        'address',
        'payload',
        'peqband'
      ]) {
        expect(json.contains(t), isFalse, reason: t);
      }
    });
    test('33. no cause enum (roomMode/boundary/crossover) in output', () {
      final r =
          _run(_input(grid, _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.08)));
      final json = jsonEncode(r.toJson()).toLowerCase();
      for (final t in ['roommode', 'boundary', 'crossover', 'polarity']) {
        expect(json.contains(t), isFalse, reason: t);
      }
    });
    test('34. policy change moves the narrow/broad boundary', () {
      final measured = _bump(grid, fc: 1000, amp: 6, sigmaOct: 0.2);
      const narrowPolicy = AcousticClassificationPolicy(
        id: 'narrow',
        version: 1,
        analysisMinHz: 20,
        analysisMaxHz: 20000,
        localBaselineWindowOctaves: 1.0,
        minimumProminenceDb: 1.5,
        narrowFeatureMaxWidthOctaves: 0.1, // stricter → this bump is broad
        deepNullDepthDb: -10,
        deepNullMinimumWidthOctaves: 0.1,
        trendMinimumSpanOctaves: 2.0,
        trendSlopeThresholdDbPerOctave: 1.0,
        minimumBins: 8,
        minimumBinsPerFeature: 3,
        minimumFeatureSeparationOctaves: 0.25,
      );
      final wide = AcousticProblemClassifier.classify(
          _input(grid, measured), narrowPolicy);
      expect(
          wide.observedFeatures
              .any((f) => f.type == AcousticFeatureType.broadPeak),
          isTrue);
    });
    test('35. provisional policy id/version preserved', () {
      final r = _run(_input(grid, _flat(grid)));
      expect(r.policyId, 'pro_provisional');
      expect(r.policyVersion, 1);
    });
  });
}
