// TUNAI PRO — Correction Cycle model.
//
// One correction cycle = one pass of [Guided AI apply → Deploy → After FRD →
// Compare]. Serializable. Lives inside ProProject.correctionCycles.
//
// No DSP address, no hardware command, no BLE/USB/ICP5 reference.

import 'pro_tuning_data.dart';

// ── Decision ──────────────────────────────────────────────────────────────────

/// Deterministic decision returned by one correction cycle.
///
/// AI may explain the result but must not decide the numeric outcome.
enum CorrectionCycleDecision {
  /// After response is measurably better and magnitude/residual improvement
  /// is within a single-cycle achievable range — mark complete.
  improvedAndComplete,

  /// After response improved but the residual is large enough to warrant a
  /// follow-up cycle. After becomes the next Before.
  improvedNeedsAnotherCycle,

  /// Score delta is within the noise band — no meaningful change detected.
  noMeaningfulImprovement,

  /// After response is measurably worse. No automatic next Apply.
  worsened,

  /// Common frequency coverage or confidence is insufficient to produce a
  /// verdict.
  insufficientEvidence,

  /// projectId or channelId mismatch between before and after inputs.
  wrongProjectOrChannel;

  String toJson() => name;

  static CorrectionCycleDecision fromJson(String s) =>
      CorrectionCycleDecision.values.firstWhere(
        (e) => e.name == s,
        orElse: () => CorrectionCycleDecision.insufficientEvidence,
      );
}

// ── Metrics ───────────────────────────────────────────────────────────────────

/// Deterministic aligned comparison metrics for one correction cycle.
///
/// Computed on the common valid frequency range of before and after FRD data.
/// No extrapolation.
class CorrectionCycleMetrics {
  /// Common valid frequency range (Hz).
  final double commonFreqMinHz;
  final double commonFreqMaxHz;
  final int commonPointCount;

  /// Mean absolute residual relative to flat 0 dB target, before correction.
  final double meanAbsResidualBefore;

  /// Mean absolute residual after correction.
  final double meanAbsResidualAfter;

  /// `meanAbsResidualBefore − meanAbsResidualAfter`.
  /// Positive = improvement, negative = degradation.
  final double improvementDelta;

  /// Peak absolute deviation (dB) before correction, and its frequency.
  final double peakErrorBefore;
  final double peakErrorBeforeHz;

  /// Peak absolute deviation (dB) after correction, and its frequency.
  final double peakErrorAfter;
  final double peakErrorAfterHz;

  /// Number of common-grid points where |after error| > |before error|.
  final int worsenedBandCount;

  /// Ratio of points that improved or stayed the same (0..1).
  final double improvementCoverage;

  const CorrectionCycleMetrics({
    required this.commonFreqMinHz,
    required this.commonFreqMaxHz,
    required this.commonPointCount,
    required this.meanAbsResidualBefore,
    required this.meanAbsResidualAfter,
    required this.improvementDelta,
    required this.peakErrorBefore,
    required this.peakErrorBeforeHz,
    required this.peakErrorAfter,
    required this.peakErrorAfterHz,
    required this.worsenedBandCount,
    required this.improvementCoverage,
  });

  Map<String, dynamic> toJson() => {
        'commonFreqMinHz': commonFreqMinHz,
        'commonFreqMaxHz': commonFreqMaxHz,
        'commonPointCount': commonPointCount,
        'meanAbsResidualBefore': meanAbsResidualBefore,
        'meanAbsResidualAfter': meanAbsResidualAfter,
        'improvementDelta': improvementDelta,
        'peakErrorBefore': peakErrorBefore,
        'peakErrorBeforeHz': peakErrorBeforeHz,
        'peakErrorAfter': peakErrorAfter,
        'peakErrorAfterHz': peakErrorAfterHz,
        'worsenedBandCount': worsenedBandCount,
        'improvementCoverage': improvementCoverage,
      };

