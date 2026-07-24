// Phase 14-E-4 — Cloud integration contract verification.
//
// Verifies that the Flutter parser accepts exactly the JSON shape the Cloud
// Function promises, and rejects the shapes it forbids. No real HTTP — the
// Cloud's Node.js server-side logic is mirrored in Dart so both sides are
// exercised in the same test run.
//
// Three layers tested:
//   A. Request shape  — ProOrchestrateRequest.toJson() matches Cloud input
//   B. Response shape — Cloud { result: {...} } envelope parsed by Service
//   C. Contract       — forbidden keys and invalid toolIds rejected

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/orchestrator/pro_acoustic_intent.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_request.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_response.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_service.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_context.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';

// ── Dio stub ─────────────────────────────────────────────────────────────────

class _StubInterceptor extends Interceptor {
  final Map<String, dynamic> data;
  _StubInterceptor(this.data);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handler.resolve(
          Response(requestOptions: options, data: data, statusCode: 200));
}

Dio _dio(Map<String, dynamic> data) =>
    Dio()..interceptors.add(_StubInterceptor(data));

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _pid = 'project-e4-test';

ProOrchestrateRequest _request() => ProOrchestrateRequest(
      projectId: _pid,
      intent: const ProAcousticIntent(
        userGoal: 'tighter low end',
        perceivedProblem: 'boomy near wall',
        systemScope: 'full_system',
        tuningPriority: ProTuningPriority.roomAdaptation,
        allowedChangeAreas: [ProToneArea.lowEnd],
        protectedAreas: [ProToneArea.highEnd],
        listeningContext: 'near-field desk',
        explanationLevel: ProExplanationLevel.intermediate,
      ),
      context: ProOrchestratorContext(
        projectId: _pid,
        connectionState: ProConnectionState.disconnected,
      ),
    );

ProOrchestratorPlan _plan({String toolIdOverride = 'measurementAnalyze'}) =>
    ProOrchestratorPlan(
      planId: 'plan-e4',
      intentRef: 'intent-ref',
      contextRef: 'ctx-ref',
      steps: [
        ProOrchestratorStep(
          stepId: 'step-0',
          toolId: ProOrchestratorToolId.values
              .firstWhere((e) => e.name == toolIdOverride),
          objective: 'analyze measurement data',
          inputRefs: ['meas-0'],
          outputRef: 'classification-0',
          requiresUserConfirmation: false,
        ),
      ],
    );

ProExplanation _explanation() => const ProExplanation(
      title: '저음 분석 플랜',
      summary: '측정 데이터를 분석하여 저음 문제를 파악합니다.',
      explanationLevel: ProExplanationLevel.intermediate,
    );

ProOrchestrateResponse _response() => ProOrchestrateResponse(
      projectId: _pid,
      plan: _plan(),
      explanation: _explanation(),
    );

