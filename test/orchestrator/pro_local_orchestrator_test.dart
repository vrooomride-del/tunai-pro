import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/orchestrator/pro_local_orchestrator.dart';
import 'package:tunai_pro/core/orchestrator/pro_local_orchestrator_session.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_result.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';

// ── Stub adapters ─────────────────────────────────────────────────────────────

class _SuccessAdapter implements ProToolAdapter {
  final ProOrchestratorToolId _id;
  const _SuccessAdapter(this._id);

  @override
  ProOrchestratorToolId get toolId => _id;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    ctx.store.put(ctx.projectId, step.outputRef, SimulationArtifact([1.0]));
    return ProOrchestratorResult(
      resultId: 'result:${step.outputRef}',
      toolId: step.toolId,
      inputRefs: step.inputRefs,
      outputRef: step.outputRef,
      evidenceRefs: [step.outputRef],
      confidence: ProConfidence.high,
      summary: 'synthetic ok',
    );
  }
}

class _FailureAdapter implements ProToolAdapter {
  final ProOrchestratorToolId _id;
  const _FailureAdapter(this._id);

  @override
  ProOrchestratorToolId get toolId => _id;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    throw ProToolException(
        ProToolFailureCode.engineError, 'synthetic failure');
  }
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

ProOrchestratorStep step(
  String stepId,
  ProOrchestratorToolId toolId, {
  bool confirm = false,
  List<String> inputRefs = const [],
}) =>
    ProOrchestratorStep(
      stepId: stepId,
      toolId: toolId,
      objective: 'run $stepId',
      inputRefs: inputRefs,
      outputRef: 'out:$stepId',
      requiresUserConfirmation: confirm,
      explanation: confirm ? 'please confirm $stepId' : '',
    );

ProOrchestratorPlan plan(List<ProOrchestratorStep> steps) =>
    ProOrchestratorPlan(
      planId: 'plan-test',
      intentRef: 'intent:1',
      contextRef: 'ctx:1',
      steps: steps,
    );

ProToolExecutionContext ctx() => ProToolExecutionContext(
      projectId: 'p1',
      contextRef: 'ctx:1',
      resolver: InMemoryProToolReferenceResolver(),
      store: ProToolArtifactStore(),
    );

