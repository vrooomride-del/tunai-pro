// TUNAI PRO — AI Orchestrator domain contract: shared enums + STRICT parsing.
//
// TRUST BOUNDARY. Every model in `lib/core/orchestrator/` is LLM-facing or
// Orchestrator-facing. The whole point of these types is that a cloud/LLM
// response can carry intent, plans, references and explanations — but NEVER a
// directly-applicable DSP value. That guarantee is enforced two ways:
//
//   1. STRUCTURE: no model here has a frequency/gain/Q/delay/coefficient/
//      address/payload field. The deterministic `pro_*` engines own every
//      number; the Orchestrator only ever names a candidate/measurement/
//      output by an opaque *reference string*. There is simply nowhere in
//      these types to put a DSP number.
//   2. PARSING: [ProContract] rejects, at parse time (Release included, not
//      just `assert`), any JSON that (a) uses an unknown key, (b) uses a
//      forbidden DSP key in any snake/camel case, (c) carries an unknown enum
//      value, or (d) declares an unsupported schema version. Unknown keys are
//      NEVER silently ignored.
//
// Controlled actions (Apply / Deploy / hardware write / transport / SafeLoad /
// EEPROM) are deliberately ABSENT from [ProOrchestratorToolId] — the LLM plan
// can only request read/calculate tools. Applying a result lives behind the
// user + Safety Validator, in a layer this contract does not model.

/// The current schema version for every Orchestrator contract model. A
/// contract-permitted number (unlike DSP numbers, which are forbidden).
const int kProOrchestratorSchemaVersion = 1;

/// Thrown when JSON violates the Orchestrator trust boundary. A
/// [FormatException] subtype so existing `on FormatException` handlers catch
/// it, but distinct so callers can single it out.
class ProContractException extends FormatException {
  ProContractException(super.message);

  @override
  String toString() => 'ProContractException: $message';
}

/// Read/Calculate tools the Orchestrator may request. These are the ONLY tool
/// identities that can appear in a plan.
///
/// Controlled actions are intentionally not members: there is no `apply`,
/// `deploy`, `write`, `transport`, `address`, `safeLoad`, `eeprom`, or
/// `selfBoot` here, and there never will be — applying a candidate is a
/// user-approved, Safety-Validator-gated action modelled elsewhere, not a tool
/// the LLM can schedule.
enum ProOrchestratorToolId {
  measurementAnalyze,
  impedanceAnalyze,
  speakerCapability,
  targetDefine,
  crossoverPlan,
  peqOptimize,
  phaseAlign,
  delayAlign,
  gainPlan,
  simulate,
  protectionAnalyze,
  compareCandidates,
  generateReport;

  String toJson() => name;

  static ProOrchestratorToolId parse(Object? raw, String ctx) =>
      ProContract.parseEnum(values, (e) => e.name, raw, 'toolId', ctx);
}

/// Coarse confidence, never a raw probability. A double is explicitly refused
/// (see [ProContract.parseEnum]) so a model can never smuggle a number in
/// through this field.
enum ProConfidence {
  low,
  medium,
  high;

  String toJson() => name;

  static ProConfidence parse(Object? raw, String ctx) =>
      ProContract.parseEnum(values, (e) => e.name, raw, 'confidence', ctx);
}

/// Lifecycle of a whole plan.
enum ProPlanStatus {
  draft,
  ready,
  inProgress,
  completed,
  rejected;

  String toJson() => name;

  static ProPlanStatus parse(Object? raw, String ctx) =>
      ProContract.parseEnum(values, (e) => e.name, raw, 'planStatus', ctx);
}

/// Lifecycle of a single step.
enum ProStepStatus {
  pending,
  running,
  done,
  skipped,
  failed;

  String toJson() => name;

  static ProStepStatus parse(Object? raw, String ctx) =>
      ProContract.parseEnum(values, (e) => e.name, raw, 'stepStatus', ctx);
}

/// How much explanation the user wants — drives wording, not DSP.
enum ProExplanationLevel {
  beginner,
  intermediate,
  expert;

  String toJson() => name;

  static ProExplanationLevel parse(Object? raw, String ctx) =>
      ProContract.parseEnum(
          values, (e) => e.name, raw, 'explanationLevel', ctx);
}

/// Perceptual tuning priority. A direction, not a number.
enum ProTuningPriority {
  balanced,
  roomAdaptation,
  faithfulToFactory,
  personalPreference;

  String toJson() => name;

  static ProTuningPriority parse(Object? raw, String ctx) =>
      ProContract.parseEnum(values, (e) => e.name, raw, 'tuningPriority', ctx);
}

/// Perceptual tonal areas the intent may allow-to-change or protect. These are
/// human-facing regions, NOT frequency bands — there is no Hz here on purpose,
/// so allow/protect can never be read as a filter parameter.
enum ProToneArea {
  lowEnd,
  midRange,
  highEnd,
  overallTone,
  spatialImage;

  String toJson() => name;

  static ProToneArea parse(Object? raw, String ctx) =>
      ProContract.parseEnum(values, (e) => e.name, raw, 'toneArea', ctx);
}

/// Connection/readback posture, referenced (not duplicated) by the context.
enum ProConnectionState {
  disconnected,
  connecting,
  connected,
  readbackVerified;

  String toJson() => name;

