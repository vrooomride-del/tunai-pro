// ── TUNAI PRO Phase N — Acoustic Simulation Data ─────────────────────────────
// Draft response data structures for workstation-style frequency response
// preview. Not final acoustic simulation. Not hardware write.
// AI suggests. Expert verifies. AOS protects. DSP executes.

// ── Enums ─────────────────────────────────────────────────────────────────────

enum SimulationCurveType {
  target,
  summed,
  summedMagnitudeOnly,
  summedPhaseAware,
  phaseTrace,
  delayTrace,
  driver,
  peqTransfer,
  crossoverTransfer,
  gainAdjusted,
  phasePlaceholder,
  reference,
  warning;

  String get label => switch (this) {
    SimulationCurveType.target              => 'Target',
    SimulationCurveType.summed              => 'Summed',
    SimulationCurveType.summedMagnitudeOnly => 'Summed (Mag-only)',
    SimulationCurveType.summedPhaseAware    => 'Summed (Phase-aware)',
    SimulationCurveType.phaseTrace          => 'Phase Trace',
    SimulationCurveType.delayTrace          => 'Delay Trace',
    SimulationCurveType.driver              => 'Driver',
    SimulationCurveType.peqTransfer         => 'PEQ Transfer',
    SimulationCurveType.crossoverTransfer   => 'XO Transfer',
    SimulationCurveType.gainAdjusted        => 'Gain Adjusted',
    SimulationCurveType.phasePlaceholder    => 'Phase (Placeholder)',
    SimulationCurveType.reference           => 'Reference',
    SimulationCurveType.warning             => 'Warning',
  };

  String toJson() => name;
  static SimulationCurveType fromJson(String s) =>
      SimulationCurveType.values.firstWhere((e) => e.name == s,
          orElse: () => SimulationCurveType.reference);
}

enum SimulationCurveStatus {
  empty,
  placeholder,
  estimated,
  imported,
  calculatedDraft,
  phaseAwareDraft,
  missingPhaseFallback,
  requiresMeasurement,
  requiresVerification;

  String get label => switch (this) {
    SimulationCurveStatus.empty                => 'Empty',
    SimulationCurveStatus.placeholder          => 'Placeholder',
    SimulationCurveStatus.estimated            => 'Estimated',
    SimulationCurveStatus.imported             => 'Imported',
    SimulationCurveStatus.calculatedDraft      => 'Calculated Draft',
    SimulationCurveStatus.phaseAwareDraft      => 'Phase-aware Draft',
    SimulationCurveStatus.missingPhaseFallback => 'Mag-only Fallback',
    SimulationCurveStatus.requiresMeasurement  => 'Requires Measurement',
    SimulationCurveStatus.requiresVerification => 'Requires Verification',
  };

  String toJson() => name;
  static SimulationCurveStatus fromJson(String s) =>
      SimulationCurveStatus.values.firstWhere((e) => e.name == s,
          orElse: () => SimulationCurveStatus.placeholder);
}

enum SimulationScale {
  magnitudeDb,
  phaseDeg,
  impedanceOhm;

  String get label => switch (this) {
    SimulationScale.magnitudeDb  => 'Magnitude (dB)',
    SimulationScale.phaseDeg     => 'Phase (°)',
    SimulationScale.impedanceOhm => 'Impedance (Ω)',
  };

  String toJson() => name;
  static SimulationScale fromJson(String s) =>
      SimulationScale.values.firstWhere((e) => e.name == s,
          orElse: () => SimulationScale.magnitudeDb);
}

enum SimulationReadiness {
  noData,
  placeholderOnly,
  estimated,
  calculatedDraft,
  requiresVerification;

  String get label => switch (this) {
    SimulationReadiness.noData               => 'No Data',
    SimulationReadiness.placeholderOnly      => 'Placeholder Only',
    SimulationReadiness.estimated            => 'Estimated',
    SimulationReadiness.calculatedDraft      => 'Calculated Draft',
    SimulationReadiness.requiresVerification => 'Requires Verification',
  };

