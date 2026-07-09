// ── TUNAI PRO Phase T — Controlled Hardware Write Data ────────────────────────
// Safety-first data model for the controlled master volume write prototype.
//
// ABSOLUTE RESTRICTIONS (must never be changed without expert sign-off):
//   - Only ADAU1466 Master Volume L (0x67) and R (0x64) are verified addresses.
//   - Do NOT add arbitrary register addresses.
//   - Do NOT add EEPROM / Selfboot / SafeLoad targets.
//   - Do NOT add Write-All / bulk-write paths.
//   - No auto-write on startup.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

// ── Enums ─────────────────────────────────────────────────────────────────────

enum HardwareWritePermission {
  disabled,
  dryRunOnly,
  controlledMasterVolumeOnly;

  String get label => switch (this) {
    disabled                    => 'Disabled',
    dryRunOnly                  => 'Dry Run Only',
    controlledMasterVolumeOnly  => 'Controlled Master Volume Only',
  };

  bool get allowsWrite =>
      this == controlledMasterVolumeOnly;

  String toJson() => name;
  static HardwareWritePermission fromJson(String s) =>
      HardwareWritePermission.values.firstWhere((e) => e.name == s,
          orElse: () => HardwareWritePermission.disabled);
}

enum HardwareWriteStatus {
  notStarted,
  dryRunReady,
  waitingForConfirmation,
  writing,
  success,
  failed,
  blocked;

  String get label => switch (this) {
    notStarted              => 'Not Started',
    dryRunReady             => 'Dry Run Ready',
    waitingForConfirmation  => 'Waiting for Confirmation',
    writing                 => 'Writing…',
    success                 => 'Success',
    failed                  => 'Failed',
    blocked                 => 'Blocked',
  };

  bool get isTerminal => this == success || this == failed || this == blocked;
  bool get isActive   => this == writing;

  String toJson() => name;
  static HardwareWriteStatus fromJson(String s) =>
      HardwareWriteStatus.values.firstWhere((e) => e.name == s,
          orElse: () => HardwareWriteStatus.notStarted);
}

// Only verified ADAU1466 addresses are listed here.
// Addresses are locked: do NOT add new entries without hardware validation.
enum HardwareWriteTarget {
  adau1466MasterVolumeL,  // 0x67 — directWriteValidated
  adau1466MasterVolumeR;  // 0x64 — directWriteValidated

  String get label => switch (this) {
    adau1466MasterVolumeL => 'ADAU1466 Master Volume L',
    adau1466MasterVolumeR => 'ADAU1466 Master Volume R',
  };

  // Verified integer addresses — do NOT modify without hardware validation.
  int get verifiedAddressInt => switch (this) {
    adau1466MasterVolumeL => 0x67,
    adau1466MasterVolumeR => 0x64,
  };

  String get verifiedAddressHex => switch (this) {
    adau1466MasterVolumeL => '0x67',
    adau1466MasterVolumeR => '0x64',
  };

  String get safetyNote => switch (this) {
    adau1466MasterVolumeL =>
      'Verified: ADAU1466 Master Volume L — address 0x67. Volatile write only.',
    adau1466MasterVolumeR =>
      'Verified: ADAU1466 Master Volume R — address 0x64. Volatile write only.',
  };

  String toJson() => name;
  static HardwareWriteTarget fromJson(String s) =>
      HardwareWriteTarget.values.firstWhere((e) => e.name == s,
          orElse: () => HardwareWriteTarget.adau1466MasterVolumeL);
}

// ── HardwareWriteRequest ──────────────────────────────────────────────────────

class HardwareWriteRequest {
  final String id;
  final HardwareWriteTarget target;
  final int addressInt;
  final String addressHex;
  final double valueDouble;       // 0.0–1.0 only
  final String fixedPointHex;     // 5.23 fixed-point hex for ADAU1466
  final List<int> rawBytes;       // MSB-first 4 bytes for USBi write
  final DateTime createdAt;
  final HardwareWritePermission permission;
  final bool dryRunOnly;
  final String warning;

