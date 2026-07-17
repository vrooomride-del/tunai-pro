import 'adau1701_ch0_band0_decoder.dart';
import 'icp5_frame_codec.dart';
import 'icp5_raw_state_read.dart';

// ── Original state ────────────────────────────────────────────────────────────

/// Authoritative device-bound original values for channel 0, band 0.
///
/// These values are obtained by a guarded hardware read and must not be
/// synthesised, defaulted, or fabricated. They serve as the rollback baseline
/// for any write plan that modifies these fields.
class Adau1701Ch0Band0OriginalState {
  final String deviceId;
  final DateTime capturedAt;
  final int frequencyHz;
  final double gainDb;
  final double q;

  /// Raw value of DSP property 0x08 for channel 0 band 0.
  /// Evidence-backed name; semantic meaning is not yet confirmed.
  final int property08State;

  const Adau1701Ch0Band0OriginalState({
    required this.deviceId,
    required this.capturedAt,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.property08State,
  });
}

// ── Read result ───────────────────────────────────────────────────────────────

enum Adau1701Ch0Band0ReadStatus {
  success,
  deviceIdentityMismatch,
  transportNotReady,
  rawReadFailed,
  decodeFailed,
}

class Adau1701Ch0Band0ReadResult {
  final Adau1701Ch0Band0ReadStatus status;
  final Adau1701Ch0Band0OriginalState? originalState;
  final String message;

  const Adau1701Ch0Band0ReadResult._({
    required this.status,
    required this.message,
    this.originalState,
  });

  factory Adau1701Ch0Band0ReadResult.success(
    Adau1701Ch0Band0OriginalState state,
  ) =>
      Adau1701Ch0Band0ReadResult._(
        status: Adau1701Ch0Band0ReadStatus.success,
        message: 'ADAU1701 channel 0 band 0 state read succeeded.',
        originalState: state,
      );

  const Adau1701Ch0Band0ReadResult.failure(
    this.status,
    this.message,
  ) : originalState = null;

  bool get succeeded =>
      status == Adau1701Ch0Band0ReadStatus.success && originalState != null;
}

// ── Transport surface required by the service ─────────────────────────────────

/// Minimal transport surface the read service depends on.
///
/// Keeps the service testable without a full [Icp5UsbTransport] instance.
abstract interface class Adau1701RawReadTransport {
  bool get isConnected;
  bool get handshakeComplete;
  String? get detectedProfile;

  Future<RawDspStateSnapshot> readRawDspState();
}

// ── Read service ──────────────────────────────────────────────────────────────

/// Guarded read-and-decode service for ADAU1701 channel 0, band 0.
///
/// Validates:
/// - transport ready (connected + handshake + profile == DSP1701.100.00.01)
/// - raw snapshot device identity
/// - raw snapshot block ID and payload length (via [RawDspStateSnapshot] ctor)
/// - decoded field ranges (via [Adau1701Ch0Band0Decoder])
///
/// On success, returns an [Adau1701Ch0Band0OriginalState] bound to the
/// firmware identity [Icp5FrameCodec.expectedProfile].
class Adau1701Ch0Band0ReadService {
  final Adau1701RawReadTransport transport;

  const Adau1701Ch0Band0ReadService({required this.transport});

