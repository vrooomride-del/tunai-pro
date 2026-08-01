import 'dart:math' as math;

import 'acoustic_problem_classifier.dart';
import 'candidate_scoring.dart' show CandidateScoreGrade;
import 'candidate_set.dart';
import 'correction_plan.dart';
import '../pro_response_error.dart';

/// Candidate Scoring v2 — deterministic 10-item scoring/ranking engine.
///
/// Extends the v1 observation-only scorer with simulation-aware metrics,
/// penalty scoring, and hard-reject guards. All values come from the caller;
/// this layer produces NO DSP address, gain command, hardware payload, or
/// biquad coefficient. No LLM value generation is involved.
///
/// ## Score breakdown (max 100 pts positive + boost penalty)
///
/// | # | Item                   | Max  | Nature           |
/// |---|------------------------|------|------------------|
/// | 1 | Target improvement     |  25  | scored           |
/// | 2 | Weighted RMS error     |  20  | scored           |
/// | 3 | Maximum deviation      |  15  | scored           |
/// | 4 | Boost                  |  —   | penalty / reject |
/// | 5 | Excessive Q            |  15  | penalty          |
/// | 6 | Filter count/complexity|  10  | penalty          |
/// | 7 | Headroom               |   5  | penalty          |
/// | 8 | Protection margin      |   5  | scored           |
/// | 9 | Blocked/disposition    |   —  | hard reject      |
/// |10 | Measurement confidence |   5  | scored           |
///
/// Item 4 (boost) is handled by policy threshold:
///   gainDb > policy.maxBoostDb → hard reject.
///   0 < gainDb ≤ maxBoostDb   → boost penalty deducted from total (up to −30).
///   gainDb ≤ 0                → no boost penalty.
///
/// Items 2 and 3 use per-candidate simulation error when available in
/// [CandidateScoringContextV2.perCandidateSimulatedError]; otherwise the
/// shared set-level error is used.
///
/// Hard-reject candidates receive `totalScore = 0`, `grade = rejected`.
/// Non-rejected candidates receive `totalScore = breakdown.total ∈ [0, 100]`.
///
/// Ranking: `totalScore` descending → `prominenceDb` descending →
/// `candidateId` ascending (deterministic tie-break).

// ── Policy ────────────────────────────────────────────────────────────────────

class ScoringV2PolicyException implements Exception {
  final String message;
  ScoringV2PolicyException(this.message);
  @override
  String toString() => 'ScoringV2PolicyException: $message';
}

/// Numerical thresholds that govern v2 score computation.
/// Carries no DSP address, hardware value, or biquad coefficient.
class CandidateScoringPolicyV2 {
  final String id;
  final int version;

  /// Item 1 — deviation (dB) that maps to the full targetImprovementScore of 25.
  /// Features corrected at or above this amplitude receive the maximum sub-score.
  final double targetImprovementRefDb;

  /// Item 2 — weighted RMS error (dB) at or above which the rms sub-score is 0.
  final double weightedRmsWorstDb;

  /// Item 3 — maximum per-point deviation (dB) at or above which the deviation
  /// sub-score is 0.
  final double maxDeviationWorstDb;

  /// Item 4 — boost threshold.
  ///
  /// When [gainDb > maxBoostDb]: hard reject.
  /// When [0 < gainDb ≤ maxBoostDb]: boost penalty deducted from totalScore
  ///   (penalty = gainDb/maxBoostDb × 30, capped at 30 pts).
  /// When [gainDb ≤ 0]: no boost involvement.
  ///
  /// Set to 0.0 to reject any positive gainDb immediately (default behaviour
  /// for `proProvisional` — the candidate generator already produces cuts only).
  final double maxBoostDb;

  /// Lower gain bound for device-specific envelopes.
  final double minGainDb;

  /// Item 5 — Q at or below this value receives no Q penalty (full 15 pts).
  final double excessiveQThreshold;

  /// Item 5 — Q at or above this ceiling receives Q score 0 (maximum penalty).
  /// Must be > [excessiveQThreshold].
  final double excessiveQCeilingQ;

  /// Item 6 — candidate count at or below this reference receives no complexity
  /// penalty (full 10 pts).
  final int complexityRefBands;

  /// Item 7 — fraction of available headroom used below which no penalty applies.
  /// Above this ratio, the headroom score decreases linearly to 0 at ratio = 1.0.
  final double headroomPenaltyRatio;

  /// Item 8 — protection margin (dB) at or above which the full protection score
  /// of 5 is awarded.
  final double protectionMinMarginDb;

  // Grade thresholds on [0, 100] totalScore (after boost penalty).
  final double rejectionThreshold;
  final double goodThreshold;
  final double excellentThreshold;

