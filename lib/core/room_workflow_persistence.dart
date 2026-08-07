// Phase 3-F3 — Room Auto PEQ approval / verified deployment receipt / closed
// loop verdict persistence.
//
// Three small, additive, immutable records stored on
// RoomMeasurementProjectState (see room_measurement_data.dart) so the
// workflow survives an app restart or project reopen without inventing a
// parallel truth source: they are read the same way roomState.before/after
// already are, and written through the existing
// ProProjectStoreNotifier.updateRoomState.
//
// Approval != deployment != verification — each record only ever claims
// exactly what it was built from:
//   - RoomAutoPeqApproval        — the user approved this package. Nothing
//     about hardware.
//   - VerifiedDeploymentReceipt  — a specific write actually executed and
//     every operation was DSP-readback verified (never ack-only, never a
//     bare ack). Built only from a real HardwareWriteExecutionResult.
//   - PersistedRoomClosedLoopResult — a real Before/After comparison reached
//     a verdict. Carries an identity fingerprint of the exact Before/After
//     pair it was computed from, so a caller can detect when the underlying
//     measurements have since changed (defense in depth — the controller
//     also actively clears this field on any Before/After change; see
//     RoomMeasurementController.accept()/startNewAfterSession()).

import 'deploy/pro_hardware_write_executor.dart'
    show HardwareWriteExecutionResult;
import 'pro_correction_cycle.dart' show CorrectionCycleDecision;
import 'room_measurement_data.dart' show RoomMeasurementSnapshot;

/// Persisted record of a user's Room Auto PEQ approval — project-scoped,
/// survives restart. Never implies the package actually reached hardware;
/// see [VerifiedDeploymentReceipt] for that.
class RoomAutoPeqApproval {
  final String projectId;

  /// The exact DspExportPackage.id approved — identical identity role to
  /// RoomAutoPeqState.approvedPackageId, just persisted.
  final String approvedPackageId;
  final DateTime approvedAt;

