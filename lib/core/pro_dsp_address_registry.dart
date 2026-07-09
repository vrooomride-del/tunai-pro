// ── TUNAI PRO Phase P — Verified DSP Address Registry ─────────────────────────
// Reference-only registry for known, verified DSP parameter addresses.
// DO NOT write to hardware. DO NOT use addresses for register writes.
// Only verified addresses from SigmaStudio Export/Capture or validated direct-write
// work are allowed. All others remain unknown.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_export_data.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum DspAddressVerificationStatus {
  unknown,
  verified,
  unverified,
  placeholder,
  deprecated;

  String toJson() => name;
  static DspAddressVerificationStatus fromJson(String s) =>
      DspAddressVerificationStatus.values.firstWhere((e) => e.name == s,
          orElse: () => DspAddressVerificationStatus.unknown);

  String get label => switch (this) {
    DspAddressVerificationStatus.unknown     => 'Unknown',
    DspAddressVerificationStatus.verified    => 'Verified',
    DspAddressVerificationStatus.unverified  => 'Unverified',
    DspAddressVerificationStatus.placeholder => 'Placeholder',
    DspAddressVerificationStatus.deprecated  => 'Deprecated',
  };
}

enum DspAddressSource {
  sigmaStudioExport,
  sigmaStudioCapture,
  directWriteValidated,
  manualEntry,
  placeholder;

  String toJson() => name;
  static DspAddressSource fromJson(String s) =>
      DspAddressSource.values.firstWhere((e) => e.name == s,
          orElse: () => DspAddressSource.placeholder);

  String get label => switch (this) {
    DspAddressSource.sigmaStudioExport    => 'SigmaStudio Export',
    DspAddressSource.sigmaStudioCapture   => 'SigmaStudio Capture',
    DspAddressSource.directWriteValidated => 'Direct-Write Validated',
    DspAddressSource.manualEntry          => 'Manual Entry',
    DspAddressSource.placeholder          => 'Placeholder',
  };
}

enum DspParameterKind {
  masterVolume,
  peq,
  crossover,
  gain,
  mute,
  delay,
  phase,
  safeload,
  outputMapping,
  unknown;

  String toJson() => name;
  static DspParameterKind fromJson(String s) =>
      DspParameterKind.values.firstWhere((e) => e.name == s,
          orElse: () => DspParameterKind.unknown);

  String get label => switch (this) {
    DspParameterKind.masterVolume  => 'Master Volume',
    DspParameterKind.peq           => 'PEQ',
    DspParameterKind.crossover     => 'Crossover',
    DspParameterKind.gain          => 'Gain',
    DspParameterKind.mute          => 'Mute',
    DspParameterKind.delay         => 'Delay',
    DspParameterKind.phase         => 'Phase',
    DspParameterKind.safeload      => 'SafeLoad',
    DspParameterKind.outputMapping => 'Output Mapping',
    DspParameterKind.unknown       => 'Unknown',
  };
}

// ── VerifiedDspAddress ────────────────────────────────────────────────────────

class VerifiedDspAddress {
  final String id;
  final DspTargetPlatform platform;
  final DspParameterKind parameterKind;
  final String? channelId;
  final String logicalName;
  final String addressHex;
  final int addressInt;
  final DspAddressVerificationStatus verificationStatus;
  final DspAddressSource source;
  final String? notes;
  final DateTime? verifiedAt;

