/// Measurement Evidence model — what confidence CAN be computed from, and from
/// what it explicitly CANNOT.
///
/// This is NOT the measurement data. The actual spectra (frequency / magnitude
/// / phase / impedance) live in [ParsedMeasurementData] / a measurement session
/// and are referenced here by opaque id only — never duplicated, never
/// serialized here. Evidence records the KIND of measurement, WHERE its data
/// is, WHICH confidence metrics it can back, which are UNAVAILABLE, and its
/// provenance — so a [MeasurementConfidenceResult] can be (re)computed under any
/// policy without the evidence itself carrying a confidence number.
///
/// Boundaries enforced by construction/parse:
///   • no raw spectrum / PCM / dynamic map is ever stored or serialized;
///   • a metric cannot be both available and unavailable;
///   • imported evidence cannot CLAIM repeatability/SNR/clipping — a single
///     imported curve has no such evidence;
///   • FRD is an acoustic-response measurement, ZMA is an impedance one, and
///     neither can masquerade as the other;
///   • placeholder / generated-demo evidence is never production-usable.
library;

/// Thrown when evidence data violates a model invariant. A [FormatException]
/// subtype so `on FormatException` catches it.
class MeasurementEvidenceException extends FormatException {
  MeasurementEvidenceException(super.message);
  @override
  String toString() => 'MeasurementEvidenceException: $message';
}

const int kMeasurementEvidenceSchemaVersion = 1;

/// The physical quantity a measurement describes.
enum MeasurementDomain {
  acousticResponse,
  impedance;

  String toJson() => name;
  static MeasurementDomain parse(Object? raw, String ctx) =>
      _EvidenceParse.enumValue(values, (e) => e.name, raw, 'domain', ctx);
}

/// Where a measurement came from. `placeholder`/`generatedDemo` are never real
/// evidence.
enum MeasurementSource {
  importedFrd,
  importedZma,
  liveMicrophone,
  generatedDemo,
  placeholder;

  String toJson() => name;
  static MeasurementSource parse(Object? raw, String ctx) =>
      _EvidenceParse.enumValue(values, (e) => e.name, raw, 'source', ctx);

  /// True only for evidence that can back a production decision. Placeholder
  /// and demo evidence never can.
  bool get isRealMeasurement =>
      this == importedFrd || this == importedZma || this == liveMicrophone;
}

/// Confidence-metric identifiers at the evidence layer. The first four mirror
/// `ConfidenceMetric`; [phase] and [calibration] are additional evidence kinds
/// tracked here but not (yet) scored by the confidence engine.
enum EvidenceMetric {
  repeatability,
  snr,
  validBandCoverage,
  clipping,
  phase,
  calibration;

  String toJson() => name;
  static EvidenceMetric parse(Object? raw, String ctx) =>
      _EvidenceParse.enumValue(values, (e) => e.name, raw, 'metric', ctx);
}

/// Where the evidence came from and how to identify it — never a file path or
/// raw content. [contentHash] is computed by the caller from the original
/// content; this model never reads a file. [capturedAtIso] is an optional,
/// caller-supplied label; it is NOT used in any deterministic computation.
class MeasurementProvenance {
  final String producer;
  final String producerVersion;
  final String sourceIdentity;
  final String? contentHash;
  final String? label;
  final String? capturedAtIso;

  const MeasurementProvenance({
    required this.producer,
    required this.producerVersion,
    required this.sourceIdentity,
    this.contentHash,
    this.label,
    this.capturedAtIso,
  });

  static const _keys = {
    'producer',
    'producerVersion',
    'sourceIdentity',
    'contentHash',
    'label',
    'capturedAtIso',
  };

  Map<String, dynamic> toJson() => {
        'producer': producer,
        'producerVersion': producerVersion,
        'sourceIdentity': sourceIdentity,
        if (contentHash != null) 'contentHash': contentHash,
        if (label != null) 'label': label,
        if (capturedAtIso != null) 'capturedAtIso': capturedAtIso,
      };

  factory MeasurementProvenance.fromJson(Map<String, dynamic> json) {
    const ctx = 'MeasurementProvenance';
    _EvidenceParse.ensureKeys(json, _keys, ctx);
    return MeasurementProvenance(
      producer: _EvidenceParse.requireString(json, 'producer', ctx),
      producerVersion:
          _EvidenceParse.requireString(json, 'producerVersion', ctx),
      sourceIdentity: _EvidenceParse.requireString(json, 'sourceIdentity', ctx),
      contentHash: _EvidenceParse.optionalString(json, 'contentHash', ctx),
      label: _EvidenceParse.optionalString(json, 'label', ctx),
      capturedAtIso: _EvidenceParse.optionalString(json, 'capturedAtIso', ctx),
    );
  }
}

