import 'dart:async';

import 'pro_explanation.dart';
import 'pro_local_orchestrator_session.dart';
import 'pro_orchestrator_plan.dart';
import 'pro_orchestrator_types.dart';
import 'tools/pro_tool_execution.dart';
import 'tools/pro_tool_registry.dart';

// TRUST BOUNDARY. This file touches only opaque references and lifecycle
// statuses — no DSP value, no frequency, no gain, no Q, no coefficient,
// no address, no payload at any call site.

// ── Events ────────────────────────────────────────────────────────────────────

sealed class ProLocalOrchestratorEvent {
  const ProLocalOrchestratorEvent();
}

class ProStepStarted extends ProLocalOrchestratorEvent {
  final String stepId;
  final ProOrchestratorToolId toolId;
  const ProStepStarted({required this.stepId, required this.toolId});
}

class ProStepCompleted extends ProLocalOrchestratorEvent {
  final ProStepExecutionRecord record;
  const ProStepCompleted(this.record);
}

class ProWaitingConfirmation extends ProLocalOrchestratorEvent {
  final ProUserConfirmationRequest request;
  const ProWaitingConfirmation(this.request);
}

class ProPlanCompleted extends ProLocalOrchestratorEvent {
  final ProLocalOrchestratorOutcome outcome;
  const ProPlanCompleted(this.outcome);
}

class ProPlanFailed extends ProLocalOrchestratorEvent {
  final ProLocalOrchestratorOutcome outcome;
  const ProPlanFailed(this.outcome);
}

class ProPlanRejected extends ProLocalOrchestratorEvent {
  final ProLocalOrchestratorOutcome outcome;
  const ProPlanRejected(this.outcome);
}

// ── State machine ─────────────────────────────────────────────────────────────

/// Deterministic local executor for a [ProOrchestratorPlan].
///
/// Streams [ProLocalOrchestratorEvent]s as steps execute. Pauses at any
/// [ProOrchestratorStep.requiresUserConfirmation] step until [confirm] or
/// [cancel] is called on the same instance. On cancel the plan transitions to
/// [ProOrchestratorOutcomeStatus.rejected]; on step-level failure it
/// transitions to [ProOrchestratorOutcomeStatus.failed].
///
/// No DSP write, no Apply step, no hardware command is issued here.
/// Every adapter is called through [ProDeterministicToolRegistry.execute],
/// which guarantees a typed outcome without propagating exceptions to callers.
class ProLocalOrchestrator {
  final ProDeterministicToolRegistry _registry;

  Completer<bool>? _confirmationCompleter;
  String? _awaitingStepId;

  ProLocalOrchestrator(this._registry);

