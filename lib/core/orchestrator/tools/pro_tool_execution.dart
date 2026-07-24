import '../pro_orchestrator_result.dart';

/// Every way a deterministic tool run can fail, as a closed set of typed codes.
/// No stringly-typed errors leave this layer.
enum ProToolFailureCode {
  /// The requested tool id is a valid ToolId but no adapter is registered.
  unsupportedTool,

  /// Two adapters claim the same tool id (registry build refuses this).
  duplicateRegistration,

  /// A reference the step needs does not exist in this project's namespace.
  missingReference,

  /// A reference belongs to a different projectId than the execution context.
  scopeViolation,

  /// A reference or artifact resolved to a different type than required.
  typeMismatch,

  /// The step declared an empty outputRef.
  emptyOutputRef,

  /// An artifact already exists at this project + outputRef.
  outputRefConflict,

  /// The measurement source is not a format this tool supports.
  unknownFormat,

  /// The underlying deterministic engine threw.
  engineError,
}

/// A typed failure. Adapters and stores throw this; the registry converts it to
/// a [ProToolFailure] outcome. Never carries a DSP value — only a code and a
/// human message.
class ProToolException implements Exception {
  final ProToolFailureCode code;
  final String message;

  ProToolException(this.code, this.message);

  @override
  String toString() => 'ProToolException(${code.name}): $message';
}

/// The outcome of executing one plan step.
///
/// On success it carries ONLY a reference-only [ProOrchestratorResult] — the
/// numeric artifact stays in the artifact store, never here. On failure it
/// carries a typed code, never a partial/leaked result.
sealed class ProToolExecutionOutcome {
  const ProToolExecutionOutcome();
}

class ProToolSuccess extends ProToolExecutionOutcome {
  final ProOrchestratorResult result;
  const ProToolSuccess(this.result);
}

class ProToolFailure extends ProToolExecutionOutcome {
  final ProToolFailureCode code;
  final String message;
  const ProToolFailure(this.code, this.message);
}
