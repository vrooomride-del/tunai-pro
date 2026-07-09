// ── TUNAI PRO Phase H/I — DSP Export Architecture Data Models ────────────────
// Draft export packages only. No hardware write. No USBi. No SafeLoad.
// AI suggests. Expert verifies. AOS protects. DSP executes.

// ── Enums ─────────────────────────────────────────────────────────────────────

enum DspTargetPlatform {
  simulationOnly,
  genericBiquad,
  adau1701,
  adau1466;

  String get label => switch (this) {
    DspTargetPlatform.simulationOnly => 'Simulation Only',
    DspTargetPlatform.genericBiquad  => 'Generic Biquad',
    DspTargetPlatform.adau1701       => 'ADAU1701',
    DspTargetPlatform.adau1466       => 'ADAU1466',
  };

  String get description => switch (this) {
    DspTargetPlatform.simulationOnly => 'No hardware target. Safe for review.',
    DspTargetPlatform.genericBiquad  => 'Platform-agnostic biquad coefficient draft.',
    DspTargetPlatform.adau1701       => 'SigmaStudio ADAU1701 parameter map (placeholder).',
    DspTargetPlatform.adau1466       => 'SigmaStudio ADAU1466 parameter map (placeholder).',
  };

  String toJson() => name;
  static DspTargetPlatform fromJson(String s) =>
      DspTargetPlatform.values.firstWhere((e) => e.name == s,
          orElse: () => DspTargetPlatform.simulationOnly);
}

enum ExportFormat {
  jsonPackage,
  biquadDraft,
  sigmaStudioPlaceholder,
  hardwareWritePlanPlaceholder;

  String get label => switch (this) {
    ExportFormat.jsonPackage                  => 'JSON Package',
    ExportFormat.biquadDraft                  => 'Biquad Draft',
    ExportFormat.sigmaStudioPlaceholder       => 'SigmaStudio Placeholder',
    ExportFormat.hardwareWritePlanPlaceholder => 'Hardware Write Plan Placeholder',
  };

  String get description => switch (this) {
    ExportFormat.jsonPackage                  => 'TUNAI PRO JSON archive of all parameters.',
    ExportFormat.biquadDraft                  => 'Draft biquad coefficient tables (no DSP addresses).',
    ExportFormat.sigmaStudioPlaceholder       => 'SigmaStudio-style parameter map (placeholder only).',
    ExportFormat.hardwareWritePlanPlaceholder => 'Hardware write plan structure (no register writes).',
  };

  String toJson() => name;
  static ExportFormat fromJson(String s) =>
      ExportFormat.values.firstWhere((e) => e.name == s,
          orElse: () => ExportFormat.jsonPackage);
}

enum ExportStatus {
  notReady,
  blocked,
  draftReady,
  exported;

  String get label => switch (this) {
    ExportStatus.notReady   => 'Not Ready',
    ExportStatus.blocked    => 'Blocked',
    ExportStatus.draftReady => 'Draft Ready',
    ExportStatus.exported   => 'Exported',
  };

  String toJson() => name;
  static ExportStatus fromJson(String s) =>
      ExportStatus.values.firstWhere((e) => e.name == s,
          orElse: () => ExportStatus.notReady);
}

enum ExportBlockType {
  peq,
  crossover,
  gain,
  delay,
  phase,
  protection;

  String get label => switch (this) {
    ExportBlockType.peq        => 'PEQ',
    ExportBlockType.crossover  => 'Crossover',
    ExportBlockType.gain       => 'Gain',
    ExportBlockType.delay      => 'Delay',
    ExportBlockType.phase      => 'Phase',
    ExportBlockType.protection => 'Protection',
  };

  String toJson() => name;
  static ExportBlockType fromJson(String s) =>
      ExportBlockType.values.firstWhere((e) => e.name == s,
          orElse: () => ExportBlockType.peq);
}

// ── Models ────────────────────────────────────────────────────────────────────

class ExportChannelMap {
  final String channelId;
  final String logicalName;
  final String role;
  final String side;
  final int? outputIndex;
  final String? notes;

