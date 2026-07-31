import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';
import 'package:tunai_pro/core/acoustic/correction_policy.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

const _candidatePolicy = CandidatePolicy(
  id: 'test_policy',
  version: 1,
  maxCutDb: 9.0,
  minQ: 0.5,
  maxQ: 10.0,
  gainScale: 1.0,
  broadQ: 1.0,
  minimumGainDb: 1.0,
);

final _correctionPolicy = CorrectionPolicy.proProvisional();

AcousticObservedFeature _feat({
  required String id,
  AcousticFeatureType type = AcousticFeatureType.narrowPeak,
  double centerHz = 200,
  double deviationDb = 8.0,
  double estimatedQ = 4.0,
  AcousticFeatureQuality quality = AcousticFeatureQuality.confident,
  AcousticActionability actionability =
      AcousticActionability.safePeqCutCandidate,
}) =>
    AcousticObservedFeature(
      featureId: id,
      type: type,
      startHz: centerHz * 0.9,
      centerHz: centerHz,
      endHz: centerHz * 1.1,
      deviationDb: deviationDb,
      prominenceDb: deviationDb.abs(),
      bandwidthHz: centerHz * 0.2,
      bandwidthOctaves: 0.28,
      estimatedQ: estimatedQ,
      quality: quality,
      actionability: actionability,
    );

AcousticClassificationResult _result(
  List<AcousticObservedFeature> features, {
  AcousticClassificationStatus status = AcousticClassificationStatus.ok,
  MeasurementConfidenceInterpretation interp =
      MeasurementConfidenceInterpretation.correctableAllowed,
  List<AcousticFeatureType> blocked = const [],
}) =>
    AcousticClassificationResult(
      status: status,
      residualSummary: null,
      observedFeatures: features,
      analysisMinHz: 20,
      analysisMaxHz: 20000,
      confidenceInterpretation: interp,
      blockedAutomaticCorrections: blocked,
      suggestedNextActions: const [],
      reasons: const [],
      warnings: const [],
      policyId: 'cls',
      policyVersion: 1,
      evidenceRefs: const ['ev1'],
    );

