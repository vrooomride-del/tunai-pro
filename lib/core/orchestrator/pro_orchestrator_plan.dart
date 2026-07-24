import 'pro_orchestrator_types.dart';

/// One step of an Orchestrator work plan: a single deterministic tool to run.
///
/// A step names a [ProOrchestratorToolId] (read/calculate only), an [objective]
/// in words, the [inputRefs] it consumes and the single [outputRef] it
/// produces — all opaque references, never data. There is deliberately NO
/// `parameters`/`arguments` map: a step cannot carry a dynamic bag of values,
/// so an LLM cannot hand the engine a DSP number through a step.
class ProOrchestratorStep {
  final String stepId;
  final ProOrchestratorToolId toolId;
  final String objective;
  final List<String> inputRefs;
  final String outputRef;
  final bool requiresUserConfirmation;
  final String explanation;

  const ProOrchestratorStep({
    required this.stepId,
    required this.toolId,
    required this.objective,
    required this.inputRefs,
    required this.outputRef,
    required this.requiresUserConfirmation,
    this.explanation = '',
  });

  static const _allowedKeys = {
    'stepId',
    'toolId',
    'objective',
    'inputRefs',
    'outputRef',
    'requiresUserConfirmation',
    'explanation',
  };

  Map<String, dynamic> toJson() => {
        'stepId': stepId,
        'toolId': toolId.toJson(),
        'objective': objective,
        'inputRefs': inputRefs,
        'outputRef': outputRef,
        'requiresUserConfirmation': requiresUserConfirmation,
        'explanation': explanation,
      };

  factory ProOrchestratorStep.fromJson(Map<String, dynamic> json, String ctx) {
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    return ProOrchestratorStep(
      stepId: ProContract.requireString(json, 'stepId', ctx),
      toolId: ProOrchestratorToolId.parse(json['toolId'], ctx),
      objective: ProContract.requireString(json, 'objective', ctx),
      inputRefs: ProContract.stringList(json, 'inputRefs', ctx),
      outputRef: ProContract.requireString(json, 'outputRef', ctx),
      requiresUserConfirmation:
          ProContract.requireBool(json, 'requiresUserConfirmation', ctx),
      explanation: ProContract.optionalString(json, 'explanation', ctx) ?? '',
    );
  }
}

/// An ordered plan of read/calculate steps the Orchestrator proposes.
///
/// The plan references its intent and context by id ([intentRef]/[contextRef])
/// rather than embedding them. Step order is significant and preserved.
/// Structural invariants are enforced at parse time: a plan must have at least
/// one step, and both `stepId` and `outputRef` must be unique across steps.
class ProOrchestratorPlan {
  final String planId;
  final int schemaVersion;
  final String intentRef;
  final String contextRef;
  final List<ProOrchestratorStep> steps;
  final String summary;
  final List<String> warnings;
  final String completionCriteria;

  const ProOrchestratorPlan({
    required this.planId,
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.intentRef,
    required this.contextRef,
    required this.steps,
    this.summary = '',
    this.warnings = const [],
    this.completionCriteria = '',
  });

  static const _allowedKeys = {
    'planId',
    'schemaVersion',
    'intentRef',
    'contextRef',
    'steps',
    'summary',
    'warnings',
    'completionCriteria',
  };

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'schemaVersion': schemaVersion,
        'intentRef': intentRef,
        'contextRef': contextRef,
        'steps': [for (final s in steps) s.toJson()],
        'summary': summary,
        'warnings': warnings,
        'completionCriteria': completionCriteria,
      };

  factory ProOrchestratorPlan.fromJson(Map<String, dynamic> json) {
    const ctx = 'ProOrchestratorPlan';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);

    final rawSteps = json['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      throw ProContractException(
          '$ctx: "steps" must be a non-empty list — an empty plan is not a '
          'valid plan.');
    }
    final steps = [
      for (var i = 0; i < rawSteps.length; i++)
        ProOrchestratorStep.fromJson(
            ProContract.asObject(rawSteps[i], '$ctx.steps[$i]'),
            '$ctx.steps[$i]')
    ];

    final seenStepIds = <String>{};
    final seenOutputRefs = <String>{};
    for (final s in steps) {
      if (!seenStepIds.add(s.stepId)) {
        throw ProContractException('$ctx: duplicate stepId "${s.stepId}".');
      }
      if (!seenOutputRefs.add(s.outputRef)) {
        throw ProContractException(
            '$ctx: duplicate outputRef "${s.outputRef}" — each step must '
            'produce a distinct output.');
      }
    }

    return ProOrchestratorPlan(
      planId: ProContract.requireString(json, 'planId', ctx),
      schemaVersion: kProOrchestratorSchemaVersion,
      intentRef: ProContract.requireString(json, 'intentRef', ctx),
      contextRef: ProContract.requireString(json, 'contextRef', ctx),
      steps: steps,
      summary: ProContract.optionalString(json, 'summary', ctx) ?? '',
      warnings: ProContract.stringList(json, 'warnings', ctx),
      completionCriteria:
          ProContract.optionalString(json, 'completionCriteria', ctx) ?? '',
    );
  }
}
