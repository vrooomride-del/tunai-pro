// ── TUNAI PRO Phase R — Versioned Deploy Package / Preset Management ──────────
// Review/dry-run packages only. No hardware write. No USBi/BLE/SafeLoad/EEPROM.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_export_data.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum DeployPackageStatus {
  draft,
  ready,
  blocked,
  archived,
  exported;

  String toJson() => name;
  static DeployPackageStatus fromJson(String s) =>
      DeployPackageStatus.values.firstWhere((e) => e.name == s,
          orElse: () => DeployPackageStatus.draft);

  String get label => switch (this) {
    DeployPackageStatus.draft    => 'Draft',
    DeployPackageStatus.ready    => 'Ready',
    DeployPackageStatus.blocked  => 'Blocked',
    DeployPackageStatus.archived => 'Archived',
    DeployPackageStatus.exported => 'Exported',
  };
}

enum DeployPackageKind {
  simulationPreset,
  dspExportDraft,
  hardwareDryRun,
  fullProjectSnapshot;

  String toJson() => name;
  static DeployPackageKind fromJson(String s) =>
      DeployPackageKind.values.firstWhere((e) => e.name == s,
          orElse: () => DeployPackageKind.fullProjectSnapshot);

  String get label => switch (this) {
    DeployPackageKind.simulationPreset   => 'Simulation Preset',
    DeployPackageKind.dspExportDraft     => 'DSP Export Draft',
    DeployPackageKind.hardwareDryRun     => 'Hardware Dry-run',
    DeployPackageKind.fullProjectSnapshot => 'Full Project Snapshot',
  };
}

enum DeployReadinessLevel {
  incomplete,
  warnings,
  readyForReview,
  readyForDryRun,
  blocked;

  String toJson() => name;
  static DeployReadinessLevel fromJson(String s) =>
      DeployReadinessLevel.values.firstWhere((e) => e.name == s,
          orElse: () => DeployReadinessLevel.incomplete);

  String get label => switch (this) {
    DeployReadinessLevel.incomplete    => 'Incomplete',
    DeployReadinessLevel.warnings      => 'Warnings',
    DeployReadinessLevel.readyForReview => 'Ready for Review',
    DeployReadinessLevel.readyForDryRun => 'Ready for Dry-run',
    DeployReadinessLevel.blocked       => 'Blocked',
  };
}

enum PresetSlotType {
  factory,
  user,
  project,
  experimental,
  archived;

  String toJson() => name;
  static PresetSlotType fromJson(String s) =>
      PresetSlotType.values.firstWhere((e) => e.name == s,
          orElse: () => PresetSlotType.project);

  String get label => switch (this) {
    PresetSlotType.factory      => 'Factory',
    PresetSlotType.user         => 'User',
    PresetSlotType.project      => 'Project',
    PresetSlotType.experimental => 'Experimental',
    PresetSlotType.archived     => 'Archived',
  };
}

// ── DeployPackageSnapshot ─────────────────────────────────────────────────────

class DeployPackageSnapshot {
  final String projectId;
  final String projectName;
  final String projectStatus;
  final DateTime createdAt;
  final int? tuningRevision;
  final int? protectionRevision;
  final int? exportRevision;
  final int? hardwareRevision;
  final int? simulationRevision;
  final Map<String, dynamic> measurementSummary;
  final Map<String, dynamic> tuningSummary;
  final Map<String, dynamic> simulationSummary;
  final Map<String, dynamic> protectionSummary;
  final Map<String, dynamic> exportSummary;
  final Map<String, dynamic> hardwareSummary;
  final List<String> warnings;
  final String? blockedReason;

