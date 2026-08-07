// ── TUNAI PRO Phase 3-D3A-3 — Room After dual capture gate ──────────────────
//
// Room After measurement requires BOTH independent safety conditions to
// hold at once:
//   1. the approved Room correction has actually reached hardware and been
//      readback-verified (RoomAfterGate — unmodified, only additively typed
//      this phase)
//   2. the current measurement setup/capture chain is valid
//      (MeasurementCaptureGate/preflight — unmodified, from Phase 3-D3A)
//
// This is a pure composition — it evaluates neither condition itself, only
// combines two already-computed results. Callers must feed it FRESH
// evaluations of both (RoomMeasurementController.capture() does so on every
// call, not just at mode-entry) so a capture can never proceed on a stale
// verdict of either kind.
library;

import '../measurement/measurement_capture_gate.dart';
import '../measurement/measurement_capture_gate_types.dart';
import 'room_after_gate.dart';

enum RoomAfterCaptureBlockerCode {
  /// No Room Auto PEQ correction has been approved yet.
  correctionNotApproved,

  /// No hardware write for the approved plan has run (or it was rejected
  /// before executing).
  correctionNotDeployed,

  /// A write ran for the current plan but wasn't fully readback-verified
  /// (failed, ack-only, or not yet verified).
  hardwareWriteNotVerified,

  /// A hardware write ran, but for a different plan than the one currently
  /// approved (different project, superseded generation, or a rollback's
  /// result being mistaken for a fresh correction's).
  staleHardwareResult,

  /// The measurement setup/capture chain itself is blocked — see
  /// [RoomAfterCaptureGateResult.measurementGate].primaryBlocker for which
  /// specific [MeasurementCaptureBlockerCode]; this code alone never loses
  /// that detail because the full [MeasurementCaptureGateResult] stays
  /// attached to the composite result.
  measurementSetupBlocked,

  /// The measurement chain has warnings that require explicit user
  /// acknowledgement before capture (same contract as Factory/Room's
  /// existing single-gate warning flow).
  measurementSetupWarningNotAcknowledged,
}

class RoomAfterCaptureBlocker {
  final RoomAfterCaptureBlockerCode code;
  final String message;

  const RoomAfterCaptureBlocker(this.code, this.message);

  @override
  String toString() => '${code.name}: $message';
}

/// What the UI should do about a [RoomAfterCaptureBlocker], typed rather
/// than string-matched. Exactly one of [measurementRemediation] is non-null
/// when [kind] is [RoomAfterCaptureRemediationKind.measurement].
class RoomAfterCaptureRemediation {
  final RoomAfterCaptureRemediationKind kind;
  final MeasurementCaptureRemediation? measurementRemediation;

  const RoomAfterCaptureRemediation._(this.kind, this.measurementRemediation);

  const RoomAfterCaptureRemediation.deployCorrection()
      : this._(RoomAfterCaptureRemediationKind.deployCorrection, null);

  const RoomAfterCaptureRemediation.measurement(
      MeasurementCaptureRemediation remediation)
      : this._(RoomAfterCaptureRemediationKind.measurement, remediation);

  const RoomAfterCaptureRemediation.acknowledgeMeasurementWarning()
      : this._(RoomAfterCaptureRemediationKind.acknowledgeMeasurementWarning,
            null);
}

enum RoomAfterCaptureRemediationKind {
  /// Go apply/re-apply the Room correction (existing Deploy tab /
  /// HardwareApplyFlow — no new navigation).
  deployCorrection,

  /// Route through the existing typed [MeasurementCaptureRemediation]
  /// dispatch (manage microphone, guided setup, etc.).
  measurement,

  /// Show the existing warning-acknowledgement confirmation dialog.
  acknowledgeMeasurementWarning,
}

class RoomAfterCaptureGateResult {
  final bool canCapture;
  final RoomAfterGateResult hardwareGate;
  final MeasurementCaptureGateResult measurementGate;
  final List<RoomAfterCaptureBlocker> blockers;