  const ExportChannelMap({
    required this.channelId,
    required this.logicalName,
    required this.role,
    required this.side,
    this.outputIndex,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'channelId': channelId,
    'logicalName': logicalName,
    'role': role,
    'side': side,
    if (outputIndex != null) 'outputIndex': outputIndex,
    if (notes != null) 'notes': notes,
  };

  factory ExportChannelMap.fromJson(Map<String, dynamic> j) => ExportChannelMap(
    channelId: j['channelId'] as String,
    logicalName: j['logicalName'] as String? ?? '',
    role: j['role'] as String? ?? 'unknown',
    side: j['side'] as String? ?? 'left',
    outputIndex: j['outputIndex'] as int?,
    notes: j['notes'] as String?,
  );
}

class ExportParameterBlock {
  final String id;
  final ExportBlockType type;
  final String channelId;
  final String title;
  final String summary;
  final Map<String, dynamic> parameters;
  final String? warning;

  const ExportParameterBlock({
    required this.id,
    required this.type,
    required this.channelId,
    required this.title,
    required this.summary,
    required this.parameters,
    this.warning,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toJson(),
    'channelId': channelId,
    'title': title,
    'summary': summary,
    'parameters': parameters,
    if (warning != null) 'warning': warning,
  };

  factory ExportParameterBlock.fromJson(Map<String, dynamic> j) =>
      ExportParameterBlock(
        id: j['id'] as String,
        type: ExportBlockType.fromJson(j['type'] as String? ?? 'peq'),
        channelId: j['channelId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        parameters: Map<String, dynamic>.from(j['parameters'] as Map? ?? {}),
        warning: j['warning'] as String?,
      );
}

class DspExportPackage {
  final String id;
  final DspTargetPlatform targetPlatform;
  final ExportFormat format;
  final ExportStatus status;
  final DateTime createdAt;
  final String projectName;
  final int tuningRevision;
  final int protectionRevision;
  final int optimizerRevision;
  final List<ExportChannelMap> channelMaps;
  final List<ExportParameterBlock> parameterBlocks;
  final List<String> warnings;
  final String? blockedReason;
  final String? notes;
  // Phase I: serialized DspImplementationDraft (avoids circular import)
  final Map<String, dynamic>? implementationDraftJson;

  DspExportPackage({
    required this.id,
    this.targetPlatform = DspTargetPlatform.simulationOnly,
    this.format = ExportFormat.jsonPackage,
    this.status = ExportStatus.notReady,
    DateTime? createdAt,
    this.projectName = '',
    this.tuningRevision = 0,
    this.protectionRevision = 0,
    this.optimizerRevision = 0,
    this.channelMaps = const [],
    this.parameterBlocks = const [],
    this.warnings = const [],
    this.blockedReason,
    this.notes,
    this.implementationDraftJson,
  }) : createdAt = createdAt ?? DateTime.now();

  int get blockCount => parameterBlocks.length;
  int get warningCount => warnings.length;
  bool get isBlocked => status == ExportStatus.blocked;
  bool get isDraftReady => status == ExportStatus.draftReady;

  DspExportPackage copyWith({
    ExportStatus? status,
    List<ExportChannelMap>? channelMaps,
    List<ExportParameterBlock>? parameterBlocks,
    List<String>? warnings,
    String? blockedReason,
    Map<String, dynamic>? implementationDraftJson,
  }) => DspExportPackage(
    id: id,
    targetPlatform: targetPlatform,
    format: format,
    status: status ?? this.status,
    createdAt: createdAt,
    projectName: projectName,
    tuningRevision: tuningRevision,
    protectionRevision: protectionRevision,
    optimizerRevision: optimizerRevision,
    channelMaps: channelMaps ?? this.channelMaps,
    parameterBlocks: parameterBlocks ?? this.parameterBlocks,
    warnings: warnings ?? this.warnings,
    blockedReason: blockedReason ?? this.blockedReason,
    notes: notes,
    implementationDraftJson: implementationDraftJson ?? this.implementationDraftJson,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'targetPlatform': targetPlatform.toJson(),
    'format': format.toJson(),
    'status': status.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'projectName': projectName,
    'tuningRevision': tuningRevision,
    'protectionRevision': protectionRevision,
    'optimizerRevision': optimizerRevision,
    'channelMaps': channelMaps.map((c) => c.toJson()).toList(),
    'parameterBlocks': parameterBlocks.map((b) => b.toJson()).toList(),
    'warnings': warnings,
    if (blockedReason != null) 'blockedReason': blockedReason,
    if (notes != null) 'notes': notes,
    if (implementationDraftJson != null)
      'implementationDraft': implementationDraftJson,
  };

  factory DspExportPackage.fromJson(Map<String, dynamic> j) => DspExportPackage(
    id: j['id'] as String,
    targetPlatform: DspTargetPlatform.fromJson(j['targetPlatform'] as String? ?? 'simulationOnly'),
    format: ExportFormat.fromJson(j['format'] as String? ?? 'jsonPackage'),
    status: ExportStatus.fromJson(j['status'] as String? ?? 'notReady'),
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    projectName: j['projectName'] as String? ?? '',
    tuningRevision: j['tuningRevision'] as int? ?? 0,
    protectionRevision: j['protectionRevision'] as int? ?? 0,
    optimizerRevision: j['optimizerRevision'] as int? ?? 0,
    channelMaps: (j['channelMaps'] as List? ?? [])
        .map((e) => ExportChannelMap.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    parameterBlocks: (j['parameterBlocks'] as List? ?? [])
        .map((e) => ExportParameterBlock.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    warnings: List<String>.from(j['warnings'] as List? ?? []),
    blockedReason: j['blockedReason'] as String?,
    notes: j['notes'] as String?,
    implementationDraftJson: j['implementationDraft'] != null
        ? Map<String, dynamic>.from(j['implementationDraft'] as Map)
        : null,
  );
}

class ExportProjectState {
  final DspTargetPlatform selectedTarget;
  final ExportFormat selectedFormat;
  final List<DspExportPackage> packages;
  final String? activePackageId;
  final DateTime updatedAt;
  final int revision;

  ExportProjectState({
    this.selectedTarget = DspTargetPlatform.simulationOnly,
    this.selectedFormat = ExportFormat.jsonPackage,
    this.packages = const [],
    this.activePackageId,
    DateTime? updatedAt,
    this.revision = 0,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ── Computed getters ──────────────────────────────────────────────────────

  DspExportPackage? get activePackage {
    if (activePackageId == null) {
      return packages.isNotEmpty ? packages.last : null;
    }
    try {
      return packages.firstWhere((p) => p.id == activePackageId);
    } catch (_) {
      return packages.isNotEmpty ? packages.last : null;
    }
  }

  int get packageCount => packages.length;

  ExportStatus get lastStatus => activePackage?.status ?? ExportStatus.notReady;

  String get readinessLabel {
    if (packages.isEmpty) return 'No export packages';
    final pkg = activePackage;
    if (pkg == null) return 'No active package';
    switch (pkg.status) {
      case ExportStatus.blocked:
        return 'Export blocked: ${pkg.blockedReason ?? "Unknown reason"}';
      case ExportStatus.draftReady:
        final w = pkg.warningCount;
        return w > 0 ? 'Draft ready with $w warning(s)' : 'Draft ready';
      case ExportStatus.exported:
        return 'Exported';
      case ExportStatus.notReady:
        return 'Not ready';
    }
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  ExportProjectState copyWith({
    DspTargetPlatform? selectedTarget,
    ExportFormat? selectedFormat,
    List<DspExportPackage>? packages,
    String? activePackageId,
    DateTime? updatedAt,
    int? revision,
  }) => ExportProjectState(
    selectedTarget: selectedTarget ?? this.selectedTarget,
    selectedFormat: selectedFormat ?? this.selectedFormat,
    packages: packages ?? this.packages,
    activePackageId: activePackageId ?? this.activePackageId,
    updatedAt: updatedAt ?? DateTime.now(),
    revision: revision ?? this.revision,
  );

  Map<String, dynamic> toJson() => {
    'selectedTarget': selectedTarget.toJson(),
    'selectedFormat': selectedFormat.toJson(),
    'packages': packages.map((p) => p.toJson()).toList(),
    if (activePackageId != null) 'activePackageId': activePackageId,
    'updatedAt': updatedAt.toIso8601String(),
    'revision': revision,
  };

  factory ExportProjectState.fromJson(Map<String, dynamic> j) =>
      ExportProjectState(
        selectedTarget: DspTargetPlatform.fromJson(
            j['selectedTarget'] as String? ?? 'simulationOnly'),
        selectedFormat: ExportFormat.fromJson(
            j['selectedFormat'] as String? ?? 'jsonPackage'),
        packages: (j['packages'] as List? ?? [])
            .map((e) => DspExportPackage.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        activePackageId: j['activePackageId'] as String?,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        revision: j['revision'] as int? ?? 0,
      );

  static ExportProjectState createDefault() => ExportProjectState();
}
