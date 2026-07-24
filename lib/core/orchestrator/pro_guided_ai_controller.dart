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

import '../acoustic/closed_loop_evaluator.dart';
import '../pro_project.dart';
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
import 'tools/adapters/measurement_analyze_adapter.dart';
import 'tools/adapters/simulate_adapter.dart';
import 'tools/pro_project_resolver.dart';
import 'tools/pro_tool_artifact_store.dart';
import 'tools/pro_tool_registry.dart';

final guidedAiProvider =
    StateNotifierProvider.autoDispose<ProGuidedAiController, ProGuidedAiState>(
  (ref) => ProGuidedAiController(),
);

class ProGuidedAiController extends StateNotifier<ProGuidedAiState> {
  final ProOrchestrateService _cloudService;

  // Null → production adapters; non-null → test stub adapters.
  final List<ProToolAdapter>? _adapterOverrides;

  ProLocalOrchestrator? _orchestrator;

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
          const MeasurementAnalyzeAdapter(),
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
          state = ProGuidedAiCompleted(
            outcome: outcome,
            explanation: explanation,
            loopVerdict: _extractVerdict(pid, store, outcome.loopResultRef),
          );
        case ProPlanFailed(:final outcome):
          state = ProGuidedAiFailed(outcome.terminationReason ?? '실행 실패');
        case ProPlanRejected(:final outcome):
          state = ProGuidedAiFailed(outcome.terminationReason ?? '사용자 취소');
      }
    }
  }

  void confirm(String stepId) => _orchestrator?.confirm(stepId);
  void cancel(String stepId) => _orchestrator?.cancel(stepId);

  void reset() {
    _orchestrator = null;
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
}

