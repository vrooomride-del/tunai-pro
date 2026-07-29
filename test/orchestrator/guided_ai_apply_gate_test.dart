// Confirmation gate tests for ProGuidedAiController.
//
// 5 scenarios:
//   1. Successful analysis → ProGuidedAiConfirmPending state
//   2. Candidate preview carries exactly 3 selected candidates
//   3. onApply is NOT called before user confirms
//   4. After confirm() → existing Apply path (onApply called once)
//   5. Blocked safety result → no confirmation, ProGuidedAiCompleted with reason

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/closed_loop_evaluator.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_state.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_response.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_service.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_result.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_response_error.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _pid = 'gate-test-project';
const _channelId = 'woofer-l';

// ── Helpers ───────────────────────────────────────────────────────────────────

class _CloudStub extends Interceptor {
  final Map<String, dynamic> data;
  _CloudStub(this.data);
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handler.resolve(
          Response(requestOptions: options, data: data, statusCode: 200));
}

Dio _dio(Map<String, dynamic> envelope) =>
    Dio()..interceptors.add(_CloudStub(envelope));

ProOrchestratorStep _step(
  String id,
  ProOrchestratorToolId toolId, {
  List<String> inputRefs = const [],
}) =>
    ProOrchestratorStep(
      stepId: id,
      toolId: toolId,
      objective: 'stub step $id',
      inputRefs: inputRefs,
      outputRef: 'out-$id',
      requiresUserConfirmation: false,
    );

/// Plan: measurementAnalyze → acousticOptimizeSelection → acousticValidateSafety
List<ProOrchestratorStep> _gatePlan() => [
      _step('analyze', ProOrchestratorToolId.measurementAnalyze,
          inputRefs: [_channelId]),
      _step('optimize', ProOrchestratorToolId.acousticOptimizeSelection),
      _step('safety', ProOrchestratorToolId.acousticValidateSafety),
    ];

ProOrchestrateResponse _cloudResponse(List<ProOrchestratorStep> steps) =>
    ProOrchestrateResponse(
      projectId: _pid,
      plan: ProOrchestratorPlan(
        planId: 'gate-plan',
        intentRef: 'intent-ref',
        contextRef: 'ctx-ref',
        steps: steps,
      ),
      explanation: const ProExplanation(
        title: '게이트 테스트',
        summary: '적용 게이트 확인',
        explanationLevel: ProExplanationLevel.intermediate,
      ),
    );

Map<String, dynamic> _envelope(ProOrchestrateResponse r) =>
    {'result': r.toJson()};

/// Project with a fixed 10-slot PEQ channel for [_channelId].
ProProject _projectWithChannel() => ProProject(
      id: _pid,
      name: 'Gate Test',
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
      tuningState: TuningProjectState(
        peqChannels: [PeqChannelState.fixed(_channelId)],
      ),
    );

// ── Candidate fixtures ────────────────────────────────────────────────────────

PeqCandidate _candidate(int n) => PeqCandidate(
      candidateId: 'candidate:feat-$n',
      featureId: 'feat-$n',
      featureType: AcousticFeatureType.narrowPeak,
      frequencyHz: 100.0 * n,
      gainDb: -3.0 * n,
      q: 2.0,
      intent: CorrectionIntent.cut,
      reason: 'stub candidate $n',
    );

ScoredCandidate _scored(int n) => ScoredCandidate(
      candidate: _candidate(n),
      prominenceDb: 6.0,
      prominenceScore: 30.0,
      magnitudeConsistencyScore: 25.0,
      qualityFactor: 1.0,
      compositeScore: 75.0,
      rank: n,
      grade: CandidateScoreGrade.good,
      reasons: const ['stub'],
    );

SelectedCandidate _selected(int n) => SelectedCandidate(
      scoredCandidate: _scored(n),
      applicationOrder: n,
      selectionReason: 'stub selection $n',
    );

List<SelectedCandidate> _threeSelected() =>
    [_selected(1), _selected(2), _selected(3)];

// ── Stub adapters ─────────────────────────────────────────────────────────────

/// Passes measurementAnalyze with a LoopSnapshotArtifact (required by registry).
class _PassAdapter implements ProToolAdapter {
  @override
  final ProOrchestratorToolId toolId;
  const _PassAdapter(this.toolId);

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    ctx.store.put(ctx.projectId, step.outputRef,
        LoopSnapshotArtifact(_snapshot()));
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'pass ok',
    );
  }
}

