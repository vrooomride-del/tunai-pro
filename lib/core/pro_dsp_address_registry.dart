// ── TUNAI PRO Phase P / U1 — Verified DSP Address Registry ───────────────────
// Reference-only registry for known, verified DSP parameter addresses.
// DO NOT write to hardware. DO NOT use addresses for register writes.
// Only verified addresses from SigmaStudio Export/Capture or validated direct-write
// work are allowed. SigmaStudio export-confirmed addresses require live validation.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_export_data.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum DspAddressVerificationStatus {
  unknown,
  exportConfirmed,        // extracted from SigmaStudio export — not yet live-validated
  needsLiveValidation,    // extracted but requires one-parameter capture to confirm
  liveWriteVerified,      // confirmed by controlled app-side live write validation
  verified,               // previously verified reference (e.g. Master Volume L/R)
  unverified,
  placeholder,
  deprecated,
  blocked;                // must not be written

  String toJson() => name;
  static DspAddressVerificationStatus fromJson(String s) =>
      DspAddressVerificationStatus.values.firstWhere((e) => e.name == s,
          orElse: () => DspAddressVerificationStatus.unknown);

  String get label => switch (this) {
    DspAddressVerificationStatus.unknown             => 'Unknown',
    DspAddressVerificationStatus.exportConfirmed     => 'Export Confirmed',
    DspAddressVerificationStatus.needsLiveValidation => 'Needs Live Validation',
    DspAddressVerificationStatus.liveWriteVerified   => 'Live Write Verified',
    DspAddressVerificationStatus.verified            => 'Verified',
    DspAddressVerificationStatus.unverified          => 'Unverified',
    DspAddressVerificationStatus.placeholder         => 'Placeholder',
    DspAddressVerificationStatus.deprecated          => 'Deprecated',
    DspAddressVerificationStatus.blocked             => 'Blocked',
  };

  // Only verified and liveWriteVerified are eligible for actual hardware write.
  bool get isActualWriteEligible =>
      this == verified || this == liveWriteVerified;
}

enum DspAddressSource {
  sigmaStudioExport,
  sigmaStudioCapture,
  directWriteValidated,
  liveWriteValidation,    // Phase U1+: one-parameter-at-a-time live validation
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
    DspAddressSource.liveWriteValidation  => 'Live Write Validation',
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
  polarity,
  protection,
  router,
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
    DspParameterKind.polarity      => 'Polarity',
    DspParameterKind.protection    => 'Protection',
    DspParameterKind.router        => 'Router',
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

  // Phase U1: optional SigmaStudio mapping fields
  final String? parameterId;
  final String? blockGroup;
  final String? sigmaOutputCell;
  final String? physicalOutput;
  final String? bandOrStage;
  final String? coefficient;
  final String? dataFormat;
  final String? writeMethod;
  final bool? safeloadRequired;
  final String? currentDataWord;
  final String? expectedEffect;

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
    this.parameterId,
    this.blockGroup,
    this.sigmaOutputCell,
    this.physicalOutput,
    this.bandOrStage,
    this.coefficient,
    this.dataFormat,
    this.writeMethod,
    this.safeloadRequired,
    this.currentDataWord,
    this.expectedEffect,
  });

  bool get isActualWriteEligible =>
      verificationStatus.isActualWriteEligible;

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
    if (parameterId != null) 'parameterId': parameterId,
    if (blockGroup != null) 'blockGroup': blockGroup,
    if (sigmaOutputCell != null) 'sigmaOutputCell': sigmaOutputCell,
    if (physicalOutput != null) 'physicalOutput': physicalOutput,
    if (bandOrStage != null) 'bandOrStage': bandOrStage,
    if (coefficient != null) 'coefficient': coefficient,
    if (dataFormat != null) 'dataFormat': dataFormat,
    if (writeMethod != null) 'writeMethod': writeMethod,
    if (safeloadRequired != null) 'safeloadRequired': safeloadRequired,
    if (currentDataWord != null) 'currentDataWord': currentDataWord,
    if (expectedEffect != null) 'expectedEffect': expectedEffect,
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
        parameterId: j['parameterId'] as String?,
        blockGroup: j['blockGroup'] as String?,
        sigmaOutputCell: j['sigmaOutputCell'] as String?,
        physicalOutput: j['physicalOutput'] as String?,
        bandOrStage: j['bandOrStage'] as String?,
        coefficient: j['coefficient'] as String?,
        dataFormat: j['dataFormat'] as String?,
        writeMethod: j['writeMethod'] as String?,
        safeloadRequired: j['safeloadRequired'] as bool?,
        currentDataWord: j['currentDataWord'] as String?,
        expectedEffect: j['expectedEffect'] as String?,
      );
}

