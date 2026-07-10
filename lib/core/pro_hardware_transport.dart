// ── TUNAI PRO Phase T2 Revised — Multi-Transport Abstraction ─────────────────
// Transport selection and readiness layer for BLE / USBi / ICP5 / Simulation.
// Phase T2: detection-only placeholders. No write backend enabled.
//
// ABSOLUTE RESTRICTIONS:
//   - Do NOT write to hardware.
//   - Do NOT send USB, BLE, or ICP5 packets.
//   - Do NOT claim write access.
//   - isWriteEnabled must remain false in Phase T2.
//   - wasActualWrite must remain false everywhere.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

// ── HardwareTransportBackend ──────────────────────────────────────────────────

enum HardwareTransportBackend {
  none,
  bleMacos,
  usbiWindowsTemporary,
  icp5,
  simulation,
  placeholder;

  String toJson() => name;

  static HardwareTransportBackend fromJson(String s) =>
      HardwareTransportBackend.values.firstWhere(
        (e) => e.name == s,
        orElse: () => HardwareTransportBackend.none,
      );

  String get label => switch (this) {
    HardwareTransportBackend.none                 => 'None',
    HardwareTransportBackend.bleMacos             => 'BLE / macOS',
    HardwareTransportBackend.usbiWindowsTemporary => 'USBi (Windows Temporary)',
    HardwareTransportBackend.icp5                 => 'ICP5 (Final Target)',
    HardwareTransportBackend.simulation           => 'Simulation',
    HardwareTransportBackend.placeholder          => 'Placeholder',
  };

  String get platformHint => switch (this) {
    HardwareTransportBackend.bleMacos             => 'macOS',
    HardwareTransportBackend.usbiWindowsTemporary => 'Windows (temporary)',
    HardwareTransportBackend.icp5                 => 'Any (final target)',
    HardwareTransportBackend.simulation           => 'Any',
    _                                             => 'Unknown',
  };

  String get descriptionNote => switch (this) {
    HardwareTransportBackend.bleMacos =>
        'BLE path for macOS. Hardware write disabled.',
    HardwareTransportBackend.usbiWindowsTemporary =>
        'USBi temporary engineering path. Use only for controlled validation.',
    HardwareTransportBackend.icp5 =>
        'ICP5 final transport target. Backend pending.',
    HardwareTransportBackend.simulation =>
        'Simulation mode. No hardware. Dry-run only.',
    _ => 'Transport not configured.',
  };

  bool get isTemporary => this == usbiWindowsTemporary;
  bool get isFinalTarget => this == icp5;
  bool get isSimulation => this == simulation;
}

// ── TransportReadinessStatus ──────────────────────────────────────────────────

enum TransportReadinessStatus {
  notConfigured,
  placeholder,
  detectionOnly,
  detected,
  connected,
  accessDenied,
  driverMissing,
  unsupportedPlatform,
  writeDisabled,
  error;

  String toJson() => name;

  static TransportReadinessStatus fromJson(String s) =>
      TransportReadinessStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => TransportReadinessStatus.notConfigured,
      );

  String get label => switch (this) {
    TransportReadinessStatus.notConfigured      => 'Not Configured',
    TransportReadinessStatus.placeholder        => 'Placeholder',
    TransportReadinessStatus.detectionOnly      => 'Detection Only',
    TransportReadinessStatus.detected           => 'Detected',
    TransportReadinessStatus.connected          => 'Connected',
    TransportReadinessStatus.accessDenied       => 'Access Denied',
    TransportReadinessStatus.driverMissing      => 'Driver Missing',
    TransportReadinessStatus.unsupportedPlatform => 'Unsupported Platform',
    TransportReadinessStatus.writeDisabled      => 'Write Disabled',
    TransportReadinessStatus.error              => 'Error',
  };

  bool get isWarning =>
      this == accessDenied ||
      this == driverMissing ||
      this == unsupportedPlatform ||
      this == error;
}

// ── TransportWriteCapability ──────────────────────────────────────────────────

