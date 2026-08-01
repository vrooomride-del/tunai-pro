// TRUST BOUNDARY. No DSP value, no hardware command.
//
// Drives a complete guided-AI session:
//   1. Accepts a user goal + project snapshot.
//   2. Calls ProOrchestrateService (Cloud) → ProOrchestrateResponse.
//   3. Runs ProLocalOrchestrator (stream) → lifecycle events.
//   4. Pauses at requiresUserConfirmation gates; caller calls confirm/cancel.
//   5. After acousticValidateSafety completes with applyPermitted + selected
//      candidates, emits ProGuidedAiConfirmPending (controller-level gate)
//      and awaits user confirmation before calling _runApply.
//   6. After ProPlanCompleted, extracts ImprovementVerdict if the loop ran.
//
// [adapterOverrides] is intentionally public for test injection: pass stub
// adapters to avoid touching the real Acoustic Engine in unit tests.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../acoustic/acoustic_apply_engine.dart';
import '../acoustic/full_system_candidate_evaluator.dart';
import '../acoustic/candidate_safety.dart';
import '../acoustic/measurement_confidence.dart' show ConfidenceStatus;
import '../deploy/pro_hardware_capability.dart';
import '../deploy/pro_hardware_write_plan.dart';
import '../frd_parser.dart';
import '../pro_correction_cycle.dart';
import '../pro_tuning_report_data.dart' show GuidedTuningSessionSummary;
import '../pro_tuning_data.dart';
import '../acoustic/closed_loop_evaluator.dart';
import '../pro_project.dart';
import '../pro_export_data.dart';
import '../spectrum_snapshot.dart';
import 'correction_cycle_evaluator.dart';
import 'pro_acoustic_intent.dart';
import 'pro_guided_ai_state.dart';
import 'pro_local_orchestrator.dart';
import 'pro_local_orchestrator_session.dart';
import 'pro_explanation.dart';
import 'pro_orchestrate_request.dart';
import 'pro_orchestrate_service.dart';
import 'pro_orchestrator_context.dart';
import 'pro_orchestrator_plan.dart';
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
  static const List<String> requiredFullSystemChannelIds = [
    'ch_tw_l',
    'ch_wf_l',
    'ch_tw_r',
    'ch_wf_r',
  ];

  final ProOrchestrateService _cloudService;

  // Null → production adapters; non-null → test stub adapters.
  final List<ProToolAdapter>? _adapterOverrides;

  ProLocalOrchestrator? _orchestrator;

  // Preserved after a session completes so submitAfterMeasurement can
  // retrieve the before-measurement artifact for closed-loop comparison.
  ProToolArtifactStore? _sessionStore;
  String? _sessionProjectId;

  // Controller-level apply gate: completes true (confirm) or false (cancel).
  // Non-null only while waiting for user confirmation after safety validation.
  Completer<bool>? _applyGateCompleter;
  String? _applyGateStepId;

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
    Future<void> Function(String projectId, HardwareWritePlan plan)?
        onHardwareWritePlan,
    Future<void> Function(String projectId, DspExportPackage package)?
        onExportPackage,
  }) async {
    if (state is! ProGuidedAiIdle) return;
    state = const ProGuidedAiCloudCalling();

    final pid = project.id;

    // Cloud request includes all channel IDs for full context.
    final cloudMeasRefs = targetChannelId != null
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
        measurementRefs: cloudMeasRefs,
      ),
    );

    final cloudOutcome = await _cloudService.call(request);

    final ProOrchestratorPlan plan;
    final ProExplanation explanation;
    // Local project truth only: Cloud responses cannot make Full Apply ready.
    final frdReadyChannelIds = _frdReadyRequiredChannelIds(project);

    if (frdReadyChannelIds.isEmpty) {
      if (cloudOutcome is ProOrchestrateFailure) {
        state = const ProGuidedAiFailed('분석할 채널이 없습니다.');
        return;
      }
      // Cloud success with no local FRD: run the cloud plan as-is (edge case).
      final response = (cloudOutcome as ProOrchestrateSuccess).response;
      plan = response.plan;
      explanation = response.explanation;
    } else {
      // FRD data available: always run the local deterministic 4-channel plan.
      // Cloud explanation is kept when Cloud succeeded; local text otherwise.
      plan = _buildLocalFallbackPlan(pid, frdReadyChannelIds);
      explanation = cloudOutcome is ProOrchestrateSuccess
          ? cloudOutcome.response.explanation
          : _localFallbackExplanation;
    }

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
    HardwareWritePlan? hardwareWritePlan;

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
          if (record.toolId == ProOrchestratorToolId.acousticValidateSafety) {
            // Fire the apply gate only after ALL safety steps in the plan have
            // completed (multi-channel plans have one safety step per channel).
            final totalSafetySteps = plan.steps
                .where((s) =>
                    s.toolId == ProOrchestratorToolId.acousticValidateSafety)
                .length;
            final completedSafetySteps = completedSteps
                .where((r) =>
                    r.toolId == ProOrchestratorToolId.acousticValidateSafety)
                .length;

            if (completedSafetySteps == totalSafetySteps) {
              // Identify the primary analyzed channel (first measurementAnalyze).
              final analyzedChannelId = plan.steps
                  .where((s) =>
                      s.toolId == ProOrchestratorToolId.measurementAnalyze)
                  .firstOrNull
                  ?.inputRefs
                  .firstOrNull;
              final anyPermitted =
                  _anyChannelSafetyPermitted(pid, store, completedSteps);
              final hasSelected =
                  _anyChannelHasSelected(pid, store, completedSteps);
              // fullSystemReady is always computed here so both the gate path
              // and the legacy path share the same 4-channel condition.
              final missingChannelIds = _missingFullSystemChannelIds(
                project,
                completedSteps,
                plan,
              );
              final fullSystemReady = missingChannelIds.isEmpty;
              if (anyPermitted &&
                  hasSelected &&
                  (onApply != null || onHardwareWritePlan != null)) {
                // At least one channel has approved candidates — show the
                // review gate. Full Apply remains blocked until all 4 required
                // channels have local FRD evidence and completed safety output.
                _applyGateStepId = 'apply_gate_${record.outputRef}';
                _applyGateCompleter = Completer<bool>();
                state = _buildApplyGatePending(
                  pid: pid,
                  store: store,
                  plan: plan,
                  explanation: explanation,
                  completedSteps: completedSteps,
                  project: project,
                  analyzedChannelId: analyzedChannelId,
                  safetyRef: record.outputRef,
                  fullSystemReady: fullSystemReady,
                  missingChannelIds: missingChannelIds,
                );
                final confirmed = await _applyGateCompleter!.future;
                _applyGateCompleter = null;
                _applyGateStepId = null;
                if (confirmed && fullSystemReady) {
                  final multiResults = _runMultiChannelApply(
                      pid, store, completedSteps, plan, project);
                  final fullResults = _validatedFullSystemResults(multiResults);
                  if (fullResults != null) {
                    for (final r in fullResults) {
                      if (onApply != null) await onApply(pid, r);
                      applyResult ??= r;
                    }
                    final buildResult =
                        _buildFullSystemHardwareWritePlan(pid, fullResults);
                    if (buildResult != null) {
                      final (exportPkg, writePlan) = buildResult;
                      hardwareWritePlan = writePlan;
                      if (onExportPackage != null) {
                        await onExportPackage(pid, exportPkg);
                      }
                      if (onHardwareWritePlan != null) {
                        await onHardwareWritePlan(pid, writePlan);
                      }
                    }
                  }
                }
              } else if (onApply != null && anyPermitted && fullSystemReady) {
                // Safety passed without optimizer candidates — legacy auto-apply.
                // Gated behind fullSystemReady: single/partial-channel sessions
                // must not bypass the 4-channel completeness requirement.
                applyResult = _runApply(pid, store, record.outputRef, project,
                    analyzedChannelId: analyzedChannelId);
                if (applyResult != null) {
                  await onApply(pid, applyResult);
                }
              }
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
              .where(
                  (s) => s.toolId == ProOrchestratorToolId.measurementAnalyze)
              .firstOrNull
              ?.inputRefs
              .firstOrNull;

          // Available PEQ slots for the target channel.
          final targetChannel = analyzedChannelId != null
              ? project.tuningState.peqChannels
                  .where((ch) => ch.channelId == analyzedChannelId)
                  .firstOrNull
              : null;
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
                final sorted = [...opt.value.selected]..sort(
                    (a, b) => a.applicationOrder.compareTo(b.applicationOrder));
                for (final sel in sorted) {
                  final norm = simCh.normalized();
                  final idx = norm.bands.indexWhere((b) => !b.enabled);
                  slotMap[sel.applicationOrder] = idx >= 0 ? idx + 1 : null;
                  if (idx >= 0) {
                    simCh = simCh.fillNextFreeSlot(
                      type: PeqBandType.peak,
                      frequencyHz: sel.scoredCandidate.candidate.frequencyHz,
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
          final blockedReason = applyResult == null
              ? _extractBlockedReason(pid, store, completedSteps)
              : null;
          final guidedSession = applyResult != null
              ? _buildGuidedTuningSession(
                  pid, store, completedSteps, applyResult)
              : null;
          state = ProGuidedAiCompleted(
            outcome: outcome,
            explanation: explanation,
            loopVerdict: loopVerdict,
            applyResult: applyResult,
            applyBlockedReason: blockedReason,
            beforeMeasurementRef: beforeRef,
            loopPhase: loopPhase,
            hardwareWritePlan: hardwareWritePlan,
            guidedTuningSession: guidedSession,
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

  void confirm(String stepId) {
    final completer = _applyGateCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(true);
      return;
    }
    _orchestrator?.confirm(stepId);
  }

  void cancel(String stepId) {
    final completer = _applyGateCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
      return;
    }
    _orchestrator?.cancel(stepId);
  }

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
      hardwareWritePlan: current.hardwareWritePlan,
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
      hardwareWritePlan: current.hardwareWritePlan,
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
      hardwareWritePlan: current.hardwareWritePlan,
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
      hardwareWritePlan: current.hardwareWritePlan,
    );
    return cycle;
  }

  void reset() {
    final completer = _applyGateCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    _applyGateCompleter = null;
    _applyGateStepId = null;
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

  // ── Apply-gate helpers ───────────────────────────────────────────────────────

  static bool _isSafetyPermitted(
    String projectId,
    ProToolArtifactStore store,
    String safetyRef,
  ) {
    if (!store.has(projectId, safetyRef)) return false;
    try {
      return store
          .getTyped<CandidateSafetyArtifact>(projectId, safetyRef)
          .value
          .applyPermitted;
    } catch (_) {
      return false;
    }
  }

  /// True when at least one completed safety step has applyPermitted=true.
  static bool _anyChannelSafetyPermitted(
    String projectId,
    ProToolArtifactStore store,
    List<ProStepExecutionRecord> completedSteps,
  ) {
    return completedSteps
        .where((r) => r.toolId == ProOrchestratorToolId.acousticValidateSafety)
        .any((r) => _isSafetyPermitted(projectId, store, r.outputRef));
  }

  /// True when at least one completed optimize step has non-empty selected list.
  static bool _anyChannelHasSelected(
    String projectId,
    ProToolArtifactStore store,
    List<ProStepExecutionRecord> completedSteps,
  ) {
    for (final r in completedSteps.where(
        (r) => r.toolId == ProOrchestratorToolId.acousticOptimizeSelection)) {
      if (!store.has(projectId, r.outputRef)) continue;
      try {
        if (store
            .getTyped<OptimizedSelectionArtifact>(projectId, r.outputRef)
            .value
            .selected
            .isNotEmpty) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  static List<String> _frdReadyRequiredChannelIds(ProProject project) {
    final ready = <String>[];
    for (final id in requiredFullSystemChannelIds) {
      final channel = project.acousticState.driverChannels
          .where((ch) => ch.id == id)
          .firstOrNull;
      if (channel?.hasParsedFrd == true) ready.add(id);
    }
    return List.unmodifiable(ready);
  }

  static Set<String> _completedSafetyChannelIds(
    List<ProStepExecutionRecord> completedSteps,
    ProOrchestratorPlan plan,
  ) {
    final ids = <String>{};
    for (final record in completedSteps.where(
        (r) => r.toolId == ProOrchestratorToolId.acousticValidateSafety)) {
      final channelId = _resolveChannelForSafetyRef(record.outputRef, plan);
      if (channelId != null &&
          requiredFullSystemChannelIds.contains(channelId)) {
        ids.add(channelId);
      }
    }
    return ids;
  }

  static List<String> _missingFullSystemChannelIds(
    ProProject project,
    List<ProStepExecutionRecord> completedSteps,
    ProOrchestratorPlan plan,
  ) {
    final frdReady = _frdReadyRequiredChannelIds(project).toSet();
    final safetyReady = _completedSafetyChannelIds(completedSteps, plan);
    return [
      for (final id in requiredFullSystemChannelIds)
        if (!frdReady.contains(id) || !safetyReady.contains(id)) id,
    ];
  }

  static List<TuningApplyResult>? _validatedFullSystemResults(
    List<TuningApplyResult> results,
  ) {
    final byChannel = <String, TuningApplyResult>{};
    for (final result in results) {
      if (!requiredFullSystemChannelIds.contains(result.channelId)) continue;
      byChannel[result.channelId] = result;
    }
    if (!requiredFullSystemChannelIds.every(byChannel.containsKey)) {
      return null;
    }
    return [
      for (final id in requiredFullSystemChannelIds) byChannel[id]!,
    ];
  }

  // Returns (exportPackage, writePlan) so callers can store the package in
  // project export state for the Deploy tab's HardwareApplyFlow.
  static (DspExportPackage, HardwareWritePlan)?
      _buildFullSystemHardwareWritePlan(
    String projectId,
    List<TuningApplyResult> results,
  ) {
    final fullResults = _validatedFullSystemResults(results);
    if (fullResults == null) return null;

    final blocks = <ExportParameterBlock>[];
    for (final result in fullResults) {
      final bands = <String, dynamic>{};
      final normalized = result.updatedChannel.normalized();
      for (var i = 0; i < normalized.bands.length; i++) {
        final band = normalized.bands[i];
        if (!band.enabled) continue;
        bands['band_$i'] = {
          'freq_hz': band.frequencyHz,
          'gain_db': band.gainDb,
          'q': band.q,
          'type': band.type.name,
        };
      }
      if (bands.isEmpty) continue;
      blocks.add(ExportParameterBlock(
        id: 'guided-${result.channelId}-peq',
        type: ExportBlockType.peq,
        channelId: result.channelId,
        title: 'Guided Tuning PEQ ${result.channelId}',
        summary: 'Guided tuning verified PEQ changes',
        parameters: {'bands': bands},
      ));
    }

    if (blocks.isEmpty) return null;
    final package = DspExportPackage(
      id: 'guided-full-system-$projectId',
      targetPlatform: DspTargetPlatform.adau1701,
      format: ExportFormat.hardwareWritePlanPlaceholder,
      status: ExportStatus.draftReady,
      projectName: projectId,
      parameterBlocks: blocks,
      notes: 'Generated from confirmed 4-channel Guided Tuning results.',
    );
    return (
      package,
      buildHardwareWritePlan(package, HardwareDeviceProfiles.adau1701Icp5)
    );
  }

  /// Applies all completed safety artifacts to their respective PEQ channels
  /// and returns one [TuningApplyResult] per channel that was applied.
  static List<TuningApplyResult> _runMultiChannelApply(
    String projectId,
    ProToolArtifactStore store,
    List<ProStepExecutionRecord> completedSteps,
    ProOrchestratorPlan plan,
    ProProject project,
  ) {
    final safetyByChannel = <String, CandidateSafetyResult>{};
    final safetyRefByChannel = <String, String>{};
    for (final record in completedSteps.where(
        (r) => r.toolId == ProOrchestratorToolId.acousticValidateSafety)) {
      final channelId = _resolveChannelForSafetyRef(record.outputRef, plan);
      if (channelId == null || !store.has(projectId, record.outputRef))
        continue;
      try {
        final safety = store
            .getTyped<CandidateSafetyArtifact>(projectId, record.outputRef)
            .value;
        if (safety.applyPermitted) {
          safetyByChannel[channelId] = safety;
          safetyRefByChannel[channelId] = record.outputRef;
        }
      } catch (_) {}
    }
    final joint = FullSystemCandidateEvaluator.evaluate(
      project: project,
      safetyByChannel: safetyByChannel,
    );
    if (!joint.accepted) return const [];

    final results = <TuningApplyResult>[];
    for (final channelId in requiredFullSystemChannelIds) {
      final safety = safetyByChannel[channelId];
      final safetyRef = safetyRefByChannel[channelId];
      if (safety == null || safetyRef == null) continue;
      final selected = joint.selectedByChannel[channelId] ?? const [];
      if (selected.isEmpty) continue;
      final filteredSafety = CandidateSafetyResult(
        applyPermitted: true,
        issues: safety.issues,
        verifiedCandidates: selected,
        policyId: safety.policyId,
        policyVersion: safety.policyVersion,
        evidenceRefs: safety.evidenceRefs,
      );
      final result = _runApply(
        projectId,
        store,
        safetyRef,
        project,
        analyzedChannelId: channelId,
        safetyOverride: filteredSafety,
      );
      if (result != null) results.add(result);
    }
    return results;
  }

  /// Traces the plan's dependency chain backwards from a safety outputRef to
  /// find the channel ID used in the scoring step's inputRefs[2].
  /// Returns null when the chain cannot be resolved (e.g. cloud plans).
  static String? _resolveChannelForSafetyRef(
      String safetyRef, ProOrchestratorPlan plan) {
    final safetyStep =
        plan.steps.where((s) => s.outputRef == safetyRef).firstOrNull;
    if (safetyStep == null || safetyStep.inputRefs.isEmpty) return null;
    // Fast path: local plan convention — safety→opt→score→inputRefs[2]=channel.
    final viaOpt = _resolveChannelForOptRef(safetyStep.inputRefs.first, plan);
    if (viaOpt != null) return viaOpt;
    // Fallback for cloud plans: BFS backward through the dependency graph until
    // a required channel ID is found as a leaf input ref.
    return _resolveChannelByGraphBfs(safetyRef, plan);
  }

  /// BFS backward from [startOutputRef] through plan step inputRefs until a
  /// ref that equals one of [requiredFullSystemChannelIds] is encountered.
  /// Returns null when no required channel ID is reachable.
  static String? _resolveChannelByGraphBfs(
      String startOutputRef, ProOrchestratorPlan plan) {
    final stepByOutput = {for (final s in plan.steps) s.outputRef: s};
    final startStep = stepByOutput[startOutputRef];
    if (startStep == null) return null;
    final visited = <String>{startOutputRef};
    final queue = [...startStep.inputRefs];
    while (queue.isNotEmpty) {
      final ref = queue.removeLast();
      if (visited.contains(ref)) continue;
      visited.add(ref);
      if (requiredFullSystemChannelIds.contains(ref)) return ref;
      final step = stepByOutput[ref];
      if (step != null) queue.addAll(step.inputRefs);
    }
    return null;
  }

  /// Traces: optimizedRef → scoreStep.inputRefs[2] = channelRef.
  static String? _resolveChannelForOptRef(
      String optimizedRef, ProOrchestratorPlan plan) {
    final optimizeStep =
        plan.steps.where((s) => s.outputRef == optimizedRef).firstOrNull;
    if (optimizeStep == null || optimizeStep.inputRefs.isEmpty) return null;
    final scoredRef = optimizeStep.inputRefs.first;
    final scoreStep =
        plan.steps.where((s) => s.outputRef == scoredRef).firstOrNull;
    if (scoreStep == null || scoreStep.inputRefs.length < 3) return null;
    return scoreStep.inputRefs[2];
  }

  static String? _extractBlockedReason(
    String projectId,
    ProToolArtifactStore store,
    List<ProStepExecutionRecord> completedSteps,
  ) {
    final safetyRef = completedSteps
        .where((r) => r.toolId == ProOrchestratorToolId.acousticValidateSafety)
        .firstOrNull
        ?.outputRef;
    if (safetyRef == null || !store.has(projectId, safetyRef)) return null;
    try {
      final safety =
          store.getTyped<CandidateSafetyArtifact>(projectId, safetyRef).value;
      if (safety.applyPermitted) return null;
      if (safety.issues.isEmpty) return '안전 검사 미통과';
      return safety.issues.map((i) => i.detail).join('; ');
    } catch (_) {
      return null;
    }
  }

  ProGuidedAiConfirmPending _buildApplyGatePending({
    required String pid,
    required ProToolArtifactStore store,
    required ProOrchestratorPlan plan,
    required ProExplanation explanation,
    required List<ProStepExecutionRecord> completedSteps,
    required ProProject project,
    required String? analyzedChannelId,
    required String safetyRef,
    required bool fullSystemReady,
    required List<String> missingChannelIds,
  }) {
    List<CandidatePreviewEntry>? preview;
    String? applyBlockedReason;

    // Block apply when local evidence cannot prove the full 4-channel system.
    if (!fullSystemReady) {
      final missing = missingChannelIds.isEmpty
          ? requiredFullSystemChannelIds.join(', ')
          : missingChannelIds.join(', ');
      applyBlockedReason = 'Full Tuning Apply 차단: 4채널 분석/안전 확인이 모두 필요합니다. '
          '누락: $missing.';
    }

    // Collect per-channel preview entries from all optimize artifacts.
    final allOptRecords = completedSteps
        .where(
            (r) => r.toolId == ProOrchestratorToolId.acousticOptimizeSelection)
        .toList();

    final previewEntries = <CandidatePreviewEntry>[];
    for (final optRecord in allOptRecords) {
      final optRef = optRecord.outputRef;
      if (!store.has(pid, optRef)) continue;
      try {
        final opt = store.getTyped<OptimizedSelectionArtifact>(pid, optRef);
        // Resolve channel for this optimize step by tracing plan dependencies.
        final channelLabel =
            _resolveChannelForOptRef(optRef, plan) ?? analyzedChannelId ?? '';
        final targetChannel = channelLabel.isNotEmpty
            ? (project.tuningState.peqChannels
                    .where((ch) => ch.channelId == channelLabel)
                    .firstOrNull ??
                PeqChannelState.fixed(channelLabel))
            : project.tuningState.peqChannels.firstOrNull;
        final availableSlots = targetChannel?.normalized().bands.length;
        final needed = opt.value.selected.length;
        if (applyBlockedReason == null &&
            availableSlots != null &&
            needed > availableSlots) {
          applyBlockedReason =
              '슬롯 부족: $needed개 필요, 채널 ${channelLabel.isNotEmpty ? channelLabel : "—"}에 $availableSlots개 가능';
        }
        final slotMap = <int, int?>{};
        if (targetChannel != null) {
          var simCh = targetChannel;
          final sorted = [...opt.value.selected]
            ..sort((a, b) => a.applicationOrder.compareTo(b.applicationOrder));
          for (final sel in sorted) {
            final norm = simCh.normalized();
            final idx = norm.bands.indexWhere((b) => !b.enabled);
            slotMap[sel.applicationOrder] = idx >= 0 ? idx + 1 : null;
            if (idx >= 0) {
              simCh = simCh.fillNextFreeSlot(
                type: PeqBandType.peak,
                frequencyHz: sel.scoredCandidate.candidate.frequencyHz,
                gainDb: sel.scoredCandidate.candidate.gainDb,
                q: sel.scoredCandidate.candidate.q,
              );
            }
          }
        }
        for (final c in opt.value.selected) {
          previewEntries.add(CandidatePreviewEntry(
            applicationOrder: c.applicationOrder,
            frequencyHz: c.scoredCandidate.candidate.frequencyHz,
            gainDb: c.scoredCandidate.candidate.gainDb,
            q: c.scoredCandidate.candidate.q,
            grade: c.scoredCandidate.grade.name,
            channelId: channelLabel,
            safetyVerified: false,
            targetPeqSlot: slotMap[c.applicationOrder],
          ));
        }
      } catch (_) {}
    }
    if (previewEntries.isNotEmpty) preview = previewEntries;

    // insufficientEvidence: any channel with single-sweep measurement.
    bool insufficientEvidence = false;
    for (final mRecord in completedSteps
        .where((r) => r.toolId == ProOrchestratorToolId.measurementAnalyze)) {
      if (!store.has(pid, mRecord.outputRef)) continue;
      try {
        final mArt =
            store.getTyped<MeasurementArtifact>(pid, mRecord.outputRef);
        if (mArt.confidence?.status == ConfidenceStatus.insufficientEvidence) {
          insufficientEvidence = true;
          break;
        }
      } catch (_) {}
    }

    // Before/After summary: aggregate best improvement across all channels.
    String? beforeAfterSummary;
    double bestImprovement = 0.0;
    String? bestSummary;
    for (final scoreRecord in completedSteps.where(
        (r) => r.toolId == ProOrchestratorToolId.acousticScoreCandidates)) {
      final simErrRef = '${scoreRecord.outputRef}:sim_err';
      if (!store.has(pid, simErrRef)) continue;
      try {
        final simErr = store.getTyped<SimulationErrorArtifact>(pid, simErrRef);
        final bestAfterRms = simErr.perCandidateErrors.values
            .map((e) => e.weightedRmsDb)
            .fold<double>(double.infinity, (a, b) => b < a ? b : a);
        if (bestAfterRms != double.infinity) {
          final improvement = simErr.beforeError.weightedRmsDb - bestAfterRms;
          if (improvement > bestImprovement) {
            bestImprovement = improvement;
            final before = simErr.beforeError.weightedRmsDb.toStringAsFixed(1);
            final after = bestAfterRms.toStringAsFixed(1);
            final modeLabel = simErr.simulationMode == 'phase-aware'
                ? ', phase-aware'
                : ', magnitude-only';
            bestSummary =
                'Before $before dB → After $after dB (가중 RMS$modeLabel)';
          }
        }
      } catch (_) {}
    }
    beforeAfterSummary = bestSummary;

    return ProGuidedAiConfirmPending(
      request: ProUserConfirmationRequest(
        stepId: _applyGateStepId!,
        toolId: ProOrchestratorToolId.acousticValidateSafety,
        objective: '분석된 후보 적용',
        explanation: explanation,
      ),
      plan: plan,
      explanation: explanation,
      completedSteps: List.unmodifiable(completedSteps),
      candidatePreview: preview,
      applyBlockedReason: applyBlockedReason,
      targetChannelId: analyzedChannelId,
      beforeAfterSummary: beforeAfterSummary,
      fullSystemReady: fullSystemReady,
      missingChannelIds: List.unmodifiable(missingChannelIds),
      insufficientEvidence: insufficientEvidence,
    );
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
    CandidateSafetyResult? safetyOverride,
  }) {
    if (!store.has(projectId, safetyRef)) return null;
    CandidateSafetyResult safety;
    try {
      safety = safetyOverride ??
          store.getTyped<CandidateSafetyArtifact>(projectId, safetyRef).value;
    } catch (_) {
      return null;
    }
    if (!safety.applyPermitted) return null;
    if (analyzedChannelId == null) return null;
    final channel = project.tuningState.peqChannels
            .where((ch) => ch.channelId == analyzedChannelId)
            .firstOrNull ??
        PeqChannelState.fixed(analyzedChannelId);
    return AcousticApplyEngine.apply(safety, channel);
  }

  // ── Guided tuning session summary builder ─────────────────────────────────────

  /// Builds a [GuidedTuningSessionSummary] from the artifact store after a
  /// successful apply. All data is read from the store; no DSP values cross.
  static GuidedTuningSessionSummary _buildGuidedTuningSession(
    String pid,
    ProToolArtifactStore store,
    List<ProStepExecutionRecord> completedSteps,
    TuningApplyResult applyResult,
  ) {
    // Measurement basis from the measurement analyze artifact.
    String? measurementBasis;
    final mRef = completedSteps
        .where((r) => r.toolId == ProOrchestratorToolId.measurementAnalyze)
        .firstOrNull
        ?.outputRef;
    if (mRef != null && store.has(pid, mRef)) {
      try {
        final mArt = store.getTyped<MeasurementArtifact>(pid, mRef);
        final conf = mArt.confidence;
        measurementBasis = conf == null
            ? 'FRD'
            : conf.status == ConfidenceStatus.insufficientEvidence
                ? 'FRD (신뢰도 부족)'
                : conf.status == ConfidenceStatus.valid
                    ? 'FRD (유효)'
                    : 'FRD (무효)';
      } catch (_) {}
    }

    // Candidates from the optimizer artifact.
    int selectedCount = 0;
    String? bestLabel;
    final altLabels = <String>[];
    final optRef = completedSteps
        .where(
            (r) => r.toolId == ProOrchestratorToolId.acousticOptimizeSelection)
        .firstOrNull
        ?.outputRef;
    if (optRef != null && store.has(pid, optRef)) {
      try {
        final opt = store.getTyped<OptimizedSelectionArtifact>(pid, optRef);
        final sorted = [...opt.value.selected]
          ..sort((a, b) => a.applicationOrder.compareTo(b.applicationOrder));
        selectedCount = sorted.length;
        for (final sel in sorted) {
          final c = sel.scoredCandidate.candidate;
          final label =
              '${sel.scoredCandidate.grade.name} ${c.frequencyHz.round()} Hz '
              '${c.gainDb >= 0 ? "+" : ""}${c.gainDb.toStringAsFixed(1)} dB '
              'Q:${c.q.toStringAsFixed(2)}';
          if (sel.applicationOrder == 1) {
            bestLabel = label;
          } else {
            altLabels.add(label);
          }
        }
      } catch (_) {}
    }

    // Before/After + simulation mode from the scoring side-channel artifact.
    String? simSummary;
    String? simMode;
    final scoreRef = completedSteps
        .where((r) => r.toolId == ProOrchestratorToolId.acousticScoreCandidates)
        .firstOrNull
        ?.outputRef;
    if (scoreRef != null && store.has(pid, '$scoreRef:sim_err')) {
      try {
        final simErr =
            store.getTyped<SimulationErrorArtifact>(pid, '$scoreRef:sim_err');
        final bestAfterRms = simErr.perCandidateErrors.values
            .map((e) => e.weightedRmsDb)
            .fold<double>(double.infinity, (a, b) => b < a ? b : a);
        if (bestAfterRms != double.infinity) {
          final before = simErr.beforeError.weightedRmsDb.toStringAsFixed(1);
          final after = bestAfterRms.toStringAsFixed(1);
          final modeLabel = simErr.simulationMode == 'phase-aware'
              ? ', phase-aware'
              : ', magnitude-only';
          simSummary = 'Before $before dB → After $after dB (가중 RMS$modeLabel)';
        }
        simMode = simErr.simulationMode;
      } catch (_) {}
    }

    // Safety status from the safety artifact.
    String safetyLabel = '미확인';
    final safetyRef = completedSteps
        .where((r) => r.toolId == ProOrchestratorToolId.acousticValidateSafety)
        .firstOrNull
        ?.outputRef;
    if (safetyRef != null && store.has(pid, safetyRef)) {
      try {
        final safety =
            store.getTyped<CandidateSafetyArtifact>(pid, safetyRef).value;
        safetyLabel = safety.applyPermitted ? '통과' : '차단';
      } catch (_) {}
    }

    return GuidedTuningSessionSummary(
      measurementBasis: measurementBasis,
      selectedCandidateCount: selectedCount,
      bestCandidateLabel: bestLabel,
      alternativeLabels: List.unmodifiable(altLabels),
      beforeAfterSummary: simSummary,
      simulationMode: simMode,
      safetyStatusLabel: safetyLabel,
      applyStatusLabel: applyResult.status.name,
      generatedAt: DateTime.now(),
    );
  }

  // ── Local offline fallback ────────────────────────────────────────────────────

  static const ProExplanation _localFallbackExplanation = ProExplanation(
    title: '오프라인 분석',
    summary: 'Cloud 연결 없이 측정 데이터에서 직접 음향 최적화를 실행합니다.',
    explanationLevel: ProExplanationLevel.intermediate,
    warnings: ['Cloud AI 설명 없음 — 로컬 엔진 전용'],
  );

  /// Builds the deterministic acoustic pipeline plan used when Cloud is
  /// unavailable. Generates one 7-step chain per channel in [measRefs] so that
  /// all channels are analyzed and applied as a single atomic full-system plan.
  static ProOrchestratorPlan _buildLocalFallbackPlan(
    String projectId,
    List<String> measRefs,
  ) {
    final steps = <ProOrchestratorStep>[];
    for (final channelRef in measRefs) {
      // Use the channel ID as a step-name segment (safe: IDs are alphanumeric+_).
      final p = 'local-$channelRef';
      steps.addAll([
        ProOrchestratorStep(
          stepId: '$p-s1-measure',
          toolId: ProOrchestratorToolId.measurementAnalyze,
          objective: '측정 데이터 분석 ($channelRef)',
          inputRefs: [channelRef],
          outputRef: '$p-measure',
          requiresUserConfirmation: false,
        ),
        ProOrchestratorStep(
          stepId: '$p-s2-classify',
          toolId: ProOrchestratorToolId.acousticClassify,
          objective: '음향 문제 분류 ($channelRef)',
          inputRefs: ['$p-measure'],
          outputRef: '$p-classify',
          requiresUserConfirmation: false,
        ),
        ProOrchestratorStep(
          stepId: '$p-s3-plan',
          toolId: ProOrchestratorToolId.acousticPlan,
          objective: '수정 계획 수립 ($channelRef)',
          inputRefs: ['$p-classify'],
          outputRef: '$p-plan',
          requiresUserConfirmation: false,
        ),
        ProOrchestratorStep(
          stepId: '$p-s4-generate',
          toolId: ProOrchestratorToolId.acousticGenerateCandidates,
          objective: '보정 후보 생성 ($channelRef)',
          inputRefs: ['$p-plan', '$p-classify', channelRef],
          outputRef: '$p-candidates',
          requiresUserConfirmation: false,
        ),
        ProOrchestratorStep(
          stepId: '$p-s5-score',
          toolId: ProOrchestratorToolId.acousticScoreCandidates,
          objective: '후보 점수화 ($channelRef)',
          // inputRefs[2] = channelRef lets the scorer run phase-aware simulation
          // and enables _resolveChannelForSafetyRef to trace back to this channel.
          inputRefs: ['$p-candidates', '$p-classify', channelRef],
          outputRef: '$p-scored',
          requiresUserConfirmation: false,
        ),
        ProOrchestratorStep(
          stepId: '$p-s6-optimize',
          toolId: ProOrchestratorToolId.acousticOptimizeSelection,
          objective: '최적 후보 선정 ($channelRef)',
          inputRefs: ['$p-scored'],
          outputRef: '$p-optimized',
          requiresUserConfirmation: false,
        ),
        ProOrchestratorStep(
          stepId: '$p-s7-safety',
          toolId: ProOrchestratorToolId.acousticValidateSafety,
          objective: '안전 검증 ($channelRef)',
          inputRefs: ['$p-optimized'],
          outputRef: '$p-safety',
          requiresUserConfirmation: false,
        ),
      ]);
    }
    return ProOrchestratorPlan(
      planId: 'local-offline-$projectId',
      intentRef: 'local-intent',
      contextRef: 'local-offline',
      summary: '오프라인 전체 시스템 분석 플랜 (${measRefs.length}채널, Cloud 없음)',
      completionCriteria: 'acousticValidateSafety 완료 (전 채널)',
      steps: steps,
    );
  }
}