  const DeployPackageSnapshot({
    required this.projectId,
    required this.projectName,
    required this.projectStatus,
    required this.createdAt,
    this.tuningRevision,
    this.protectionRevision,
    this.exportRevision,
    this.hardwareRevision,
    this.simulationRevision,
    this.measurementSummary = const {},
    this.tuningSummary = const {},
    this.simulationSummary = const {},
    this.protectionSummary = const {},
    this.exportSummary = const {},
    this.hardwareSummary = const {},
    this.warnings = const [],
    this.blockedReason,
  });

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'projectName': projectName,
    'projectStatus': projectStatus,
    'createdAt': createdAt.toIso8601String(),
    if (tuningRevision != null) 'tuningRevision': tuningRevision,
    if (protectionRevision != null) 'protectionRevision': protectionRevision,
    if (exportRevision != null) 'exportRevision': exportRevision,
    if (hardwareRevision != null) 'hardwareRevision': hardwareRevision,
    if (simulationRevision != null) 'simulationRevision': simulationRevision,
    'measurementSummary': measurementSummary,
    'tuningSummary': tuningSummary,
    'simulationSummary': simulationSummary,
    'protectionSummary': protectionSummary,
    'exportSummary': exportSummary,
    'hardwareSummary': hardwareSummary,
    'warnings': warnings,
    if (blockedReason != null) 'blockedReason': blockedReason,
  };

  factory DeployPackageSnapshot.fromJson(Map<String, dynamic> j) =>
      DeployPackageSnapshot(
        projectId: j['projectId'] as String? ?? '',
        projectName: j['projectName'] as String? ?? '',
        projectStatus: j['projectStatus'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        tuningRevision: j['tuningRevision'] as int?,
        protectionRevision: j['protectionRevision'] as int?,
        exportRevision: j['exportRevision'] as int?,
        hardwareRevision: j['hardwareRevision'] as int?,
        simulationRevision: j['simulationRevision'] as int?,
        measurementSummary:
            Map<String, dynamic>.from(j['measurementSummary'] as Map? ?? {}),
        tuningSummary:
            Map<String, dynamic>.from(j['tuningSummary'] as Map? ?? {}),
        simulationSummary:
            Map<String, dynamic>.from(j['simulationSummary'] as Map? ?? {}),
        protectionSummary:
            Map<String, dynamic>.from(j['protectionSummary'] as Map? ?? {}),
        exportSummary:
            Map<String, dynamic>.from(j['exportSummary'] as Map? ?? {}),
        hardwareSummary:
            Map<String, dynamic>.from(j['hardwareSummary'] as Map? ?? {}),
        warnings: List<String>.from(j['warnings'] as List? ?? []),
        blockedReason: j['blockedReason'] as String?,
      );
}

// ── DeployPackage ─────────────────────────────────────────────────────────────

class DeployPackage {
  final String id;
  final String version;
  final String name;
  final DeployPackageKind kind;
  final DeployPackageStatus status;
  final DeployReadinessLevel readinessLevel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DeployPackageSnapshot snapshot;
  final String? exportPackageId;
  final String? hardwarePlanId;
  final String? notes;

  const DeployPackage({
    required this.id,
    required this.version,
    required this.name,
    required this.kind,
    required this.status,
    required this.readinessLevel,
    required this.createdAt,
    required this.updatedAt,
    required this.snapshot,
    this.exportPackageId,
    this.hardwarePlanId,
    this.notes,
  });

  DeployPackage copyWith({
    String? version,
    String? name,
    DeployPackageKind? kind,
    DeployPackageStatus? status,
    DeployReadinessLevel? readinessLevel,
    DateTime? updatedAt,
    DeployPackageSnapshot? snapshot,
    String? exportPackageId,
    String? hardwarePlanId,
    String? notes,
  }) => DeployPackage(
    id: id,
    version: version ?? this.version,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    readinessLevel: readinessLevel ?? this.readinessLevel,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    snapshot: snapshot ?? this.snapshot,
    exportPackageId: exportPackageId ?? this.exportPackageId,
    hardwarePlanId: hardwarePlanId ?? this.hardwarePlanId,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'name': name,
    'kind': kind.toJson(),
    'status': status.toJson(),
    'readinessLevel': readinessLevel.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'snapshot': snapshot.toJson(),
    if (exportPackageId != null) 'exportPackageId': exportPackageId,
    if (hardwarePlanId != null) 'hardwarePlanId': hardwarePlanId,
    if (notes != null) 'notes': notes,
    'safetyNote': 'This deploy package is a review/dry-run package. No hardware write has been performed.',
  };

  factory DeployPackage.fromJson(Map<String, dynamic> j) => DeployPackage(
    id: j['id'] as String,
    version: j['version'] as String? ?? 'v0.0.0',
    name: j['name'] as String? ?? 'Unnamed Package',
    kind: DeployPackageKind.fromJson(j['kind'] as String? ?? 'fullProjectSnapshot'),
    status: DeployPackageStatus.fromJson(j['status'] as String? ?? 'draft'),
    readinessLevel: DeployReadinessLevel.fromJson(
        j['readinessLevel'] as String? ?? 'incomplete'),
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    snapshot: DeployPackageSnapshot.fromJson(
        Map<String, dynamic>.from(j['snapshot'] as Map? ?? {})),
    exportPackageId: j['exportPackageId'] as String?,
    hardwarePlanId: j['hardwarePlanId'] as String?,
    notes: j['notes'] as String?,
  );
}

// ── PresetRecord ──────────────────────────────────────────────────────────────

class PresetRecord {
  final String id;
  final String name;
  final String version;
  final PresetSlotType slotType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? deployPackageId;
  final DspTargetPlatform? targetPlatform;
  final String? description;
  final List<String> tags;
  final bool locked;
  final bool archived;

  const PresetRecord({
    required this.id,
    required this.name,
    required this.version,
    required this.slotType,
    required this.createdAt,
    required this.updatedAt,
    this.deployPackageId,
    this.targetPlatform,
    this.description,
    this.tags = const [],
    this.locked = false,
    this.archived = false,
  });

