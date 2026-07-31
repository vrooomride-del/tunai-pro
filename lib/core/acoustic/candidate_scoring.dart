import 'acoustic_problem_classifier.dart';
import 'candidate_set.dart';

/// Candidate Scoring v1 — ranks [PeqCandidate] proposals produced by
/// [CandidateGenerator] using observation-only metrics.
///
/// This layer is deliberately measurement-only: it reads
/// [AcousticObservedFeature] fields already available from the classifier
/// (prominenceDb, deviationDb, quality) and computes a deterministic composite
/// score. No FRD simulation, no DSP application, no optimizer calls, and no
/// hardware values are produced here.
///
/// Scoring formula:
///   prominenceScore     (0–40)  = clip(prominenceDb / targetProminenceDb) × 40
///   consistencyScore    (0–30)  = clip(|gainDb| / |deviationDb|) × 30
///   qualityFactor       (0–1]   = 1.0 for confident; tentativeFactor for tentative
///   rawComposite        (0–70)  = prominenceScore + consistencyScore
///   compositeScore      (0–100) = rawComposite × qualityFactor × 100/70, clamped
///
/// Ranking is by compositeScore descending; ties broken by prominenceDb
/// descending, then featureId ascending (deterministic).

// ── Policy ───────────────────────────────────────────────────────────────────

class ScoringPolicyException implements Exception {
  final String message;
  ScoringPolicyException(this.message);
  @override
  String toString() => 'ScoringPolicyException: $message';
}

/// Numerical thresholds that govern score computation and grade assignment.
/// Carries no DSP address, hardware value, or biquad coefficient.
class ScoringPolicy {
  final String id;
  final int version;

  /// The prominenceDb that maps to a full prominenceScore of 40.
  /// Features at or above this prominence receive the maximum sub-score.
  final double targetProminenceDb;

  /// Score multiplier applied when a feature's quality is
  /// [AcousticFeatureQuality.tentative]. Must be in (0, 1].
  final double tentativeFactor;

  /// compositeScore below this threshold → [CandidateScoreGrade.rejected].
  final double rejectionThreshold;

  /// compositeScore at or above this → [CandidateScoreGrade.good].
  final double goodThreshold;

  /// compositeScore at or above this → [CandidateScoreGrade.excellent].
  final double excellentThreshold;

  const ScoringPolicy({
    required this.id,
    required this.version,
    required this.targetProminenceDb,
    required this.tentativeFactor,
    required this.rejectionThreshold,
    required this.goodThreshold,
    required this.excellentThreshold,
  });

  void validate() {
    if (id.isEmpty) {
      throw ScoringPolicyException('id must not be empty.');
    }
    if (version < 1) {
      throw ScoringPolicyException('version must be >= 1.');
    }
    if (!targetProminenceDb.isFinite || targetProminenceDb <= 0) {
      throw ScoringPolicyException('targetProminenceDb must be finite and > 0.');
    }
    if (!tentativeFactor.isFinite || tentativeFactor <= 0 || tentativeFactor > 1) {
      throw ScoringPolicyException('tentativeFactor must be in (0, 1].');
    }
    if (!rejectionThreshold.isFinite ||
        rejectionThreshold < 0 ||
        rejectionThreshold >= 100) {
      throw ScoringPolicyException(
          'rejectionThreshold must be finite and in [0, 100).');
    }
    if (!goodThreshold.isFinite || goodThreshold <= rejectionThreshold) {
      throw ScoringPolicyException(
          'goodThreshold must be finite and > rejectionThreshold.');
    }
    if (!excellentThreshold.isFinite || excellentThreshold <= goodThreshold) {
      throw ScoringPolicyException(
          'excellentThreshold must be finite and > goodThreshold.');
    }
    if (excellentThreshold > 100) {
      throw ScoringPolicyException('excellentThreshold must be <= 100.');
    }
  }