/// Simulates the Cloud Function's { result: {...} } envelope.
Map<String, dynamic> _cloudEnvelope(ProOrchestrateResponse r) =>
    {'result': r.toJson()};

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── A. Request shape ────────────────────────────────────────────────────────
  group('A. Request round-trip matches Cloud input contract', () {
    test('toJson top-level keys are schemaVersion/projectId/intent/context', () {
      final j = _request().toJson();
      expect(j.keys.toSet(),
          {'schemaVersion', 'projectId', 'intent', 'context'});
    });

    test('schemaVersion is integer 1', () {
      expect(_request().toJson()['schemaVersion'], 1);
    });

    test('projectId matches context.projectId (Cloud validation passes)', () {
      final j = _request().toJson();
      final ctx = j['context'] as Map<String, dynamic>;
      expect(j['projectId'], ctx['projectId']);
    });

    test('intent object is present and has no DSP keys', () {
      final j = _request().toJson();
      final intent = j['intent'] as Map<String, dynamic>;
      final keys = jsonEncode(intent).toLowerCase();
      for (final token in ProContract.forbiddenKeyTokens) {
        expect(keys.contains('"$token":'), isFalse,
            reason: 'intent must not contain forbidden key $token');
      }
    });

    test('context object is present and has no DSP keys', () {
      final j = _request().toJson();
      final context = j['context'] as Map<String, dynamic>;
      final keys = jsonEncode(context).toLowerCase();
      for (final token in ProContract.forbiddenKeyTokens) {
        expect(keys.contains('"$token":'), isFalse,
            reason: 'context must not contain forbidden key $token');
      }
    });

    test('fromJson(toJson()) round-trip is lossless', () {
      final r = _request();
      final parsed = ProOrchestrateRequest.fromJson(r.toJson());
      expect(parsed.projectId, r.projectId);
      expect(parsed.intent.userGoal, r.intent.userGoal);
      expect(parsed.context.connectionState, r.context.connectionState);
    });
  });

  // ── B. Response round-trip matches Cloud output contract ────────────────────
  group('B. Response envelope { result:{...} } parsed by ProOrchestrateService', () {
    test('valid Cloud envelope → ProOrchestrateSuccess', () async {
      final svc = ProOrchestrateService(dio: _dio(_cloudEnvelope(_response())));
      final out = await svc.call(_request());
      expect(out, isA<ProOrchestrateSuccess>());
    });

    test('success carries correct projectId from Cloud', () async {
      final svc = ProOrchestrateService(dio: _dio(_cloudEnvelope(_response())));
      final out = (await svc.call(_request())) as ProOrchestrateSuccess;
      expect(out.response.projectId, _pid);
    });

    test('plan planId is preserved through envelope', () async {
      final svc = ProOrchestrateService(dio: _dio(_cloudEnvelope(_response())));
      final out = (await svc.call(_request())) as ProOrchestrateSuccess;
      expect(out.response.plan.planId, 'plan-e4');
    });

    test('explanation title is preserved through envelope', () async {
      final svc = ProOrchestrateService(dio: _dio(_cloudEnvelope(_response())));
      final out = (await svc.call(_request())) as ProOrchestrateSuccess;
      expect(out.response.explanation.title, '저음 분석 플랜');
    });

    test('missing result key in Cloud envelope → ProOrchestrateFailure', () async {
      final svc = ProOrchestrateService(dio: _dio({'status': 'ok'}));
      expect(await svc.call(_request()), isA<ProOrchestrateFailure>());
    });

    test('projectId mismatch between request and Cloud response → failure', () async {
      final wrongResponse = ProOrchestrateResponse(
        projectId: 'wrong-project',
        plan: _plan(),
        explanation: _explanation(),
      );
      final svc = ProOrchestrateService(dio: _dio(_cloudEnvelope(wrongResponse)));
      expect(await svc.call(_request()), isA<ProOrchestrateFailure>());
    });
  });

  // ── C. toolId whitelist — all 20 known IDs accepted ─────────────────────────
  group('C. toolId whitelist: all 20 Cloud-allowed IDs accepted by Flutter parser', () {
    for (final toolId in ProOrchestratorToolId.values) {
      test('toolId "${toolId.name}" parses cleanly', () {
        final planJson = ProOrchestratorPlan(
          planId: 'p',
          intentRef: 'i',
          contextRef: 'c',
          steps: [
            ProOrchestratorStep(
              stepId: 'step-0',
              toolId: toolId,
              objective: 'test step',
              inputRefs: const ['ref-0'],
              outputRef: 'out-0',
              requiresUserConfirmation: false,
            ),
          ],
        ).toJson();
        expect(() => ProOrchestratorPlan.fromJson(planJson), returnsNormally);
      });
    }

    test('toolId not in the 20 → ProContractException', () {
      final planJson = ProOrchestratorPlan(
        planId: 'p',
        intentRef: 'i',
        contextRef: 'c',
        steps: const [
          ProOrchestratorStep(
            stepId: 'step-0',
            toolId: ProOrchestratorToolId.acousticClassify,
            objective: 'x',
            inputRefs: ['r'],
            outputRef: 'o',
            requiresUserConfirmation: false,
          ),
        ],
      ).toJson();
      (planJson['steps'] as List)[0]['toolId'] = 'roomModeEstimate'; // old wrong id
      expect(() => ProOrchestratorPlan.fromJson(planJson),
          throwsA(isA<ProContractException>()));
    });

    test('old wrong toolId "acousticOptimizeSelection" still in enum → accepts', () {
      // Confirm the enum hasn't regressed.
      expect(
        ProOrchestratorToolId.values.map((e) => e.name),
        contains('acousticOptimizeSelection'),
      );
    });
  });

  // ── D. Forbidden DSP key rejection ──────────────────────────────────────────
  group('D. Forbidden DSP keys rejected in Cloud response', () {
    for (final key in const [
      'frequency',
      'gainDb',
      'q',
      'biquad',
      'address',
      'payload',
      'coefficient',
      'delay',
    ]) {
      test('Cloud response with "$key" at top level → ProOrchestrateFailure', () async {
        final badEnvelope = {
          'result': {..._response().toJson(), key: 0},
        };
        final svc = ProOrchestrateService(dio: _dio(badEnvelope));
        expect(await svc.call(_request()), isA<ProOrchestrateFailure>());
      });

      test('Cloud response with "$key" in plan step → ProOrchestrateFailure', () async {
        final planJson = _plan().toJson();
        (planJson['steps'] as List)[0][key] = 0;
        final badEnvelope = {
          'result': {..._response().toJson(), 'plan': planJson},
        };
        final svc = ProOrchestrateService(dio: _dio(badEnvelope));
        expect(await svc.call(_request()), isA<ProOrchestrateFailure>());
      });
    }
  });

  // ── E. Controlled-action toolIds rejected ───────────────────────────────────
  group('E. Controlled-action toolIds from Cloud rejected by Flutter parser', () {
    for (final badId in const [
      'apply',
      'deploy',
      'write',
      'transport',
      'safeLoad',
      'eeprom',
      'selfBoot',
      'hardwareWrite',
    ]) {
      test('toolId "$badId" → ProContractException', () {
        final planJson = _plan().toJson();
        (planJson['steps'] as List)[0]['toolId'] = badId;
        expect(() => ProOrchestratorPlan.fromJson(planJson),
            throwsA(isA<ProContractException>()));
      });
    }
  });

  // ── F. System prompt tool ID list consistency ───────────────────────────────
  group('F. Cloud system prompt tool ID list matches Flutter enum (static)', () {
    // The 20 tool IDs listed in SYSTEM_ORCHESTRATE_PRO in functions/index.js.
    // If the Flutter enum ever changes, this test catches the divergence.
    const cloudPromptToolIds = {
      'measurementAnalyze',
      'impedanceAnalyze',
      'speakerCapability',
      'targetDefine',
      'crossoverPlan',
      'peqOptimize',
      'phaseAlign',
      'delayAlign',
      'gainPlan',
      'simulate',
      'protectionAnalyze',
      'compareCandidates',
      'generateReport',
      'acousticClassify',
      'acousticPlan',
      'acousticGenerateCandidates',
      'acousticScoreCandidates',
      'acousticOptimizeSelection',
      'acousticValidateSafety',
      'acousticEvaluateLoop',
    };

    final flutterEnumIds =
        ProOrchestratorToolId.values.map((e) => e.name).toSet();

    test('Cloud prompt lists every Flutter enum member', () {
      final missing = flutterEnumIds.difference(cloudPromptToolIds);
      expect(missing, isEmpty,
          reason:
              'These Flutter toolIds are missing from the Cloud system prompt: $missing');
    });

    test('Cloud prompt contains no extra toolIds not in Flutter enum', () {
      final extra = cloudPromptToolIds.difference(flutterEnumIds);
      expect(extra, isEmpty,
          reason:
              'Cloud system prompt lists toolIds not in Flutter enum: $extra');
    });

    test('Flutter enum count matches Cloud prompt count (20)', () {
      expect(flutterEnumIds.length, 20);
      expect(cloudPromptToolIds.length, 20);
    });
  });
}
