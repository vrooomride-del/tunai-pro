// ── TUNAI PRO Phase G — Optimizer Draft Data Models ───────────────────────────
// AI suggests. Expert verifies. AOS protects. DSP executes.
// No DSP write. No SafeLoad. No register addresses. Suggestions only.

// ── Enums ─────────────────────────────────────────────────────────────────────

enum OptimizerMode {
  conservative,
  balanced,
  aggressive,
  manualReview;

  String get label => switch (this) {
    OptimizerMode.conservative => 'Conservative',
    OptimizerMode.balanced     => 'Balanced',
    OptimizerMode.aggressive   => 'Aggressive',
    OptimizerMode.manualReview => 'Manual Review',
  };

  String get description => switch (this) {
    OptimizerMode.conservative => 'Minimal corrections. Low risk. Prefer flat adjustments.',
    OptimizerMode.balanced     => 'Moderate corrections. Balanced target fidelity.',
    OptimizerMode.aggressive   => 'Stronger corrections. Higher confidence required.',
    OptimizerMode.manualReview => 'Generate suggestions without applying any defaults.',
  };

  String toJson() => name;
  static OptimizerMode fromJson(String s) =>
      OptimizerMode.values.firstWhere((e) => e.name == s,
          orElse: () => OptimizerMode.balanced);
}

enum OptimizerScope {
  peq,
  crossover,
  gain,
  delay,
  phase,
  fullSystem;

  String get label => switch (this) {
    OptimizerScope.peq        => 'PEQ',
    OptimizerScope.crossover  => 'Crossover',
    OptimizerScope.gain       => 'Gain',
    OptimizerScope.delay      => 'Delay',
    OptimizerScope.phase      => 'Phase',
    OptimizerScope.fullSystem => 'Full System',
  };

  String toJson() => name;
  static OptimizerScope fromJson(String s) =>
      OptimizerScope.values.firstWhere((e) => e.name == s,
          orElse: () => OptimizerScope.fullSystem);
}

enum OptimizerSuggestionType {
  addPeqBand,
  adjustPeqBand,
  removePeqBand,
  addHighPass,
  adjustCrossover,
  adjustGain,
  adjustDelay,
  invertPolarity,
  warningOnly;

  String get label => switch (this) {
    OptimizerSuggestionType.addPeqBand      => 'Add PEQ Band',
    OptimizerSuggestionType.adjustPeqBand   => 'Adjust PEQ Band',
    OptimizerSuggestionType.removePeqBand   => 'Remove PEQ Band',
    OptimizerSuggestionType.addHighPass     => 'Add High-Pass',
    OptimizerSuggestionType.adjustCrossover => 'Adjust Crossover',
    OptimizerSuggestionType.adjustGain      => 'Adjust Gain',
    OptimizerSuggestionType.adjustDelay     => 'Adjust Delay',
    OptimizerSuggestionType.invertPolarity  => 'Invert Polarity',
    OptimizerSuggestionType.warningOnly     => 'Warning',
  };

  String toJson() => name;
  static OptimizerSuggestionType fromJson(String s) =>
      OptimizerSuggestionType.values.firstWhere((e) => e.name == s,
          orElse: () => OptimizerSuggestionType.warningOnly);
}

enum OptimizerSuggestionStatus {
  pending,
  accepted,
  rejected,
  locked;

  String get label => switch (this) {
    OptimizerSuggestionStatus.pending  => 'Pending',
    OptimizerSuggestionStatus.accepted => 'Accepted',
    OptimizerSuggestionStatus.rejected => 'Rejected',
    OptimizerSuggestionStatus.locked   => 'Locked',
  };

  String toJson() => name;
  static OptimizerSuggestionStatus fromJson(String s) =>
      OptimizerSuggestionStatus.values.firstWhere((e) => e.name == s,
          orElse: () => OptimizerSuggestionStatus.pending);
}

enum OptimizerConfidence {
  low,
  medium,
  high;

  String get label => switch (this) {
    OptimizerConfidence.low    => 'Low',
    OptimizerConfidence.medium => 'Medium',
    OptimizerConfidence.high   => 'High',
  };

  String toJson() => name;
  static OptimizerConfidence fromJson(String s) =>
      OptimizerConfidence.values.firstWhere((e) => e.name == s,
          orElse: () => OptimizerConfidence.low);
}

// ── Models ────────────────────────────────────────────────────────────────────

class OptimizerRunConfig {
  final OptimizerMode mode;
  final OptimizerScope scope;
  final int maxPeqBandsPerChannel;
  final double maxBoostDb;
  final double maxCutDb;
  final String targetPresetName;
  final String? notes;