  const CandidateScoringPolicyV2({
    required this.id,
    required this.version,
    required this.targetImprovementRefDb,
    required this.weightedRmsWorstDb,
    required this.maxDeviationWorstDb,
    required this.maxBoostDb,
    this.minGainDb = double.negativeInfinity,
    required this.excessiveQThreshold,
    required this.excessiveQCeilingQ,
    required this.complexityRefBands,
    required this.headroomPenaltyRatio,
    required this.protectionMinMarginDb,
    required this.rejectionThreshold,
    required this.goodThreshold,
    required this.excellentThreshold,
  });

  void validate() {
    if (id.isEmpty) throw ScoringV2PolicyException('id must not be empty.');
    if (version < 1) throw ScoringV2PolicyException('version must be >= 1.');
    if (!targetImprovementRefDb.isFinite || targetImprovementRefDb <= 0) {
      throw ScoringV2PolicyException(
          'targetImprovementRefDb must be finite and > 0.');
    }
    if (!weightedRmsWorstDb.isFinite || weightedRmsWorstDb <= 0) {
      throw ScoringV2PolicyException(
          'weightedRmsWorstDb must be finite and > 0.');
    }
    if (!maxDeviationWorstDb.isFinite || maxDeviationWorstDb <= 0) {
      throw ScoringV2PolicyException(
          'maxDeviationWorstDb must be finite and > 0.');
    }
    if (!maxBoostDb.isFinite || maxBoostDb < 0) {
      throw ScoringV2PolicyException('maxBoostDb must be finite and >= 0.');
    }
    if (minGainDb.isNaN || minGainDb > maxBoostDb) {
      throw ScoringV2PolicyException('minGainDb must be <= maxBoostDb.');
    }
    if (!excessiveQThreshold.isFinite || excessiveQThreshold <= 0) {
      throw ScoringV2PolicyException(
          'excessiveQThreshold must be finite and > 0.');
    }
    if (!excessiveQCeilingQ.isFinite ||
        excessiveQCeilingQ <= excessiveQThreshold) {
      throw ScoringV2PolicyException(
          'excessiveQCeilingQ must be finite and > excessiveQThreshold.');
    }
    if (complexityRefBands < 1) {
      throw ScoringV2PolicyException('complexityRefBands must be >= 1.');
    }
    if (!headroomPenaltyRatio.isFinite ||
        headroomPenaltyRatio <= 0 ||
        headroomPenaltyRatio > 1) {
      throw ScoringV2PolicyException('headroomPenaltyRatio must be in (0, 1].');
    }
    if (!protectionMinMarginDb.isFinite || protectionMinMarginDb <= 0) {
      throw ScoringV2PolicyException(
          'protectionMinMarginDb must be finite and > 0.');
    }
    if (!rejectionThreshold.isFinite ||
        rejectionThreshold < 0 ||
        rejectionThreshold >= 100) {
      throw ScoringV2PolicyException(
          'rejectionThreshold must be finite and in [0, 100).');
    }
    if (!goodThreshold.isFinite || goodThreshold <= rejectionThreshold) {
      throw ScoringV2PolicyException(
          'goodThreshold must be finite and > rejectionThreshold.');
    }
    if (!excellentThreshold.isFinite ||
        excellentThreshold <= goodThreshold ||
        excellentThreshold > 100) {
      throw ScoringV2PolicyException(
          'excellentThreshold must be in (goodThreshold, 100].');
    }
  }

  /// PRO provisional v2 scoring policy.
  ///
  /// [maxBoostDb] = 0 means any boost is immediately rejected (the candidate
  /// generator always produces cuts, so this is a safety guard only).
  factory CandidateScoringPolicyV2.proProvisional() =>
      const CandidateScoringPolicyV2(
        id: 'pro_provisional_v2',
        version: 2,
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

  factory CandidateScoringPolicyV2.adau1701Icp5() =>
      const CandidateScoringPolicyV2(
        id: 'adau1701_icp5_v2',
        version: 2,
        targetImprovementRefDb: 6.0,
        weightedRmsWorstDb: 10.0,
        maxDeviationWorstDb: 15.0,
        maxBoostDb: 3.0,
        minGainDb: -6.0,
        excessiveQThreshold: 8.0,
        excessiveQCeilingQ: 14.0,
        complexityRefBands: 3,
        headroomPenaltyRatio: 0.7,
        protectionMinMarginDb: 3.0,
        rejectionThreshold: 20.0,
        goodThreshold: 50.0,
        excellentThreshold: 75.0,
      );
}

// ── Scoring context ───────────────────────────────────────────────────────────

/// All inputs the v2 scorer requires. Immutable value object; holds no
/// DSP address, hardware command, or hardware value.
class CandidateScoringContextV2 {
  final CandidateSet candidateSet;
  final AcousticClassificationResult classificationResult;