enum TransportWriteCapability {
  none,
  dryRunOnly,
  controlledMasterVolumeOnly,
  safeloadCapableFuture,
  fullWriteFuture;

  String toJson() => name;

  static TransportWriteCapability fromJson(String s) =>
      TransportWriteCapability.values.firstWhere(
        (e) => e.name == s,
        orElse: () => TransportWriteCapability.none,
      );

  String get label => switch (this) {
    TransportWriteCapability.none                    => 'None',
    TransportWriteCapability.dryRunOnly              => 'Dry-Run Only',
    TransportWriteCapability.controlledMasterVolumeOnly =>
        'Controlled Master Volume Only',
    TransportWriteCapability.safeloadCapableFuture   => 'SafeLoad (Future)',
    TransportWriteCapability.fullWriteFuture         => 'Full Write (Future)',
  };
}

// ── HardwareTransportInfo ─────────────────────────────────────────────────────

class HardwareTransportInfo {
  final String id;
  final HardwareTransportBackend backend;
  final String displayName;
  final String platformHint;
  final TransportReadinessStatus readinessStatus;
  final TransportWriteCapability writeCapability;

  /// Always false in Phase T2. Must not be set true without expert sign-off.
  final bool isWriteEnabled;

  final bool isPlaceholder;
  final bool isDetectionOnly;
  final String? deviceName;
  final String? vid;
  final String? pid;
  final String? bluetoothId;
  final String? serviceUuid;
  final String? characteristicUuid;
  final String? notes;
  final DateTime? lastCheckedAt;

  const HardwareTransportInfo({
    required this.id,
    required this.backend,
    required this.displayName,
    required this.platformHint,
    required this.readinessStatus,
    required this.writeCapability,
    required this.isPlaceholder,
    required this.isDetectionOnly,
    // Phase T2: isWriteEnabled is always false — not a parameter
    this.deviceName,
    this.vid,
    this.pid,
    this.bluetoothId,
    this.serviceUuid,
    this.characteristicUuid,
    this.notes,
    this.lastCheckedAt,
  }) : isWriteEnabled = false; // NEVER true in Phase T2

  HardwareTransportInfo copyWith({
    TransportReadinessStatus? readinessStatus,
    TransportWriteCapability? writeCapability,
    String? deviceName,
    String? vid,
    String? pid,
    String? bluetoothId,
    String? serviceUuid,
    String? characteristicUuid,
    String? notes,
    DateTime? lastCheckedAt,
  }) => HardwareTransportInfo(
    id: id,
    backend: backend,
    displayName: displayName,
    platformHint: platformHint,
    readinessStatus: readinessStatus ?? this.readinessStatus,
    writeCapability: writeCapability ?? this.writeCapability,
    isPlaceholder: isPlaceholder,
    isDetectionOnly: isDetectionOnly,
    deviceName: deviceName ?? this.deviceName,
    vid: vid ?? this.vid,
    pid: pid ?? this.pid,
    bluetoothId: bluetoothId ?? this.bluetoothId,
    serviceUuid: serviceUuid ?? this.serviceUuid,
    characteristicUuid: characteristicUuid ?? this.characteristicUuid,
    notes: notes ?? this.notes,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
  );

  Map<String, dynamic> toJson() => {
    'id':               id,
    'backend':          backend.toJson(),
    'displayName':      displayName,
    'platformHint':     platformHint,
    'readinessStatus':  readinessStatus.toJson(),
    'writeCapability':  writeCapability.toJson(),
    'isWriteEnabled':   isWriteEnabled,   // always false
    'isPlaceholder':    isPlaceholder,
    'isDetectionOnly':  isDetectionOnly,
    if (deviceName != null)         'deviceName':         deviceName,
    if (vid != null)                'vid':                vid,
    if (pid != null)                'pid':                pid,
    if (bluetoothId != null)        'bluetoothId':        bluetoothId,
    if (serviceUuid != null)        'serviceUuid':        serviceUuid,
    if (characteristicUuid != null) 'characteristicUuid': characteristicUuid,
    if (notes != null)              'notes':              notes,
    if (lastCheckedAt != null)
      'lastCheckedAt': lastCheckedAt!.toIso8601String(),
    // Safety: no write packet fields, no address write fields
  };

