// ── TUNAI PRO — ADAU1466 Sigma Candidate Model ────────────────────────────────
// Mutable candidate for hardware verification console.
// Each candidate represents one DSP address from the Sigma export.
//
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM. No Selfboot. No WriteAll. No SafeLoad until validated.
//   - validationStatus mutated only by explicit operator action.
//   - wasActualWrite = true only if native backend was actually called.
//   - USBi is TEMPORARY. ICP5 is the final target.

// ── Enums ─────────────────────────────────────────────────────────────────────

enum CandidateKind {
  masterVolume,
  gain,
  mute,
  delay,
  peq,
  crossover,
  outputRouting,
  inputRouting,
  safeload,
  protection,
  polarity,
  unknown;

  String get label => switch (this) {
    CandidateKind.masterVolume  => 'Master Volume',
    CandidateKind.gain          => 'Gain',
    CandidateKind.mute          => 'Mute',
    CandidateKind.delay         => 'Delay',
    CandidateKind.peq           => 'PEQ',
    CandidateKind.crossover     => 'Crossover',
    CandidateKind.outputRouting => 'Output Routing',
    CandidateKind.inputRouting  => 'Input Routing',
    CandidateKind.safeload      => 'SafeLoad',
    CandidateKind.protection    => 'Protection',
    CandidateKind.polarity      => 'Polarity',
    CandidateKind.unknown       => 'Unknown',
  };

  String toJson() => name;
  static CandidateKind fromJson(String s) =>
      CandidateKind.values.firstWhere((e) => e.name == s,
          orElse: () => CandidateKind.unknown);
}

enum CandidateValidationStatus {
  unknown,
  candidate,
  passAck,
  needsMeasurement,
  verified,
  rejected,
  fail,
  blocked,
  staleRevalidationRequired;

  String get label => switch (this) {
    CandidateValidationStatus.unknown                    => 'Unknown',
    CandidateValidationStatus.candidate                  => 'Candidate',
    CandidateValidationStatus.passAck                    => 'PASS_ACK',
    CandidateValidationStatus.needsMeasurement           => 'Needs Measurement',
    CandidateValidationStatus.verified                   => 'Verified',
    CandidateValidationStatus.rejected                   => 'Rejected',
    CandidateValidationStatus.fail                       => 'FAIL',
    CandidateValidationStatus.blocked                    => 'BLOCKED',
    CandidateValidationStatus.staleRevalidationRequired  => 'Stale/Revalidation Required',
  };

  String toJson() => name;
  static CandidateValidationStatus fromJson(String s) =>
      CandidateValidationStatus.values.firstWhere((e) => e.name == s,
          orElse: () => CandidateValidationStatus.unknown);
}

enum CandidateRisk {
  low,
  medium,
  high,
  forbidden;

  String get label => switch (this) {
    CandidateRisk.low       => 'Low',
    CandidateRisk.medium    => 'Medium',
    CandidateRisk.high      => 'High',
    CandidateRisk.forbidden => 'FORBIDDEN',
  };

  String toJson() => name;
  static CandidateRisk fromJson(String s) =>
      CandidateRisk.values.firstWhere((e) => e.name == s,
          orElse: () => CandidateRisk.medium);
}

enum AddressRegion {
  parameterRam,
  safeloadArea,
  programMemory,
  systemControl,
  eepromOrSelfboot,
  unknown;

  String get label => switch (this) {
    AddressRegion.parameterRam     => 'Parameter RAM',
    AddressRegion.safeloadArea     => 'SafeLoad Area',
    AddressRegion.programMemory    => 'Program Memory',
    AddressRegion.systemControl    => 'System Control',
    AddressRegion.eepromOrSelfboot => 'EEPROM/Selfboot',
    AddressRegion.unknown          => 'Unknown',
  };

  String toJson() => name;
  static AddressRegion fromJson(String s) =>
      AddressRegion.values.firstWhere((e) => e.name == s,
          orElse: () => AddressRegion.unknown);
}

enum MeasurementMethod {
  voltage,
  scope,
  audioInterface,
  acousticMic,
  subjectiveCheck,
  notMeasured;

  String toJson() => name;
  static MeasurementMethod fromJson(String s) =>
      MeasurementMethod.values.firstWhere((e) => e.name == s,
          orElse: () => MeasurementMethod.notMeasured);
}

