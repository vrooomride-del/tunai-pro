// TRUST BOUNDARY. No DSP value, no hardware command.
//
// Drives a complete guided-AI session:
//   1. Accepts a user goal + project snapshot.
//   2. Calls ProOrchestrateService (Cloud) → ProOrchestrateResponse.
//   3. Runs ProLocalOrchestrator (stream) → lifecycle events.
//   4. Pauses at requiresUserConfirmation gates; caller calls confirm/cancel.
//   5. After ProPlanCompleted, extracts ImprovementVerdict if the loop ran.
//
// [adapterOverrides] is intentionally public for test injection: pass stub
// adapters to avoid touching the real Acoustic Engine in unit tests.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../acoustic/acoustic_apply_engine.dart';
import '../acoustic/candidate_safety.dart';
import '../frd_parser.dart';
import '../pro_correction_cycle.dart';
import '../pro_tuning_data.dart';
import '../acoustic/closed_loop_evaluator.dart';
import '../pro_project.dart';
import '../spectrum_snapshot.dart';
import 'correction_cycle_evaluator.dart';
import 'pro_acoustic_intent.dart';
import 'pro_guided_ai_state.dart';
import 'pro_local_orchestrator.dart';
import 'pro_local_orchestrator_session.dart';
import 'pro_orchestrate_request.dart';
import 'pro_orchestrate_service.dart';
import 'pro_orchestrator_context.dart';
import 'pro_orchestrator_types.dart';
import 'tools/adapters/acoustic_classify_adapter.dart';
import 'tools/adapters/acoustic_evaluate_loop_adapter.dart';
import 'tools/adapters/candidate_generation_adapter.dart';
import 'tools/adapters/candidate_optimizer_adapter.dart';
import 'tools/adapters/candidate_safety_adapter.dart';
import 'tools/adapters/candidate_scoring_adapter.dart';
import 'tools/adapters/correction_plan_adapter.dart';
import 'tools/adapters/impedance_analyze_adapter.dart';
import 'tools/adapters/parsed_measurement_adapter.dart';
import 'tools/adapters/simulate_adapter.dart';
import 'tools/pro_project_resolver.dart';
import 'tools/pro_tool_artifact_store.dart';
import 'tools/pro_tool_registry.dart';
import 'pro_closed_loop_measurement_bridge.dart';

final guidedAiProvider =
    StateNotifierProvider.autoDispose<ProGuidedAiController, ProGuidedAiState>(
  (ref) => ProGuidedAiController(),
);

class ProGuidedAiController extends StateNotifier<ProGuidedAiState> {
  final ProOrchestrateService _cloudService;

  // Null → production adapters; non-null → test stub adapters.
  final List<ProToolAdapter>? _adapterOverrides;

  ProLocalOrchestrator? _orchestrator;

  // Preserved after a session completes so submitAfterMeasurement can
  // retrieve the before-measurement artifact for closed-loop comparison.
  ProToolArtifactStore? _sessionStore;
  String? _sessionProjectId;

  ProGuidedAiController({
    ProOrchestrateService? service,
    List<ProToolAdapter>? adapterOverrides,
  })  : _cloudService = service ?? ProOrchestrateService(),
        _adapterOverrides = adapterOverrides,
        super(const ProGuidedAiIdle());

  // ── Public API ───────────────────────────────────────────────────────────────