/// Common evidence contract. Concrete kinds are [ImportedMeasurementEvidence]
/// and [MeasurementCaptureEvidence].
sealed class MeasurementEvidence {
  final int schemaVersion;
  final String evidenceId;
  final String projectId;
  final String measurementRef;
  final MeasurementDomain domain;
  final MeasurementSource source;
  final MeasurementProvenance provenance;
  final Set<EvidenceMetric> availableMetrics;
  final Set<EvidenceMetric> unavailableMetrics;

  const MeasurementEvidence({
    required this.schemaVersion,
    required this.evidenceId,
    required this.projectId,
    required this.measurementRef,
    required this.domain,
    required this.source,
    required this.provenance,
    required this.availableMetrics,
    required this.unavailableMetrics,
  });

  /// Placeholder/demo evidence is never production-usable.
  bool get isProductionUsable => source.isRealMeasurement;

  /// Discriminator for JSON.
  String get kind;

  Map<String, dynamic> baseJson() => {
        'kind': kind,
        'schemaVersion': schemaVersion,
        'evidenceId': evidenceId,
        'projectId': projectId,
        'measurementRef': measurementRef,
        'domain': domain.toJson(),
        'source': source.toJson(),
        'provenance': provenance.toJson(),
        'availableMetrics': [for (final m in availableMetrics) m.toJson()],
        'unavailableMetrics': [for (final m in unavailableMetrics) m.toJson()],
      };

  /// Dispatches on `kind`.
  factory MeasurementEvidence.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    return switch (kind) {
      'imported' => ImportedMeasurementEvidence.fromJson(json),
      'capture' => MeasurementCaptureEvidence.fromJson(json),
      _ => throw MeasurementEvidenceException('unknown evidence kind "$kind".'),
    };
  }

  /// Common invariants shared by all kinds.
  static void checkCommon({
    required int schemaVersion,
    required String evidenceId,
    required String projectId,
    required String measurementRef,
    required Set<EvidenceMetric> available,
    required Set<EvidenceMetric> unavailable,
  }) {
    if (schemaVersion != kMeasurementEvidenceSchemaVersion) {
      throw MeasurementEvidenceException(
          'unsupported schemaVersion $schemaVersion.');
    }
    if (evidenceId.isEmpty) {
      throw MeasurementEvidenceException('evidenceId must not be empty.');
    }
    if (projectId.isEmpty) {
      throw MeasurementEvidenceException('projectId must not be empty.');
    }
    if (measurementRef.isEmpty) {
      throw MeasurementEvidenceException('measurementRef must not be empty.');
    }
    final overlap = available.intersection(unavailable);
    if (overlap.isNotEmpty) {
      throw MeasurementEvidenceException(
          'metric(s) both available and unavailable: '
          '${overlap.map((e) => e.name).join(', ')}.');
    }
  }
}

/// Evidence for a measurement imported from a file (FRD or ZMA).
///
/// A single imported curve backs only coverage (and phase, if present). It
/// CANNOT back repeatability, SNR, or clipping — claiming so is rejected.
class ImportedMeasurementEvidence extends MeasurementEvidence {
  final String displayName;
  final String originalFormat;
  final String parserSchemaVersion;
  final bool magnitudePresent;
  final bool phasePresent;
  final bool impedancePresent;

  ImportedMeasurementEvidence({
    super.schemaVersion = kMeasurementEvidenceSchemaVersion,
    required super.evidenceId,
    required super.projectId,
    required super.measurementRef,
    required super.domain,
    required super.source,
    required super.provenance,
    required super.availableMetrics,
    required super.unavailableMetrics,
    required this.displayName,
    required this.originalFormat,
    required this.parserSchemaVersion,
    required this.magnitudePresent,
    required this.phasePresent,
    required this.impedancePresent,
  }) {
    _validate();
  }

  @override
  String get kind => 'imported';

