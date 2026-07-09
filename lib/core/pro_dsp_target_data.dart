// ── TUNAI PRO Phase I — DSP Target Profile & Biquad Draft Data Models ─────────
// Logical target profiles and coefficient placeholder structures only.
// No hardware addresses. No SigmaStudio register maps. No hardware write.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_export_data.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum DspSampleRate {
  hz48000,
  hz96000,
  hz192000;

  String get label => switch (this) {
    DspSampleRate.hz48000  => '48 kHz',
    DspSampleRate.hz96000  => '96 kHz',
    DspSampleRate.hz192000 => '192 kHz',
  };

  int get hz => switch (this) {
    DspSampleRate.hz48000  => 48000,
    DspSampleRate.hz96000  => 96000,
    DspSampleRate.hz192000 => 192000,
  };

  String toJson() => name;
  static DspSampleRate fromJson(String s) =>
      DspSampleRate.values.firstWhere((e) => e.name == s,
          orElse: () => DspSampleRate.hz48000);
}

enum DspPrecision {
  fixedPoint,
  floatingPoint,
  mixed;

  String get label => switch (this) {
    DspPrecision.fixedPoint   => 'Fixed-Point',
    DspPrecision.floatingPoint => 'Floating-Point',
    DspPrecision.mixed        => 'Mixed',
  };

  String toJson() => name;
  static DspPrecision fromJson(String s) =>
      DspPrecision.values.firstWhere((e) => e.name == s,
          orElse: () => DspPrecision.floatingPoint);
}

enum DspTargetCapabilityType {
  peq,
  crossover,
  gain,
  delay,
  phase,
  limiterPlaceholder,
  safeloadPlaceholder,
  sigmaStudioPlaceholder;

  String get label => switch (this) {
    DspTargetCapabilityType.peq                    => 'PEQ',
    DspTargetCapabilityType.crossover              => 'Crossover',
    DspTargetCapabilityType.gain                   => 'Gain',
    DspTargetCapabilityType.delay                  => 'Delay',
    DspTargetCapabilityType.phase                  => 'Phase',
    DspTargetCapabilityType.limiterPlaceholder     => 'Limiter (Placeholder)',
    DspTargetCapabilityType.safeloadPlaceholder    => 'SafeLoad (Placeholder)',
    DspTargetCapabilityType.sigmaStudioPlaceholder => 'SigmaStudio (Placeholder)',
  };

  String toJson() => name;
  static DspTargetCapabilityType fromJson(String s) =>
      DspTargetCapabilityType.values.firstWhere((e) => e.name == s,
          orElse: () => DspTargetCapabilityType.peq);
}

enum BiquadDraftStatus {
  notRequired,
  placeholder,
  calculatedDraft,
  requiresVerification;

  String get label => switch (this) {
    BiquadDraftStatus.notRequired          => 'Not Required',
    BiquadDraftStatus.placeholder          => 'Placeholder',
    BiquadDraftStatus.calculatedDraft      => 'Calculated Draft',
    BiquadDraftStatus.requiresVerification => 'Requires Verification',
  };

  String toJson() => name;
  static BiquadDraftStatus fromJson(String s) =>
      BiquadDraftStatus.values.firstWhere((e) => e.name == s,
          orElse: () => BiquadDraftStatus.placeholder);
}

// ── Models ────────────────────────────────────────────────────────────────────

class DspTargetCapability {
  final DspTargetCapabilityType type;
  final bool supported;
  final int? limit;
  final String? note;

  const DspTargetCapability({
    required this.type,
    this.supported = true,
    this.limit,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'type': type.toJson(),
    'supported': supported,
    if (limit != null) 'limit': limit,
    if (note != null) 'note': note,
  };

  factory DspTargetCapability.fromJson(Map<String, dynamic> j) =>
      DspTargetCapability(
        type: DspTargetCapabilityType.fromJson(j['type'] as String? ?? 'peq'),
        supported: j['supported'] as bool? ?? true,
        limit: j['limit'] as int?,
        note: j['note'] as String?,
      );
}

class DspTargetProfile {
  final DspTargetPlatform platform;
  final String displayName;
  final DspPrecision precision;
  final List<DspSampleRate> supportedSampleRates;
  final int maxChannels;
  final int maxPeqBandsPerChannel;
  final List<DspTargetCapability> capabilities;
  final String? warning;
  final String? notes;

