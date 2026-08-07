// Phase 2 — Room Auto PEQ session controller.
//
// Thin state machine around the pure lib/core/orchestrator/room_auto_peq.dart
// pipeline: generate -> user approval gate -> persist DspExportPackage into
// exportState exactly the way guided_ai_screen.dart's onExportPackage
// callback already does for the Factory path (pro_project_store.dart's
// updateExportState — no new persistence path) -> hand off to Deploy tab,
// which reuses the existing HardwareApplyFlow / HardwareWriteExecutor
// approve-then-apply UI unchanged. Zero hardware writes happen in this file.
//
// Safety audit follow-up (this file):
//  - approve() now mints a per-approval-unique packageId and captures a
//    fresh pre-apply TuningProjectState snapshot at approval time — both
//    consumed by RoomAfterGate (After-mode hardware gate) and
//    requestRollback() (worsened-verdict recovery). Neither existed before
//    this pass; RoomMeasurementController.setMode(after) was previously
//    ungated entirely.
//  - Factory's equivalent rollback (ProProjectStoreNotifier.rollbackTuningState)
//    is explicitly software-only — see its doc comment: "performs no
//    hardware I/O whatsoever". It works by reverting the live tuningState
//    and marking export packages stale, requiring the user to re-export and
//    re-deploy through the normal flow to actually reach hardware again.
//    Room's rollback is intentionally NOT a copy of that: Room Auto PEQ
//    never writes tuningState in the first place (see approve() below), so
//    there is no local model to revert. Instead requestRollback() builds an
//    explicit rollback HardwareWritePlan from the captured snapshot and
//    routes it through the exact same exportState -> Deploy ->
//    HardwareApplyFlow path as a normal correction — still zero direct
//    writes here, and still gated by the same approve-then-apply UI.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/orchestrator/room_auto_peq.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../core/room_measurement_data.dart';

enum RoomAutoPeqPhase { idle, confirmPending, noChange, approved }

enum RoomRollbackPhase {
  /// No approved correction to roll back (or nothing worsened yet).
  none,

  /// Rollback package built and persisted into exportState; awaiting Deploy.
  approved,
}

class RoomAutoPeqState {
  final RoomAutoPeqPhase phase;
  final List<RoomAutoPeqCandidate> candidates;
  final String? error;

  /// The exact DspExportPackage.id most recently approved for a Room
  /// correction (not a rollback) — RoomAfterGate matches this against
  /// lastHardwareWriteResultProvider's planId prefix. Null until an approval
  /// has actually succeeded.
  final String? approvedPackageId;

  /// The project's full TuningProjectState (PEQ/XO/gain/delay/mute/phase),
  /// captured fresh at the moment [approvedPackageId]'s approval happened —
  /// never at candidate-generation time, and never fabricated. This is
  /// Room's equivalent of ProGuidedAiController's _preApplyTuningState.
  final TuningProjectState? preApplySnapshot;

  final RoomRollbackPhase rollbackPhase;

  /// Same identity role as [approvedPackageId] but for the rollback package,
  /// so RoomAfterGate can independently confirm "the rollback itself was
  /// actually written" without conflating it with the original correction.
  final String? rollbackApprovedPackageId;

  const RoomAutoPeqState({
    this.phase = RoomAutoPeqPhase.idle,
    this.candidates = const [],
    this.error,
    this.approvedPackageId,
    this.preApplySnapshot,
    this.rollbackPhase = RoomRollbackPhase.none,
    this.rollbackApprovedPackageId,
  });

  RoomAutoPeqState copyWith({
    RoomAutoPeqPhase? phase,
    List<RoomAutoPeqCandidate>? candidates,
    String? error,
    bool clearError = false,
    String? approvedPackageId,
    TuningProjectState? preApplySnapshot,
    RoomRollbackPhase? rollbackPhase,
    String? rollbackApprovedPackageId,
  }) =>
      RoomAutoPeqState(
        phase: phase ?? this.phase,
        candidates: candidates ?? this.candidates,
        error: clearError ? null : (error ?? this.error),
        approvedPackageId: approvedPackageId ?? this.approvedPackageId,
        preApplySnapshot: preApplySnapshot ?? this.preApplySnapshot,
        rollbackPhase: rollbackPhase ?? this.rollbackPhase,
        rollbackApprovedPackageId:
            rollbackApprovedPackageId ?? this.rollbackApprovedPackageId,
      );
}

final roomAutoPeqControllerProvider = StateNotifierProvider.family<
    RoomAutoPeqController, RoomAutoPeqState, String>(
  (ref, projectId) => RoomAutoPeqController(ref, projectId),
);

class RoomAutoPeqController extends StateNotifier<RoomAutoPeqState> {
  final Ref _ref;
  final String projectId;

  RoomAutoPeqController(this._ref, this.projectId)
      : super(const RoomAutoPeqState());