  /// Correction plan for Item 9b disposition check (optional).
  /// When null, the disposition check is skipped — the candidate generator
  /// already filters non-correctable directives, so this is a safety guard.
  final CorrectionPlan? correctionPlan;

  /// Pre-correction response error from measurement (optional).
  /// Used for items 2 and 3 when [simulatedError] and
  /// [perCandidateSimulatedError] are both absent.
  final ResponseErrorResult? currentError;

  /// Post-correction simulated response error for the whole set (optional).
  /// When present, preferred over [currentError] for items 2 and 3 unless a
  /// per-candidate entry exists in [perCandidateSimulatedError].
  final ResponseErrorResult? simulatedError;

  /// Per-candidate simulation errors keyed by [PeqCandidate.candidateId].
  ///
  /// When a candidate's id is present here, its entry is used for items 2
  /// and 3 instead of the shared [simulatedError] / [currentError].
  /// This allows the caller to provide candidate-specific residuals from
  /// separate simulation runs.
  final Map<String, ResponseErrorResult>? perCandidateSimulatedError;

  /// Available acoustic/DSP headroom in dB (optional).
  /// When null, item 7 defaults to a neutral half-score.
  final double? availableHeadroomDb;

  /// Available protection margin in dB above the protection threshold (optional).
  /// When null, item 8 defaults to a conservative half-score.
  final double? protectionMarginDb;

  const CandidateScoringContextV2({
    required this.candidateSet,
    required this.classificationResult,
    this.correctionPlan,
    this.currentError,
    this.simulatedError,
    this.perCandidateSimulatedError,
    this.availableHeadroomDb,
    this.protectionMarginDb,
  });
}

// ── Breakdown ─────────────────────────────────────────────────────────────────

/// 10-item score breakdown. [total] always equals the sum of all sub-scores
/// (including [boostPenaltyScore] which is ≤ 0) and must equal the candidate's
/// [ScoredCandidateV2.totalScore].
///
/// Hard-reject candidates (boost > maxBoostDb, deepNull, prohibited disposition)
/// receive [zero] breakdown; their rejection is expressed via
/// [CandidateScoreGrade.rejected] and [ScoredCandidateV2.rejectionReason].
class CandidateScoreBreakdownV2 {
  /// Item 1 — correction of observed deviation. ∈ [0, 25].
  final double targetImprovementScore;

  /// Item 2 — weighted RMS error quality. ∈ [0, 20].
  final double weightedRmsScore;

  /// Item 3 — maximum per-point deviation quality. ∈ [0, 15].
  final double maxDeviationScore;

  /// Item 4 — boost penalty (≤ 0). Zero when gainDb ≤ 0.
  /// Applied when 0 < gainDb ≤ policy.maxBoostDb (within allowed boost range).
  /// Hard-reject candidates have zero here (they receive grade = rejected instead).
  final double boostPenaltyScore;

  /// Item 5 — Q penalty score (15 = no penalty, 0 = excessive Q). ∈ [0, 15].
  final double excessiveQScore;

  /// Item 6 — complexity penalty score (10 = low count, 0 = many bands). ∈ [0, 10].
  final double complexityScore;

  /// Item 7 — headroom score (5 = ample headroom, 0 = ceiling). ∈ [0, 5].
  final double headroomScore;

  /// Item 8 — protection margin score. ∈ [0, 5].
  final double protectionScore;

  /// Item 10 — measurement confidence score. ∈ [0, 5].
  final double confidenceScore;

  const CandidateScoreBreakdownV2({
    required this.targetImprovementScore,
    required this.weightedRmsScore,
    required this.maxDeviationScore,
    required this.boostPenaltyScore,
    required this.excessiveQScore,
    required this.complexityScore,
    required this.headroomScore,
    required this.protectionScore,
    required this.confidenceScore,
  });

  /// Sum of all sub-scores. Invariant: must equal [ScoredCandidateV2.totalScore]
  /// for every non-rejected candidate.
  double get total =>
      targetImprovementScore +
      weightedRmsScore +
      maxDeviationScore +
      boostPenaltyScore +
      excessiveQScore +
      complexityScore +
      headroomScore +
      protectionScore +
      confidenceScore;

  static const CandidateScoreBreakdownV2 zero = CandidateScoreBreakdownV2(
    targetImprovementScore: 0,
    weightedRmsScore: 0,
    maxDeviationScore: 0,
    boostPenaltyScore: 0,
    excessiveQScore: 0,
    complexityScore: 0,
    headroomScore: 0,
    protectionScore: 0,
    confidenceScore: 0,
  );

