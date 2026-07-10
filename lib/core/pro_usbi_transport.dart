// ── TUNAI PRO Phase T2 — USBi Detection / Transport Readiness ────────────────
// Read-only detection layer for ADI USBi-class devices.
// This is a PLACEHOLDER with detection-only UI — no real USB I/O is implemented.
//
// ABSOLUTE RESTRICTIONS:
//   - Do NOT write to hardware.
//   - Do NOT send USB parameter write packets.
//   - Do NOT send control transfers.
//   - Do NOT claim write access.
//   - Do NOT fake successful hardware connection.
//   - Do NOT remove the isPlaceholder guard without expert sign-off.
//   - wasActualWrite must remain false everywhere.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.
//
// Phase T2: isPlaceholder == true, isWriteBackendEnabled == false.
// detectDevices() returns placeholder status — no native USB scan is implemented.
// When native macOS USB enumeration is added in a future phase, it will be
// implemented via MethodChannel and will only enumerate (not write).

// ── Enums ─────────────────────────────────────────────────────────────────────

enum UsbiBackendStatus {
  placeholder,
  detectionOnly,
  nativeAvailable,
  deviceDetected,
  driverMissing,
  accessDenied,
  unsupportedPlatform,
  error;

  String toJson() => name;

  static UsbiBackendStatus fromJson(String s) =>
      UsbiBackendStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => UsbiBackendStatus.placeholder,
      );

  String get label => switch (this) {
    UsbiBackendStatus.placeholder          => 'Placeholder',
    UsbiBackendStatus.detectionOnly        => 'Detection Only',
    UsbiBackendStatus.nativeAvailable      => 'Native Available',
    UsbiBackendStatus.deviceDetected       => 'Device Detected',
    UsbiBackendStatus.driverMissing        => 'Driver Missing',
    UsbiBackendStatus.accessDenied         => 'Access Denied',
    UsbiBackendStatus.unsupportedPlatform  => 'Unsupported Platform',
    UsbiBackendStatus.error                => 'Error',
  };

  bool get isUsable =>
      this == detectionOnly ||
      this == nativeAvailable ||
      this == deviceDetected;
}

enum UsbiAccessStatus {
  unknown,
  notDetected,
  detected,
  accessible,
  accessDenied,
  driverMissing,
  unsupported,
  placeholder;

  String toJson() => name;

  static UsbiAccessStatus fromJson(String s) =>
      UsbiAccessStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => UsbiAccessStatus.unknown,
      );

  String get label => switch (this) {
    UsbiAccessStatus.unknown      => 'Unknown',
    UsbiAccessStatus.notDetected  => 'Not Detected',
    UsbiAccessStatus.detected     => 'Detected',
    UsbiAccessStatus.accessible   => 'Accessible',
    UsbiAccessStatus.accessDenied => 'Access Denied',
    UsbiAccessStatus.driverMissing => 'Driver Missing',
    UsbiAccessStatus.unsupported  => 'Unsupported',
    UsbiAccessStatus.placeholder  => 'Placeholder',
  };
}

// ── UsbDeviceInfo ─────────────────────────────────────────────────────────────

// ADI Sigma Studio USBi VID
const int kAdiVendorId = 0x0456;

class UsbDeviceInfo {
  final String id;
  final int vid;
  final int pid;
  final String? productName;
  final String? manufacturer;
  final String? serialNumber;
  final String backendName;
  final UsbiAccessStatus accessStatus;
  final String? notes;

  const UsbDeviceInfo({
    required this.id,
    required this.vid,
    required this.pid,
    this.productName,
    this.manufacturer,
    this.serialNumber,
    required this.backendName,
    required this.accessStatus,
    this.notes,
  });

  String get vidHex => '0x${vid.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  String get pidHex => '0x${pid.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  /// True if VID matches ADI. Not sufficient alone — expert verification needed.
  bool get isLikelyUsbi => vid == kAdiVendorId;

  Map<String, dynamic> toJson() => {
    'id':           id,
    'vid':          vid,
    'pid':          pid,
    'vidHex':       vidHex,
    'pidHex':       pidHex,
    if (productName != null) 'productName': productName,
    if (manufacturer != null) 'manufacturer': manufacturer,
    if (serialNumber != null) 'serialNumber': serialNumber,
    'backendName':  backendName,
    'accessStatus': accessStatus.toJson(),
    'isLikelyUsbi': isLikelyUsbi,
    if (notes != null) 'notes': notes,
    // Safety: no write-capability fields in device info
  };

  factory UsbDeviceInfo.fromJson(Map<String, dynamic> j) => UsbDeviceInfo(
    id:           j['id'] as String,
    vid:          j['vid'] as int? ?? 0,
    pid:          j['pid'] as int? ?? 0,
    productName:  j['productName'] as String?,
    manufacturer: j['manufacturer'] as String?,
    serialNumber: j['serialNumber'] as String?,
    backendName:  j['backendName'] as String? ?? 'unknown',
    accessStatus: UsbiAccessStatus.fromJson(j['accessStatus'] as String? ?? 'unknown'),
    notes:        j['notes'] as String?,
  );
}

// ── ProUsbiTransport ──────────────────────────────────────────────────────────

class ProUsbiTransport {
  // ── Phase T/T2 safety constants ──────────────────────────────────────────

