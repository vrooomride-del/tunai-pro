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
import '../acoustic/closed_loop_evaluator.dart';
import '../pro_project.dart';
import '../spectrum_snapshot.dart';
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
    // Called after acousticValidateSafety completes to persist the apply result.
    // Null → apply step is skipped (tests, offline mode).
    Future<void> Function(String projectId, TuningApplyResult)? onApply,
  }) async {
    if (state is! ProGuidedAiIdle) return;
    state = const ProGuidedAiCloudCalling();

    final pid = project.id;

    final measRefs = [
      for (final ch in project.acousticState.driverChannels) ch.id,
    ];

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
            applyResult = _runApply(pid, store, record.outputRef, project);
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
          state = ProGuidedAiConfirmPending(
            request: request,
            plan: plan,
            explanation: explanation,
            completedSteps: List.unmodifiable(completedSteps),
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
  /// AcousticApplyEngine on the project's first available PEQ channel.
  /// Returns null when the artifact is missing, safety is blocked, or there is
  /// no PEQ channel configured in the project.
  static TuningApplyResult? _runApply(
    String projectId,
    ProToolArtifactStore store,
    String safetyRef,
    ProProject project,
  ) {
    if (!store.has(projectId, safetyRef)) return null;
    CandidateSafetyResult safety;
    try {
      safety =
          store.getTyped<CandidateSafetyArtifact>(projectId, safetyRef).value;
    } catch (_) {
      return null;
    }
    if (!safety.applyPermitted) return null;
    final channel = project.tuningState.peqChannels.firstOrNull;
    if (channel == null) return null;
    return AcousticApplyEngine.apply(safety, channel);
  }
}
