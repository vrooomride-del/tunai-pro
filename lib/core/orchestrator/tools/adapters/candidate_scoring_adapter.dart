import '../../../acoustic/candidate_scoring.dart';
import '../../../acoustic/candidate_scoring_v2.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

/// `acousticScoreCandidates` → [CandidateScorerV2.score] (v2 engine).
///
/// Resolves a [CandidateSetArtifact] (first inputRef) and a
/// [ClassificationArtifact] (second inputRef) — both produced by prior steps —
/// and calls the v2 deterministic scorer with the proProvisional v2 policy.
///
/// The v2 result is bridged to the v1 [ScoredCandidateSet] type so that the
/// existing [CandidateOptimizerAdapter] and downstream consumers continue to
/// receive a [ScoredCandidateSetArtifact] without any change to their code.
///
/// No DSP value, biquad coefficient, gain/Q/address, or hardware command is
/// generated. No AI/LLM score is produced. Optimizer, Safety, and Apply are not
/// connected here.
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

    // Score with v2 engine. correctionPlan is null — the candidate generator
    // already filters non-correctable directives; the disposition guard is a
    // double-check that is available when a plan artifact is present.
    final v2ctx = CandidateScoringContextV2(
      candidateSet: candsArtifact.value,
      classificationResult: classArtifact.value,
    );
    final v2result = CandidateScorerV2.score(
        v2ctx, CandidateScoringPolicyV2.proProvisional());

    // Bridge v2 → v1 so the downstream optimizer receives the expected type.
    final bridged = _toV1(v2result);

    ctx.store
        .put(ctx.projectId, step.outputRef, ScoredCandidateSetArtifact(bridged));

    return referenceResult(
      step,
      confidence: _toolConfidence(bridged),
      summary: '${v2result.scoredCandidates.length} scored (v2); '
          'status=${v2result.status.name}.',
    );
  }

  // ── v2 → v1 bridge ──────────────────────────────────────────────────────

  static ScoredCandidateSet _toV1(ScoredCandidateSetV2 v2) => ScoredCandidateSet(
        status: _mapStatus(v2.status),
        scoredCandidates: [for (final c in v2.scoredCandidates) _candidateToV1(c)],
        reasons: v2.reasons,
        policyId: v2.policyId,
        policyVersion: v2.policyVersion,
        evidenceRefs: v2.evidenceRefs,
      );

  static ScoredCandidate _candidateToV1(ScoredCandidateV2 c) => ScoredCandidate(
        candidate: c.candidate,
        prominenceDb: c.breakdown.targetImprovementScore,
        prominenceScore: c.breakdown.targetImprovementScore,
        magnitudeConsistencyScore: c.breakdown.weightedRmsScore,
        qualityFactor: 1.0,
        compositeScore: c.totalScore.clamp(0.0, 100.0),
        rank: c.rank,
        grade: c.grade,
        reasons: c.explanationEvidenceRefs,
      );

  static ScoredCandidateSetStatus _mapStatus(ScoredCandidateSetV2Status s) =>
      switch (s) {
        ScoredCandidateSetV2Status.ok => ScoredCandidateSetStatus.ok,
        ScoredCandidateSetV2Status.allRejected =>
          ScoredCandidateSetStatus.allRejected,
        ScoredCandidateSetV2Status.insufficientEvidence =>
          ScoredCandidateSetStatus.insufficientEvidence,
        ScoredCandidateSetV2Status.noCorrectableDirectives =>
          ScoredCandidateSetStatus.noCorrectableDirectives,
        ScoredCandidateSetV2Status.invalidPlan =>
          ScoredCandidateSetStatus.invalidPlan,
      };

  ProConfidence _toolConfidence(ScoredCandidateSet s) => switch (s.status) {
        ScoredCandidateSetStatus.ok => ProConfidence.high,
        _ => ProConfidence.low,
      };
}