  const OptimizerRunConfig({
    this.mode = OptimizerMode.balanced,
    this.scope = OptimizerScope.fullSystem,
    this.maxPeqBandsPerChannel = 8,
    this.maxBoostDb = 6.0,
    this.maxCutDb = 12.0,
    this.targetPresetName = 'flat',
    this.notes,
  });

  OptimizerRunConfig copyWith({
    OptimizerMode? mode,
    OptimizerScope? scope,
    int? maxPeqBandsPerChannel,
    double? maxBoostDb,
    double? maxCutDb,
    String? targetPresetName,
    String? notes,
  }) => OptimizerRunConfig(
    mode: mode ?? this.mode,
    scope: scope ?? this.scope,
    maxPeqBandsPerChannel: maxPeqBandsPerChannel ?? this.maxPeqBandsPerChannel,
    maxBoostDb: maxBoostDb ?? this.maxBoostDb,
    maxCutDb: maxCutDb ?? this.maxCutDb,
    targetPresetName: targetPresetName ?? this.targetPresetName,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.toJson(),
    'scope': scope.toJson(),
    'maxPeqBandsPerChannel': maxPeqBandsPerChannel,
    'maxBoostDb': maxBoostDb,
    'maxCutDb': maxCutDb,
    'targetPresetName': targetPresetName,
    if (notes != null) 'notes': notes,
  };

  factory OptimizerRunConfig.fromJson(Map<String, dynamic> j) => OptimizerRunConfig(
    mode: OptimizerMode.fromJson(j['mode'] as String? ?? 'balanced'),
    scope: OptimizerScope.fromJson(j['scope'] as String? ?? 'fullSystem'),
    maxPeqBandsPerChannel: j['maxPeqBandsPerChannel'] as int? ?? 8,
    maxBoostDb: (j['maxBoostDb'] as num?)?.toDouble() ?? 6.0,
    maxCutDb: (j['maxCutDb'] as num?)?.toDouble() ?? 12.0,
    targetPresetName: j['targetPresetName'] as String? ?? 'flat',
    notes: j['notes'] as String?,
  );
}

class OptimizerSuggestion {
  final String id;
  final OptimizerSuggestionType type;
  final OptimizerSuggestionStatus status;
  final OptimizerConfidence confidence;
  final String? channelId;
  final String title;
  final String description;
  final String reason;
  final double? proposedFrequencyHz;
  final double? proposedGainDb;
  final double? proposedQ;
  final double? proposedDelayMs;
  final double? proposedCrossoverHz;
  final String? proposedValueText;
  final DateTime createdAt;

