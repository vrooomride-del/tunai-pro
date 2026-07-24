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

// ── Dio stubs (interceptors, no real HTTP) ────────────────────────────────────

/// Resolves every request with [data] as the response body.
class _SuccessInterceptor extends Interceptor {
  final Map<String, dynamic> data;
  _SuccessInterceptor(this.data);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handler.resolve(
          Response(requestOptions: options, data: data, statusCode: 200));
}

/// Rejects every request with a connection-level DioException.
class _NetworkErrorInterceptor extends Interceptor {
  final String message;
  _NetworkErrorInterceptor(this.message);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handler.reject(DioException(
        requestOptions: options,
        message: message,
        type: DioExceptionType.connectionError,
      ));
}

/// Rejects with a server-side 500 that carries an 'error' field.
class _ServerErrorInterceptor extends Interceptor {
  final String errorMessage;
  _ServerErrorInterceptor(this.errorMessage);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handler.reject(DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 500,
          data: {'error': errorMessage},
        ),
        type: DioExceptionType.badResponse,
      ));
}

Dio _stubDio(Map<String, dynamic> data) =>
    Dio()..interceptors.add(_SuccessInterceptor(data));

Dio _networkErrorDio(String msg) =>
    Dio()..interceptors.add(_NetworkErrorInterceptor(msg));

Dio _serverErrorDio(String errorMsg) =>
    Dio()..interceptors.add(_ServerErrorInterceptor(errorMsg));

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _projectId = 'p1';

ProOrchestratorStep _step() => const ProOrchestratorStep(
      stepId: 's0',
      toolId: ProOrchestratorToolId.acousticClassify,
      objective: 'classify drivers',
      inputRefs: ['m0'],
      outputRef: 'classification-0',
      requiresUserConfirmation: false,
    );

ProOrchestratorPlan _plan() => ProOrchestratorPlan(
      planId: 'plan-1',
      intentRef: 'intent-ref',
      contextRef: 'ctx-ref',
      steps: [_step()],
    );

ProExplanation _explanation() => const ProExplanation(
      title: 'Plan explanation',
      summary: 'Classify drivers first.',
      explanationLevel: ProExplanationLevel.intermediate,
    );

ProOrchestrateResponse _response({String projectId = _projectId}) =>
    ProOrchestrateResponse(
      projectId: projectId,
      plan: _plan(),
      explanation: _explanation(),
    );

/// Wraps [response] in the Cloud Function envelope: { result: { ... } }.
Map<String, dynamic> _envelope(ProOrchestrateResponse response) =>
    {'result': response.toJson()};

