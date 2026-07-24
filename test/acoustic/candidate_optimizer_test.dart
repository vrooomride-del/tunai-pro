import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

const _defaultPolicy = OptimizerPolicy(
  id: 'test_policy',
  version: 1,
  maxNewBands: 3,
  minimumGrade: CandidateScoreGrade.marginal,
  minFrequencySpacingOctaves: 0.5,
);

PeqCandidate _peq({
  required String featureId,
  double frequencyHz = 200.0,
  double gainDb = -6.0,
  double q = 4.0,
  AcousticFeatureType featureType = AcousticFeatureType.narrowPeak,
}) =>
    PeqCandidate(
      candidateId: 'candidate:$featureId',
      featureId: featureId,
      featureType: featureType,
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: q,
      intent: CorrectionIntent.cut,
      reason: 'test',
    );

ScoredCandidate _scored({
  required String featureId,
  required CandidateScoreGrade grade,
  double frequencyHz = 200.0,
  double compositeScore = 70.0,
  double prominenceDb = 6.0,
  int rank = 1,
}) =>
    ScoredCandidate(
      candidate: _peq(featureId: featureId, frequencyHz: frequencyHz),
      prominenceDb: prominenceDb,
      prominenceScore: 40.0,
      magnitudeConsistencyScore: 30.0,
      qualityFactor: 1.0,
      compositeScore: compositeScore,
      rank: rank,
      grade: grade,
      reasons: const ['test'],
    );

ScoredCandidateSet _scoredSet(
  List<ScoredCandidate> candidates, {
  ScoredCandidateSetStatus status = ScoredCandidateSetStatus.ok,
}) =>
    ScoredCandidateSet(
      status: status,
      scoredCandidates: candidates,
      reasons: const ['test'],
      policyId: 'scoring_policy',
      policyVersion: 1,
      evidenceRefs: const ['ev1'],
    );

