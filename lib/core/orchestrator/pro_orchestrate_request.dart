import 'pro_acoustic_intent.dart';
import 'pro_orchestrator_context.dart';
import 'pro_orchestrator_types.dart';

// TRUST BOUNDARY. Wrapper for the aiOrchestratePro Cloud Function request.
// Carries only perceptual intent and opaque context references — no DSP number,
// no frequency, no gain, no Q, no coefficient, no address.
//
// [ProContract.ensureKeys] enforces this at parse time in both this wrapper and
// every nested model. A forbidden key in any layer throws [ProContractException]
// before any value reaches the engine.

/// The request envelope sent to the `aiOrchestratePro` Cloud Function.
///
/// The LLM on the Cloud side sees only [intent] (perceptual goals) and
/// [context] (opaque reference strings). It returns a [ProOrchestratorPlan]
/// naming deterministic tools to run — it never receives or returns a DSP
/// number.
///
/// Invariant: [projectId] == [context.projectId]. Both [fromJson] and
/// [toJson] round-trips preserve this.
class ProOrchestrateRequest {
  final int schemaVersion;
  final String projectId;
  final ProAcousticIntent intent;
  final ProOrchestratorContext context;

  const ProOrchestrateRequest({
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.projectId,
    required this.intent,
    required this.context,
  });

  static const _allowedKeys = {
    'schemaVersion',
    'projectId',
    'intent',
    'context',
  };

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'projectId': projectId,
        'intent': intent.toJson(),
        'context': context.toJson(),
      };

  factory ProOrchestrateRequest.fromJson(Map<String, dynamic> json) {
    const ctx = 'ProOrchestrateRequest';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);

    final projectId = ProContract.requireString(json, 'projectId', ctx);

    // Parse context first so we can compare projectId before proceeding.
    final context = ProOrchestratorContext.fromJson(
        ProContract.asObject(json['context'], '$ctx.context'));

    if (projectId != context.projectId) {
      throw ProContractException(
          '$ctx: top-level projectId "$projectId" does not match '
          'context.projectId "${context.projectId}".');
    }

    final intent = ProAcousticIntent.fromJson(
        ProContract.asObject(json['intent'], '$ctx.intent'));

    return ProOrchestrateRequest(
      projectId: projectId,
      intent: intent,
      context: context,
    );
  }
}
