// ── TUNAI PRO Phase D — Tuning Data Models ───────────────────────────────────
// PEQ band state, crossover filter state, per-channel tuning.
// No DSP addresses. No SafeLoad. No EEPROM. No register writes.

// ── Enums ─────────────────────────────────────────────────────────────────────

enum PeqBandType {
  peak,
  lowShelf,
  highShelf,
  notch,
  highPass,
  lowPass;

  String get label => switch (this) {
    PeqBandType.peak      => 'Peak',
    PeqBandType.lowShelf  => 'Low Shelf',
    PeqBandType.highShelf => 'High Shelf',
    PeqBandType.notch     => 'Notch',
    PeqBandType.highPass  => 'HPF',
    PeqBandType.lowPass   => 'LPF',
  };

  String get short => switch (this) {
    PeqBandType.peak      => 'PK',
    PeqBandType.lowShelf  => 'LS',
    PeqBandType.highShelf => 'HS',
    PeqBandType.notch     => 'NT',
    PeqBandType.highPass  => 'HP',
    PeqBandType.lowPass   => 'LP',
  };

  bool get hasGain => this == PeqBandType.peak ||
      this == PeqBandType.lowShelf || this == PeqBandType.highShelf;
  bool get hasQ    => this == PeqBandType.peak || this == PeqBandType.notch ||
      this == PeqBandType.highPass || this == PeqBandType.lowPass;

  String toJson() => name;
  static PeqBandType fromJson(String s) =>
      PeqBandType.values.firstWhere((e) => e.name == s, orElse: () => PeqBandType.peak);
}

enum PeqBandStatus {
  active,
  bypassed,
  suggested,
  locked;

  String get label => switch (this) {
    PeqBandStatus.active    => 'Active',
    PeqBandStatus.bypassed  => 'Bypassed',
    PeqBandStatus.suggested => 'Suggested',
    PeqBandStatus.locked    => 'Locked',
  };

  String toJson() => name;
  static PeqBandStatus fromJson(String s) =>
      PeqBandStatus.values.firstWhere((e) => e.name == s, orElse: () => PeqBandStatus.active);
}

enum CrossoverFilterType {
  linkwitzRiley,
  butterworth,
  bessel,
  linearPhasePlaceholder;

  String get label => switch (this) {
    CrossoverFilterType.linkwitzRiley          => 'LR',
    CrossoverFilterType.butterworth            => 'BW',
    CrossoverFilterType.bessel                 => 'Bessel',
    CrossoverFilterType.linearPhasePlaceholder => 'Lin Phase †',
  };

  String get fullLabel => switch (this) {
    CrossoverFilterType.linkwitzRiley          => 'Linkwitz-Riley',
    CrossoverFilterType.butterworth            => 'Butterworth',
    CrossoverFilterType.bessel                 => 'Bessel',
    CrossoverFilterType.linearPhasePlaceholder => 'Linear Phase (placeholder)',
  };

  String toJson() => name;
  static CrossoverFilterType fromJson(String s) =>
      CrossoverFilterType.values.firstWhere((e) => e.name == s,
          orElse: () => CrossoverFilterType.linkwitzRiley);
}

enum CrossoverSlope {
  db12,
  db24,
  db36,
  db48;

  String get label => switch (this) {
    CrossoverSlope.db12 => '12 dB/oct',
    CrossoverSlope.db24 => '24 dB/oct',
    CrossoverSlope.db36 => '36 dB/oct',
    CrossoverSlope.db48 => '48 dB/oct',
  };

  String get short => switch (this) {
    CrossoverSlope.db12 => '12',
    CrossoverSlope.db24 => '24',
    CrossoverSlope.db36 => '36',
    CrossoverSlope.db48 => '48',
  };

  String toJson() => name;
  static CrossoverSlope fromJson(String s) =>
      CrossoverSlope.values.firstWhere((e) => e.name == s, orElse: () => CrossoverSlope.db24);
}

enum FilterSide {
  highPass,
  lowPass;

  String get label => this == FilterSide.highPass ? 'HPF' : 'LPF';
  String toJson() => name;
  static FilterSide fromJson(String s) =>
      FilterSide.values.firstWhere((e) => e.name == s, orElse: () => FilterSide.highPass);
}

// ── Models ────────────────────────────────────────────────────────────────────

class PeqBand {
  final String id;
  final bool enabled;
  final PeqBandStatus status;
  final PeqBandType type;
  final double frequencyHz;
  final double gainDb;
  final double q;
  final String? note;

  const PeqBand({
    required this.id,
    this.enabled = true,
    this.status = PeqBandStatus.active,
    this.type = PeqBandType.peak,
    this.frequencyHz = 1000.0,
    this.gainDb = 0.0,
    this.q = 1.0,
    this.note,
  });

  String get freqLabel {
    if (frequencyHz >= 1000) {
      return '${(frequencyHz / 1000).toStringAsFixed(frequencyHz % 1000 == 0 ? 0 : 1)} kHz';
    }
    return '${frequencyHz.toStringAsFixed(0)} Hz';
  }

