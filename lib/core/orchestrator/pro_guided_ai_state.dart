// Sealed state hierarchy for ProGuidedAiController.
//
// TRUST BOUNDARY. No raw DSP register value crosses this layer.
// CandidatePreviewEntry carries display-only values that already exist in the
// artifact store; they are mirrored here for the confirmation-gate UI only
// and are never written to hardware directly.

import '../acoustic/acoustic_apply_engine.dart';
import '../acoustic/closed_loop_evaluator.dart';
import '../pro_correction_cycle.dart';
import 'pro_explanation.dart';
import 'pro_local_orchestrator_session.dart';
import 'pro_orchestrator_plan.dart';
import 'pro_orchestrator_types.dart';

sealed class ProGuidedAiState {
  const ProGuidedAiState();
}

class ProGuidedAiIdle extends ProGuidedAiState {
  const ProGuidedAiIdle();
}

class ProGuidedAiCloudCalling extends ProGuidedAiState {
  const ProGuidedAiCloudCalling();
}

class ProGuidedAiExecuting extends ProGuidedAiState {
  final ProOrchestratorPlan plan;
  final ProExplanation explanation;
  final List<ProStepExecutionRecord> completedSteps;

  /// Non-null while one step is running; null between steps.
  final ProOrchestratorToolId? currentToolId;

  const ProGuidedAiExecuting({
    required this.plan,
    required this.explanation,
    required this.completedSteps,
    this.currentToolId,
  });
}

/// Display-only entry for the confirmation-gate candidate preview table.
/// Values are mirrored from OptimizedSelectionArtifact in the artifact store.
/// Safety validation has NOT yet run at the time this is constructed — the
/// safety status is "pending" for all entries.
class CandidatePreviewEntry {
  final int applicationOrder;
  final double frequencyHz;
  final double gainDb;
  final double q;
  final String grade;

  /// PEQ channel that will receive this candidate on apply.
  /// Empty string when the analyzed channel could not be determined.
  final String channelId;

  /// Whether safety validation has cleared this candidate.
  /// Always false at the confirmation gate (safety runs after user confirms).
  final bool safetyVerified;

  /// 1-based PEQ slot index that will be used on apply, computed by simulating
  /// fillNextFreeSlot against the current PeqChannelState at confirmation time.
  /// Null when the target channel state is unavailable.
  final int? targetPeqSlot;

  const CandidatePreviewEntry({
    required this.applicationOrder,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.grade,
    required this.channelId,
    this.safetyVerified = false,
    this.targetPeqSlot,
  });
}

class ProGuidedAiConfirmPending extends ProGuidedAiState {
  final ProUserConfirmationRequest request;
  final ProOrchestratorPlan plan;
  final ProExplanation explanation;
  final List<ProStepExecutionRecord> completedSteps;

  /// Display-only preview of candidates at the confirmation gate.
  /// Null when the OptimizedSelectionArtifact is not yet in the store.
  final List<CandidatePreviewEntry>? candidatePreview;

  /// Non-null when apply is blocked; contains the human-readable reason.
  final String? applyBlockedReason;

  /// PEQ channel targeted by this confirmation (same as candidatePreview[].channelId).
  final String? targetChannelId;

  /// Number of PEQ slots available in the target channel.
  /// Used to show slot availability vs required count.
  final int? availablePeqSlots;

  const ProGuidedAiConfirmPending({
    required this.request,
    required this.plan,
    required this.explanation,
    required this.completedSteps,
    this.candidatePreview,
    this.applyBlockedReason,
    this.targetChannelId,
    this.availablePeqSlots,
  });
}

/// Post-apply closed-loop lifecycle phase.
///
/// `awaitingMeasurement` — apply succeeded; the UI should prompt the user to
/// re-measure so a Closed Loop comparison can run.
/// `awaitingAfterFrd`    — an After FRD import is pending (deploy done, no
///   after measurement yet). Mutually exclusive with `awaitingMeasurement`.
/// `evaluated`           — both before/after snapshots were available and
/// [AcousticClosedLoopEvaluator] produced a [LoopVerdict].
/// `cycleComplete`       — a [CorrectionCycle] has been evaluated and persisted.
///
/// Never carries a DSP value: this is a lifecycle label only.
enum ProClosedLoopPhase {
  awaitingMeasurement,
  awaitingAfterFrd,
  evaluated,
  cycleComplete,
}

class ProGuidedAiCompleted extends ProGuidedAiState {
  final ProLocalOrchestratorOutcome outcome;
  final ProExplanation explanation;

  /// Non-null when `acousticEvaluateLoop` ran and produced a verdict.
  /// `improved`, `regressed`, or `inconclusive` — never a DSP number.
  final ImprovementVerdict? loopVerdict;

  /// Non-null when the Apply Coordinator ran after safety validation.
  /// Contains the applied/skipped band audit — no DSP register values.
  final TuningApplyResult? applyResult;

  /// Non-null when safety validation ran but apply was not permitted.
  /// Human-readable blocking reason(s). Null when apply ran or safety
  /// did not run. Never a DSP value.
  final String? applyBlockedReason;

  /// Opaque artifact-store key for the before-apply measurement artifact.
  /// Present when apply succeeded; used to retrieve [MeasurementArtifact] for
  /// the Closed Loop comparison once an after-measurement is available.
  /// Never a DSP value — just a lookup reference.
  final String? beforeMeasurementRef;

  /// Closed Loop phase after apply. Null when no apply ran.
  final ProClosedLoopPhase? loopPhase;

  /// Completed correction cycle — non-null when [loopPhase] is
  /// [ProClosedLoopPhase.cycleComplete]. Contains the decision and metrics.
  final CorrectionCycle? completedCycle;

  const ProGuidedAiCompleted({
    required this.outcome,
    required this.explanation,
    this.loopVerdict,
    this.applyResult,
    this.applyBlockedReason,
    this.beforeMeasurementRef,
    this.loopPhase,
    this.completedCycle,
  });
}

class ProGuidedAiFailed extends ProGuidedAiState {
  final String message;
  const ProGuidedAiFailed(this.message);
}