  const RoomAutoPeqApproval({
    required this.projectId,
    required this.approvedPackageId,
    required this.approvedAt,
  });

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'approvedPackageId': approvedPackageId,
        'approvedAt': approvedAt.toIso8601String(),
      };

  /// Item-resilient: any malformed/missing identity yields null rather than
  /// throwing or fabricating a synthetic approval.
  static RoomAutoPeqApproval? fromJson(Map<String, dynamic> j) {
    try {
      final projectId = j['projectId'] as String?;
      final approvedPackageId = j['approvedPackageId'] as String?;
      if (projectId == null || projectId.isEmpty) return null;
      if (approvedPackageId == null || approvedPackageId.isEmpty) return null;
      return RoomAutoPeqApproval(
        projectId: projectId,
        approvedPackageId: approvedPackageId,
        approvedAt: DateTime.tryParse(j['approvedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persisted, immutable proof that a specific plan actually executed and
/// every approved operation was DSP-readback verified. The restart-safe
/// counterpart to the session-only lastHardwareWriteResultProvider — built
/// with the same [HardwareWriteExecutionResult.allReadbackVerified]
/// contract, never a looser one.
class VerifiedDeploymentReceipt {
  final String projectId;

  /// Extracted from `planId`'s `packageId@generatedAt` shape — the same
  /// identity RoomAfterGate already prefix-matches against.
  final String packageId;
  final String planId;
  final String dspTarget;
  final bool executed;
  final bool allReadbackVerified;
  final DateTime verifiedAt;

  const VerifiedDeploymentReceipt({
    required this.projectId,
    required this.packageId,
    required this.planId,
    required this.dspTarget,
    required this.executed,
    required this.allReadbackVerified,
    required this.verifiedAt,
  });

  /// Same prefix-identity contract as RoomAfterGate's session-result check.
  bool matchesApprovedPackage(String? approvedPackageId) =>
      approvedPackageId != null && planId.startsWith('$approvedPackageId@');

  /// Builds a receipt ONLY when [result] is a genuine, fully-verified
  /// success (never ack-only, never a bare ACK, never a partial write) AND
  /// its plan matches one of the project's currently-approved Room
  /// identities — the correction itself or its rollback. Both count as
  /// "approved" (see RoomAutoPeqController.approve()/requestRollback());
  /// matching either keeps this receipt's single slot in sync with
  /// whichever plan the hardware most recently actually reflects, mirroring
  /// lastHardwareWriteResultProvider's existing single-slot "most recent
  /// write wins" semantics — so a later rollback correctly supersedes an
  /// earlier correction's receipt instead of leaving it falsely valid.
  ///
  /// Returns null for every other case — an unrelated (e.g. Factory)
  /// package, an ack-only or failed result, or no approval at all. No
  /// receipt is ever fabricated from a partial signal.
  static VerifiedDeploymentReceipt? fromExecutionResult({
    required HardwareWriteExecutionResult result,
    required String projectId,
    required String dspTarget,
    required String? approvedPackageId,
    required String? rollbackApprovedPackageId,
    required DateTime verifiedAt,
  }) {
    if (!result.executed || !result.allReadbackVerified) return null;
    final matchesCorrection = approvedPackageId != null &&
        result.planId.startsWith('$approvedPackageId@');
    final matchesRollback = rollbackApprovedPackageId != null &&
        result.planId.startsWith('$rollbackApprovedPackageId@');
    if (!matchesCorrection && !matchesRollback) return null;
    final packageId = result.planId.split('@').first;
    if (packageId.isEmpty) return null;
    return VerifiedDeploymentReceipt(
      projectId: projectId,
      packageId: packageId,
      planId: result.planId,
      dspTarget: dspTarget,
      executed: true,
      allReadbackVerified: true,
      verifiedAt: verifiedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'packageId': packageId,
        'planId': planId,
        'dspTarget': dspTarget,
        'executed': executed,
        'allReadbackVerified': allReadbackVerified,
        'verifiedAt': verifiedAt.toIso8601String(),
      };

  static VerifiedDeploymentReceipt? fromJson(Map<String, dynamic> j) {
    try {
      final projectId = j['projectId'] as String?;
      final packageId = j['packageId'] as String?;
      final planId = j['planId'] as String?;
      if (projectId == null || projectId.isEmpty) return null;
      if (packageId == null || packageId.isEmpty) return null;
      if (planId == null || planId.isEmpty) return null;
      final executed = j['executed'] as bool? ?? false;
      final verified = j['allReadbackVerified'] as bool? ?? false;
      // A legacy/corrupt receipt that doesn't itself claim full verification
      // must never decode into one that does.
      if (!executed || !verified) return null;
      return VerifiedDeploymentReceipt(
        projectId: projectId,
        packageId: packageId,
        planId: planId,
        dspTarget: j['dspTarget'] as String? ?? '',
        executed: executed,
        allReadbackVerified: verified,
        verifiedAt: DateTime.tryParse(j['verifiedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persisted summary of a real RoomClosedLoopEvaluator verdict, so a
/// restart/reopen can restore "workflow complete" without re-deriving a
/// parallel verdict. Carries an identity fingerprint of the exact Before/
/// After pair the verdict was computed from — [matchesCurrent] lets a
/// caller refuse to trust a persisted verdict against measurements that have
/// since changed, as a second layer under the controller's own active
/// invalidation (see room_measurement_controller.dart).
class PersistedRoomClosedLoopResult {
  final String projectId;
  final CorrectionCycleDecision decision;
  final DateTime evaluatedAt;
  final String beforeIdentity;
  final String afterIdentity;

  const PersistedRoomClosedLoopResult({
    required this.projectId,
    required this.decision,
    required this.evaluatedAt,
    required this.beforeIdentity,
    required this.afterIdentity,
  });

  static String _snapshotIdentity(RoomMeasurementSnapshot s) {
    String side(dynamic m) =>
        m == null ? '' : '${m.frd.id}@${m.capturedAt.toIso8601String()}';
    return '${side(s.leftSystemFrd)}|${side(s.rightSystemFrd)}';
  }

  factory PersistedRoomClosedLoopResult.fromResult({
    required String projectId,
    required RoomMeasurementSnapshot before,
    required RoomMeasurementSnapshot after,
    required CorrectionCycleDecision decision,
    required DateTime evaluatedAt,
  }) =>
      PersistedRoomClosedLoopResult(
        projectId: projectId,
        decision: decision,
        evaluatedAt: evaluatedAt,
        beforeIdentity: _snapshotIdentity(before),
        afterIdentity: _snapshotIdentity(after),
      );

  bool matchesCurrent(
          RoomMeasurementSnapshot before, RoomMeasurementSnapshot after) =>
      beforeIdentity == _snapshotIdentity(before) &&
      afterIdentity == _snapshotIdentity(after);

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'decision': decision.name,
        'evaluatedAt': evaluatedAt.toIso8601String(),
        'beforeIdentity': beforeIdentity,
        'afterIdentity': afterIdentity,
      };

  static PersistedRoomClosedLoopResult? fromJson(Map<String, dynamic> j) {
    try {
      final projectId = j['projectId'] as String?;
      if (projectId == null || projectId.isEmpty) return null;
      final decisionName = j['decision'] as String?;
      final decision = CorrectionCycleDecision.values
          .where((d) => d.name == decisionName)
          .firstOrNull;
      if (decision == null) return null;
      return PersistedRoomClosedLoopResult(
        projectId: projectId,
        decision: decision,
        evaluatedAt: DateTime.tryParse(j['evaluatedAt'] as String? ?? '') ??
            DateTime.now(),
        beforeIdentity: j['beforeIdentity'] as String? ?? '',
        afterIdentity: j['afterIdentity'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