enum TestProfile {
  linear824,
  muteA,
  muteB,
  delayStep,
  raw32bit,
  restoreOnly;

  String get label => switch (this) {
    TestProfile.linear824   => 'Linear 8.24',
    TestProfile.muteA       => 'Mute A (test=0x01000000)',
    TestProfile.muteB       => 'Mute B (test=0x00000000)',
    TestProfile.delayStep   => 'Delay Step',
    TestProfile.raw32bit    => 'Raw 32-bit',
    TestProfile.restoreOnly => 'Restore Only',
  };

  String toJson() => name;
  static TestProfile fromJson(String s) =>
      TestProfile.values.firstWhere((e) => e.name == s,
          orElse: () => TestProfile.raw32bit);
}

// ── SigmaExportSignature ──────────────────────────────────────────────────────

class SigmaExportSignature {
  final String sourceLabel;
  final int rowCount;
  final String checksum;
  final DateTime? timestamp;

  const SigmaExportSignature({
    required this.sourceLabel,
    required this.rowCount,
    required this.checksum,
    this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'sourceLabel': sourceLabel,
    'rowCount':    rowCount,
    'checksum':    checksum,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
  };

  factory SigmaExportSignature.fromJson(Map<String, dynamic> j) =>
      SigmaExportSignature(
        sourceLabel: j['sourceLabel'] as String? ?? '',
        rowCount:    j['rowCount']    as int?    ?? 0,
        checksum:    j['checksum']    as String? ?? '',
        timestamp:   j['timestamp'] != null
            ? DateTime.tryParse(j['timestamp'] as String)
            : null,
      );
}

// ── SigmaWriteStepResult ──────────────────────────────────────────────────────

class SigmaWriteStepResult {
  final int addressInt;
  final String addressHex;
  final String label;
  final int testValue;
  final int restoreValue;
  final String testBodyHex;
  final String restoreBodyHex;
  final String? testAckBytes;
  final String? restoreAckBytes;
  final bool testWasActualWrite;
  final bool restoreWasActualWrite;
  final bool testAckOk;
  final bool restoreAckOk;
  final String? error;

  const SigmaWriteStepResult({
    required this.addressInt,
    required this.addressHex,
    required this.label,
    required this.testValue,
    required this.restoreValue,
    required this.testBodyHex,
    required this.restoreBodyHex,
    this.testAckBytes,
    this.restoreAckBytes,
    required this.testWasActualWrite,
    required this.restoreWasActualWrite,
    required this.testAckOk,
    required this.restoreAckOk,
    this.error,
  });
}

// ── Adau1466SigmaCandidate ────────────────────────────────────────────────────

class Adau1466SigmaCandidate {
  // Identity
  final String id;
  final int addressInt;
  final String addressHex;

  // Source metadata
  final String sourceType;
  final String sourceFile;

  // From CSV columns
  final String rawName;       // col 10 parameter_name
  final String logicalName;   // col 11
  final String blockGroup;    // col 2
  final String parameterId;   // col 0
  final String coefficient;   // col 8
  final String bandOrStage;   // col 7
  final CandidateKind kind;
  final String guessedChannel; // col 3
  final String dataFormatHint; // col 14
  final String sigmaOutputCell; // col 4
  final String physicalOutput;  // col 5

  // Derived
  final CandidateRisk riskLevel;
  final AddressRegion addressRegion;
  final String exportDefaultHex;  // col 19 current_data_word
  final bool safeloadRequired;    // col 16
  final bool isDuplicate;

  // Mutable validation state
  CandidateValidationStatus validationStatus;
  String? lastTestValueHex;
  String? lastRestoreValueHex;
  String? lastTestBodyHex;
  String? lastRestoreBodyHex;
  String? lastAckBytes;
  String? lastRestoreAckBytes;
  bool wasActualWrite;
  double? measurementBefore;
  double? measurementAfter;
  MeasurementMethod? measurementMethod;
  String? measurementNote;
  String? operatorNote;
  String? blockedReason;
  DateTime? timestamp;