  /// Runs [plan] synchronously (per-step) except at confirmation gates.
  ///
  /// Emits events in order:
  ///   [ProStepStarted] → ([ProWaitingConfirmation] →) [ProStepCompleted]
  ///   for each step that runs; then one terminal event:
  ///   [ProPlanCompleted] | [ProPlanFailed] | [ProPlanRejected].
  ///
  /// Skipped steps (due to prior failure or user cancel) appear only in
  /// [ProLocalOrchestratorOutcome.stepRecords] — no individual events.
  Stream<ProLocalOrchestratorEvent> run(
    ProOrchestratorPlan plan,
    ProToolExecutionContext ctx,
  ) async* {
    final records = <ProStepExecutionRecord>[];

    for (var i = 0; i < plan.steps.length; i++) {
      final step = plan.steps[i];

      yield ProStepStarted(stepId: step.stepId, toolId: step.toolId);

      // ── Confirmation gate ────────────────────────────────────────────────
      if (step.requiresUserConfirmation) {
        _confirmationCompleter = Completer<bool>();
        _awaitingStepId = step.stepId;

        yield ProWaitingConfirmation(ProUserConfirmationRequest(
          stepId: step.stepId,
          toolId: step.toolId,
          objective: step.objective,
          explanation: ProExplanation(
            title: step.objective,
            summary: step.explanation.isNotEmpty
                ? step.explanation
                : 'Step ${step.stepId} requires confirmation before running.',
            explanationLevel: ProExplanationLevel.intermediate,
          ),
        ));

        final confirmed = await _confirmationCompleter!.future;
        _confirmationCompleter = null;
        _awaitingStepId = null;

        if (!confirmed) {
          records.add(_skippedRecord(step));
          for (var j = i + 1; j < plan.steps.length; j++) {
            records.add(_skippedRecord(plan.steps[j]));
          }
          yield ProPlanRejected(ProLocalOrchestratorOutcome(
            sessionId: plan.planId,
            finalStatus: ProOrchestratorOutcomeStatus.rejected,
            terminationReason:
                'user cancelled confirmation for step ${step.stepId}',
            stepRecords: records,
          ));
          return;
        }
      }

      // ── Execute ──────────────────────────────────────────────────────────
      final sw = Stopwatch()..start();
      final outcome = _registry.execute(step, ctx);
      sw.stop();

      final record = _toRecord(step, outcome, sw.elapsedMilliseconds);
      records.add(record);
      yield ProStepCompleted(record);

      if (outcome is ProToolFailure) {
        for (var j = i + 1; j < plan.steps.length; j++) {
          records.add(_skippedRecord(plan.steps[j]));
        }
        yield ProPlanFailed(ProLocalOrchestratorOutcome(
          sessionId: plan.planId,
          finalStatus: ProOrchestratorOutcomeStatus.failed,
          terminationReason: outcome.message,
          stepRecords: records,
        ));
        return;
      }
    }

    yield ProPlanCompleted(ProLocalOrchestratorOutcome(
      sessionId: plan.planId,
      finalStatus: ProOrchestratorOutcomeStatus.completed,
      stepRecords: records,
      safetyResultRef:
          _findOutputRef(records, ProOrchestratorToolId.acousticValidateSafety),
      loopResultRef:
          _findOutputRef(records, ProOrchestratorToolId.acousticEvaluateLoop),
    ));
  }

  /// Resumes a paused plan at [stepId]. No-op if not awaiting that step.
  void confirm(String stepId) {
    if (_awaitingStepId == stepId &&
        _confirmationCompleter != null &&
        !_confirmationCompleter!.isCompleted) {
      _confirmationCompleter!.complete(true);
    }
  }

  /// Rejects a paused plan at [stepId]. No-op if not awaiting that step.
  void cancel(String stepId) {
    if (_awaitingStepId == stepId &&
        _confirmationCompleter != null &&
        !_confirmationCompleter!.isCompleted) {
      _confirmationCompleter!.complete(false);
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static ProStepExecutionRecord _toRecord(
    ProOrchestratorStep step,
    ProToolExecutionOutcome outcome,
    int elapsedMs,
  ) =>
      switch (outcome) {
        ProToolSuccess(:final result) => ProStepExecutionRecord(
            stepId: step.stepId,
            toolId: step.toolId,
            status: ProStepStatus.done,
            outputRef: result.outputRef,
            summary: result.summary,
            confidence: result.confidence,
            elapsedMs: elapsedMs,
          ),
        ProToolFailure(:final code, :final message) => ProStepExecutionRecord(
            stepId: step.stepId,
            toolId: step.toolId,
            status: ProStepStatus.failed,
            outputRef: '',
            failureCode: code.name,
            failureMessage: message,
            elapsedMs: elapsedMs,
          ),
      };

  static ProStepExecutionRecord _skippedRecord(ProOrchestratorStep step) =>
      ProStepExecutionRecord(
        stepId: step.stepId,
        toolId: step.toolId,
        status: ProStepStatus.skipped,
        outputRef: '',
        elapsedMs: 0,
      );

  static String? _findOutputRef(
    List<ProStepExecutionRecord> records,
    ProOrchestratorToolId toolId,
  ) {
    for (final r in records.reversed) {
      if (r.toolId == toolId && r.status == ProStepStatus.done) {
        return r.outputRef;
      }
    }
    return null;
  }
}
