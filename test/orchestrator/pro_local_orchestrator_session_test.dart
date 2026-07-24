import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_local_orchestrator_session.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

ProOrchestratorStep _step({
  String stepId = 'step-1',
  ProOrchestratorToolId toolId = ProOrchestratorToolId.acousticClassify,
  bool confirm = false,
}) =>
    ProOrchestratorStep(
      stepId: stepId,
      toolId: toolId,
      objective: 'test objective for $stepId',
      inputRefs: ['meas:1'],
      outputRef: 'out:$stepId',
      requiresUserConfirmation: confirm,
    );

ProOrchestratorPlan _plan({int numSteps = 2}) => ProOrchestratorPlan(
      planId: 'plan-test',
      intentRef: 'intent:1',
      contextRef: 'ctx:1',
      steps: [
        for (var i = 0; i < numSteps; i++)
          _step(
            stepId: 'step-$i',
            toolId: ProOrchestratorToolId.acousticClassify,
          )
      ],
    );

const _explanation = ProExplanation(
  title: 'Step Explanation',
  summary: 'This step classifies acoustic features.',
  explanationLevel: ProExplanationLevel.intermediate,
);

ProStepExecutionRecord _doneRecord({
  String stepId = 'step-1',
  String outputRef = 'class:1',
  int elapsedMs = 42,
}) =>
    ProStepExecutionRecord(
      stepId: stepId,
      toolId: ProOrchestratorToolId.acousticClassify,
      status: ProStepStatus.done,
      outputRef: outputRef,
      summary: 'classified 3 features',
      confidence: ProConfidence.high,
      elapsedMs: elapsedMs,
    );

ProStepExecutionRecord _failedRecord({
  String stepId = 'step-2',
}) =>
    ProStepExecutionRecord(
      stepId: stepId,
      toolId: ProOrchestratorToolId.acousticPlan,
      status: ProStepStatus.failed,
      outputRef: '',
      failureCode: 'engineError',
      failureMessage: 'engine threw unexpectedly',
      elapsedMs: 0,
    );

ProStepExecutionRecord _skippedRecord({String stepId = 'step-3'}) =>
    ProStepExecutionRecord(
      stepId: stepId,
      toolId: ProOrchestratorToolId.acousticGenerateCandidates,
      status: ProStepStatus.skipped,
      outputRef: '',
      elapsedMs: 0,
    );