  const HardwareWriteRequest({
    required this.id,
    required this.target,
    required this.addressInt,
    required this.addressHex,
    required this.valueDouble,
    required this.fixedPointHex,
    required this.rawBytes,
    required this.createdAt,
    required this.permission,
    required this.dryRunOnly,
    required this.warning,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'target': target.toJson(),
    'addressInt': addressInt,
    'addressHex': addressHex,
    'valueDouble': valueDouble,
    'fixedPointHex': fixedPointHex,
    'rawBytes': rawBytes,
    'createdAt': createdAt.toIso8601String(),
    'permission': permission.toJson(),
    'dryRunOnly': dryRunOnly,
    'warning': warning,
    // Safety: no EEPROM/Selfboot/SafeLoad fields ever emitted
    'safetyNote': 'Volatile write only. No EEPROM. No Selfboot. No SafeLoad.',
  };

  factory HardwareWriteRequest.fromJson(Map<String, dynamic> j) =>
      HardwareWriteRequest(
        id:           j['id'] as String,
        target:       HardwareWriteTarget.fromJson(j['target'] as String),
        addressInt:   j['addressInt'] as int,
        addressHex:   j['addressHex'] as String,
        valueDouble:  (j['valueDouble'] as num).toDouble(),
        fixedPointHex: j['fixedPointHex'] as String,
        rawBytes:     (j['rawBytes'] as List).cast<int>(),
        createdAt:    DateTime.parse(j['createdAt'] as String),
        permission:   HardwareWritePermission.fromJson(j['permission'] as String),
        dryRunOnly:   j['dryRunOnly'] as bool,
        warning:      j['warning'] as String,
      );
}

// ── HardwareWriteResult ───────────────────────────────────────────────────────

class HardwareWriteResult {
  final String requestId;
  final HardwareWriteStatus status;
  final DateTime attemptedAt;
  final String? errorMessage;
  final bool wasActualWrite;  // always false in Phase T — transport is placeholder
  final String safetyNote;

  const HardwareWriteResult({
    required this.requestId,
    required this.status,
    required this.attemptedAt,
    this.errorMessage,
    required this.wasActualWrite,
    required this.safetyNote,
  });

  Map<String, dynamic> toJson() => {
    'requestId':    requestId,
    'status':       status.toJson(),
    'attemptedAt':  attemptedAt.toIso8601String(),
    if (errorMessage != null) 'errorMessage': errorMessage,
    'wasActualWrite': wasActualWrite,
    'safetyNote':   safetyNote,
  };

  factory HardwareWriteResult.fromJson(Map<String, dynamic> j) =>
      HardwareWriteResult(
        requestId:      j['requestId'] as String,
        status:         HardwareWriteStatus.fromJson(j['status'] as String),
        attemptedAt:    DateTime.parse(j['attemptedAt'] as String),
        errorMessage:   j['errorMessage'] as String?,
        wasActualWrite: j['wasActualWrite'] as bool? ?? false,
        safetyNote:     j['safetyNote'] as String? ??
                        'No hardware write occurred.',
      );
}

// ── HardwareWriteLog ──────────────────────────────────────────────────────────

class HardwareWriteLog {
  final String id;
  final List<HardwareWriteRequest> requests;
  final HardwareWriteResult? result;
  final DateTime createdAt;
  final bool userConfirmed;
  final String sessionNote;

  const HardwareWriteLog({
    required this.id,
    required this.requests,
    this.result,
    required this.createdAt,
    required this.userConfirmed,
    required this.sessionNote,
  });

  HardwareWriteStatus get status =>
      result?.status ?? HardwareWriteStatus.notStarted;

  bool get wasActualWrite => result?.wasActualWrite ?? false;

  HardwareWriteLog copyWith({HardwareWriteResult? result}) => HardwareWriteLog(
    id:            id,
    requests:      requests,
    result:        result ?? this.result,
    createdAt:     createdAt,
    userConfirmed: userConfirmed,
    sessionNote:   sessionNote,
  );

  Map<String, dynamic> toJson() => {
    'id':            id,
    'requests':      requests.map((r) => r.toJson()).toList(),
    if (result != null) 'result': result!.toJson(),
    'createdAt':     createdAt.toIso8601String(),
    'userConfirmed': userConfirmed,
    'sessionNote':   sessionNote,
    'safetyNote':    'Volatile write only. No EEPROM. No Selfboot. No SafeLoad. '
                     'No hardware write until USBi transport is production-ready.',
  };

  factory HardwareWriteLog.fromJson(Map<String, dynamic> j) => HardwareWriteLog(
    id:            j['id'] as String,
    requests:      (j['requests'] as List)
                    .map((e) => HardwareWriteRequest.fromJson(
                        Map<String, dynamic>.from(e as Map)))
                    .toList(),
    result:        j['result'] == null
                    ? null
                    : HardwareWriteResult.fromJson(
                        Map<String, dynamic>.from(j['result'] as Map)),
    createdAt:     DateTime.parse(j['createdAt'] as String),
    userConfirmed: j['userConfirmed'] as bool? ?? false,
    sessionNote:   j['sessionNote'] as String? ?? '',
  );
}
