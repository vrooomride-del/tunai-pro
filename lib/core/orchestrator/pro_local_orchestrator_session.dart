import 'pro_explanation.dart';
import 'pro_orchestrator_plan.dart';
import 'pro_orchestrator_types.dart';

// TRUST BOUNDARY. All models in this file follow the same rules as the rest of
// lib/core/orchestrator/: no DSP value, no frequency, no gain, no Q, no
// coefficient, no address, no payload. Artifact references are opaque strings.
// ProContract.ensureKeys rejects any unknown key, so forbidden DSP keys cannot
// sneak through a round-trip.

// ── Outcome status ────────────────────────────────────────────────────────────

/// Final (or transitional) status of a Local Orchestrator run.
///
/// [waitingConfirmation] is the transient pause state while the state machine
/// awaits user approval for a [requiresUserConfirmation] step.
enum ProOrchestratorOutcomeStatus {
  completed,
  failed,
  rejected,
  waitingConfirmation;

  String toJson() => name;

  static ProOrchestratorOutcomeStatus parse(Object? raw, String ctx) =>
      ProContract.parseEnum(values, (e) => e.name, raw, 'outcomeStatus', ctx);
}

// ── Step execution record ─────────────────────────────────────────────────────

/// Immutable record of one step's execution result.
///
/// Contains only step identity ([stepId], [toolId]), lifecycle [status], the
/// opaque [outputRef] produced (non-empty when done, empty otherwise), an
/// optional LLM [explanation], optional failure details, and [elapsedMs].
///
/// No DSP value: [outputRef] is an opaque identifier, not a frequency or gain.
class ProStepExecutionRecord {
  final String stepId;
  final ProOrchestratorToolId toolId;

  /// Lifecycle outcome of this step.
  final ProStepStatus status;

  /// The artifact reference produced by the tool. Non-empty when [status] is
  /// done; empty for failed or skipped steps. Opaque — never a DSP value.
  final String outputRef;

  /// Human-readable summary from the tool result (empty when not done).
  final String summary;

  /// Coarse confidence from the tool result; null when not completed.
  final ProConfidence? confidence;

  /// [ProToolFailureCode] name when [status] is failed; null otherwise.
  final String? failureCode;

  /// Human message accompanying [failureCode]; null when not failed.
  final String? failureMessage;

  /// Optional LLM-authored explanation produced for this step.
  final ProExplanation? explanation;

  /// Elapsed wall-clock milliseconds (0 for skipped or not-yet-run steps).
  final int elapsedMs;

  const ProStepExecutionRecord({
    required this.stepId,
    required this.toolId,
    required this.status,
    required this.outputRef,
    this.summary = '',
    this.confidence,
    this.failureCode,
    this.failureMessage,
    this.explanation,
    required this.elapsedMs,
  });

  static const _allowedKeys = {
    'stepId',
    'toolId',
    'status',
    'outputRef',
    'summary',
    'confidence',
    'failureCode',
    'failureMessage',
    'explanation',
    'elapsedMs',
  };

  Map<String, dynamic> toJson() => {
        'stepId': stepId,
        'toolId': toolId.toJson(),
        'status': status.toJson(),
        'outputRef': outputRef,
        'summary': summary,
        if (confidence != null) 'confidence': confidence!.toJson(),
        if (failureCode != null) 'failureCode': failureCode,
        if (failureMessage != null) 'failureMessage': failureMessage,
        if (explanation != null) 'explanation': explanation!.toJson(),
        'elapsedMs': elapsedMs,
      };

  factory ProStepExecutionRecord.fromJson(
      Map<String, dynamic> json, String ctx) {
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    final rawExpl = json['explanation'];
    return ProStepExecutionRecord(
      stepId: ProContract.requireString(json, 'stepId', ctx),
      toolId: ProOrchestratorToolId.parse(json['toolId'], ctx),
      status: ProStepStatus.parse(json['status'], ctx),
      outputRef: ProContract.optionalString(json, 'outputRef', ctx) ?? '',
      summary: ProContract.optionalString(json, 'summary', ctx) ?? '',
      confidence: json.containsKey('confidence')
          ? ProConfidence.parse(json['confidence'], ctx)
          : null,
      failureCode: ProContract.optionalString(json, 'failureCode', ctx),
      failureMessage: ProContract.optionalString(json, 'failureMessage', ctx),
      explanation: rawExpl == null
          ? null
          : ProExplanation.fromJson(
              ProContract.asObject(rawExpl, '$ctx.explanation')),
      elapsedMs: _requireInt(json, 'elapsedMs', ctx),
    );
  }

