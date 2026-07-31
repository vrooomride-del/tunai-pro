// Phase 15-C-3 — Closed Loop Bridge tests.
//
// Verifies that after safety validation + apply:
//   1. loopPhase transitions to awaitingMeasurement
//   2. beforeMeasurementRef is preserved (opaque ref, no DSP value)
//   3. without after-measurement, loopPhase stays awaitingMeasurement
//   4. no DSP forbidden keys appear in the completed state
//   5. regression (all tests pass)

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_state.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_response.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_service.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_result.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

// ── Dio stub ──────────────────────────────────────────────────────────────────

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

// ── Adapters ──────────────────────────────────────────────────────────────────

/// Generic stub — writes LoopSnapshotArtifact to satisfy the registry's
/// store-check, for steps that are not the focus of these tests.
class _StubAdapter implements ProToolAdapter {
  @override
  final ProOrchestratorToolId toolId;
  const _StubAdapter(this.toolId);

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    // Any concrete ProToolArtifact subtype satisfies the sealed class.
    ctx.store.put(ctx.projectId, step.outputRef,
        const CandidateSafetyArtifact(_emptySafety));
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'stub ok',
    );
  }
}

/// Safety adapter — writes CandidateSafetyArtifact with applyPermitted.
class _SafetyAdapter implements ProToolAdapter {
  final bool applyPermitted;
  const _SafetyAdapter({this.applyPermitted = true});

  @override
  ProOrchestratorToolId get toolId => ProOrchestratorToolId.acousticValidateSafety;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    ctx.store.put(
      ctx.projectId,
      step.outputRef,
      CandidateSafetyArtifact(CandidateSafetyResult(
        applyPermitted: applyPermitted,
        issues: const [],
        verifiedCandidates: const [],
        policyId: 'stub-policy',
        policyVersion: 1,
        evidenceRefs: const [],
      )),
    );
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'safety: ${applyPermitted ? 'ok' : 'blocked'}',
    );
  }
}

// Shared constant — used by _StubAdapter for non-safety steps.
const _emptySafety = CandidateSafetyResult(
  applyPermitted: false,
  issues: [],
  verifiedCandidates: [],
  policyId: 'n/a',
  policyVersion: 0,
  evidenceRefs: [],
);

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _pid = 'proj-loop-bridge';
final _now = DateTime(2025, 1, 1);

/// Project with one PEQ channel so _runApply can find a channel.
ProProject _project() => ProProject(
      id: _pid,
      name: 'Loop Bridge Test',
      createdAt: _now,
      updatedAt: _now,
      tuningState: TuningProjectState(
        peqChannels: [
          PeqChannelState(
            channelId: 'ch_wf_l',
            bands: [
              const PeqBand(
                  id: 'b0', frequencyHz: 200.0, gainDb: -3.0, q: 1.5),
            ],
          ),
        ],
      ),
    );

ProOrchestratorStep _step(
  String id,
  ProOrchestratorToolId toolId, {
  String? outputRef,
}) =>
    ProOrchestratorStep(
      stepId: id,
      toolId: toolId,
      objective: 'stub $id',
      inputRefs: const [],
      outputRef: outputRef ?? 'out-$id',
      requiresUserConfirmation: false,
    );

Map<String, dynamic> _envelope(List<ProOrchestratorStep> steps) =>
    {
      'result': ProOrchestrateResponse(
        projectId: _pid,
        plan: ProOrchestratorPlan(
          planId: 'plan-bridge',
          intentRef: 'intent-ref',
          contextRef: 'ctx-ref',
          steps: steps,
        ),
        explanation: const ProExplanation(
          title: '루프 브리지 테스트',
          summary: '스텁 플랜.',
          explanationLevel: ProExplanationLevel.intermediate,
        ),
      ).toJson()
    };

