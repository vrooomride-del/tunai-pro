import 'adau1701_deployment_preflight.dart';
import 'icp5_transports.dart';

/// Immutable evidence record of a single ADAU1701 deployment attempt.
///
/// Captures the full chain of evidence: preflight context, write outcome,
/// and rollback outcome. Created by [fromAttempt] immediately after the
/// write operation completes; never mutated after construction.
class Adau1701DeploymentReport {
  /// When the deployment attempt was initiated.
  final DateTime attemptedAt;

  // ── Preflight context ────────────────────────────────────────────────────

  /// Firmware identity confirmed during transport handshake.
  /// Null when the preflight did not reach the transport-ready stage.
  final String? dspIdentity;

  /// Transport-layer identifier (COM port name or BLE UUID).
  /// Populated from the active transport at the time of the attempt.
  final String? transportIdentity;

  /// Timestamp at which the raw DSP state snapshot was captured.
  /// Null when the raw read did not succeed.
  final DateTime? snapshotCapturedAt;

  /// Whether the decoded original state was available for coverage evaluation.
  final bool originalStateAvailable;

  /// Whether all fields modified by the write plan had original values.
  /// Null when no coverage evaluation was reached.
  final bool? coverageResult;

  /// Outcome of the deployment preflight check.
  final Adau1701PreflightStatus preflightStatus;

  /// Human-readable reason when the preflight did not pass.
  /// Null when [preflightStatus] is [Adau1701PreflightStatus.passed].
  final String? preflightFailureReason;

  // ── Deployment outcome ───────────────────────────────────────────────────

  /// Whether the preflight passed and a write was attempted.
  final bool deploymentAllowed;

  /// Result of the deployment write. Null when [deploymentAllowed] is false.
  final Icp5PhaseCResult? deploymentResult;

  /// Result of the automatic rollback. Null when no rollback was needed or
  /// when the deployment was blocked by the preflight.
  final Icp5PhaseCResult? rollbackResult;

  const Adau1701DeploymentReport({
    required this.attemptedAt,
    this.dspIdentity,
    this.transportIdentity,
    this.snapshotCapturedAt,
    required this.originalStateAvailable,
    this.coverageResult,
    required this.preflightStatus,
    this.preflightFailureReason,
    required this.deploymentAllowed,
    this.deploymentResult,
    this.rollbackResult,
  });

  bool get deploymentSucceeded => deploymentResult?.success == true;
  bool get rollbackRequired => rollbackResult != null;
  bool get rollbackSucceeded => rollbackResult?.success == true;

  /// Builds a report from a completed deployment attempt.
  ///
  /// [preflight] is the result captured immediately before the write.
  /// [transportIdentity] is the COM port or BLE UUID of the active transport.
  /// [outcome] is the write + rollback result; null when the write was not
  /// attempted (e.g. when [preflight] did not pass).
  factory Adau1701DeploymentReport.fromAttempt({
    required Adau1701PreflightResult preflight,
    required String? transportIdentity,
    required Icp5PhaseCOutcome? outcome,
    required DateTime attemptedAt,
  }) {
    final allowed = preflight.passed;
    return Adau1701DeploymentReport(
      attemptedAt: attemptedAt,
      dspIdentity: preflight.confirmedDeviceId,
      transportIdentity: transportIdentity,
      snapshotCapturedAt: preflight.snapshotCapturedAt,
      originalStateAvailable: preflight.originalState != null,
      coverageResult: preflight.coverage?.isCovered,
      preflightStatus: preflight.status,
      preflightFailureReason: allowed ? null : preflight.message,
      deploymentAllowed: allowed,
      deploymentResult: outcome?.test,
      rollbackResult: outcome?.restore,
    );
  }
}