  Map<String, dynamic> toJson() => {
        'targetImprovementScore': targetImprovementScore,
        'weightedRmsScore': weightedRmsScore,
        'maxDeviationScore': maxDeviationScore,
        'boostPenaltyScore': boostPenaltyScore,
        'excessiveQScore': excessiveQScore,
        'complexityScore': complexityScore,
        'headroomScore': headroomScore,
        'protectionScore': protectionScore,
        'confidenceScore': confidenceScore,
        'total': total,
      };
}

// ── Status ────────────────────────────────────────────────────────────────────

enum ScoredCandidateSetV2Status {
  /// Scoring completed; at least one non-rejected candidate exists.
  ok,

  /// Scoring completed but every candidate was rejected.
  allRejected,

  /// Blocked by confidence interpretation (analysisOnly or remeasure).
  /// No candidates were scored — automatic promotion is prohibited.
  insufficientEvidence,

  /// Propagated from [CandidateSetStatus.noCorrectableDirectives].
  noCorrectableDirectives,

  /// Propagated from any non-ok [CandidateSetStatus].
  invalidPlan,
}

// ── Output models ─────────────────────────────────────────────────────────────

/// A [PeqCandidate] annotated with a v2 10-item score breakdown and a rank.
class ScoredCandidateV2 {
  /// Opaque reference equal to [candidate.candidateId].
  final String candidateRef;

  final PeqCandidate candidate;

  /// Total score ∈ [0, 100]. Always equals [breakdown.total] clamped.
  /// Hard-rejected candidates receive 0.
  final double totalScore;

  final CandidateScoreBreakdownV2 breakdown;

  final CandidateScoreGrade grade;

  /// 1-based rank within the [ScoredCandidateSetV2] (1 = best).
  final int rank;

  /// Non-null when the candidate was hard-rejected (boost > maxBoostDb, deepNull,
  /// or prohibited disposition). Describes the blocking reason.
  final String? rejectionReason;

  /// Human-readable scoring evidence referencing measurement/plan artifacts.
  final List<String> explanationEvidenceRefs;

  const ScoredCandidateV2({
    required this.candidateRef,
    required this.candidate,
    required this.totalScore,
    required this.breakdown,
    required this.grade,
    required this.rank,
    this.rejectionReason,
    required this.explanationEvidenceRefs,
  });

  /// Full JSON including DSP-adjacent values (frequencyHz/gainDb/q).
  /// For internal store and debugging only — do not send to Cloud/AI.
  Map<String, dynamic> toJson() => {
        'candidateRef': candidateRef,
        'candidateId': candidate.candidateId,
        'featureId': candidate.featureId,
        'frequencyHz': candidate.frequencyHz,
        'gainDb': candidate.gainDb,
        'q': candidate.q,
        'totalScore': totalScore,
        'breakdown': breakdown.toJson(),
        'grade': grade.name,
        'rank': rank,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'explanationEvidenceRefs': explanationEvidenceRefs,
      };

  /// AI-facing JSON. Contains only candidateRef, rank, totalScore, grade,
  /// and rejection/evidence text. Does NOT contain gainDb, q, frequencyHz,
  /// biquad coefficients, DSP addresses, or hardware payload.
  Map<String, dynamic> toAiJson() => {
        'candidateRef': candidateRef,
        'rank': rank,
        'totalScore': totalScore,
        'grade': grade.name,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'explanationEvidenceRefs': explanationEvidenceRefs,
      };
}

/// The complete ranked result of one v2 scoring pass.
class ScoredCandidateSetV2 {
  final ScoredCandidateSetV2Status status;

  /// All scored candidates in rank order (rank 1 first).
  final List<ScoredCandidateV2> scoredCandidates;

  /// True when scoring ran under [MeasurementConfidenceInterpretation.analysisOnly]
  /// (single-sweep / insufficient evidence). Candidates are scored and ranked
  /// normally but the UI Expert approval gate must be satisfied before Apply.
  final bool requiresExpertApproval;

  final List<String> reasons;
  final String policyId;
  final int policyVersion;
  final List<String> evidenceRefs;

  const ScoredCandidateSetV2({
    required this.status,
    required this.scoredCandidates,
    this.requiresExpertApproval = false,
    required this.reasons,
    required this.policyId,
    required this.policyVersion,
    required this.evidenceRefs,
  });

  /// Non-rejected candidates in rank order.
  List<ScoredCandidateV2> get accepted => [
        for (final c in scoredCandidates)
          if (c.grade != CandidateScoreGrade.rejected) c,
      ];

  /// Rank-1 candidate, or null when none exist.
  ScoredCandidateV2? get topCandidate =>
      scoredCandidates.isNotEmpty ? scoredCandidates.first : null;

  /// Best non-rejected candidate (rank 1 among accepted), or null.
  ScoredCandidateV2? get bestCandidate {
    final a = accepted;
    return a.isNotEmpty ? a.first : null;
  }