  void _validate() {
    MeasurementEvidence.checkCommon(
      schemaVersion: schemaVersion,
      evidenceId: evidenceId,
      projectId: projectId,
      measurementRef: measurementRef,
      available: availableMetrics,
      unavailable: unavailableMetrics,
    );
    if (displayName.isEmpty) {
      throw MeasurementEvidenceException('displayName must not be empty.');
    }
    if (provenance.contentHash == null || provenance.contentHash!.isEmpty) {
      throw MeasurementEvidenceException(
          'imported evidence requires a provenance.contentHash.');
    }
    // Source must be an import kind.
    if (source != MeasurementSource.importedFrd &&
        source != MeasurementSource.importedZma) {
      throw MeasurementEvidenceException(
          'ImportedMeasurementEvidence source must be importedFrd/importedZma, '
          'got ${source.name}.');
    }
    // Import can never claim these — a single curve has no such evidence.
    for (final forbidden in const [
      EvidenceMetric.repeatability,
      EvidenceMetric.snr,
      EvidenceMetric.clipping,
    ]) {
      if (availableMetrics.contains(forbidden)) {
        throw MeasurementEvidenceException(
            'imported evidence cannot mark ${forbidden.name} available.');
      }
    }
    // FRD ↔ acoustic + magnitude; ZMA ↔ impedance + impedance data.
    if (source == MeasurementSource.importedFrd) {
      if (domain != MeasurementDomain.acousticResponse) {
        throw MeasurementEvidenceException(
            'FRD import must be acousticResponse domain.');
      }
      if (!magnitudePresent) {
        throw MeasurementEvidenceException(
            'FRD import must carry magnitude data.');
      }
    } else {
      // importedZma
      if (domain != MeasurementDomain.impedance) {
        throw MeasurementEvidenceException(
            'ZMA import must be impedance domain.');
      }
      if (!impedancePresent) {
        throw MeasurementEvidenceException(
            'ZMA import must carry impedance data.');
      }
    }
    // Phase availability must match the flag exactly.
    final claimsPhase = availableMetrics.contains(EvidenceMetric.phase);
    if (claimsPhase != phasePresent) {
      throw MeasurementEvidenceException(
          'phase availability ($claimsPhase) must match phasePresent '
          '($phasePresent).');
    }
    // Coverage is always backable by an imported curve.
    if (!availableMetrics.contains(EvidenceMetric.validBandCoverage)) {
      throw MeasurementEvidenceException(
          'imported evidence must mark validBandCoverage available.');
    }
  }

  static const _keys = {
    'kind',
    'schemaVersion',
    'evidenceId',
    'projectId',
    'measurementRef',
    'domain',
    'source',
    'provenance',
    'availableMetrics',
    'unavailableMetrics',
    'displayName',
    'originalFormat',
    'parserSchemaVersion',
    'magnitudePresent',
    'phasePresent',
    'impedancePresent',
  };

  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'displayName': displayName,
        'originalFormat': originalFormat,
        'parserSchemaVersion': parserSchemaVersion,
        'magnitudePresent': magnitudePresent,
        'phasePresent': phasePresent,
        'impedancePresent': impedancePresent,
      };

  factory ImportedMeasurementEvidence.fromJson(Map<String, dynamic> json) {
    const ctx = 'ImportedMeasurementEvidence';
    _EvidenceParse.ensureKeys(json, _keys, ctx);
    return ImportedMeasurementEvidence(
      schemaVersion: _EvidenceParse.requireSchemaVersion(json, ctx),
      evidenceId: _EvidenceParse.requireString(json, 'evidenceId', ctx),
      projectId: _EvidenceParse.requireString(json, 'projectId', ctx),
      measurementRef: _EvidenceParse.requireString(json, 'measurementRef', ctx),
      domain: MeasurementDomain.parse(json['domain'], ctx),
      source: MeasurementSource.parse(json['source'], ctx),
      provenance: MeasurementProvenance.fromJson(
          _EvidenceParse.object(json['provenance'], ctx)),
      availableMetrics: _EvidenceParse.metricSet(json, 'availableMetrics', ctx),
      unavailableMetrics:
          _EvidenceParse.metricSet(json, 'unavailableMetrics', ctx),
      displayName: _EvidenceParse.requireString(json, 'displayName', ctx),
      originalFormat: _EvidenceParse.requireString(json, 'originalFormat', ctx),
      parserSchemaVersion:
          _EvidenceParse.requireString(json, 'parserSchemaVersion', ctx),
      magnitudePresent:
          _EvidenceParse.requireBool(json, 'magnitudePresent', ctx),
      phasePresent: _EvidenceParse.requireBool(json, 'phasePresent', ctx),
      impedancePresent:
          _EvidenceParse.requireBool(json, 'impedancePresent', ctx),
    );
  }
}

