import '../../../acoustic/candidate_safety.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

/// `acousticValidateSafety` → [AcousticSelectionValidator.validate].
///
/// Resolves an [OptimizedSelectionArtifact] from the step's single inputRef
/// (produced by a prior `acousticOptimizeSelection` step) and calls the pure
/// safety validator with the proProvisional policy. Stores the result as a
/// [CandidateSafetyArtifact]; the Cloud-facing result carries only the outputRef.
///
/// Read-only: no DSP write, tuning state update, or hardware command is issued.
/// [CandidateSafetyResult.applyPermitted] must be checked by a downstream
/// orchestrator step before any Apply action — this adapter never calls Apply.
class CandidateSafetyAdapter implements ProToolAdapter {
  const CandidateSafetyAdapter();

  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticValidateSafety;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final ref = singleInputRef(step);

    final optimArtifact =
        ctx.store.getTyped<OptimizedSelectionArtifact>(ctx.projectId, ref);

    final safetyResult = AcousticSelectionValidator.validate(
      optimArtifact.value,
      CandidateSafetyPolicy.proProvisional(),
    );

    ctx.store.put(
        ctx.projectId, step.outputRef, CandidateSafetyArtifact(safetyResult));

    return referenceResult(
      step,
      confidence: _toolConfidence(safetyResult),
      summary: 'applyPermitted=${safetyResult.applyPermitted}; '
          '${safetyResult.issues.length} issue(s).',
    );
  }

  ProConfidence _toolConfidence(CandidateSafetyResult r) =>
      r.applyPermitted ? ProConfidence.high : ProConfidence.low;
}