  factory CorrectionCycleMetrics.fromJson(Map<String, dynamic> j) =>
      CorrectionCycleMetrics(
        commonFreqMinHz: (j['commonFreqMinHz'] as num? ?? 0.0).toDouble(),
        commonFreqMaxHz: (j['commonFreqMaxHz'] as num? ?? 0.0).toDouble(),
        commonPointCount: j['commonPointCount'] as int? ?? 0,
        meanAbsResidualBefore:
            (j['meanAbsResidualBefore'] as num? ?? 0.0).toDouble(),
        meanAbsResidualAfter:
            (j['meanAbsResidualAfter'] as num? ?? 0.0).toDouble(),
        improvementDelta: (j['improvementDelta'] as num? ?? 0.0).toDouble(),
        peakErrorBefore: (j['peakErrorBefore'] as num? ?? 0.0).toDouble(),
        peakErrorBeforeHz: (j['peakErrorBeforeHz'] as num? ?? 0.0).toDouble(),
        peakErrorAfter: (j['peakErrorAfter'] as num? ?? 0.0).toDouble(),
        peakErrorAfterHz: (j['peakErrorAfterHz'] as num? ?? 0.0).toDouble(),
        worsenedBandCount: j['worsenedBandCount'] as int? ?? 0,
        improvementCoverage:
            (j['improvementCoverage'] as num? ?? 0.0).toDouble(),
      );
}

// ── Cycle ─────────────────────────────────────────────────────────────────────

/// One complete Guided AI correction cycle.
///
/// Tracks the before measurement reference, the applied PEQ snapshot, the
/// optional deploy acknowledgement reference, and the after comparison result.
///
/// Null fields indicate a pending state (apply done but after FRD not yet
/// imported; or cycle started but deploy not acknowledged). No fake data is
/// ever filled in.
class CorrectionCycle {
  final String projectId;
  final String channelId;
  final int cycleNumber;

  /// Opaque reference to the before-measurement FRD data.
  final String beforeMeasurementRef;

  /// PEQ state at the time of apply — snapshot for audit/rollback.
  final PeqChannelState peqSnapshot;

  /// Opaque deploy-acknowledgement reference (e.g. deploy package id).
  /// Null = no ACK recorded yet. The evaluator accepts null if policy allows.
  final String? deployAckRef;

  /// Opaque reference to the after-measurement FRD data.
  /// Null = not yet imported.
  final String? afterMeasurementRef;

  /// Filename of the after measurement FRD for display/audit.
  final String? afterMeasurementFileName;

  /// Comparison metrics. Non-null only when both before+after are available.
  final CorrectionCycleMetrics? metrics;

  /// Final verdict. Non-null only when metrics are available.
  final CorrectionCycleDecision? decision;

  /// When the cycle was closed (decision set).
  final DateTime? completedAt;

  final DateTime createdAt;

  final List<String> reasons;

  /// Four-channel evidence and rollback baseline for full-system cycles.
  final Map<String, String> fullSystemBeforeRefs;
  final Map<String, String> fullSystemAfterRefs;
  final TuningProjectState? rollbackTuningState;
  final bool? safetyPassed;
  final bool? phaseAware;
  final int? nextCycleNumber;
  final bool requiresUserApproval;
  final bool alignmentReevaluationAllowed;

  const CorrectionCycle({
    required this.projectId,
    required this.channelId,
    required this.cycleNumber,
    required this.beforeMeasurementRef,
    required this.peqSnapshot,
    this.deployAckRef,
    this.afterMeasurementRef,
    this.afterMeasurementFileName,
    this.metrics,
    this.decision,
    this.completedAt,
    required this.createdAt,
    this.reasons = const [],
    this.fullSystemBeforeRefs = const {},
    this.fullSystemAfterRefs = const {},
    this.rollbackTuningState,
    this.safetyPassed,
    this.phaseAware,
    this.nextCycleNumber,
    this.requiresUserApproval = false,
    this.alignmentReevaluationAllowed = false,
  });

  bool get isComplete => decision != null;
  bool get isPending => decision == null;
  bool get hasAfterMeasurement => afterMeasurementRef != null;