  /// PRO provisional scoring policy.
  factory ScoringPolicy.proProvisional() => const ScoringPolicy(
        id: 'pro_provisional',
        version: 1,
        targetProminenceDb: 6.0,
        tentativeFactor: 0.7,
        rejectionThreshold: 20.0,
        goodThreshold: 45.0,
        excellentThreshold: 70.0,
      );
}

// ── Grade ─────────────────────────────────────────────────────────────────────

enum CandidateScoreGrade {
  /// compositeScore ≥ excellentThreshold.
  excellent,

  /// goodThreshold ≤ compositeScore < excellentThreshold.
  good,

  /// rejectionThreshold ≤ compositeScore < goodThreshold.
  marginal,

  /// compositeScore < rejectionThreshold. Candidate is not recommended.
  rejected,
}

// ── Status ────────────────────────────────────────────────────────────────────

enum ScoredCandidateSetStatus {
  /// Scoring completed; at least one non-rejected candidate exists.
  ok,

  /// Scoring completed but every candidate was rejected.
  allRejected,

  /// Propagated from [CandidateSetStatus.noCorrectableDirectives].
  noCorrectableDirectives,

  /// Propagated from [CandidateSetStatus.insufficientEvidence].
  insufficientEvidence,

  /// Propagated from any other non-ok [CandidateSetStatus].
  invalidPlan,
}

// ── Output models ─────────────────────────────────────────────────────────────

/// A [PeqCandidate] annotated with observation-derived scores and a rank.
class ScoredCandidate {
  final PeqCandidate candidate;

  /// Raw prominenceDb from the observed feature, used for tie-breaking.
  final double prominenceDb;

  /// Prominence sub-score ∈ [0, 40].
  final double prominenceScore;

  /// Magnitude-consistency sub-score ∈ [0, 30].
  /// Measures how closely the proposed gain tracks the measured deviation.
  final double magnitudeConsistencyScore;

  /// Quality multiplier: 1.0 (confident) or policy.tentativeFactor (tentative).
  final double qualityFactor;

  /// Overall score ∈ [0, 100] (normalized, includes qualityFactor).
  final double compositeScore;

  /// 1-based rank within the [ScoredCandidateSet] (lower = apply first).
  final int rank;

  final CandidateScoreGrade grade;
  final List<String> reasons;

  const ScoredCandidate({
    required this.candidate,
    required this.prominenceDb,
    required this.prominenceScore,
    required this.magnitudeConsistencyScore,
    required this.qualityFactor,
    required this.compositeScore,
    required this.rank,
    required this.grade,
    required this.reasons,
  });

  Map<String, dynamic> toJson() => {
        'candidateId': candidate.candidateId,
        'featureId': candidate.featureId,
        'featureType': candidate.featureType.name,
        'frequencyHz': candidate.frequencyHz,
        'gainDb': candidate.gainDb,
        'q': candidate.q,
        'intent': candidate.intent.name,
        'prominenceDb': prominenceDb,
        'prominenceScore': prominenceScore,
        'magnitudeConsistencyScore': magnitudeConsistencyScore,
        'qualityFactor': qualityFactor,
        'compositeScore': compositeScore,
        'rank': rank,
        'grade': grade.name,
        'reasons': reasons,
      };
}

/// The scored and ranked result of one scoring pass over a [CandidateSet].
class ScoredCandidateSet {
  final ScoredCandidateSetStatus status;

  /// All scored candidates in rank order (rank 1 first).
  final List<ScoredCandidate> scoredCandidates;

  /// Propagated from [ScoredCandidateSetV2.requiresExpertApproval].
  /// True when scoring ran under single-sweep (analysisOnly) evidence.
  final bool requiresExpertApproval;

  final List<String> reasons;
  final String policyId;
  final int policyVersion;
  final List<String> evidenceRefs;

  const ScoredCandidateSet({
    required this.status,
    required this.scoredCandidates,
    this.requiresExpertApproval = false,
    required this.reasons,
    required this.policyId,
    required this.policyVersion,
    required this.evidenceRefs,
  });

