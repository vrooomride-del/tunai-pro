// ── TUNAI PRO Phase P — SigmaStudio Mapping Reference ────────────────────────
// Structural reference for SigmaStudio parameter block address mapping.
// All unverified mappings require SigmaStudio Export/Capture before use.
// DO NOT write to hardware. DO NOT invent DSP addresses.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_export_data.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum SigmaMappingStatus {
  unmapped,
  partiallyMapped,
  mappedVerified,
  mappedUnverified,
  requiresCapture;

  String toJson() => name;
  static SigmaMappingStatus fromJson(String s) =>
      SigmaMappingStatus.values.firstWhere((e) => e.name == s,
          orElse: () => SigmaMappingStatus.unmapped);

  String get label => switch (this) {
    SigmaMappingStatus.unmapped          => 'Unmapped',
    SigmaMappingStatus.partiallyMapped   => 'Partially Mapped',
    SigmaMappingStatus.mappedVerified    => 'Mapped — Verified',
    SigmaMappingStatus.mappedUnverified  => 'Mapped — Unverified',
    SigmaMappingStatus.requiresCapture   => 'Requires SigmaStudio Capture',
  };
}

enum SigmaBlockKind {
  masterVolume,
  peq,
  crossover,
  gain,
  delay,
  mute,
  output,
  safeload,
  unknown;

  String toJson() => name;
  static SigmaBlockKind fromJson(String s) =>
      SigmaBlockKind.values.firstWhere((e) => e.name == s,
          orElse: () => SigmaBlockKind.unknown);

  String get label => switch (this) {
    SigmaBlockKind.masterVolume => 'Master Volume',
    SigmaBlockKind.peq          => 'PEQ',
    SigmaBlockKind.crossover    => 'Crossover',
    SigmaBlockKind.gain         => 'Gain',
    SigmaBlockKind.delay        => 'Delay',
    SigmaBlockKind.mute         => 'Mute',
    SigmaBlockKind.output       => 'Output',
    SigmaBlockKind.safeload     => 'SafeLoad',
    SigmaBlockKind.unknown      => 'Unknown',
  };
}

// ── SigmaParameterMapping ─────────────────────────────────────────────────────

class SigmaParameterMapping {
  final String id;
  final DspTargetPlatform platform;
  final SigmaBlockKind blockKind;
  final String logicalName;
  final String? channelId;
  final String? addressId;
  final String? addressHex;
  final SigmaMappingStatus mappingStatus;
  final String? sourceNote;
  final String? warning;

  const SigmaParameterMapping({
    required this.id,
    required this.platform,
    required this.blockKind,
    required this.logicalName,
    this.channelId,
    this.addressId,
    this.addressHex,
    required this.mappingStatus,
    this.sourceNote,
    this.warning,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform.toJson(),
    'blockKind': blockKind.toJson(),
    'logicalName': logicalName,
    if (channelId != null) 'channelId': channelId,
    if (addressId != null) 'addressId': addressId,
    if (addressHex != null) 'addressHex': addressHex,
    'mappingStatus': mappingStatus.toJson(),
    if (sourceNote != null) 'sourceNote': sourceNote,
    if (warning != null) 'warning': warning,
  };

  factory SigmaParameterMapping.fromJson(Map<String, dynamic> j) =>
      SigmaParameterMapping(
        id: j['id'] as String,
        platform: DspTargetPlatform.fromJson(j['platform'] as String? ?? 'simulationOnly'),
        blockKind: SigmaBlockKind.fromJson(j['blockKind'] as String? ?? 'unknown'),
        logicalName: j['logicalName'] as String? ?? '',
        channelId: j['channelId'] as String?,
        addressId: j['addressId'] as String?,
        addressHex: j['addressHex'] as String?,
        mappingStatus: SigmaMappingStatus.fromJson(j['mappingStatus'] as String? ?? 'unmapped'),
        sourceNote: j['sourceNote'] as String?,
        warning: j['warning'] as String?,
      );
}

// ── SigmaMappingReference ─────────────────────────────────────────────────────

class SigmaMappingReference {
  final String id;
  final DspTargetPlatform platform;
  final DateTime createdAt;
  final List<SigmaParameterMapping> mappings;
  final List<String> warnings;
  final String summary;
  final SigmaMappingStatus status;

  SigmaMappingReference({
    required this.id,
    required this.platform,
    DateTime? createdAt,
    required this.mappings,
    required this.warnings,
    required this.summary,
    required this.status,
  }) : createdAt = createdAt ?? DateTime.now();

  // ── Computed getters ──────────────────────────────────────────────────────

  int get mappedCount => mappings
      .where((m) =>
          m.mappingStatus == SigmaMappingStatus.mappedVerified ||
          m.mappingStatus == SigmaMappingStatus.mappedUnverified)
      .length;

  int get verifiedMappedCount => mappings
      .where((m) => m.mappingStatus == SigmaMappingStatus.mappedVerified)
      .length;

  int get requiresCaptureCount => mappings
      .where((m) => m.mappingStatus == SigmaMappingStatus.requiresCapture)
      .length;

  String get readinessLabel {
    if (mappings.isEmpty) return 'No parameter mappings';
    if (status == SigmaMappingStatus.mappedVerified) {
      return 'Verified master volume mapping available';
    }
    if (requiresCaptureCount == mappings.length) {
      return 'Mapping requires SigmaStudio capture';
    }
    if (verifiedMappedCount > 0) {
      return 'Partial verified mapping — capture required for remainder';
    }
    return 'Mapping requires SigmaStudio capture';
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  SigmaMappingReference copyWith({
    List<SigmaParameterMapping>? mappings,
    List<String>? warnings,
    String? summary,
    SigmaMappingStatus? status,
  }) => SigmaMappingReference(
    id: id,
    platform: platform,
    createdAt: createdAt,
    mappings: mappings ?? this.mappings,
    warnings: warnings ?? this.warnings,
    summary: summary ?? this.summary,
    status: status ?? this.status,
  );

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'mappings': mappings.map((m) => m.toJson()).toList(),
    'warnings': warnings,
    'summary': summary,
    'status': status.toJson(),
  };

  factory SigmaMappingReference.fromJson(Map<String, dynamic> j) =>
      SigmaMappingReference(
        id: j['id'] as String,
        platform: DspTargetPlatform.fromJson(j['platform'] as String? ?? 'simulationOnly'),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        mappings: (j['mappings'] as List? ?? [])
            .map((e) => SigmaParameterMapping.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        warnings: List<String>.from(j['warnings'] as List? ?? []),
        summary: j['summary'] as String? ?? '',
        status: SigmaMappingStatus.fromJson(j['status'] as String? ?? 'unmapped'),
      );
}