  /// Up to 2 alternative accepted candidates after [bestCandidate], in rank order.
  List<ScoredCandidateV2> get alternatives {
    final a = accepted;
    if (a.length <= 1) return const [];
    return a.sublist(1, math.min(3, a.length));
  }

  /// Full JSON including DSP-adjacent values. For internal use only.
  Map<String, dynamic> toJson() => {
        'status': status.name,
        'scoredCandidates': [for (final c in scoredCandidates) c.toJson()],
        if (requiresExpertApproval) 'requiresExpertApproval': true,
        'reasons': reasons,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'evidenceRefs': evidenceRefs,
      };

  /// AI-facing JSON. candidateRef/rank/score/grade/reasons only.
  /// Does NOT contain gainDb, q, frequencyHz, or hardware/DSP values.
  Map<String, dynamic> toAiJson() => {
        'status': status.name,
        if (requiresExpertApproval) 'requiresExpertApproval': true,
        'scoredCandidates': [for (final c in scoredCandidates) c.toAiJson()],
        'reasons': reasons,
      };
}

// ── Internal pre-rank entry ───────────────────────────────────────────────────

class _EntryV2 {
  final PeqCandidate candidate;
  final double prominenceDb;
  final double totalScore;
  final CandidateScoreBreakdownV2 breakdown;
  final CandidateScoreGrade grade;
  final String? rejectionReason;
  final List<String> evidenceRefs;

  const _EntryV2({
    required this.candidate,
    required this.prominenceDb,
    required this.totalScore,
    required this.breakdown,
    required this.grade,
    this.rejectionReason,
    required this.evidenceRefs,
  });
}

// ── Scorer ────────────────────────────────────────────────────────────────────

abstract final class CandidateScorerV2 {
  /// Score and rank the candidates in [ctx.candidateSet].
  ///
  /// Pure and deterministic: identical inputs always produce identical output.
  /// No DSP value, biquad coefficient, hardware command, or optimizer call is
  /// produced. No LLM or random value is read.
  static ScoredCandidateSetV2 score(
    CandidateScoringContextV2 ctx,
    CandidateScoringPolicyV2 policy,
  ) {
    policy.validate();

    final candidateSet = ctx.candidateSet;
    final classResult = ctx.classificationResult;
    final evidenceRefs = candidateSet.evidenceRefs;

    // Propagate non-ok CandidateSet status without scoring.
    if (candidateSet.status != CandidateSetStatus.ok) {
      return ScoredCandidateSetV2(
        status: _propagateCandidateStatus(candidateSet.status),
        scoredCandidates: const [],
        reasons: [
          'CandidateSet status ${candidateSet.status.name} — no scoring performed.',
        ],
        policyId: policy.id,
        policyVersion: policy.version,
        evidenceRefs: evidenceRefs,
      );
    }

    // Item 10 / set-level gate: block only when evidence is structurally
    // invalid (remeasure). Under analysisOnly (single-sweep insufficientEvidence)
    // scoring runs but requiresExpertApproval is set — the UI Expert approval
    // gate blocks Apply until the user explicitly approves.
    final confidenceInterp = classResult.confidenceInterpretation;
    if (confidenceInterp == MeasurementConfidenceInterpretation.remeasure) {
      return ScoredCandidateSetV2(
        status: ScoredCandidateSetV2Status.insufficientEvidence,
        scoredCandidates: const [],
        reasons: [
          'confidenceInterpretation=${confidenceInterp.name} — '
              'remeasure required; scoring blocked.',
        ],
        policyId: policy.id,
        policyVersion: policy.version,
        evidenceRefs: evidenceRefs,
      );
    }
    final requiresExpertApproval =
        confidenceInterp == MeasurementConfidenceInterpretation.analysisOnly;

    // Build lookup maps (O(1) per candidate).
    final featureMap = <String, AcousticObservedFeature>{
      for (final f in classResult.observedFeatures) f.featureId: f,
    };
    // directiveMap is empty when correctionPlan is null (disposition check skipped).
    final directiveMap = <String, CorrectionDirective>{
      if (ctx.correctionPlan != null)
        for (final d in ctx.correctionPlan!.directives) d.featureId: d,
    };

    // Pre-compute set-level scores (shared across all candidates in this pass).
    final confidenceScore = _confidenceScore(confidenceInterp);
    final sharedWeightedRmsScore = _weightedRmsScoreFromContext(ctx, policy);
    final sharedMaxDeviationScore = _maxDeviationScoreFromContext(ctx, policy);
    final complexityScore =
        _complexityScore(candidateSet.candidates.length, policy);

    final entries = <_EntryV2>[];
    for (final candidate in candidateSet.candidates) {
      // Per-candidate simulation error overrides shared metrics for items 2 & 3.
      final perCandError =
          ctx.perCandidateSimulatedError?[candidate.candidateId];
      if (perCandError != null &&
          ctx.currentError != null &&
          perCandError.weightedRmsDb >= ctx.currentError!.weightedRmsDb) {
        entries.add(_hardReject(
          candidate,
          featureMap[candidate.featureId]?.prominenceDb ?? 0.0,
          'Simulation reject — after weighted RMS '
              '${perCandError.weightedRmsDb.toStringAsFixed(3)} dB does not improve '
              'before ${ctx.currentError!.weightedRmsDb.toStringAsFixed(3)} dB.',
          candidateSet.evidenceRefs,
        ));
        continue;
      }
      final weightedRmsScore = perCandError != null
          ? _weightedRmsScoreFromError(perCandError, policy)
          : sharedWeightedRmsScore;
      final maxDeviationScore = perCandError != null
          ? _maxDeviationScoreFromError(perCandError, policy)
          : sharedMaxDeviationScore;

      entries.add(_scoreOne(
        candidate,
        featureMap[candidate.featureId],
        directiveMap[candidate.featureId],
        ctx,
        policy,
        sharedConfidenceScore: confidenceScore,
        perCandidateWeightedRmsScore: weightedRmsScore,
        perCandidateMaxDeviationScore: maxDeviationScore,
        sharedComplexityScore: complexityScore,
      ));
    }

    // Rank: totalScore desc → prominenceDb desc → candidateId asc.
    entries.sort((a, b) {
      final sc = b.totalScore.compareTo(a.totalScore);
      if (sc != 0) return sc;
      final pc = b.prominenceDb.compareTo(a.prominenceDb);
      if (pc != 0) return pc;
      return a.candidate.candidateId.compareTo(b.candidate.candidateId);
    });

    final scoredCandidates = [
      for (var i = 0; i < entries.length; i++)
        ScoredCandidateV2(
          candidateRef: entries[i].candidate.candidateId,
          candidate: entries[i].candidate,
          totalScore: entries[i].totalScore,
          breakdown: entries[i].breakdown,
          grade: entries[i].grade,
          rank: i + 1,
          rejectionReason: entries[i].rejectionReason,
          explanationEvidenceRefs: entries[i].evidenceRefs,
        ),
    ];

    final allRejected = scoredCandidates.isNotEmpty &&
        scoredCandidates.every((c) => c.grade == CandidateScoreGrade.rejected);

    final acceptedCount = scoredCandidates
        .where((c) => c.grade != CandidateScoreGrade.rejected)
        .length;

    return ScoredCandidateSetV2(
      status: allRejected
          ? ScoredCandidateSetV2Status.allRejected
          : ScoredCandidateSetV2Status.ok,
      scoredCandidates: scoredCandidates,
      requiresExpertApproval: requiresExpertApproval,
      reasons: [
        '${scoredCandidates.length} candidate(s) scored; $acceptedCount accepted.'
            '${requiresExpertApproval ? ' Expert approval required (single-sweep).' : ''}',
      ],
      policyId: policy.id,
      policyVersion: policy.version,
      evidenceRefs: evidenceRefs,
    );
  }

