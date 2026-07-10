// ── TUNAI PRO Phase T3 — Transport Command Envelope ──────────────────────────
// Transport-independent DSP write command envelope for controlled Master Volume
// dry-run preview. No hardware packets are generated in Phase T3.
//
// ABSOLUTE RESTRICTIONS:
//   - actualWriteAllowed must remain false.
//   - isExecutableNow must remain false.
//   - No USB, BLE, or ICP5 packet bytes are produced.
//   - Only ADAU1466 Master Volume L (0x0067) and R (0x0064) are supported.
//   - No SafeLoad. No EEPROM. No Selfboot. No Write-All.
//   - wasActualWrite must remain false everywhere.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_hardware_transport.dart';
import 'pro_export_data.dart'; // DspTargetPlatform

// ── Verified Master Volume addresses ─────────────────────────────────────────

const int kMasterVolumeLAddr = 0x0067;
const int kMasterVolumeRAddr = 0x0064;

bool isMasterVolumeAddress(int addrInt) =>
    addrInt == kMasterVolumeLAddr || addrInt == kMasterVolumeRAddr;

// ── Enums ─────────────────────────────────────────────────────────────────────

enum TransportCommandType {
  writeParameter,
  safeloadFuture,
  validationFuture,
  unsupported;

  String toJson() => name;
  static TransportCommandType fromJson(String s) =>
      TransportCommandType.values.firstWhere((e) => e.name == s,
          orElse: () => TransportCommandType.unsupported);

  String get label => switch (this) {
    TransportCommandType.writeParameter  => 'Write Parameter',
    TransportCommandType.safeloadFuture  => 'SafeLoad (Future)',
    TransportCommandType.validationFuture => 'Validation (Future)',
    TransportCommandType.unsupported     => 'Unsupported',
  };
}

enum TransportCommandStatus {
  draft,
  dryRunReady,
  blocked,
  awaitingConfirmation,
  transportDisabled,
  executedFuture,
  failed;

  String toJson() => name;
  static TransportCommandStatus fromJson(String s) =>
      TransportCommandStatus.values.firstWhere((e) => e.name == s,
          orElse: () => TransportCommandStatus.draft);

  String get label => switch (this) {
    TransportCommandStatus.draft                => 'Draft',
    TransportCommandStatus.dryRunReady          => 'Dry-Run Ready',
    TransportCommandStatus.blocked              => 'Blocked',
    TransportCommandStatus.awaitingConfirmation => 'Awaiting Confirmation',
    TransportCommandStatus.transportDisabled    => 'Transport Disabled',
    TransportCommandStatus.executedFuture       => 'Executed (Future)',
    TransportCommandStatus.failed               => 'Failed',
  };

  bool get isBlockedOrFailed =>
      this == blocked || this == failed || this == transportDisabled;
}

enum TransportWriteMode {
  volatileOnly,
  safeloadFuture,
  persistentForbidden;

  String toJson() => name;
  static TransportWriteMode fromJson(String s) =>
      TransportWriteMode.values.firstWhere((e) => e.name == s,
          orElse: () => TransportWriteMode.volatileOnly);

  String get label => switch (this) {
    TransportWriteMode.volatileOnly        => 'Volatile Only',
    TransportWriteMode.safeloadFuture      => 'SafeLoad (Future)',
    TransportWriteMode.persistentForbidden => 'Persistent (Forbidden)',
  };
}

// ── TransportCommandEnvelope ──────────────────────────────────────────────────

class TransportCommandEnvelope {
  final String id;
  final TransportCommandType commandType;
  final TransportCommandStatus status;
  final HardwareTransportBackend transportBackend;
  final DspTargetPlatform targetPlatform;
  final String parameterId;
  final String logicalName;
  final String addressHex;
  final int addressInt;
  final double? valueFloat;
  final String? fixedPointHex;
  final int? fixedPointInt;
  final String byteOrder;
  final TransportWriteMode writeMode;
  final bool requiresUserConfirmation;

  /// Always false in Phase T3. Must not be set to true without expert sign-off.
  final bool actualWriteAllowed;

  final String? blockedReason;
  final DateTime createdAt;
  final String? notes;

