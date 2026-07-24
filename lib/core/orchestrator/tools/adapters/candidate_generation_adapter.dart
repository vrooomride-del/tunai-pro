import '../../../acoustic/candidate_set.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

/// `acousticGenerateCandidates` → [CandidateGenerator.generate].
///
/// Resolves a [CorrectionPlanArtifact] (first inputRef) and a
/// [ClassificationArtifact] (second inputRef) — both produced by prior steps —
/// and calls the pure generator with the proProvisional policy. Stores the
/// result as a [CandidateSetArtifact]; the Cloud-facing result carries only the
/// outputRef.
///
/// Read-only: no DSP value, biquad coefficient, gain/Q/address, or hardware
/// command is generated. Scoring, optimizer, Safety, and Apply are not
/// connected here.
class CandidateGenerationAdapter implements ProToolAdapter {
  const CandidateGenerationAdapter();

  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticGenerateCandidates;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final (planRef, classRef) = pairedInputRefs(step);

    final planArtifact =
        ctx.store.getTyped<CorrectionPlanArtifact>(ctx.projectId, planRef);
    final classArtifact =
        ctx.store.getTyped<ClassificationArtifact>(ctx.projectId, classRef);

    final candidateSet = CandidateGenerator.generate(
      planArtifact.value,
      classArtifact.value,
      CandidatePolicy.proProvisional(),
    );

    ctx.store
        .put(ctx.projectId, step.outputRef, CandidateSetArtifact(candidateSet));

    return referenceResult(
      step,
      confidence: _toolConfidence(candidateSet),
      summary: '${candidateSet.candidates.length} candidate(s); '
          'status=${candidateSet.status.name}.',
    );
  }

  ProConfidence _toolConfidence(CandidateSet s) => switch (s.status) {
        CandidateSetStatus.ok => ProConfidence.high,
        _ => ProConfidence.low,
      };
}