  PresetRecord copyWith({
    String? name,
    String? version,
    PresetSlotType? slotType,
    DateTime? updatedAt,
    String? deployPackageId,
    DspTargetPlatform? targetPlatform,
    String? description,
    List<String>? tags,
    bool? locked,
    bool? archived,
  }) => PresetRecord(
    id: id,
    name: name ?? this.name,
    version: version ?? this.version,
    slotType: slotType ?? this.slotType,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deployPackageId: deployPackageId ?? this.deployPackageId,
    targetPlatform: targetPlatform ?? this.targetPlatform,
    description: description ?? this.description,
    tags: tags ?? this.tags,
    locked: locked ?? this.locked,
    archived: archived ?? this.archived,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'slotType': slotType.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (deployPackageId != null) 'deployPackageId': deployPackageId,
    if (targetPlatform != null) 'targetPlatform': targetPlatform!.toJson(),
    if (description != null) 'description': description,
    'tags': tags,
    'locked': locked,
    'archived': archived,
  };

  factory PresetRecord.fromJson(Map<String, dynamic> j) => PresetRecord(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Unnamed Preset',
    version: j['version'] as String? ?? 'v0.0.0',
    slotType: PresetSlotType.fromJson(j['slotType'] as String? ?? 'project'),
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    deployPackageId: j['deployPackageId'] as String?,
    targetPlatform: j['targetPlatform'] != null
        ? DspTargetPlatform.fromJson(j['targetPlatform'] as String)
        : null,
    description: j['description'] as String?,
    tags: List<String>.from(j['tags'] as List? ?? []),
    locked: j['locked'] as bool? ?? false,
    archived: j['archived'] as bool? ?? false,
  );
}

// ── DeployProjectState ────────────────────────────────────────────────────────

class DeployProjectState {
  final List<DeployPackage> packages;
  final List<PresetRecord> presets;
  final String? activePackageId;
  final String? activePresetId;
  final DateTime updatedAt;
  final int revision;

  DeployProjectState({
    this.packages = const [],
    this.presets = const [],
    this.activePackageId,
    this.activePresetId,
    DateTime? updatedAt,
    this.revision = 0,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ── Computed getters ──────────────────────────────────────────────────────

  DeployPackage? get activePackage {
    if (packages.isEmpty) return null;
    if (activePackageId == null) return packages.last;
    try {
      return packages.firstWhere((p) => p.id == activePackageId);
    } catch (_) {
      return packages.last;
    }
  }

  PresetRecord? get activePreset {
    if (activePresetId == null) return null;
    try {
      return presets.firstWhere((p) => p.id == activePresetId);
    } catch (_) {
      return null;
    }
  }

  DeployPackage? get latestPackage =>
      packages.isEmpty ? null : packages.last;

  int get packageCount => packages.length;

  int get presetCount => presets.length;

  int get readyPackageCount => packages
      .where((p) =>
          p.status == DeployPackageStatus.ready ||
          p.readinessLevel == DeployReadinessLevel.readyForReview ||
          p.readinessLevel == DeployReadinessLevel.readyForDryRun)
      .length;

  int get blockedPackageCount =>
      packages.where((p) => p.status == DeployPackageStatus.blocked).length;

  String get readinessLabel {
    final pkg = activePackage;
    if (pkg == null) return 'No deploy package';
    return pkg.readinessLevel.label;
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  DeployProjectState copyWith({
    List<DeployPackage>? packages,
    List<PresetRecord>? presets,
    String? activePackageId,
    String? activePresetId,
    DateTime? updatedAt,
    int? revision,
  }) => DeployProjectState(
    packages: packages ?? this.packages,
    presets: presets ?? this.presets,
    activePackageId: activePackageId ?? this.activePackageId,
    activePresetId: activePresetId ?? this.activePresetId,
    updatedAt: updatedAt ?? this.updatedAt,
    revision: revision ?? this.revision,
  );

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'packages': packages.map((p) => p.toJson()).toList(),
    'presets': presets.map((p) => p.toJson()).toList(),
    if (activePackageId != null) 'activePackageId': activePackageId,
    if (activePresetId != null) 'activePresetId': activePresetId,
    'updatedAt': updatedAt.toIso8601String(),
    'revision': revision,
  };

  factory DeployProjectState.fromJson(Map<String, dynamic> j) =>
      DeployProjectState(
        packages: (j['packages'] as List? ?? [])
            .map((e) => DeployPackage.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        presets: (j['presets'] as List? ?? [])
            .map((e) => PresetRecord.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        activePackageId: j['activePackageId'] as String?,
        activePresetId: j['activePresetId'] as String?,
        updatedAt:
            DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        revision: j['revision'] as int? ?? 0,
      );

  static DeployProjectState createDefault() => DeployProjectState(
    packages: const [],
    presets: const [],
    revision: 0,
  );
}
