import 'pro_explanation.dart';
import 'pro_orchestrator_plan.dart';
import 'pro_orchestrator_types.dart';

// TRUST BOUNDARY. Wrapper for the aiOrchestratePro Cloud Function response.
// The LLM returns a plan (ordered tool references) and an explanation (prose).
// Neither carries a DSP number — [ProOrchestratorPlan.fromJson] and
// [ProExplanation.fromJson] both call [ProContract.ensureKeys], so forbidden
// keys in nested objects are rejected at parse time.

/// The response envelope returned by the `aiOrchestratePro` Cloud Function.
///
/// [plan] is an ordered list of deterministic tool steps (read/calculate only).
/// [explanation] is LLM-authored prose describing the plan to the user.
/// Neither field can carry a DSP number — [ProContract.ensureKeys] enforces
/// this at every nesting level.
///
/// Pass [requestProjectId] to [fromJson] to assert that the Cloud response
/// belongs to the same project as the outgoing request. A mismatch throws
/// [ProContractException] before the plan is accepted.
class ProOrchestrateResponse {
  final int schemaVersion;
  final String projectId;
  final ProOrchestratorPlan plan;
  final ProExplanation explanation;

  const ProOrchestrateResponse({
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.projectId,
    required this.plan,
    required this.explanation,
  });

  static const _allowedKeys = {
    'schemaVersion',
    'projectId',
    'plan',
    'explanation',
  };

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'projectId': projectId,
        'plan': plan.toJson(),
        'explanation': explanation.toJson(),
      };

  /// Parses and validates a Cloud response.
  ///
  /// If [requestProjectId] is provided, the response [projectId] must match it
  /// exactly — a mismatch throws [ProContractException]. Pass the request's
  /// [ProOrchestrateRequest.projectId] here to prevent cross-project
  /// contamination.
  factory ProOrchestrateResponse.fromJson(
    Map<String, dynamic> json, {
    String? requestProjectId,
  }) {
    const ctx = 'ProOrchestrateResponse';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);

    final projectId = ProContract.requireString(json, 'projectId', ctx);

    if (requestProjectId != null && projectId != requestProjectId) {
      throw ProContractException(
          '$ctx: response projectId "$projectId" does not match request '
          'projectId "$requestProjectId".');
    }

    final plan = ProOrchestratorPlan.fromJson(
        ProContract.asObject(json['plan'], '$ctx.plan'));
    final explanation = ProExplanation.fromJson(
        ProContract.asObject(json['explanation'], '$ctx.explanation'));

    return ProOrchestrateResponse(
      projectId: projectId,
      plan: plan,
      explanation: explanation,
    );
  }
}