  String toJson() => name;
  static SimulationReadiness fromJson(String s) =>
      SimulationReadiness.values.firstWhere((e) => e.name == s,
          orElse: () => SimulationReadiness.noData);
}

// ── Models ────────────────────────────────────────────────────────────────────

class SimulationPoint {
  final double frequencyHz;
  final double value;
  final double? phaseDeg;

  const SimulationPoint({
    required this.frequencyHz,
    required this.value,
    this.phaseDeg,
  });

  Map<String, dynamic> toJson() => {
    'f': frequencyHz,
    'v': value,
    if (phaseDeg != null) 'p': phaseDeg,
  };

  factory SimulationPoint.fromJson(Map<String, dynamic> j) => SimulationPoint(
    frequencyHz: (j['f'] as num?)?.toDouble() ?? 0.0,
    value: (j['v'] as num?)?.toDouble() ?? 0.0,
    phaseDeg: (j['p'] as num?)?.toDouble(),
  );
}

class SimulationCurve {
  final String id;
  final String label;
  final SimulationCurveType type;
  final SimulationCurveStatus status;
  final SimulationScale scale;
  final String? channelId;
  final List<SimulationPoint> points;
  final double? minFrequencyHz;
  final double? maxFrequencyHz;
  final String? warning;
  final String? notes;

  const SimulationCurve({
    required this.id,
    required this.label,
    required this.type,
    required this.status,
    this.scale = SimulationScale.magnitudeDb,
    this.channelId,
    this.points = const [],
    this.minFrequencyHz,
    this.maxFrequencyHz,
    this.warning,
    this.notes,
  });

  int get pointCount => points.length;
  bool get hasPoints => points.isNotEmpty;
  bool get isPlaceholder =>
      status == SimulationCurveStatus.placeholder ||
      status == SimulationCurveStatus.empty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.toJson(),
    'status': status.toJson(),
    'scale': scale.toJson(),
    if (channelId != null) 'channelId': channelId,
    'points': points.map((p) => p.toJson()).toList(),
    if (minFrequencyHz != null) 'minFrequencyHz': minFrequencyHz,
    if (maxFrequencyHz != null) 'maxFrequencyHz': maxFrequencyHz,
    if (warning != null) 'warning': warning,
    if (notes != null) 'notes': notes,
  };

  factory SimulationCurve.fromJson(Map<String, dynamic> j) => SimulationCurve(
    id: j['id'] as String? ?? '',
    label: j['label'] as String? ?? '',
    type: SimulationCurveType.fromJson(j['type'] as String? ?? 'reference'),
    status: SimulationCurveStatus.fromJson(j['status'] as String? ?? 'placeholder'),
    scale: SimulationScale.fromJson(j['scale'] as String? ?? 'magnitudeDb'),
    channelId: j['channelId'] as String?,
    points: (j['points'] as List? ?? [])
        .map((e) => SimulationPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    minFrequencyHz: (j['minFrequencyHz'] as num?)?.toDouble(),
    maxFrequencyHz: (j['maxFrequencyHz'] as num?)?.toDouble(),
    warning: j['warning'] as String?,
    notes: j['notes'] as String?,
  );
}

class SimulationRunConfig {
  final double sampleRateHz;
  final double minFrequencyHz;
  final double maxFrequencyHz;
  final int pointsPerOctave;
  final bool includeTarget;
  final bool includeDrivers;
  final bool includeSummed;
  final bool includePhasePlaceholder;
  // Phase N additions
  final bool includePhaseAwareSummation;
  final bool includeMagnitudeOnlyComparison;
  final bool includeDriverPhaseCurves;
  final bool useAcousticOffsets;
  final String? notes;

  const SimulationRunConfig({
    this.sampleRateHz = 48000,
    this.minFrequencyHz = 20,
    this.maxFrequencyHz = 20000,
    this.pointsPerOctave = 12,
    this.includeTarget = true,
    this.includeDrivers = true,
    this.includeSummed = true,
    this.includePhasePlaceholder = false,
    this.includePhaseAwareSummation = true,
    this.includeMagnitudeOnlyComparison = true,
    this.includeDriverPhaseCurves = false,
    this.useAcousticOffsets = false,
    this.notes,
  });