/// Generate via full planning pipeline — exercises the real CorrectionPlanner.
CandidateSet _generate(
  List<AcousticObservedFeature> features, {
  AcousticClassificationStatus classStatus = AcousticClassificationStatus.ok,
  MeasurementConfidenceInterpretation interp =
      MeasurementConfidenceInterpretation.correctableAllowed,
  CandidatePolicy policy = _candidatePolicy,
}) {
  final result = _result(features, status: classStatus, interp: interp);
  final plan = CorrectionPlanner.plan(result, _correctionPolicy);
  return CandidateGenerator.generate(plan, result, policy);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  test('ADAU1701 candidate generation limits -9 dB input to -6 dB', () {
    final set = _generate(
      [_feat(id: 'adau1701-cut', deviationDb: 9.0)],
      policy: CandidatePolicy.adau1701Icp5(),
    );
    expect(set.status, CandidateSetStatus.ok);
    expect(set.candidates.single.gainDb, -6.0);
  });

  test('shared candidate policy remains unchanged for ADAU1466/default', () {
    final set = _generate([_feat(id: 'shared-cut', deviationDb: 9.0)]);
    expect(set.candidates.single.gainDb, -9.0);
  });

  group('correctable → candidate generated', () {
    test('safePeqCutCandidate feature produces a PeqCandidate with cut intent',
        () {
      final cs = _generate([_feat(id: 'f1')]);

      expect(cs.status, CandidateSetStatus.ok);
      expect(cs.candidates, hasLength(1));
      final c = cs.candidates.single;
      expect(c.featureId, 'f1');
      expect(c.candidateId, 'candidate:f1');
      expect(c.frequencyHz, 200.0);
      expect(c.gainDb, isNegative);
      expect(c.intent, CorrectionIntent.cut);
    });

    test('cautiousBroadCorrection feature produces broadShape intent', () {
      final feat = _feat(
        id: 'f1',
        type: AcousticFeatureType.broadPeak,
        actionability: AcousticActionability.cautiousBroadCorrection,
        estimatedQ: 6.0,
      );
      final cs = _generate([feat]);

      expect(cs.status, CandidateSetStatus.ok);
      expect(cs.candidates.single.intent, CorrectionIntent.broadShape);
      expect(cs.candidates.single.q, _candidatePolicy.broadQ);
    });

    test('candidateId is always candidate:<featureId>', () {
      final feat = _feat(id: 'narrowPeak@200Hz#0');
      final cs = _generate([feat]);
      expect(cs.candidates.single.candidateId, 'candidate:narrowPeak@200Hz#0');
    });

    test('frequencyHz equals the feature centerHz (observation, not command)',
        () {
      final feat = _feat(id: 'f1', centerHz: 350.0);
      final cs = _generate([feat]);
      expect(cs.candidates.single.frequencyHz, 350.0);
    });

    test('multiple correctable features all produce candidates', () {
      final feats = [
        _feat(id: 'f0', centerHz: 80),
        _feat(id: 'f1', centerHz: 200),
        _feat(id: 'f2', centerHz: 500),
      ];
      final cs = _generate(feats);
      expect(cs.status, CandidateSetStatus.ok);
      expect(cs.candidates, hasLength(3));
    });
  });

  group('gain clamping', () {
    test('deviationDb > maxCutDb → gainDb clamped to -maxCutDb', () {
      final feat = _feat(id: 'f1', deviationDb: 20.0);
      final cs = _generate([feat]);
      expect(cs.candidates.single.gainDb, -_candidatePolicy.maxCutDb);
    });

    test('deviationDb × gainScale < minimumGainDb → skipped', () {
      const policy = CandidatePolicy(
        id: 'tinyGain',
        version: 1,
        maxCutDb: 9.0,
        minQ: 0.5,
        maxQ: 10.0,
        gainScale: 0.1, // 5 dB × 0.1 = 0.5 dB < minimumGainDb=1.0
        broadQ: 1.0,
        minimumGainDb: 1.0,
      );
      final feat = _feat(id: 'f1', deviationDb: 5.0);
      final result = _result([feat]);
      final plan = CorrectionPlanner.plan(result, _correctionPolicy);
      final cs = CandidateGenerator.generate(plan, result, policy);

      expect(cs.candidates, isEmpty);
      expect(cs.skippedDirectives, hasLength(1));
      expect(cs.status, CandidateSetStatus.noCorrectableDirectives);
    });

    test('gainDb is always negative (never a boost)', () {
      for (final dev in [1.5, 4.0, 9.5]) {
        final feat = _feat(id: 'f', deviationDb: dev);
        final cs = _generate([feat]);
        expect(cs.candidates.single.gainDb, isNegative,
            reason: 'deviation=$dev must yield negative gainDb');
      }
    });
  });

  group('Q clamping', () {
    test('estimatedQ above maxQ is clamped to maxQ', () {
      final feat = _feat(id: 'f1', estimatedQ: 50.0);
      final cs = _generate([feat]);
      expect(cs.candidates.single.q, _candidatePolicy.maxQ);
    });

    test('estimatedQ below minQ is clamped to minQ', () {
      final feat = _feat(id: 'f1', estimatedQ: 0.01);
      final cs = _generate([feat]);
      expect(cs.candidates.single.q, _candidatePolicy.minQ);
    });

    test('broadShape directive uses policy.broadQ regardless of estimatedQ',
        () {
      final feat = _feat(
        id: 'f1',
        type: AcousticFeatureType.broadPeak,
        actionability: AcousticActionability.cautiousBroadCorrection,
        estimatedQ: 8.0,
      );
      final cs = _generate([feat]);
      expect(cs.candidates.single.q, _candidatePolicy.broadQ);
    });
  });

  group('blocked directives → skipped', () {
    for (final action in [
      AcousticActionability.doNotBoost,
      AcousticActionability.informationalOnly,
      AcousticActionability.inspectPlacementOrPhase,
      AcousticActionability.requiresExpertReview,
      AcousticActionability.noAutomaticCorrection,
      AcousticActionability.remeasureRequired,
    ]) {
      test('$action → SkippedDirective, no candidate', () {
        final feat = _feat(id: 'f1', actionability: action);
        final cs = _generate([feat]);
        expect(cs.candidates, isEmpty,
            reason: '$action should not produce a candidate');
        expect(cs.skippedDirectives, hasLength(1));
      });
    }

    test('tentative feature escalated to manualReview by default policy', () {
      final feat = _feat(
        id: 'f1',
        actionability: AcousticActionability.safePeqCutCandidate,
        quality: AcousticFeatureQuality.tentative,
      );
      final cs = _generate([feat]);
      expect(cs.candidates, isEmpty);
      expect(cs.skippedDirectives.single.disposition,
          CorrectionDisposition.manualReview);
    });
  });

  group('deepNull protection', () {
    test('deepNull is always skipped even if planner marks it prohibitedBoost',
        () {
      final feat = _feat(
        id: 'dn',
        type: AcousticFeatureType.deepNull,
        deviationDb: -15.0,
        actionability: AcousticActionability.doNotBoost,
      );
      final cs = _generate([feat]);

      expect(cs.candidates, isEmpty);
      expect(cs.skippedDirectives.single.featureType,
          AcousticFeatureType.deepNull);
    });

    test(
        'deepNull mixed with correctable → only correctable produces candidate',
        () {
      final peak = _feat(id: 'pk');
      final null_ = _feat(
        id: 'dn',
        type: AcousticFeatureType.deepNull,
        deviationDb: -15.0,
        actionability: AcousticActionability.doNotBoost,
      );
      final cs = _generate([peak, null_]);

      expect(cs.candidates, hasLength(1));
      expect(cs.candidates.single.featureId, 'pk');
      expect(cs.skippedDirectives.single.featureType,
          AcousticFeatureType.deepNull);
    });
  });

  group('plan status propagation', () {
    test('invalidMeasurement → CandidateSetStatus.invalidPlan, no candidates',
        () {
      final cs = _generate([],
          classStatus: AcousticClassificationStatus.invalidMeasurement);
      expect(cs.status, CandidateSetStatus.invalidPlan);
      expect(cs.candidates, isEmpty);
      expect(cs.skippedDirectives, isEmpty);
    });

    test(
        'insufficientEvidence → CandidateSetStatus.insufficientEvidence, no candidates',
        () {
      final cs = _generate([],
          classStatus: AcousticClassificationStatus.insufficientEvidence);
      expect(cs.status, CandidateSetStatus.insufficientEvidence);
      expect(cs.candidates, isEmpty);
    });
    test(
        'analysisOnly + narrowPeak (safePeqCutCandidate) → candidate generated',
        () {
      // Simulates single-sweep FRD: narrowPeak retains safePeqCutCandidate
      // actionability after the analysisOnly fix; Expert approval UI gate
      // enforces review before Apply.
      final feat = _feat(
        id: 'narrowPeak@1000Hz',
        type: AcousticFeatureType.narrowPeak,
        actionability: AcousticActionability.safePeqCutCandidate,
        quality: AcousticFeatureQuality.confident,
      );
      final cs = _generate([feat],
          interp: MeasurementConfidenceInterpretation.analysisOnly);
      expect(cs.status, CandidateSetStatus.ok);
      expect(cs.candidates, isNotEmpty);
    });
    test(
        'analysisOnly + risingTrend → noCorrectableDirectives (trend stays blocked)',
        () {
      final feat = _feat(
        id: 'risingTrend@500Hz',
        type: AcousticFeatureType.risingTrend,
        actionability: AcousticActionability.noAutomaticCorrection,
      );
      final cs = _generate([feat],
          interp: MeasurementConfidenceInterpretation.analysisOnly);
      expect(cs.status, CandidateSetStatus.noCorrectableDirectives);
      expect(cs.candidates, isEmpty);
    });
  });

  group('empty / no correctable', () {
    test('ok plan with zero features → noCorrectableDirectives', () {
      final cs = _generate(const []);
      expect(cs.status, CandidateSetStatus.noCorrectableDirectives);
      expect(cs.candidates, isEmpty);
    });

    test('only non-correctable features → noCorrectableDirectives', () {
      final feat = _feat(
          id: 'f1', actionability: AcousticActionability.requiresExpertReview);
      final cs = _generate([feat]);
      expect(cs.status, CandidateSetStatus.noCorrectableDirectives);
    });
  });

  group('boundary / determinism', () {
    test('no DSP-forbidden field in JSON output', () {
      final feat = _feat(id: 'f1', centerHz: 200);
      final cs = _generate([feat]);
      final json = jsonEncode(cs.toJson()).toLowerCase();

      for (final forbidden in [
        'address',
        'payload',
        'biquad',
        'coefficient',
        'register',
        'safeload',
        'peqband',
        'hardware',
        'suggestion',
        'proposedgain',
      ]) {
        expect(json.contains(forbidden), isFalse,
            reason: 'forbidden field "$forbidden" found in JSON');
      }
    });

    test('same input + policy → identical JSON (deterministic)', () {
      final feats = [
        _feat(id: 'f1', centerHz: 100),
        _feat(id: 'f2', centerHz: 400),
      ];
      final result = _result(feats);
      final plan = CorrectionPlanner.plan(result, _correctionPolicy);
      final a = CandidateGenerator.generate(plan, result, _candidatePolicy);
      final b = CandidateGenerator.generate(plan, result, _candidatePolicy);
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
      expect(a.candidates.map((c) => c.candidateId),
          b.candidates.map((c) => c.candidateId));
    });

    test('policyId and policyVersion recorded in CandidateSet', () {
      final cs = _generate(const []);
      expect(cs.policyId, 'test_policy');
      expect(cs.policyVersion, 1);
    });

    test('evidenceRefs propagated from plan', () {
      final cs = _generate(const []);
      expect(cs.evidenceRefs, contains('ev1'));
    });

    test('proProvisional() has PRO-specific maxCutDb and Q envelope', () {
      final p = CandidatePolicy.proProvisional();
      expect(p.maxCutDb, 9.0);
      expect(p.minQ, 0.5);
      expect(p.maxQ, 10.0);
      expect(p.id, 'pro_provisional');
    });
  });

  group('CandidatePolicy.validate()', () {
    test('empty id throws', () {
      const bad = CandidatePolicy(
        id: '',
        version: 1,
        maxCutDb: 9,
        minQ: 0.5,
        maxQ: 10,
        gainScale: 1.0,
        broadQ: 1.0,
        minimumGainDb: 1.0,
      );
      expect(() => bad.validate(), throwsA(isA<CandidatePolicyException>()));
    });

    test('gainScale of 0.0 throws', () {
      const bad = CandidatePolicy(
        id: 'x',
        version: 1,
        maxCutDb: 9,
        minQ: 0.5,
        maxQ: 10,
        gainScale: 0.0,
        broadQ: 1.0,
        minimumGainDb: 1.0,
      );
      expect(() => bad.validate(), throwsA(isA<CandidatePolicyException>()));
    });

    test('broadQ below minQ throws', () {
      const bad = CandidatePolicy(
        id: 'x',
        version: 1,
        maxCutDb: 9,
        minQ: 0.5,
        maxQ: 10,
        gainScale: 1.0,
        broadQ: 0.1,
        minimumGainDb: 1.0,
      );
      expect(() => bad.validate(), throwsA(isA<CandidatePolicyException>()));
    });

    test('minimumGainDb exceeding maxCutDb throws', () {
      const bad = CandidatePolicy(
        id: 'x',
        version: 1,
        maxCutDb: 2.0,
        minQ: 0.5,
        maxQ: 10,
        gainScale: 1.0,
        broadQ: 1.0,
        minimumGainDb: 3.0,
      );
      expect(() => bad.validate(), throwsA(isA<CandidatePolicyException>()));
    });

    test('proProvisional() passes validate() without throwing', () {
      expect(
          () => CandidatePolicy.proProvisional().validate(), returnsNormally);
    });
  });
}
