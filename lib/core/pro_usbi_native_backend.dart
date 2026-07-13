// ── TUNAI PRO Phase T4A — USBi Native Backend Interface ──────────────────────
// Abstract interface + disabled stub + fake test backend for USBi write path.
//
// The real native backend (FFI / platform channel) is NOT implemented here.
// ProUsbiNativeBackendDisabled is the production stub: isAvailable = false.
// ProUsbiNativeBackendFake is for unit tests only — simulates ACK response.
//
// ABSOLUTE RESTRICTIONS:
//   - The real native write call is NOT implemented. isAvailable always false.
//   - ProUsbiNativeBackendFake must NEVER be used in production builds.
//   - wasActualWrite = false unless a real native write confirmed success.
//   - No EEPROM. No Selfboot. No SafeLoad. No other parameters.
//   - USBi is TEMPORARY. ICP5 is the final target.

// ── Abstract interface ────────────────────────────────────────────────────────

abstract class ProUsbiNativeBackend {
  /// Whether the native write backend is available on this platform.
  bool get isAvailable;

  /// Whether this is a test/fake backend (never true in production).
  bool get isFake => false;

  /// Sends the pre-built [setupPacket] then [bodyPacket], reads ACK.
  /// Returns the raw ACK payload bytes, or null on transport error.
  ///
  /// PRECONDITION: Caller must have verified all guards before calling.
  /// This method does NOT verify address or platform — the executor does.
  Future<List<int>?> sendPacketsAndReadAck({
    required List<int> setupPacket,
    required List<int> bodyPacket,
    required List<int> ackReadRequest,
  });
}

/// Optional read-only diagnostics exposed by native backends.
/// Executors must not use this metadata to widen an address allowlist.
abstract interface class ProUsbiTransactionDiagnosticsProvider {
  UsbiNativeTransactionDiagnostics? get lastTransactionDiagnostics;
}

class UsbiNativeTransactionDiagnostics {
  final List<int> setupPacket;
  final List<int> bodyPacket;
  final List<int> ackRequestPacket;
  final bool? setupTransferSuccess;
  final bool? bodyTransferSuccess;
  final int? bytesTransferred;
  final bool? ackReadSuccess;
  final int? ackBytesTransferred;
  final List<int>? rawAckBytes;
  final String? transferError;
  final String? ackReadError;
  final String? nativeException;
  final int? setupElapsedMilliseconds;
  final int? ackElapsedMilliseconds;
  final String timeoutDescription;
  final String bodyTransferDescription;

  const UsbiNativeTransactionDiagnostics({
    required this.setupPacket,
    required this.bodyPacket,
    required this.ackRequestPacket,
    this.setupTransferSuccess,
    this.bodyTransferSuccess,
    this.bytesTransferred,
    this.ackReadSuccess,
    this.ackBytesTransferred,
    this.rawAckBytes,
    this.transferError,
    this.ackReadError,
    this.nativeException,
    this.setupElapsedMilliseconds,
    this.ackElapsedMilliseconds,
    this.timeoutDescription =
        'No explicit timeout; synchronous WinUsb_ControlTransfer.',
    this.bodyTransferDescription =
        'Body is the data phase of the setup control transfer.',
  });
}

// ── Production disabled stub ──────────────────────────────────────────────────

/// Disabled stub used in all production builds.
/// isAvailable = false — sendPacketsAndReadAck always returns null.
class ProUsbiNativeBackendDisabled implements ProUsbiNativeBackend {
  const ProUsbiNativeBackendDisabled();

  @override
  bool get isAvailable => false;

  @override
  bool get isFake => false;

  @override
  Future<List<int>?> sendPacketsAndReadAck({
    required List<int> setupPacket,
    required List<int> bodyPacket,
    required List<int> ackReadRequest,
  }) async => null;
}

// ── Test fake backend ─────────────────────────────────────────────────────────

/// Fake backend for unit tests only. Simulates a successful ACK response.
/// Must NEVER be used in production builds.
class ProUsbiNativeBackendFake implements ProUsbiNativeBackend {
  final bool _simulateAckSuccess;
  final List<int>? _overrideAckPayload;

  List<List<int>> capturedSetupPackets = [];
  List<List<int>> capturedBodyPackets = [];
  int callCount = 0;

  ProUsbiNativeBackendFake({
    bool simulateAckSuccess = true,
    List<int>? overrideAckPayload,
  })  : _simulateAckSuccess = simulateAckSuccess,
        _overrideAckPayload = overrideAckPayload;

  @override
  bool get isAvailable => true;

  @override
  bool get isFake => true;

  @override
  Future<List<int>?> sendPacketsAndReadAck({
    required List<int> setupPacket,
    required List<int> bodyPacket,
    required List<int> ackReadRequest,
  }) async {
    callCount++;
    capturedSetupPackets.add(List.from(setupPacket));
    capturedBodyPackets.add(List.from(bodyPacket));

    if (_overrideAckPayload != null) return _overrideAckPayload;
    if (_simulateAckSuccess) {
      // Simulated ACK: [C0 B5 00 00 00 00 01 00]
      return [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00];
    } else {
      // Simulated NAK: byte 6 = 0x00 instead of 0x01
      return [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
    }
  }
}
