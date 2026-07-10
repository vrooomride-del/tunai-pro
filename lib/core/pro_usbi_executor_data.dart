// ── TUNAI PRO Phase T4A — USBi Temporary Executor Data ───────────────────────
// Strictly controlled execution data for ADAU1466 Master Volume L/R writes
// via the temporary Windows USBi engineering transport.
//
// ABSOLUTE RESTRICTIONS:
//   - wasActualWrite defaults false — only true if native write occurred.
//   - Only ADAU1466 Master Volume L (0x0067) and R (0x0064) are allowed.
//   - No PEQ / XO / Gain / Mute / Delay / SafeLoad / EEPROM / Selfboot.
//   - Platform must be Windows for actual write (injectable for tests).
//   - Transport must be HardwareTransportBackend.usbiWindowsTemporary.
//   - USBi is TEMPORARY. ICP5 remains the final target.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_hardware_transport.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum UsbiExecutionStatus {
  draft,
  ready,
  blocked,
  awaitingUserConfirmation,
  transportUnavailable,
  unsupportedPlatform,
  sent,
  ackReceived,
  ackFailed,
  failed;

  String toJson() => name;
  static UsbiExecutionStatus fromJson(String s) =>
      UsbiExecutionStatus.values.firstWhere((e) => e.name == s,
          orElse: () => UsbiExecutionStatus.draft);

  String get label => switch (this) {
    UsbiExecutionStatus.draft                  => 'Draft',
    UsbiExecutionStatus.ready                  => 'Ready',
    UsbiExecutionStatus.blocked                => 'Blocked',
    UsbiExecutionStatus.awaitingUserConfirmation => 'Awaiting Confirmation',
    UsbiExecutionStatus.transportUnavailable   => 'Transport Unavailable',
    UsbiExecutionStatus.unsupportedPlatform    => 'Unsupported Platform',
    UsbiExecutionStatus.sent                   => 'Sent',
    UsbiExecutionStatus.ackReceived            => 'ACK Received',
    UsbiExecutionStatus.ackFailed              => 'ACK Failed',
    UsbiExecutionStatus.failed                 => 'Failed',
  };

  bool get isTerminal =>
      this == sent || this == ackReceived || this == ackFailed || this == failed;

  bool get isSuccess => this == ackReceived;
}

enum UsbiExecutionGuardCode {
  platformNotWindows,
  transportNotUsbiTemporary,
  transportNotConnected,
  commandNotMasterVolume,
  addressNotVerifiedMasterVolume,
  valueOutOfRange,
  userConfirmationMissing,
  writeBackendDisabled,
  packetBuildFailed,
  ackFailed,
  blockedBySafetyPolicy;

  String toJson() => name;
  static UsbiExecutionGuardCode fromJson(String s) =>
      UsbiExecutionGuardCode.values.firstWhere((e) => e.name == s,
          orElse: () => UsbiExecutionGuardCode.blockedBySafetyPolicy);

  String get label => switch (this) {
    UsbiExecutionGuardCode.platformNotWindows           => 'Platform Not Windows',
    UsbiExecutionGuardCode.transportNotUsbiTemporary    => 'Transport Not USBi Temporary',
    UsbiExecutionGuardCode.transportNotConnected        => 'Transport Not Connected',
    UsbiExecutionGuardCode.commandNotMasterVolume       => 'Command Not Master Volume',
    UsbiExecutionGuardCode.addressNotVerifiedMasterVolume =>
        'Address Not Verified Master Volume',
    UsbiExecutionGuardCode.valueOutOfRange              => 'Value Out Of Range',
    UsbiExecutionGuardCode.userConfirmationMissing      => 'User Confirmation Missing',
    UsbiExecutionGuardCode.writeBackendDisabled         => 'Write Backend Disabled',
    UsbiExecutionGuardCode.packetBuildFailed            => 'Packet Build Failed',
    UsbiExecutionGuardCode.ackFailed                    => 'ACK Failed',
    UsbiExecutionGuardCode.blockedBySafetyPolicy        => 'Blocked By Safety Policy',
  };
}

// ── Models ────────────────────────────────────────────────────────────────────

class UsbiExecutionGuardResult {
  final bool passed;
  final UsbiExecutionGuardCode code;
  final String message;
  final String severity; // 'block' | 'warn'

  const UsbiExecutionGuardResult({
    required this.passed,
    required this.code,
    required this.message,
    this.severity = 'block',
  });

  Map<String, dynamic> toJson() => {
    'passed':   passed,
    'code':     code.toJson(),
    'message':  message,
    'severity': severity,
  };

  factory UsbiExecutionGuardResult.fromJson(Map<String, dynamic> j) =>
      UsbiExecutionGuardResult(
        passed:   j['passed'] as bool? ?? false,
        code:     UsbiExecutionGuardCode.fromJson(
            j['code'] as String? ?? 'blockedBySafetyPolicy'),
        message:  j['message'] as String? ?? '',
        severity: j['severity'] as String? ?? 'block',
      );
}

