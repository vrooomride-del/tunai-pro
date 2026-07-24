import '../pro_orchestrator_plan.dart';
import '../pro_orchestrator_result.dart';
import '../pro_orchestrator_types.dart';
import 'pro_tool_artifact_store.dart';
import 'pro_tool_execution.dart';
import 'pro_tool_reference_resolver.dart';

/// Everything an adapter needs to run one step: the project scope, the opaque
/// contextRef, the local reference resolver, and the artifact store.
///
/// Cancellation/timeout: these adapters are synchronous, pure, in-process
/// engine calls with no I/O — there is nothing to cancel or time out, so this
/// layer deliberately declares no timer/cancellation field. A real timeout
/// policy belongs to a future async/hardware tool layer, not here.
class ProToolExecutionContext {
  final String projectId;
  final String contextRef;
  final ProToolReferenceResolver resolver;
  final ProToolArtifactStore store;

  const ProToolExecutionContext({
    required this.projectId,
    required this.contextRef,
    required this.resolver,
    required this.store,
  });
}

/// A deterministic tool: binds one [ProOrchestratorToolId] to a pure engine.
///
/// [run] resolves its inputs LOCALLY (never from `step.objective`/`explanation`
/// or any Cloud free text), calls the existing engine, stores the numeric
/// artifact at `step.outputRef`, and returns a reference-only result. It throws
/// a [ProToolException] on any typed failure.
abstract interface class ProToolAdapter {
  ProOrchestratorToolId get toolId;
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step);
}

/// Static, enum-keyed registry of deterministic tools.
///
/// - Registration is by [ProOrchestratorToolId] only — no reflection, no
///   arbitrary string tool names.
/// - Controlled actions cannot be registered: they are not members of
///   [ProOrchestratorToolId], so no adapter can even name one.
/// - Duplicate/override registration of the same tool id is refused at build.
/// - [execute] takes a typed [ProOrchestratorStep]; a valid-but-unregistered
///   tool yields [ProToolFailureCode.unsupportedTool].
class ProDeterministicToolRegistry {
  final Map<ProOrchestratorToolId, ProToolAdapter> _adapters;

  ProDeterministicToolRegistry(List<ProToolAdapter> adapters)
      : _adapters = _build(adapters);

  static Map<ProOrchestratorToolId, ProToolAdapter> _build(
      List<ProToolAdapter> adapters) {
    final map = <ProOrchestratorToolId, ProToolAdapter>{};
    for (final adapter in adapters) {
      if (map.containsKey(adapter.toolId)) {
        throw ProToolException(
            ProToolFailureCode.duplicateRegistration,
            'tool ${adapter.toolId.name} is registered more than once — '
            'override is not allowed.');
      }
      map[adapter.toolId] = adapter;
    }
    return Map.unmodifiable(map);
  }

  bool supports(ProOrchestratorToolId toolId) => _adapters.containsKey(toolId);

  Set<ProOrchestratorToolId> get registered => _adapters.keys.toSet();

  /// Runs [step]'s tool. Returns a typed outcome; never throws for a tool-level
  /// failure. Verifies the adapter actually stored an artifact at the declared
  /// outputRef.
  ProToolExecutionOutcome execute(
      ProOrchestratorStep step, ProToolExecutionContext ctx) {
    final adapter = _adapters[step.toolId];
    if (adapter == null) {
      return ProToolFailure(ProToolFailureCode.unsupportedTool,
          'tool ${step.toolId.name} is not registered.');
    }
    try {
      final result = adapter.run(ctx, step);
      if (!ctx.store.has(ctx.projectId, step.outputRef)) {
        return ProToolFailure(
            ProToolFailureCode.engineError,
            'adapter for ${step.toolId.name} did not store an artifact at '
            '${step.outputRef}.');
      }
      return ProToolSuccess(result);
    } on ProToolException catch (e) {
      return ProToolFailure(e.code, e.message);
    } catch (e) {
      return ProToolFailure(ProToolFailureCode.engineError, e.toString());
    }
  }
}

/// Shared helpers for adapters — kept here so each adapter stays tiny and the
/// reference-only result shape is identical across tools.
extension ProToolAdapterSupport on ProToolAdapter {
  /// The single input reference a one-input tool expects. Zero or many refs is
  /// a typed [ProToolFailureCode.missingReference] — a step must be explicit.
  String singleInputRef(ProOrchestratorStep step) {
    if (step.inputRefs.length != 1) {
      throw ProToolException(
          ProToolFailureCode.missingReference,
          '${step.toolId.name} expects exactly one inputRef, got '
          '${step.inputRefs.length}.');
    }
    return step.inputRefs.single;
  }

  /// The two input references a two-input tool expects (first, second).
  /// Zero, one, or more than two refs throws [ProToolFailureCode.missingReference].
  (String, String) pairedInputRefs(ProOrchestratorStep step) {
    if (step.inputRefs.length != 2) {
      throw ProToolException(
          ProToolFailureCode.missingReference,
          '${step.toolId.name} expects exactly two inputRefs, got '
          '${step.inputRefs.length}.');
    }
    return (step.inputRefs[0], step.inputRefs[1]);
  }

  /// A reference-only result. The resultId is a deterministic, opaque function
  /// of the outputRef (no DateTime/sequence), and evidence points at the stored
  /// artifact — no numbers ride along.
  ProOrchestratorResult referenceResult(
    ProOrchestratorStep step, {
    required ProConfidence confidence,
    String summary = '',
  }) =>
      ProOrchestratorResult(
        resultId: 'result:${step.outputRef}',
        toolId: step.toolId,
        inputRefs: step.inputRefs,
        outputRef: step.outputRef,
        evidenceRefs: [step.outputRef],
        confidence: confidence,
        summary: summary,
      );
}
