// Sealed state hierarchy for ProGuidedAiController.
//
// TRUST BOUNDARY. No DSP value, no frequency, no gain, no Q at any level.
// Only opaque references, lifecycle labels, and prose strings cross this layer.

import '../acoustic/closed_loop_evaluator.dart';
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

class ProGuidedAiCompleted extends ProGuidedAiState {
  final ProLocalOrchestratorOutcome outcome;
  final ProExplanation explanation;

  /// Non-null when `acousticEvaluateLoop` ran and produced a verdict.
  /// `improved`, `regressed`, or `inconclusive` — never a DSP number.
  final ImprovementVerdict? loopVerdict;

  const ProGuidedAiCompleted({
    required this.outcome,
    required this.explanation,
    this.loopVerdict,
  });
}

class ProGuidedAiFailed extends ProGuidedAiState {
  final String message;
  const ProGuidedAiFailed(this.message);
}