  factory HardwareTransportInfo.fromJson(Map<String, dynamic> j) =>
      HardwareTransportInfo(
        id: j['id'] as String? ?? '',
        backend: HardwareTransportBackend.fromJson(
            j['backend'] as String? ?? 'placeholder'),
        displayName: j['displayName'] as String? ?? '',
        platformHint: j['platformHint'] as String? ?? '',
        readinessStatus: TransportReadinessStatus.fromJson(
            j['readinessStatus'] as String? ?? 'placeholder'),
        writeCapability: TransportWriteCapability.fromJson(
            j['writeCapability'] as String? ?? 'none'),
        isPlaceholder: j['isPlaceholder'] as bool? ?? true,
        isDetectionOnly: j['isDetectionOnly'] as bool? ?? true,
        deviceName:         j['deviceName'] as String?,
        vid:                j['vid'] as String?,
        pid:                j['pid'] as String?,
        bluetoothId:        j['bluetoothId'] as String?,
        serviceUuid:        j['serviceUuid'] as String?,
        characteristicUuid: j['characteristicUuid'] as String?,
        notes:              j['notes'] as String?,
        lastCheckedAt: j['lastCheckedAt'] != null
            ? DateTime.tryParse(j['lastCheckedAt'] as String)
            : null,
      );

  // ── Default transport catalogue (Phase T2 placeholders) ──────────────────

  static HardwareTransportInfo get defaultBleMacos => const HardwareTransportInfo(
    id: 'ble_macos',
    backend: HardwareTransportBackend.bleMacos,
    displayName: 'BLE / macOS Bluetooth',
    platformHint: 'macOS',
    readinessStatus: TransportReadinessStatus.placeholder,
    writeCapability: TransportWriteCapability.dryRunOnly,
    isPlaceholder: true,
    isDetectionOnly: true,
    notes: 'macOS BLE transport planned. Detection/write backend not enabled in this build.',
  );

  static HardwareTransportInfo get defaultUsbiWindowsTemporary =>
      const HardwareTransportInfo(
    id: 'usbi_windows_temporary',
    backend: HardwareTransportBackend.usbiWindowsTemporary,
    displayName: 'USBi — Windows Temporary Engineering',
    platformHint: 'Windows (temporary)',
    readinessStatus: TransportReadinessStatus.placeholder,
    writeCapability: TransportWriteCapability.dryRunOnly,
    isPlaceholder: true,
    isDetectionOnly: true,
    notes: 'USBi temporary engineering transport. Label clearly as temporary.',
  );

  static HardwareTransportInfo get defaultIcp5 => const HardwareTransportInfo(
    id: 'icp5',
    backend: HardwareTransportBackend.icp5,
    displayName: 'ICP5 — Final Transport Target',
    platformHint: 'Any (final target)',
    readinessStatus: TransportReadinessStatus.placeholder,
    writeCapability: TransportWriteCapability.dryRunOnly,
    isPlaceholder: true,
    isDetectionOnly: true,
    notes: 'ICP5 final transport target. Backend pending.',
  );

  static HardwareTransportInfo get defaultSimulation => const HardwareTransportInfo(
    id: 'simulation',
    backend: HardwareTransportBackend.simulation,
    displayName: 'Simulation',
    platformHint: 'Any',
    readinessStatus: TransportReadinessStatus.detectionOnly,
    writeCapability: TransportWriteCapability.dryRunOnly,
    isPlaceholder: false,
    isDetectionOnly: true,
    notes: 'Simulation mode. No hardware. Dry-run only.',
  );

  static List<HardwareTransportInfo> get defaultAvailableTransports => [
    defaultBleMacos,
    defaultUsbiWindowsTemporary,
    defaultIcp5,
    defaultSimulation,
  ];
}
