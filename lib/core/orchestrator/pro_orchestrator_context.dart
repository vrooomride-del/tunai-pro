import 'pro_orchestrator_types.dart';

/// The working context the Orchestrator reasons over — REFERENCES and STATE
/// only, never the underlying data.
///
/// Measurements, tunings, DSP targets and candidates are named by opaque id
/// strings; the real arrays and values stay in their repositories/stores and
/// are resolved later by a local Tool Facade (not modelled in this commit).
/// There is no board address, no transport payload, and no raw measurement
/// array here — so the context can be handed to an LLM without ever exposing a
/// DSP number or a hardware detail.
class ProOrchestratorContext {
  final int schemaVersion;
  final String projectId;
  final String? speakerProfileRef;
  final String? systemProfileRef;
  final List<String> measurementRefs;
  final String? currentTuningRef;
  final String? dspTargetRef;
  final ProConnectionState connectionState;

  /// A descriptor of what readback proved (e.g. 'ch0_band0_verified'), never
  /// the read values themselves.
  final String? readbackEvidence;

  final String? safetyPolicyRef;
  final List<String> candidateRefs;
  final List<String> historyRefs;

  const ProOrchestratorContext({
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.projectId,
    this.speakerProfileRef,
    this.systemProfileRef,
    this.measurementRefs = const [],
    this.currentTuningRef,
    this.dspTargetRef,
    required this.connectionState,
    this.readbackEvidence,
    this.safetyPolicyRef,
    this.candidateRefs = const [],
    this.historyRefs = const [],
  });

  static const _allowedKeys = {
    'schemaVersion',
    'projectId',
    'speakerProfileRef',
    'systemProfileRef',
    'measurementRefs',
    'currentTuningRef',
    'dspTargetRef',
    'connectionState',
    'readbackEvidence',
    'safetyPolicyRef',
    'candidateRefs',
    'historyRefs',
  };

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'projectId': projectId,
        if (speakerProfileRef != null) 'speakerProfileRef': speakerProfileRef,
        if (systemProfileRef != null) 'systemProfileRef': systemProfileRef,
        'measurementRefs': measurementRefs,
        if (currentTuningRef != null) 'currentTuningRef': currentTuningRef,
        if (dspTargetRef != null) 'dspTargetRef': dspTargetRef,
        'connectionState': connectionState.toJson(),
        if (readbackEvidence != null) 'readbackEvidence': readbackEvidence,
        if (safetyPolicyRef != null) 'safetyPolicyRef': safetyPolicyRef,
        'candidateRefs': candidateRefs,
        'historyRefs': historyRefs,
      };

  factory ProOrchestratorContext.fromJson(Map<String, dynamic> json) {
    const ctx = 'ProOrchestratorContext';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);
    return ProOrchestratorContext(
      schemaVersion: kProOrchestratorSchemaVersion,
      projectId: ProContract.requireString(json, 'projectId', ctx),
      speakerProfileRef:
          ProContract.optionalString(json, 'speakerProfileRef', ctx),
      systemProfileRef:
          ProContract.optionalString(json, 'systemProfileRef', ctx),
      measurementRefs: ProContract.stringList(json, 'measurementRefs', ctx),
      currentTuningRef:
          ProContract.optionalString(json, 'currentTuningRef', ctx),
      dspTargetRef: ProContract.optionalString(json, 'dspTargetRef', ctx),
      connectionState: ProConnectionState.parse(json['connectionState'], ctx),
      readbackEvidence:
          ProContract.optionalString(json, 'readbackEvidence', ctx),
      safetyPolicyRef: ProContract.optionalString(json, 'safetyPolicyRef', ctx),
      candidateRefs: ProContract.stringList(json, 'candidateRefs', ctx),
      historyRefs: ProContract.stringList(json, 'historyRefs', ctx),
    );
  }
}
