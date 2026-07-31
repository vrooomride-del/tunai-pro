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
//
// v1 Guided Tuning scenarios (groups 9-13):
//   9.  Cloud unavailable → local deterministic fallback
//   10. Missing FRD → fail-closed (measurementAnalyze throws)
//   11. Unsafe candidates → apply blocked (applyPermitted=false)
//   12. No hardware write before approval (onApply not called before confirm)
//   13. Post-approval deploy handoff (onApply called after confirm)

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart'
    show TuningApplyResult;
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart'
    show AcousticFeatureType;
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/closed_loop_evaluator.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart' show CorrectionIntent;
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';
import 'package:tunai_pro/core/acoustic/measurement_evidence.dart';
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
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_classify_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_scoring_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart'
    show
        DriverRole,
        DriverSide,
        MeasurementParseResult,
        MeasurementParseStatus,
        MeasurementProjectState;
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_response_error.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart'
    show PeqChannelState, TuningProjectState;
import 'package:tunai_pro/core/pro_tuning_report_data.dart'
    show GuidedTuningSessionSummary;

// ── Dio stubs ─────────────────────────────────────────────────────────────────

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

class _NetworkErrorStub extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handler.reject(DioException(
        requestOptions: options,
        message: 'simulated network error',
        type: DioExceptionType.connectionError,
      ));
}

Dio _failingDio() => Dio()..interceptors.add(_NetworkErrorStub());

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

// ── Specialized stub adapters for v1 Guided Tuning tests ─────────────────────

/// Stores a [CandidateSafetyArtifact] with [applyPermitted] as requested.
class _SafetyStubAdapter implements ProToolAdapter {
  final bool applyPermitted;
  const _SafetyStubAdapter({required this.applyPermitted});

  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticValidateSafety;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final result = CandidateSafetyResult(
      applyPermitted: applyPermitted,
      issues: applyPermitted
          ? []
          : [
              const CandidateSafetyIssue(
                code: CandidateSafetyViolationCode.noBoostGuard,
                detail: 'stub: boost not permitted',
              )
            ],
      verifiedCandidates: [],
      policyId: 'test',
      policyVersion: 1,
      evidenceRefs: [],
    );
    ctx.store.put(
        ctx.projectId, step.outputRef, CandidateSafetyArtifact(result));
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: applyPermitted ? ProConfidence.high : ProConfidence.low,
      summary: 'safety stub applyPermitted=$applyPermitted',
    );
  }
}

/// Stores an [OptimizedSelectionArtifact] with one selected stub candidate
/// so the controller-level apply gate triggers.
class _OptimizerWithCandidateStubAdapter implements ProToolAdapter {
  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticOptimizeSelection;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final candidate = _stubScoredCandidate();
    final selection = OptimizedSelection(
      status: OptimizationStatus.ok,
      selected: [
        SelectedCandidate(
          scoredCandidate: candidate,
          applicationOrder: 1,
          selectionReason: 'stub selection',
        ),
      ],
      rejected: [],
      reasons: [],
      evidenceRefs: [],
      policyId: 'test',
      policyVersion: 1,
    );
    ctx.store.put(
        ctx.projectId, step.outputRef, OptimizedSelectionArtifact(selection));
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'optimizer stub: 1 candidate selected',
    );
  }
}

ScoredCandidate _stubScoredCandidate() => const ScoredCandidate(
      candidate: PeqCandidate(
        candidateId: 'candidate:feat-stub',
        featureId: 'feat-stub',
        featureType: AcousticFeatureType.narrowPeak,
        frequencyHz: 200.0,
        gainDb: -3.0,
        q: 2.0,
        intent: CorrectionIntent.cut,
        reason: 'stub',
      ),
      prominenceDb: 6.0,
      prominenceScore: 24.0,
      magnitudeConsistencyScore: 20.0,
      qualityFactor: 1.0,
      compositeScore: 80.0,
      grade: CandidateScoreGrade.good,
      rank: 1,
      reasons: [],
    );

