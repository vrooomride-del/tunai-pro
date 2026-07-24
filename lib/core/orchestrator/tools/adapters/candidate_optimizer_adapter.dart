import '../../../acoustic/candidate_optimizer.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

/// `acousticOptimizeSelection` → [CandidateOptimizer.select].
///
/// Resolves a [ScoredCandidateSetArtifact] from the step's single inputRef
/// (produced by a prior `acousticScoreCandidates` step) and calls the pure
/// optimizer with the proProvisional policy. Stores the result as an
/// [OptimizedSelectionArtifact]; the Cloud-facing result carries only the
/// outputRef.
///
/// Read-only: no DSP value, biquad coefficient, gain/Q/address, or hardware
/// command is generated. Safety and Apply are not connected here.
class CandidateOptimizerAdapter implements ProToolAdapter {
  const CandidateOptimizerAdapter();

  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticOptimizeSelection;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final ref = singleInputRef(step);

    final scoredArtifact =
        ctx.store.getTyped<ScoredCandidateSetArtifact>(ctx.projectId, ref);

    final selection = CandidateOptimizer.select(
      scoredArtifact.value,
      OptimizerPolicy.proProvisional(),
    );

    ctx.store.put(
        ctx.projectId, step.outputRef, OptimizedSelectionArtifact(selection));

    return referenceResult(
      step,
      confidence: _toolConfidence(selection),
      summary: '${selection.selected.length} selected; '
          'status=${selection.status.name}.',
    );
  }

  ProConfidence _toolConfidence(OptimizedSelection s) => switch (s.status) {
        OptimizationStatus.ok => ProConfidence.high,
        _ => ProConfidence.low,
      };
}
