import 'pro_orchestrator_types.dart';

/// The expert's tuning intent, as the PRO Orchestrator understands it.
///
/// This is NOT a copy of the Consumer `AcousticIntent` — it is the Pro-side,
/// expert-facing intent that steers a work plan. Like the Consumer contract it
/// is PERCEPTUAL: every field is a goal, a descriptor, or an allow/protect
/// area. There is no frequency, gain, Q, delay, coefficient, address, or
/// payload here, and [freeTextContext] is explicitly a human note — it is
/// carried as an opaque string and is never parsed into an engine parameter
/// (a request like "cut 80 Hz" survives as text but produces no DSP value).
class ProAcousticIntent {
  final int schemaVersion;

  /// What the expert is trying to achieve, in words (e.g. 'tighter low end
  /// without losing warmth').
  final String userGoal;

  /// The problem the expert perceives, in words (e.g. 'boomy near the wall').
  final String perceivedProblem;

  /// Which part of the system this intent addresses, as a descriptor (e.g.
  /// 'full_system', 'woofer_channel'). A label, not an address.
  final String systemScope;

  final ProTuningPriority tuningPriority;

  /// Perceptual areas the expert permits changing.
  final List<ProToneArea> allowedChangeAreas;

  /// Perceptual areas the expert wants preserved. Must not overlap
  /// [allowedChangeAreas].
  final List<ProToneArea> protectedAreas;

  /// The listening situation, in words (e.g. 'near-field desk, small room').
  final String listeningContext;

  final ProExplanationLevel explanationLevel;

  /// Free human note. Opaque by contract: never converted to an engine
  /// parameter. May contain numbers/words with no effect on any DSP value.
  final String freeTextContext;

  const ProAcousticIntent({
    this.schemaVersion = kProOrchestratorSchemaVersion,
    required this.userGoal,
    required this.perceivedProblem,
    required this.systemScope,
    required this.tuningPriority,
    required this.allowedChangeAreas,
    required this.protectedAreas,
    required this.listeningContext,
    required this.explanationLevel,
    this.freeTextContext = '',
  });

  static const _allowedKeys = {
    'schemaVersion',
    'userGoal',
    'perceivedProblem',
    'systemScope',
    'tuningPriority',
    'allowedChangeAreas',
    'protectedAreas',
    'listeningContext',
    'explanationLevel',
    'freeTextContext',
  };

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'userGoal': userGoal,
        'perceivedProblem': perceivedProblem,
        'systemScope': systemScope,
        'tuningPriority': tuningPriority.toJson(),
        'allowedChangeAreas': [for (final a in allowedChangeAreas) a.toJson()],
        'protectedAreas': [for (final a in protectedAreas) a.toJson()],
        'listeningContext': listeningContext,
        'explanationLevel': explanationLevel.toJson(),
        'freeTextContext': freeTextContext,
      };

  factory ProAcousticIntent.fromJson(Map<String, dynamic> json) {
    const ctx = 'ProAcousticIntent';
    ProContract.ensureKeys(json, _allowedKeys, ctx);
    ProContract.requireSchemaVersion(json, ctx);

    final allowed = _parseAreas(json, 'allowedChangeAreas', ctx);
    final protected = _parseAreas(json, 'protectedAreas', ctx);
    final overlap = allowed.toSet().intersection(protected.toSet());
    if (overlap.isNotEmpty) {
      throw ProContractException(
          '$ctx: ${overlap.map((e) => e.name).join(', ')} appear in both '
          'allowedChangeAreas and protectedAreas — an area cannot be both '
          'changeable and protected.');
    }

    return ProAcousticIntent(
      schemaVersion: kProOrchestratorSchemaVersion,
      userGoal: ProContract.requireString(json, 'userGoal', ctx),
      perceivedProblem:
          ProContract.requireString(json, 'perceivedProblem', ctx),
      systemScope: ProContract.requireString(json, 'systemScope', ctx),
      tuningPriority: ProTuningPriority.parse(json['tuningPriority'], ctx),
      allowedChangeAreas: allowed,
      protectedAreas: protected,
      listeningContext:
          ProContract.requireString(json, 'listeningContext', ctx),
      explanationLevel:
          ProExplanationLevel.parse(json['explanationLevel'], ctx),
      freeTextContext:
          ProContract.optionalString(json, 'freeTextContext', ctx) ?? '',
    );
  }

  static List<ProToneArea> _parseAreas(
      Map<String, dynamic> json, String key, String ctx) {
    final raw = json[key];
    if (raw == null) return const [];
    if (raw is! List) {
      throw ProContractException('$ctx: "$key" must be a list of tone areas.');
    }
    return [for (final e in raw) ProToneArea.parse(e, '$ctx.$key')];
  }
}