  String get gainLabel => gainDb >= 0 ? '+${gainDb.toStringAsFixed(1)} dB' : '${gainDb.toStringAsFixed(1)} dB';
  String get qLabel => 'Q ${q.toStringAsFixed(2)}';

  PeqBand copyWith({
    bool? enabled,
    PeqBandStatus? status,
    PeqBandType? type,
    double? frequencyHz,
    double? gainDb,
    double? q,
    String? note,
  }) => PeqBand(
    id: id,
    enabled: enabled ?? this.enabled,
    status: status ?? this.status,
    type: type ?? this.type,
    frequencyHz: frequencyHz ?? this.frequencyHz,
    gainDb: gainDb ?? this.gainDb,
    q: q ?? this.q,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'enabled': enabled,
    'status': status.toJson(),
    'type': type.toJson(),
    'frequencyHz': frequencyHz,
    'gainDb': gainDb,
    'q': q,
    if (note != null) 'note': note,
  };

  factory PeqBand.fromJson(Map<String, dynamic> j) => PeqBand(
    id: j['id'] as String,
    enabled: j['enabled'] as bool? ?? true,
    status: PeqBandStatus.fromJson(j['status'] as String? ?? 'active'),
    type: PeqBandType.fromJson(j['type'] as String? ?? 'peak'),
    frequencyHz: (j['frequencyHz'] as num?)?.toDouble() ?? 1000.0,
    gainDb: (j['gainDb'] as num?)?.toDouble() ?? 0.0,
    q: (j['q'] as num?)?.toDouble() ?? 1.0,
    note: j['note'] as String?,
  );

  factory PeqBand.create({
    required PeqBandType type,
    double frequencyHz = 1000.0,
    double gainDb = 0.0,
    double q = 1.0,
  }) => PeqBand(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    type: type,
    frequencyHz: frequencyHz,
    gainDb: gainDb,
    q: q,
  );
}

class PeqChannelState {
  final String channelId;
  final bool bypassed;
  final List<PeqBand> bands;

  const PeqChannelState({
    required this.channelId,
    this.bypassed = false,
    this.bands = const [],
  });

  int get activeBandCount => bands.where((b) => b.enabled && b.status != PeqBandStatus.bypassed).length;
  bool get isEmpty => bands.isEmpty;

  PeqChannelState copyWith({
    bool? bypassed,
    List<PeqBand>? bands,
  }) => PeqChannelState(
    channelId: channelId,
    bypassed: bypassed ?? this.bypassed,
    bands: bands ?? this.bands,
  );

  Map<String, dynamic> toJson() => {
    'channelId': channelId,
    'bypassed': bypassed,
    'bands': bands.map((b) => b.toJson()).toList(),
  };

