import '../../../acoustic/closed_loop_evaluator.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

/// `acousticEvaluateLoop` → [AcousticClosedLoopEvaluator.evaluate].
///
/// Resolves a [LoopSnapshotArtifact] for each of the two inputRefs — the first
/// is the before-apply snapshot and the second is the after-apply snapshot —
/// then calls the pure evaluator with the proProvisional policy. Stores the
/// result as a [ClosedLoopResultArtifact]; the Cloud-facing result carries only
/// the outputRef.
///
/// Read-only: no DSP write, hardware command, rollback, or Apply call is
/// issued here. The [ImprovementVerdict] is for the orchestrator to act on.
class AcousticEvaluateLoopAdapter implements ProToolAdapter {
  const AcousticEvaluateLoopAdapter();

  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticEvaluateLoop;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final (beforeRef, afterRef) = pairedInputRefs(step);

    final beforeArtifact =
        ctx.store.getTyped<LoopSnapshotArtifact>(ctx.projectId, beforeRef);
    final afterArtifact =
        ctx.store.getTyped<LoopSnapshotArtifact>(ctx.projectId, afterRef);

    final result = AcousticClosedLoopEvaluator.evaluate(
      beforeArtifact.value,
      afterArtifact.value,
      ClosedLoopPolicy.proProvisional(),
      evidenceRefs: [beforeRef, afterRef],
    );

    ctx.store
        .put(ctx.projectId, step.outputRef, ClosedLoopResultArtifact(result));

    return referenceResult(
      step,
      confidence: _toolConfidence(result),
      summary: 'verdict=${result.verdict.name}; '
          'scoreDelta=${result.scoreDelta.toStringAsFixed(2)}.',
    );
  }

  ProConfidence _toolConfidence(ClosedLoopResult r) => switch (r.verdict) {
        ImprovementVerdict.improved => ProConfidence.high,
        ImprovementVerdict.neutral => ProConfidence.medium,
        ImprovementVerdict.regressed => ProConfidence.low,
        ImprovementVerdict.inconclusive => ProConfidence.low,
      };
}
