import 'adau1701_ch0_band0_read_service.dart';
import 'icp5_frame_codec.dart';

// ── Preflight status ──────────────────────────────────────────────────────────

enum Adau1701PreflightStatus {
  /// All checks passed; deployment may proceed.
  passed,

  /// Transport is not connected or handshake has not been completed.
  transportNotReady,

  /// Snapshot device identity does not match expected firmware identity.
  deviceIdentityMismatch,

  /// The raw DSP state read or page assembly failed.
  rawReadFailed,

  /// The decoder rejected the raw payload (field out of range, etc.).
  decodeFailed,

  /// At least one field that the write plan will modify lacks an original value.
  incompleteCoverage,
}

// ── Preflight result ──────────────────────────────────────────────────────────

/// Full report produced by [Adau1701DeploymentPreflight.run].
///
/// Callers must check [passed] before allowing any write to proceed.
/// All report fields are populated regardless of outcome so that engineering
/// tooling can surface diagnostic information on failure.
class Adau1701PreflightResult {
  final Adau1701PreflightStatus status;
  final String message;

  // ── Read report ────────────────────────────────────────────────────────────

  /// Firmware identity confirmed during handshake.
  /// Populated only when [status] is not [Adau1701PreflightStatus.transportNotReady].
  final String? confirmedDeviceId;

  /// Timestamp at which the raw DSP snapshot was captured.
  /// Non-null only when the raw read succeeded.
  final DateTime? snapshotCapturedAt;

  /// Decoded original state for channel 0, band 0.
  /// Non-null only when the read and decode both succeeded.
  final Adau1701Ch0Band0OriginalState? originalState;

  // ── Coverage report ────────────────────────────────────────────────────────

  /// Coverage evaluation result against the write plan.
  /// Non-null only when [originalState] is available.
  final Adau1701OriginalStateCoverage? coverage;

  const Adau1701PreflightResult._({
    required this.status,
    required this.message,
    this.confirmedDeviceId,
    this.snapshotCapturedAt,
    this.originalState,
    this.coverage,
  });

  bool get passed => status == Adau1701PreflightStatus.passed;
}

// ── Preflight service ─────────────────────────────────────────────────────────

/// Verifies that all deployment prerequisites are met before any write is
/// allowed to execute.
///
/// This class has no write API. It only reads and evaluates.
///
/// Call [run] once per deployment attempt. A [passed] result does not cache;
/// the caller is responsible for proceeding to write immediately after a
/// passing preflight, before the device state can change.
class Adau1701DeploymentPreflight {
  final Adau1701RawReadTransport transport;

  const Adau1701DeploymentPreflight({required this.transport});

  Future<Adau1701PreflightResult> run({
    required Adau1701PeqWriteFields writePlan,
  }) async {
    // ── 1. Transport readiness ───────────────────────────────────────────────
    if (!transport.isConnected ||
        !transport.handshakeComplete ||
        transport.detectedProfile != Icp5FrameCodec.expectedProfile) {
      return const Adau1701PreflightResult._(
        status: Adau1701PreflightStatus.transportNotReady,
        message:
            'ADAU1701 identity handshake is required before deployment preflight.',
      );
    }

    final confirmedDeviceId = transport.detectedProfile!;

    // ── 2. Raw DSP state read ────────────────────────────────────────────────
    final readService =
        Adau1701Ch0Band0ReadService(transport: transport);
    final readResult = await readService.readOriginalState();

    if (!readResult.succeeded) {
      return Adau1701PreflightResult._(
        status: _mapReadStatus(readResult.status),
        message: readResult.message,
        confirmedDeviceId: confirmedDeviceId,
      );
    }

    final originalState = readResult.originalState!;

    // ── 3. Coverage evaluation ───────────────────────────────────────────────
    final coverage = evaluateOriginalStateCoverage(
      plan: writePlan,
      originalState: originalState,
    );

    if (!coverage.isCovered) {
      final missing = coverage.missingFields.join(', ');
      final reason = switch (coverage.status) {
        Adau1701OriginalStateCoverageStatus.noFieldsModified =>
          'Write plan does not modify any fields.',
        Adau1701OriginalStateCoverageStatus.missingOriginalValues =>
          'Original values missing for: $missing.',
        _ => 'Coverage check failed.',
      };
      return Adau1701PreflightResult._(
        status: coverage.status ==
                Adau1701OriginalStateCoverageStatus.noFieldsModified
            ? Adau1701PreflightStatus.incompleteCoverage
            : Adau1701PreflightStatus.incompleteCoverage,
        message: 'Deployment preflight failed — $reason',
        confirmedDeviceId: confirmedDeviceId,
        snapshotCapturedAt: originalState.capturedAt,
        originalState: originalState,
        coverage: coverage,
      );
    }

    // ── 4. All checks passed ─────────────────────────────────────────────────
    return Adau1701PreflightResult._(
      status: Adau1701PreflightStatus.passed,
      message: 'Deployment preflight passed. Original state captured at '
          '${originalState.capturedAt.toIso8601String()}.',
      confirmedDeviceId: confirmedDeviceId,
      snapshotCapturedAt: originalState.capturedAt,
      originalState: originalState,
      coverage: coverage,
    );
  }

  static Adau1701PreflightStatus _mapReadStatus(
    Adau1701Ch0Band0ReadStatus status,
  ) =>
      switch (status) {
        Adau1701Ch0Band0ReadStatus.deviceIdentityMismatch =>
          Adau1701PreflightStatus.deviceIdentityMismatch,
        Adau1701Ch0Band0ReadStatus.rawReadFailed =>
          Adau1701PreflightStatus.rawReadFailed,
        Adau1701Ch0Band0ReadStatus.decodeFailed =>
          Adau1701PreflightStatus.decodeFailed,
        _ => Adau1701PreflightStatus.rawReadFailed,
      };
}
