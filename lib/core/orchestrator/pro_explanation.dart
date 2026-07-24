import 'pro_orchestrator_types.dart';

/// A user-facing explanation the Orchestrator surfaces (LLM-authored prose,
/// engine-owned facts).
///
/// Prose only: it says what the problem is, why a candidate was proposed, the
/// tradeoffs and the next step, tailored to [explanationLevel]. It references
/// candidates by id but carries no DSP number — the numbers stay with the
/// candidate. Free prose may legitimately mention "a little less low end", but
/// because there is no numeric field here, nothing in an explanation can be
/// consumed as an engine parameter.
class ProExplanation {
  final int schemaVersion;
  final String title;
  final String summary;
  final List<String> reasons;
  final List<String> tradeoffs;
  final List<String> warnings;
  final String nextStep;
  final ProExplanationLevel explanationLevel;
  final List<String> candidateRefs;

  const ProExplanation({
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.title,
    required this.summary,
    this.reasons = const [],
    this.tradeoffs = const [],
    this.warnings = const [],
    this.nextStep = '',
    required this.explanationLevel,
    this.candidateRefs = const [],
  });

  static const _allowedKeys = {
    'schemaVersion',
    'title',
    'summary',
    'reasons',
    'tradeoffs',
    'warnings',
    'nextStep',
    'explanationLevel',
    'candidateRefs',
  };

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'title': title,
        'summary': summary,
        'reasons': reasons,
        'tradeoffs': tradeoffs,
        'warnings': warnings,
        'nextStep': nextStep,
        'explanationLevel': explanationLevel.toJson(),
        'candidateRefs': candidateRefs,
      };

  factory ProExplanation.fromJson(Map<String, dynamic> json) {
    const ctx = 'ProExplanation';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);
    return ProExplanation(
      schemaVersion: kProOrchestratorSchemaVersion,
      title: ProContract.requireString(json, 'title', ctx),
      summary: ProContract.requireString(json, 'summary', ctx),
      reasons: ProContract.stringList(json, 'reasons', ctx),
      tradeoffs: ProContract.stringList(json, 'tradeoffs', ctx),
      warnings: ProContract.stringList(json, 'warnings', ctx),
      nextStep: ProContract.optionalString(json, 'nextStep', ctx) ?? '',
      explanationLevel:
          ProExplanationLevel.parse(json['explanationLevel'], ctx),
      candidateRefs: ProContract.stringList(json, 'candidateRefs', ctx),
    );
  }
}
