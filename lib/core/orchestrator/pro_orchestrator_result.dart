import 'pro_orchestrator_types.dart';

/// The outcome of running one deterministic tool, as the Orchestrator and the
/// LLM see it.
///
/// A result POINTS at what the tool produced ([outputRef], [candidateRefs],
/// [evidenceRefs]) and describes it in words ([summary], [warnings],
/// [nextActions]) with a coarse [confidence] enum. The actual numbers the tool
/// computed live behind those references, owned by the deterministic engine —
/// this object never contains a frequency, gain, Q, or coefficient, so a tool
/// result can be shown to an LLM for comparison/explanation without leaking a
/// DSP value.
class ProOrchestratorResult {
  final int schemaVersion;
  final String resultId;
  final ProOrchestratorToolId toolId;
  final List<String> inputRefs;
  final String outputRef;
  final List<String> candidateRefs;
  final List<String> evidenceRefs;
  final ProConfidence confidence;
  final List<String> warnings;
  final String summary;
  final List<String> nextActions;

  const ProOrchestratorResult({
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.resultId,
    required this.toolId,
    this.inputRefs = const [],
    required this.outputRef,
    this.candidateRefs = const [],
    this.evidenceRefs = const [],
    required this.confidence,
    this.warnings = const [],
    this.summary = '',
    this.nextActions = const [],
  });

  static const _allowedKeys = {
    'schemaVersion',
    'resultId',
    'toolId',
    'inputRefs',
    'outputRef',
    'candidateRefs',
    'evidenceRefs',
    'confidence',
    'warnings',
    'summary',
    'nextActions',
  };

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'resultId': resultId,
        'toolId': toolId.toJson(),
        'inputRefs': inputRefs,
        'outputRef': outputRef,
        'candidateRefs': candidateRefs,
        'evidenceRefs': evidenceRefs,
        'confidence': confidence.toJson(),
        'warnings': warnings,
        'summary': summary,
        'nextActions': nextActions,
      };

  factory ProOrchestratorResult.fromJson(Map<String, dynamic> json) {
    const ctx = 'ProOrchestratorResult';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);
    return ProOrchestratorResult(
      schemaVersion: kProOrchestratorSchemaVersion,
      resultId: ProContract.requireString(json, 'resultId', ctx),
      toolId: ProOrchestratorToolId.parse(json['toolId'], ctx),
      inputRefs: ProContract.stringList(json, 'inputRefs', ctx),
      outputRef: ProContract.requireString(json, 'outputRef', ctx),
      candidateRefs: ProContract.stringList(json, 'candidateRefs', ctx),
      evidenceRefs: ProContract.stringList(json, 'evidenceRefs', ctx),
      confidence: ProConfidence.parse(json['confidence'], ctx),
      warnings: ProContract.stringList(json, 'warnings', ctx),
      summary: ProContract.optionalString(json, 'summary', ctx) ?? '',
      nextActions: ProContract.stringList(json, 'nextActions', ctx),
    );
  }
}
