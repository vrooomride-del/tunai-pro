// Phase 2 — Room After-mode hardware gate.
//
// Read-only helper: no state, no write, no store. Reuses the SAME
// lastHardwareWriteResultProvider (HardwareWriteExecutionResult) the Factory
// path (LiveMeasurementController.afterModeAvailable) already relies on — no
// new provider, no new persisted state.
//
// Stricter than Factory on purpose: Factory's afterModeAvailable accepts
// HardwareWriteExecutionResult.allWritten (written OR ack-only). Room
// requires allReadbackVerified (every op actually DSP-readback-confirmed,
// not just ACKed) — see the completed safety audit for why: Room correction
// is a newer, less-proven path and the spec explicitly calls out blocking
// ack-only results.
//
// Identity-checked, not just boolean: lastHardwareWriteResultProvider is a
// single GLOBAL (non-project-scoped) StateProvider holding only the most
// recent write result across the whole app session. A boolean-only check
// (as Factory's afterModeAvailable does) would let a stale result from a
// DIFFERENT project or a PRIOR, superseded Room correction plan satisfy the
// gate. Room's approvedPackageId always embeds the projectId and a
// per-generation id (see RoomAutoPeqController.approve()), so prefix-matching
// against it rejects cross-project and stale-plan results structurally.

import '../deploy/pro_hardware_write_executor.dart'
    show HardwareWriteExecutionResult;
import '../room_workflow_persistence.dart' show VerifiedDeploymentReceipt;

/// Phase 3-D3A-3 — a typed reason alongside the existing free-text
/// [RoomAfterGateResult.blockedReason], added additively (the string stays
/// exactly as before) so a caller composing this gate with another (see
/// RoomAfterCaptureGate) can branch on WHICH kind of hardware block this is
/// without string-matching. Every existing blocked-branch below keeps its
/// exact original message; this only tags each with one of these codes.
enum RoomAfterBlockerCode {
  /// No Room Auto PEQ correction has been approved yet.
  correctionNotApproved,

  /// No hardware write has ever run for this project, or the most recent
  /// one was rejected before executing.
  correctionNotDeployed,

  /// A write ran for the current plan but failed outright, was only
  /// ACK-confirmed (not DSP-readback-verified), or hasn't been verified yet.
  hardwareWriteNotVerified,

  /// A hardware write DID run, but for a DIFFERENT plan than the one
  /// currently approved — a different project, a superseded correction
  /// generation, or (critically) a rollback's result being read where a
  /// fresh correction's result was expected. See this file's identity-check
  /// doc comment above.
  staleHardwareResult,
}

class RoomAfterGateResult {
  final bool available;
  final String? blockedReason;
  final RoomAfterBlockerCode? blockedCode;

  const RoomAfterGateResult._(this.available, this.blockedReason,
      [this.blockedCode]);
  const RoomAfterGateResult.available() : this._(true, null);
  const RoomAfterGateResult.blocked(String reason, [RoomAfterBlockerCode? code])
      : this._(false, reason, code);
}

abstract final class RoomAfterGate {
  /// [approvedPackageId] is the exact DspExportPackage.id the caller most
  /// recently approved for this project (RoomAutoPeqState.approvedPackageId
  /// or .rollbackApprovedPackageId — this helper is generic to both).
  /// [lastResult] is lastHardwareWriteResultProvider's current value —
  /// session-only, null after every app restart.
  ///
  /// [persistedReceipt] (Phase 3-F3) is the project's restart-safe
  /// VerifiedDeploymentReceipt, if any. It is consulted ONLY when
  /// [lastResult] is absent or does not match [approvedPackageId] — a live
  /// session result always takes precedence, so a fresh failed retry is
  /// never masked by an older, still-persisted successful receipt. This is
  /// the ONLY way this gate can return available() after a restart, when
  /// activeAdau1701ContextProvider is necessarily null: approval and
  /// deployment-verification are proven from persisted identity, never from
  /// "hardware is currently connected".
  static RoomAfterGateResult evaluate({
    required String? approvedPackageId,
    required HardwareWriteExecutionResult? lastResult,
    VerifiedDeploymentReceipt? persistedReceipt,
  }) {
    if (approvedPackageId == null) {
      return const RoomAfterGateResult.blocked(
        'Room Auto PEQ 승인이 필요합니다 — 후보를 승인한 뒤 Deploy에서 적용하세요.',
        RoomAfterBlockerCode.correctionNotApproved,
      );
    }

    // HardwareWriteApproval.planIdFor = '$sourceExportPackageId@$generatedAt'
    // (pro_hardware_write_approval.dart). Deploy tab rebuilds its own
    // HardwareWritePlan (and therefore a fresh generatedAt) from the
    // persisted DspExportPackage independently of when this controller built
    // its copy, so only the exportPackageId prefix is a stable, comparable
    // identity — never the full string.
    final sessionMatches = lastResult != null &&
        lastResult.planId.startsWith('$approvedPackageId@');

    if (!sessionMatches &&
        persistedReceipt != null &&
        persistedReceipt.matchesApprovedPackage(approvedPackageId) &&
        persistedReceipt.executed &&
        persistedReceipt.allReadbackVerified) {
      return const RoomAfterGateResult.available();
    }

    if (lastResult == null) {
      return const RoomAfterGateResult.blocked(
        'Deploy 탭에서 하드웨어에 실제로 적용해야 사용 가능합니다.',
        RoomAfterBlockerCode.correctionNotDeployed,
      );
    }
    if (!sessionMatches) {
      return const RoomAfterGateResult.blocked(
        '현재 승인된 Room 보정 계획과 일치하는 Deploy 결과가 없습니다 — 다시 승인 후 Deploy에서 적용하세요.',
        RoomAfterBlockerCode.staleHardwareResult,
      );
    }
    if (!lastResult.executed) {
      return RoomAfterGateResult.blocked(
        'Deploy가 실행되지 않았습니다 — ${lastResult.rejectionReason ?? "Deploy 탭 확인 필요"}',
        RoomAfterBlockerCode.correctionNotDeployed,
      );
    }
    if (!lastResult.allReadbackVerified) {
      if (lastResult.failedCount > 0) {
        return RoomAfterGateResult.blocked(
          'Deploy 실패 — ${lastResult.failedCount}개 작업 실패. Deploy 탭에서 다시 시도하세요.',
          RoomAfterBlockerCode.hardwareWriteNotVerified,
        );
      }
      if (lastResult.ackOnlyCount > 0) {
        return const RoomAfterGateResult.blocked(
          '일부 값이 ACK만 확인되고 DSP 판독으로 검증되지 않았습니다 — '
          'Room 보정은 판독 검증까지 완료되어야 사용 가능합니다.',
          RoomAfterBlockerCode.hardwareWriteNotVerified,
        );
      }
      return const RoomAfterGateResult.blocked(
        'Deploy 결과가 아직 검증되지 않았습니다.',
        RoomAfterBlockerCode.hardwareWriteNotVerified,
      );
    }
    return const RoomAfterGateResult.available();
  }
}