class UsbiExecutionRequest {
  final String id;
  final String commandEnvelopeId;
  final HardwareTransportBackend transportBackend;
  final String parameterId;
  final String logicalName;
  final String addressHex;
  final int addressInt;
  final String fixedPointHex;
  final int fixedPointInt;
  final double valueFloat;
  final bool userConfirmed;

  /// Restore value — written on restore-unity request. Defaults to 1.0.
  final double restoreValueFloat;
  final DateTime createdAt;

  UsbiExecutionRequest({
    required this.id,
    required this.commandEnvelopeId,
    required this.transportBackend,
    required this.parameterId,
    required this.logicalName,
    required this.addressHex,
    required this.addressInt,
    required this.fixedPointHex,
    required this.fixedPointInt,
    required this.valueFloat,
    required this.userConfirmed,
    this.restoreValueFloat = 1.0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id':                id,
    'commandEnvelopeId': commandEnvelopeId,
    'transportBackend':  transportBackend.toJson(),
    'parameterId':       parameterId,
    'logicalName':       logicalName,
    'addressHex':        addressHex,
    'addressInt':        addressInt,
    'fixedPointHex':     fixedPointHex,
    'fixedPointInt':     fixedPointInt,
    'valueFloat':        valueFloat,
    'userConfirmed':     userConfirmed,
    'restoreValueFloat': restoreValueFloat,
    'createdAt':         createdAt.toIso8601String(),
  };

  factory UsbiExecutionRequest.fromJson(Map<String, dynamic> j) =>
      UsbiExecutionRequest(
        id:                j['id'] as String,
        commandEnvelopeId: j['commandEnvelopeId'] as String? ?? '',
        transportBackend:  HardwareTransportBackend.fromJson(
            j['transportBackend'] as String? ?? 'usbiWindowsTemporary'),
        parameterId:       j['parameterId'] as String? ?? '',
        logicalName:       j['logicalName'] as String? ?? '',
        addressHex:        j['addressHex'] as String? ?? '',
        addressInt:        j['addressInt'] as int? ?? 0,
        fixedPointHex:     j['fixedPointHex'] as String? ?? '',
        fixedPointInt:     j['fixedPointInt'] as int? ?? 0,
        valueFloat:        (j['valueFloat'] as num?)?.toDouble() ?? 0.0,
        userConfirmed:     j['userConfirmed'] as bool? ?? false,
        restoreValueFloat: (j['restoreValueFloat'] as num?)?.toDouble() ?? 1.0,
        createdAt:         j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
      );
}

class UsbiExecutionResult {
  final String id;
  final String requestId;
  final UsbiExecutionStatus status;

  /// True only if native write call actually occurred and returned success.
  /// Defaults false. Never true when native backend is disabled.
  final bool wasActualWrite;

  /// True only if expected ACK byte (0x01) was received.
  final bool ackReceived;

  final String? ackByteHex;
  final String? error;
  final List<UsbiExecutionGuardResult> guardResults;
  final DateTime? executedAt;
  final String? notes;

  UsbiExecutionResult({
    required this.id,
    required this.requestId,
    required this.status,
    this.wasActualWrite = false, // defaults false
    this.ackReceived    = false, // defaults false
    this.ackByteHex,
    this.error,
    this.guardResults = const [],
    this.executedAt,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'id':            id,
    'requestId':     requestId,
    'status':        status.toJson(),
    'wasActualWrite': wasActualWrite,
    'ackReceived':   ackReceived,
    if (ackByteHex != null) 'ackByteHex': ackByteHex,
    if (error != null)      'error':      error,
    'guardResults':  guardResults.map((g) => g.toJson()).toList(),
    if (executedAt != null) 'executedAt': executedAt!.toIso8601String(),
    if (notes != null)      'notes':      notes,
    'safetyNote':
        'Phase T4A USBi temporary executor. '
        'ADAU1466 Master Volume L/R only. Volatile write. '
        'No EEPROM. No Selfboot. No SafeLoad. USBi is temporary.',
  };

  factory UsbiExecutionResult.fromJson(Map<String, dynamic> j) =>
      UsbiExecutionResult(
        id:           j['id'] as String,
        requestId:    j['requestId'] as String? ?? '',
        status:       UsbiExecutionStatus.fromJson(
            j['status'] as String? ?? 'failed'),
        wasActualWrite: j['wasActualWrite'] as bool? ?? false,
        ackReceived:    j['ackReceived']    as bool? ?? false,
        ackByteHex:    j['ackByteHex'] as String?,
        error:         j['error']     as String?,
        guardResults:  (j['guardResults'] as List? ?? [])
            .map((e) => UsbiExecutionGuardResult.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        executedAt: j['executedAt'] != null
            ? DateTime.tryParse(j['executedAt'] as String)
            : null,
        notes: j['notes'] as String?,
      );
}