  Future<Adau1701Ch0Band0ReadResult> readOriginalState() async {
    if (!transport.isConnected ||
        !transport.handshakeComplete ||
        transport.detectedProfile != Icp5FrameCodec.expectedProfile) {
      return const Adau1701Ch0Band0ReadResult.failure(
        Adau1701Ch0Band0ReadStatus.transportNotReady,
        'ADAU1701 identity handshake is required before reading state.',
      );
    }

    final RawDspStateSnapshot snapshot;
    try {
      snapshot = await transport.readRawDspState();
    } catch (error) {
      return Adau1701Ch0Band0ReadResult.failure(
        Adau1701Ch0Band0ReadStatus.rawReadFailed,
        'Raw DSP state read failed: $error',
      );
    }

    if (snapshot.deviceId != Icp5FrameCodec.expectedProfile) {
      return Adau1701Ch0Band0ReadResult.failure(
        Adau1701Ch0Band0ReadStatus.deviceIdentityMismatch,
        'Raw snapshot device identity mismatch: ${snapshot.deviceId}',
      );
    }

    final Adau1701Ch0Band0DecodedState decoded;
    try {
      decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
    } on FormatException catch (e) {
      return Adau1701Ch0Band0ReadResult.failure(
        Adau1701Ch0Band0ReadStatus.decodeFailed,
        'ADAU1701 channel 0 band 0 decode failed: ${e.message}',
      );
    }

    return Adau1701Ch0Band0ReadResult.success(
      Adau1701Ch0Band0OriginalState(
        deviceId: snapshot.deviceId,
        capturedAt: snapshot.timestamp,
        frequencyHz: decoded.frequencyHz,
        gainDb: decoded.gainDb,
        q: decoded.q,
        property08State: decoded.property08State,
      ),
    );
  }
}

// ── Write-plan field coverage ─────────────────────────────────────────────────

/// Describes which PEQ fields a write plan intends to modify for channel 0
/// band 0. Only fields the plan modifies must be covered by original state.
class Adau1701PeqWriteFields {
  final bool frequency;
  final bool gain;
  final bool q;
  final bool property08;

  const Adau1701PeqWriteFields({
    this.frequency = false,
    this.gain = false,
    this.q = false,
    this.property08 = false,
  });

  bool get anyModified => frequency || gain || q || property08;
}

enum Adau1701OriginalStateCoverageStatus {
  /// All fields modified by the write plan have original values.
  covered,

  /// No fields are modified — coverage check is not applicable.
  noFieldsModified,

  /// At least one field that the write plan modifies lacks an original value.
  missingOriginalValues,
}

class Adau1701OriginalStateCoverage {
  final Adau1701OriginalStateCoverageStatus status;
  final List<String> missingFields;

  const Adau1701OriginalStateCoverage._({
    required this.status,
    required this.missingFields,
  });

  bool get isCovered =>
      status == Adau1701OriginalStateCoverageStatus.covered;
}

/// Evaluates whether [originalState] covers every field that [plan] will
/// modify. Fields the plan does not modify are not required.
///
/// [originalState] may be null when no hardware read has been performed.
Adau1701OriginalStateCoverage evaluateOriginalStateCoverage({
  required Adau1701PeqWriteFields plan,
  required Adau1701Ch0Band0OriginalState? originalState,
}) {
  if (!plan.anyModified) {
    return const Adau1701OriginalStateCoverage._(
      status: Adau1701OriginalStateCoverageStatus.noFieldsModified,
      missingFields: [],
    );
  }

  if (originalState == null) {
    // No read has been performed; every modified field is missing.
    final missing = [
      if (plan.frequency) 'frequencyHz',
      if (plan.gain) 'gainDb',
      if (plan.q) 'q',
      if (plan.property08) 'property08State',
    ];
    return Adau1701OriginalStateCoverage._(
      status: Adau1701OriginalStateCoverageStatus.missingOriginalValues,
      missingFields: List.unmodifiable(missing),
    );
  }

  // When original state is present all four fields are always populated, so
  // every required field is covered.  The check is field-by-field so that
  // future partial-state models can extend this without changing the API.
  final missing = <String>[
    // originalState always has frequencyHz; listed for symmetry.
    if (plan.frequency && originalState.frequencyHz == 0) 'frequencyHz',
    if (plan.gain && !originalState.gainDb.isFinite) 'gainDb',
    if (plan.q && !originalState.q.isFinite) 'q',
    // property08State is always 0 or 1 (enforced by decoder); 0 is valid.
  ];

  if (missing.isNotEmpty) {
    return Adau1701OriginalStateCoverage._(
      status: Adau1701OriginalStateCoverageStatus.missingOriginalValues,
      missingFields: List.unmodifiable(missing),
    );
  }

  return const Adau1701OriginalStateCoverage._(
    status: Adau1701OriginalStateCoverageStatus.covered,
    missingFields: [],
  );
}