  const DspTargetProfile({
    required this.platform,
    required this.displayName,
    required this.precision,
    required this.supportedSampleRates,
    required this.maxChannels,
    required this.maxPeqBandsPerChannel,
    required this.capabilities,
    this.warning,
    this.notes,
  });

  String get sampleRateLabel =>
      supportedSampleRates.map((r) => r.label).join(' / ');

  // ── Factory: create profile from platform ─────────────────────────────────

  factory DspTargetProfile.forPlatform(DspTargetPlatform platform) {
    switch (platform) {
      case DspTargetPlatform.simulationOnly:
        return DspTargetProfile(
          platform: platform,
          displayName: 'Simulation Only',
          precision: DspPrecision.floatingPoint,
          supportedSampleRates: const [
            DspSampleRate.hz48000,
            DspSampleRate.hz96000,
            DspSampleRate.hz192000,
          ],
          maxChannels: 16,
          maxPeqBandsPerChannel: 12,
          capabilities: const [
            DspTargetCapability(type: DspTargetCapabilityType.peq, supported: true, limit: 12),
            DspTargetCapability(type: DspTargetCapabilityType.crossover, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.gain, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.delay, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.phase, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.limiterPlaceholder, supported: false,
                note: 'Not applicable in simulation.'),
            DspTargetCapability(type: DspTargetCapabilityType.safeloadPlaceholder, supported: false,
                note: 'Not applicable in simulation.'),
            DspTargetCapability(type: DspTargetCapabilityType.sigmaStudioPlaceholder, supported: false,
                note: 'Not applicable in simulation.'),
          ],
        );

      case DspTargetPlatform.genericBiquad:
        return DspTargetProfile(
          platform: platform,
          displayName: 'Generic Biquad',
          precision: DspPrecision.floatingPoint,
          supportedSampleRates: const [
            DspSampleRate.hz48000,
            DspSampleRate.hz96000,
          ],
          maxChannels: 16,
          maxPeqBandsPerChannel: 12,
          capabilities: const [
            DspTargetCapability(type: DspTargetCapabilityType.peq, supported: true, limit: 12),
            DspTargetCapability(type: DspTargetCapabilityType.crossover, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.gain, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.delay, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.phase, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.limiterPlaceholder, supported: false,
                note: 'Platform-dependent.'),
            DspTargetCapability(type: DspTargetCapabilityType.safeloadPlaceholder, supported: false,
                note: 'Not applicable.'),
            DspTargetCapability(type: DspTargetCapabilityType.sigmaStudioPlaceholder, supported: false,
                note: 'Not applicable.'),
          ],
        );

      case DspTargetPlatform.adau1701:
        return DspTargetProfile(
          platform: platform,
          displayName: 'ADAU1701',
          precision: DspPrecision.fixedPoint,
          supportedSampleRates: const [
            DspSampleRate.hz48000,
          ],
          maxChannels: 4,
          maxPeqBandsPerChannel: 6,
          capabilities: const [
            DspTargetCapability(type: DspTargetCapabilityType.peq, supported: true, limit: 6,
                note: '6 biquad stages per channel (5.23 fixed-point).'),
            DspTargetCapability(type: DspTargetCapabilityType.crossover, supported: true,
                note: 'Via biquad cells.'),
            DspTargetCapability(type: DspTargetCapabilityType.gain, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.delay, supported: true,
                note: 'SPDIF delay cells (samples).'),
            DspTargetCapability(type: DspTargetCapabilityType.phase, supported: false,
                note: 'Phase via biquad approximation only.'),
            DspTargetCapability(type: DspTargetCapabilityType.limiterPlaceholder, supported: false,
                note: 'Placeholder — SigmaStudio program required.'),
            DspTargetCapability(type: DspTargetCapabilityType.safeloadPlaceholder, supported: true,
                note: 'SafeLoad available — not implemented here.'),
            DspTargetCapability(type: DspTargetCapabilityType.sigmaStudioPlaceholder, supported: true,
                note: 'Export address map requires SigmaStudio capture.'),
          ],
          warning: 'Logical profile only. No SigmaStudio addresses are defined.',
          notes: 'ADAU1701: 28-bit fixed-point. 2 ADC / 2 DAC. 4 audio channels.',
        );

      case DspTargetPlatform.adau1466:
        return DspTargetProfile(
          platform: platform,
          displayName: 'ADAU1466',
          precision: DspPrecision.fixedPoint,
          supportedSampleRates: const [
            DspSampleRate.hz48000,
            DspSampleRate.hz96000,
            DspSampleRate.hz192000,
          ],
          maxChannels: 16,
          maxPeqBandsPerChannel: 12,
          capabilities: const [
            DspTargetCapability(type: DspTargetCapabilityType.peq, supported: true, limit: 12,
                note: '32-bit fixed-point biquads.'),
            DspTargetCapability(type: DspTargetCapabilityType.crossover, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.gain, supported: true),
            DspTargetCapability(type: DspTargetCapabilityType.delay, supported: true,
                note: 'Up to 1024 samples at 48 kHz.'),
            DspTargetCapability(type: DspTargetCapabilityType.phase, supported: true,
                note: 'Via all-pass biquad cells.'),
            DspTargetCapability(type: DspTargetCapabilityType.limiterPlaceholder, supported: false,
                note: 'Placeholder — SigmaStudio program required.'),
            DspTargetCapability(type: DspTargetCapabilityType.safeloadPlaceholder, supported: true,
                note: 'SafeLoad available — not implemented here.'),
            DspTargetCapability(type: DspTargetCapabilityType.sigmaStudioPlaceholder, supported: true,
                note: 'Export address map requires SigmaStudio capture.'),
          ],
          warning: 'Logical profile only. No SigmaStudio addresses are defined.',
          notes: 'ADAU1466: 32-bit fixed-point. 16 channels. Up to 294.912 MHz core clock.',
        );
    }
  }