  const RoomAfterCaptureGateResult({
    required this.canCapture,
    required this.hardwareGate,
    required this.measurementGate,
    required this.blockers,
  });

  /// Ordered per Phase 3-D3A-3 §4: hardware first, then measurement setup,
  /// then measurement warning — never a UI-side string condition, this
  /// order falls directly out of the order [blockers] was built in.
  RoomAfterCaptureBlocker? get primaryBlocker =>
      blockers.isEmpty ? null : blockers.first;

  RoomAfterCaptureRemediation? get primaryRemediation {
    final blocker = primaryBlocker;
    if (blocker == null) return null;
    switch (blocker.code) {
      case RoomAfterCaptureBlockerCode.correctionNotApproved:
      case RoomAfterCaptureBlockerCode.correctionNotDeployed:
      case RoomAfterCaptureBlockerCode.hardwareWriteNotVerified:
      case RoomAfterCaptureBlockerCode.staleHardwareResult:
        return const RoomAfterCaptureRemediation.deployCorrection();
      case RoomAfterCaptureBlockerCode.measurementSetupBlocked:
        return RoomAfterCaptureRemediation.measurement(
            measurementGate.primaryBlocker!.remediation);
      case RoomAfterCaptureBlockerCode.measurementSetupWarningNotAcknowledged:
        return const RoomAfterCaptureRemediation
            .acknowledgeMeasurementWarning();
    }
  }

  bool hasBlocker(RoomAfterCaptureBlockerCode code) =>
      blockers.any((b) => b.code == code);
}

abstract final class RoomAfterCaptureGate {
  static const _hardwareCodeMap = {
    RoomAfterBlockerCode.correctionNotApproved:
        RoomAfterCaptureBlockerCode.correctionNotApproved,
    RoomAfterBlockerCode.correctionNotDeployed:
        RoomAfterCaptureBlockerCode.correctionNotDeployed,
    RoomAfterBlockerCode.hardwareWriteNotVerified:
        RoomAfterCaptureBlockerCode.hardwareWriteNotVerified,
    RoomAfterBlockerCode.staleHardwareResult:
        RoomAfterCaptureBlockerCode.staleHardwareResult,
  };

  /// Pure composition — evaluates neither gate itself. Both [hardwareGate]
  /// and [measurementGate] must be FRESH evaluations from the caller (never
  /// values cached from an earlier point in time).
  static RoomAfterCaptureGateResult evaluate({
    required RoomAfterGateResult hardwareGate,
    required MeasurementCaptureGateResult measurementGate,
  }) {
    final blockers = <RoomAfterCaptureBlocker>[];

    if (!hardwareGate.available) {
      final code = _hardwareCodeMap[hardwareGate.blockedCode] ??
          RoomAfterCaptureBlockerCode.correctionNotDeployed;
      blockers.add(RoomAfterCaptureBlocker(
        code,
        hardwareGate.blockedReason ?? '하드웨어 적용 상태를 확인할 수 없습니다.',
      ));
    }

    if (measurementGate.blockers.isNotEmpty) {
      blockers.add(RoomAfterCaptureBlocker(
        RoomAfterCaptureBlockerCode.measurementSetupBlocked,
        measurementGate.primaryBlocker!.message,
      ));
    } else if (measurementGate.requiresExplicitWarningAcknowledgement) {
      blockers.add(const RoomAfterCaptureBlocker(
        RoomAfterCaptureBlockerCode.measurementSetupWarningNotAcknowledged,
        '측정 전 경고 확인이 필요합니다.',
      ));
    }

    return RoomAfterCaptureGateResult(
      canCapture: hardwareGate.available && measurementGate.canCapture,
      hardwareGate: hardwareGate,
      measurementGate: measurementGate,
      blockers: List.unmodifiable(blockers),
    );
  }
}