/// Evidence for a live microphone capture. This commit provides the CONTRACT
/// only — no capture is wired here. Fields that a capture did not actually
/// produce stay null and their metric is unavailable; nothing is faked to a
/// passing value.
class MeasurementCaptureEvidence extends MeasurementEvidence {
  final int? sampleRate;
  final int? channelCount;
  final int? fftSize;
  final String? windowType;
  final String? averagingMethod;
  final List<String> repeatSpectrumRefs;
  final String? splitHalfARef;
  final String? splitHalfBRef;
  final double? signalPower;
  final double? noisePower;
  final int? clippedSamples;
  final int? totalSamples;
  final String? microphoneProfileRef;
  final String? calibrationRef;
  final String? captureConfigurationRef;

  // domain and source are fixed for a capture, so they are passed explicitly to
  // super rather than as super-parameters.
  // ignore: use_super_parameters
  MeasurementCaptureEvidence({
    int schemaVersion = kMeasurementEvidenceSchemaVersion,
    required String evidenceId,
    required String projectId,
    required String measurementRef,
    required MeasurementProvenance provenance,
    required Set<EvidenceMetric> availableMetrics,
    required Set<EvidenceMetric> unavailableMetrics,
    this.sampleRate,
    this.channelCount,
    this.fftSize,
    this.windowType,
    this.averagingMethod,
    this.repeatSpectrumRefs = const [],
    this.splitHalfARef,
    this.splitHalfBRef,
    this.signalPower,
    this.noisePower,
    this.clippedSamples,
    this.totalSamples,
    this.microphoneProfileRef,
    this.calibrationRef,
    this.captureConfigurationRef,
  }) : super(
          schemaVersion: schemaVersion,
          evidenceId: evidenceId,
          projectId: projectId,
          measurementRef: measurementRef,
          domain: MeasurementDomain.acousticResponse,
          source: MeasurementSource.liveMicrophone,
          provenance: provenance,
          availableMetrics: availableMetrics,
          unavailableMetrics: unavailableMetrics,
        ) {
    _validate();
  }

  @override
  String get kind => 'capture';

  bool get _hasSplitHalf => splitHalfARef != null && splitHalfBRef != null;

  void _validate() {
    MeasurementEvidence.checkCommon(
      schemaVersion: schemaVersion,
      evidenceId: evidenceId,
      projectId: projectId,
      measurementRef: measurementRef,
      available: availableMetrics,
      unavailable: unavailableMetrics,
    );
    for (final v in [signalPower, noisePower]) {
      if (v != null && !v.isFinite) {
        throw MeasurementEvidenceException('power values must be finite.');
      }
    }
    if (clippedSamples != null && clippedSamples! < 0) {
      throw MeasurementEvidenceException('clippedSamples must be >= 0.');
    }
    if (totalSamples != null && totalSamples! < 0) {
      throw MeasurementEvidenceException('totalSamples must be >= 0.');
    }
    if (clippedSamples != null &&
        totalSamples != null &&
        clippedSamples! > totalSamples!) {
      throw MeasurementEvidenceException(
          'clippedSamples (${clippedSamples!}) exceeds totalSamples '
          '(${totalSamples!}).');
    }
    // Repeatability needs split-half A/B or >=2 repeat spectra.
    if (availableMetrics.contains(EvidenceMetric.repeatability) &&
        !(_hasSplitHalf || repeatSpectrumRefs.length >= 2)) {
      throw MeasurementEvidenceException(
          'repeatability available requires split-half A/B refs or >=2 '
          'repeat spectra.');
    }
    // SNR needs both powers.
    if (availableMetrics.contains(EvidenceMetric.snr) &&
        !(signalPower != null && noisePower != null)) {
      throw MeasurementEvidenceException(
          'SNR available requires both signalPower and noisePower.');
    }
    // Clipping needs both counts.
    if (availableMetrics.contains(EvidenceMetric.clipping) &&
        !(clippedSamples != null && totalSamples != null)) {
      throw MeasurementEvidenceException(
          'clipping available requires both clipped and total sample counts.');
    }
    // Calibration availability requires a calibration ref.
    if (availableMetrics.contains(EvidenceMetric.calibration) &&
        calibrationRef == null) {
      throw MeasurementEvidenceException(
          'calibration available requires a calibrationRef.');
    }
  }