  Future<void> start({
    required ProProject project,
    required String userGoal,
    // When set, only this channel's ID is passed as measurementRef so the
    // orchestrator analyzes the exact selected channel. Null → all channels.
    String? targetChannelId,
    // Called after acousticValidateSafety completes to persist the apply result.
    // Null → apply step is skipped (tests, offline mode).
    Future<void> Function(String projectId, TuningApplyResult)? onApply,
  }) async {
    if (state is! ProGuidedAiIdle) return;
    state = const ProGuidedAiCloudCalling();

    final pid = project.id;

    final measRefs = targetChannelId != null
        ? [targetChannelId]
        : [for (final ch in project.acousticState.driverChannels) ch.id];

    final request = ProOrchestrateRequest(
      projectId: pid,
      intent: ProAcousticIntent(
        userGoal: userGoal.trim().isEmpty ? '음향 분석 및 최적화' : userGoal.trim(),
        perceivedProblem: '',
        systemScope: 'full_system',
        tuningPriority: ProTuningPriority.balanced,
        allowedChangeAreas: const [
          ProToneArea.lowEnd,
          ProToneArea.midRange,
          ProToneArea.highEnd,
          ProToneArea.overallTone,
        ],
        protectedAreas: const [],
        listeningContext: '',
        explanationLevel: ProExplanationLevel.intermediate,
      ),
      context: ProOrchestratorContext(
        projectId: pid,
        connectionState: ProConnectionState.disconnected,
        measurementRefs: measRefs,
      ),
    );

    final cloudOutcome = await _cloudService.call(request);
    if (cloudOutcome is ProOrchestrateFailure) {
      state = ProGuidedAiFailed(cloudOutcome.message);
      return;
    }

    final response = (cloudOutcome as ProOrchestrateSuccess).response;
    final plan = response.plan;
    final explanation = response.explanation;

    final adapters = _adapterOverrides ??
        [
          const ParsedMeasurementAdapter(),
          const AcousticClassifyAdapter(),
          const CorrectionPlanAdapter(),
          const CandidateGenerationAdapter(),
          const CandidateScoringAdapter(),
          const CandidateOptimizerAdapter(),
          const CandidateSafetyAdapter(),
          const AcousticEvaluateLoopAdapter(),
          const ImpedanceAnalyzeAdapter(),
          const SimulateAdapter(),
        ];

    final registry = ProDeterministicToolRegistry(adapters);
    final store = ProToolArtifactStore();

    final resolver = ProProjectResolver(project: project);

    final ctx = ProToolExecutionContext(
      projectId: pid,
      contextRef: plan.contextRef,
      resolver: resolver,
      store: store,
    );

    _orchestrator = ProLocalOrchestrator(registry);
    final completedSteps = <ProStepExecutionRecord>[];
    TuningApplyResult? applyResult;

    await for (final event in _orchestrator!.run(plan, ctx)) {
      switch (event) {
        case ProStepStarted(:final toolId):
          state = ProGuidedAiExecuting(
            plan: plan,
            explanation: explanation,
            completedSteps: List.unmodifiable(completedSteps),
            currentToolId: toolId,
          );
        case ProStepCompleted(:final record):
          completedSteps.add(record);
          // Apply gate: runs after safety validation, before plan completion.
          if (record.toolId == ProOrchestratorToolId.acousticValidateSafety &&
              onApply != null) {
            // Identify which driver channel was analyzed so the apply targets
            // the correct PEQ channel in multi-channel projects.
            final analyzedChannelId = plan.steps
                .where(
                    (s) => s.toolId == ProOrchestratorToolId.measurementAnalyze)
                .firstOrNull
                ?.inputRefs
                .firstOrNull;
            applyResult = _runApply(pid, store, record.outputRef, project,
                analyzedChannelId: analyzedChannelId);
            if (applyResult != null) {
              await onApply(pid, applyResult);
            }
          }
          state = ProGuidedAiExecuting(
            plan: plan,
            explanation: explanation,
            completedSteps: List.unmodifiable(completedSteps),
          );
        case ProWaitingConfirmation(:final request):
          // Determine the channel that will be written on apply — same logic
          // as the apply gate below.
          final analyzedChannelId = plan.steps
              .where((s) =>
                  s.toolId == ProOrchestratorToolId.measurementAnalyze)
              .firstOrNull
              ?.inputRefs
              .firstOrNull;

          // Available PEQ slots for the target channel.
          final targetChannel = analyzedChannelId != null
              ? project.tuningState.peqChannels
                  .where((ch) => ch.channelId == analyzedChannelId)
                  .firstOrNull
              : project.tuningState.peqChannels.firstOrNull;
          final availableSlots = targetChannel?.bands.length;

          List<CandidatePreviewEntry>? preview;
          String? applyBlockedReason;

          final optRef = completedSteps
              .where((r) =>
                  r.toolId == ProOrchestratorToolId.acousticOptimizeSelection)
              .firstOrNull
              ?.outputRef;
          if (optRef != null && store.has(pid, optRef)) {
            try {
              final opt =
                  store.getTyped<OptimizedSelectionArtifact>(pid, optRef);
              final channelLabel = analyzedChannelId ?? '';
              final needed = opt.value.selected.length;
              if (availableSlots != null && needed > availableSlots) {
                applyBlockedReason =
                    '슬롯 부족: $needed개 필요, 채널 ${channelLabel.isNotEmpty ? channelLabel : "—"}에 $availableSlots개 가능';
              }
              // Simulate fillNextFreeSlot in applicationOrder to determine the
              // 1-based PEQ slot each candidate will occupy on apply.
              final slotMap = <int, int?>{};
              if (targetChannel != null) {
                var simCh = targetChannel;
                final sorted = [...opt.value.selected]
                  ..sort((a, b) =>
                      a.applicationOrder.compareTo(b.applicationOrder));
                for (final sel in sorted) {
                  final norm = simCh.normalized();
                  final idx = norm.bands.indexWhere((b) => !b.enabled);
                  slotMap[sel.applicationOrder] =
                      idx >= 0 ? idx + 1 : null;
                  if (idx >= 0) {
                    simCh = simCh.fillNextFreeSlot(
                      type: PeqBandType.peak,
                      frequencyHz:
                          sel.scoredCandidate.candidate.frequencyHz,
                      gainDb: sel.scoredCandidate.candidate.gainDb,
                      q: sel.scoredCandidate.candidate.q,
                    );
                  }
                }
              }
              preview = [
                for (final c in opt.value.selected)
                  CandidatePreviewEntry(
                    applicationOrder: c.applicationOrder,
                    frequencyHz: c.scoredCandidate.candidate.frequencyHz,
                    gainDb: c.scoredCandidate.candidate.gainDb,
                    q: c.scoredCandidate.candidate.q,
                    grade: c.scoredCandidate.grade.name,
                    channelId: channelLabel,
                    safetyVerified: false,
                    targetPeqSlot: slotMap[c.applicationOrder],
                  ),
              ];
            } catch (_) {}
          }
          state = ProGuidedAiConfirmPending(
            request: request,
            plan: plan,
            explanation: explanation,
            completedSteps: List.unmodifiable(completedSteps),
            candidatePreview: preview,
            applyBlockedReason: applyBlockedReason,
            targetChannelId: analyzedChannelId,
            availablePeqSlots: availableSlots,
          );
        case ProPlanCompleted(:final outcome):
          final loopVerdict =
              _extractVerdict(pid, store, outcome.loopResultRef);
          final beforeRef = completedSteps
              .where(
                  (r) => r.toolId == ProOrchestratorToolId.measurementAnalyze)
              .firstOrNull
              ?.outputRef;
          final loopPhase = loopVerdict != null
              ? ProClosedLoopPhase.evaluated
              : (applyResult != null &&
                      applyResult.status != TuningApplyStatus.notPermitted)
                  ? ProClosedLoopPhase.awaitingMeasurement
                  : null;
          state = ProGuidedAiCompleted(
            outcome: outcome,
            explanation: explanation,
            loopVerdict: loopVerdict,
            applyResult: applyResult,
            beforeMeasurementRef: beforeRef,
            loopPhase: loopPhase,
          );
        case ProPlanFailed(:final outcome):
          state = ProGuidedAiFailed(outcome.terminationReason ?? '실행 실패');
        case ProPlanRejected(:final outcome):
          state = ProGuidedAiFailed(outcome.terminationReason ?? '사용자 취소');
      }
    }
    // Preserve store so submitAfterMeasurement can retrieve before artifacts.
    _sessionStore = store;
    _sessionProjectId = pid;
  }

