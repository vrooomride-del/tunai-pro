import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_response.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _planId = 'plan-1';
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
      planId: _planId,
      intentRef: 'intent-ref',
      contextRef: 'ctx-ref',
      steps: [_step()],
    );

ProExplanation _explanation() => const ProExplanation(
      title: 'Plan explanation',
      summary: 'This plan classifies speaker drivers.',
      explanationLevel: ProExplanationLevel.intermediate,
    );

ProOrchestrateResponse _response({String projectId = _projectId}) =>
    ProOrchestrateResponse(
      projectId: projectId,
      plan: _plan(),
      explanation: _explanation(),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('round-trip', () {
    test('fromJson(toJson()) preserves projectId', () {
      final r = _response();
      final parsed = ProOrchestrateResponse.fromJson(r.toJson());
      expect(parsed.projectId, r.projectId);
    });

    test('fromJson(toJson()) preserves plan.planId', () {
      final r = _response();
      final parsed = ProOrchestrateResponse.fromJson(r.toJson());
      expect(parsed.plan.planId, r.plan.planId);
    });

    test('fromJson(toJson()) preserves plan step toolId', () {
      final r = _response();
      final parsed = ProOrchestrateResponse.fromJson(r.toJson());
      expect(parsed.plan.steps.single.toolId,
          ProOrchestratorToolId.acousticClassify);
    });

    test('fromJson(toJson()) preserves explanation.title', () {
      final r = _response();
      final parsed = ProOrchestrateResponse.fromJson(r.toJson());
      expect(parsed.explanation.title, r.explanation.title);
    });

    test('fromJson(toJson()) preserves explanation.explanationLevel', () {
      final r = _response();
      final parsed = ProOrchestrateResponse.fromJson(r.toJson());
      expect(
          parsed.explanation.explanationLevel, r.explanation.explanationLevel);
    });
  });

  group('requestProjectId', () {
    test('fromJson without requestProjectId succeeds', () {
      final json = _response().toJson();
      final parsed = ProOrchestrateResponse.fromJson(json);
      expect(parsed.projectId, _projectId);
    });

    test('fromJson with matching requestProjectId succeeds', () {
      final json = _response().toJson();
      final parsed =
          ProOrchestrateResponse.fromJson(json, requestProjectId: _projectId);
      expect(parsed.projectId, _projectId);
    });

    test('fromJson with mismatched requestProjectId throws', () {
      final json = _response(projectId: _projectId).toJson();
      expect(
        () => ProOrchestrateResponse.fromJson(json, requestProjectId: 'p999'),
        throwsA(isA<ProContractException>()),
      );
    });

    test('mismatch error message names both project ids', () {
      final json = _response(projectId: _projectId).toJson();
      expect(
        () => ProOrchestrateResponse.fromJson(json, requestProjectId: 'p999'),
        throwsA(predicate<ProContractException>((e) =>
            e.message.contains(_projectId) && e.message.contains('p999'))),
      );
    });
  });

  group('schemaVersion', () {
    test('wrong schemaVersion throws ProContractException', () {
      final json = _response().toJson();
      json['schemaVersion'] = 99;
      expect(
        () => ProOrchestrateResponse.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });

    test('missing schemaVersion throws ProContractException', () {
      final json = _response().toJson()..remove('schemaVersion');
      expect(
        () => ProOrchestrateResponse.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });
  });

  group('plan validation', () {
    test('empty steps list in plan throws ProContractException', () {
      final json = _response().toJson();
      (json['plan'] as Map<String, dynamic>)['steps'] = <dynamic>[];
      expect(
        () => ProOrchestrateResponse.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });

    test('duplicate stepId in plan throws ProContractException', () {
      final json = _response().toJson();
      final stepJson = Map<String, dynamic>.from(
          (_step().toJson())..['outputRef'] = 'dup-output');
      (json['plan'] as Map<String, dynamic>)['steps'] = [
        _step().toJson(),
        stepJson,
      ];
      expect(
        () => ProOrchestrateResponse.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });
  });

  group('forbidden DSP keys', () {
    test('gainDb at top level throws ProContractException', () {
      final json = _response().toJson();
      json['gainDb'] = 0.0;
      expect(
        () => ProOrchestrateResponse.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });

    test('unknown key throws ProContractException', () {
      final json = _response().toJson();
      json['extraField'] = 'x';
      expect(
        () => ProOrchestrateResponse.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });
  });

  group('determinism', () {
    test('toJson produces identical output on two calls', () {
      final j1 = _response().toJson();
      final j2 = _response().toJson();
      expect(jsonEncode(j1), jsonEncode(j2));
    });

    test('toJson top-level keys contain no DSP values', () {
      final keys = _response().toJson().keys.toSet();
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
