import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/orchestrator/pro_acoustic_intent.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrate_request.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_context.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

ProAcousticIntent _intent() => const ProAcousticIntent(
      userGoal: 'tighter low end',
      perceivedProblem: 'boomy near wall',
      systemScope: 'full_system',
      tuningPriority: ProTuningPriority.balanced,
      allowedChangeAreas: [ProToneArea.lowEnd],
      protectedAreas: [ProToneArea.highEnd],
      listeningContext: 'near-field desk',
      explanationLevel: ProExplanationLevel.intermediate,
    );

ProOrchestratorContext _context({String projectId = 'p1'}) =>
    ProOrchestratorContext(
      projectId: projectId,
      connectionState: ProConnectionState.disconnected,
    );

ProOrchestrateRequest _request({String projectId = 'p1'}) =>
    ProOrchestrateRequest(
      projectId: projectId,
      intent: _intent(),
      context: _context(projectId: projectId),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('round-trip', () {
    test('fromJson(toJson()) preserves projectId', () {
      final r = _request();
      final parsed = ProOrchestrateRequest.fromJson(r.toJson());
      expect(parsed.projectId, r.projectId);
    });

    test('fromJson(toJson()) preserves intent.userGoal', () {
      final r = _request();
      final parsed = ProOrchestrateRequest.fromJson(r.toJson());
      expect(parsed.intent.userGoal, r.intent.userGoal);
    });

    test('fromJson(toJson()) preserves intent.tuningPriority', () {
      final r = _request();
      final parsed = ProOrchestrateRequest.fromJson(r.toJson());
      expect(parsed.intent.tuningPriority, r.intent.tuningPriority);
    });

    test('fromJson(toJson()) preserves context.connectionState', () {
      final r = _request();
      final parsed = ProOrchestrateRequest.fromJson(r.toJson());
      expect(parsed.context.connectionState, r.context.connectionState);
    });

    test('fromJson(toJson()) preserves allowedChangeAreas', () {
      final r = _request();
      final parsed = ProOrchestrateRequest.fromJson(r.toJson());
      expect(parsed.intent.allowedChangeAreas, r.intent.allowedChangeAreas);
    });
  });

  group('schemaVersion', () {
    test('wrong schemaVersion throws ProContractException', () {
      final json = _request().toJson();
      json['schemaVersion'] = 99;
      expect(
        () => ProOrchestrateRequest.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });

    test('missing schemaVersion throws ProContractException', () {
      final json = _request().toJson()..remove('schemaVersion');
      expect(
        () => ProOrchestrateRequest.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });
  });

  group('projectId invariant', () {
    test('projectId != context.projectId throws ProContractException', () {
      final json = _request(projectId: 'p1').toJson();
      json['projectId'] = 'p999'; // override top-level, context still has p1
      expect(
        () => ProOrchestrateRequest.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });

    test('error message names both conflicting project ids', () {
      final json = _request(projectId: 'p1').toJson();
      json['projectId'] = 'p999';
      expect(
        () => ProOrchestrateRequest.fromJson(json),
        throwsA(predicate<ProContractException>(
            (e) => e.message.contains('p1') && e.message.contains('p999'))),
      );
    });
  });

  group('forbidden DSP keys', () {
    test('gainDb at top level throws ProContractException', () {
      final json = _request().toJson();
      json['gainDb'] = 0.0;
      expect(
        () => ProOrchestrateRequest.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });

    test('frequency at top level throws ProContractException', () {
      final json = _request().toJson();
      json['frequency'] = 1000.0;
      expect(
        () => ProOrchestrateRequest.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });

    test('unknown key throws ProContractException', () {
      final json = _request().toJson();
      json['unexpectedField'] = 'x';
      expect(
        () => ProOrchestrateRequest.fromJson(json),
        throwsA(isA<ProContractException>()),
      );
    });
  });

  group('determinism', () {
    test('toJson produces identical output on two calls', () {
      final j1 = _request().toJson();
      final j2 = _request().toJson();
      expect(jsonEncode(j1), jsonEncode(j2));
    });

    test('toJson output contains no DSP keys at top level', () {
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
