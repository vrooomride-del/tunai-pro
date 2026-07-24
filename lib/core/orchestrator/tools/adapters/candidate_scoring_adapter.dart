import '../../../acoustic/candidate_scoring.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

/// `acousticScoreCandidates` → [CandidateScorer.score].
///
/// Resolves a [CandidateSetArtifact] (first inputRef) and a
/// [ClassificationArtifact] (second inputRef) — both produced by prior steps —
/// and calls the pure scorer with the proProvisional policy. Stores the result
/// as a [ScoredCandidateSetArtifact]; the Cloud-facing result carries only the
/// outputRef.
///
/// Read-only: no DSP value, biquad coefficient, gain/Q/address, or hardware
/// command is generated. Optimizer, Safety, and Apply are not connected here.
class CandidateScoringAdapter implements ProToolAdapter {
  const CandidateScoringAdapter();

  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticScoreCandidates;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final (candsRef, classRef) = pairedInputRefs(step);

    final candsArtifact =
        ctx.store.getTyped<CandidateSetArtifact>(ctx.projectId, candsRef);
    final classArtifact =
        ctx.store.getTyped<ClassificationArtifact>(ctx.projectId, classRef);

    final scored = CandidateScorer.score(
      candsArtifact.value,
      classArtifact.value,
      ScoringPolicy.proProvisional(),
    );

    ctx.store
        .put(ctx.projectId, step.outputRef, ScoredCandidateSetArtifact(scored));

    return referenceResult(
      step,
      confidence: _toolConfidence(scored),
      summary: '${scored.scoredCandidates.length} scored; '
          'status=${scored.status.name}.',
    );
  }

  ProConfidence _toolConfidence(ScoredCandidateSet s) => switch (s.status) {
        ScoredCandidateSetStatus.ok => ProConfidence.high,
        _ => ProConfidence.low,
      };
}