  Adau1466SigmaCandidate({
    required this.id,
    required this.addressInt,
    required this.addressHex,
    required this.sourceType,
    required this.sourceFile,
    required this.rawName,
    required this.logicalName,
    required this.blockGroup,
    required this.parameterId,
    required this.coefficient,
    required this.bandOrStage,
    required this.kind,
    required this.guessedChannel,
    required this.dataFormatHint,
    required this.sigmaOutputCell,
    required this.physicalOutput,
    required this.riskLevel,
    required this.addressRegion,
    required this.exportDefaultHex,
    required this.safeloadRequired,
    this.isDuplicate = false,
    this.validationStatus = CandidateValidationStatus.candidate,
    this.lastTestValueHex,
    this.lastRestoreValueHex,
    this.lastTestBodyHex,
    this.lastRestoreBodyHex,
    this.lastAckBytes,
    this.lastRestoreAckBytes,
    this.wasActualWrite = false,
    this.measurementBefore,
    this.measurementAfter,
    this.measurementMethod,
    this.measurementNote,
    this.operatorNote,
    this.blockedReason,
    this.timestamp,
  });

  Adau1466SigmaCandidate copyWith({
    CandidateValidationStatus? validationStatus,
    String? lastTestValueHex,
    String? lastRestoreValueHex,
    String? lastTestBodyHex,
    String? lastRestoreBodyHex,
    String? lastAckBytes,
    String? lastRestoreAckBytes,
    bool? wasActualWrite,
    double? measurementBefore,
    double? measurementAfter,
    MeasurementMethod? measurementMethod,
    String? measurementNote,
    String? operatorNote,
    String? blockedReason,
    DateTime? timestamp,
  }) => Adau1466SigmaCandidate(
    id:                id,
    addressInt:        addressInt,
    addressHex:        addressHex,
    sourceType:        sourceType,
    sourceFile:        sourceFile,
    rawName:           rawName,
    logicalName:       logicalName,
    blockGroup:        blockGroup,
    parameterId:       parameterId,
    coefficient:       coefficient,
    bandOrStage:       bandOrStage,
    kind:              kind,
    guessedChannel:    guessedChannel,
    dataFormatHint:    dataFormatHint,
    sigmaOutputCell:   sigmaOutputCell,
    physicalOutput:    physicalOutput,
    riskLevel:         riskLevel,
    addressRegion:     addressRegion,
    exportDefaultHex:  exportDefaultHex,
    safeloadRequired:  safeloadRequired,
    isDuplicate:       isDuplicate,
    validationStatus:  validationStatus ?? this.validationStatus,
    lastTestValueHex:  lastTestValueHex ?? this.lastTestValueHex,
    lastRestoreValueHex: lastRestoreValueHex ?? this.lastRestoreValueHex,
    lastTestBodyHex:   lastTestBodyHex ?? this.lastTestBodyHex,
    lastRestoreBodyHex: lastRestoreBodyHex ?? this.lastRestoreBodyHex,
    lastAckBytes:      lastAckBytes ?? this.lastAckBytes,
    lastRestoreAckBytes: lastRestoreAckBytes ?? this.lastRestoreAckBytes,
    wasActualWrite:    wasActualWrite ?? this.wasActualWrite,
    measurementBefore: measurementBefore ?? this.measurementBefore,
    measurementAfter:  measurementAfter ?? this.measurementAfter,
    measurementMethod: measurementMethod ?? this.measurementMethod,
    measurementNote:   measurementNote ?? this.measurementNote,
    operatorNote:      operatorNote ?? this.operatorNote,
    blockedReason:     blockedReason ?? this.blockedReason,
    timestamp:         timestamp ?? this.timestamp,
  );

