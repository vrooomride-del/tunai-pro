// ── TUNAI PRO Phase T — USBi Transport Placeholder ───────────────────────────
// Guarded interface for USBi hardware communication.
// This is a PLACEHOLDER — no real USB I/O is implemented.
//
// ABSOLUTE RESTRICTIONS:
//   - Do NOT fake successful hardware writes. Return failure when not connected.
//   - Do NOT implement real USB I/O until the platform channel is production-ready.
//   - Do NOT remove the isPlaceholder guard without expert sign-off.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.
//
// When real USBi support is added in a future phase, a platform channel (MethodChannel)
// will be implemented here and isPlaceholder will become false only after
// driver installation and hardware validation are confirmed.

// Reason this transport does NOT write:
// isPlaceholder == true → all write calls return failure immediately.
// The UI uses this flag to keep the Write button disabled with a clear explanation.

class ProUsbiTransport {
  // Always true in Phase T. Set to false only after hardware validation.
  static const bool isPlaceholder = true;

  static const String placeholderReason =
      'USBi transport is a placeholder in Phase T. '
      'No real USB I/O is available. '
      'Hardware write button remains disabled until the transport is production-ready.';

  bool _connected = false;
  bool _opened = false;
  String? _lastError;

  bool get isConnected => _connected && !isPlaceholder;
  bool get isOpened    => _opened && !isPlaceholder;
  String? get lastError => _lastError;

  // Returns list of detected device paths.
  // Phase T: always returns empty — no real USB scan.
  Future<List<String>> detectDevices() async {
    _lastError = placeholderReason;
    return [];
  }

  // Opens the transport channel.
  // Phase T: always fails — placeholder guard.
  Future<bool> open() async {
    _lastError = placeholderReason;
    _connected = false;
    _opened = false;
    return false;
  }

  // Closes the transport channel.
  Future<void> close() async {
    _connected = false;
    _opened = false;
  }

  // Writes a 4-byte parameter to the given address.
  // Phase T: always returns failure — placeholder guard.
  // addressInt: verified hardware address (e.g., 0x67 or 0x64)
  // bytes: MSB-first 4-byte fixed-point value
  Future<UsbiWriteOutcome> writeParameter(int addressInt, List<int> bytes) async {
    if (isPlaceholder) {
      return UsbiWriteOutcome(
        success: false,
        address: addressInt,
        bytesAttempted: bytes,
        errorMessage: placeholderReason,
        wasActualWrite: false,
      );
    }
    // Real implementation goes here in a future phase.
    // This branch is unreachable while isPlaceholder == true.
    return UsbiWriteOutcome(
      success: false,
      address: addressInt,
      bytesAttempted: bytes,
      errorMessage: 'Transport not initialized.',
      wasActualWrite: false,
    );
  }

  Map<String, dynamic> toStatusJson() => {
    'isPlaceholder':      isPlaceholder,
    'isConnected':        isConnected,
    'placeholderReason':  placeholderReason,
    'safetyNote':         'No hardware write occurs while isPlaceholder is true.',
  };
}

// ── Result type ───────────────────────────────────────────────────────────────

class UsbiWriteOutcome {
  final bool success;
  final int address;
  final List<int> bytesAttempted;
  final String? errorMessage;
  final bool wasActualWrite;  // always false in Phase T

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