  TransportCommandEnvelope({
    required this.id,
    required this.commandType,
    required this.status,
    required this.transportBackend,
    required this.targetPlatform,
    required this.parameterId,
    required this.logicalName,
    required this.addressHex,
    required this.addressInt,
    this.valueFloat,
    this.fixedPointHex,
    this.fixedPointInt,
    required this.byteOrder,
    required this.writeMode,
    required this.requiresUserConfirmation,
    // Phase T3: actualWriteAllowed is always false — not a parameter
    this.blockedReason,
    DateTime? createdAt,
    this.notes,
  })  : actualWriteAllowed = false, // NEVER true in Phase T3
        createdAt = createdAt ?? DateTime.now();

  // ── Computed ──────────────────────────────────────────────────────────────

  /// Always false in Phase T3. No command can be executed now.
  bool get isExecutableNow => false;

  /// Always true — every command in Phase T3 is dry-run only.
  bool get isDryRunOnly => true;

  /// True only for verified Master Volume L (0x0067) or R (0x0064) addresses.
  bool get isMasterVolumeCommand => isMasterVolumeAddress(addressInt);

  /// True when this envelope meets the static eligibility criteria for the
  /// Phase T4A USBi temporary executor:
  ///   - isMasterVolumeCommand (address is 0x0067 or 0x0064)
  ///   - status == dryRunReady
  ///   - valueFloat is in [0.0, 1.0]
  /// Does NOT check platform, transport selection, or user confirmation.
  bool get eligibleForTemporaryUsbiExecution =>
      isMasterVolumeCommand &&
      status == TransportCommandStatus.dryRunReady &&
      (valueFloat ?? -1.0) >= 0.0 &&
      (valueFloat ?? 2.0) <= 1.0;

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id':                      id,
    'commandType':             commandType.toJson(),
    'status':                  status.toJson(),
    'transportBackend':        transportBackend.toJson(),
    'targetPlatform':          targetPlatform.toJson(),
    'parameterId':             parameterId,
    'logicalName':             logicalName,
    'addressHex':              addressHex,
    'addressInt':              addressInt,
    if (valueFloat != null)    'valueFloat':     valueFloat,
    if (fixedPointHex != null) 'fixedPointHex':  fixedPointHex,
    if (fixedPointInt != null) 'fixedPointInt':  fixedPointInt,
    'byteOrder':               byteOrder,
    'writeMode':               writeMode.toJson(),
    'requiresUserConfirmation': requiresUserConfirmation,
    'actualWriteAllowed':      actualWriteAllowed, // always false
    'isExecutableNow':         isExecutableNow,    // always false
    'isDryRunOnly':            isDryRunOnly,        // always true
    if (blockedReason != null) 'blockedReason':  blockedReason,
    'createdAt':               createdAt.toIso8601String(),
    if (notes != null)         'notes':           notes,
    // Safety note: no USB/BLE/ICP5 packet bytes in this envelope
    'safetyNote':
        'Phase T3 dry-run envelope. No hardware packet generated. '
        'No write performed. actualWriteAllowed = false.',
  };

  factory TransportCommandEnvelope.fromJson(Map<String, dynamic> j) =>
      TransportCommandEnvelope(
        id:           j['id'] as String,
        commandType:  TransportCommandType.fromJson(
            j['commandType'] as String? ?? 'unsupported'),
        status:       TransportCommandStatus.fromJson(
            j['status'] as String? ?? 'draft'),
        transportBackend: HardwareTransportBackend.fromJson(
            j['transportBackend'] as String? ?? 'simulation'),
        targetPlatform: DspTargetPlatform.fromJson(
            j['targetPlatform'] as String? ?? 'simulationOnly'),
        parameterId:  j['parameterId'] as String? ?? '',
        logicalName:  j['logicalName'] as String? ?? '',
        addressHex:   j['addressHex'] as String? ?? '',
        addressInt:   j['addressInt'] as int? ?? 0,
        valueFloat:   (j['valueFloat'] as num?)?.toDouble(),
        fixedPointHex: j['fixedPointHex'] as String?,
        fixedPointInt: j['fixedPointInt'] as int?,
        byteOrder:    j['byteOrder'] as String? ?? 'big-endian',
        writeMode:    TransportWriteMode.fromJson(
            j['writeMode'] as String? ?? 'volatileOnly'),
        requiresUserConfirmation:
            j['requiresUserConfirmation'] as bool? ?? true,
        blockedReason: j['blockedReason'] as String?,
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
        notes: j['notes'] as String?,
      );
}