  static int _requireInt(Map<String, dynamic> json, String key, String ctx) {
    final v = json[key];
    if (v is! int) {
      throw ProContractException('$ctx: "$key" must be an int, got '
          '${v.runtimeType}.');
    }
    return v;
  }
}

// ── User confirmation request ─────────────────────────────────────────────────

/// Emitted when a step has [ProOrchestratorStep.requiresUserConfirmation] set.
///
/// The state machine pauses. The UI surfaces [explanation] and waits for the
/// user to confirm (resume) or cancel (reject). No DSP value, no coefficient,
/// no numeric parameter rides along — only the step's identity and objective
/// in words plus the LLM explanation to display.
class ProUserConfirmationRequest {
  final int schemaVersion;
  final String stepId;
  final ProOrchestratorToolId toolId;

  /// The step's objective text. Verbatim human description of what the step
  /// will do — treated as opaque prose, never parsed into an engine parameter.
  final String objective;

  /// Always true for a valid confirmation request (mirrors the step's flag).
  final bool requiresUserConfirmation;

  /// LLM-authored explanation the user should review before deciding.
  final ProExplanation explanation;

  const ProUserConfirmationRequest({
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.stepId,
    required this.toolId,
    required this.objective,
    this.requiresUserConfirmation = true,
    required this.explanation,
  });

  static const _allowedKeys = {
    'schemaVersion',
    'stepId',
    'toolId',
    'objective',
    'requiresUserConfirmation',
    'explanation',
  };

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'stepId': stepId,
        'toolId': toolId.toJson(),
        'objective': objective,
        'requiresUserConfirmation': requiresUserConfirmation,
        'explanation': explanation.toJson(),
      };

  factory ProUserConfirmationRequest.fromJson(Map<String, dynamic> json) {
    const ctx = 'ProUserConfirmationRequest';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);
    return ProUserConfirmationRequest(
      schemaVersion: kProOrchestratorSchemaVersion,
      stepId: ProContract.requireString(json, 'stepId', ctx),
      toolId: ProOrchestratorToolId.parse(json['toolId'], ctx),
      objective: ProContract.requireString(json, 'objective', ctx),
      requiresUserConfirmation:
          ProContract.requireBool(json, 'requiresUserConfirmation', ctx),
      explanation: ProExplanation.fromJson(
        ProContract.asObject(json['explanation'], '$ctx.explanation'),
      ),
    );
  }
}

// ── Orchestrator outcome ──────────────────────────────────────────────────────

/// Complete result of a Local Orchestrator run.
///
/// [finalStatus] is the definitive [ProOrchestratorOutcomeStatus]: completed,
/// failed, rejected, or waitingConfirmation. [stepRecords] are the
/// step-by-step audit trail. [safetyResultRef] and [loopResultRef] are opaque
/// artifact references — the actual safety/loop data is in the session's
/// [ProToolArtifactStore], never embedded here.
///
/// No DSP value: every ref field is an opaque string identifier.
class ProLocalOrchestratorOutcome {
  final int schemaVersion;
  final String sessionId;
  final ProOrchestratorOutcomeStatus finalStatus;

  /// Non-null when [finalStatus] is failed or rejected. Human-readable reason;
  /// never a DSP number.
  final String? terminationReason;

  final List<ProStepExecutionRecord> stepRecords;

  /// OutputRef of the [CandidateSafetyArtifact] produced by
  /// `acousticValidateSafety`, when that step ran. Null otherwise.
  final String? safetyResultRef;

  /// OutputRef of the [ClosedLoopResultArtifact] produced by
  /// `acousticEvaluateLoop`, when that step ran. Null otherwise.
  final String? loopResultRef;

  const ProLocalOrchestratorOutcome({
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.sessionId,
    required this.finalStatus,
    this.terminationReason,
    required this.stepRecords,
    this.safetyResultRef,
    this.loopResultRef,
  });