ProDeterministicToolRegistry successRegistry(List<ProOrchestratorToolId> ids) =>
    ProDeterministicToolRegistry([for (final id in ids) _SuccessAdapter(id)]);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Full plan success ──────────────────────────────────────────────────────

  group('full plan success', () {
    test(
        'two-step success emits stepStarted/Completed pairs then planCompleted',
        () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan),
      ]);
      final registry = successRegistry([
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticPlan
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      final events = <ProLocalOrchestratorEvent>[];

      await for (final e in orchestrator.run(p, ctx())) {
        events.add(e);
      }

      expect(events.whereType<ProStepStarted>(), hasLength(2));
      expect(events.whereType<ProStepCompleted>(), hasLength(2));
      expect(events.last, isA<ProPlanCompleted>());
      final done = events.last as ProPlanCompleted;
      expect(done.outcome.finalStatus, ProOrchestratorOutcomeStatus.completed);
      expect(done.outcome.stepRecords, hasLength(2));
      expect(
          done.outcome.stepRecords.every((r) => r.status == ProStepStatus.done),
          isTrue);
    });

    test('outcome has correct sessionId = plan.planId', () async {
      final p = plan([step('s0', ProOrchestratorToolId.acousticClassify)]);
      final registry =
          successRegistry([ProOrchestratorToolId.acousticClassify]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanCompleted) outcome = e.outcome;
      }

      expect(outcome?.sessionId, equals('plan-test'));
    });

    test('single-step plan completes with one done record', () async {
      final p = plan([step('s0', ProOrchestratorToolId.acousticClassify)]);
      final registry =
          successRegistry([ProOrchestratorToolId.acousticClassify]);
      final orchestrator = ProLocalOrchestrator(registry);
      final events = <ProLocalOrchestratorEvent>[];

      await for (final e in orchestrator.run(p, ctx())) {
        events.add(e);
      }

      expect(events.last, isA<ProPlanCompleted>());
      expect(
          (events.last as ProPlanCompleted).outcome.stepRecords.single.status,
          ProStepStatus.done);
    });
  });

  // ── Step failure propagation ───────────────────────────────────────────────

  group('step failure propagation', () {
    test('failed step emits stepCompleted(failed) then planFailed', () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan),
        step('s2', ProOrchestratorToolId.acousticGenerateCandidates),
      ]);
      final registry = ProDeterministicToolRegistry([
        const _SuccessAdapter(ProOrchestratorToolId.acousticClassify),
        const _FailureAdapter(ProOrchestratorToolId.acousticPlan),
        const _SuccessAdapter(ProOrchestratorToolId.acousticGenerateCandidates),
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      final events = <ProLocalOrchestratorEvent>[];

      await for (final e in orchestrator.run(p, ctx())) {
        events.add(e);
      }

      expect(events.last, isA<ProPlanFailed>());
      final failed = events.last as ProPlanFailed;
      expect(failed.outcome.finalStatus, ProOrchestratorOutcomeStatus.failed);
      expect(failed.outcome.terminationReason, contains('synthetic failure'));

      final records = failed.outcome.stepRecords;
      expect(records, hasLength(3));
      expect(records[0].status, ProStepStatus.done);
      expect(records[1].status, ProStepStatus.failed);
      expect(records[2].status, ProStepStatus.skipped);
    });

    test('skipped steps have zero elapsedMs', () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan),
      ]);
      final registry = ProDeterministicToolRegistry([
        const _FailureAdapter(ProOrchestratorToolId.acousticClassify),
        const _SuccessAdapter(ProOrchestratorToolId.acousticPlan),
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanFailed) outcome = e.outcome;
      }

      expect(outcome?.stepRecords[1].elapsedMs, 0);
    });

    test('failed record carries failureCode and failureMessage', () async {
      final p = plan([step('s0', ProOrchestratorToolId.acousticClassify)]);
      final registry = ProDeterministicToolRegistry([
        const _FailureAdapter(ProOrchestratorToolId.acousticClassify),
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanFailed) outcome = e.outcome;
      }

      final record = outcome!.stepRecords.single;
      expect(record.failureCode, 'engineError');
      expect(record.failureMessage, 'synthetic failure');
    });

    test('unregistered tool yields unsupportedTool failure', () async {
      final p = plan([step('s0', ProOrchestratorToolId.acousticClassify)]);
      final registry = ProDeterministicToolRegistry([]);
      final orchestrator = ProLocalOrchestrator(registry);
      final events = <ProLocalOrchestratorEvent>[];

      await for (final e in orchestrator.run(p, ctx())) {
        events.add(e);
      }

      expect(events.last, isA<ProPlanFailed>());
      final record = (events.last as ProPlanFailed).outcome.stepRecords.single;
      expect(record.failureCode, 'unsupportedTool');
    });
  });

  // ── Confirmation gate ──────────────────────────────────────────────────────

  group('confirmation gate', () {
    test('stream pauses at waitingConfirmation — emitted before stepCompleted',
        () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan, confirm: true),
        step('s2', ProOrchestratorToolId.acousticGenerateCandidates),
      ]);
      final registry = successRegistry([
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticPlan,
        ProOrchestratorToolId.acousticGenerateCandidates,
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      final events = <ProLocalOrchestratorEvent>[];

      await for (final e in orchestrator.run(p, ctx())) {
        events.add(e);
        if (e is ProWaitingConfirmation) {
          orchestrator.confirm(e.request.stepId);
        }
      }

      expect(events.whereType<ProWaitingConfirmation>(), hasLength(1));
      final waitIdx = events.indexWhere((e) => e is ProWaitingConfirmation);
      final s1CompletedIdx = events
          .indexWhere((e) => e is ProStepCompleted && e.record.stepId == 's1');
      expect(waitIdx, lessThan(s1CompletedIdx));
      expect(events.last, isA<ProPlanCompleted>());
    });

    test('confirm resumes — plan completes with all three steps done',
        () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan, confirm: true),
        step('s2', ProOrchestratorToolId.acousticGenerateCandidates),
      ]);
      final registry = successRegistry([
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticPlan,
        ProOrchestratorToolId.acousticGenerateCandidates,
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProWaitingConfirmation) orchestrator.confirm(e.request.stepId);
        if (e is ProPlanCompleted) outcome = e.outcome;
      }

      expect(outcome?.stepRecords, hasLength(3));
      expect(outcome?.stepRecords.every((r) => r.status == ProStepStatus.done),
          isTrue);
    });

    test('waitingConfirmation request carries correct stepId and toolId',
        () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticPlan, confirm: true),
      ]);
      final registry = successRegistry([ProOrchestratorToolId.acousticPlan]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProWaitingConfirmation? waitEvent;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProWaitingConfirmation) {
          waitEvent = e;
          orchestrator.confirm(e.request.stepId);
        }
      }

      expect(waitEvent?.request.stepId, 's0');
      expect(waitEvent?.request.toolId, ProOrchestratorToolId.acousticPlan);
      expect(waitEvent?.request.requiresUserConfirmation, isTrue);
    });
  });

  // ── Cancel → rejected ──────────────────────────────────────────────────────

  group('cancel → rejected', () {
    test('cancel emits planRejected with terminationReason containing stepId',
        () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan, confirm: true),
        step('s2', ProOrchestratorToolId.acousticGenerateCandidates),
      ]);
      final registry = successRegistry([
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticPlan,
        ProOrchestratorToolId.acousticGenerateCandidates,
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      final events = <ProLocalOrchestratorEvent>[];

      await for (final e in orchestrator.run(p, ctx())) {
        events.add(e);
        if (e is ProWaitingConfirmation) orchestrator.cancel(e.request.stepId);
      }

      expect(events.last, isA<ProPlanRejected>());
      final rejected = events.last as ProPlanRejected;
      expect(
          rejected.outcome.finalStatus, ProOrchestratorOutcomeStatus.rejected);
      expect(rejected.outcome.terminationReason, contains('s1'));
    });

    test('cancelled step and remaining steps appear as skipped in outcome',
        () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan, confirm: true),
        step('s2', ProOrchestratorToolId.acousticGenerateCandidates),
      ]);
      final registry = successRegistry([
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticPlan,
        ProOrchestratorToolId.acousticGenerateCandidates,
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProWaitingConfirmation) orchestrator.cancel(e.request.stepId);
        if (e is ProPlanRejected) outcome = e.outcome;
      }

      expect(outcome?.stepRecords, hasLength(3));
      expect(outcome?.stepRecords[0].status, ProStepStatus.done);
      expect(outcome?.stepRecords[1].status, ProStepStatus.skipped);
      expect(outcome?.stepRecords[2].status, ProStepStatus.skipped);
    });

    test('cancel with wrong stepId is a no-op — plan stays paused', () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticPlan, confirm: true),
      ]);
      final registry = successRegistry([ProOrchestratorToolId.acousticPlan]);
      final orchestrator = ProLocalOrchestrator(registry);
      var gotWaiting = false;

      final stream = orchestrator.run(p, ctx());
      // Confirm via a separate async listener so we can call cancel first.
      await for (final e in stream) {
        if (e is ProWaitingConfirmation && !gotWaiting) {
          gotWaiting = true;
          orchestrator.cancel('wrong-step-id'); // no-op
          orchestrator.confirm(e.request.stepId); // actual resume
        }
      }

      expect(gotWaiting, isTrue);
    });
  });

  // ── Event ordering ─────────────────────────────────────────────────────────

  group('event ordering', () {
    test('stepStarted always precedes stepCompleted for each stepId', () async {
      final ids = [
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticPlan,
        ProOrchestratorToolId.acousticGenerateCandidates,
      ];
      final stepIds = ['s0', 's1', 's2'];
      final p = plan([
        for (var i = 0; i < ids.length; i++) step(stepIds[i], ids[i]),
      ]);
      final orchestrator = ProLocalOrchestrator(successRegistry(ids));
      final events = <ProLocalOrchestratorEvent>[];

      await for (final e in orchestrator.run(p, ctx())) {
        events.add(e);
      }

      for (final sid in stepIds) {
        final startedIdx =
            events.indexWhere((e) => e is ProStepStarted && e.stepId == sid);
        final completedIdx = events
            .indexWhere((e) => e is ProStepCompleted && e.record.stepId == sid);
        expect(startedIdx, lessThan(completedIdx),
            reason: 'stepStarted must precede stepCompleted for $sid');
      }
    });

    test('terminal event is always the last event', () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan),
      ]);
      final orchestrator = ProLocalOrchestrator(successRegistry([
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticPlan,
      ]));
      final events = <ProLocalOrchestratorEvent>[];

      await for (final e in orchestrator.run(p, ctx())) {
        events.add(e);
      }

      final terminal = events.last;
      expect(terminal, isA<ProPlanCompleted>());
      final terminalCount = events.whereType<ProPlanCompleted>().length +
          events.whereType<ProPlanFailed>().length +
          events.whereType<ProPlanRejected>().length;
      expect(terminalCount, 1);
    });

    test(
        '3-step failure: s0 done, s1 failed, s2 skipped — correct record order',
        () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan),
        step('s2', ProOrchestratorToolId.acousticGenerateCandidates),
      ]);
      final registry = ProDeterministicToolRegistry([
        const _SuccessAdapter(ProOrchestratorToolId.acousticClassify),
        const _FailureAdapter(ProOrchestratorToolId.acousticPlan),
        const _SuccessAdapter(ProOrchestratorToolId.acousticGenerateCandidates),
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanFailed) outcome = e.outcome;
      }

      final statuses = outcome!.stepRecords.map((r) => r.status).toList();
      expect(statuses,
          [ProStepStatus.done, ProStepStatus.failed, ProStepStatus.skipped]);
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────

  group('determinism', () {
    test('same plan produces same event count and terminal type on two runs',
        () async {
      final ids = [
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticPlan,
      ];
      final p = plan([step('s0', ids[0]), step('s1', ids[1])]);

      Future<List<ProLocalOrchestratorEvent>> runOnce() async {
        final events = <ProLocalOrchestratorEvent>[];
        await for (final e
            in ProLocalOrchestrator(successRegistry(ids)).run(p, ctx())) {
          events.add(e);
        }
        return events;
      }

      final events1 = await runOnce();
      final events2 = await runOnce();

      expect(events1.length, events2.length);
      expect(events1.last.runtimeType, events2.last.runtimeType);
    });

    test('stepRecord outputRefs match plan outputRefs', () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticPlan),
      ]);
      final registry = successRegistry([
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticPlan,
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanCompleted) outcome = e.outcome;
      }

      expect(outcome?.stepRecords[0].outputRef, 'out:s0');
      expect(outcome?.stepRecords[1].outputRef, 'out:s1');
    });
  });

  // ── safetyResultRef / loopResultRef ─────────────────────────────────────────

  group('safetyResultRef and loopResultRef', () {
    test('safetyResultRef is null when no acousticValidateSafety step ran',
        () async {
      final p = plan([step('s0', ProOrchestratorToolId.acousticClassify)]);
      final registry =
          successRegistry([ProOrchestratorToolId.acousticClassify]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanCompleted) outcome = e.outcome;
      }

      expect(outcome?.safetyResultRef, isNull);
      expect(outcome?.loopResultRef, isNull);
    });

    test('safetyResultRef = outputRef of acousticValidateSafety step',
        () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticValidateSafety),
      ]);
      final registry = successRegistry([
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticValidateSafety,
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanCompleted) outcome = e.outcome;
      }

      expect(outcome?.safetyResultRef, 'out:s1');
    });

    test('loopResultRef = outputRef of acousticEvaluateLoop step', () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticClassify),
        step('s1', ProOrchestratorToolId.acousticEvaluateLoop),
      ]);
      final registry = successRegistry([
        ProOrchestratorToolId.acousticClassify,
        ProOrchestratorToolId.acousticEvaluateLoop,
      ]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanCompleted) outcome = e.outcome;
      }

      expect(outcome?.loopResultRef, 'out:s1');
    });
  });

  // ── Forbidden DSP key absence ──────────────────────────────────────────────

  group('forbidden DSP key absence', () {
    final forbiddenKeys = [
      'frequency',
      'frequencyHz',
      'gainDb',
      'gain',
      'q',
      'biquad',
      'address',
      'coefficients',
      'payload',
    ];

    test('outcome JSON has no forbidden DSP keys at top level', () async {
      final p = plan([step('s0', ProOrchestratorToolId.acousticClassify)]);
      final registry =
          successRegistry([ProOrchestratorToolId.acousticClassify]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanCompleted) outcome = e.outcome;
      }

      final j = outcome!.toJson();
      for (final key in forbiddenKeys) {
        expect(j.containsKey(key), isFalse,
            reason: 'found forbidden DSP key "$key" in outcome JSON');
      }
    });

    test('stepRecord JSON has no forbidden DSP keys', () async {
      final p = plan([step('s0', ProOrchestratorToolId.acousticClassify)]);
      final registry =
          successRegistry([ProOrchestratorToolId.acousticClassify]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProLocalOrchestratorOutcome? outcome;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProPlanCompleted) outcome = e.outcome;
      }

      for (final record in outcome!.stepRecords) {
        final j = record.toJson();
        for (final key in forbiddenKeys) {
          expect(j.containsKey(key), isFalse,
              reason: 'found forbidden DSP key "$key" in stepRecord JSON');
        }
      }
    });

    test('ProWaitingConfirmation request JSON has no forbidden DSP keys',
        () async {
      final p = plan([
        step('s0', ProOrchestratorToolId.acousticPlan, confirm: true),
      ]);
      final registry = successRegistry([ProOrchestratorToolId.acousticPlan]);
      final orchestrator = ProLocalOrchestrator(registry);
      ProWaitingConfirmation? waitEvent;

      await for (final e in orchestrator.run(p, ctx())) {
        if (e is ProWaitingConfirmation) {
          waitEvent = e;
          orchestrator.confirm(e.request.stepId);
        }
      }

      final j = waitEvent!.request.toJson();
      for (final key in forbiddenKeys) {
        expect(j.containsKey(key), isFalse,
            reason:
                'found forbidden DSP key "$key" in confirmation request JSON');
      }
    });
  });
}
