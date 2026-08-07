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

class RoomAfterGateResult {
  final bool available;
  final String? blockedReason;

  const RoomAfterGateResult._(this.available, this.blockedReason);
  const RoomAfterGateResult.available() : this._(true, null);
  const RoomAfterGateResult.blocked(String reason) : this._(false, reason);
}

abstract final class RoomAfterGate {
  /// [approvedPackageId] is the exact DspExportPackage.id the caller most
  /// recently approved for this project (RoomAutoPeqState.approvedPackageId
  /// or .rollbackApprovedPackageId — this helper is generic to both).
  /// [lastResult] is lastHardwareWriteResultProvider's current value.
  static RoomAfterGateResult evaluate({
    required String? approvedPackageId,
    required HardwareWriteExecutionResult? lastResult,
  }) {
    if (approvedPackageId == null) {
      return const RoomAfterGateResult.blocked(
        'Room Auto PEQ 승인이 필요합니다 — 후보를 승인한 뒤 Deploy에서 적용하세요.',
      );
    }
    if (lastResult == null) {
      return const RoomAfterGateResult.blocked(
        'Deploy 탭에서 하드웨어에 실제로 적용해야 사용 가능합니다.',
      );
    }
    // HardwareWriteApproval.planIdFor = '$sourceExportPackageId@$generatedAt'
    // (pro_hardware_write_approval.dart). Deploy tab rebuilds its own
    // HardwareWritePlan (and therefore a fresh generatedAt) from the
    // persisted DspExportPackage independently of when this controller built
    // its copy, so only the exportPackageId prefix is a stable, comparable
    // identity — never the full string.
    if (!lastResult.planId.startsWith('$approvedPackageId@')) {
      return const RoomAfterGateResult.blocked(
        '현재 승인된 Room 보정 계획과 일치하는 Deploy 결과가 없습니다 — 다시 승인 후 Deploy에서 적용하세요.',
      );
    }
    if (!lastResult.executed) {
      return RoomAfterGateResult.blocked(
        'Deploy가 실행되지 않았습니다 — ${lastResult.rejectionReason ?? "Deploy 탭 확인 필요"}',
      );
    }
    if (!lastResult.allReadbackVerified) {
      if (lastResult.failedCount > 0) {
        return RoomAfterGateResult.blocked(
          'Deploy 실패 — ${lastResult.failedCount}개 작업 실패. Deploy 탭에서 다시 시도하세요.',
        );
      }
      if (lastResult.ackOnlyCount > 0) {
        return const RoomAfterGateResult.blocked(
          '일부 값이 ACK만 확인되고 DSP 판독으로 검증되지 않았습니다 — '
          'Room 보정은 판독 검증까지 완료되어야 사용 가능합니다.',
        );
      }
      return const RoomAfterGateResult.blocked('Deploy 결과가 아직 검증되지 않았습니다.');
    }
    return const RoomAfterGateResult.available();
  }
}
