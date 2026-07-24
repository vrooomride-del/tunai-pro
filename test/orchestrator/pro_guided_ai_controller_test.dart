// Phase 15 — ProGuidedAiController integration tests.
//
// 8 required scenarios:
//   1. Intent → Plan round-trip
//   2. Plan → Local Orchestrator execution
//   3. Confirmation pause/resume
//   4. Safety failure propagation
//   5. Closed loop improved
//   6. Closed loop regressed
//   7. Forbidden DSP key absence in state
//   8. Deterministic output

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/closed_loop_evaluator.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';
import 'package:tunai_pro/core/orchestrator/pro_acoustic_intent.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_state.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_request.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_response.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_service.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_context.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_result.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_response_error.dart';

// ── Dio stub ─────────────────────────────────────────────────────────────────

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

// ── Stub adapters ─────────────────────────────────────────────────────────────
// ProToolArtifact is sealed — stubs use concrete LoopSnapshotArtifact.
// ProDeterministicToolRegistry checks ctx.store.has(outputRef) after run(),
// so every adapter must write an artifact there.

class _StubAdapter implements ProToolAdapter {
  @override
  final ProOrchestratorToolId toolId;
  const _StubAdapter(this.toolId);

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    ctx.store.put(ctx.projectId, step.outputRef,
        LoopSnapshotArtifact(_snapshot(70.0)));
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'stub ok',
    );
  }
}

class _FailingAdapter implements ProToolAdapter {
  @override
  final ProOrchestratorToolId toolId;
  final String failMessage;
  const _FailingAdapter(this.toolId, {this.failMessage = 'stub failure'});

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    throw ProToolException(ProToolFailureCode.engineError, failMessage);
  }
}

LoopMeasurementSnapshot _snapshot(double score) => LoopMeasurementSnapshot(
      measurementRef: 'snap-ref',
      scoreResult: ResponseErrorResult(
        rmsDb: 0.0,
        maxDeviationDb: 0.0,
        maxDeviationHz: 0.0,
        weightedRmsDb: 0.0,
        score: score,
      ),
      confidenceStatus: ConfidenceStatus.valid,
    );

class _LoopAdapter implements ProToolAdapter {
  final ImprovementVerdict verdict;
  const _LoopAdapter(this.verdict);

  @override
  ProOrchestratorToolId get toolId => ProOrchestratorToolId.acousticEvaluateLoop;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final scoreDelta = verdict == ImprovementVerdict.improved
        ? 5.0
        : verdict == ImprovementVerdict.regressed
            ? -3.0
            : 0.0;
    ctx.store.put(
      ctx.projectId,
      step.outputRef,
      ClosedLoopResultArtifact(ClosedLoopResult(
        verdict: verdict,
        before: _snapshot(70.0),
        after: _snapshot(70.0 + scoreDelta),
        scoreDelta: scoreDelta,
        policyId: 'stub-policy',
        policyVersion: 1,
        evidenceRefs: const [],
        reasons: const [],
      )),
    );
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'loop: ${verdict.name}',
    );
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _pid = 'test-project-15';