  static const _allowedKeys = {
    'schemaVersion',
    'sessionId',
    'finalStatus',
    'terminationReason',
    'stepRecords',
    'safetyResultRef',
    'loopResultRef',
  };

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'sessionId': sessionId,
        'finalStatus': finalStatus.toJson(),
        if (terminationReason != null) 'terminationReason': terminationReason,
        'stepRecords': [for (final r in stepRecords) r.toJson()],
        if (safetyResultRef != null) 'safetyResultRef': safetyResultRef,
        if (loopResultRef != null) 'loopResultRef': loopResultRef,
      };

  factory ProLocalOrchestratorOutcome.fromJson(Map<String, dynamic> json) {
    const ctx = 'ProLocalOrchestratorOutcome';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);

    final rawRecords = json['stepRecords'];
    if (rawRecords is! List) {
      throw ProContractException('$ctx: "stepRecords" must be a list.');
    }
    final records = [
      for (var i = 0; i < rawRecords.length; i++)
        ProStepExecutionRecord.fromJson(
          ProContract.asObject(rawRecords[i], '$ctx.stepRecords[$i]'),
          '$ctx.stepRecords[$i]',
        )
    ];

    return ProLocalOrchestratorOutcome(
      schemaVersion: kProOrchestratorSchemaVersion,
      sessionId: ProContract.requireString(json, 'sessionId', ctx),
      finalStatus: ProOrchestratorOutcomeStatus.parse(json['finalStatus'], ctx),
      terminationReason:
          ProContract.optionalString(json, 'terminationReason', ctx),
      stepRecords: records,
      safetyResultRef: ProContract.optionalString(json, 'safetyResultRef', ctx),
      loopResultRef: ProContract.optionalString(json, 'loopResultRef', ctx),
    );
  }
}

// ── Session ───────────────────────────────────────────────────────────────────

/// Observable, serializable state of a running orchestration session.
///
/// Carries the session identity ([sessionId], [projectId]), the [plan] being
/// executed, the lifecycle [status], and the [currentStepId] (null when not
/// running). The store and reference resolver that power step execution live
/// at the state-machine layer — they are not serialisable and are not here.
///
/// No DSP value: [currentStepId] is an opaque step identifier.
class ProLocalOrchestratorSession {
  final int schemaVersion;
  final String sessionId;
  final String projectId;
  final ProOrchestratorPlan plan;
  final ProPlanStatus status;

  /// The stepId currently executing or awaiting confirmation. Null when the
  /// session is draft, completed, or rejected.
  final String? currentStepId;

  const ProLocalOrchestratorSession({
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.sessionId,
    required this.projectId,
    required this.plan,
    required this.status,
    this.currentStepId,
  });

  static const _allowedKeys = {
    'schemaVersion',
    'sessionId',
    'projectId',
    'plan',
    'status',
    'currentStepId',
  };

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'sessionId': sessionId,
        'projectId': projectId,
        'plan': plan.toJson(),
        'status': status.toJson(),
        if (currentStepId != null) 'currentStepId': currentStepId,
      };

  factory ProLocalOrchestratorSession.fromJson(Map<String, dynamic> json) {
    const ctx = 'ProLocalOrchestratorSession';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);
    return ProLocalOrchestratorSession(
      schemaVersion: kProOrchestratorSchemaVersion,
      sessionId: ProContract.requireString(json, 'sessionId', ctx),
      projectId: ProContract.requireString(json, 'projectId', ctx),
      plan: ProOrchestratorPlan.fromJson(
          ProContract.asObject(json['plan'], '$ctx.plan')),
      status: ProPlanStatus.parse(json['status'], ctx),
      currentStepId: ProContract.optionalString(json, 'currentStepId', ctx),
    );
  }

  /// Returns a copy with [newStatus] and an updated [currentStepId].
  ProLocalOrchestratorSession withStatus(
    ProPlanStatus newStatus, {
    String? currentStepId,
  }) =>
      ProLocalOrchestratorSession(
        sessionId: sessionId,
        projectId: projectId,
        plan: plan,
        status: newStatus,
        currentStepId: currentStepId,
      );
}
