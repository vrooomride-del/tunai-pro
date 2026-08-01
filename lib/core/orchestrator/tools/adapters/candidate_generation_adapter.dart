import '../../../acoustic/candidate_set.dart';
import '../../../acoustic/full_system_candidate_evaluator.dart';
import '../../../pro_acoustic_data.dart' show DriverRole;
import '../../../pro_project.dart' show ProProject;
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

CandidateCorrectionRange candidateCorrectionRangeFor(
    ProProject project, String channelId) {
  final driver = project.acousticState.driverChannels
      .firstWhere((channel) => channel.id == channelId);
  final validFrdPoints = (driver.frdData?.points ?? const [])
      .where((point) =>
          point.frequencyHz.isFinite &&
          point.frequencyHz > 0 &&
          point.magnitudeDb != null)
      .toList();

  var minHz = validFrdPoints.isEmpty
      ? 20.0
      : validFrdPoints
          .map((point) => point.frequencyHz)
          .reduce((a, b) => a < b ? a : b);
  var maxHz = validFrdPoints.isEmpty
      ? 20000.0
      : validFrdPoints
          .map((point) => point.frequencyHz)
          .reduce((a, b) => a > b ? a : b);

  final (roleMinHz, roleMaxHz) = switch (driver.role) {
    DriverRole.tweeter || DriverRole.coaxTweeter => (500.0, 20000.0),
    DriverRole.woofer || DriverRole.coaxWoofer => (20.0, 5000.0),
    DriverRole.subwoofer || DriverRole.passiveRadiator => (20.0, 500.0),
    DriverRole.midrange => (100.0, 10000.0),
    DriverRole.fullrange || DriverRole.unknown => (20.0, 20000.0),
  };
  if (roleMinHz > minHz) minHz = roleMinHz;
  if (roleMaxHz < maxHz) maxHz = roleMaxHz;

  final xo = project.tuningState.crossoverChannels
      .where((channel) => channel.channelId == channelId)
      .firstOrNull;
  if (xo != null && !xo.bypassed) {
    if (xo.hasHighPass && xo.highPass!.frequencyHz > minHz) {
      minHz = xo.highPass!.frequencyHz;
    }
    if (xo.hasLowPass && xo.lowPass!.frequencyHz < maxHz) {
      maxHz = xo.lowPass!.frequencyHz;
    }
  }

  return CandidateCorrectionRange(
    channelId: channelId,
    minFrequencyHz: minHz,
    maxFrequencyHz: maxHz,
  );
}

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

    final isAdau1701 = ctx.resolver
            .resolveProjectSnapshot(ctx.projectId)
            ?.dspTarget
            .toUpperCase() ==
        'ADAU1701';
    final project = ctx.resolver.resolveProjectSnapshot(ctx.projectId);
    // Candidate generation consumes exactly planRef + classificationRef.
    // The channel is carried in the deterministic step objective and is used
    // only to derive the existing Driver/XO/FRD correction range.
    final channelId = FullSystemCandidateEvaluator.requiredChannelIds
        .where((id) => step.objective.contains(id))
        .firstOrNull;
    final candidateSet = CandidateGenerator.generate(
      planArtifact.value,
      classArtifact.value,
      isAdau1701
          ? CandidatePolicy.adau1701Icp5()
          : CandidatePolicy.proProvisional(),
      correctionRange: project != null && channelId != null
          ? candidateCorrectionRangeFor(project, channelId)
          : null,
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