  // ── Per-candidate scoring ─────────────────────────────────────────────────

  static _EntryV2 _scoreOne(
    PeqCandidate candidate,
    AcousticObservedFeature? feature,
    CorrectionDirective? directive,
    CandidateScoringContextV2 ctx,
    CandidateScoringPolicyV2 policy, {
    required double sharedConfidenceScore,
    required double perCandidateWeightedRmsScore,
    required double perCandidateMaxDeviationScore,
    required double sharedComplexityScore,
  }) {
    final refs = <String>[...ctx.candidateSet.evidenceRefs];
    final prominenceDb = feature?.prominenceDb ?? 0.0;

    // ── Item 4: boost check ─────────────────────────────────────────────────
    // gainDb > maxBoostDb → hard reject (any boost when maxBoostDb = 0).
    // 0 < gainDb ≤ maxBoostDb → compute normally, then apply boost penalty.
    if (candidate.gainDb < policy.minGainDb ||
        candidate.gainDb > policy.maxBoostDb) {
      return _hardReject(
        candidate,
        prominenceDb,
        'Item 4 — boost exceeds maxBoostDb (${policy.maxBoostDb.toStringAsFixed(1)} dB): '
        'gainDb ${candidate.gainDb.toStringAsFixed(2)} dB.',
        refs,
      );
    }

    // Boost penalty score (≤ 0). Zero when no boost.
    final double boostPenaltyScore;
    if (candidate.gainDb > 0 && policy.maxBoostDb > 0) {
      final fraction = candidate.gainDb / policy.maxBoostDb;
      boostPenaltyScore = -(fraction.clamp(0.0, 1.0) * 30.0);
    } else {
      boostPenaltyScore = 0.0;
    }

    // ── Item 9a: deepNull hard-reject ───────────────────────────────────────
    if (candidate.featureType == AcousticFeatureType.deepNull) {
      return _hardReject(
        candidate,
        prominenceDb,
        'Item 9 — deepNull candidates are unconditionally prohibited.',
        refs,
      );
    }

    // ── Item 9b: blocked/prohibited disposition hard-reject ─────────────────
    if (directive != null) {
      final d = directive.disposition;
      if (d == CorrectionDisposition.prohibitedBoost ||
          d == CorrectionDisposition.inspectOnly ||
          d == CorrectionDisposition.manualReview ||
          d == CorrectionDisposition.remeasure) {
        return _hardReject(
          candidate,
          prominenceDb,
          'Item 9 — disposition ${d.name} blocks automatic correction.',
          refs,
        );
      }
    }

    // ── Item 1: target improvement ──────────────────────────────────────────
    // Score = min(|gainDb|, |deviationDb|) / refDb clamped to [0,1] × 25.
    // For a boost candidate within the allowed range, gainDb.abs() is used —
    // boosting can also "correct" a dip feature; the penalty covers excess.
    final double targetImprovementScore;
    if (feature != null) {
      final effectiveCorrection =
          math.min(candidate.gainDb.abs(), feature.deviationDb.abs());
      targetImprovementScore =
          (effectiveCorrection / policy.targetImprovementRefDb)
                  .clamp(0.0, 1.0) *
              25.0;
    } else {
      targetImprovementScore = 0.0;
      refs.add('feature not found — targetImprovementScore = 0.');
    }

    // ── Item 5: excessive Q penalty ────────────────────────────────────────
    final qScore = _excessiveQScore(candidate.q, policy);

    // ── Item 7: headroom score ──────────────────────────────────────────────
    final headroomScore =
        _headroomScore(candidate.gainDb.abs(), ctx.availableHeadroomDb, policy);

    // ── Item 8: protection score ────────────────────────────────────────────
    final protectionScore = _protectionScore(ctx.protectionMarginDb, policy);

    final breakdown = CandidateScoreBreakdownV2(
      targetImprovementScore: targetImprovementScore.clamp(0.0, 25.0),
      weightedRmsScore: perCandidateWeightedRmsScore,
      maxDeviationScore: perCandidateMaxDeviationScore,
      boostPenaltyScore: boostPenaltyScore,
      excessiveQScore: qScore,
      complexityScore: sharedComplexityScore,
      headroomScore: headroomScore,
      protectionScore: protectionScore,
      confidenceScore: sharedConfidenceScore,
    );

    final totalScore = breakdown.total.clamp(0.0, 100.0);
    final grade = _grade(totalScore, policy);

    refs
      ..add('candidate ${candidate.candidateId}: '
          'freq=${candidate.frequencyHz.toStringAsFixed(0)} Hz, '
          'gain=${candidate.gainDb.toStringAsFixed(1)} dB, '
          'q=${candidate.q.toStringAsFixed(2)}.')
      ..add('totalScore=${totalScore.toStringAsFixed(1)} → ${grade.name}.');

    return _EntryV2(
      candidate: candidate,
      prominenceDb: prominenceDb,
      totalScore: totalScore,
      breakdown: breakdown,
      grade: grade,
      evidenceRefs: List.unmodifiable(refs),
    );
  }