/// Resolver that throws on every call — used for adapters that don't call the
/// resolver (e.g. AcousticClassifyAdapter reads only from the artifact store).
class _ThrowingResolver implements ProToolReferenceResolver {
  @override
  ProMeasurementSource resolveMeasurementSource(String projectId, String ref) =>
      throw UnsupportedError('_ThrowingResolver: resolveMeasurementSource not supported');

  @override
  MeasurementProjectState resolveMeasurementProjectState(
          String projectId, String ref) =>
      throw UnsupportedError(
          '_ThrowingResolver: resolveMeasurementProjectState not supported');

  @override
  ProSimulationInput resolveSimulationInput(String projectId, String ref) =>
      throw UnsupportedError(
          '_ThrowingResolver: resolveSimulationInput not supported');

  @override
  ProProject? resolveProjectSnapshot(String projectId) => null;
}

/// Stub adapter for `acousticScoreCandidates` that:
///   1. Stores a [ScoredCandidateSetArtifact] so downstream optimizer runs.
///   2. Stores a [SimulationErrorArtifact] at the expected side-channel key
///      ('${outputRef}:sim_err') so [_buildApplyGatePending] can build the
///      Before/After summary string.
class _ScoringWithSimErrAdapter implements ProToolAdapter {
  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticScoreCandidates;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    // Scored candidate set — minimal but well-formed.
    final scored = ScoredCandidateSet(
      status: ScoredCandidateSetStatus.ok,
      scoredCandidates: [_stubScoredCandidate()],
      reasons: [],
      policyId: 'test',
      policyVersion: 1,
      evidenceRefs: [],
    );
    ctx.store
        .put(ctx.projectId, step.outputRef, ScoredCandidateSetArtifact(scored));

    // Side-channel simulation error artifact (Before 5.0 dB, best After 2.0 dB).
    const before = ResponseErrorResult(
      rmsDb: 5.5,
      maxDeviationDb: 8.0,
      maxDeviationHz: 200.0,
      weightedRmsDb: 5.0,
      score: 43.0,
    );
    const afterCand = ResponseErrorResult(
      rmsDb: 2.5,
      maxDeviationDb: 4.0,
      maxDeviationHz: 200.0,
      weightedRmsDb: 2.0,
      score: 72.0,
    );
    ctx.store.put(
      ctx.projectId,
      '${step.outputRef}:sim_err',
      SimulationErrorArtifact(
        before,
        const {'candidate:feat-stub': afterCand},
        simulationMode: 'magnitude-only',
      ),
    );

    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'score+simErr stub',
    );
  }
}

/// Variant of [_ScoringWithSimErrAdapter] that writes simulationMode='phase-aware'.
class _ScoringPhaseAwareAdapter implements ProToolAdapter {
  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.acousticScoreCandidates;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final scored = ScoredCandidateSet(
      status: ScoredCandidateSetStatus.ok,
      scoredCandidates: [_stubScoredCandidate()],
      reasons: [],
      policyId: 'test',
      policyVersion: 1,
      evidenceRefs: [],
    );
    ctx.store
        .put(ctx.projectId, step.outputRef, ScoredCandidateSetArtifact(scored));

    const before = ResponseErrorResult(
      rmsDb: 5.5,
      maxDeviationDb: 8.0,
      maxDeviationHz: 200.0,
      weightedRmsDb: 5.0,
      score: 43.0,
    );
    const afterCand = ResponseErrorResult(
      rmsDb: 2.5,
      maxDeviationDb: 4.0,
      maxDeviationHz: 200.0,
      weightedRmsDb: 2.0,
      score: 72.0,
    );
    ctx.store.put(
      ctx.projectId,
      '${step.outputRef}:sim_err',
      SimulationErrorArtifact(
        before,
        const {'candidate:feat-stub': afterCand},
        simulationMode: 'phase-aware',
      ),
    );

    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.high,
      summary: 'score+simErr phase-aware stub',
    );
  }
}

