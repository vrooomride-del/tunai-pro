import '../../../pro_impedance_analysis.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

/// `impedanceAnalyze` → [ProImpedanceAnalyzer].
///
/// Resolves a local `MeasurementProjectState` from the step's single inputRef,
/// calls the existing analyzer unchanged, and stores the result as an
/// [ImpedanceArtifact] at the step's outputRef. The numeric analysis stays in
/// the store; the Cloud-facing result carries only references.
class ImpedanceAnalyzeAdapter implements ProToolAdapter {
  const ImpedanceAnalyzeAdapter();

  @override
  ProOrchestratorToolId get toolId => ProOrchestratorToolId.impedanceAnalyze;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final ref = singleInputRef(step);
    final state =
        ctx.resolver.resolveMeasurementProjectState(ctx.projectId, ref);

    final analysis = ProImpedanceAnalyzer.analyze(acousticState: state);

    ctx.store.put(ctx.projectId, step.outputRef, ImpedanceArtifact(analysis));
    return referenceResult(step, confidence: ProConfidence.high);
  }
}