ProProject _project() => ProProject(
      id: _pid,
      name: 'Test Project',
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

ProOrchestratorStep _step(
  String id,
  ProOrchestratorToolId toolId, {
  bool confirm = false,
}) =>
    ProOrchestratorStep(
      stepId: id,
      toolId: toolId,
      objective: 'stub step $id',
      inputRefs: const [],
      outputRef: 'out-$id',
      requiresUserConfirmation: confirm,
    );

ProOrchestrateResponse _cloudResponse(List<ProOrchestratorStep> steps) =>
    ProOrchestrateResponse(
      projectId: _pid,
      plan: ProOrchestratorPlan(
        planId: 'plan-test',
        intentRef: 'intent-ref',
        contextRef: 'ctx-ref',
        steps: steps,
      ),
      explanation: const ProExplanation(
        title: '테스트 플랜',
        summary: '스텁 AI 설명입니다.',
        explanationLevel: ProExplanationLevel.intermediate,
      ),
    );

Map<String, dynamic> _envelope(ProOrchestrateResponse r) =>
    {'result': r.toJson()};

ProGuidedAiController _ctrl(
  List<ProOrchestratorStep> steps,
  List<ProToolAdapter> adapters,
) =>
    ProGuidedAiController(
      service: ProOrchestrateService(
          dio: _dio(_envelope(_cloudResponse(steps)))),
      adapterOverrides: adapters,
    );

Future<List<ProGuidedAiState>> _collect(
  ProGuidedAiController ctrl,
) async {
  // StateNotifier.addListener fires immediately with current state, so don't
  // pre-add ctrl.state manually — it would double-count the initial idle.
  final states = <ProGuidedAiState>[];
  ctrl.addListener(states.add);
  await ctrl.start(project: _project(), userGoal: 'test goal');
  return states;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. Intent → Plan round-trip ────────────────────────────────────────────
  group('1. Intent → Plan round-trip', () {
    test('ProOrchestrateRequest toJson has no forbidden DSP keys', () {
      final req = ProOrchestrateRequest(
        projectId: _pid,
        intent: const ProAcousticIntent(
          userGoal: 'tighter bass',
          perceivedProblem: 'boomy',
          systemScope: 'full_system',
          tuningPriority: ProTuningPriority.roomAdaptation,
          allowedChangeAreas: [ProToneArea.lowEnd],
          protectedAreas: [ProToneArea.highEnd],
          listeningContext: 'desk',
          explanationLevel: ProExplanationLevel.intermediate,
        ),
        context: ProOrchestratorContext(
          projectId: _pid,
          connectionState: ProConnectionState.disconnected,
        ),
      );
      final encoded = jsonEncode(req.toJson()).toLowerCase();
      for (final token in ProContract.forbiddenKeyTokens) {
        expect(encoded.contains('"$token":'), isFalse,
            reason: 'forbidden key "$token" must not appear in request');
      }
    });

    test('Cloud response fromJson(toJson()) round-trip preserves plan', () {
      final resp =
          _cloudResponse([_step('s0', ProOrchestratorToolId.acousticClassify)]);
      final parsed = ProOrchestrateResponse.fromJson(resp.toJson());
      expect(parsed.plan.planId, resp.plan.planId);
      expect(parsed.explanation.title, resp.explanation.title);
    });
  });

  // ── 2. Plan → Local Orchestrator execution ─────────────────────────────────
  group('2. Plan → Orchestrator execution', () {
    test('two-step plan reaches ProGuidedAiCompleted', () async {
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticClassify),
          _step('s1', ProOrchestratorToolId.acousticPlan),
        ],
        [
          const _StubAdapter(ProOrchestratorToolId.acousticClassify),
          const _StubAdapter(ProOrchestratorToolId.acousticPlan),
        ],
      );
      final states = await _collect(ctrl);
      expect(states.last, isA<ProGuidedAiCompleted>());
    });

    test('completed outcome has same step count as plan', () async {
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticClassify),
          _step('s1', ProOrchestratorToolId.acousticPlan),
        ],
        [
          const _StubAdapter(ProOrchestratorToolId.acousticClassify),
          const _StubAdapter(ProOrchestratorToolId.acousticPlan),
        ],
      );
      final states = await _collect(ctrl);
      final done = states.last as ProGuidedAiCompleted;
      expect(done.outcome.stepRecords.length, 2);
    });

    test('state transitions: idle → cloudCalling → executing → completed',
        () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticClassify)],
        [const _StubAdapter(ProOrchestratorToolId.acousticClassify)],
      );
      final states = await _collect(ctrl);
      expect(states[0], isA<ProGuidedAiIdle>());
      expect(states[1], isA<ProGuidedAiCloudCalling>());
      expect(states.any((s) => s is ProGuidedAiExecuting), isTrue);
      expect(states.last, isA<ProGuidedAiCompleted>());
    });
  });

  // ── 3. Confirmation pause/resume ───────────────────────────────────────────
  group('3. Confirmation pause/resume', () {
    // Poll until state reaches ProGuidedAiConfirmPending or timeout.
    Future<void> _waitForPending(ProGuidedAiController ctrl) async {
      for (var i = 0; i < 200; i++) {
        if (ctrl.state is ProGuidedAiConfirmPending) return;
        await Future.delayed(const Duration(milliseconds: 2));
      }
    }

    test('confirm resumes execution → ProGuidedAiCompleted', () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticClassify, confirm: true)],
        [const _StubAdapter(ProOrchestratorToolId.acousticClassify)],
      );

      final future = ctrl.start(project: _project(), userGoal: 'test');
      await _waitForPending(ctrl);

      expect(ctrl.state, isA<ProGuidedAiConfirmPending>());
      ctrl.confirm((ctrl.state as ProGuidedAiConfirmPending).request.stepId);
      await future;

      expect(ctrl.state, isA<ProGuidedAiCompleted>());
    });

    test('cancel at confirmation → ProGuidedAiFailed', () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticClassify, confirm: true)],
        [const _StubAdapter(ProOrchestratorToolId.acousticClassify)],
      );

      final future = ctrl.start(project: _project(), userGoal: 'test');
      await _waitForPending(ctrl);

      ctrl.cancel((ctrl.state as ProGuidedAiConfirmPending).request.stepId);
      await future;

      expect(ctrl.state, isA<ProGuidedAiFailed>());
    });

    test('pending request carries correct stepId', () async {
      final ctrl = _ctrl(
        [_step('my-step-42', ProOrchestratorToolId.acousticClassify,
            confirm: true)],
        [const _StubAdapter(ProOrchestratorToolId.acousticClassify)],
      );

      final future = ctrl.start(project: _project(), userGoal: 'test');
      await _waitForPending(ctrl);

      final pending = ctrl.state as ProGuidedAiConfirmPending;
      expect(pending.request.stepId, 'my-step-42');

      ctrl.cancel(pending.request.stepId);
      await future;
    });
  });

  // ── 4. Safety failure propagation ─────────────────────────────────────────
  group('4. Safety failure propagation', () {
    test('failing safety adapter → ProGuidedAiFailed', () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticValidateSafety)],
        [const _FailingAdapter(ProOrchestratorToolId.acousticValidateSafety,
            failMessage: 'safety check failed')],
      );
      final states = await _collect(ctrl);
      expect(states.last, isA<ProGuidedAiFailed>());
    });

    test('failure message is surfaced in state', () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticValidateSafety)],
        [const _FailingAdapter(ProOrchestratorToolId.acousticValidateSafety,
            failMessage: 'safety check failed')],
      );
      final states = await _collect(ctrl);
      expect(
          (states.last as ProGuidedAiFailed).message,
          contains('safety check failed'));
    });

    test('failure stops execution mid-plan', () async {
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticClassify),
          _step('s1', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          const _StubAdapter(ProOrchestratorToolId.acousticClassify),
          const _FailingAdapter(ProOrchestratorToolId.acousticValidateSafety),
        ],
      );
      final states = await _collect(ctrl);
      expect(states.last, isA<ProGuidedAiFailed>());
    });
  });

  // ── 5. Closed loop: improved ───────────────────────────────────────────────
  group('5. Closed loop: improved', () {
    test('loopVerdict is improved', () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticEvaluateLoop)],
        [const _LoopAdapter(ImprovementVerdict.improved)],
      );
      final states = await _collect(ctrl);
      expect((states.last as ProGuidedAiCompleted).loopVerdict,
          ImprovementVerdict.improved);
    });
  });

  // ── 6. Closed loop: regressed ─────────────────────────────────────────────
  group('6. Closed loop: regressed', () {
    test('loopVerdict is regressed', () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticEvaluateLoop)],
        [const _LoopAdapter(ImprovementVerdict.regressed)],
      );
      final states = await _collect(ctrl);
      expect((states.last as ProGuidedAiCompleted).loopVerdict,
          ImprovementVerdict.regressed);
    });

    test('loopVerdict is null when no loop step ran', () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticClassify)],
        [const _StubAdapter(ProOrchestratorToolId.acousticClassify)],
      );
      final states = await _collect(ctrl);
      expect((states.last as ProGuidedAiCompleted).loopVerdict, isNull);
    });
  });

  // ── 7. Forbidden DSP key absence ──────────────────────────────────────────
  group('7. Forbidden DSP key absence in state', () {
    test('explanation.summary has no forbidden key as a JSON key', () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticClassify)],
        [const _StubAdapter(ProOrchestratorToolId.acousticClassify)],
      );
      final states = await _collect(ctrl);
      final done = states.last as ProGuidedAiCompleted;
      final text = done.explanation.summary.toLowerCase();
      for (final token in ProContract.forbiddenKeyTokens) {
        expect(text.contains('"$token":'), isFalse,
            reason: 'explanation must not embed "$token" as a JSON key');
      }
    });

    test('step records serialized with no forbidden DSP key', () async {
      final ctrl = _ctrl(
        [_step('s0', ProOrchestratorToolId.acousticClassify)],
        [const _StubAdapter(ProOrchestratorToolId.acousticClassify)],
      );
      final states = await _collect(ctrl);
      final done = states.last as ProGuidedAiCompleted;
      for (final r in done.outcome.stepRecords) {
        final json = jsonEncode(r.toJson()).toLowerCase();
        for (final token in [
          'frequency',
          'gaindb',
          'biquad',
          'address',
          'payload'
        ]) {
          expect(json.contains('"$token":'), isFalse,
              reason: 'step record must not contain "$token"');
        }
      }
    });
  });

  // ── 8. Deterministic output ────────────────────────────────────────────────
  group('8. Deterministic output', () {
    test('ProOrchestrateRequest toJson is stable across calls', () {
      final req = ProOrchestrateRequest(
        projectId: _pid,
        intent: const ProAcousticIntent(
          userGoal: 'test',
          perceivedProblem: '',
          systemScope: 'full_system',
          tuningPriority: ProTuningPriority.balanced,
          allowedChangeAreas: [ProToneArea.overallTone],
          protectedAreas: [],
          listeningContext: '',
          explanationLevel: ProExplanationLevel.intermediate,
        ),
        context: ProOrchestratorContext(
          projectId: _pid,
          connectionState: ProConnectionState.disconnected,
        ),
      );
      expect(jsonEncode(req.toJson()), jsonEncode(req.toJson()));
    });

    test('step order is identical across two equivalent runs', () async {
      Future<List<String>> stepOrder() async {
        final ctrl = _ctrl(
          [
            _step('s0', ProOrchestratorToolId.acousticClassify),
            _step('s1', ProOrchestratorToolId.acousticPlan),
          ],
          [
            const _StubAdapter(ProOrchestratorToolId.acousticClassify),
            const _StubAdapter(ProOrchestratorToolId.acousticPlan),
          ],
        );
        final states = await _collect(ctrl);
        final done = states.last as ProGuidedAiCompleted;
        return done.outcome.stepRecords.map((r) => r.stepId).toList();
      }

      expect(await stepOrder(), await stepOrder());
    });
  });
}