ProOrchestrateRequest _request({String projectId = _projectId}) =>
    ProOrchestrateRequest(
      projectId: projectId,
      intent: const ProAcousticIntent(
        userGoal: 'tighter low end',
        perceivedProblem: 'boomy near wall',
        systemScope: 'full_system',
        tuningPriority: ProTuningPriority.balanced,
        allowedChangeAreas: [ProToneArea.lowEnd],
        protectedAreas: [ProToneArea.highEnd],
        listeningContext: 'near-field desk',
        explanationLevel: ProExplanationLevel.intermediate,
      ),
      context: ProOrchestratorContext(
        projectId: projectId,
        connectionState: ProConnectionState.disconnected,
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('success response parsing', () {
    test('valid envelope returns ProOrchestrateSuccess', () async {
      final service =
          ProOrchestrateService(dio: _stubDio(_envelope(_response())));
      final outcome = await service.call(_request());
      expect(outcome, isA<ProOrchestrateSuccess>());
    });

    test('success response carries correct projectId', () async {
      final service =
          ProOrchestrateService(dio: _stubDio(_envelope(_response())));
      final outcome = await service.call(_request());
      final resp = (outcome as ProOrchestrateSuccess).response;
      expect(resp.projectId, _projectId);
    });

    test('success response preserves plan planId', () async {
      final service =
          ProOrchestrateService(dio: _stubDio(_envelope(_response())));
      final outcome = await service.call(_request());
      final resp = (outcome as ProOrchestrateSuccess).response;
      expect(resp.plan.planId, 'plan-1');
    });

    test('success response preserves plan step toolId', () async {
      final service =
          ProOrchestrateService(dio: _stubDio(_envelope(_response())));
      final outcome = await service.call(_request());
      final resp = (outcome as ProOrchestrateSuccess).response;
      expect(resp.plan.steps.single.toolId,
          ProOrchestratorToolId.acousticClassify);
    });
  });

  group('contract rejection', () {
    test('gainDb in result envelope returns ProOrchestrateFailure', () async {
      final badEnvelope = {
        'result': {..._response().toJson(), 'gainDb': 0.0},
      };
      final service = ProOrchestrateService(dio: _stubDio(badEnvelope));
      final outcome = await service.call(_request());
      expect(outcome, isA<ProOrchestrateFailure>());
    });

    test('forbidden DSP key in plan returns ProOrchestrateFailure', () async {
      final planJson = _plan().toJson();
      (planJson['steps'] as List).first['frequency'] = 1000.0;
      final badEnvelope = {
        'result': {
          ..._response().toJson(),
          'plan': planJson,
        },
      };
      final service = ProOrchestrateService(dio: _stubDio(badEnvelope));
      final outcome = await service.call(_request());
      expect(outcome, isA<ProOrchestrateFailure>());
    });

    test('wrong schemaVersion in result returns ProOrchestrateFailure',
        () async {
      final badEnvelope = {
        'result': {..._response().toJson(), 'schemaVersion': 99},
      };
      final service = ProOrchestrateService(dio: _stubDio(badEnvelope));
      final outcome = await service.call(_request());
      expect(outcome, isA<ProOrchestrateFailure>());
    });

    test('projectId mismatch in response returns ProOrchestrateFailure',
        () async {
      // Cloud returns p999 but request says p1.
      final mismatchEnvelope = _envelope(_response(projectId: 'p999'));
      final service = ProOrchestrateService(dio: _stubDio(mismatchEnvelope));
      final outcome = await service.call(_request(projectId: _projectId));
      expect(outcome, isA<ProOrchestrateFailure>());
    });

    test('missing result field returns ProOrchestrateFailure', () async {
      final service = ProOrchestrateService(
          dio: _stubDio({'status': 'ok'})); // no 'result' key
      final outcome = await service.call(_request());
      expect(outcome, isA<ProOrchestrateFailure>());
    });
  });

  group('failure mapping', () {
    test('connection error returns ProOrchestrateFailure', () async {
      final service =
          ProOrchestrateService(dio: _networkErrorDio('Connection refused'));
      final outcome = await service.call(_request());
      expect(outcome, isA<ProOrchestrateFailure>());
    });

    test('DioException message is preserved in ProOrchestrateFailure',
        () async {
      final service =
          ProOrchestrateService(dio: _networkErrorDio('Connection refused'));
      final outcome = await service.call(_request());
      expect((outcome as ProOrchestrateFailure).message,
          contains('Connection refused'));
    });

    test('server error field is surfaced in ProOrchestrateFailure', () async {
      final service =
          ProOrchestrateService(dio: _serverErrorDio('quota exceeded'));
      final outcome = await service.call(_request());
      expect((outcome as ProOrchestrateFailure).message,
          contains('quota exceeded'));
    });
  });

  group('deterministic JSON', () {
    test('request toJson produces identical output on two calls', () {
      final j1 = _request().toJson();
      final j2 = _request().toJson();
      expect(jsonEncode(j1), jsonEncode(j2));
    });

    test('request toJson contains no DSP keys', () {
      final keys = _request().toJson().keys.toSet();
      const dspKeys = {
        'frequency',
        'gainDb',
        'q',
        'delay',
        'coefficient',
        'address',
        'payload',
        'biquad'
      };
      expect(keys.intersection(dspKeys), isEmpty);
    });
  });
}