  Map<String, dynamic> toJson() => {
    'platform': platform.toJson(),
    'displayName': displayName,
    'precision': precision.toJson(),
    'supportedSampleRates': supportedSampleRates.map((r) => r.toJson()).toList(),
    'maxChannels': maxChannels,
    'maxPeqBandsPerChannel': maxPeqBandsPerChannel,
    'capabilities': capabilities.map((c) => c.toJson()).toList(),
    if (warning != null) 'warning': warning,
    if (notes != null) 'notes': notes,
  };

  factory DspTargetProfile.fromJson(Map<String, dynamic> j) =>
      DspTargetProfile.forPlatform(
          DspTargetPlatform.fromJson(j['platform'] as String? ?? 'simulationOnly'));
}

class DspParameterSlot {
  final String id;
  final String channelId;
  final ExportBlockType blockType;
  final String logicalName;
  final int? slotIndex;
  final String? addressPlaceholder;
  final String? notes;

  const DspParameterSlot({
    required this.id,
    required this.channelId,
    required this.blockType,
    required this.logicalName,
    this.slotIndex,
    this.addressPlaceholder,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelId': channelId,
    'blockType': blockType.toJson(),
    'logicalName': logicalName,
    if (slotIndex != null) 'slotIndex': slotIndex,
    if (addressPlaceholder != null) 'addressPlaceholder': addressPlaceholder,
    if (notes != null) 'notes': notes,
  };

  factory DspParameterSlot.fromJson(Map<String, dynamic> j) => DspParameterSlot(
    id: j['id'] as String,
    channelId: j['channelId'] as String? ?? '',
    blockType: ExportBlockType.fromJson(j['blockType'] as String? ?? 'peq'),
    logicalName: j['logicalName'] as String? ?? '',
    slotIndex: j['slotIndex'] as int?,
    addressPlaceholder: j['addressPlaceholder'] as String?,
    notes: j['notes'] as String?,
  );
}

class BiquadCoefficientSet {
  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;
  final BiquadDraftStatus status;
  final String? warning;
  // Phase J: optional metadata, backward-compatible
  final bool normalized;
  final String? source;

  const BiquadCoefficientSet({
    this.b0 = 1.0,
    this.b1 = 0.0,
    this.b2 = 0.0,
    this.a1 = 0.0,
    this.a2 = 0.0,
    this.status = BiquadDraftStatus.placeholder,
    this.warning,
    this.normalized = true,
    this.source,
  });

  Map<String, dynamic> toJson() => {
    'b0': b0, 'b1': b1, 'b2': b2, 'a1': a1, 'a2': a2,
    'status': status.toJson(),
    if (warning != null) 'warning': warning,
    'normalized': normalized,
    if (source != null) 'source': source,
  };

  factory BiquadCoefficientSet.fromJson(Map<String, dynamic> j) =>
      BiquadCoefficientSet(
        b0: (j['b0'] as num?)?.toDouble() ?? 1.0,
        b1: (j['b1'] as num?)?.toDouble() ?? 0.0,
        b2: (j['b2'] as num?)?.toDouble() ?? 0.0,
        a1: (j['a1'] as num?)?.toDouble() ?? 0.0,
        a2: (j['a2'] as num?)?.toDouble() ?? 0.0,
        status: BiquadDraftStatus.fromJson(j['status'] as String? ?? 'placeholder'),
        warning: j['warning'] as String?,
        normalized: j['normalized'] as bool? ?? true,
        source: j['source'] as String?,
      );

