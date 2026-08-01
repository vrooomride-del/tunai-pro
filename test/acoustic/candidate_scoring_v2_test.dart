import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart'
    show CandidateScoreGrade;
import 'package:tunai_pro/core/acoustic/candidate_scoring_v2.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';
import 'package:tunai_pro/core/pro_response_error.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_protection_data.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

const _policy = CandidateScoringPolicyV2(
  id: 'test_policy',
  version: 1,
  targetImprovementRefDb: 6.0,
  weightedRmsWorstDb: 10.0,
  maxDeviationWorstDb: 15.0,
  maxBoostDb: 0.0,
  excessiveQThreshold: 8.0,
  excessiveQCeilingQ: 14.0,
  complexityRefBands: 3,
  headroomPenaltyRatio: 0.7,
  protectionMinMarginDb: 3.0,
  rejectionThreshold: 20.0,
  goodThreshold: 50.0,
  excellentThreshold: 75.0,
);

AcousticObservedFeature _feature({
  String featureId = 'f1',
  AcousticFeatureType type = AcousticFeatureType.narrowPeak,
  double deviationDb = -6.0,
  double prominenceDb = 5.0,
  double estimatedQ = 4.0,
}) =>
    AcousticObservedFeature(
      featureId: featureId,
      type: type,
      startHz: 900.0,
      centerHz: 1000.0,
      endHz: 1100.0,
      deviationDb: deviationDb,
      prominenceDb: prominenceDb,
      bandwidthHz: 200.0,
      bandwidthOctaves: 0.29,
      estimatedQ: estimatedQ,
      quality: AcousticFeatureQuality.confident,
      actionability: AcousticActionability.safePeqCutCandidate,
    );

AcousticClassificationResult _classResult({
  MeasurementConfidenceInterpretation confidence =
      MeasurementConfidenceInterpretation.correctableAllowed,
  List<AcousticObservedFeature>? features,
  ResidualSummary? residualSummary,
}) =>
    AcousticClassificationResult(
      status: AcousticClassificationStatus.ok,
      residualSummary: residualSummary,
      observedFeatures: features ?? [_feature()],
      analysisMinHz: 20.0,
      analysisMaxHz: 20000.0,
      confidenceInterpretation: confidence,
      blockedAutomaticCorrections: const [],
      suggestedNextActions: const [],
      reasons: const [],
      warnings: const [],
      policyId: 'test',
      policyVersion: 1,
      evidenceRefs: const [],
    );

CorrectionDirective _directive({
  String featureId = 'f1',
  AcousticFeatureType featureType = AcousticFeatureType.narrowPeak,
  CorrectionDisposition disposition = CorrectionDisposition.correctable,
  CorrectionIntent intent = CorrectionIntent.cut,
}) =>
    CorrectionDirective(
      featureId: featureId,
      featureType: featureType,
      region: const CorrectionRegion(
          startHz: 900.0, centerHz: 1000.0, endHz: 1100.0),
      intent: intent,
      disposition: disposition,
      sourceActionability: AcousticActionability.safePeqCutCandidate,
      reason: 'test directive',
    );

CorrectionPlan _plan({List<CorrectionDirective>? directives}) =>
    CorrectionPlan(
      status: CorrectionPlanStatus.ok,
      directives: directives ?? [_directive()],
      correctableRegions: const [],
      prohibitedBoostRegions: const [],
      inspectOnlyRegions: const [],
      manualReviewRequired: false,
      confidenceInterpretation:
          MeasurementConfidenceInterpretation.correctableAllowed,
      blockedFeatureTypes: const [],
      reasons: const [],
      warnings: const [],
      policyId: 'test',
      policyVersion: 1,
      evidenceRefs: const ['ref-001'],
    );

PeqCandidate _candidate({
  String candidateId = 'candidate:f1',
  String featureId = 'f1',
  AcousticFeatureType featureType = AcousticFeatureType.narrowPeak,
  double gainDb = -6.0,
  double q = 4.0,
  double frequencyHz = 1000.0,
}) =>
    PeqCandidate(
      candidateId: candidateId,
      featureId: featureId,
      featureType: featureType,
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: q,
      intent: CorrectionIntent.cut,
      reason: 'test',
    );

CandidateSet _candidateSet({
  List<PeqCandidate>? candidates,
  CandidateSetStatus status = CandidateSetStatus.ok,
}) =>
    CandidateSet(
      status: status,
      candidates: candidates ?? [_candidate()],
      skippedDirectives: const [],
      reasons: const [],
      policyId: 'test',
      policyVersion: 1,
      evidenceRefs: const ['ref-001'],
    );