  static ProConnectionState parse(Object? raw, String ctx) =>
      ProContract.parseEnum(values, (e) => e.name, raw, 'connectionState', ctx);
}

/// Strict parsing primitives shared by every Orchestrator model.
///
/// Not a general JSON helper — every method here fails CLOSED. Anything not
/// explicitly permitted is rejected with a [ProContractException].
abstract final class ProContract {
  /// DSP concepts that must never be a key in an Orchestrator payload,
  /// normalised (lowercased, underscores stripped) so snake_case and camelCase
  /// variants are all caught: `gain_db`, `gainDb`, `GAINDB` → `gaindb`.
  ///
  /// This is defence-in-depth. The primary guard is [ensureKeys]'s allowlist
  /// (an unknown key is rejected regardless); this set exists so the *common*
  /// smuggling attempts fail with an explicit, unambiguous message.
  static const Set<String> forbiddenKeyTokens = {
    'frequency',
    'frequencyhz',
    'gain',
    'gaindb',
    'q',
    'delay',
    'delayms',
    'coefficient',
    'coefficients',
    'biquad',
    'address',
    'register',
    'payload',
    'packet',
    'rawvalue',
    'limitervalue',
    'safeload',
    'eeprom',
    'selfboot',
    'transportcommand',
  };

  static String _norm(String key) => key.toLowerCase().replaceAll('_', '');

  /// Asserts [json] contains ONLY keys in [allowed]. A forbidden DSP key throws
  /// with a pointed message; any other unknown key throws too — unknown keys
  /// are never silently dropped.
  static void ensureKeys(
    Map<String, dynamic> json,
    Set<String> allowed,
    String ctx,
  ) {
    for (final key in json.keys) {
      final norm = _norm(key);
      if (forbiddenKeyTokens.contains(norm)) {
        throw ProContractException(
            '$ctx: forbidden DSP-value key "$key". The Orchestrator contract '
            'carries references and descriptors only — never a DSP number.');
      }
      if (!allowed.contains(key)) {
        throw ProContractException(
            '$ctx: unknown key "$key". Allowed keys: ${allowed.join(', ')}.');
      }
    }
  }

  /// [json] must be a `Map<String, dynamic>`; anything else throws.
  static Map<String, dynamic> asObject(Object? raw, String ctx) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    throw ProContractException(
        '$ctx: expected a JSON object, got ${raw.runtimeType}.');
  }

  /// The schema version field: must be exactly [kProOrchestratorSchemaVersion]
  /// as an int. A missing, non-int, or unsupported value throws. This is the
  /// one number the contract permits.
  static int requireSchemaVersion(Map<String, dynamic> json, String ctx) {
    final v = json['schemaVersion'];
    if (v is! int) {
      throw ProContractException(
          '$ctx: schemaVersion must be an int, got ${v.runtimeType}.');
    }
    if (v != kProOrchestratorSchemaVersion) {
      throw ProContractException('$ctx: unsupported schemaVersion $v (expected '
          '$kProOrchestratorSchemaVersion).');
    }
    return v;
  }

  /// Exactly-one enum match by [nameOf]. A non-String or unmatched value throws
  /// — an unknown enum string is never coerced to a default, and a numeric
  /// value (e.g. a probability where a confidence enum belongs) is refused.
  static T parseEnum<T>(
    List<T> values,
    String Function(T) nameOf,
    Object? raw,
    String field,
    String ctx,
  ) {
    if (raw is! String) {
      throw ProContractException(
          '$ctx: $field must be an enum string, got ${raw.runtimeType}.');
    }
    for (final v in values) {
      if (nameOf(v) == raw) return v;
    }
    throw ProContractException(
        '$ctx: $field has unknown value "$raw". Allowed: '
        '${values.map(nameOf).join(', ')}.');
  }

  /// A required non-empty string.
  static String requireString(
      Map<String, dynamic> json, String key, String ctx) {
    final v = json[key];
    if (v is! String || v.isEmpty) {
      throw ProContractException('$ctx: "$key" must be a non-empty string.');
    }
    return v;
  }

  /// An optional string (absent → null). If present it must be a String.
  static String? optionalString(
      Map<String, dynamic> json, String key, String ctx) {
    if (!json.containsKey(key)) return null;
    final v = json[key];
    if (v is! String) {
      throw ProContractException('$ctx: "$key" must be a string when present.');
    }
    return v;
  }

  /// A required bool.
  static bool requireBool(Map<String, dynamic> json, String key, String ctx) {
    final v = json[key];
    if (v is! bool) {
      throw ProContractException('$ctx: "$key" must be a bool.');
    }
    return v;
  }

  /// A list of plain strings (absent → empty). Every element must be a String;
  /// a nested object or number is refused, so no parameter map can hide inside
  /// a "refs" array.
  static List<String> stringList(
      Map<String, dynamic> json, String key, String ctx) {
    if (!json.containsKey(key)) return const [];
    final v = json[key];
    if (v is! List) {
      throw ProContractException('$ctx: "$key" must be a list of strings.');
    }
    return [
      for (var i = 0; i < v.length; i++)
        if (v[i] is String)
          v[i] as String
        else
          throw ProContractException(
              '$ctx: "$key"[$i] must be a string, got ${v[i].runtimeType}.')
    ];
  }
}