  static const placeholder = BiquadCoefficientSet(
    b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0,
    status: BiquadDraftStatus.placeholder,
    warning: 'Coefficient placeholder only. Final biquad calculation will be added later.',
  );
}

class BiquadDraftStage {
  final String id;
  final String channelId;
  final String sourceBlockId;
  final String title;
  final String filterSummary;
  final BiquadCoefficientSet coefficients;
  final String? notes;

  const BiquadDraftStage({
    required this.id,
    required this.channelId,
    required this.sourceBlockId,
    required this.title,
    required this.filterSummary,
    this.coefficients = BiquadCoefficientSet.placeholder,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelId': channelId,
    'sourceBlockId': sourceBlockId,
    'title': title,
    'filterSummary': filterSummary,
    'coefficients': coefficients.toJson(),
    if (notes != null) 'notes': notes,
  };

  factory BiquadDraftStage.fromJson(Map<String, dynamic> j) => BiquadDraftStage(
    id: j['id'] as String,
    channelId: j['channelId'] as String? ?? '',
    sourceBlockId: j['sourceBlockId'] as String? ?? '',
    title: j['title'] as String? ?? '',
    filterSummary: j['filterSummary'] as String? ?? '',
    coefficients: j['coefficients'] != null
        ? BiquadCoefficientSet.fromJson(
            Map<String, dynamic>.from(j['coefficients'] as Map))
        : BiquadCoefficientSet.placeholder,
    notes: j['notes'] as String?,
  );
}

class DspImplementationDraft {
  final DspTargetProfile targetProfile;
  final List<DspParameterSlot> parameterSlots;
  final List<BiquadDraftStage> biquadStages;
  final List<String> warnings;
  final DateTime createdAt;

  DspImplementationDraft({
    required this.targetProfile,
    this.parameterSlots = const [],
    this.biquadStages = const [],
    this.warnings = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get slotCount => parameterSlots.length;
  int get stageCount => biquadStages.length;

  int get calculatedCount => biquadStages
      .where((s) => s.coefficients.status == BiquadDraftStatus.calculatedDraft)
      .length;
  int get placeholderCount => biquadStages
      .where((s) => s.coefficients.status == BiquadDraftStatus.placeholder)
      .length;
  int get requiresVerificationCount => biquadStages
      .where((s) => s.coefficients.status == BiquadDraftStatus.requiresVerification)
      .length;

  String get readinessLabel {
    if (biquadStages.isEmpty && parameterSlots.isEmpty) return 'Target profile ready';
    if (placeholderCount > 0) return 'Biquad placeholders only';
    if (requiresVerificationCount > 0) return 'Some coefficients require verification';
    if (calculatedCount > 0) return 'Draft coefficients generated';
    return 'Target profile ready';
  }

  DspImplementationDraft copyWith({
    DspTargetProfile? targetProfile,
    List<DspParameterSlot>? parameterSlots,
    List<BiquadDraftStage>? biquadStages,
    List<String>? warnings,
  }) => DspImplementationDraft(
    targetProfile: targetProfile ?? this.targetProfile,
    parameterSlots: parameterSlots ?? this.parameterSlots,
    biquadStages: biquadStages ?? this.biquadStages,
    warnings: warnings ?? this.warnings,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'targetProfile': targetProfile.toJson(),
    'parameterSlots': parameterSlots.map((s) => s.toJson()).toList(),
    'biquadStages': biquadStages.map((s) => s.toJson()).toList(),
    'warnings': warnings,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DspImplementationDraft.fromJson(Map<String, dynamic> j) =>
      DspImplementationDraft(
        targetProfile: j['targetProfile'] != null
            ? DspTargetProfile.fromJson(
                Map<String, dynamic>.from(j['targetProfile'] as Map))
            : DspTargetProfile.forPlatform(DspTargetPlatform.simulationOnly),
        parameterSlots: (j['parameterSlots'] as List? ?? [])
            .map((e) => DspParameterSlot.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        biquadStages: (j['biquadStages'] as List? ?? [])
            .map((e) => BiquadDraftStage.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        warnings: List<String>.from(j['warnings'] as List? ?? []),
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