/// Writes OptimizedSelectionArtifact with 3 selected candidates.
class _OptAdapter implements ProToolAdapter {
  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticOptimizeSelection;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    ctx.store.put(
      ctx.projectId,
      step.outputRef,
      OptimizedSelectionArtifact(OptimizedSelection(
        status: OptimizationStatus.ok,
        selected: _threeSelected(),
        rejected: const [],
        reasons: const [],
        policyId: 'stub',
        policyVersion: 1,
        evidenceRefs: const [],
      )),
    );
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'opt ok',
    );
  }
}

/// Writes CandidateSafetyArtifact with applyPermitted=true and 3 verified.
class _SafetyAdapter implements ProToolAdapter {
  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticValidateSafety;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    ctx.store.put(
      ctx.projectId,
      step.outputRef,
      CandidateSafetyArtifact(CandidateSafetyResult(
        applyPermitted: true,
        issues: const [],
        verifiedCandidates: _threeSelected(),
        policyId: 'stub',
        policyVersion: 1,
        evidenceRefs: const [],
      )),
    );
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'safety ok',
    );
  }
}

/// Writes CandidateSafetyArtifact with applyPermitted=false.
class _BlockedSafetyAdapter implements ProToolAdapter {
  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticValidateSafety;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    ctx.store.put(
      ctx.projectId,
      step.outputRef,
      CandidateSafetyArtifact(CandidateSafetyResult(
        applyPermitted: false,
        issues: const [
          CandidateSafetyIssue(
            code: CandidateSafetyViolationCode.noBoostGuard,
            detail: 'gainDb 3.0 dB is positive — boost forbidden',
          ),
        ],
        verifiedCandidates: const [],
        policyId: 'stub',
        policyVersion: 1,
        evidenceRefs: const [],
      )),
    );
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'safety blocked',
    );
  }
}

LoopMeasurementSnapshot _snapshot() => LoopMeasurementSnapshot(
      measurementRef: 'snap',
      scoreResult: const ResponseErrorResult(
        rmsDb: 0.0,
        maxDeviationDb: 0.0,
        maxDeviationHz: 0.0,
        weightedRmsDb: 0.0,
        score: 70.0,
      ),
      confidenceStatus: ConfidenceStatus.valid,
    );

// ── Controller factory ────────────────────────────────────────────────────────