CandidateScoringContextV2 _ctx({
  CandidateSet? candidateSet,
  AcousticClassificationResult? classificationResult,
  CorrectionPlan? correctionPlan,
  bool? nullCorrectionPlan,
  ResponseErrorResult? currentError,
  ResponseErrorResult? simulatedError,
  Map<String, ResponseErrorResult>? perCandidateSimulatedError,
  double? availableHeadroomDb,
  double? protectionMarginDb,
}) =>
    CandidateScoringContextV2(
      candidateSet: candidateSet ?? _candidateSet(),
      classificationResult: classificationResult ?? _classResult(),
      correctionPlan: (nullCorrectionPlan == true) ? null : (correctionPlan ?? _plan()),
      currentError: currentError,
      simulatedError: simulatedError,
      perCandidateSimulatedError: perCandidateSimulatedError,
      availableHeadroomDb: availableHeadroomDb,
      protectionMarginDb: protectionMarginDb,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('CandidateScoringPolicyV2 — validation', () {
    test('proProvisional is valid', () {
      expect(
          () => CandidateScoringPolicyV2.proProvisional().validate(),
          returnsNormally);
    });

    test('empty id throws', () {
      const bad = CandidateScoringPolicyV2(
        id: '',
        version: 1,
        targetImprovementRefDb: 6.0,
        weightedRmsWorstDb: 10.0,
        maxDeviationWorstDb: 15.0,
        maxBoostDb: 0.0,
        excessiveQThreshold: 8.0,
        excessiveQCeilingQ: 14.0,
        complexityRefBands: 3,
        headroomPenaltyRatio: 0.7,
        protectionMinMarginDb: 3.0,
        rejectionThreshold: 20.0,
        goodThreshold: 50.0,
        excellentThreshold: 75.0,
      );
      expect(() => bad.validate(), throwsA(isA<ScoringV2PolicyException>()));
    });

    test('excessiveQCeiling <= threshold throws', () {
      const bad = CandidateScoringPolicyV2(
        id: 'x',
        version: 1,
        targetImprovementRefDb: 6.0,
        weightedRmsWorstDb: 10.0,
        maxDeviationWorstDb: 15.0,
        maxBoostDb: 0.0,
        excessiveQThreshold: 8.0,
        excessiveQCeilingQ: 8.0, // must be > threshold
        complexityRefBands: 3,
        headroomPenaltyRatio: 0.7,
        protectionMinMarginDb: 3.0,
        rejectionThreshold: 20.0,
        goodThreshold: 50.0,
        excellentThreshold: 75.0,
      );
      expect(() => bad.validate(), throwsA(isA<ScoringV2PolicyException>()));
    });
  });

  group('Item 1 — target improvement', () {
    test('perfect correction of refDb deviation earns max targetImprovement (25)', () {
      // deviationDb = -6.0 matches targetImprovementRefDb = 6.0.
      // Full correction → targetImprovementScore = 25.
      final result = CandidateScorerV2.score(_ctx(), _policy);
      expect(result.status, ScoredCandidateSetV2Status.ok);
      final sc = result.scoredCandidates.first;
      expect(sc.breakdown.targetImprovementScore, closeTo(25.0, 0.01));
    });

    test('partial correction earns proportional targetImprovement', () {
      // deviationDb = -6.0, gainDb = -3.0 → effectiveCorrection = 3.0.
      // targetImprovementScore = 3/6 × 25 = 12.5.
      final set = _candidateSet(candidates: [_candidate(gainDb: -3.0)]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.scoredCandidates.first.breakdown.targetImprovementScore,
          closeTo(12.5, 0.01));
    });

    test('over-correction is capped at targetImprovementRefDb (25 pts)', () {
      // gainDb = -12.0 but deviationDb = -6.0 → effectiveCorrection = 6.0.
      // Score is capped at 25.
      final set = _candidateSet(candidates: [_candidate(gainDb: -12.0)]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.scoredCandidates.first.breakdown.targetImprovementScore,
          closeTo(25.0, 0.01));
    });
  });

  group('Item 2 — weighted RMS error', () {
    test('low weighted RMS earns near-max score (20)', () {
      final result = CandidateScorerV2.score(
        _ctx(
            simulatedError: const ResponseErrorResult(
                rmsDb: 1.0,
                maxDeviationDb: 2.0,
                maxDeviationHz: 500.0,
                weightedRmsDb: 0.5,
                score: 95.0)),
        _policy,
      );
      // weightedRmsScore = (1 - 0.5/10) × 20 = 0.95 × 20 = 19.0.
      expect(result.scoredCandidates.first.breakdown.weightedRmsScore,
          closeTo(19.0, 0.01));
    });

    test('worst-case weighted RMS earns 0', () {
      final result = CandidateScorerV2.score(
        _ctx(
            simulatedError: const ResponseErrorResult(
                rmsDb: 10.0,
                maxDeviationDb: 10.0,
                maxDeviationHz: 1000.0,
                weightedRmsDb: 10.0,
                score: 0.0)),
        _policy,
      );
      expect(result.scoredCandidates.first.breakdown.weightedRmsScore,
          closeTo(0.0, 0.01));
    });

    test('simulatedError takes priority over currentError for items 2 and 3', () {
      final resultWithSim = CandidateScorerV2.score(
        _ctx(
          simulatedError: const ResponseErrorResult(
              rmsDb: 1.0,
              maxDeviationDb: 1.0,
              maxDeviationHz: 100.0,
              weightedRmsDb: 1.0,
              score: 90.0),
          currentError: const ResponseErrorResult(
              rmsDb: 8.0,
              maxDeviationDb: 8.0,
              maxDeviationHz: 800.0,
              weightedRmsDb: 8.0,
              score: 20.0),
        ),
        _policy,
      );
      // simulatedError.weightedRmsDb = 1.0 → (1 - 1/10) × 20 = 18.0 (not 4.0 from currentError).
      expect(resultWithSim.scoredCandidates.first.breakdown.weightedRmsScore,
          closeTo(18.0, 0.01));
    });
  });

  group('Item 4 — boost hard reject', () {
    test('candidate with gainDb > maxBoostDb (0.0) is REJECTED', () {
      // _policy has maxBoostDb = 0.0: any positive gainDb is a hard reject.
      const boostCandidate = PeqCandidate(
        candidateId: 'candidate:boost',
        featureId: 'f1',
        featureType: AcousticFeatureType.narrowPeak,
        frequencyHz: 1000.0,
        gainDb: 2.0, // exceeds maxBoostDb (0.0)
        q: 4.0,
        intent: CorrectionIntent.cut,
        reason: 'test boost',
      );
      final set = _candidateSet(candidates: [boostCandidate]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.status, ScoredCandidateSetV2Status.allRejected);
      final sc = result.scoredCandidates.first;
      expect(sc.grade, CandidateScoreGrade.rejected);
      expect(sc.totalScore, 0.0);
      expect(sc.rejectionReason, contains('maxBoostDb'));
    });
  });

  group('Item 5 — excessive Q penalty', () {
    test('Q at threshold earns full Q score (15)', () {
      final set = _candidateSet(candidates: [_candidate(q: 8.0)]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.scoredCandidates.first.breakdown.excessiveQScore,
          closeTo(15.0, 0.01));
    });

    test('Q midway between threshold and ceiling earns half Q score (~7.5)', () {
      // threshold = 8, ceiling = 14, midpoint = 11.
      // penalty = (11-8)/(14-8) = 0.5 → score = (1-0.5) × 15 = 7.5.
      final set = _candidateSet(candidates: [_candidate(q: 11.0)]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.scoredCandidates.first.breakdown.excessiveQScore,
          closeTo(7.5, 0.01));
    });

    test('Q at ceiling earns Q score 0', () {
      final set = _candidateSet(candidates: [_candidate(q: 14.0)]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.scoredCandidates.first.breakdown.excessiveQScore,
          closeTo(0.0, 0.01));
    });

    test('Q beyond ceiling earns Q score 0 (clamped)', () {
      final set = _candidateSet(candidates: [_candidate(q: 20.0)]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.scoredCandidates.first.breakdown.excessiveQScore,
          closeTo(0.0, 0.01));
    });
  });

  group('Item 6 — complexity/filter count penalty', () {
    List<PeqCandidate> nCandidates(int n) => [
          for (var i = 0; i < n; i++)
            _candidate(
                candidateId: 'candidate:f$i',
                featureId: 'f$i',
                frequencyHz: 500.0 + i * 100),
        ];

    List<AcousticObservedFeature> nFeatures(int n) => [
          for (var i = 0; i < n; i++)
            _feature(featureId: 'f$i', prominenceDb: 5.0 - i * 0.01),
        ];

    List<CorrectionDirective> nDirectives(int n) => [
          for (var i = 0; i < n; i++)
            _directive(featureId: 'f$i'),
        ];

    test('candidate count at ref (3) earns full complexity score (10)', () {
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: nCandidates(3)),
          classificationResult: _classResult(features: nFeatures(3)),
          correctionPlan: _plan(directives: nDirectives(3)),
        ),
        _policy,
      );
      expect(result.scoredCandidates.first.breakdown.complexityScore,
          closeTo(10.0, 0.01));
    });

    test('double ref count (6) earns complexity score 0', () {
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: nCandidates(6)),
          classificationResult: _classResult(features: nFeatures(6)),
          correctionPlan: _plan(directives: nDirectives(6)),
        ),
        _policy,
      );
      // excess = (6-3)/3 = 1.0 → score = 0.
      expect(result.scoredCandidates.first.breakdown.complexityScore,
          closeTo(0.0, 0.01));
    });
  });

  group('Item 9a — deepNull hard reject', () {
    test('deepNull candidate is rejected regardless of disposition', () {
      final nullCandidate = _candidate(
        featureType: AcousticFeatureType.deepNull,
        gainDb: -3.0,
      );
      final set = _candidateSet(candidates: [nullCandidate]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.status, ScoredCandidateSetV2Status.allRejected);
      final sc = result.scoredCandidates.first;
      expect(sc.grade, CandidateScoreGrade.rejected);
      expect(sc.totalScore, 0.0);
      expect(sc.rejectionReason, contains('deepNull'));
    });
  });

  group('Item 9b — blocked disposition hard reject', () {
    test('prohibitedBoost disposition rejects candidate', () {
      final set = _candidateSet(candidates: [_candidate()]);
      final plan = _plan(directives: [
        _directive(disposition: CorrectionDisposition.prohibitedBoost)
      ]);
      final result =
          CandidateScorerV2.score(_ctx(candidateSet: set, correctionPlan: plan), _policy);
      final sc = result.scoredCandidates.first;
      expect(sc.grade, CandidateScoreGrade.rejected);
      expect(sc.rejectionReason, contains('prohibitedBoost'));
    });

    test('manualReview disposition rejects candidate', () {
      final plan =
          _plan(directives: [_directive(disposition: CorrectionDisposition.manualReview)]);
      final result =
          CandidateScorerV2.score(_ctx(correctionPlan: plan), _policy);
      expect(result.scoredCandidates.first.grade, CandidateScoreGrade.rejected);
    });

    test('remeasure disposition rejects candidate', () {
      final plan =
          _plan(directives: [_directive(disposition: CorrectionDisposition.remeasure)]);
      final result =
          CandidateScorerV2.score(_ctx(correctionPlan: plan), _policy);
      expect(result.scoredCandidates.first.grade, CandidateScoreGrade.rejected);
    });
  });

  group('Item 10 — measurement confidence', () {
    test('correctableAllowed confidence earns full confidence score (5)', () {
      final result = CandidateScorerV2.score(
        _ctx(
            classificationResult:
                _classResult(confidence: MeasurementConfidenceInterpretation.correctableAllowed)),
        _policy,
      );
      expect(result.scoredCandidates.first.breakdown.confidenceScore,
          closeTo(5.0, 0.01));
    });

    test('conservative confidence earns half confidence score (2.5)', () {
      final result = CandidateScorerV2.score(
        _ctx(
            classificationResult:
                _classResult(confidence: MeasurementConfidenceInterpretation.conservative)),
        _policy,
      );
      expect(result.scoredCandidates.first.breakdown.confidenceScore,
          closeTo(2.5, 0.01));
    });

    test(
        'analysisOnly confidence scores candidates with requiresExpertApproval=true',
        () {
      final result = CandidateScorerV2.score(
        _ctx(
            classificationResult:
                _classResult(confidence: MeasurementConfidenceInterpretation.analysisOnly)),
        _policy,
      );
      // Scoring now proceeds under analysisOnly; Expert approval UI gate blocks Apply.
      expect(result.status, ScoredCandidateSetV2Status.ok);
      expect(result.scoredCandidates, isNotEmpty);
      expect(result.requiresExpertApproval, isTrue);
      // Confidence item (item 10) earns 0 pts for analysisOnly.
      expect(result.scoredCandidates.first.breakdown.confidenceScore,
          closeTo(0.0, 0.01));
    });

    test('remeasure confidence blocks entire set (insufficientEvidence)', () {
      final result = CandidateScorerV2.score(
        _ctx(
            classificationResult:
                _classResult(confidence: MeasurementConfidenceInterpretation.remeasure)),
        _policy,
      );
      expect(result.status, ScoredCandidateSetV2Status.insufficientEvidence);
      expect(result.scoredCandidates, isEmpty);
      expect(result.requiresExpertApproval, isFalse);
    });
    test('correctableAllowed confidence: requiresExpertApproval is false', () {
      final result = CandidateScorerV2.score(
        _ctx(
            classificationResult: _classResult(
                confidence: MeasurementConfidenceInterpretation.correctableAllowed)),
        _policy,
      );
      expect(result.status, ScoredCandidateSetV2Status.ok);
      expect(result.requiresExpertApproval, isFalse);
    });
    test('analysisOnly: toJson includes requiresExpertApproval=true', () {
      final result = CandidateScorerV2.score(
        _ctx(
            classificationResult:
                _classResult(confidence: MeasurementConfidenceInterpretation.analysisOnly)),
        _policy,
      );
      expect(result.toJson()['requiresExpertApproval'], isTrue);
    });
  });

  group('Score breakdown invariant', () {
    test('breakdown.total always equals totalScore', () {
      final candidates = [
        _candidate(candidateId: 'candidate:f1', featureId: 'f1', gainDb: -4.0, q: 5.0),
        _candidate(candidateId: 'candidate:f2', featureId: 'f2', gainDb: -6.0, q: 9.0,
            frequencyHz: 2000.0),
        _candidate(candidateId: 'candidate:f3', featureId: 'f3', gainDb: -2.0, q: 3.0,
            frequencyHz: 500.0),
      ];
      final features = [
        _feature(featureId: 'f1', deviationDb: -4.0, prominenceDb: 4.0),
        _feature(featureId: 'f2', deviationDb: -8.0, prominenceDb: 7.0),
        _feature(featureId: 'f3', deviationDb: -2.0, prominenceDb: 2.0),
      ];
      final directives = [
        _directive(featureId: 'f1'),
        _directive(featureId: 'f2'),
        _directive(featureId: 'f3'),
      ];
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: candidates),
          classificationResult: _classResult(features: features),
          correctionPlan: _plan(directives: directives),
          availableHeadroomDb: 12.0,
          protectionMarginDb: 4.0,
        ),
        _policy,
      );
      for (final sc in result.scoredCandidates) {
        expect(sc.totalScore, closeTo(sc.breakdown.total, 1e-9),
            reason:
                'totalScore (${sc.totalScore}) must equal breakdown.total (${sc.breakdown.total}) '
                'for ${sc.candidateRef}');
      }
    });

    test('breakdown sub-score max values sum to 100', () {
      // Max positive: 25+20+15+15+10+5+5+5 = 100. boostPenaltyScore = 0 (no boost).
      const maxBreakdown = CandidateScoreBreakdownV2(
        targetImprovementScore: 25,
        weightedRmsScore: 20,
        maxDeviationScore: 15,
        boostPenaltyScore: 0,
        excessiveQScore: 15,
        complexityScore: 10,
        headroomScore: 5,
        protectionScore: 5,
        confidenceScore: 5,
      );
      expect(maxBreakdown.total, closeTo(100.0, 1e-9));
    });
  });

  group('Ranking and tie-break', () {
    test('higher totalScore ranks first (rank 1)', () {
      final candidates = [
        _candidate(candidateId: 'candidate:f1', featureId: 'f1', gainDb: -6.0, q: 4.0),
        _candidate(candidateId: 'candidate:f2', featureId: 'f2', gainDb: -1.0, q: 4.0,
            frequencyHz: 2000.0),
      ];
      final features = [
        _feature(featureId: 'f1', deviationDb: -6.0, prominenceDb: 5.0),
        _feature(featureId: 'f2', deviationDb: -1.0, prominenceDb: 5.0),
      ];
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: candidates),
          classificationResult: _classResult(features: features),
          correctionPlan:
              _plan(directives: [_directive(featureId: 'f1'), _directive(featureId: 'f2')]),
        ),
        _policy,
      );
      // f1 corrects 6 dB (full refDb), f2 corrects only 1 dB → f1 must rank first.
      expect(result.scoredCandidates.first.candidate.featureId, 'f1');
      expect(result.scoredCandidates.first.rank, 1);
      expect(result.scoredCandidates.last.rank, 2);
    });

    test('tie-break: equal totalScore → higher prominenceDb ranks first', () {
      // Both candidates get identical structural scores (same gain, same Q, same error metrics).
      // f2 has higher prominenceDb → should rank first on tie-break.
      final candidates = [
        _candidate(candidateId: 'candidate:f1', featureId: 'f1', gainDb: -6.0, q: 4.0),
        _candidate(candidateId: 'candidate:f2', featureId: 'f2', gainDb: -6.0, q: 4.0,
            frequencyHz: 2000.0),
      ];
      final features = [
        _feature(featureId: 'f1', deviationDb: -6.0, prominenceDb: 4.0),
        _feature(featureId: 'f2', deviationDb: -6.0, prominenceDb: 8.0), // higher prominence
      ];
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: candidates),
          classificationResult: _classResult(features: features),
          correctionPlan: _plan(
              directives: [_directive(featureId: 'f1'), _directive(featureId: 'f2')]),
        ),
        _policy,
      );
      // Scores should be equal (same structural inputs).
      final sc1 = result.scoredCandidates.firstWhere((c) => c.candidate.featureId == 'f1');
      final sc2 = result.scoredCandidates.firstWhere((c) => c.candidate.featureId == 'f2');
      expect(sc1.totalScore, closeTo(sc2.totalScore, 0.01));
      // f2 has higher prominenceDb → ranks first.
      expect(result.scoredCandidates.first.candidate.featureId, 'f2');
    });

    test('tie-break: equal totalScore and equal prominence → alphabetically lower candidateId first',
        () {
      final candidates = [
        _candidate(candidateId: 'candidate:zzz', featureId: 'f1', gainDb: -6.0),
        _candidate(candidateId: 'candidate:aaa', featureId: 'f2', gainDb: -6.0,
            frequencyHz: 2000.0),
      ];
      final features = [
        _feature(featureId: 'f1', deviationDb: -6.0, prominenceDb: 5.0),
        _feature(featureId: 'f2', deviationDb: -6.0, prominenceDb: 5.0), // same prominence
      ];
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: candidates),
          classificationResult: _classResult(features: features),
          correctionPlan: _plan(
              directives: [_directive(featureId: 'f1'), _directive(featureId: 'f2')]),
        ),
        _policy,
      );
      // candidateId 'candidate:aaa' < 'candidate:zzz' → aaa ranks first.
      expect(result.scoredCandidates.first.candidateRef, 'candidate:aaa');
    });

    test('tie-break is deterministic: same input always produces same rank order', () {
      final ctx = _ctx(
        candidateSet: _candidateSet(candidates: [
          _candidate(candidateId: 'candidate:f1', featureId: 'f1', gainDb: -3.0, q: 6.0),
          _candidate(candidateId: 'candidate:f2', featureId: 'f2', gainDb: -4.0, q: 4.0,
              frequencyHz: 2000.0),
        ]),
        classificationResult: _classResult(features: [
          _feature(featureId: 'f1', deviationDb: -3.0, prominenceDb: 3.0),
          _feature(featureId: 'f2', deviationDb: -4.0, prominenceDb: 4.0),
        ]),
        correctionPlan: _plan(directives: [
          _directive(featureId: 'f1'),
          _directive(featureId: 'f2'),
        ]),
      );
      final r1 = CandidateScorerV2.score(ctx, _policy);
      final r2 = CandidateScorerV2.score(ctx, _policy);
      expect(r1.scoredCandidates.map((c) => c.candidateRef).toList(),
          equals(r2.scoredCandidates.map((c) => c.candidateRef).toList()));
    });
  });

  group('Determinism', () {
    test('identical context produces identical scores', () {
      final ctx = _ctx(
        availableHeadroomDb: 10.0,
        protectionMarginDb: 2.5,
        simulatedError: const ResponseErrorResult(
          rmsDb: 3.0,
          maxDeviationDb: 4.0,
          maxDeviationHz: 500.0,
          weightedRmsDb: 3.5,
          score: 65.0,
        ),
      );
      final r1 = CandidateScorerV2.score(ctx, _policy);
      final r2 = CandidateScorerV2.score(ctx, _policy);
      expect(r1.scoredCandidates.first.totalScore,
          equals(r2.scoredCandidates.first.totalScore));
      expect(r1.scoredCandidates.first.rank,
          equals(r2.scoredCandidates.first.rank));
    });
  });

  group('Grade assignment', () {
    test('excellent grade when totalScore >= excellentThreshold (75)', () {
      // Max score scenario: full correction, low RMS, low maxDev, good Q, few bands.
      final result = CandidateScorerV2.score(
        _ctx(
          simulatedError: const ResponseErrorResult(
              rmsDb: 0.5,
              maxDeviationDb: 0.5,
              maxDeviationHz: 50.0,
              weightedRmsDb: 0.1,
              score: 99.0),
          availableHeadroomDb: 12.0,
          protectionMarginDb: 5.0,
        ),
        _policy,
      );
      expect(result.scoredCandidates.first.grade, CandidateScoreGrade.excellent);
    });

    test('rejected grade when totalScore < rejectionThreshold (20)', () {
      // Score components that sum to < 20:
      // targetImprovement: min(0.1, 0.1)/6 × 25 ≈ 0.4
      // weightedRmsScore:  (1-9.8/10) × 20 = 0.4
      // maxDeviationScore: (1-14.5/15) × 15 = 0.5
      // excessiveQScore:   q=13.9 → (1-(5.9/6)) × 15 ≈ 0.25
      // complexityScore:   6 bands (2× ref) → 0
      // headroomScore:     null → 2.5
      // protectionScore:   null → 2.5
      // confidenceScore:   conservative → 2.5
      // Total ≈ 9 → well below rejectionThreshold (20).
      final candidates = [
        for (var i = 0; i < 6; i++)
          _candidate(
            candidateId: 'candidate:f$i',
            featureId: 'f$i',
            gainDb: -0.1,
            q: 13.9,
            frequencyHz: 500.0 + i * 200,
          ),
      ];
      final features = [
        for (var i = 0; i < 6; i++)
          _feature(featureId: 'f$i', deviationDb: -0.1, prominenceDb: 1.0),
      ];
      final directives = [
        for (var i = 0; i < 6; i++) _directive(featureId: 'f$i'),
      ];
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: candidates),
          classificationResult: _classResult(
            features: features,
            confidence: MeasurementConfidenceInterpretation.conservative,
            residualSummary: const ResidualSummary(
                rmsDb: 9.8, maxAbsDeviationDb: 14.5, maxAbsDeviationHz: 500.0),
          ),
          correctionPlan: _plan(directives: directives),
        ),
        _policy,
      );
      expect(result.scoredCandidates.first.grade, CandidateScoreGrade.rejected);
    });
  });

  group('Set-level status propagation', () {
    test('non-ok CandidateSet status is propagated without scoring', () {
      final emptySet = _candidateSet(
        candidates: const [],
        status: CandidateSetStatus.insufficientEvidence,
      );
      final result =
          CandidateScorerV2.score(_ctx(candidateSet: emptySet), _policy);
      expect(result.status, ScoredCandidateSetV2Status.insufficientEvidence);
      expect(result.scoredCandidates, isEmpty);
    });

    test('noCorrectableDirectives propagates', () {
      final set = _candidateSet(
        candidates: const [],
        status: CandidateSetStatus.noCorrectableDirectives,
      );
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.status, ScoredCandidateSetV2Status.noCorrectableDirectives);
    });

    test('allRejected when every candidate is hard-rejected', () {
      // gainDb = 3.0 > maxBoostDb (0.0) → hard reject.
      const boostCandidate = PeqCandidate(
        candidateId: 'candidate:boost',
        featureId: 'f1',
        featureType: AcousticFeatureType.narrowPeak,
        frequencyHz: 1000.0,
        gainDb: 3.0,
        q: 4.0,
        intent: CorrectionIntent.cut,
        reason: 'test',
      );
      final set = _candidateSet(candidates: [boostCandidate]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.status, ScoredCandidateSetV2Status.allRejected);
    });

    test('accepted returns only non-rejected candidates', () {
      final candidates = [
        _candidate(candidateId: 'candidate:f1', featureId: 'f1', gainDb: -6.0),
        const PeqCandidate(
          candidateId: 'candidate:f2',
          featureId: 'f2',
          featureType: AcousticFeatureType.deepNull,
          frequencyHz: 2000.0,
          gainDb: -2.0,
          q: 3.0,
          intent: CorrectionIntent.cut,
          reason: 'deep null test',
        ),
      ];
      final features = [
        _feature(featureId: 'f1', deviationDb: -6.0),
        _feature(featureId: 'f2', type: AcousticFeatureType.deepNull, deviationDb: -2.0),
      ];
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: candidates),
          classificationResult: _classResult(features: features),
          correctionPlan: _plan(directives: [
            _directive(featureId: 'f1'),
            _directive(featureId: 'f2',
                featureType: AcousticFeatureType.deepNull),
          ]),
        ),
        _policy,
      );
      expect(result.scoredCandidates.length, 2);
      expect(result.accepted.length, 1);
      expect(result.accepted.first.candidate.featureId, 'f1');
    });
  });

  group('Items 7 & 8 — headroom and protection', () {
    test('Project protection rules provide real headroom and margin evidence', () {
      final now = DateTime(2026, 8, 1);
      final evidence = CandidateScoringResourceEvidence.fromProject(ProProject(
        id: 'p',
        name: 'p',
        createdAt: now,
        updatedAt: now,
        protectionState: ProtectionProjectState(
          verificationStatus: VerificationStatus.passed,
          rules: ProtectionProjectState.createDefault().rules,
        ),
      ));
      expect(evidence.availableHeadroomDb, closeTo(6.0, 0.01));
      expect(evidence.protectionMarginDb, closeTo(12.0, 0.01));
    });

    test('unverified protection keeps resource evidence unknown', () {
      final now = DateTime(2026, 8, 1);
      final evidence = CandidateScoringResourceEvidence.fromProject(ProProject(
        id: 'p', name: 'p', createdAt: now, updatedAt: now));
      expect(evidence.availableHeadroomDb, isNull);
      expect(evidence.protectionMarginDb, isNull);
    });

    test('null headroom earns neutral half-score (2.5)', () {
      final result =
          CandidateScorerV2.score(_ctx(availableHeadroomDb: null), _policy);
      expect(result.scoredCandidates.first.breakdown.headroomScore,
          closeTo(2.5, 0.01));
    });

    test('null protection margin earns neutral half-score (2.5)', () {
      final result =
          CandidateScorerV2.score(_ctx(protectionMarginDb: null), _policy);
      expect(result.scoredCandidates.first.breakdown.protectionScore,
          closeTo(2.5, 0.01));
    });

    test('ample headroom earns full headroom score (5)', () {
      // gainDb = -6, headroom = 12 → used = 0.5 ≤ 0.7 penalty ratio → full.
      final result =
          CandidateScorerV2.score(_ctx(availableHeadroomDb: 12.0), _policy);
      expect(result.scoredCandidates.first.breakdown.headroomScore,
          closeTo(5.0, 0.01));
    });

    test('sufficient protection earns full protection score (5)', () {
      // protectionMarginDb = 6 ≥ policy.protectionMinMarginDb = 3 → score = 5.
      final result =
          CandidateScorerV2.score(_ctx(protectionMarginDb: 6.0), _policy);
      expect(result.scoredCandidates.first.breakdown.protectionScore,
          closeTo(5.0, 0.01));
    });

    test('zero protection margin earns 0 protection score', () {
      final result =
          CandidateScorerV2.score(_ctx(protectionMarginDb: 0.0), _policy);
      expect(result.scoredCandidates.first.breakdown.protectionScore,
          closeTo(0.0, 0.01));
    });
  });

  group('policyId and version propagate to result', () {
    test('result carries policy id and version', () {
      final result = CandidateScorerV2.score(_ctx(), _policy);
      expect(result.policyId, 'test_policy');
      expect(result.policyVersion, 1);
    });
  });

  group('toJson — smoke tests', () {
    test('ScoredCandidateSetV2.toJson produces serializable map', () {
      final result = CandidateScorerV2.score(_ctx(), _policy);
      final json = result.toJson();
      expect(json['status'], isA<String>());
      expect(json['scoredCandidates'], isA<List>());
      expect((json['scoredCandidates'] as List).first['totalScore'],
          isA<double>());
    });
  });

  // ── New Task 2 tests ───────────────────────────────────────────────────────

  group('Item 4 — boost penalty (maxBoostDb > 0)', () {
    // Policy that allows up to 3 dB boost before hard-rejecting.
    const boostPolicy = CandidateScoringPolicyV2(
      id: 'boost_test',
      version: 1,
      targetImprovementRefDb: 6.0,
      weightedRmsWorstDb: 10.0,
      maxDeviationWorstDb: 15.0,
      maxBoostDb: 3.0,
      excessiveQThreshold: 8.0,
      excessiveQCeilingQ: 14.0,
      complexityRefBands: 3,
      headroomPenaltyRatio: 0.7,
      protectionMinMarginDb: 3.0,
      rejectionThreshold: 20.0,
      goodThreshold: 50.0,
      excellentThreshold: 75.0,
    );

    test('gainDb within allowed range earns negative boostPenaltyScore, not rejected', () {
      // gainDb = 1.5, maxBoostDb = 3.0 → fraction = 0.5 → penalty = -(0.5 × 30) = -15.
      const boostedCandidate = PeqCandidate(
        candidateId: 'candidate:f1',
        featureId: 'f1',
        featureType: AcousticFeatureType.narrowPeak,
        frequencyHz: 1000.0,
        gainDb: 1.5,
        q: 4.0,
        intent: CorrectionIntent.cut,
        reason: 'within-boost-range test',
      );
      final set = _candidateSet(candidates: [boostedCandidate]);
      final result = CandidateScorerV2.score(
        _ctx(candidateSet: set, nullCorrectionPlan: true),
        boostPolicy,
      );
      final sc = result.scoredCandidates.first;
      expect(sc.grade, isNot(CandidateScoreGrade.rejected));
      expect(sc.breakdown.boostPenaltyScore, closeTo(-15.0, 0.01));
      expect(sc.totalScore, closeTo(sc.breakdown.total, 1e-9));
    });

    test('gainDb at full maxBoostDb earns maximum penalty of -30', () {
      const boostedCandidate = PeqCandidate(
        candidateId: 'candidate:f1',
        featureId: 'f1',
        featureType: AcousticFeatureType.narrowPeak,
        frequencyHz: 1000.0,
        gainDb: 3.0, // exactly maxBoostDb → fraction = 1.0 → penalty = -30
        q: 4.0,
        intent: CorrectionIntent.cut,
        reason: 'max-boost-range test',
      );
      final set = _candidateSet(candidates: [boostedCandidate]);
      final result = CandidateScorerV2.score(
        _ctx(candidateSet: set, nullCorrectionPlan: true),
        boostPolicy,
      );
      final sc = result.scoredCandidates.first;
      expect(sc.grade, isNot(CandidateScoreGrade.rejected));
      expect(sc.breakdown.boostPenaltyScore, closeTo(-30.0, 0.01));
    });

    test('gainDb exceeding maxBoostDb is hard-rejected', () {
      const tooMuchBoost = PeqCandidate(
        candidateId: 'candidate:f1',
        featureId: 'f1',
        featureType: AcousticFeatureType.narrowPeak,
        frequencyHz: 1000.0,
        gainDb: 3.1, // exceeds maxBoostDb (3.0)
        q: 4.0,
        intent: CorrectionIntent.cut,
        reason: 'over-max-boost test',
      );
      final set = _candidateSet(candidates: [tooMuchBoost]);
      final result = CandidateScorerV2.score(
        _ctx(candidateSet: set, nullCorrectionPlan: true),
        boostPolicy,
      );
      final sc = result.scoredCandidates.first;
      expect(sc.grade, CandidateScoreGrade.rejected);
      expect(sc.totalScore, 0.0);
      expect(sc.rejectionReason, contains('maxBoostDb'));
    });

    test('zero boost (gainDb = 0) earns zero boostPenaltyScore', () {
      final result = CandidateScorerV2.score(
        _ctx(candidateSet: _candidateSet(candidates: [_candidate(gainDb: 0.0)])),
        boostPolicy,
      );
      expect(result.scoredCandidates.first.breakdown.boostPenaltyScore, 0.0);
    });
  });

  group('bestCandidate and alternatives', () {
    List<PeqCandidate> threeCandidates() => [
          _candidate(
              candidateId: 'candidate:f1',
              featureId: 'f1',
              gainDb: -6.0,
              frequencyHz: 1000.0),
          _candidate(
              candidateId: 'candidate:f2',
              featureId: 'f2',
              gainDb: -3.0,
              frequencyHz: 2000.0),
          _candidate(
              candidateId: 'candidate:f3',
              featureId: 'f3',
              gainDb: -1.0,
              frequencyHz: 3000.0),
        ];

    List<AcousticObservedFeature> threeFeatures() => [
          _feature(featureId: 'f1', deviationDb: -6.0, prominenceDb: 6.0),
          _feature(featureId: 'f2', deviationDb: -3.0, prominenceDb: 3.0),
          _feature(featureId: 'f3', deviationDb: -1.0, prominenceDb: 1.0),
        ];

    List<CorrectionDirective> threeDirectives() => [
          _directive(featureId: 'f1'),
          _directive(featureId: 'f2'),
          _directive(featureId: 'f3'),
        ];

    test('bestCandidate is the rank-1 accepted candidate', () {
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: threeCandidates()),
          classificationResult: _classResult(features: threeFeatures()),
          correctionPlan: _plan(directives: threeDirectives()),
        ),
        _policy,
      );
      expect(result.bestCandidate, isNotNull);
      expect(result.bestCandidate!.rank, 1);
      expect(result.bestCandidate!.grade, isNot(CandidateScoreGrade.rejected));
    });

    test('alternatives returns at most 2 accepted candidates after bestCandidate', () {
      final result = CandidateScorerV2.score(
        _ctx(
          candidateSet: _candidateSet(candidates: threeCandidates()),
          classificationResult: _classResult(features: threeFeatures()),
          correctionPlan: _plan(directives: threeDirectives()),
        ),
        _policy,
      );
      final alts = result.alternatives;
      expect(alts.length, lessThanOrEqualTo(2));
      for (final alt in alts) {
        expect(alt.grade, isNot(CandidateScoreGrade.rejected));
        expect(alt.rank, greaterThan(result.bestCandidate!.rank));
      }
    });

    test('alternatives are empty when only one accepted candidate exists', () {
      final result = CandidateScorerV2.score(_ctx(), _policy);
      // Single candidate → no alternatives.
      expect(result.accepted.length, 1);
      expect(result.alternatives, isEmpty);
    });

    test('bestCandidate is null when all candidates are rejected', () {
      const boostCandidate = PeqCandidate(
        candidateId: 'candidate:boost',
        featureId: 'f1',
        featureType: AcousticFeatureType.narrowPeak,
        frequencyHz: 1000.0,
        gainDb: 5.0,
        q: 4.0,
        intent: CorrectionIntent.cut,
        reason: 'reject test',
      );
      final set = _candidateSet(candidates: [boostCandidate]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      expect(result.bestCandidate, isNull);
      expect(result.alternatives, isEmpty);
    });
  });

  group('perCandidateSimulatedError — items 2 and 3', () {
    test('after weighted RMS >= before is hard-rejected', () {
      const before = ResponseErrorResult(
          rmsDb: 3,
          maxDeviationDb: 6,
          maxDeviationHz: 1000,
          weightedRmsDb: 3,
          score: 70);
      const after = ResponseErrorResult(
          rmsDb: 3.2,
          maxDeviationDb: 6,
          maxDeviationHz: 1000,
          weightedRmsDb: 3,
          score: 65);

      final result = CandidateScorerV2.score(
        _ctx(
          currentError: before,
          perCandidateSimulatedError: const {'candidate:f1': after},
        ),
        _policy,
      );

      expect(result.scoredCandidates.single.grade,
          CandidateScoreGrade.rejected);
      expect(result.scoredCandidates.single.rejectionReason,
          contains('does not improve'));
    });

    test('per-candidate error overrides shared simulatedError for items 2 & 3', () {
      // f1 has terrible per-candidate error, f2 uses the shared error.
      final candidates = [
        _candidate(
            candidateId: 'candidate:f1',
            featureId: 'f1',
            gainDb: -6.0,
            frequencyHz: 1000.0),
        _candidate(
            candidateId: 'candidate:f2',
            featureId: 'f2',
            gainDb: -6.0,
            frequencyHz: 2000.0),
      ];
      final features = [
        _feature(featureId: 'f1', deviationDb: -6.0, prominenceDb: 6.0),
        _feature(featureId: 'f2', deviationDb: -6.0, prominenceDb: 6.0),
      ];
      final directives = [_directive(featureId: 'f1'), _directive(featureId: 'f2')];

      final result = CandidateScorerV2.score(
        CandidateScoringContextV2(
          candidateSet: _candidateSet(candidates: candidates),
          classificationResult: _classResult(features: features),
          correctionPlan: _plan(directives: directives),
          // Shared error: perfect scores for items 2 & 3.
          simulatedError: const ResponseErrorResult(
              rmsDb: 0.1,
              maxDeviationDb: 0.1,
              maxDeviationHz: 100.0,
              weightedRmsDb: 0.1,
              score: 99.0),
          // Per-candidate override for f1: worst-case scores.
          perCandidateSimulatedError: {
            'candidate:f1': const ResponseErrorResult(
                rmsDb: 10.0,
                maxDeviationDb: 15.0,
                maxDeviationHz: 1000.0,
                weightedRmsDb: 10.0,
                score: 0.0),
          },
        ),
        _policy,
      );

      final sc1 = result.scoredCandidates
          .firstWhere((c) => c.candidateRef == 'candidate:f1');
      final sc2 = result.scoredCandidates
          .firstWhere((c) => c.candidateRef == 'candidate:f2');

      // f1 has per-candidate worst-case error → items 2 & 3 are near 0.
      expect(sc1.breakdown.weightedRmsScore, closeTo(0.0, 0.01));
      expect(sc1.breakdown.maxDeviationScore, closeTo(0.0, 0.01));

      // f2 uses shared near-perfect error → items 2 & 3 are near max.
      expect(sc2.breakdown.weightedRmsScore, greaterThan(19.0));
      expect(sc2.breakdown.maxDeviationScore, greaterThan(14.0));

      // f2 ranks higher than f1 because of per-candidate error difference.
      expect(sc2.rank, lessThan(sc1.rank));
    });
  });

  group('toAiJson — no DSP fields', () {
    test('ScoredCandidateV2.toAiJson does not contain gainDb, q, frequencyHz', () {
      final result = CandidateScorerV2.score(_ctx(), _policy);
      final aiJson = result.scoredCandidates.first.toAiJson();
      expect(aiJson.containsKey('gainDb'), isFalse);
      expect(aiJson.containsKey('q'), isFalse);
      expect(aiJson.containsKey('frequencyHz'), isFalse);
      expect(aiJson.containsKey('featureId'), isFalse);
      expect(aiJson.containsKey('candidateId'), isFalse);
    });

    test('ScoredCandidateV2.toAiJson contains candidateRef, rank, totalScore, grade', () {
      final result = CandidateScorerV2.score(_ctx(), _policy);
      final aiJson = result.scoredCandidates.first.toAiJson();
      expect(aiJson.containsKey('candidateRef'), isTrue);
      expect(aiJson.containsKey('rank'), isTrue);
      expect(aiJson.containsKey('totalScore'), isTrue);
      expect(aiJson.containsKey('grade'), isTrue);
    });

    test('ScoredCandidateSetV2.toAiJson does not contain gainDb, q, frequencyHz', () {
      final result = CandidateScorerV2.score(_ctx(), _policy);
      final aiJson = result.toAiJson();
      final candidates = aiJson['scoredCandidates'] as List;
      for (final c in candidates) {
        final m = c as Map<String, dynamic>;
        expect(m.containsKey('gainDb'), isFalse);
        expect(m.containsKey('q'), isFalse);
        expect(m.containsKey('frequencyHz'), isFalse);
      }
    });

    test('ScoredCandidateSetV2.toAiJson contains status and scoredCandidates', () {
      final result = CandidateScorerV2.score(_ctx(), _policy);
      final aiJson = result.toAiJson();
      expect(aiJson.containsKey('status'), isTrue);
      expect(aiJson.containsKey('scoredCandidates'), isTrue);
    });

    test('rejected candidate toAiJson includes rejectionReason', () {
      const boostCandidate = PeqCandidate(
        candidateId: 'candidate:boost',
        featureId: 'f1',
        featureType: AcousticFeatureType.narrowPeak,
        frequencyHz: 1000.0,
        gainDb: 2.0,
        q: 4.0,
        intent: CorrectionIntent.cut,
        reason: 'boost test',
      );
      final set = _candidateSet(candidates: [boostCandidate]);
      final result = CandidateScorerV2.score(_ctx(candidateSet: set), _policy);
      final aiJson = result.scoredCandidates.first.toAiJson();
      expect(aiJson.containsKey('rejectionReason'), isTrue);
      expect(aiJson['rejectionReason'], isA<String>());
    });
  });

  group('nullable correctionPlan — disposition check skipped', () {
    test('null correctionPlan allows correctable candidate through', () {
      // Without a plan, even a candidate that would match a blocked directive
      // is scored normally (disposition check skipped).
      final result = CandidateScorerV2.score(
        _ctx(nullCorrectionPlan: true),
        _policy,
      );
      expect(result.status, ScoredCandidateSetV2Status.ok);
      expect(result.scoredCandidates.first.grade,
          isNot(CandidateScoreGrade.rejected));
    });

    test('null correctionPlan does not cause error', () {
      expect(
        () => CandidateScorerV2.score(
          _ctx(nullCorrectionPlan: true),
          _policy,
        ),
        returnsNormally,
      );
    });
  });
}