  SimulationRunConfig copyWith({
    double? sampleRateHz,
    double? minFrequencyHz,
    double? maxFrequencyHz,
    int? pointsPerOctave,
    bool? includeTarget,
    bool? includeDrivers,
    bool? includeSummed,
    bool? includePhasePlaceholder,
    bool? includePhaseAwareSummation,
    bool? includeMagnitudeOnlyComparison,
    bool? includeDriverPhaseCurves,
    bool? useAcousticOffsets,
    String? notes,
  }) => SimulationRunConfig(
    sampleRateHz: sampleRateHz ?? this.sampleRateHz,
    minFrequencyHz: minFrequencyHz ?? this.minFrequencyHz,
    maxFrequencyHz: maxFrequencyHz ?? this.maxFrequencyHz,
    pointsPerOctave: pointsPerOctave ?? this.pointsPerOctave,
    includeTarget: includeTarget ?? this.includeTarget,
    includeDrivers: includeDrivers ?? this.includeDrivers,
    includeSummed: includeSummed ?? this.includeSummed,
    includePhasePlaceholder:
        includePhasePlaceholder ?? this.includePhasePlaceholder,
    includePhaseAwareSummation:
        includePhaseAwareSummation ?? this.includePhaseAwareSummation,
    includeMagnitudeOnlyComparison:
        includeMagnitudeOnlyComparison ?? this.includeMagnitudeOnlyComparison,
    includeDriverPhaseCurves:
        includeDriverPhaseCurves ?? this.includeDriverPhaseCurves,
    useAcousticOffsets: useAcousticOffsets ?? this.useAcousticOffsets,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'sampleRateHz': sampleRateHz,
    'minFrequencyHz': minFrequencyHz,
    'maxFrequencyHz': maxFrequencyHz,
    'pointsPerOctave': pointsPerOctave,
    'includeTarget': includeTarget,
    'includeDrivers': includeDrivers,
    'includeSummed': includeSummed,
    'includePhasePlaceholder': includePhasePlaceholder,
    'includePhaseAwareSummation': includePhaseAwareSummation,
    'includeMagnitudeOnlyComparison': includeMagnitudeOnlyComparison,
    'includeDriverPhaseCurves': includeDriverPhaseCurves,
    'useAcousticOffsets': useAcousticOffsets,
    if (notes != null) 'notes': notes,
  };

  factory SimulationRunConfig.fromJson(Map<String, dynamic> j) =>
      SimulationRunConfig(
        sampleRateHz: (j['sampleRateHz'] as num?)?.toDouble() ?? 48000,
        minFrequencyHz: (j['minFrequencyHz'] as num?)?.toDouble() ?? 20,
        maxFrequencyHz: (j['maxFrequencyHz'] as num?)?.toDouble() ?? 20000,
        pointsPerOctave: j['pointsPerOctave'] as int? ?? 12,
        includeTarget: j['includeTarget'] as bool? ?? true,
        includeDrivers: j['includeDrivers'] as bool? ?? true,
        includeSummed: j['includeSummed'] as bool? ?? true,
        includePhasePlaceholder:
            j['includePhasePlaceholder'] as bool? ?? false,
        includePhaseAwareSummation:
            j['includePhaseAwareSummation'] as bool? ?? true,
        includeMagnitudeOnlyComparison:
            j['includeMagnitudeOnlyComparison'] as bool? ?? true,
        includeDriverPhaseCurves:
            j['includeDriverPhaseCurves'] as bool? ?? false,
        useAcousticOffsets: j['useAcousticOffsets'] as bool? ?? false,
        notes: j['notes'] as String?,
      );
}

class SimulationRunResult {
  final String id;
  final DateTime createdAt;
  final SimulationRunConfig config;
  final List<SimulationCurve> curves;
  final List<String> warnings;
  final String summary;
  final SimulationReadiness readiness;

  SimulationRunResult({
    required this.id,
    DateTime? createdAt,
    required this.config,
    required this.curves,
    required this.warnings,
    required this.summary,
    required this.readiness,
  }) : createdAt = createdAt ?? DateTime.now();