  CorrectionCycle withAfterResult({
    required String afterMeasurementRef,
    required String afterMeasurementFileName,
    required CorrectionCycleMetrics metrics,
    required CorrectionCycleDecision decision,
    required List<String> reasons,
  }) =>
      CorrectionCycle(
        projectId: projectId,
        channelId: channelId,
        cycleNumber: cycleNumber,
        beforeMeasurementRef: beforeMeasurementRef,
        peqSnapshot: peqSnapshot,
        deployAckRef: deployAckRef,
        afterMeasurementRef: afterMeasurementRef,
        afterMeasurementFileName: afterMeasurementFileName,
        metrics: metrics,
        decision: decision,
        completedAt: DateTime.now(),
        createdAt: createdAt,
        reasons: reasons,
        fullSystemBeforeRefs: fullSystemBeforeRefs,
        fullSystemAfterRefs: fullSystemAfterRefs,
        rollbackTuningState: rollbackTuningState,
        safetyPassed: safetyPassed,
        phaseAware: phaseAware,
        nextCycleNumber: nextCycleNumber,
        requiresUserApproval: requiresUserApproval,
        alignmentReevaluationAllowed: alignmentReevaluationAllowed,
      );

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'channelId': channelId,
        'cycleNumber': cycleNumber,
        'beforeMeasurementRef': beforeMeasurementRef,
        'peqSnapshot': peqSnapshot.toJson(),
        if (deployAckRef != null) 'deployAckRef': deployAckRef,
        if (afterMeasurementRef != null)
          'afterMeasurementRef': afterMeasurementRef,
        if (afterMeasurementFileName != null)
          'afterMeasurementFileName': afterMeasurementFileName,
        if (metrics != null) 'metrics': metrics!.toJson(),
        if (decision != null) 'decision': decision!.toJson(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'reasons': reasons,
        if (fullSystemBeforeRefs.isNotEmpty)
          'fullSystemBeforeRefs': fullSystemBeforeRefs,
        if (fullSystemAfterRefs.isNotEmpty)
          'fullSystemAfterRefs': fullSystemAfterRefs,
        if (rollbackTuningState != null)
          'rollbackTuningState': rollbackTuningState!.toJson(),
        if (safetyPassed != null) 'safetyPassed': safetyPassed,
        if (phaseAware != null) 'phaseAware': phaseAware,
        if (nextCycleNumber != null) 'nextCycleNumber': nextCycleNumber,
        'requiresUserApproval': requiresUserApproval,
        'alignmentReevaluationAllowed': alignmentReevaluationAllowed,
      };

  factory CorrectionCycle.fromJson(Map<String, dynamic> j) {
    final metricsJ = j['metrics'];
    final decisionS = j['decision'] as String?;
    return CorrectionCycle(
      projectId: j['projectId'] as String? ?? '',
      channelId: j['channelId'] as String? ?? '',
      cycleNumber: j['cycleNumber'] as int? ?? 1,
      beforeMeasurementRef: j['beforeMeasurementRef'] as String? ?? '',
      peqSnapshot: PeqChannelState.fromJson(
          Map<String, dynamic>.from(j['peqSnapshot'] as Map? ?? {})),
      deployAckRef: j['deployAckRef'] as String?,
      afterMeasurementRef: j['afterMeasurementRef'] as String?,
      afterMeasurementFileName: j['afterMeasurementFileName'] as String?,
      metrics: metricsJ != null
          ? CorrectionCycleMetrics.fromJson(
              Map<String, dynamic>.from(metricsJ as Map))
          : null,
      decision: decisionS != null
          ? CorrectionCycleDecision.fromJson(decisionS)
          : null,
      completedAt: DateTime.tryParse(j['completedAt'] as String? ?? ''),
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reasons: List<String>.from(j['reasons'] as List? ?? []),
      fullSystemBeforeRefs: Map<String, String>.from(
          j['fullSystemBeforeRefs'] as Map? ?? const {}),
      fullSystemAfterRefs: Map<String, String>.from(
          j['fullSystemAfterRefs'] as Map? ?? const {}),
      rollbackTuningState: j['rollbackTuningState'] != null
          ? TuningProjectState.fromJson(
              Map<String, dynamic>.from(j['rollbackTuningState'] as Map))
          : null,
      safetyPassed: j['safetyPassed'] as bool?,
      phaseAware: j['phaseAware'] as bool?,
      nextCycleNumber: j['nextCycleNumber'] as int?,
      requiresUserApproval: j['requiresUserApproval'] as bool? ?? false,
      alignmentReevaluationAllowed:
          j['alignmentReevaluationAllowed'] as bool? ?? false,
    );
  }
}