  OptimizerSuggestion({
    required this.id,
    required this.type,
    this.status = OptimizerSuggestionStatus.pending,
    this.confidence = OptimizerConfidence.medium,
    this.channelId,
    required this.title,
    required this.description,
    required this.reason,
    this.proposedFrequencyHz,
    this.proposedGainDb,
    this.proposedQ,
    this.proposedDelayMs,
    this.proposedCrossoverHz,
    this.proposedValueText,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  OptimizerSuggestion copyWith({
    OptimizerSuggestionStatus? status,
    String? proposedValueText,
  }) => OptimizerSuggestion(
    id: id,
    type: type,
    status: status ?? this.status,
    confidence: confidence,
    channelId: channelId,
    title: title,
    description: description,
    reason: reason,
    proposedFrequencyHz: proposedFrequencyHz,
    proposedGainDb: proposedGainDb,
    proposedQ: proposedQ,
    proposedDelayMs: proposedDelayMs,
    proposedCrossoverHz: proposedCrossoverHz,
    proposedValueText: proposedValueText ?? this.proposedValueText,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toJson(),
    'status': status.toJson(),
    'confidence': confidence.toJson(),
    if (channelId != null) 'channelId': channelId,
    'title': title,
    'description': description,
    'reason': reason,
    if (proposedFrequencyHz != null) 'proposedFrequencyHz': proposedFrequencyHz,
    if (proposedGainDb != null) 'proposedGainDb': proposedGainDb,
    if (proposedQ != null) 'proposedQ': proposedQ,
    if (proposedDelayMs != null) 'proposedDelayMs': proposedDelayMs,
    if (proposedCrossoverHz != null) 'proposedCrossoverHz': proposedCrossoverHz,
    if (proposedValueText != null) 'proposedValueText': proposedValueText,
    'createdAt': createdAt.toIso8601String(),
  };

  factory OptimizerSuggestion.fromJson(Map<String, dynamic> j) => OptimizerSuggestion(
    id: j['id'] as String,
    type: OptimizerSuggestionType.fromJson(j['type'] as String? ?? 'warningOnly'),
    status: OptimizerSuggestionStatus.fromJson(j['status'] as String? ?? 'pending'),
    confidence: OptimizerConfidence.fromJson(j['confidence'] as String? ?? 'medium'),
    channelId: j['channelId'] as String?,
    title: j['title'] as String? ?? '',
    description: j['description'] as String? ?? '',
    reason: j['reason'] as String? ?? '',
    proposedFrequencyHz: (j['proposedFrequencyHz'] as num?)?.toDouble(),
    proposedGainDb: (j['proposedGainDb'] as num?)?.toDouble(),
    proposedQ: (j['proposedQ'] as num?)?.toDouble(),
    proposedDelayMs: (j['proposedDelayMs'] as num?)?.toDouble(),
    proposedCrossoverHz: (j['proposedCrossoverHz'] as num?)?.toDouble(),
    proposedValueText: j['proposedValueText'] as String?,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class OptimizerRunResult {
  final String id;
  final OptimizerRunConfig config;
  final List<OptimizerSuggestion> suggestions;
  final DateTime createdAt;
  final String summary;
  final int warningCount;

  OptimizerRunResult({
    required this.id,
    required this.config,
    required this.suggestions,
    DateTime? createdAt,
    this.summary = '',
    this.warningCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  OptimizerRunResult copyWith({
    List<OptimizerSuggestion>? suggestions,
    String? summary,
  }) => OptimizerRunResult(
    id: id,
    config: config,
    suggestions: suggestions ?? this.suggestions,
    createdAt: createdAt,
    summary: summary ?? this.summary,
    warningCount: warningCount,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'config': config.toJson(),
    'suggestions': suggestions.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'summary': summary,
    'warningCount': warningCount,
  };

  factory OptimizerRunResult.fromJson(Map<String, dynamic> j) => OptimizerRunResult(
    id: j['id'] as String,
    config: OptimizerRunConfig.fromJson(
        Map<String, dynamic>.from(j['config'] as Map? ?? {})),
    suggestions: (j['suggestions'] as List? ?? [])
        .map((e) => OptimizerSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    summary: j['summary'] as String? ?? '',
    warningCount: j['warningCount'] as int? ?? 0,
  );
}

class OptimizerProjectState {
  final List<OptimizerRunResult> runs;
  final String? activeRunId;
  final DateTime updatedAt;
  final int revision;

  OptimizerProjectState({
    this.runs = const [],
    this.activeRunId,
    DateTime? updatedAt,
    this.revision = 0,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ── Computed getters ──────────────────────────────────────────────────────

  OptimizerRunResult? get activeRun {
    if (activeRunId == null) return null;
    try {
      return runs.firstWhere((r) => r.id == activeRunId);
    } catch (_) {
      return runs.isNotEmpty ? runs.last : null;
    }
  }

  List<OptimizerSuggestion> get _activeSuggestions => activeRun?.suggestions ?? [];

  int get pendingSuggestionCount =>
      _activeSuggestions.where((s) => s.status == OptimizerSuggestionStatus.pending).length;
  int get acceptedSuggestionCount =>
      _activeSuggestions.where((s) => s.status == OptimizerSuggestionStatus.accepted).length;
  int get rejectedSuggestionCount =>
      _activeSuggestions.where((s) => s.status == OptimizerSuggestionStatus.rejected).length;
  int get lockedSuggestionCount =>
      _activeSuggestions.where((s) => s.status == OptimizerSuggestionStatus.locked).length;
  int get totalSuggestionCount => _activeSuggestions.length;

  String get readinessLabel {
    if (runs.isEmpty) return 'No optimizer runs';
    final pending = pendingSuggestionCount;
    final accepted = acceptedSuggestionCount;
    if (pending == 0 && accepted == 0) return 'All suggestions reviewed';
    if (pending > 0) return '$pending suggestion(s) pending review';
    return '$accepted suggestion(s) accepted';
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  OptimizerProjectState copyWith({
    List<OptimizerRunResult>? runs,
    String? activeRunId,
    DateTime? updatedAt,
    int? revision,
  }) => OptimizerProjectState(
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

  factory OptimizerProjectState.fromJson(Map<String, dynamic> j) =>
      OptimizerProjectState(
        runs: (j['runs'] as List? ?? [])
            .map((e) => OptimizerRunResult.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        activeRunId: j['activeRunId'] as String?,
        updatedAt:
            DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        revision: j['revision'] as int? ?? 0,
      );

  static OptimizerProjectState createDefault() => OptimizerProjectState();
}