  const VerifiedDspAddress({
    required this.id,
    required this.platform,
    required this.parameterKind,
    this.channelId,
    required this.logicalName,
    required this.addressHex,
    required this.addressInt,
    required this.verificationStatus,
    required this.source,
    this.notes,
    this.verifiedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform.toJson(),
    'parameterKind': parameterKind.toJson(),
    if (channelId != null) 'channelId': channelId,
    'logicalName': logicalName,
    'addressHex': addressHex,
    'addressInt': addressInt,
    'verificationStatus': verificationStatus.toJson(),
    'source': source.toJson(),
    if (notes != null) 'notes': notes,
    if (verifiedAt != null) 'verifiedAt': verifiedAt!.toIso8601String(),
  };

  factory VerifiedDspAddress.fromJson(Map<String, dynamic> j) =>
      VerifiedDspAddress(
        id: j['id'] as String,
        platform: DspTargetPlatform.fromJson(j['platform'] as String? ?? 'simulationOnly'),
        parameterKind: DspParameterKind.fromJson(j['parameterKind'] as String? ?? 'unknown'),
        channelId: j['channelId'] as String?,
        logicalName: j['logicalName'] as String? ?? '',
        addressHex: j['addressHex'] as String? ?? '0x00',
        addressInt: j['addressInt'] as int? ?? 0,
        verificationStatus: DspAddressVerificationStatus.fromJson(
            j['verificationStatus'] as String? ?? 'unknown'),
        source: DspAddressSource.fromJson(j['source'] as String? ?? 'placeholder'),
        notes: j['notes'] as String?,
        verifiedAt: j['verifiedAt'] != null
            ? DateTime.tryParse(j['verifiedAt'] as String)
            : null,
      );
}

// ── DspAddressRegistry ────────────────────────────────────────────────────────

class DspAddressRegistry {
  final List<VerifiedDspAddress> addresses;
  final DateTime updatedAt;
  final int revision;

  DspAddressRegistry({
    required this.addresses,
    DateTime? updatedAt,
    this.revision = 0,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ── Computed getters ──────────────────────────────────────────────────────

  int get verifiedCount => addresses
      .where((a) => a.verificationStatus == DspAddressVerificationStatus.verified)
      .length;

  int get unknownCount => addresses
      .where((a) => a.verificationStatus == DspAddressVerificationStatus.unknown)
      .length;

  List<VerifiedDspAddress> addressesForPlatform(DspTargetPlatform platform) =>
      addresses.where((a) => a.platform == platform).toList();

  VerifiedDspAddress? findByLogicalName(String name) {
    try {
      return addresses.firstWhere((a) => a.logicalName == name);
    } catch (_) {
      return null;
    }
  }

  bool get hasVerifiedMasterVolume1466 => addresses.any(
      (a) =>
          a.platform == DspTargetPlatform.adau1466 &&
          a.parameterKind == DspParameterKind.masterVolume &&
          a.verificationStatus == DspAddressVerificationStatus.verified);

  // ── copyWith ──────────────────────────────────────────────────────────────

  DspAddressRegistry copyWith({
    List<VerifiedDspAddress>? addresses,
    DateTime? updatedAt,
    int? revision,
  }) => DspAddressRegistry(
    addresses: addresses ?? this.addresses,
    updatedAt: updatedAt ?? this.updatedAt,
    revision: revision ?? this.revision,
  );

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'addresses': addresses.map((a) => a.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'revision': revision,
  };

  factory DspAddressRegistry.fromJson(Map<String, dynamic> j) =>
      DspAddressRegistry(
        addresses: (j['addresses'] as List? ?? [])
            .map((e) => VerifiedDspAddress.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        revision: j['revision'] as int? ?? 0,
      );

  // ── Default registry (Phase P verified addresses only) ────────────────────
  // Only addresses confirmed by SigmaStudio Export/Capture or direct-write
  // validation are listed here. All others remain absent (not guessed).

  factory DspAddressRegistry.createDefault() => DspAddressRegistry(
    revision: 1,
    addresses: [
      // ADAU1466 Master Volume L — 0x67
      // Verified from ADAU1466 master volume direct-write/capture work.
      const VerifiedDspAddress(
        id: 'adau1466_master_vol_l',
        platform: DspTargetPlatform.adau1466,
        parameterKind: DspParameterKind.masterVolume,
        logicalName: 'Master Volume L',
        addressHex: '0x67',
        addressInt: 0x67,
        verificationStatus: DspAddressVerificationStatus.verified,
        source: DspAddressSource.directWriteValidated,
        notes: 'Verified from previous ADAU1466 master volume direct-write/capture work. '
            'Do not generalize to other parameters.',
      ),
      // ADAU1466 Master Volume R — 0x64
      const VerifiedDspAddress(
        id: 'adau1466_master_vol_r',
        platform: DspTargetPlatform.adau1466,
        parameterKind: DspParameterKind.masterVolume,
        logicalName: 'Master Volume R',
        addressHex: '0x64',
        addressInt: 0x64,
        verificationStatus: DspAddressVerificationStatus.verified,
        source: DspAddressSource.directWriteValidated,
        notes: 'Verified from previous ADAU1466 master volume direct-write/capture work. '
            'Do not generalize to other parameters.',
      ),
    ],
  );
}
