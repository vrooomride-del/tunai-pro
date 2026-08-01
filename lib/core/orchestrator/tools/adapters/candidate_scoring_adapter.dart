import '../../../acoustic/candidate_scoring.dart';
import '../../../acoustic/candidate_scoring_v2.dart';
import '../../../adau1701_peq_response.dart' show PeqResponseBand;
import '../../../pro_response_error.dart'
    show ProResponseError, ResponseErrorResult;
import '../../../pro_simulation_optimizer.dart' show ProSimulationOptimizer;
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_execution.dart';
import '../pro_tool_registry.dart';

/// `acousticScoreCandidates` → [CandidateScorerV2.score] (v2 engine).
///
/// Resolves a [CandidateSetArtifact] (inputRefs[0]) and a
/// [ClassificationArtifact] (inputRefs[1]) — both produced by prior steps —
/// and calls the v2 deterministic scorer with the proProvisional v2 policy.
///
/// Optional inputRefs[2]: a channel ref. When present, per-candidate
/// phase-aware simulation runs via [ProSimulationOptimizer.simulatedResponse]
/// and the results are:
///   1. stored as a [SimulationErrorArtifact] at '${outputRef}:sim_err' for
///      the controller's Before/After confirmation display, and
///   2. passed as [CandidateScoringContextV2.perCandidateSimulatedError] so
///      the v2 scorer can weight simulation quality into each score.
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
    if (step.inputRefs.length < 2) {
      throw ProToolException(
        ProToolFailureCode.missingReference,
        'acousticScoreCandidates requires at least 2 inputRefs '
        '(candidatesRef, classificationRef); got ${step.inputRefs.length}.',
      );
    }
    final candsRef = step.inputRefs[0];
    final classRef = step.inputRefs[1];
    final channelRef = step.inputRefs.length >= 3 ? step.inputRefs[2] : null;

    final candsArtifact =
        ctx.store.getTyped<CandidateSetArtifact>(ctx.projectId, candsRef);
    final classArtifact =
        ctx.store.getTyped<ClassificationArtifact>(ctx.projectId, classRef);

    // Optional per-candidate phase-aware simulation when channelRef is present.
    ResponseErrorResult? beforeError;
    Map<String, ResponseErrorResult>? perCandidateErrors;

    if (channelRef != null) {
      try {
        final input =
            ctx.resolver.resolveSimulationInput(ctx.projectId, channelRef);
        final freqs = input.freqs;
        if (freqs.isNotEmpty) {
          final flatTarget = List<double>.filled(freqs.length, 0.0);
          final weights = ProResponseError.defaultWeights(freqs);

          // Determine simulation mode: phase-aware when FRD phase data is
          // present (same condition as _buildPhaseAwareSummedCurve in
          // pro_simulation_engine.dart). The magnitude scoring algorithm is
          // the same for both modes; the mode label surfaces in the UI.
          final simulationMode = (input.driver.frdData?.hasPhase == true)
              ? 'phase-aware'
              : 'magnitude-only';

          final beforeCurve = ProSimulationOptimizer.simulatedResponse(
            driver: input.driver,
            bands: input.bands,
            freqs: freqs,
          );
          beforeError = ProResponseError.analyze(
            freqs: freqs,
            responseDb: beforeCurve,
            targetDb: flatTarget,
            weights: weights,
          );

          perCandidateErrors = {};
          for (final cand in candsArtifact.value.candidates) {
            final afterBands = [
              ...input.bands,
              PeqResponseBand(
                frequencyHz: cand.frequencyHz,
                gainDb: cand.gainDb,
                q: cand.q,
              ),
            ];
            final afterCurve = ProSimulationOptimizer.simulatedResponse(
              driver: input.driver,
              bands: afterBands,
              freqs: freqs,
            );
            perCandidateErrors[cand.candidateId] = ProResponseError.analyze(
              freqs: freqs,
              responseDb: afterCurve,
              targetDb: flatTarget,
              weights: weights,
            );
          }

          // Store simulation error artifact as side-channel for Before/After UI.
          ctx.store.put(
            ctx.projectId,
            '${step.outputRef}:sim_err',
            SimulationErrorArtifact(
              beforeError,
              Map.unmodifiable(perCandidateErrors),
              simulationMode: simulationMode,
            ),
          );
        }
      } catch (_) {
        // Simulation is best-effort — scoring continues without it.
        beforeError = null;
        perCandidateErrors = null;
      }
    }

    // Score with v2 engine. correctionPlan is null — the candidate generator
    // already filters non-correctable directives; the disposition guard is a
    // double-check that is available when a plan artifact is present.
    final project = ctx.resolver.resolveProjectSnapshot(ctx.projectId);
    final resourceEvidence = project == null
        ? const CandidateScoringResourceEvidence()
        : CandidateScoringResourceEvidence.fromProject(project);
    final v2ctx = CandidateScoringContextV2(
      candidateSet: candsArtifact.value,
      classificationResult: classArtifact.value,
      currentError: beforeError,
      perCandidateSimulatedError: perCandidateErrors,
      availableHeadroomDb: resourceEvidence.availableHeadroomDb,
      protectionMarginDb: resourceEvidence.protectionMarginDb,
    );
    final isAdau1701 = ctx.resolver
            .resolveProjectSnapshot(ctx.projectId)
            ?.dspTarget
            .toUpperCase() ==
        'ADAU1701';
    final v2result = CandidateScorerV2.score(
        v2ctx,
        isAdau1701
            ? CandidateScoringPolicyV2.adau1701Icp5()
            : CandidateScoringPolicyV2.proProvisional());

    // Bridge v2 → v1 so the downstream optimizer receives the expected type.
    final bridged = _toV1(v2result);

    ctx.store.put(
        ctx.projectId, step.outputRef, ScoredCandidateSetArtifact(bridged));

    return referenceResult(
      step,
      confidence: _toolConfidence(bridged),
      summary: '${v2result.scoredCandidates.length} scored (v2); '
          'status=${v2result.status.name}.',
    );
  }

  // ── v2 → v1 bridge ──────────────────────────────────────────────────────

  static ScoredCandidateSet _toV1(ScoredCandidateSetV2 v2) =>
      ScoredCandidateSet(
        status: _mapStatus(v2.status),
        scoredCandidates: [
          for (final c in v2.scoredCandidates) _candidateToV1(c)
        ],
        requiresExpertApproval: v2.requiresExpertApproval,
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