OptimizedSelection _select(
  List<ScoredCandidate> candidates, {
  ScoredCandidateSetStatus status = ScoredCandidateSetStatus.ok,
  OptimizerPolicy policy = _defaultPolicy,
}) =>
    CandidateOptimizer.select(_scoredSet(candidates, status: status), policy);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('single candidate', () {
    test('single excellent candidate → selected, applicationOrder=1', () {
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            compositeScore: 80.0, rank: 1),
      ]);

      expect(result.status, OptimizationStatus.ok);
      expect(result.selected, hasLength(1));
      expect(result.rejected, isEmpty);
      expect(result.selected.single.applicationOrder, 1);
      expect(result.selected.single.scoredCandidate.candidate.featureId, 'f1');
    });

    test('single good candidate → selected', () {
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.good,
            compositeScore: 50.0, rank: 1),
      ]);
      expect(result.status, OptimizationStatus.ok);
      expect(result.selected, hasLength(1));
    });

    test('single marginal candidate → selected (at minimumGrade)', () {
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.marginal,
            compositeScore: 25.0, rank: 1),
      ]);
      expect(result.status, OptimizationStatus.ok);
      expect(result.selected, hasLength(1));
    });
  });

  group('grade threshold', () {
    test('rejected grade → OptimizationRejectionReason.gradeThreshold', () {
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.rejected,
            compositeScore: 10.0, rank: 1),
      ]);

      expect(result.status, OptimizationStatus.nothingSelected);
      expect(result.selected, isEmpty);
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.rejectionReason,
          OptimizationRejectionReason.gradeThreshold);
    });

    test('minimumGrade=excellent rejects good candidates', () {
      const strictPolicy = OptimizerPolicy(
        id: 'strict',
        version: 1,
        maxNewBands: 3,
        minimumGrade: CandidateScoreGrade.excellent,
        minFrequencySpacingOctaves: 0.5,
      );
      final result = _select(
        [_scored(featureId: 'f1', grade: CandidateScoreGrade.good,
            compositeScore: 60.0, rank: 1)],
        policy: strictPolicy,
      );
      expect(result.status, OptimizationStatus.nothingSelected);
      expect(result.rejected.single.rejectionReason,
          OptimizationRejectionReason.gradeThreshold);
    });

    test('minimumGrade=excellent accepts excellent', () {
      const strictPolicy = OptimizerPolicy(
        id: 'strict',
        version: 1,
        maxNewBands: 3,
        minimumGrade: CandidateScoreGrade.excellent,
        minFrequencySpacingOctaves: 0.5,
      );
      final result = _select(
        [_scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            compositeScore: 80.0, rank: 1)],
        policy: strictPolicy,
      );
      expect(result.status, OptimizationStatus.ok);
      expect(result.selected, hasLength(1));
    });
  });

  group('band budget', () {
    test('maxNewBands=1: second candidate → bandBudgetExceeded', () {
      const budgetPolicy = OptimizerPolicy(
        id: 'budget1',
        version: 1,
        maxNewBands: 1,
        minimumGrade: CandidateScoreGrade.marginal,
        minFrequencySpacingOctaves: 0.0,
      );
      final result = _select(
        [
          _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
              frequencyHz: 200.0, compositeScore: 90.0, rank: 1),
          _scored(featureId: 'f2', grade: CandidateScoreGrade.excellent,
              frequencyHz: 2000.0, compositeScore: 80.0, rank: 2),
        ],
        policy: budgetPolicy,
      );

      expect(result.status, OptimizationStatus.ok);
      expect(result.selected, hasLength(1));
      expect(result.selected.single.scoredCandidate.candidate.featureId, 'f1');
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.rejectionReason,
          OptimizationRejectionReason.bandBudgetExceeded);
      expect(result.rejected.single.scoredCandidate.candidate.featureId, 'f2');
    });

    test('maxNewBands=2: third candidate → bandBudgetExceeded', () {
      const budgetPolicy = OptimizerPolicy(
        id: 'budget2',
        version: 1,
        maxNewBands: 2,
        minimumGrade: CandidateScoreGrade.marginal,
        minFrequencySpacingOctaves: 0.0,
      );
      final result = _select(
        [
          _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
              frequencyHz: 100.0, compositeScore: 90.0, rank: 1),
          _scored(featureId: 'f2', grade: CandidateScoreGrade.good,
              frequencyHz: 1000.0, compositeScore: 60.0, rank: 2),
          _scored(featureId: 'f3', grade: CandidateScoreGrade.marginal,
              frequencyHz: 5000.0, compositeScore: 30.0, rank: 3),
        ],
        policy: budgetPolicy,
      );
      expect(result.selected, hasLength(2));
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.rejectionReason,
          OptimizationRejectionReason.bandBudgetExceeded);
    });
  });

  group('frequency spacing', () {
    // 100Hz and 120Hz: |log2(120/100)| ≈ 0.263 oct < 0.5 → clustered
    test('two candidates within 0.5 oct → second rejected (frequencyClustering)',
        () {
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            frequencyHz: 100.0, compositeScore: 90.0, rank: 1),
        _scored(featureId: 'f2', grade: CandidateScoreGrade.excellent,
            frequencyHz: 120.0, compositeScore: 80.0, rank: 2),
      ]);

      final spacing =
          (math.log(120.0) - math.log(100.0)).abs() / math.ln2;
      expect(spacing, lessThan(0.5));

      expect(result.selected, hasLength(1));
      expect(result.selected.single.scoredCandidate.candidate.featureId, 'f1');
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.rejectionReason,
          OptimizationRejectionReason.frequencyClustering);
      expect(result.rejected.single.detail, contains('f1@100Hz'));
    });

    // 100Hz and 200Hz: |log2(2)| = 1.0 oct > 0.5 → both selected
    test('two candidates 1.0 oct apart → both selected', () {
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            frequencyHz: 100.0, compositeScore: 90.0, rank: 1),
        _scored(featureId: 'f2', grade: CandidateScoreGrade.excellent,
            frequencyHz: 200.0, compositeScore: 80.0, rank: 2),
      ]);

      expect(result.status, OptimizationStatus.ok);
      expect(result.selected, hasLength(2));
      expect(result.rejected, isEmpty);
    });

    // Exactly at minFrequencySpacingOctaves boundary: spacing < threshold → reject
    test('spacing exactly at threshold rounds to clustered (strict <)', () {
      // 0.5 oct apart = f2 = 100 * 2^0.5 ≈ 141.42 Hz
      const f1 = 100.0;
      final f2 = f1 * math.pow(2.0, 0.5); // exactly 0.5 oct
      final spacing = (math.log(f2) - math.log(f1)).abs() / math.ln2;
      expect(spacing, closeTo(0.5, 1e-10));

      // spacing == minSpacing (0.5) is NOT < 0.5, so it should pass
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            frequencyHz: f1, compositeScore: 90.0, rank: 1),
        _scored(featureId: 'f2', grade: CandidateScoreGrade.excellent,
            frequencyHz: f2, compositeScore: 80.0, rank: 2),
      ]);
      expect(result.selected, hasLength(2),
          reason: 'spacing == minSpacing should pass (< not <=)');
    });

    test('three candidates: f1=100, f2=120(close to f1), f3=2000 → f1,f3 selected',
        () {
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            frequencyHz: 100.0, compositeScore: 90.0, rank: 1),
        _scored(featureId: 'f2', grade: CandidateScoreGrade.excellent,
            frequencyHz: 120.0, compositeScore: 80.0, rank: 2),
        _scored(featureId: 'f3', grade: CandidateScoreGrade.excellent,
            frequencyHz: 2000.0, compositeScore: 70.0, rank: 3),
      ]);

      expect(result.selected, hasLength(2));
      expect(
        result.selected.map((s) => s.scoredCandidate.candidate.featureId),
        containsAll(['f1', 'f3']),
      );
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.scoredCandidate.candidate.featureId, 'f2');
    });
  });

  group('applicationOrder', () {
    test('applicationOrder is 1-based and sequential', () {
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            frequencyHz: 100.0, compositeScore: 90.0, rank: 1),
        _scored(featureId: 'f2', grade: CandidateScoreGrade.excellent,
            frequencyHz: 400.0, compositeScore: 80.0, rank: 2),
        _scored(featureId: 'f3', grade: CandidateScoreGrade.excellent,
            frequencyHz: 2000.0, compositeScore: 70.0, rank: 3),
      ]);

      expect(result.selected, hasLength(3));
      final orders = result.selected.map((s) => s.applicationOrder).toList();
      expect(orders, [1, 2, 3]);
    });

    test('applicationOrder after clustering skip is still sequential', () {
      // f2 clustered (close to f1), so selected = [f1, f3] with orders [1, 2]
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            frequencyHz: 100.0, compositeScore: 90.0, rank: 1),
        _scored(featureId: 'f2', grade: CandidateScoreGrade.excellent,
            frequencyHz: 110.0, compositeScore: 80.0, rank: 2),
        _scored(featureId: 'f3', grade: CandidateScoreGrade.excellent,
            frequencyHz: 1000.0, compositeScore: 70.0, rank: 3),
      ]);

      expect(result.selected, hasLength(2));
      expect(result.selected[0].applicationOrder, 1);
      expect(result.selected[1].applicationOrder, 2);
      expect(result.selected[1].scoredCandidate.candidate.featureId, 'f3');
    });
  });

  group('upstream status propagation', () {
    test('noCorrectableDirectives → OptimizationStatus.propagated', () {
      final result = _select(
        [],
        status: ScoredCandidateSetStatus.noCorrectableDirectives,
      );
      expect(result.status, OptimizationStatus.propagated);
      expect(result.selected, isEmpty);
      expect(result.rejected, isEmpty);
      expect(result.reasons.single,
          contains('noCorrectableDirectives'));
    });

    test('insufficientEvidence → OptimizationStatus.propagated', () {
      final result = _select(
        [],
        status: ScoredCandidateSetStatus.insufficientEvidence,
      );
      expect(result.status, OptimizationStatus.propagated);
    });

    test('invalidPlan → OptimizationStatus.propagated', () {
      final result = _select(
        [],
        status: ScoredCandidateSetStatus.invalidPlan,
      );
      expect(result.status, OptimizationStatus.propagated);
    });

    test('allRejected (all grade=rejected) → nothingSelected', () {
      final result = _select(
        [
          _scored(featureId: 'f1', grade: CandidateScoreGrade.rejected,
              compositeScore: 10.0, rank: 1),
          _scored(featureId: 'f2', grade: CandidateScoreGrade.rejected,
              frequencyHz: 1000.0, compositeScore: 5.0, rank: 2),
        ],
        status: ScoredCandidateSetStatus.allRejected,
      );
      expect(result.status, OptimizationStatus.nothingSelected);
      expect(result.selected, isEmpty);
      expect(result.rejected, hasLength(2));
      expect(
        result.rejected
            .every((r) => r.rejectionReason == OptimizationRejectionReason.gradeThreshold),
        isTrue,
      );
    });
  });

  group('evidenceRefs propagation', () {
    test('evidenceRefs from ScoredCandidateSet appear in OptimizedSelection', () {
      final set = ScoredCandidateSet(
        status: ScoredCandidateSetStatus.ok,
        scoredCandidates: [
          _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
              compositeScore: 80.0, rank: 1),
        ],
        reasons: const [],
        policyId: 'p',
        policyVersion: 1,
        evidenceRefs: const ['measurement-abc', 'sweep-001'],
      );
      final result = CandidateOptimizer.select(set, _defaultPolicy);
      expect(result.evidenceRefs, containsAll(['measurement-abc', 'sweep-001']));
    });
  });

  group('JSON — no DSP-forbidden fields', () {
    test('toJson() contains no address/payload/biquad/hardware fields', () {
      final result = _select([
        _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            frequencyHz: 200.0, compositeScore: 80.0, rank: 1),
      ]);
      final json = jsonEncode(result.toJson()).toLowerCase();

      for (final forbidden in [
        'address',
        'payload',
        'biquad',
        'coefficient',
        'register',
        'safeload',
        'hardware',
        'suggestion',
        'proposedgain',
      ]) {
        expect(json.contains(forbidden), isFalse,
            reason: 'forbidden field "$forbidden" found in JSON');
      }
    });
  });

  group('determinism', () {
    test('same inputs → identical JSON output', () {
      final candidates = [
        _scored(featureId: 'f1', grade: CandidateScoreGrade.excellent,
            frequencyHz: 100.0, compositeScore: 90.0, rank: 1),
        _scored(featureId: 'f2', grade: CandidateScoreGrade.good,
            frequencyHz: 800.0, compositeScore: 60.0, rank: 2),
        _scored(featureId: 'f3', grade: CandidateScoreGrade.marginal,
            frequencyHz: 4000.0, compositeScore: 30.0, rank: 3),
      ];
      final a = _select(candidates);
      final b = _select(candidates);
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    });
  });

  group('empty input', () {
    test('empty scoredCandidates → nothingSelected', () {
      final result = _select([]);
      expect(result.status, OptimizationStatus.nothingSelected);
      expect(result.selected, isEmpty);
      expect(result.rejected, isEmpty);
    });
  });

  group('policyId / policyVersion in output', () {
    test('policyId and policyVersion from OptimizerPolicy are recorded', () {
      const p = OptimizerPolicy(
        id: 'my_policy',
        version: 42,
        maxNewBands: 2,
        minimumGrade: CandidateScoreGrade.good,
        minFrequencySpacingOctaves: 0.3,
      );
      final result = _select([], policy: p);
      expect(result.policyId, 'my_policy');
      expect(result.policyVersion, 42);
    });
  });

  group('OptimizerPolicy.validate()', () {
    test('empty id throws', () {
      const bad = OptimizerPolicy(
        id: '',
        version: 1,
        maxNewBands: 1,
        minimumGrade: CandidateScoreGrade.marginal,
        minFrequencySpacingOctaves: 0.5,
      );
      expect(() => bad.validate(), throwsA(isA<OptimizerPolicyException>()));
    });

    test('version < 1 throws', () {
      const bad = OptimizerPolicy(
        id: 'x',
        version: 0,
        maxNewBands: 1,
        minimumGrade: CandidateScoreGrade.marginal,
        minFrequencySpacingOctaves: 0.5,
      );
      expect(() => bad.validate(), throwsA(isA<OptimizerPolicyException>()));
    });

    test('maxNewBands < 1 throws', () {
      const bad = OptimizerPolicy(
        id: 'x',
        version: 1,
        maxNewBands: 0,
        minimumGrade: CandidateScoreGrade.marginal,
        minFrequencySpacingOctaves: 0.5,
      );
      expect(() => bad.validate(), throwsA(isA<OptimizerPolicyException>()));
    });

    test('negative minFrequencySpacingOctaves throws', () {
      const bad = OptimizerPolicy(
        id: 'x',
        version: 1,
        maxNewBands: 1,
        minimumGrade: CandidateScoreGrade.marginal,
        minFrequencySpacingOctaves: -0.1,
      );
      expect(() => bad.validate(), throwsA(isA<OptimizerPolicyException>()));
    });

    test('infinite minFrequencySpacingOctaves throws', () {
      const bad = OptimizerPolicy(
        id: 'x',
        version: 1,
        maxNewBands: 1,
        minimumGrade: CandidateScoreGrade.marginal,
        minFrequencySpacingOctaves: double.infinity,
      );
      expect(() => bad.validate(), throwsA(isA<OptimizerPolicyException>()));
    });

    test('proProvisional() passes validate()', () {
      expect(
          () => OptimizerPolicy.proProvisional().validate(), returnsNormally);
    });
  });
}