  static const _keys = {
    'kind',
    'schemaVersion',
    'evidenceId',
    'projectId',
    'measurementRef',
    'domain',
    'source',
    'provenance',
    'availableMetrics',
    'unavailableMetrics',
    'sampleRate',
    'channelCount',
    'fftSize',
    'windowType',
    'averagingMethod',
    'repeatSpectrumRefs',
    'splitHalfARef',
    'splitHalfBRef',
    'signalPower',
    'noisePower',
    'clippedSamples',
    'totalSamples',
    'microphoneProfileRef',
    'calibrationRef',
    'captureConfigurationRef',
  };

  Map<String, dynamic> toJson() => {
        ...baseJson(),
        if (sampleRate != null) 'sampleRate': sampleRate,
        if (channelCount != null) 'channelCount': channelCount,
        if (fftSize != null) 'fftSize': fftSize,
        if (windowType != null) 'windowType': windowType,
        if (averagingMethod != null) 'averagingMethod': averagingMethod,
        'repeatSpectrumRefs': repeatSpectrumRefs,
        if (splitHalfARef != null) 'splitHalfARef': splitHalfARef,
        if (splitHalfBRef != null) 'splitHalfBRef': splitHalfBRef,
        if (signalPower != null) 'signalPower': signalPower,
        if (noisePower != null) 'noisePower': noisePower,
        if (clippedSamples != null) 'clippedSamples': clippedSamples,
        if (totalSamples != null) 'totalSamples': totalSamples,
        if (microphoneProfileRef != null)
          'microphoneProfileRef': microphoneProfileRef,
        if (calibrationRef != null) 'calibrationRef': calibrationRef,
        if (captureConfigurationRef != null)
          'captureConfigurationRef': captureConfigurationRef,
      };

  factory MeasurementCaptureEvidence.fromJson(Map<String, dynamic> json) {
    const ctx = 'MeasurementCaptureEvidence';
    _EvidenceParse.ensureKeys(json, _keys, ctx);
    // domain/source are fixed for a capture; validate if present.
    final domain = MeasurementDomain.parse(json['domain'], ctx);
    final source = MeasurementSource.parse(json['source'], ctx);
    if (domain != MeasurementDomain.acousticResponse ||
        source != MeasurementSource.liveMicrophone) {
      throw MeasurementEvidenceException(
          'capture evidence must be acousticResponse / liveMicrophone.');
    }
    return MeasurementCaptureEvidence(
      schemaVersion: _EvidenceParse.requireSchemaVersion(json, ctx),
      evidenceId: _EvidenceParse.requireString(json, 'evidenceId', ctx),
      projectId: _EvidenceParse.requireString(json, 'projectId', ctx),
      measurementRef: _EvidenceParse.requireString(json, 'measurementRef', ctx),
      provenance: MeasurementProvenance.fromJson(
          _EvidenceParse.object(json['provenance'], ctx)),
      availableMetrics: _EvidenceParse.metricSet(json, 'availableMetrics', ctx),
      unavailableMetrics:
          _EvidenceParse.metricSet(json, 'unavailableMetrics', ctx),
      sampleRate: _EvidenceParse.optionalInt(json, 'sampleRate', ctx),
      channelCount: _EvidenceParse.optionalInt(json, 'channelCount', ctx),
      fftSize: _EvidenceParse.optionalInt(json, 'fftSize', ctx),
      windowType: _EvidenceParse.optionalString(json, 'windowType', ctx),
      averagingMethod:
          _EvidenceParse.optionalString(json, 'averagingMethod', ctx),
      repeatSpectrumRefs:
          _EvidenceParse.stringList(json, 'repeatSpectrumRefs', ctx),
      splitHalfARef: _EvidenceParse.optionalString(json, 'splitHalfARef', ctx),
      splitHalfBRef: _EvidenceParse.optionalString(json, 'splitHalfBRef', ctx),
      signalPower: _EvidenceParse.optionalDouble(json, 'signalPower', ctx),
      noisePower: _EvidenceParse.optionalDouble(json, 'noisePower', ctx),
      clippedSamples: _EvidenceParse.optionalInt(json, 'clippedSamples', ctx),
      totalSamples: _EvidenceParse.optionalInt(json, 'totalSamples', ctx),
      microphoneProfileRef:
          _EvidenceParse.optionalString(json, 'microphoneProfileRef', ctx),
      calibrationRef:
          _EvidenceParse.optionalString(json, 'calibrationRef', ctx),
      captureConfigurationRef:
          _EvidenceParse.optionalString(json, 'captureConfigurationRef', ctx),
    );
  }
}

