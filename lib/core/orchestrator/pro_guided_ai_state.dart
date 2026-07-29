// Sealed state hierarchy for ProGuidedAiController.
//
// TRUST BOUNDARY. No DSP value, no frequency, no gain, no Q at any level.
// Only opaque references, lifecycle labels, and prose strings cross this layer.

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

class ProGuidedAiConfirmPending extends ProGuidedAiState {
  final ProUserConfirmationRequest request;
  final ProOrchestratorPlan plan;
  final ProExplanation explanation;
  final List<ProStepExecutionRecord> completedSteps;

  const ProGuidedAiConfirmPending({
    required this.request,
    required this.plan,
    required this.explanation,
    required this.completedSteps,
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
    this.beforeMeasurementRef,
    this.loopPhase,
    this.completedCycle,
  });
}

class ProGuidedAiFailed extends ProGuidedAiState {
  final String message;
  const ProGuidedAiFailed(this.message);
}
