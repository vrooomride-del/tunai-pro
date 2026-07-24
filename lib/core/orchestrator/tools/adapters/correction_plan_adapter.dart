import '../../../acoustic/correction_plan.dart';
import '../../../acoustic/correction_policy.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

/// `acousticPlan` → [CorrectionPlanner.plan].
///
/// Resolves a [ClassificationArtifact] from the step's single inputRef (the
/// output of a prior `acousticClassify` step), and calls the pure planner with
/// the proProvisional policy. Stores the result as a [CorrectionPlanArtifact];
/// the Cloud-facing result carries only the outputRef.
///
/// Read-only: no DSP value, biquad, gain/Q/address, or hardware command is
/// generated. Candidate generation, optimizer, Safety, and Apply are not
/// connected here.
class CorrectionPlanAdapter implements ProToolAdapter {
  const CorrectionPlanAdapter();

  @override
  ProOrchestratorToolId get toolId => ProOrchestratorToolId.acousticPlan;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final ref = singleInputRef(step);
    final artifact =
        ctx.store.getTyped<ClassificationArtifact>(ctx.projectId, ref);

    final plan = CorrectionPlanner.plan(
      artifact.value,
      CorrectionPolicy.proProvisional(),
    );

    ctx.store.put(ctx.projectId, step.outputRef, CorrectionPlanArtifact(plan));

    return referenceResult(
      step,
      confidence: _toolConfidence(plan),
      summary: '${plan.directives.length} directive(s); '
          'status=${plan.status.name}.',
    );
  }

  ProConfidence _toolConfidence(CorrectionPlan plan) => switch (plan.status) {
        CorrectionPlanStatus.ok => ProConfidence.high,
        CorrectionPlanStatus.insufficientEvidence => ProConfidence.low,
        CorrectionPlanStatus.invalidMeasurement => ProConfidence.low,
      };
}
