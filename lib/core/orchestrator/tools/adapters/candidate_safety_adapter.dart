import '../../../acoustic/candidate_safety.dart';
import '../../../acoustic/speaker_capability_evidence.dart';
import 'dart:math' as math;
import '../../../pro_protection_data.dart';
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

    final isAdau1701 = ctx.resolver
            .resolveProjectSnapshot(ctx.projectId)
            ?.dspTarget
            .toUpperCase() ==
        'ADAU1701';
    final project = ctx.resolver.resolveProjectSnapshot(ctx.projectId);
    var policy = isAdau1701
        ? CandidateSafetyPolicy.adau1701Icp5()
        : CandidateSafetyPolicy.proProvisional();
    final maxCutRule = project?.protectionState.rules
        .where((rule) =>
            rule.enabled &&
            rule.type == ProtectionRuleType.maxCut &&
            rule.threshold.isFinite &&
            rule.threshold < 0)
        .firstOrNull;
    if (maxCutRule != null) {
      policy = policy.copyWith(
          maxCutDb: math.min(policy.maxCutDb, maxCutRule.threshold.abs()));
    }
    var safetyResult = AcousticSelectionValidator.validate(
      optimArtifact.value,
      policy,
    );
    if (project != null) {
      final evidence = SpeakerCapabilityEvidence.fromProject(project);
      final capabilityIssues = <CandidateSafetyIssue>[];
      for (final candidate in safetyResult.verifiedCandidates) {
        final e = evidence[candidate.scoredCandidate.candidate.channelId];
        if (e != null && !e.permitsGain(candidate.scoredCandidate.candidate.gainDb)) {
          capabilityIssues.add(CandidateSafetyIssue(
            code: CandidateSafetyViolationCode.gainOutOfRange,
            candidateId: candidate.scoredCandidate.candidate.candidateId,
            detail: 'Protection evidence rejects ${candidate.scoredCandidate.candidate.channelId}.',
          ));
        }
      }
      if (capabilityIssues.isNotEmpty) {
        safetyResult = CandidateSafetyResult(
          applyPermitted: false,
          issues: [...safetyResult.issues, ...capabilityIssues],
          verifiedCandidates: const [],
          policyId: safetyResult.policyId,
          policyVersion: safetyResult.policyVersion,
          evidenceRefs: [...safetyResult.evidenceRefs, ...capabilityIssues.map((i) => i.detail)],
        );
      }
    }

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
