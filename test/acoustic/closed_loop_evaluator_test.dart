import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/closed_loop_evaluator.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';
import 'package:tunai_pro/core/pro_response_error.dart';

void main() {
  // ── Helpers ──────────────────────────────────────────────────────────────────

  ResponseErrorResult score(double s) => ResponseErrorResult(
        rmsDb: 1.0,
        maxDeviationDb: 2.0,
        maxDeviationHz: 1000.0,
        weightedRmsDb: 1.0,
        score: s,
      );

  LoopMeasurementSnapshot snap(
    String ref,
    double s, {
    ConfidenceStatus confidence = ConfidenceStatus.valid,
  }) =>
      LoopMeasurementSnapshot(
        measurementRef: ref,
        scoreResult: score(s),
        confidenceStatus: confidence,
      );

  const policy = ClosedLoopPolicy(
    id: 'test',
    version: 1,
    improvementThresholdScore: 2.0,
    regressionThresholdScore: -2.0,
  );

  // ── Improved ─────────────────────────────────────────────────────────────────

  group('improved', () {
    test('delta well above threshold → improved', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 70.0),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.improved);
      expect(result.scoreDelta, closeTo(10.0, 1e-9));
    });

    test('delta exactly at improvement threshold → improved', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 62.0),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.improved);
      expect(result.scoreDelta, closeTo(2.0, 1e-9));
    });
  });

  // ── Neutral ──────────────────────────────────────────────────────────────────

  group('neutral', () {
    test('no change → neutral', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 60.0),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.neutral);
      expect(result.scoreDelta, closeTo(0.0, 1e-9));
    });

    test('small positive delta below threshold → neutral', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 61.5),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.neutral);
      expect(result.scoreDelta, closeTo(1.5, 1e-9));
    });

    test('small negative delta above regression threshold → neutral', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 58.5),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.neutral);
      expect(result.scoreDelta, closeTo(-1.5, 1e-9));
    });
  });

  // ── Regressed ────────────────────────────────────────────────────────────────

  group('regressed', () {
    test('delta well below regression threshold → regressed', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 70.0),
        snap('after', 55.0),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.regressed);
      expect(result.scoreDelta, closeTo(-15.0, 1e-9));
    });

    test('delta exactly at regression threshold → regressed', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 58.0),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.regressed);
      expect(result.scoreDelta, closeTo(-2.0, 1e-9));
    });
  });

  // ── Threshold boundary ────────────────────────────────────────────────────────

  group('threshold boundary', () {
    test('delta just inside improvement threshold → neutral', () {
      // 1.999... < 2.0 → neutral, not improved
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 61.999),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.neutral);
    });

    test('delta just inside regression threshold → neutral', () {
      // -1.999... > -2.0 → neutral, not regressed
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 58.001),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.neutral);
    });
  });

  // ── Confidence gate ───────────────────────────────────────────────────────────

  group('confidence gate', () {
    test('after insufficientEvidence → inconclusive regardless of delta', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 90.0, confidence: ConfidenceStatus.insufficientEvidence),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.inconclusive);
      expect(result.scoreDelta, 0.0);
    });

    test('after invalid → inconclusive', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 90.0, confidence: ConfidenceStatus.invalid),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.inconclusive);
      expect(result.scoreDelta, 0.0);
    });

    test('inconclusive reason contains confidence status', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 90.0, confidence: ConfidenceStatus.insufficientEvidence),
        policy,
      );
      expect(result.reasons, hasLength(1));
      expect(result.reasons.first, contains('insufficientEvidence'));
    });

    test('before invalid but after valid → verdict based on delta', () {
      // Only after confidence matters for the gate.
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0, confidence: ConfidenceStatus.invalid),
        snap('after', 65.0),
        policy,
      );
      expect(result.verdict, ImprovementVerdict.improved);
    });
  });

  // ── Evidence propagation ──────────────────────────────────────────────────────

  group('evidence propagation', () {
    test('evidenceRefs carried into result', () {
      final refs = ['ev-before-001', 'ev-after-002'];
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 65.0),
        policy,
        evidenceRefs: refs,
      );
      expect(result.evidenceRefs, equals(refs));
    });

    test('empty evidenceRefs preserved', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 65.0),
        policy,
      );
      expect(result.evidenceRefs, isEmpty);
    });

    test('measurementRefs accessible via snapshots', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('ref-before', 60.0),
        snap('ref-after', 65.0),
        policy,
      );
      expect(result.before.measurementRef, 'ref-before');
      expect(result.after.measurementRef, 'ref-after');
    });
  });

  // ── Policy metadata ───────────────────────────────────────────────────────────

  group('policy metadata', () {
    test('policyId and policyVersion propagated', () {
      const p = ClosedLoopPolicy(
        id: 'my_policy',
        version: 3,
        improvementThresholdScore: 5.0,
        regressionThresholdScore: -5.0,
      );
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 50.0),
        snap('after', 60.0),
        p,
      );
      expect(result.policyId, 'my_policy');
      expect(result.policyVersion, 3);
    });

    test('proProvisional factory produces valid policy', () {
      expect(
          () => ClosedLoopPolicy.proProvisional().validate(), returnsNormally);
    });
  });

  // ── JSON / deterministic ──────────────────────────────────────────────────────

  group('JSON and determinism', () {
    test('toJson contains required keys, no DSP fields', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 65.0),
        policy,
        evidenceRefs: ['ev-001'],
      );
      final j = result.toJson();
      expect(j.containsKey('verdict'), isTrue);
      expect(j.containsKey('scoreDelta'), isTrue);
      expect(j.containsKey('before'), isTrue);
      expect(j.containsKey('after'), isTrue);
      expect(j.containsKey('policyId'), isTrue);
      expect(j.containsKey('policyVersion'), isTrue);
      expect(j.containsKey('evidenceRefs'), isTrue);
      expect(j.containsKey('reasons'), isTrue);
      // No DSP fields
      for (final key in ['biquad', 'address', 'payload', 'register']) {
        expect(j.containsKey(key), isFalse, reason: 'forbidden key: $key');
      }
    });

    test('snapshot toJson contains score and confidenceStatus, no DSP fields',
        () {
      final s = snap('ref-1', 75.0);
      final j = s.toJson();
      expect(j['measurementRef'], 'ref-1');
      expect(j['score'], closeTo(75.0, 1e-9));
      expect(j['confidenceStatus'], 'valid');
      for (final key in ['biquad', 'address', 'payload']) {
        expect(j.containsKey(key), isFalse, reason: 'forbidden key: $key');
      }
    });

    test('same inputs produce identical JSON', () {
      final before = snap('b', 60.0);
      final after = snap('a', 65.0);
      final r1 = AcousticClosedLoopEvaluator.evaluate(before, after, policy,
          evidenceRefs: ['ev-1']);
      final r2 = AcousticClosedLoopEvaluator.evaluate(before, after, policy,
          evidenceRefs: ['ev-1']);
      expect(jsonEncode(r1.toJson()), equals(jsonEncode(r2.toJson())));
    });

    test('verdict name in JSON matches enum name', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 65.0),
        policy,
      );
      expect(result.toJson()['verdict'], result.verdict.name);
    });
  });

  // ── Reasons ───────────────────────────────────────────────────────────────────

  group('reasons', () {
    test('improved reason contains delta and threshold', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 65.0),
        policy,
      );
      expect(result.reasons, hasLength(1));
      expect(result.reasons.first, contains('5.00'));
      expect(result.reasons.first, contains('2.00'));
    });

    test('regressed reason contains delta and threshold', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 70.0),
        snap('after', 65.0),
        policy,
      );
      expect(result.reasons, hasLength(1));
      expect(result.reasons.first, contains('-5.00'));
      expect(result.reasons.first, contains('-2.00'));
    });

    test('neutral reason contains delta', () {
      final result = AcousticClosedLoopEvaluator.evaluate(
        snap('before', 60.0),
        snap('after', 61.0),
        policy,
      );
      expect(result.reasons, hasLength(1));
      expect(result.reasons.first, contains('1.00'));
    });
  });

  // ── Policy validation ─────────────────────────────────────────────────────────

  group('policy validate', () {
    test('empty id throws', () {
      const p = ClosedLoopPolicy(
        id: '',
        version: 1,
        improvementThresholdScore: 2.0,
        regressionThresholdScore: -2.0,
      );
      expect(p.validate, throwsA(isA<ClosedLoopPolicyException>()));
    });

    test('version 0 throws', () {
      const p = ClosedLoopPolicy(
        id: 'x',
        version: 0,
        improvementThresholdScore: 2.0,
        regressionThresholdScore: -2.0,
      );
      expect(p.validate, throwsA(isA<ClosedLoopPolicyException>()));
    });

    test('improvementThreshold 0 throws', () {
      const p = ClosedLoopPolicy(
        id: 'x',
        version: 1,
        improvementThresholdScore: 0.0,
        regressionThresholdScore: -2.0,
      );
      expect(p.validate, throwsA(isA<ClosedLoopPolicyException>()));
    });

    test('improvementThreshold negative throws', () {
      const p = ClosedLoopPolicy(
        id: 'x',
        version: 1,
        improvementThresholdScore: -1.0,
        regressionThresholdScore: -2.0,
      );
      expect(p.validate, throwsA(isA<ClosedLoopPolicyException>()));
    });

    test('regressionThreshold 0 throws', () {
      const p = ClosedLoopPolicy(
        id: 'x',
        version: 1,
        improvementThresholdScore: 2.0,
        regressionThresholdScore: 0.0,
      );
      expect(p.validate, throwsA(isA<ClosedLoopPolicyException>()));
    });

    test('regressionThreshold positive throws', () {
      const p = ClosedLoopPolicy(
        id: 'x',
        version: 1,
        improvementThresholdScore: 2.0,
        regressionThresholdScore: 1.0,
      );
      expect(p.validate, throwsA(isA<ClosedLoopPolicyException>()));
    });
  });
}