  void confirm(String stepId) => _orchestrator?.confirm(stepId);
  void cancel(String stepId) => _orchestrator?.cancel(stepId);

  /// Receives the after-measurement artifact and transitions the state from
  /// [ProClosedLoopPhase.awaitingMeasurement] to [ProClosedLoopPhase.evaluated].
  ///
  /// No-op unless the current state is [ProGuidedAiCompleted] with
  /// [ProClosedLoopPhase.awaitingMeasurement] and a valid before-measurement ref.
  /// No fake verdict is ever produced.
  void submitAfterMeasurement({
    required MeasurementArtifact afterArtifact,
    required String afterRef,
  }) {
    final current = state;
    if (current is! ProGuidedAiCompleted) return;
    if (current.loopPhase != ProClosedLoopPhase.awaitingMeasurement) return;
    final beforeRef = current.beforeMeasurementRef;
    final store = _sessionStore;
    final pid = _sessionProjectId;
    if (beforeRef == null || store == null || pid == null) return;

    MeasurementArtifact beforeArtifact;
    try {
      beforeArtifact = store.getTyped<MeasurementArtifact>(pid, beforeRef);
    } catch (_) {
      return;
    }

    final result = ProClosedLoopMeasurementBridge.evaluate(
      beforeArtifact: beforeArtifact,
      beforeRef: beforeRef,
      afterArtifact: afterArtifact,
      afterRef: afterRef,
    );
    if (result == null) return;

    state = ProGuidedAiCompleted(
      outcome: current.outcome,
      explanation: current.explanation,
      loopVerdict: result.verdict,
      applyResult: current.applyResult,
      beforeMeasurementRef: beforeRef,
      loopPhase: ProClosedLoopPhase.evaluated,
    );
  }