  factory PeqChannelState.fromJson(Map<String, dynamic> j) => PeqChannelState(
    channelId: j['channelId'] as String,
    bypassed: j['bypassed'] as bool? ?? false,
    bands: (j['bands'] as List? ?? [])
        .map((e) => PeqBand.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  factory PeqChannelState.empty(String channelId) =>
      PeqChannelState(channelId: channelId);
}

class CrossoverFilter {
  final bool enabled;
  final FilterSide side;
  final CrossoverFilterType type;
  final CrossoverSlope slope;
  final double frequencyHz;
  final String? note;

  const CrossoverFilter({
    this.enabled = true,
    required this.side,
    this.type = CrossoverFilterType.linkwitzRiley,
    this.slope = CrossoverSlope.db24,
    this.frequencyHz = 2000.0,
    this.note,
  });

  String get freqLabel {
    if (frequencyHz >= 1000) {
      return '${(frequencyHz / 1000).toStringAsFixed(1)} kHz';
    }
    return '${frequencyHz.toStringAsFixed(0)} Hz';
  }

  String get summaryLabel => '${side.label} ${type.label}-${slope.short} @ $freqLabel';

  CrossoverFilter copyWith({
    bool? enabled,
    CrossoverFilterType? type,
    CrossoverSlope? slope,
    double? frequencyHz,
    String? note,
  }) => CrossoverFilter(
    enabled: enabled ?? this.enabled,
    side: side,
    type: type ?? this.type,
    slope: slope ?? this.slope,
    frequencyHz: frequencyHz ?? this.frequencyHz,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'side': side.toJson(),
    'type': type.toJson(),
    'slope': slope.toJson(),
    'frequencyHz': frequencyHz,
    if (note != null) 'note': note,
  };

  factory CrossoverFilter.fromJson(Map<String, dynamic> j) => CrossoverFilter(
    enabled: j['enabled'] as bool? ?? true,
    side: FilterSide.fromJson(j['side'] as String? ?? 'highPass'),
    type: CrossoverFilterType.fromJson(j['type'] as String? ?? 'linkwitzRiley'),
    slope: CrossoverSlope.fromJson(j['slope'] as String? ?? 'db24'),
    frequencyHz: (j['frequencyHz'] as num?)?.toDouble() ?? 2000.0,
    note: j['note'] as String?,
  );
}

class CrossoverChannelState {
  final String channelId;
  final bool bypassed;
  final bool polarityInverted;
  final CrossoverFilter? highPass;
  final CrossoverFilter? lowPass;

  const CrossoverChannelState({
    required this.channelId,
    this.bypassed = false,
    this.polarityInverted = false,
    this.highPass,
    this.lowPass,
  });

  bool get hasHighPass => highPass != null && highPass!.enabled;
  bool get hasLowPass => lowPass != null && lowPass!.enabled;
  bool get isConfigured => hasHighPass || hasLowPass;

  CrossoverChannelState copyWith({
    bool? bypassed,
    bool? polarityInverted,
    CrossoverFilter? highPass,
    bool clearHighPass = false,
    CrossoverFilter? lowPass,
    bool clearLowPass = false,
  }) => CrossoverChannelState(
    channelId: channelId,
    bypassed: bypassed ?? this.bypassed,
    polarityInverted: polarityInverted ?? this.polarityInverted,
    highPass: clearHighPass ? null : (highPass ?? this.highPass),
    lowPass: clearLowPass ? null : (lowPass ?? this.lowPass),
  );

  Map<String, dynamic> toJson() => {
    'channelId': channelId,
    'bypassed': bypassed,
    'polarityInverted': polarityInverted,
    if (highPass != null) 'highPass': highPass!.toJson(),
    if (lowPass != null) 'lowPass': lowPass!.toJson(),
  };

  factory CrossoverChannelState.fromJson(Map<String, dynamic> j) => CrossoverChannelState(
    channelId: j['channelId'] as String,
    bypassed: j['bypassed'] as bool? ?? false,
    polarityInverted: j['polarityInverted'] as bool? ?? false,
    highPass: j['highPass'] != null
        ? CrossoverFilter.fromJson(Map<String, dynamic>.from(j['highPass'] as Map))
        : null,
    lowPass: j['lowPass'] != null
        ? CrossoverFilter.fromJson(Map<String, dynamic>.from(j['lowPass'] as Map))
        : null,
  );

  factory CrossoverChannelState.empty(String channelId) =>
      CrossoverChannelState(channelId: channelId);
}

class TuningProjectState {
  final List<PeqChannelState> peqChannels;
  final List<CrossoverChannelState> crossoverChannels;
  final DateTime updatedAt;
  final int tuningRevision;
  final bool hasManualChanges;
  final String? notes;

  TuningProjectState({
    this.peqChannels = const [],
    this.crossoverChannels = const [],
    DateTime? updatedAt,
    this.tuningRevision = 0,
    this.hasManualChanges = false,
    this.notes,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ── Readiness getters ─────────────────────────────────────────────────────

  int get totalPeqBands => peqChannels.fold(0, (n, ch) => n + ch.bands.length);
  int get activePeqBands => peqChannels.fold(0, (n, ch) => n + ch.activeBandCount);
  int get configuredXoChannels => crossoverChannels.where((c) => c.isConfigured).length;
  int get hpfCount => crossoverChannels.where((c) => c.hasHighPass).length;
  int get lpfCount => crossoverChannels.where((c) => c.hasLowPass).length;
  int get polarityInvertedCount => crossoverChannels.where((c) => c.polarityInverted).length;

  String get readinessLabel {
    final hasPeq = totalPeqBands > 0;
    final hasXo = configuredXoChannels > 0;
    if (!hasPeq && !hasXo) return 'No tuning configured';
    if (hasPeq && !hasXo) return 'PEQ started';
    if (!hasPeq && hasXo) return 'XO structure started';
    return 'Ready for optimization draft';
  }

  TuningProjectState copyWith({
    List<PeqChannelState>? peqChannels,
    List<CrossoverChannelState>? crossoverChannels,
    DateTime? updatedAt,
    int? tuningRevision,
    bool? hasManualChanges,
    String? notes,
  }) => TuningProjectState(
    peqChannels: peqChannels ?? this.peqChannels,
    crossoverChannels: crossoverChannels ?? this.crossoverChannels,
    updatedAt: updatedAt ?? DateTime.now(),
    tuningRevision: tuningRevision ?? this.tuningRevision,
    hasManualChanges: hasManualChanges ?? this.hasManualChanges,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'peqChannels': peqChannels.map((c) => c.toJson()).toList(),
    'crossoverChannels': crossoverChannels.map((c) => c.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'tuningRevision': tuningRevision,
    'hasManualChanges': hasManualChanges,
    if (notes != null) 'notes': notes,
  };

  factory TuningProjectState.fromJson(Map<String, dynamic> j) => TuningProjectState(
    peqChannels: (j['peqChannels'] as List? ?? [])
        .map((e) => PeqChannelState.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    crossoverChannels: (j['crossoverChannels'] as List? ?? [])
        .map((e) => CrossoverChannelState.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    tuningRevision: j['tuningRevision'] as int? ?? 0,
    hasManualChanges: j['hasManualChanges'] as bool? ?? false,
    notes: j['notes'] as String?,
  );

  static TuningProjectState createDefault() => TuningProjectState();
}