  /// Non-rejected candidates in rank order.
  List<ScoredCandidate> get accepted => [
        for (final c in scoredCandidates)
          if (c.grade != CandidateScoreGrade.rejected) c,
      ];

  /// The highest-ranked candidate, or null when none exist.
  ScoredCandidate? get topCandidate =>
      scoredCandidates.isNotEmpty ? scoredCandidates.first : null;

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'scoredCandidates': [for (final c in scoredCandidates) c.toJson()],
        if (requiresExpertApproval) 'requiresExpertApproval': true,
        'reasons': reasons,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'evidenceRefs': evidenceRefs,
      };
}

// ── Internal pre-rank holder ──────────────────────────────────────────────────

class _Entry {
  final PeqCandidate candidate;
  final double prominenceDb;
  final double prominenceScore;
  final double magnitudeConsistencyScore;
  final double qualityFactor;
  final double compositeScore;
  final CandidateScoreGrade grade;
  final List<String> reasons;

  const _Entry({
    required this.candidate,
    required this.prominenceDb,
    required this.prominenceScore,
    required this.magnitudeConsistencyScore,
    required this.qualityFactor,
    required this.compositeScore,
    required this.grade,
    required this.reasons,
  });
}

// ── Scorer ────────────────────────────────────────────────────────────────────

abstract final class CandidateScorer {
  /// Score and rank the candidates in [candidateSet].
  ///
  /// [result] provides the observation data ([AcousticObservedFeature])
  /// referenced by each candidate's [PeqCandidate.featureId].
  /// Pure and deterministic: same inputs always produce the same output.
  static ScoredCandidateSet score(
    CandidateSet candidateSet,
    AcousticClassificationResult result,
    ScoringPolicy policy,
  ) {
    policy.validate();

    // Propagate non-ok candidate set status without scoring.
    if (candidateSet.status != CandidateSetStatus.ok) {
      return ScoredCandidateSet(
        status: _propagateStatus(candidateSet.status),
        scoredCandidates: const [],
        reasons: [
          'candidate set status ${candidateSet.status.name} — no scoring performed.',
        ],
        policyId: policy.id,
        policyVersion: policy.version,
        evidenceRefs: candidateSet.evidenceRefs,
      );
    }

    final featureMap = <String, AcousticObservedFeature>{
      for (final f in result.observedFeatures) f.featureId: f,
    };

    final entries = <_Entry>[];
    for (final candidate in candidateSet.candidates) {
      entries.add(_scoreOne(candidate, featureMap[candidate.featureId], policy));
    }

    // Sort: compositeScore desc → prominenceDb desc → featureId asc (deterministic).
    entries.sort((a, b) {
      final sc = b.compositeScore.compareTo(a.compositeScore);
      if (sc != 0) return sc;
      final pc = b.prominenceDb.compareTo(a.prominenceDb);
      if (pc != 0) return pc;
      return a.candidate.featureId.compareTo(b.candidate.featureId);
    });

    final scoredCandidates = [
      for (var i = 0; i < entries.length; i++)
        ScoredCandidate(
          candidate: entries[i].candidate,
          prominenceDb: entries[i].prominenceDb,
          prominenceScore: entries[i].prominenceScore,
          magnitudeConsistencyScore: entries[i].magnitudeConsistencyScore,
          qualityFactor: entries[i].qualityFactor,
          compositeScore: entries[i].compositeScore,
          rank: i + 1,
          grade: entries[i].grade,
          reasons: entries[i].reasons,
        ),
    ];

    final allRejected = scoredCandidates.isNotEmpty &&
        scoredCandidates.every((c) => c.grade == CandidateScoreGrade.rejected);

    return ScoredCandidateSet(
      status: allRejected
          ? ScoredCandidateSetStatus.allRejected
          : ScoredCandidateSetStatus.ok,
      scoredCandidates: scoredCandidates,
      reasons: [
        '${scoredCandidates.length} candidate(s) scored; '
            '${scoredCandidates.where((c) => c.grade != CandidateScoreGrade.rejected).length} accepted.',
      ],
      policyId: policy.id,
      policyVersion: policy.version,
      evidenceRefs: candidateSet.evidenceRefs,
    );
  }

