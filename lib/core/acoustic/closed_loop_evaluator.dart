import '../pro_response_error.dart';
import 'measurement_confidence.dart';

/// Closed Loop Evaluator v1 — pure before/after tuning quality comparison.
///
/// Compares two [LoopMeasurementSnapshot] values (before and after apply) and
/// returns a deterministic [ImprovementVerdict] based on score delta and
/// after-measurement confidence.
///
/// No DSP writes, hardware access, measurement triggers, or rollback
/// execution are performed here.

// ── Policy ────────────────────────────────────────────────────────────────────

class ClosedLoopPolicyException implements Exception {
  final String message;
  ClosedLoopPolicyException(this.message);
  @override
  String toString() => 'ClosedLoopPolicyException: $message';
}

/// Thresholds that govern verdict classification.
class ClosedLoopPolicy {
  final String id;
  final int version;

  /// Score delta >= this → [ImprovementVerdict.improved]. Must be > 0.
  final double improvementThresholdScore;

  /// Score delta <= this → [ImprovementVerdict.regressed]. Must be < 0.
  final double regressionThresholdScore;

  const ClosedLoopPolicy({
    required this.id,
    required this.version,
    required this.improvementThresholdScore,
    required this.regressionThresholdScore,
  });

  void validate() {
    if (id.isEmpty) {
      throw ClosedLoopPolicyException('id must not be empty.');
    }
    if (version < 1) {
      throw ClosedLoopPolicyException('version must be >= 1.');
    }
    if (!improvementThresholdScore.isFinite || improvementThresholdScore <= 0) {
      throw ClosedLoopPolicyException(
          'improvementThresholdScore must be finite and > 0.');
    }
    if (!regressionThresholdScore.isFinite || regressionThresholdScore >= 0) {
      throw ClosedLoopPolicyException(
          'regressionThresholdScore must be finite and < 0.');
    }
  }

  factory ClosedLoopPolicy.proProvisional() => const ClosedLoopPolicy(
        id: 'pro_provisional',
        version: 1,
        improvementThresholdScore: 2.0,
        regressionThresholdScore: -2.0,
      );
}

// ── Verdict ───────────────────────────────────────────────────────────────────

enum ImprovementVerdict {
  /// After score improved by >= [ClosedLoopPolicy.improvementThresholdScore].
  improved,

  /// Score delta within the neutral band.
  neutral,

  /// After score dropped by >= |[ClosedLoopPolicy.regressionThresholdScore]|.
  regressed,

  /// After-measurement confidence insufficient — no verdict possible.
  inconclusive,
}

// ── Snapshot ──────────────────────────────────────────────────────────────────

/// A single point-in-time acoustic quality measurement used for comparison.
class LoopMeasurementSnapshot {
  /// Opaque reference to the underlying measurement data.
  final String measurementRef;

  /// Frequency-domain error metrics from [ProResponseError.analyze].
  final ResponseErrorResult scoreResult;

  /// Confidence of this measurement's data.
  final ConfidenceStatus confidenceStatus;

  const LoopMeasurementSnapshot({
    required this.measurementRef,
    required this.scoreResult,
    required this.confidenceStatus,
  });

  Map<String, dynamic> toJson() => {
        'measurementRef': measurementRef,
        'score': scoreResult.score,
        'rmsDb': scoreResult.rmsDb,
        'weightedRmsDb': scoreResult.weightedRmsDb,
        'confidenceStatus': confidenceStatus.name,
      };
}

// ── Result ────────────────────────────────────────────────────────────────────

class ClosedLoopResult {
  final ImprovementVerdict verdict;
  final LoopMeasurementSnapshot before;
  final LoopMeasurementSnapshot after;

  /// `after.score − before.score`. Zero when verdict is [ImprovementVerdict.inconclusive].
  final double scoreDelta;

  final String policyId;
  final int policyVersion;
  final List<String> evidenceRefs;
  final List<String> reasons;

  const ClosedLoopResult({
    required this.verdict,
    required this.before,
    required this.after,
    required this.scoreDelta,
    required this.policyId,
    required this.policyVersion,
    required this.evidenceRefs,
    required this.reasons,
  });

  Map<String, dynamic> toJson() => {
        'verdict': verdict.name,
        'scoreDelta': scoreDelta,
        'before': before.toJson(),
        'after': after.toJson(),
        'policyId': policyId,
        'policyVersion': policyVersion,
        'evidenceRefs': evidenceRefs,
        'reasons': reasons,
      };
}

// ── Evaluator ─────────────────────────────────────────────────────────────────

abstract final class AcousticClosedLoopEvaluator {
  /// Compare [before] and [after] snapshots under [policy].
  ///
  /// Pure and deterministic — same inputs always produce the same result.
  static ClosedLoopResult evaluate(
    LoopMeasurementSnapshot before,
    LoopMeasurementSnapshot after,
    ClosedLoopPolicy policy, {
    List<String> evidenceRefs = const [],
  }) {
    policy.validate();

    // Confidence gate: after-measurement must be trustworthy.
    if (after.confidenceStatus != ConfidenceStatus.valid) {
      return ClosedLoopResult(
        verdict: ImprovementVerdict.inconclusive,
        before: before,
        after: after,
        scoreDelta: 0.0,
        policyId: policy.id,
        policyVersion: policy.version,
        evidenceRefs: evidenceRefs,
        reasons: [
          'after-measurement confidence ${after.confidenceStatus.name} — '
              'verdict inconclusive.',
        ],
      );
    }

    final scoreDelta = after.scoreResult.score - before.scoreResult.score;

    final ImprovementVerdict verdict;
    final String verdictReason;

    if (scoreDelta >= policy.improvementThresholdScore) {
      verdict = ImprovementVerdict.improved;
      verdictReason = 'score delta ${scoreDelta.toStringAsFixed(2)} >= '
          'improvement threshold '
          '${policy.improvementThresholdScore.toStringAsFixed(2)}.';
    } else if (scoreDelta <= policy.regressionThresholdScore) {
      verdict = ImprovementVerdict.regressed;
      verdictReason = 'score delta ${scoreDelta.toStringAsFixed(2)} <= '
          'regression threshold '
          '${policy.regressionThresholdScore.toStringAsFixed(2)}.';
    } else {
      verdict = ImprovementVerdict.neutral;
      verdictReason =
          'score delta ${scoreDelta.toStringAsFixed(2)} within neutral range.';
    }

    return ClosedLoopResult(
      verdict: verdict,
      before: before,
      after: after,
      scoreDelta: scoreDelta,
      policyId: policy.id,
      policyVersion: policy.version,
      evidenceRefs: evidenceRefs,
      reasons: [verdictReason],
    );
  }
}