  /// Receives live-mic bins and transitions the state from
  /// [ProClosedLoopPhase.awaitingMeasurement] to [ProClosedLoopPhase.evaluated].
  ///
  /// Parallel to [submitAfterMeasurement] but accepts a [List<FrequencyBin>]
  /// (e.g. converted from [MicMeasurementState.frequencyResponse]) instead of
  /// a [MeasurementArtifact]. No-op unless conditions in [submitAfterMeasurement]
  /// are met. No fake verdict is ever produced.
  void submitAfterMeasurementFromBins({
    required List<FrequencyBin> afterBins,
    required String afterRef,
  }) {
    final current = state;
    if (current is! ProGuidedAiCompleted) return;
    if (current.loopPhase != ProClosedLoopPhase.awaitingMeasurement) return;
    final beforeRef = current.beforeMeasurementRef;
    final store = _sessionStore;
    final pid = _sessionProjectId;
    if (beforeRef == null || store == null || pid == null) return;

    MeasurementArtifact beforeArtifact;
    try {
      beforeArtifact = store.getTyped<MeasurementArtifact>(pid, beforeRef);
    } catch (_) {
      return;
    }

    final result = ProClosedLoopMeasurementBridge.evaluateWithBins(
      beforeArtifact: beforeArtifact,
      beforeRef: beforeRef,
      afterBins: afterBins,
      afterRef: afterRef,
    );
    if (result == null) return;

    state = ProGuidedAiCompleted(
      outcome: current.outcome,
      explanation: current.explanation,
      loopVerdict: result.verdict,
      applyResult: current.applyResult,
      beforeMeasurementRef: beforeRef,
      loopPhase: ProClosedLoopPhase.evaluated,
    );
  }

  /// Transitions to [ProClosedLoopPhase.awaitingAfterFrd] when the current
  /// state is completed and [applyResult] succeeded.
  ///
  /// Call this when the user taps "Add After Measurement" after a confirmed
  /// Deploy, before providing the After FRD file.
  void enterAwaitingAfterFrd() {
    final current = state;
    if (current is! ProGuidedAiCompleted) return;
    if (current.applyResult?.status != TuningApplyStatus.ok) return;
    state = ProGuidedAiCompleted(
      outcome: current.outcome,
      explanation: current.explanation,
      loopVerdict: current.loopVerdict,
      applyResult: current.applyResult,
      beforeMeasurementRef: current.beforeMeasurementRef,
      loopPhase: ProClosedLoopPhase.awaitingAfterFrd,
      completedCycle: current.completedCycle,
    );
  }