  // ── Hard reject helper ────────────────────────────────────────────────────

  static _EntryV2 _hardReject(
    PeqCandidate candidate,
    double prominenceDb,
    String reason,
    List<String> refs,
  ) =>
      _EntryV2(
        candidate: candidate,
        prominenceDb: prominenceDb,
        totalScore: 0.0,
        breakdown: CandidateScoreBreakdownV2.zero,
        grade: CandidateScoreGrade.rejected,
        rejectionReason: reason,
        evidenceRefs: List.unmodifiable([...refs, reason]),
      );

  // ── Sub-score helpers ─────────────────────────────────────────────────────

  /// Item 2 — weighted RMS score ∈ [0, 20] from context (set-level fallback).
  static double _weightedRmsScoreFromContext(
      CandidateScoringContextV2 ctx, CandidateScoringPolicyV2 policy) {
    final rms = ctx.simulatedError?.weightedRmsDb ??
        ctx.currentError?.weightedRmsDb ??
        ctx.classificationResult.residualSummary?.rmsDb;
    if (rms == null) return 10.0;
    return _weightedRmsScoreFromValue(rms, policy);
  }

  /// Item 2 — weighted RMS score from a specific [ResponseErrorResult].
  static double _weightedRmsScoreFromError(
          ResponseErrorResult error, CandidateScoringPolicyV2 policy) =>
      _weightedRmsScoreFromValue(error.weightedRmsDb, policy);