  /// Always true in Phase T/T2. Set to false only after expert hardware validation.
  static const bool isPlaceholder = true;

  /// True while USB backend only enumerates devices but cannot write.
  static const bool isDetectionOnly = true;

  /// False in all phases until write backend is production-ready and expert-signed.
  static const bool isWriteBackendEnabled = false;

  static const String placeholderReason =
      'USBi transport is a placeholder in Phase T2. '
      'No real USB I/O is available. '
      'Hardware write button remains disabled until the transport is production-ready.';

  static const String detectionNote =
      'Detection only. No USB write packets are sent. '
      'No control transfers are issued. '
      'Native USBi detection backend not implemented yet.';

  // ── Mutable state ─────────────────────────────────────────────────────────

  List<UsbDeviceInfo> _detectedDevices = const [];
  String? _selectedDeviceId;
  UsbiBackendStatus _backendStatus = UsbiBackendStatus.placeholder;
  String? _lastDetectionMessage;
  DateTime? _lastCheckedAt;
  String? _lastError;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isConnected => false; // never true while isPlaceholder
  bool get isOpened    => false;
  String? get lastError => _lastError;

  List<UsbDeviceInfo> get detectedDevices => List.unmodifiable(_detectedDevices);

  UsbDeviceInfo? get selectedDevice => _selectedDeviceId == null
      ? null
      : _detectedDevices.where((d) => d.id == _selectedDeviceId).firstOrNull;

  UsbiBackendStatus get backendStatus => _backendStatus;
  String? get lastDetectionMessage => _lastDetectionMessage;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  int get likelyUsbiCount =>
      _detectedDevices.where((d) => d.isLikelyUsbi).length;

  // ── Detection (read-only) ─────────────────────────────────────────────────

  /// Detects USB devices without writing or opening any device for write access.
  ///
  /// Phase T2: Native detection is not implemented. Returns placeholder status.
  /// No USB write packets are sent. No control transfers. No device claimed.
  Future<List<UsbDeviceInfo>> detectDevices() async {
    _lastCheckedAt = DateTime.now();
    _lastError = null;

    // Phase T2: Native macOS USB enumeration via MethodChannel is not
    // implemented yet. We return an empty list with a clear status message.
    // Do NOT simulate a detected device — this would mislead the operator.
    _backendStatus = UsbiBackendStatus.placeholder;
    _lastDetectionMessage =
        'Native USBi detection backend not implemented yet. '
        'Install Sigma Studio USBi driver and connect the ADI USBi device '
        'to enable detection in a future phase.';
    _detectedDevices = const [];
    return const [];
  }

  /// Selects a previously detected device by id.
  /// Does NOT open the device for writing.
  void selectDevice(String deviceId) {
    if (_detectedDevices.any((d) => d.id == deviceId)) {
      _selectedDeviceId = deviceId;
    }
  }

  void clearSelection() => _selectedDeviceId = null;

  // ── Legacy open/close (placeholder) ──────────────────────────────────────

  Future<bool> open() async {
    _lastError = placeholderReason;
    return false;
  }

  Future<void> close() async {}

  // ── Write (permanently blocked in Phase T2) ───────────────────────────────

  /// Returns a failed outcome. Write is NOT enabled in Phase T2.
  /// wasActualWrite is always false.
  Future<UsbiWriteOutcome> writeParameter(int addressInt, List<int> bytes) async =>
      UsbiWriteOutcome(
        success: false,
        address: addressInt,
        bytesAttempted: bytes,
        errorMessage: isPlaceholder
            ? placeholderReason
            : 'USBi write backend is not enabled in Phase T2. '
              'Detection does not imply write permission. '
              'Actual write remains disabled.',
        wasActualWrite: false,       // NEVER true in Phase T2
      );

  // ── Status ────────────────────────────────────────────────────────────────

  Map<String, dynamic> toStatusJson() => {
    'isPlaceholder':          isPlaceholder,
    'isDetectionOnly':        isDetectionOnly,
    'isWriteBackendEnabled':  isWriteBackendEnabled,
    'isConnected':            isConnected,
    'backendStatus':          _backendStatus.toJson(),
    'detectedCount':          _detectedDevices.length,
    'likelyUsbiCount':        likelyUsbiCount,
    'selectedDeviceId':       _selectedDeviceId,
    if (_lastDetectionMessage != null)
      'lastDetectionMessage': _lastDetectionMessage,
    if (_lastCheckedAt != null)
      'lastCheckedAt':        _lastCheckedAt!.toIso8601String(),
    'placeholderReason':      placeholderReason,
    'safetyNote':             'No hardware write occurs. Detection only.',
  };
}

// ── Result type ───────────────────────────────────────────────────────────────

class UsbiWriteOutcome {
  final bool success;
  final int address;
  final List<int> bytesAttempted;
  final String? errorMessage;
  final bool wasActualWrite;  // always false in Phase T / T2

  const UsbiWriteOutcome({
    required this.success,
    required this.address,
    required this.bytesAttempted,
    this.errorMessage,
    required this.wasActualWrite,
  });

  Map<String, dynamic> toJson() => {
    'success':         success,
    'address':         address,
    'bytesAttempted':  bytesAttempted,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'wasActualWrite':  wasActualWrite,
    'safetyNote':      'Volatile write only. No EEPROM. No Selfboot. No SafeLoad.',
  };
}