/// Strict, fail-closed JSON helpers for the evidence model.
abstract final class _EvidenceParse {
  /// Keys that must never appear — raw spectrum/PCM would defeat the "reference
  /// only" contract. The allowlist already rejects unknown keys; this gives a
  /// pointed message for the obvious mistakes.
  static const Set<String> _forbidden = {
    'spectrum',
    'spectra',
    'spectradb',
    'pcm',
    'samples',
    'frequencies',
    'magnitudes',
    'magnitudedb',
    'phasedegrees',
    'rawdata',
  };

  static void ensureKeys(
      Map<String, dynamic> json, Set<String> allowed, String ctx) {
    for (final key in json.keys) {
      if (_forbidden.contains(key.toLowerCase())) {
        throw MeasurementEvidenceException(
            '$ctx: forbidden raw-data key "$key" — evidence references data, '
            'it never embeds it.');
      }
      if (!allowed.contains(key)) {
        throw MeasurementEvidenceException('$ctx: unknown key "$key".');
      }
    }
  }

  static Map<String, dynamic> object(Object? raw, String ctx) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw MeasurementEvidenceException('$ctx: expected an object.');
  }

  static int requireSchemaVersion(Map<String, dynamic> json, String ctx) {
    final v = json['schemaVersion'];
    if (v is! int) {
      throw MeasurementEvidenceException('$ctx: schemaVersion must be an int.');
    }
    if (v != kMeasurementEvidenceSchemaVersion) {
      throw MeasurementEvidenceException('$ctx: unsupported schemaVersion $v.');
    }
    return v;
  }

  static String requireString(
      Map<String, dynamic> json, String key, String ctx) {
    final v = json[key];
    if (v is! String || v.isEmpty) {
      throw MeasurementEvidenceException(
          '$ctx: "$key" must be a non-empty string.');
    }
    return v;
  }

  static String? optionalString(
      Map<String, dynamic> json, String key, String ctx) {
    if (!json.containsKey(key)) return null;
    final v = json[key];
    if (v is! String) {
      throw MeasurementEvidenceException('$ctx: "$key" must be a string.');
    }
    return v;
  }

  static bool requireBool(Map<String, dynamic> json, String key, String ctx) {
    final v = json[key];
    if (v is! bool) {
      throw MeasurementEvidenceException('$ctx: "$key" must be a bool.');
    }
    return v;
  }

  static int? optionalInt(Map<String, dynamic> json, String key, String ctx) {
    if (!json.containsKey(key)) return null;
    final v = json[key];
    if (v is! int) {
      throw MeasurementEvidenceException('$ctx: "$key" must be an int.');
    }
    return v;
  }

  static double? optionalDouble(
      Map<String, dynamic> json, String key, String ctx) {
    if (!json.containsKey(key)) return null;
    final v = json[key];
    final d = (v is int) ? v.toDouble() : v;
    if (d is! double || !d.isFinite) {
      throw MeasurementEvidenceException(
          '$ctx: "$key" must be a finite number.');
    }
    return d;
  }

  static List<String> stringList(
      Map<String, dynamic> json, String key, String ctx) {
    if (!json.containsKey(key)) return const [];
    final v = json[key];
    if (v is! List) {
      throw MeasurementEvidenceException('$ctx: "$key" must be a list.');
    }
    return [
      for (var i = 0; i < v.length; i++)
        if (v[i] is String)
          v[i] as String
        else
          throw MeasurementEvidenceException(
              '$ctx: "$key"[$i] must be a string.')
    ];
  }

  static Set<EvidenceMetric> metricSet(
      Map<String, dynamic> json, String key, String ctx) {
    final v = json[key];
    if (v is! List) {
      throw MeasurementEvidenceException('$ctx: "$key" must be a list.');
    }
    final out = <EvidenceMetric>{};
    for (final e in v) {
      final m = EvidenceMetric.parse(e, '$ctx.$key');
      if (!out.add(m)) {
        throw MeasurementEvidenceException(
            '$ctx: "$key" has duplicate metric "${m.name}".');
      }
    }
    return out;
  }

  static T enumValue<T>(List<T> values, String Function(T) nameOf, Object? raw,
      String field, String ctx) {
    if (raw is! String) {
      throw MeasurementEvidenceException('$ctx: $field must be a string.');
    }
    for (final v in values) {
      if (nameOf(v) == raw) return v;
    }
    throw MeasurementEvidenceException(
        '$ctx: $field has unknown value "$raw".');
  }
}