  static double _weightedRmsScoreFromValue(
          double rms, CandidateScoringPolicyV2 policy) =>
      (1.0 - (rms / policy.weightedRmsWorstDb).clamp(0.0, 1.0)) * 20.0;

  /// Item 3 — max deviation score ∈ [0, 15] from context (set-level fallback).
  static double _maxDeviationScoreFromContext(
      CandidateScoringContextV2 ctx, CandidateScoringPolicyV2 policy) {
    final maxDev = ctx.simulatedError?.maxDeviationDb ??
        ctx.currentError?.maxDeviationDb ??
        ctx.classificationResult.residualSummary?.maxAbsDeviationDb;
    if (maxDev == null) return 7.5;
    return _maxDeviationScoreFromValue(maxDev, policy);
  }

  /// Item 3 — max deviation score from a specific [ResponseErrorResult].
  static double _maxDeviationScoreFromError(
          ResponseErrorResult error, CandidateScoringPolicyV2 policy) =>
      _maxDeviationScoreFromValue(error.maxDeviationDb, policy);

  static double _maxDeviationScoreFromValue(
          double maxDev, CandidateScoringPolicyV2 policy) =>
      (1.0 - (maxDev / policy.maxDeviationWorstDb).clamp(0.0, 1.0)) * 15.0;

  /// Item 5 — excessive Q score ∈ [0, 15] (15 = no penalty, 0 = excessive).
  static double _excessiveQScore(double q, CandidateScoringPolicyV2 policy) {
    if (q <= policy.excessiveQThreshold) return 15.0;
    final excess = (q - policy.excessiveQThreshold) /
        (policy.excessiveQCeilingQ - policy.excessiveQThreshold);
    return (1.0 - excess.clamp(0.0, 1.0)) * 15.0;
  }

  /// Item 6 — complexity score ∈ [0, 10] (10 = at or below ref, 0 = 2× ref).
  static double _complexityScore(
      int bandCount, CandidateScoringPolicyV2 policy) {
    if (bandCount <= policy.complexityRefBands) return 10.0;
    final excess =
        (bandCount - policy.complexityRefBands) / policy.complexityRefBands;
    return (1.0 - excess.clamp(0.0, 1.0)) * 10.0;
  }

  /// Item 7 — headroom score ∈ [0, 5].
  /// When [headroomDb] is null returns 2.5 (conservative neutral).
  static double _headroomScore(
      double cutAbs, double? headroomDb, CandidateScoringPolicyV2 policy) {
    if (headroomDb == null || headroomDb <= 0) return 2.5;
    final used = cutAbs / headroomDb;
    if (used <= policy.headroomPenaltyRatio) return 5.0;
    final range = 1.0 - policy.headroomPenaltyRatio;
    final excess = (used - policy.headroomPenaltyRatio) / range;
    return (1.0 - excess.clamp(0.0, 1.0)) * 5.0;
  }

  /// Item 8 — protection score ∈ [0, 5].
  /// When [marginDb] is null returns 2.5 (conservative neutral).
  static double _protectionScore(
      double? marginDb, CandidateScoringPolicyV2 policy) {
    if (marginDb == null) return 2.5;
    return (marginDb / policy.protectionMinMarginDb).clamp(0.0, 1.0) * 5.0;
  }

  /// Item 10 — confidence score ∈ [0, 5].
  static double _confidenceScore(MeasurementConfidenceInterpretation interp) =>
      switch (interp) {
        MeasurementConfidenceInterpretation.correctableAllowed => 5.0,
        MeasurementConfidenceInterpretation.conservative => 2.5,
        // analysisOnly: scores run provisionally; confidence item = 0.
        // remeasure: blocked at set level, never reaches here.
        _ => 0.0,
      };

  // ── Grade ─────────────────────────────────────────────────────────────────

  static CandidateScoreGrade _grade(
      double score, CandidateScoringPolicyV2 policy) {
    if (score >= policy.excellentThreshold)
      return CandidateScoreGrade.excellent;
    if (score >= policy.goodThreshold) return CandidateScoreGrade.good;
    if (score >= policy.rejectionThreshold) return CandidateScoreGrade.marginal;
    return CandidateScoreGrade.rejected;
  }

  // ── Status propagation ────────────────────────────────────────────────────

  static ScoredCandidateSetV2Status _propagateCandidateStatus(
          CandidateSetStatus s) =>
      switch (s) {
        CandidateSetStatus.insufficientEvidence =>
          ScoredCandidateSetV2Status.insufficientEvidence,
        CandidateSetStatus.noCorrectableDirectives =>
          ScoredCandidateSetV2Status.noCorrectableDirectives,
        CandidateSetStatus.invalidPlan =>
          ScoredCandidateSetV2Status.invalidPlan,
        CandidateSetStatus.ok => ScoredCandidateSetV2Status.ok,
      };
}