  /// Accepts parsed After FRD [afterFrdPoints] and the Before FRD
  /// [beforeFrdPoints] (read from the active project's driver channel), builds
  /// a [CorrectionCycle], transitions to [ProClosedLoopPhase.cycleComplete],
  /// and returns the completed cycle for the caller to persist.
  ///
  /// Returns null when:
  ///  - the current state is not [ProGuidedAiCompleted.awaitingAfterFrd]
  ///  - the before/after FRD data is empty
  ///  - the project/channel identity is invalid
  ///
  /// Never produces a fake verdict. The caller is responsible for calling
  /// [ProProjectStoreNotifier.addCorrectionCycle] / [updateCorrectionCycle].
  CorrectionCycle? submitAfterFrd({
    required String projectId,
    required String channelId,
    required List<FrdPoint> beforeFrdPoints,
    required String beforeMeasurementRef,
    required List<FrdPoint> afterFrdPoints,
    required String afterMeasurementRef,
    required String afterMeasurementFileName,
    required PeqChannelState peqSnapshot,
    required int cycleNumber,
    String? deployAckRef,
  }) {
    final current = state;
    if (current is! ProGuidedAiCompleted) return null;
    if (current.loopPhase != ProClosedLoopPhase.awaitingAfterFrd) return null;

    final evalInput = CorrectionCycleEvalInput(
      projectId: projectId,
      channelId: channelId,
      beforeFrd: beforeFrdPoints,
      beforeMeasurementRef: beforeMeasurementRef,
      afterFrd: afterFrdPoints,
      afterMeasurementRef: afterMeasurementRef,
      afterMeasurementFileName: afterMeasurementFileName,
      deployAckRef: deployAckRef,
    );

    final result = CorrectionCycleEvaluator.evaluate(
      evalInput,
      CorrectionCyclePolicy.proProvisional(),
    );

    final cycle = CorrectionCycle(
      projectId: projectId,
      channelId: channelId,
      cycleNumber: cycleNumber,
      beforeMeasurementRef: beforeMeasurementRef,
      peqSnapshot: peqSnapshot,
      deployAckRef: deployAckRef,
      createdAt: DateTime.now(),
    ).withAfterResult(
      afterMeasurementRef: afterMeasurementRef,
      afterMeasurementFileName: afterMeasurementFileName,
      metrics: result.metrics ??
          const CorrectionCycleMetrics(
            commonFreqMinHz: 0,
            commonFreqMaxHz: 0,
            commonPointCount: 0,
            meanAbsResidualBefore: 0,
            meanAbsResidualAfter: 0,
            improvementDelta: 0,
            peakErrorBefore: 0,
            peakErrorBeforeHz: 0,
            peakErrorAfter: 0,
            peakErrorAfterHz: 0,
            worsenedBandCount: 0,
            improvementCoverage: 0,
          ),
      decision: result.decision,
      reasons: result.reasons,
    );

    state = ProGuidedAiCompleted(
      outcome: current.outcome,
      explanation: current.explanation,
      loopVerdict: current.loopVerdict,
      applyResult: current.applyResult,
      beforeMeasurementRef: current.beforeMeasurementRef,
      loopPhase: ProClosedLoopPhase.cycleComplete,
      completedCycle: cycle,
    );
    return cycle;
  }

  void reset() {
    _orchestrator = null;
    _sessionStore = null;
    _sessionProjectId = null;
    state = const ProGuidedAiIdle();
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  static ImprovementVerdict? _extractVerdict(
    String projectId,
    ProToolArtifactStore store,
    String? loopRef,
  ) {
    if (loopRef == null || !store.has(projectId, loopRef)) return null;
    try {
      return store
          .getTyped<ClosedLoopResultArtifact>(projectId, loopRef)
          .value
          .verdict;
    } catch (_) {
      return null;
    }
  }

  /// Reads the CandidateSafetyArtifact at [safetyRef] and calls
  /// AcousticApplyEngine on the matching PEQ channel.
  ///
  /// When [analyzedChannelId] is provided, the PEQ channel whose [channelId]
  /// matches is used. If no match is found, returns null — no fallback to the
  /// first channel, because applying to the wrong channel is a silent
  /// data-integrity error in multi-channel projects.
  ///
  /// Returns null when the artifact is missing, safety is blocked, or the
  /// target channel cannot be resolved.
  static TuningApplyResult? _runApply(
    String projectId,
    ProToolArtifactStore store,
    String safetyRef,
    ProProject project, {
    String? analyzedChannelId,
  }) {
    if (!store.has(projectId, safetyRef)) return null;
    CandidateSafetyResult safety;
    try {
      safety =
          store.getTyped<CandidateSafetyArtifact>(projectId, safetyRef).value;
    } catch (_) {
      return null;
    }
    if (!safety.applyPermitted) return null;
    final PeqChannelState? channel;
    if (analyzedChannelId != null) {
      channel = project.tuningState.peqChannels
          .where((ch) => ch.channelId == analyzedChannelId)
          .firstOrNull;
    } else {
      channel = project.tuningState.peqChannels.firstOrNull;
    }
    if (channel == null) return null;
    return AcousticApplyEngine.apply(safety, channel);
  }
}