  static _Entry _scoreOne(
    PeqCandidate candidate,
    AcousticObservedFeature? feature,
    ScoringPolicy policy,
  ) {
    if (feature == null) {
      return _Entry(
        candidate: candidate,
        prominenceDb: 0.0,
        prominenceScore: 0.0,
        magnitudeConsistencyScore: 0.0,
        qualityFactor: 1.0,
        compositeScore: 0.0,
        grade: CandidateScoreGrade.rejected,
        reasons: [
          'feature "${candidate.featureId}" not found in classification result — scored 0.',
        ],
      );
    }

    // prominenceScore ∈ [0, 40]
    final prominenceScore =
        (feature.prominenceDb / policy.targetProminenceDb).clamp(0.0, 1.0) *
            40.0;

    // magnitudeConsistencyScore ∈ [0, 30]
    // Ratio of proposed cut to measured deviation. 1.0 = perfect calibration.
    final deviationAbs = feature.deviationDb.abs();
    final consistencyRatio = deviationAbs > 0
        ? (candidate.gainDb.abs() / deviationAbs).clamp(0.0, 1.0)
        : 0.0;
    final magnitudeConsistencyScore = consistencyRatio * 30.0;

    // qualityFactor: confident = 1.0, tentative = policy.tentativeFactor
    final qualityFactor = feature.quality == AcousticFeatureQuality.confident
        ? 1.0
        : policy.tentativeFactor;

    // Normalize raw (0–70) to (0–100) then apply quality.
    final rawComposite = prominenceScore + magnitudeConsistencyScore;
    final compositeScore =
        (rawComposite * qualityFactor * 100.0 / 70.0).clamp(0.0, 100.0);

    final grade = _grade(compositeScore, policy);

    final reasons = <String>[
      'prominence ${feature.prominenceDb.toStringAsFixed(1)} dB '
          '→ prominenceScore ${prominenceScore.toStringAsFixed(1)}.',
      'consistency ratio ${consistencyRatio.toStringAsFixed(2)} '
          '→ consistencyScore ${magnitudeConsistencyScore.toStringAsFixed(1)}.',
      if (feature.quality != AcousticFeatureQuality.confident)
        'tentative quality — factor ${policy.tentativeFactor.toStringAsFixed(2)} applied.',
      'compositeScore ${compositeScore.toStringAsFixed(1)} → ${grade.name}.',
    ];

    return _Entry(
      candidate: candidate,
      prominenceDb: feature.prominenceDb,
      prominenceScore: prominenceScore,
      magnitudeConsistencyScore: magnitudeConsistencyScore,
      qualityFactor: qualityFactor,
      compositeScore: compositeScore,
      grade: grade,
      reasons: reasons,
    );
  }

  static CandidateScoreGrade _grade(double score, ScoringPolicy policy) {
    if (score >= policy.excellentThreshold) return CandidateScoreGrade.excellent;
    if (score >= policy.goodThreshold) return CandidateScoreGrade.good;
    if (score >= policy.rejectionThreshold) return CandidateScoreGrade.marginal;
    return CandidateScoreGrade.rejected;
  }

  static ScoredCandidateSetStatus _propagateStatus(CandidateSetStatus s) =>
      switch (s) {
        CandidateSetStatus.insufficientEvidence =>
          ScoredCandidateSetStatus.insufficientEvidence,
        CandidateSetStatus.invalidPlan => ScoredCandidateSetStatus.invalidPlan,
        CandidateSetStatus.noCorrectableDirectives =>
          ScoredCandidateSetStatus.noCorrectableDirectives,
        CandidateSetStatus.ok => ScoredCandidateSetStatus.ok,
      };
}