void main() {
  // ── ProOrchestratorOutcomeStatus ─────────────────────────────────────────

  group('ProOrchestratorOutcomeStatus', () {
    test('all values roundtrip toJson/parse', () {
      for (final status in ProOrchestratorOutcomeStatus.values) {
        expect(
          ProOrchestratorOutcomeStatus.parse(status.toJson(), 'test'),
          status,
        );
      }
    });

    test('parse rejects a number (no numeric confidence smuggling)', () {
      expect(
        () => ProOrchestratorOutcomeStatus.parse(1, 'test'),
        throwsA(isA<ProContractException>()),
      );
    });

    test('parse rejects unknown string', () {
      expect(
        () => ProOrchestratorOutcomeStatus.parse('unknown', 'test'),
        throwsA(isA<ProContractException>()),
      );
    });
  });

  // ── ProStepExecutionRecord ────────────────────────────────────────────────

  group('ProStepExecutionRecord', () {
    test('done record roundtrip', () {
      final record = _doneRecord();
      final rt = ProStepExecutionRecord.fromJson(record.toJson(), 'test');
      expect(rt.stepId, record.stepId);
      expect(rt.toolId, record.toolId);
      expect(rt.status, ProStepStatus.done);
      expect(rt.outputRef, 'class:1');
      expect(rt.summary, 'classified 3 features');
      expect(rt.confidence, ProConfidence.high);
      expect(rt.elapsedMs, 42);
      expect(rt.failureCode, isNull);
      expect(rt.explanation, isNull);
    });

    test('failed record roundtrip', () {
      final record = _failedRecord();
      final rt = ProStepExecutionRecord.fromJson(record.toJson(), 'test');
      expect(rt.status, ProStepStatus.failed);
      expect(rt.outputRef, '');
      expect(rt.failureCode, 'engineError');
      expect(rt.failureMessage, 'engine threw unexpectedly');
      expect(rt.confidence, isNull);
    });

    test('skipped record roundtrip', () {
      final record = _skippedRecord();
      final rt = ProStepExecutionRecord.fromJson(record.toJson(), 'test');
      expect(rt.status, ProStepStatus.skipped);
      expect(rt.outputRef, '');
      expect(rt.elapsedMs, 0);
    });

    test('record with explanation roundtrip', () {
      const record = ProStepExecutionRecord(
        stepId: 'step-1',
        toolId: ProOrchestratorToolId.acousticClassify,
        status: ProStepStatus.done,
        outputRef: 'class:1',
        explanation: _explanation,
        elapsedMs: 10,
      );
      final rt = ProStepExecutionRecord.fromJson(record.toJson(), 'test');
      expect(rt.explanation, isNotNull);
      expect(rt.explanation!.title, 'Step Explanation');
      expect(
          rt.explanation!.explanationLevel, ProExplanationLevel.intermediate);
    });

    test('toJson has no forbidden DSP keys', () {
      final j = _doneRecord().toJson();
      for (final key in [
        'frequency',
        'frequencyHz',
        'gain',
        'gainDb',
        'q',
        'biquad',
        'address',
        'payload',
        'register',
        'coefficients',
      ]) {
        expect(j.containsKey(key), isFalse, reason: 'forbidden key: $key');
      }
    });

    test('outputRef is an opaque string, not a numeric value', () {
      final record = _doneRecord(outputRef: 'class:out-1');
      expect(record.toJson()['outputRef'], isA<String>());
      expect(record.toJson()['outputRef'], isNot(isA<num>()));
    });

    test('fromJson rejects unknown key', () {
      final j = _doneRecord().toJson()..['unknown'] = 'x';
      expect(
        () => ProStepExecutionRecord.fromJson(j, 'test'),
        throwsA(isA<ProContractException>()),
      );
    });

    test('fromJson rejects DSP key gainDb', () {
      final j = _doneRecord().toJson()..['gainDb'] = -3.0;
      expect(
        () => ProStepExecutionRecord.fromJson(j, 'test'),
        throwsA(isA<ProContractException>()),
      );
    });

    test('fromJson rejects non-int elapsedMs', () {
      final j = _doneRecord().toJson()..['elapsedMs'] = '42';
      expect(
        () => ProStepExecutionRecord.fromJson(j, 'test'),
        throwsA(isA<ProContractException>()),
      );
    });

    test('deterministic JSON — same input same output', () {
      final r1 = _doneRecord().toJson();
      final r2 = _doneRecord().toJson();
      expect(r1, r2);
    });
  });

  // ── ProUserConfirmationRequest ────────────────────────────────────────────

  group('ProUserConfirmationRequest', () {
    ProUserConfirmationRequest request() => const ProUserConfirmationRequest(
          stepId: 'step-1',
          toolId: ProOrchestratorToolId.acousticPlan,
          objective: 'plan acoustic corrections',
          explanation: _explanation,
        );

    test('roundtrip', () {
      final req = request();
      final rt = ProUserConfirmationRequest.fromJson(req.toJson());
      expect(rt.stepId, 'step-1');
      expect(rt.toolId, ProOrchestratorToolId.acousticPlan);
      expect(rt.objective, 'plan acoustic corrections');
      expect(rt.requiresUserConfirmation, isTrue);
      expect(rt.explanation.title, 'Step Explanation');
      expect(rt.schemaVersion, kProOrchestratorSchemaVersion);
    });

    test('requiresUserConfirmation is bool in JSON, not number', () {
      final j = request().toJson();
      expect(j['requiresUserConfirmation'], isA<bool>());
      expect(j['requiresUserConfirmation'], isNot(isA<num>()));
    });

    test('toJson has no forbidden DSP keys', () {
      final j = request().toJson();
      for (final key in [
        'frequency',
        'gainDb',
        'q',
        'biquad',
        'address',
        'coefficients',
      ]) {
        expect(j.containsKey(key), isFalse, reason: 'forbidden key: $key');
      }
    });

    test('fromJson rejects unknown key', () {
      final j = request().toJson()..['extra'] = 'x';
      expect(
        () => ProUserConfirmationRequest.fromJson(j),
        throwsA(isA<ProContractException>()),
      );
    });

    test('fromJson rejects DSP key', () {
      final j = request().toJson()..['frequency'] = 1000.0;
      expect(
        () => ProUserConfirmationRequest.fromJson(j),
        throwsA(isA<ProContractException>()),
      );
    });

    test('fromJson rejects wrong schemaVersion', () {
      final j = request().toJson()..['schemaVersion'] = 99;
      expect(
        () => ProUserConfirmationRequest.fromJson(j),
        throwsA(isA<ProContractException>()),
      );
    });

    test('deterministic JSON', () {
      expect(request().toJson(), request().toJson());
    });
  });

  // ── ProLocalOrchestratorOutcome ───────────────────────────────────────────

  group('ProLocalOrchestratorOutcome', () {
    ProLocalOrchestratorOutcome completedOutcome() =>
        ProLocalOrchestratorOutcome(
          sessionId: 'session-1',
          finalStatus: ProOrchestratorOutcomeStatus.completed,
          stepRecords: [_doneRecord()],
          safetyResultRef: 'safety:1',
        );

    test('completed outcome roundtrip', () {
      final outcome = completedOutcome();
      final rt = ProLocalOrchestratorOutcome.fromJson(outcome.toJson());
      expect(rt.sessionId, 'session-1');
      expect(rt.finalStatus, ProOrchestratorOutcomeStatus.completed);
      expect(rt.stepRecords.length, 1);
      expect(rt.stepRecords.first.status, ProStepStatus.done);
      expect(rt.safetyResultRef, 'safety:1');
      expect(rt.loopResultRef, isNull);
      expect(rt.terminationReason, isNull);
    });

    test('failed outcome with terminationReason roundtrip', () {
      final outcome = ProLocalOrchestratorOutcome(
        sessionId: 'session-2',
        finalStatus: ProOrchestratorOutcomeStatus.failed,
        terminationReason: 'step-2 engine error',
        stepRecords: [_doneRecord(), _failedRecord(), _skippedRecord()],
      );
      final rt = ProLocalOrchestratorOutcome.fromJson(outcome.toJson());
      expect(rt.finalStatus, ProOrchestratorOutcomeStatus.failed);
      expect(rt.terminationReason, 'step-2 engine error');
      expect(rt.stepRecords.length, 3);
      expect(rt.stepRecords[1].status, ProStepStatus.failed);
      expect(rt.stepRecords[2].status, ProStepStatus.skipped);
    });

    test('rejected outcome roundtrip', () {
      final outcome = ProLocalOrchestratorOutcome(
        sessionId: 'session-3',
        finalStatus: ProOrchestratorOutcomeStatus.rejected,
        terminationReason: 'user cancelled confirmation',
        stepRecords: [_doneRecord()],
      );
      final rt = ProLocalOrchestratorOutcome.fromJson(outcome.toJson());
      expect(rt.finalStatus, ProOrchestratorOutcomeStatus.rejected);
      expect(rt.terminationReason, 'user cancelled confirmation');
    });

    test('waitingConfirmation status roundtrip', () {
      final outcome = ProLocalOrchestratorOutcome(
        sessionId: 'session-4',
        finalStatus: ProOrchestratorOutcomeStatus.waitingConfirmation,
        stepRecords: [_doneRecord()],
      );
      final rt = ProLocalOrchestratorOutcome.fromJson(outcome.toJson());
      expect(rt.finalStatus, ProOrchestratorOutcomeStatus.waitingConfirmation);
    });

    test('empty stepRecords roundtrip', () {
      const outcome = ProLocalOrchestratorOutcome(
        sessionId: 'session-5',
        finalStatus: ProOrchestratorOutcomeStatus.failed,
        terminationReason: 'immediate failure',
        stepRecords: [],
      );
      final rt = ProLocalOrchestratorOutcome.fromJson(outcome.toJson());
      expect(rt.stepRecords, isEmpty);
    });

    test('both safetyResultRef and loopResultRef roundtrip', () {
      final outcome = ProLocalOrchestratorOutcome(
        sessionId: 'session-6',
        finalStatus: ProOrchestratorOutcomeStatus.completed,
        stepRecords: [_doneRecord()],
        safetyResultRef: 'safety:out',
        loopResultRef: 'loop:out',
      );
      final rt = ProLocalOrchestratorOutcome.fromJson(outcome.toJson());
      expect(rt.safetyResultRef, 'safety:out');
      expect(rt.loopResultRef, 'loop:out');
    });

    test('toJson has no forbidden DSP keys (top level)', () {
      final j = completedOutcome().toJson();
      for (final key in [
        'frequency',
        'gainDb',
        'q',
        'biquad',
        'address',
        'payload',
        'register',
        'coefficients',
      ]) {
        expect(j.containsKey(key), isFalse, reason: 'forbidden key: $key');
      }
    });

    test('safetyResultRef is an opaque string, not a DSP value', () {
      final j = completedOutcome().toJson();
      expect(j['safetyResultRef'], isA<String>());
    });

    test('fromJson rejects unknown key', () {
      final j = completedOutcome().toJson()..['gainDb'] = -3.0;
      expect(
        () => ProLocalOrchestratorOutcome.fromJson(j),
        throwsA(isA<ProContractException>()),
      );
    });

    test('fromJson rejects non-list stepRecords', () {
      final j = completedOutcome().toJson()..['stepRecords'] = 'not-a-list';
      expect(
        () => ProLocalOrchestratorOutcome.fromJson(j),
        throwsA(isA<ProContractException>()),
      );
    });

    test('deterministic JSON — same outcome same JSON', () {
      expect(completedOutcome().toJson(), completedOutcome().toJson());
    });
  });

  // ── ProLocalOrchestratorSession ───────────────────────────────────────────

  group('ProLocalOrchestratorSession', () {
    ProLocalOrchestratorSession draft() => ProLocalOrchestratorSession(
          sessionId: 'sess-abc',
          projectId: 'proj-1',
          plan: _plan(),
          status: ProPlanStatus.draft,
        );

    test('draft session roundtrip', () {
      final sess = draft();
      final rt = ProLocalOrchestratorSession.fromJson(sess.toJson());
      expect(rt.sessionId, 'sess-abc');
      expect(rt.projectId, 'proj-1');
      expect(rt.status, ProPlanStatus.draft);
      expect(rt.currentStepId, isNull);
      expect(rt.schemaVersion, kProOrchestratorSchemaVersion);
    });

    test('inProgress with currentStepId roundtrip', () {
      final sess = ProLocalOrchestratorSession(
        sessionId: 'sess-abc',
        projectId: 'proj-1',
        plan: _plan(),
        status: ProPlanStatus.inProgress,
        currentStepId: 'step-1',
      );
      final rt = ProLocalOrchestratorSession.fromJson(sess.toJson());
      expect(rt.status, ProPlanStatus.inProgress);
      expect(rt.currentStepId, 'step-1');
    });

    test('completed session with no currentStepId roundtrip', () {
      final sess = ProLocalOrchestratorSession(
        sessionId: 'sess-abc',
        projectId: 'proj-1',
        plan: _plan(),
        status: ProPlanStatus.completed,
      );
      final rt = ProLocalOrchestratorSession.fromJson(sess.toJson());
      expect(rt.status, ProPlanStatus.completed);
      expect(rt.currentStepId, isNull);
    });

    test('rejected session roundtrip', () {
      final sess = ProLocalOrchestratorSession(
        sessionId: 'sess-abc',
        projectId: 'proj-1',
        plan: _plan(),
        status: ProPlanStatus.rejected,
      );
      final rt = ProLocalOrchestratorSession.fromJson(sess.toJson());
      expect(rt.status, ProPlanStatus.rejected);
    });

    test('plan is fully embedded and roundtrips', () {
      final sess = draft();
      final rt = ProLocalOrchestratorSession.fromJson(sess.toJson());
      expect(rt.plan.planId, 'plan-test');
      expect(rt.plan.steps.length, 2);
      expect(
          rt.plan.steps.first.toolId, ProOrchestratorToolId.acousticClassify);
    });

    // ── withStatus ──────────────────────────────────────────────────────────

    group('withStatus transition helper', () {
      test('draft → inProgress sets currentStepId', () {
        final updated = draft().withStatus(
          ProPlanStatus.inProgress,
          currentStepId: 'step-0',
        );
        expect(updated.status, ProPlanStatus.inProgress);
        expect(updated.currentStepId, 'step-0');
      });

      test('inProgress → completed clears currentStepId', () {
        final inProgress = ProLocalOrchestratorSession(
          sessionId: 'sess-abc',
          projectId: 'proj-1',
          plan: _plan(),
          status: ProPlanStatus.inProgress,
          currentStepId: 'step-1',
        );
        final completed = inProgress.withStatus(ProPlanStatus.completed);
        expect(completed.status, ProPlanStatus.completed);
        expect(completed.currentStepId, isNull);
      });

      test('withStatus preserves sessionId and projectId', () {
        final updated = draft().withStatus(ProPlanStatus.inProgress);
        expect(updated.sessionId, 'sess-abc');
        expect(updated.projectId, 'proj-1');
      });

      test('withStatus preserves plan identity', () {
        final updated = draft().withStatus(ProPlanStatus.inProgress);
        expect(updated.plan.planId, 'plan-test');
      });

      test('withStatus does not mutate original', () {
        final original = draft();
        original.withStatus(ProPlanStatus.inProgress, currentStepId: 'step-0');
        expect(original.status, ProPlanStatus.draft);
        expect(original.currentStepId, isNull);
      });
    });

    test('toJson has no forbidden DSP keys', () {
      final j = draft().toJson();
      for (final key in [
        'frequency',
        'gainDb',
        'q',
        'biquad',
        'address',
        'payload',
        'register',
        'coefficients',
      ]) {
        expect(j.containsKey(key), isFalse, reason: 'forbidden key: $key');
      }
    });

    test('fromJson rejects unknown key', () {
      final j = draft().toJson()..['gainDb'] = 0.0;
      expect(
        () => ProLocalOrchestratorSession.fromJson(j),
        throwsA(isA<ProContractException>()),
      );
    });

    test('fromJson rejects wrong schemaVersion', () {
      final j = draft().toJson()..['schemaVersion'] = 99;
      expect(
        () => ProLocalOrchestratorSession.fromJson(j),
        throwsA(isA<ProContractException>()),
      );
    });

    test('deterministic JSON — same session same JSON', () {
      expect(draft().toJson(), draft().toJson());
    });
  });

  // ── Cross-model: status data ──────────────────────────────────────────────

  group('status transition data', () {
    test('all ProPlanStatus values present in session roundtrip', () {
      for (final s in ProPlanStatus.values) {
        final sess = ProLocalOrchestratorSession(
          sessionId: 'sess-x',
          projectId: 'p1',
          plan: _plan(numSteps: 1),
          status: s,
        );
        final rt = ProLocalOrchestratorSession.fromJson(sess.toJson());
        expect(rt.status, s);
      }
    });

    test('all ProStepStatus values present in record roundtrip', () {
      for (final s in ProStepStatus.values) {
        final rec = ProStepExecutionRecord(
          stepId: 'step-x',
          toolId: ProOrchestratorToolId.acousticClassify,
          status: s,
          outputRef: s == ProStepStatus.done ? 'out:x' : '',
          elapsedMs: 0,
        );
        final rt = ProStepExecutionRecord.fromJson(rec.toJson(), 'test');
        expect(rt.status, s);
      }
    });

    test('all ProOrchestratorOutcomeStatus values roundtrip in outcome', () {
      for (final s in ProOrchestratorOutcomeStatus.values) {
        final outcome = ProLocalOrchestratorOutcome(
          sessionId: 'sess-x',
          finalStatus: s,
          stepRecords: const [],
        );
        final rt = ProLocalOrchestratorOutcome.fromJson(outcome.toJson());
        expect(rt.finalStatus, s);
      }
    });
  });
}