  Map<String, dynamic> toJson() => {
    'id':                id,
    'addressInt':        addressInt,
    'addressHex':        addressHex,
    'sourceType':        sourceType,
    'sourceFile':        sourceFile,
    'rawName':           rawName,
    'logicalName':       logicalName,
    'blockGroup':        blockGroup,
    'parameterId':       parameterId,
    'coefficient':       coefficient,
    'bandOrStage':       bandOrStage,
    'kind':              kind.toJson(),
    'guessedChannel':    guessedChannel,
    'dataFormatHint':    dataFormatHint,
    'sigmaOutputCell':   sigmaOutputCell,
    'physicalOutput':    physicalOutput,
    'riskLevel':         riskLevel.toJson(),
    'addressRegion':     addressRegion.toJson(),
    'exportDefaultHex':  exportDefaultHex,
    'safeloadRequired':  safeloadRequired,
    'isDuplicate':       isDuplicate,
    'validationStatus':  validationStatus.toJson(),
    if (lastTestValueHex != null)   'lastTestValueHex':    lastTestValueHex,
    if (lastRestoreValueHex != null) 'lastRestoreValueHex': lastRestoreValueHex,
    if (lastTestBodyHex != null)    'lastTestBodyHex':     lastTestBodyHex,
    if (lastRestoreBodyHex != null) 'lastRestoreBodyHex':  lastRestoreBodyHex,
    if (lastAckBytes != null)       'lastAckBytes':        lastAckBytes,
    if (lastRestoreAckBytes != null)'lastRestoreAckBytes':  lastRestoreAckBytes,
    'wasActualWrite':    wasActualWrite,
    if (measurementBefore != null)  'measurementBefore':  measurementBefore,
    if (measurementAfter != null)   'measurementAfter':   measurementAfter,
    if (measurementMethod != null)  'measurementMethod':  measurementMethod!.toJson(),
    if (measurementNote != null)    'measurementNote':    measurementNote,
    if (operatorNote != null)       'operatorNote':       operatorNote,
    if (blockedReason != null)      'blockedReason':      blockedReason,
    if (timestamp != null)          'timestamp':          timestamp!.toIso8601String(),
  };

  factory Adau1466SigmaCandidate.fromJson(Map<String, dynamic> j) =>
      Adau1466SigmaCandidate(
        id:               j['id']              as String? ?? '',
        addressInt:       j['addressInt']       as int?    ?? 0,
        addressHex:       j['addressHex']       as String? ?? '0x0000',
        sourceType:       j['sourceType']       as String? ?? '',
        sourceFile:       j['sourceFile']       as String? ?? '',
        rawName:          j['rawName']          as String? ?? '',
        logicalName:      j['logicalName']      as String? ?? '',
        blockGroup:       j['blockGroup']       as String? ?? '',
        parameterId:      j['parameterId']      as String? ?? '',
        coefficient:      j['coefficient']      as String? ?? '',
        bandOrStage:      j['bandOrStage']      as String? ?? '',
        kind:             CandidateKind.fromJson(j['kind'] as String? ?? 'unknown'),
        guessedChannel:   j['guessedChannel']   as String? ?? '',
        dataFormatHint:   j['dataFormatHint']   as String? ?? '',
        sigmaOutputCell:  j['sigmaOutputCell']  as String? ?? '',
        physicalOutput:   j['physicalOutput']   as String? ?? '',
        riskLevel:        CandidateRisk.fromJson(j['riskLevel'] as String? ?? 'medium'),
        addressRegion:    AddressRegion.fromJson(j['addressRegion'] as String? ?? 'unknown'),
        exportDefaultHex: j['exportDefaultHex'] as String? ?? '',
        safeloadRequired: j['safeloadRequired'] as bool?   ?? false,
        isDuplicate:      j['isDuplicate']       as bool?   ?? false,
        validationStatus: CandidateValidationStatus.fromJson(
            j['validationStatus'] as String? ?? 'candidate'),
        lastTestValueHex:    j['lastTestValueHex']    as String?,
        lastRestoreValueHex: j['lastRestoreValueHex'] as String?,
        lastTestBodyHex:     j['lastTestBodyHex']     as String?,
        lastRestoreBodyHex:  j['lastRestoreBodyHex']  as String?,
        lastAckBytes:        j['lastAckBytes']        as String?,
        lastRestoreAckBytes: j['lastRestoreAckBytes'] as String?,
        wasActualWrite:      j['wasActualWrite']      as bool?   ?? false,
        measurementBefore:   (j['measurementBefore']  as num?)?.toDouble(),
        measurementAfter:    (j['measurementAfter']   as num?)?.toDouble(),
        measurementMethod:   j['measurementMethod'] != null
            ? MeasurementMethod.fromJson(j['measurementMethod'] as String)
            : null,
        measurementNote:  j['measurementNote']  as String?,
        operatorNote:     j['operatorNote']     as String?,
        blockedReason:    j['blockedReason']    as String?,
        timestamp:        j['timestamp'] != null
            ? DateTime.tryParse(j['timestamp'] as String)
            : null,
      );
}