  int get curveCount => curves.length;
  bool get hasTargetCurve =>
      curves.any((c) => c.type == SimulationCurveType.target);
  bool get hasSummedCurve =>
      curves.any((c) => c.type == SimulationCurveType.summed ||
          c.type == SimulationCurveType.summedPhaseAware ||
          c.type == SimulationCurveType.summedMagnitudeOnly);
  bool get hasDriverCurves =>
      curves.any((c) => c.type == SimulationCurveType.driver);
  bool get hasPhaseAwareCurve =>
      curves.any((c) => c.type == SimulationCurveType.summedPhaseAware);
  bool get hasMagnitudeOnlyCurve =>
      curves.any((c) => c.type == SimulationCurveType.summedMagnitudeOnly ||
          (c.type == SimulationCurveType.summed &&
              c.status == SimulationCurveStatus.missingPhaseFallback));
  int get importedFrdCurveCount =>
      curves.where((c) => c.type == SimulationCurveType.driver &&
          c.status == SimulationCurveStatus.imported).length;
  int get placeholderDriverCurveCount =>
      curves.where((c) => c.type == SimulationCurveType.driver &&
          c.status != SimulationCurveStatus.imported).length;
  int get warningCount => warnings.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'config': config.toJson(),
    'curves': curves.map((c) => c.toJson()).toList(),
    'warnings': warnings,
    'summary': summary,
    'readiness': readiness.toJson(),
  };

  factory SimulationRunResult.fromJson(Map<String, dynamic> j) =>
      SimulationRunResult(
        id: j['id'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        config: j['config'] != null
            ? SimulationRunConfig.fromJson(
                Map<String, dynamic>.from(j['config'] as Map))
            : const SimulationRunConfig(),
        curves: (j['curves'] as List? ?? [])
            .map((e) => SimulationCurve.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        warnings: List<String>.from(j['warnings'] as List? ?? []),
        summary: j['summary'] as String? ?? '',
        readiness: SimulationReadiness.fromJson(
            j['readiness'] as String? ?? 'noData'),
      );
}

class SimulationProjectState {
  final List<SimulationRunResult> runs;
  final String? activeRunId;
  final DateTime updatedAt;
  final int revision;

  SimulationProjectState({
    this.runs = const [],
    this.activeRunId,
    DateTime? updatedAt,
    this.revision = 0,
  }) : updatedAt = updatedAt ?? DateTime.now();

  SimulationRunResult? get activeRun {
    if (activeRunId == null) return runs.isNotEmpty ? runs.last : null;
    try {
      return runs.firstWhere((r) => r.id == activeRunId);
    } catch (_) {
      return runs.isNotEmpty ? runs.last : null;
    }
  }

  int get runCount => runs.length;
  int get activeCurveCount => activeRun?.curveCount ?? 0;
  int get warningCount => activeRun?.warningCount ?? 0;

  String get readinessLabel {
    final run = activeRun;
    if (run == null) return 'No simulation run';
    return run.readiness.label;
  }

  SimulationProjectState copyWith({
    List<SimulationRunResult>? runs,
    String? activeRunId,
    DateTime? updatedAt,
    int? revision,
  }) => SimulationProjectState(
    runs: runs ?? this.runs,
    activeRunId: activeRunId ?? this.activeRunId,
    updatedAt: updatedAt ?? DateTime.now(),
    revision: revision ?? this.revision,
  );

  Map<String, dynamic> toJson() => {
    'runs': runs.map((r) => r.toJson()).toList(),
    if (activeRunId != null) 'activeRunId': activeRunId,
    'updatedAt': updatedAt.toIso8601String(),
    'revision': revision,
  };

  factory SimulationProjectState.fromJson(Map<String, dynamic> j) =>
      SimulationProjectState(
        runs: (j['runs'] as List? ?? [])
            .map((e) => SimulationRunResult.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        activeRunId: j['activeRunId'] as String?,
        updatedAt:
            DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        revision: j['revision'] as int? ?? 0,
      );

  static SimulationProjectState createDefault() => SimulationProjectState();
}