ProGuidedAiController _ctrl(List<ProToolAdapter> adapters) =>
    ProGuidedAiController(
      service: ProOrchestrateService(
          dio: _dio(_envelope(_cloudResponse(_gatePlan())))),
      adapterOverrides: adapters,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Apply Gate — ProGuidedAiConfirmPending', () {
    // ── 1. Successful analysis → confirmation state ──────────────────────────
    test('1. successful analysis reaches ProGuidedAiConfirmPending', () async {
      final ctrl = _ctrl([
        const _PassAdapter(ProOrchestratorToolId.measurementAnalyze),
        _OptAdapter(),
        _SafetyAdapter(),
      ]);
      final project = _projectWithChannel();

      final states = <ProGuidedAiState>[];
      ctrl.addListener(states.add);

      final future = ctrl.start(
        project: project,
        userGoal: 'test',
        onApply: (_, __) async {},
      );

      await Future.doWhile(() async {
        await Future.delayed(Duration.zero);
        return !states.any((s) => s is ProGuidedAiConfirmPending) &&
            !states.any(
                (s) => s is ProGuidedAiCompleted || s is ProGuidedAiFailed);
      });

      expect(states.any((s) => s is ProGuidedAiConfirmPending), isTrue,
          reason: 'state sequence must include ProGuidedAiConfirmPending');

      final pending = states.whereType<ProGuidedAiConfirmPending>().first;
      ctrl.cancel(pending.request.stepId);
      await future;
    });

    // ── 2. Candidate preview contains 3 selected candidates ──────────────────
    test('2. candidate preview carries 3 selected candidates', () async {
      final ctrl = _ctrl([
        const _PassAdapter(ProOrchestratorToolId.measurementAnalyze),
        _OptAdapter(),
        _SafetyAdapter(),
      ]);
      final project = _projectWithChannel();

      final states = <ProGuidedAiState>[];
      ctrl.addListener(states.add);

      final future = ctrl.start(
        project: project,
        userGoal: 'test',
        onApply: (_, __) async {},
      );

      await Future.doWhile(() async {
        await Future.delayed(Duration.zero);
        return !states.any((s) => s is ProGuidedAiConfirmPending) &&
            !states.any(
                (s) => s is ProGuidedAiCompleted || s is ProGuidedAiFailed);
      });

      final pending = states.whereType<ProGuidedAiConfirmPending>().first;

      expect(pending.candidatePreview, isNotNull);
      expect(pending.candidatePreview!.length, 3,
          reason: 'preview must mirror the 3 selected candidates');

      ctrl.cancel(pending.request.stepId);
      await future;
    });

    // ── 3. No project mutation before confirmation ────────────────────────────
    test('3. onApply is NOT called before user confirms', () async {
      int applyCallCount = 0;
      final ctrl = _ctrl([
        const _PassAdapter(ProOrchestratorToolId.measurementAnalyze),
        _OptAdapter(),
        _SafetyAdapter(),
      ]);
      final project = _projectWithChannel();

      final states = <ProGuidedAiState>[];
      ctrl.addListener(states.add);

      final future = ctrl.start(
        project: project,
        userGoal: 'test',
        onApply: (_, __) async {
          applyCallCount++;
        },
      );

      await Future.doWhile(() async {
        await Future.delayed(Duration.zero);
        return !states.any((s) => s is ProGuidedAiConfirmPending) &&
            !states.any(
                (s) => s is ProGuidedAiCompleted || s is ProGuidedAiFailed);
      });

      expect(applyCallCount, 0,
          reason: 'onApply must not fire before user confirms');

      final pending = states.whereType<ProGuidedAiConfirmPending>().first;
      ctrl.cancel(pending.request.stepId);
      await future;

      expect(applyCallCount, 0,
          reason: 'cancel must not trigger onApply either');
    });

    // ── 4. Confirmation → existing Apply path ────────────────────────────────
    test('4. confirm() triggers onApply exactly once', () async {
      int applyCallCount = 0;
      final ctrl = _ctrl([
        const _PassAdapter(ProOrchestratorToolId.measurementAnalyze),
        _OptAdapter(),
        _SafetyAdapter(),
      ]);
      final project = _projectWithChannel();

      final states = <ProGuidedAiState>[];
      ctrl.addListener(states.add);

      final future = ctrl.start(
        project: project,
        userGoal: 'test',
        onApply: (_, __) async {
          applyCallCount++;
        },
      );

      await Future.doWhile(() async {
        await Future.delayed(Duration.zero);
        return !states.any((s) => s is ProGuidedAiConfirmPending) &&
            !states.any(
                (s) => s is ProGuidedAiCompleted || s is ProGuidedAiFailed);
      });

      final pending = states.whereType<ProGuidedAiConfirmPending>().first;
      ctrl.confirm(pending.request.stepId);
      await future;

      expect(applyCallCount, 1,
          reason: 'onApply must be called exactly once after confirm');

      final completed = states.whereType<ProGuidedAiCompleted>().lastOrNull;
      expect(completed, isNotNull);
      expect(completed!.applyResult, isNotNull,
          reason: 'completed state must carry applyResult after confirm');
    });

    // ── 5. Blocked safety result → no confirmation ───────────────────────────
    test('5. blocked safety skips ConfirmPending; completed carries reason',
        () async {
      int applyCallCount = 0;
      final ctrl = _ctrl([
        const _PassAdapter(ProOrchestratorToolId.measurementAnalyze),
        _OptAdapter(),
        _BlockedSafetyAdapter(),
      ]);
      final project = _projectWithChannel();

      final states = <ProGuidedAiState>[];
      ctrl.addListener(states.add);

      await ctrl.start(
        project: project,
        userGoal: 'test',
        onApply: (_, __) async {
          applyCallCount++;
        },
      );

      expect(states.any((s) => s is ProGuidedAiConfirmPending), isFalse,
          reason: 'blocked safety must never reach ConfirmPending');
      expect(applyCallCount, 0);

      final completed = states.whereType<ProGuidedAiCompleted>().lastOrNull;
      expect(completed, isNotNull);
      expect(completed!.applyBlockedReason, isNotNull,
          reason: 'completed state must carry applyBlockedReason');
      expect(completed.applyBlockedReason,
          contains('gainDb 3.0 dB is positive — boost forbidden'));
    });
  });
}