  ProProject? get _project => _ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == projectId)
      .firstOrNull;

  bool get isReady {
    final before = _project?.roomState.before;
    return before != null && RoomAutoPeq.isReady(before);
  }

  PeqChannelState _currentWoofer(String channelId) =>
      _project?.tuningState.peqChannels
          .where((c) => c.channelId == channelId)
          .firstOrNull ??
      PeqChannelState.fixed(channelId);

  /// Runs the deterministic pipeline for both sides and stops at the
  /// approval gate. No write happens here.
  void generate() {
    final project = _project;
    final before = project?.roomState.before;
    if (project == null || before == null || !RoomAutoPeq.isReady(before)) {
      state = state.copyWith(
        error: '준비되지 않음: Before Left+Right 측정 2/2가 필요합니다.',
      );
      return;
    }

    final left = RoomAutoPeq.generateForSide(
      side: RoomSystemSide.left,
      beforeMeasurement: before.leftSystemFrd!,
      currentWooferChannel: _currentWoofer('ch_wf_l'),
    );
    final right = RoomAutoPeq.generateForSide(
      side: RoomSystemSide.right,
      beforeMeasurement: before.rightSystemFrd!,
      currentWooferChannel: _currentWoofer('ch_wf_r'),
    );
    final candidates = [
      if (left != null) left,
      if (right != null) right,
    ];
    final anyChange = candidates.any((c) => c.hasChange);

    // Only the in-progress generate/confirm cycle resets. A prior
    // approval's identity/snapshot/rollback state is untouched here — it
    // still describes whatever was actually approved and (maybe) deployed;
    // generating a fresh preview must not retroactively invalidate that
    // history or the After-gate that depends on it.
    state = state.copyWith(
      phase: anyChange
          ? RoomAutoPeqPhase.confirmPending
          : RoomAutoPeqPhase.noChange,
      candidates: candidates,
      clearError: true,
    );
  }

  /// Discards the current confirmPending candidates. Nothing was persisted
  /// yet for this attempt (approve() is the only thing that persists), so
  /// there is nothing to clean up beyond the in-progress preview — a prior
  /// approval's approvedPackageId/preApplySnapshot/rollback state is
  /// preserved, exactly like generate().
  void cancel() => state = state.copyWith(
        phase: RoomAutoPeqPhase.idle,
        candidates: const [],
        clearError: true,
      );

  /// User-approved: builds the write plan with a fresh, per-approval-unique
  /// packageId, captures the CURRENT (not generation-time) project
  /// tuningState as the pre-apply rollback baseline, persists the
  /// DspExportPackage into exportState (same store method + shape
  /// guided_ai_screen.dart already uses), and returns true so the caller can
  /// navigate to Deploy. Zero hardware write happens here — only Deploy
  /// tab's own HardwareApplyFlow, on an explicit further user action, ever
  /// writes.
  Future<bool> approve() async {
    if (state.phase != RoomAutoPeqPhase.confirmPending) return false;
    final packageId =
        'room-auto-peq-$projectId-${DateTime.now().microsecondsSinceEpoch}';
    final built = RoomAutoPeq.buildWritePlan(
      projectId: projectId,
      packageId: packageId,
      candidates: state.candidates,
    );
    if (built == null) {
      state = state.copyWith(
          phase: RoomAutoPeqPhase.noChange, error: '적용할 보정이 없습니다.');
      return false;
    }
    final (package, _) = built;
    final project = _project;
    if (project == null) return false;

    // Captured fresh, right now — not from generate() time, which may be
    // stale if other tuning changed in between. This is Room's pre-apply
    // rollback baseline: the exact PEQ/XO/gain/delay/mute/phase state the
    // project was in immediately before this approval.
    final snapshot = project.tuningState;

    final updated = project.exportState.copyWith(
      packages: [
        ...project.exportState.packages.where((p) => p.id != package.id),
        package,
      ],
      activePackageId: package.id,
    );
    await _ref
        .read(proProjectStoreProvider.notifier)
        .updateExportState(projectId, updated);
    state = state.copyWith(
      phase: RoomAutoPeqPhase.approved,
      approvedPackageId: packageId,
      preApplySnapshot: snapshot,
      clearError: true,
    );
    return true;
  }

  /// Builds and persists a rollback DspExportPackage/HardwareWritePlan from
  /// the pre-apply snapshot captured by the most recent approve() call,
  /// restoring exactly the Woofer PEQ slots Room Auto PEQ touched. Routes
  /// through the same exportState -> Deploy -> HardwareApplyFlow path as a
  /// normal correction — no direct write happens here, and none of it is
  /// automatic: the caller must still navigate to Deploy and approve there.
  ///
  /// Fail-closed: returns false (no package built, no store write) when
  /// there is no snapshot to roll back to, or nothing was actually changed
  /// by the approved candidates.
  Future<bool> requestRollback() async {
    final snapshot = state.preApplySnapshot;
    final candidates = state.candidates;
    if (snapshot == null || candidates.isEmpty) {
      state = state.copyWith(
        error: '되돌릴 이전 상태 스냅샷이 없습니다 — Room Auto PEQ를 승인한 적이 없거나 세션이 재시작되었습니다.',
      );
      return false;
    }
    final rollbackPackageId =
        'room-rollback-$projectId-${DateTime.now().microsecondsSinceEpoch}';
    final built = RoomAutoPeq.buildRollbackPlan(
      projectId: projectId,
      packageId: rollbackPackageId,
      approvedCandidates: candidates,
      preApplySnapshot: snapshot,
    );
    if (built == null) {
      state = state.copyWith(error: '되돌릴 변경 사항이 없습니다.');
      return false;
    }
    final (package, _) = built;
    final project = _project;
    if (project == null) return false;
    final updated = project.exportState.copyWith(
      packages: [
        ...project.exportState.packages.where((p) => p.id != package.id),
        package,
      ],
      activePackageId: package.id,
    );
    await _ref
        .read(proProjectStoreProvider.notifier)
        .updateExportState(projectId, updated);
    state = state.copyWith(
      rollbackPhase: RoomRollbackPhase.approved,
      rollbackApprovedPackageId: rollbackPackageId,
      clearError: true,
    );
    return true;
  }
}