// ── DspAddressRegistry ────────────────────────────────────────────────────────

class DspAddressRegistry {
  final List<VerifiedDspAddress> addresses;
  final DateTime updatedAt;
  final int revision;

  // Phase U1: PEQ rows are too numerous to index individually (875 rows).
  // Statistics are tracked separately.
  final int peqRowCount;
  final DspAddressVerificationStatus peqStatus;

  DspAddressRegistry({
    required this.addresses,
    DateTime? updatedAt,
    this.revision = 0,
    this.peqRowCount = 0,
    this.peqStatus = DspAddressVerificationStatus.unknown,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ── Computed getters ──────────────────────────────────────────────────────

  int get verifiedCount => addresses
      .where((a) => a.verificationStatus == DspAddressVerificationStatus.verified)
      .length;

  int get liveWriteVerifiedCount => addresses
      .where((a) => a.verificationStatus == DspAddressVerificationStatus.liveWriteVerified)
      .length;

  int get exportConfirmedCount => addresses
      .where((a) => a.verificationStatus == DspAddressVerificationStatus.exportConfirmed)
      .length;

  int get needsLiveValidationCount => addresses
      .where((a) => a.verificationStatus == DspAddressVerificationStatus.needsLiveValidation)
      .length;

  int get unknownCount => addresses
      .where((a) => a.verificationStatus == DspAddressVerificationStatus.unknown)
      .length;

  int get blockedCount => addresses
      .where((a) => a.verificationStatus == DspAddressVerificationStatus.blocked)
      .length;

  // Total including PEQ rows not individually indexed
  int get totalImportedCount => addresses.length + peqRowCount;

  List<VerifiedDspAddress> addressesForPlatform(DspTargetPlatform platform) =>
      addresses.where((a) => a.platform == platform).toList();

  List<VerifiedDspAddress> addressesForKind(DspParameterKind kind) =>
      addresses.where((a) => a.parameterKind == kind).toList();

  int countByKind(DspParameterKind kind) =>
      addresses.where((a) => a.parameterKind == kind).length;

  VerifiedDspAddress? findByLogicalName(String name) {
    try {
      return addresses.firstWhere((a) => a.logicalName == name);
    } catch (_) {
      return null;
    }
  }

  VerifiedDspAddress? findByAddressInt(int addr) {
    try {
      return addresses.firstWhere((a) => a.addressInt == addr);
    } catch (_) {
      return null;
    }
  }

  bool get hasVerifiedMasterVolume1466 => addresses.any(
      (a) =>
          a.platform == DspTargetPlatform.adau1466 &&
          a.parameterKind == DspParameterKind.masterVolume &&
          a.verificationStatus == DspAddressVerificationStatus.verified);

  bool get has3WayAddressMap =>
      peqRowCount > 0 || countByKind(DspParameterKind.mute) > 0;

  // Only verified/liveWriteVerified addresses may pass actual write guards.
  bool isActualWriteEligible(VerifiedDspAddress addr) =>
      addr.verificationStatus.isActualWriteEligible;

  // ── copyWith ──────────────────────────────────────────────────────────────

  DspAddressRegistry copyWith({
    List<VerifiedDspAddress>? addresses,
    DateTime? updatedAt,
    int? revision,
    int? peqRowCount,
    DspAddressVerificationStatus? peqStatus,
  }) => DspAddressRegistry(
    addresses: addresses ?? this.addresses,
    updatedAt: updatedAt ?? this.updatedAt,
    revision: revision ?? this.revision,
    peqRowCount: peqRowCount ?? this.peqRowCount,
    peqStatus: peqStatus ?? this.peqStatus,
  );

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'addresses': addresses.map((a) => a.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'revision': revision,
    'peqRowCount': peqRowCount,
    'peqStatus': peqStatus.toJson(),
  };

  factory DspAddressRegistry.fromJson(Map<String, dynamic> j) =>
      DspAddressRegistry(
        addresses: (j['addresses'] as List? ?? [])
            .map((e) => VerifiedDspAddress.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        revision: j['revision'] as int? ?? 0,
        peqRowCount: j['peqRowCount'] as int? ?? 0,
        peqStatus: DspAddressVerificationStatus.fromJson(
            j['peqStatus'] as String? ?? 'unknown'),
      );

  // ── Default registry (Phase P verified addresses only) ────────────────────
  // Only addresses confirmed by SigmaStudio Export/Capture or direct-write
  // validation are listed here. All others remain absent (not guessed).

  factory DspAddressRegistry.createDefault() => DspAddressRegistry(
    revision: 1,
    addresses: const [
      // ADAU1466 Master Volume L — 0x67
      VerifiedDspAddress(
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
      VerifiedDspAddress(
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