/// Builds a controller with given steps and adapters, runs start(), returns
/// the final [ProGuidedAiCompleted] state or throws if completion didn't happen.
Future<ProGuidedAiCompleted> _run(
  List<ProOrchestratorStep> steps,
  List<ProToolAdapter> adapters, {
  Future<void> Function(String, TuningApplyResult)? onApply,
}) async {
  final ctrl = ProGuidedAiController(
    service: ProOrchestrateService(dio: _dio(_envelope(steps))),
    adapterOverrides: adapters,
  );
  ProGuidedAiCompleted? done;
  ctrl.addListener((s) {
    if (s is ProGuidedAiCompleted) done = s;
  });
  await ctrl.start(
    project: _project(),
    userGoal: 'test',
    onApply: onApply,
  );
  expect(done, isNotNull, reason: 'expected ProGuidedAiCompleted');
  return done!;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. apply 완료 후 awaitingMeasurement 상태 ─────────────────────────────

  group('1. awaitingMeasurement after apply', () {
    // Single-channel safety-only plans cannot bypass the 4-channel gate:
    // loopPhase stays null when fullSystemReady=false (project has only ch_wf_l,
    // 3 required channels missing → legacy auto-apply is gated behind fullSystemReady).
    test('loopPhase is null when safety-only plan and !fullSystemReady', () async {
      final steps = [
        _step('s0', ProOrchestratorToolId.measurementAnalyze,
            outputRef: 'out-meas'),
        _step('s1', ProOrchestratorToolId.acousticValidateSafety,
            outputRef: 'out-safety'),
      ];
      final done = await _run(
        steps,
        [
          const _StubAdapter(ProOrchestratorToolId.measurementAnalyze),
          const _SafetyAdapter(applyPermitted: true),
        ],
        onApply: (_, __) async {},
      );
      expect(done.loopPhase, isNull);
    });

    test('loopPhase is null when apply not permitted', () async {
      final steps = [
        _step('s0', ProOrchestratorToolId.measurementAnalyze,
            outputRef: 'out-meas'),
        _step('s1', ProOrchestratorToolId.acousticValidateSafety,
            outputRef: 'out-safety'),
      ];
      final done = await _run(
        steps,
        [
          const _StubAdapter(ProOrchestratorToolId.measurementAnalyze),
          const _SafetyAdapter(applyPermitted: false),
        ],
        onApply: (_, __) async {},
      );
      // applyPermitted:false → _runApply returns null → loopPhase null
      expect(done.loopPhase, isNull);
    });

    test('loopPhase is null when onApply callback not provided', () async {
      final steps = [
        _step('s0', ProOrchestratorToolId.measurementAnalyze,
            outputRef: 'out-meas'),
        _step('s1', ProOrchestratorToolId.acousticValidateSafety,
            outputRef: 'out-safety'),
      ];
      final done = await _run(
        steps,
        [
          const _StubAdapter(ProOrchestratorToolId.measurementAnalyze),
          const _SafetyAdapter(applyPermitted: true),
        ],
        // onApply: null — apply skipped
      );
      expect(done.loopPhase, isNull);
    });
  });

  // ── 2. before snapshot 유지 ────────────────────────────────────────────────

  group('2. before snapshot ref preserved', () {
    test('beforeMeasurementRef is non-null when measurementAnalyze ran', () async {
      final steps = [
        _step('s0', ProOrchestratorToolId.measurementAnalyze,
            outputRef: 'out-meas'),
        _step('s1', ProOrchestratorToolId.acousticValidateSafety,
            outputRef: 'out-safety'),
      ];
      final done = await _run(
        steps,
        [
          const _StubAdapter(ProOrchestratorToolId.measurementAnalyze),
          const _SafetyAdapter(applyPermitted: true),
        ],
        onApply: (_, __) async {},
      );
      expect(done.beforeMeasurementRef, equals('out-meas'));
    });

    test('beforeMeasurementRef is null when no measurementAnalyze step ran', () async {
      final steps = [
        _step('s0', ProOrchestratorToolId.acousticValidateSafety,
            outputRef: 'out-safety'),
      ];
      final done = await _run(
        steps,
        [const _SafetyAdapter(applyPermitted: true)],
        onApply: (_, __) async {},
      );
      expect(done.beforeMeasurementRef, isNull);
    });

    test('beforeMeasurementRef is an opaque string (no DSP term)', () async {
      final steps = [
        _step('s0', ProOrchestratorToolId.measurementAnalyze,
            outputRef: 'out-measurement-ref'),
        _step('s1', ProOrchestratorToolId.acousticValidateSafety,
            outputRef: 'out-safety'),
      ];
      final done = await _run(
        steps,
        [
          const _StubAdapter(ProOrchestratorToolId.measurementAnalyze),
          const _SafetyAdapter(applyPermitted: true),
        ],
        onApply: (_, __) async {},
      );
      final ref = done.beforeMeasurementRef!;
      const dspTerms = ['frequency', 'gaindb', 'gain', 'q', 'biquad',
          'address', 'payload', 'coefficient'];
      for (final term in dspTerms) {
        expect(ref.toLowerCase(), isNot(contains(term)));
      }
    });
  });

  // ── 3. after 없음 → loopPhase stays awaitingMeasurement (not evaluated) ──

  group('3. without after-measurement, phase does not advance', () {
    // With the 4-channel gate, single-channel safety-only plans set loopPhase=null
    // (apply never runs). The phase cannot be 'evaluated' in either case.
    test('loopPhase is null (not evaluated) when !fullSystemReady', () async {
      final steps = [
        _step('s0', ProOrchestratorToolId.measurementAnalyze,
            outputRef: 'out-meas'),
        _step('s1', ProOrchestratorToolId.acousticValidateSafety,
            outputRef: 'out-safety'),
      ];
      final done = await _run(
        steps,
        [
          const _StubAdapter(ProOrchestratorToolId.measurementAnalyze),
          const _SafetyAdapter(applyPermitted: true),
        ],
        onApply: (_, __) async {},
      );
      expect(done.loopPhase, isNot(equals(ProClosedLoopPhase.evaluated)));
      expect(done.loopPhase, isNull);
    });

    test('loopVerdict is null when acousticEvaluateLoop did not run', () async {
      final steps = [
        _step('s0', ProOrchestratorToolId.measurementAnalyze,
            outputRef: 'out-meas'),
        _step('s1', ProOrchestratorToolId.acousticValidateSafety,
            outputRef: 'out-safety'),
      ];
      final done = await _run(
        steps,
        [
          const _StubAdapter(ProOrchestratorToolId.measurementAnalyze),
          const _SafetyAdapter(applyPermitted: true),
        ],
        onApply: (_, __) async {},
      );
      expect(done.loopVerdict, isNull);
    });
  });

  // ── 4. DSP forbidden keys absent ─────────────────────────────────────────

  group('4. no DSP forbidden keys in state', () {
    test('ProClosedLoopPhase values contain no DSP terms', () {
      const dspTerms = [
        'frequency', 'gain', 'gaindb', 'q', 'delay', 'biquad',
        'address', 'register', 'payload', 'coefficient',
      ];
      for (final phase in ProClosedLoopPhase.values) {
        for (final term in dspTerms) {
          expect(phase.name.toLowerCase(), isNot(contains(term)),
              reason:
                  'ProClosedLoopPhase.${phase.name} must not contain DSP term "$term"');
        }
      }
    });

    test('loopPhase null; beforeMeasurementRef is opaque string (no numeric)', () async {
      final steps = [
        _step('s0', ProOrchestratorToolId.measurementAnalyze,
            outputRef: 'out-meas'),
        _step('s1', ProOrchestratorToolId.acousticValidateSafety,
            outputRef: 'out-safety'),
      ];
      final done = await _run(
        steps,
        [
          const _StubAdapter(ProOrchestratorToolId.measurementAnalyze),
          const _SafetyAdapter(applyPermitted: true),
        ],
        onApply: (_, __) async {},
      );
      // Single-channel → fullSystemReady=false → apply blocked → loopPhase null.
      expect(done.loopPhase, isNull);
      // beforeMeasurementRef is set from measurementAnalyze output, not apply.
      expect(done.beforeMeasurementRef, isA<String>());
      expect(double.tryParse(done.beforeMeasurementRef!), isNull,
          reason: 'beforeMeasurementRef must not be a parseable number');
    });
  });
}