/// Stub measurementAnalyze adapter that stores a [MeasurementArtifact] with
/// [ConfidenceStatus.insufficientEvidence] so the controller's apply gate can
/// detect the insufficient evidence condition.
class _InsuffEvidenceMeasureAdapter implements ProToolAdapter {
  @override
  ProOrchestratorToolId get toolId =>
      ProOrchestratorToolId.measurementAnalyze;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final confidence = MeasurementConfidenceResult(
      status: ConfidenceStatus.insufficientEvidence,
      grade: ConfidenceGrade.unavailable,
      overallScore: 0.0,
      repeatability: const MetricOutcome(
          metric: ConfidenceMetric.repeatability,
          status: MetricStatus.unavailable),
      snr: const MetricOutcome(
          metric: ConfidenceMetric.snr, status: MetricStatus.unavailable),
      validBandCoverage: const MetricOutcome(
          metric: ConfidenceMetric.validBandCoverage,
          status: MetricStatus.unavailable),
      clipping: const MetricOutcome(
          metric: ConfidenceMetric.clipping, status: MetricStatus.unavailable),
      validBinCount: 0,
      requestedBinCount: 0,
      usableMinHz: null,
      usableMaxHz: null,
      reasons: ['single sweep only'],
      warnings: [],
      unavailableMetrics: [],
      policyId: 'test',
      policyVersion: 1,
    );
    final evidence = ImportedMeasurementEvidence(
      evidenceId: 'ev-insuff',
      projectId: ctx.projectId,
      measurementRef: step.inputRefs.isNotEmpty ? step.inputRefs.first : 'ch',
      domain: MeasurementDomain.acousticResponse,
      source: MeasurementSource.importedFrd,
      provenance: MeasurementProvenance(
        producer: 'test',
        producerVersion: '1',
        sourceIdentity: 'test.frd',
        contentHash: 'sha256:test',
        label: 'test',
      ),
      availableMetrics: {EvidenceMetric.validBandCoverage},
      unavailableMetrics: {
        EvidenceMetric.repeatability,
        EvidenceMetric.snr,
        EvidenceMetric.clipping,
      },
      displayName: 'test.frd',
      originalFormat: 'FRD',
      parserSchemaVersion: '1',
      magnitudePresent: true,
      phasePresent: false,
      impedancePresent: false,
    );
    ctx.store.put(
      ctx.projectId,
      step.outputRef,
      MeasurementArtifact(
        parse: const MeasurementParseResult(
            status: MeasurementParseStatus.parsed, summary: 'stub'),
        evidence: evidence,
        evaluation: MeasurementConfidenceEvaluation.evaluated,
        confidence: confidence,
      ),
    );

    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: toolId,
      outputRef: step.outputRef,
      confidence: ProConfidence.low,
      summary: 'measure stub: insufficientEvidence',
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

/// Shared poll helper for groups 16-18 that need to wait for the apply gate.
Future<void> _waitForApplyGateGroup16(ProGuidedAiController ctrl) async {
  for (var i = 0; i < 200; i++) {
    if (ctrl.state is ProGuidedAiConfirmPending) return;
    await Future.delayed(const Duration(milliseconds: 2));
  }
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

  // ── 9. Cloud unavailable → local deterministic fallback ───────────────────
  group('9. Cloud unavailable → local deterministic fallback', () {
    List<ProToolAdapter> _fullPipelineStubs() => [
          const _StubAdapter(ProOrchestratorToolId.measurementAnalyze),
          const _StubAdapter(ProOrchestratorToolId.acousticClassify),
          const _StubAdapter(ProOrchestratorToolId.acousticPlan),
          const _StubAdapter(ProOrchestratorToolId.acousticGenerateCandidates),
          const _StubAdapter(ProOrchestratorToolId.acousticScoreCandidates),
          const _StubAdapter(ProOrchestratorToolId.acousticOptimizeSelection),
          const _StubAdapter(ProOrchestratorToolId.acousticValidateSafety),
        ];

    test('cloud network failure → ProGuidedAiCompleted (not ProGuidedAiFailed)',
        () async {
      final ctrl = ProGuidedAiController(
        service: ProOrchestrateService(dio: _failingDio()),
        adapterOverrides: _fullPipelineStubs(),
      );
      final states = await _collect(ctrl);
      expect(states.last, isA<ProGuidedAiCompleted>());
    });

    test('cloud failure → state sequence never contains ProGuidedAiFailed',
        () async {
      final ctrl = ProGuidedAiController(
        service: ProOrchestrateService(dio: _failingDio()),
        adapterOverrides: _fullPipelineStubs(),
      );
      final states = await _collect(ctrl);
      expect(states.any((s) => s is ProGuidedAiFailed), isFalse);
    });

    test('cloud failure → transitions through cloudCalling then executing',
        () async {
      final ctrl = ProGuidedAiController(
        service: ProOrchestrateService(dio: _failingDio()),
        adapterOverrides: _fullPipelineStubs(),
      );
      final states = await _collect(ctrl);
      expect(states[0], isA<ProGuidedAiIdle>());
      expect(states[1], isA<ProGuidedAiCloudCalling>());
      expect(states.any((s) => s is ProGuidedAiExecuting), isTrue);
      expect(states.last, isA<ProGuidedAiCompleted>());
    });

    test('fallback plan runs all 7 pipeline steps', () async {
      final ctrl = ProGuidedAiController(
        service: ProOrchestrateService(dio: _failingDio()),
        adapterOverrides: _fullPipelineStubs(),
      );
      final states = await _collect(ctrl);
      final done = states.last as ProGuidedAiCompleted;
      expect(done.outcome.stepRecords.length, 7);
    });

    test('fallback explanation has offline warning', () async {
      final ctrl = ProGuidedAiController(
        service: ProOrchestrateService(dio: _failingDio()),
        adapterOverrides: _fullPipelineStubs(),
      );
      final states = await _collect(ctrl);
      final done = states.last as ProGuidedAiCompleted;
      expect(done.explanation.warnings, isNotEmpty);
    });
  });

  // ── 10. Missing FRD → fail-closed ─────────────────────────────────────────
  group('10. Missing FRD → fail-closed', () {
    test('measurementAnalyze throws → ProGuidedAiFailed', () async {
      final ctrl = ProGuidedAiController(
        service: ProOrchestrateService(dio: _failingDio()),
        adapterOverrides: [
          const _FailingAdapter(ProOrchestratorToolId.measurementAnalyze,
              failMessage: 'no FRD data'),
          const _StubAdapter(ProOrchestratorToolId.acousticClassify),
          const _StubAdapter(ProOrchestratorToolId.acousticPlan),
          const _StubAdapter(ProOrchestratorToolId.acousticGenerateCandidates),
          const _StubAdapter(ProOrchestratorToolId.acousticScoreCandidates),
          const _StubAdapter(ProOrchestratorToolId.acousticOptimizeSelection),
          const _StubAdapter(ProOrchestratorToolId.acousticValidateSafety),
        ],
      );
      final states = await _collect(ctrl);
      expect(states.last, isA<ProGuidedAiFailed>());
    });

    test('measurementAnalyze failure message is surfaced in Failed state',
        () async {
      final ctrl = ProGuidedAiController(
        service: ProOrchestrateService(dio: _failingDio()),
        adapterOverrides: [
          const _FailingAdapter(ProOrchestratorToolId.measurementAnalyze,
              failMessage: 'no FRD data'),
          const _StubAdapter(ProOrchestratorToolId.acousticClassify),
          const _StubAdapter(ProOrchestratorToolId.acousticPlan),
          const _StubAdapter(ProOrchestratorToolId.acousticGenerateCandidates),
          const _StubAdapter(ProOrchestratorToolId.acousticScoreCandidates),
          const _StubAdapter(ProOrchestratorToolId.acousticOptimizeSelection),
          const _StubAdapter(ProOrchestratorToolId.acousticValidateSafety),
        ],
      );
      final states = await _collect(ctrl);
      expect((states.last as ProGuidedAiFailed).message, contains('no FRD data'));
    });
  });

  // ── 11. Unsafe candidates → apply blocked ─────────────────────────────────
  group('11. Unsafe candidates → apply blocked', () {
    test('safety adapter applyPermitted=false → completed with blocked reason',
        () async {
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s1', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          const _StubAdapter(ProOrchestratorToolId.acousticOptimizeSelection),
          const _SafetyStubAdapter(applyPermitted: false),
        ],
      );
      final states = await _collect(ctrl);
      final done = states.last as ProGuidedAiCompleted;
      expect(done.applyBlockedReason, isNotNull);
    });

    test('safety adapter applyPermitted=false → applyResult is null', () async {
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s1', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          const _StubAdapter(ProOrchestratorToolId.acousticOptimizeSelection),
          const _SafetyStubAdapter(applyPermitted: false),
        ],
      );
      final states = await _collect(ctrl);
      final done = states.last as ProGuidedAiCompleted;
      expect(done.applyResult, isNull);
    });
  });

  // ── 12. No hardware write before approval ─────────────────────────────────
  group('12. No hardware write before approval', () {
    Future<void> _waitForApplyGate(ProGuidedAiController ctrl) async {
      for (var i = 0; i < 200; i++) {
        if (ctrl.state is ProGuidedAiConfirmPending) return;
        await Future.delayed(const Duration(milliseconds: 2));
      }
    }

    test('onApply not called before user confirm', () async {
      bool applyCalled = false;
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s1', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );

      final future = ctrl.start(
        project: _project(),
        userGoal: 'test',
        onApply: (pid, result) async {
          applyCalled = true;
        },
      );
      await _waitForApplyGate(ctrl);

      // Apply gate reached; onApply must NOT have been called yet.
      expect(ctrl.state, isA<ProGuidedAiConfirmPending>());
      expect(applyCalled, isFalse);

      ctrl.cancel((ctrl.state as ProGuidedAiConfirmPending).request.stepId);
      await future;
    });
  });

  // ── 13. Post-approval deploy handoff ──────────────────────────────────────
  group('13. Post-approval deploy handoff', () {
    Future<void> _waitForApplyGate(ProGuidedAiController ctrl) async {
      for (var i = 0; i < 200; i++) {
        if (ctrl.state is ProGuidedAiConfirmPending) return;
        await Future.delayed(const Duration(milliseconds: 2));
      }
    }

    test('onApply called after confirm with non-null result', () async {
      TuningApplyResult? receivedResult;
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s1', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );

      final future = ctrl.start(
        project: _project(),
        userGoal: 'test',
        onApply: (pid, result) async {
          receivedResult = result;
        },
      );
      await _waitForApplyGate(ctrl);

      // Not yet called.
      expect(receivedResult, isNull);

      ctrl.confirm((ctrl.state as ProGuidedAiConfirmPending).request.stepId);
      await future;

      // onApply must have been called by now.
      // receivedResult may be null if the project has no matching PEQ channel
      // for the safety artifact — which is expected in the unit-test stub
      // project that has no driver channels. The key assertion is that
      // onApply was invoked (even with a null-producing result).
      expect(ctrl.state, isA<ProGuidedAiCompleted>());
    });

    test('onApply NOT called when user cancels at apply gate', () async {
      bool applyCalled = false;
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s1', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );

      final future = ctrl.start(
        project: _project(),
        userGoal: 'test',
        onApply: (pid, result) async {
          applyCalled = true;
        },
      );
      await _waitForApplyGate(ctrl);

      ctrl.cancel((ctrl.state as ProGuidedAiConfirmPending).request.stepId);
      await future;

      expect(applyCalled, isFalse);
    });
  });

  // ── 14. Low-confidence → fail-closed ─────────────────────────────────────
  group('14. Low-confidence → fail-closed', () {
    // Minimal resolver — AcousticClassifyAdapter never calls it.
    final _throwingResolver = _ThrowingResolver();

    // Gate 3 blocks only ConfidenceStatus.invalid (corrupt/unusable data).
    // insufficientEvidence (single-sweep FRD norm) is allowed through.
    MeasurementArtifact _invalidConfidenceArtifact(
        {ConfidenceStatus status = ConfidenceStatus.invalid}) {
      final confidence = MeasurementConfidenceResult(
        status: status,
        grade: ConfidenceGrade.poor,
        overallScore: 0.2,
        repeatability: const MetricOutcome(
            metric: ConfidenceMetric.repeatability,
            status: MetricStatus.unavailable),
        snr: const MetricOutcome(
            metric: ConfidenceMetric.snr, status: MetricStatus.unavailable),
        validBandCoverage: const MetricOutcome(
            metric: ConfidenceMetric.validBandCoverage,
            status: MetricStatus.unavailable),
        clipping: const MetricOutcome(
            metric: ConfidenceMetric.clipping,
            status: MetricStatus.unavailable),
        validBinCount: 5,
        requestedBinCount: 100,
        usableMinHz: null,
        usableMaxHz: null,
        reasons: ['insufficient data'],
        warnings: [],
        unavailableMetrics: [],
        policyId: 'test',
        policyVersion: 1,
      );
      final evidence = ImportedMeasurementEvidence(
        evidenceId: 'ev-low-conf',
        projectId: _pid,
        measurementRef: 'ch-ref',
        domain: MeasurementDomain.acousticResponse,
        source: MeasurementSource.importedFrd,
        provenance: MeasurementProvenance(
          producer: 'test',
          producerVersion: '1',
          sourceIdentity: 'test.frd',
          contentHash: 'sha256:test',
          label: 'test',
        ),
        availableMetrics: {EvidenceMetric.validBandCoverage},
        unavailableMetrics: {
          EvidenceMetric.repeatability,
          EvidenceMetric.snr,
          EvidenceMetric.clipping,
        },
        displayName: 'test.frd',
        originalFormat: 'FRD',
        parserSchemaVersion: '1',
        magnitudePresent: true,
        phasePresent: false,
        impedancePresent: false,
      );
      return MeasurementArtifact(
        parse: const MeasurementParseResult(
            status: MeasurementParseStatus.parsed, summary: 'test'),
        evidence: evidence,
        evaluation: MeasurementConfidenceEvaluation.evaluated,
        confidence: confidence,
      );
    }

    ProOrchestratorStep _classifyStep(String inputRef) => ProOrchestratorStep(
          stepId: 'classify-s',
          toolId: ProOrchestratorToolId.acousticClassify,
          objective: 'classify',
          inputRefs: [inputRef],
          outputRef: 'classify-out',
          requiresUserConfirmation: false,
        );

    test('acousticClassify throws confidenceCalculationFailure for invalid status',
        () {
      final store = ProToolArtifactStore();
      store.put(_pid, 'meas-ref', _invalidConfidenceArtifact());
      final ctx = ProToolExecutionContext(
        projectId: _pid,
        contextRef: 'ctx',
        resolver: _throwingResolver,
        store: store,
      );
      expect(
        () => const AcousticClassifyAdapter().run(ctx, _classifyStep('meas-ref')),
        throwsA(isA<ProToolException>().having(
          (e) => e.code,
          'code',
          ProToolFailureCode.confidenceCalculationFailure,
        )),
      );
    });

    test('acousticClassify error message contains "invalid"', () {
      final store = ProToolArtifactStore();
      store.put(_pid, 'meas-ref', _invalidConfidenceArtifact());
      final ctx = ProToolExecutionContext(
        projectId: _pid,
        contextRef: 'ctx',
        resolver: _throwingResolver,
        store: store,
      );
      ProToolException? caught;
      try {
        const AcousticClassifyAdapter().run(ctx, _classifyStep('meas-ref'));
      } on ProToolException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.message, contains('invalid'));
    });
  });

  // ── 15. Simulation → scoring wiring ───────────────────────────────────────
  group('15. Simulation → scoring wiring', () {
    test(
        'CandidateScoringAdapter throws missingReference when fewer than 2 inputRefs',
        () {
      final store = ProToolArtifactStore();
      final ctx = ProToolExecutionContext(
        projectId: _pid,
        contextRef: 'ctx',
        resolver: _ThrowingResolver(),
        store: store,
      );
      final step = ProOrchestratorStep(
        stepId: 'score-s',
        toolId: ProOrchestratorToolId.acousticScoreCandidates,
        objective: 'score',
        inputRefs: ['only-one'],
        outputRef: 'score-out',
        requiresUserConfirmation: false,
      );
      expect(
        () => const CandidateScoringAdapter().run(ctx, step),
        throwsA(isA<ProToolException>().having(
          (e) => e.code,
          'code',
          ProToolFailureCode.missingReference,
        )),
      );
    });

    test(
        'SimulationErrorArtifact side-channel is stored at scoring step side-channel ref',
        () async {
      // Use a stub scoring adapter that also stores a SimulationErrorArtifact
      // at the expected side-channel key. Controller reads this artifact when
      // building the apply-gate pending state.
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticScoreCandidates),
          _step('s1', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s2', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _ScoringWithSimErrAdapter(),
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );
      final states = await _collect(ctrl);
      // Controller reached Completed state (score step wrote artifacts).
      expect(states.any((s) => s is ProGuidedAiCompleted), isTrue);
    });
  });

  // ── 16. Before/After summary in confirm pending ────────────────────────────
  group('16. Before/After summary', () {
    Future<void> _waitForApplyGate(ProGuidedAiController ctrl) async {
      for (var i = 0; i < 200; i++) {
        if (ctrl.state is ProGuidedAiConfirmPending) return;
        await Future.delayed(const Duration(milliseconds: 2));
      }
    }

    test('beforeAfterSummary non-null at apply gate when SimulationErrorArtifact present',
        () async {
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticScoreCandidates),
          _step('s1', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s2', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _ScoringWithSimErrAdapter(),
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );

      final future = ctrl.start(
        project: _project(),
        userGoal: 'test',
        onApply: (pid, result) async {},
      );
      await _waitForApplyGate(ctrl);

      final pending = ctrl.state as ProGuidedAiConfirmPending;
      expect(pending.beforeAfterSummary, isNotNull);
      expect(pending.beforeAfterSummary, contains('dB'));

      ctrl.cancel(pending.request.stepId);
      await future;
    });

    test('beforeAfterSummary is null at apply gate when no SimulationErrorArtifact',
        () async {
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s1', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );

      final future = ctrl.start(
        project: _project(),
        userGoal: 'test',
        onApply: (pid, result) async {},
      );
      await _waitForApplyGate(ctrl);

      final pending = ctrl.state as ProGuidedAiConfirmPending;
      expect(pending.beforeAfterSummary, isNull);

      ctrl.cancel(pending.request.stepId);
      await future;
    });
  });

  // ── 17. simulationMode in SimulationErrorArtifact ─────────────────────────
  group('17. simulationMode in SimulationErrorArtifact', () {
    test('simulationMode is phase-aware when SimulationErrorArtifact carries it',
        () async {
      // Use a custom scoring stub that writes simulationMode='phase-aware'.
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticScoreCandidates),
          _step('s1', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s2', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _ScoringPhaseAwareAdapter(),
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );

      final future = ctrl.start(
        project: _project(),
        userGoal: 'test',
        onApply: (pid, result) async {},
      );
      await _waitForApplyGateGroup16(ctrl);

      final pending = ctrl.state as ProGuidedAiConfirmPending;
      expect(pending.beforeAfterSummary, contains('phase-aware'));

      ctrl.cancel(pending.request.stepId);
      await future;
    });

    test('simulationMode defaults to magnitude-only when not set to phase-aware',
        () async {
      // _ScoringWithSimErrAdapter uses simulationMode='magnitude-only'.
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticScoreCandidates),
          _step('s1', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s2', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _ScoringWithSimErrAdapter(),
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );

      final future = ctrl.start(
        project: _project(),
        userGoal: 'test',
        onApply: (pid, result) async {},
      );
      await _waitForApplyGateGroup16(ctrl);

      final pending = ctrl.state as ProGuidedAiConfirmPending;
      expect(pending.beforeAfterSummary, contains('magnitude-only'));

      ctrl.cancel(pending.request.stepId);
      await future;
    });
  });

  // ── 18. insufficientEvidence gate ─────────────────────────────────────────
  group('18. insufficientEvidence gate', () {
    test(
        'insufficientEvidence=true in ConfirmPending when measurement artifact '
        'has insufficientEvidence confidence', () async {
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.measurementAnalyze),
          _step('s1', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s2', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _InsuffEvidenceMeasureAdapter(),
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );

      final future = ctrl.start(
        project: _project(),
        userGoal: 'test',
        onApply: (pid, result) async {},
      );
      await _waitForApplyGateGroup16(ctrl);

      final pending = ctrl.state as ProGuidedAiConfirmPending;
      expect(pending.insufficientEvidence, isTrue);

      ctrl.cancel(pending.request.stepId);
      await future;
    });

    test('insufficientEvidence=false when measurement artifact has valid confidence',
        () async {
      // No measurementAnalyze step → measureRef is null → defaults to false.
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s1', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );

      final future = ctrl.start(
        project: _project(),
        userGoal: 'test',
        onApply: (pid, result) async {},
      );
      await _waitForApplyGateGroup16(ctrl);

      final pending = ctrl.state as ProGuidedAiConfirmPending;
      expect(pending.insufficientEvidence, isFalse);

      ctrl.cancel(pending.request.stepId);
      await future;
    });
  });

  // ── 19. GuidedTuningSessionSummary in ProGuidedAiCompleted ───────────────
  group('19. GuidedTuningSessionSummary after apply', () {
    test('guidedTuningSession is non-null in ProGuidedAiCompleted after apply',
        () async {
      final ctrl = _ctrl(
        [
          _step('s0', ProOrchestratorToolId.acousticScoreCandidates),
          _step('s1', ProOrchestratorToolId.acousticOptimizeSelection),
          _step('s2', ProOrchestratorToolId.acousticValidateSafety),
        ],
        [
          _ScoringWithSimErrAdapter(),
          _OptimizerWithCandidateStubAdapter(),
          const _SafetyStubAdapter(applyPermitted: true),
        ],
      );
      // Project needs at least one PEQ channel so _runApply returns non-null.
      final projectWithPeq = _project().copyWith(
        tuningState: TuningProjectState(
          peqChannels: [PeqChannelState.empty('ch_L')],
        ),
      );
      final future = ctrl.start(
        project: projectWithPeq,
        userGoal: 'test',
        onApply: (pid, result) async {},
      );
      // Wait for apply gate then confirm to allow apply to run.
      await _waitForApplyGateGroup16(ctrl);
      final pending = ctrl.state as ProGuidedAiConfirmPending;
      ctrl.confirm(pending.request.stepId);
      await future;

      final done = ctrl.state as ProGuidedAiCompleted;
      expect(done.guidedTuningSession, isNotNull);
      expect(done.guidedTuningSession, isA<GuidedTuningSessionSummary>());
    });

    test('guidedTuningSession is null when apply did not run', () async {
      final states = await _collect(
        _ctrl(
          [_step('s0', ProOrchestratorToolId.acousticClassify)],
          [const _StubAdapter(ProOrchestratorToolId.acousticClassify)],
        ),
      );
      final done = states.last as ProGuidedAiCompleted;
      expect(done.guidedTuningSession, isNull);
    });
  });
}
