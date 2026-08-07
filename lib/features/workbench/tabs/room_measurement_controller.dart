// Phase 2 — Stereo Room Measurement session controller.
//
// Sequences the existing MicMeasurementController.startRoomMeasurement()
// (reused, unmodified engine — only the stereo pink-noise WAV changed) for
// exactly two steps: Left System, then Right System. Writes into
// ProProject.roomState (before/after leftSystemFrd/rightSystemFrd) — never
// into driverChannels[i].frdData, which stays the Factory per-driver path's
// exclusive territory.
//
// No new engine, no DSP/transport write here — same boundary
// LiveMeasurementController already established for the Factory path.
//
// This L/R-separate structure is intentional and fixed — do not change it to
// a 4-channel or per-band (Tweeter/Mid/Woofer L+R together) simultaneous
// capture scheme; see the rationale and the Stereo Final Verification P2
// note (a distinct, evaluation-only, L+R-together capability that never
// feeds Auto PEQ or a DSP write) at the top of
// lib/core/orchestrator/room_auto_peq.dart.
//
// Safety audit follow-up: setMode(after) previously had no gate at all —
// unlike LiveMeasurementController.afterModeAvailable, nothing here checked
// whether Room's correction had actually reached hardware. It now reuses
// RoomAfterGate (shared with the rollback flow) against
// RoomAutoPeqController's approvedPackageId and the same
// lastHardwareWriteResultProvider the Factory path already relies on —
// fail-closed both at the UI (room_measurement_section.dart disables the
// toggle) and here at the method level, so calling setMode(after) directly
// cannot bypass it either.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calibration/calibration_types.dart';
import '../../../core/orchestrator/room_after_gate.dart';
import '../../../core/orchestrator/room_closed_loop.dart';
import '../../../core/pro_acoustic_data.dart'
    show AcousticFileType, MeasurementDataPoint, ParsedMeasurementData;
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/room_measurement_data.dart';
import '../../mic/mic_measurement_controller.dart' as mic;
import 'live_measurement_controller.dart' show TransportKind;
import '../../../core/deploy/pro_hardware_context_provider.dart';
import 'room_auto_peq_controller.dart';

// ── Types ─────────────────────────────────────────────────────────────────────

enum RoomMeasurementPhaseUi {
  /// Waiting for the user to confirm they're ready to measure this side.
  idle,

  /// User confirmed; Capture is enabled.
  ready,

  /// MicMeasurementController is running (playback/record/FFT).
  capturing,

  /// Capture finished; preview shown, Accept/Retry available.
  captured,
}

class RoomMeasurementState {
  final RoomMeasurementPhase mode;
  final int stepIndex; // 0 = Left, 1 = Right
  final RoomMeasurementPhaseUi phase;
  final List<Map<String, double>>? capturedResponse;
  final List<Map<String, double>>? capturedRawResponse;
  final CalibrationStatus? capturedCalibrationStatus;
  final String? capturedCalibrationCurveChecksum;
  final List<String> capturedCalibrationWarnings;
  final MeasurementMicrophoneSnapshot? capturedMicrophoneSnapshot;
  final String? error;

  /// Populated exactly once, the moment After reaches 2/2 — never
  /// re-evaluated afterward (see accept()'s transition guard).
  final RoomClosedLoopResult? closedLoopResult;

  const RoomMeasurementState({
    this.mode = RoomMeasurementPhase.before,
    this.stepIndex = 0,
    this.phase = RoomMeasurementPhaseUi.idle,
    this.capturedResponse,
    this.capturedRawResponse,
    this.capturedCalibrationStatus,
    this.capturedCalibrationCurveChecksum,
    this.capturedCalibrationWarnings = const [],
    this.capturedMicrophoneSnapshot,
    this.error,
    this.closedLoopResult,
  });

  RoomMeasurementState copyWith({
    RoomMeasurementPhase? mode,
    int? stepIndex,
    RoomMeasurementPhaseUi? phase,
    List<Map<String, double>>? capturedResponse,
    bool clearCapturedResponse = false,
    List<Map<String, double>>? capturedRawResponse,
    CalibrationStatus? capturedCalibrationStatus,
    String? capturedCalibrationCurveChecksum,
    List<String>? capturedCalibrationWarnings,
    MeasurementMicrophoneSnapshot? capturedMicrophoneSnapshot,
    String? error,
    bool clearError = false,
    RoomClosedLoopResult? closedLoopResult,
  }) =>
      RoomMeasurementState(
        mode: mode ?? this.mode,
        stepIndex: stepIndex ?? this.stepIndex,
        phase: phase ?? this.phase,
        capturedResponse: clearCapturedResponse
            ? null
            : (capturedResponse ?? this.capturedResponse),
        capturedRawResponse: clearCapturedResponse
            ? null
            : (capturedRawResponse ?? this.capturedRawResponse),
        capturedCalibrationStatus: clearCapturedResponse
            ? null
            : (capturedCalibrationStatus ?? this.capturedCalibrationStatus),
        capturedCalibrationCurveChecksum: clearCapturedResponse
            ? null
            : (capturedCalibrationCurveChecksum ??
                this.capturedCalibrationCurveChecksum),
        capturedCalibrationWarnings: clearCapturedResponse
            ? const []
            : (capturedCalibrationWarnings ?? this.capturedCalibrationWarnings),
        capturedMicrophoneSnapshot: clearCapturedResponse
            ? null
            : (capturedMicrophoneSnapshot ?? this.capturedMicrophoneSnapshot),
        error: clearError ? null : (error ?? this.error),
        closedLoopResult: closedLoopResult ?? this.closedLoopResult,
      );
}

// ── Controller ────────────────────────────────────────────────────────────────

final roomMeasurementControllerProvider = StateNotifierProvider.family<
    RoomMeasurementController, RoomMeasurementState, String>(
  (ref, projectId) => RoomMeasurementController(ref, projectId),
);

class RoomMeasurementController extends StateNotifier<RoomMeasurementState> {
  final Ref _ref;
  final String projectId;

  RoomMeasurementController(this._ref, this.projectId)
      : super(const RoomMeasurementState());

  static const List<RoomSystemSide> steps = [
    RoomSystemSide.left,
    RoomSystemSide.right,
  ];

  ProProject? get _project => _ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == projectId)
      .firstOrNull;

  RoomSystemSide? get currentSide =>
      state.stepIndex >= 0 && state.stepIndex < steps.length
          ? steps[state.stepIndex]
          : null;

  bool get isSequenceComplete => state.stepIndex >= steps.length;

  RoomMeasurementSnapshot _snapshotFor(RoomMeasurementPhase mode) {
    final room =
        _project?.roomState ?? RoomMeasurementProjectState.createDefault();
    return mode == RoomMeasurementPhase.before ? room.before : room.after;
  }

  RoomMeasurementSnapshot get currentSnapshot => _snapshotFor(state.mode);

  TransportKind get transportKind {
    if (_ref.read(activeAdau1701ContextProvider) != null) {
      return TransportKind.ble;
    }
    final usb = _ref.read(adau1701Icp5UsbContextProvider);
    if (usb.isReady) return TransportKind.usb;
    return TransportKind.local;
  }

  bool get bleWarmupNeeded => transportKind == TransportKind.ble;

  // ── After-mode hardware gate ──────────────────────────────────────────────

  RoomAfterGateResult get _afterGate => RoomAfterGate.evaluate(
        approvedPackageId: _ref
            .read(roomAutoPeqControllerProvider(projectId))
            .approvedPackageId,
        lastResult: _ref.read(lastHardwareWriteResultProvider),
      );

  /// True only once Room Auto PEQ's approved correction has actually been
  /// written to hardware and DSP-readback-verified for THIS project's
  /// current plan — never merely "approved" or "Deploy tab opened".
  bool get afterModeAvailable => _afterGate.available;

  /// Human-readable reason After mode is unavailable, for display next to
  /// the disabled toggle. Null when it's available.
  String? get afterModeBlockedReason => _afterGate.blockedReason;

  /// Non-null once a full Before/After cycle has already been evaluated —
  /// setMode(after) refuses to silently re-enter in this state (see below).
  /// Only [startNewAfterSession] can begin a genuinely new After capture.
  String? get afterReentryBlockedReason {
    if (state.closedLoopResult == null) return null;
    if (!_snapshotFor(RoomMeasurementPhase.after).isComplete) return null;
    return '이미 평가된 After 측정이 있습니다 — 새로 측정하려면 "After 다시 측정"을 사용하세요.';
  }

  // ── Mode / sequencing ─────────────────────────────────────────────────────

  void setMode(RoomMeasurementPhase mode) {
    if (mode == state.mode && state.stepIndex == 0) return;
    if (mode == RoomMeasurementPhase.after) {
      // Fail closed here too, not just at the UI toggle: a caller must not
      // be able to reach After mode by calling this directly when hardware
      // was never actually written for the current Room correction.
      if (!afterModeAvailable) return;
      // A completed, already-evaluated cycle must not be silently reset by
      // re-tapping "After" — that used to reset stepIndex to 0 with no
      // feedback while roomState.after already held two complete, evaluated
      // captures. Route through startNewAfterSession() instead.
      if (afterReentryBlockedReason != null) return;
    }
    state = RoomMeasurementState(mode: mode);
  }

  /// The only way to begin a new After capture once a cycle has already been
  /// evaluated (state.closedLoopResult != null). Still subject to the same
  /// hardware gate as setMode(after) — a completed evaluation does not
  /// exempt a new attempt from proving a fresh, actually-applied correction.
  ///
  /// Also clears the PERSISTED roomState.after snapshot, not just the local
  /// controller state: leaving the old, already-complete After L/R pair in
  /// place would make accept()'s "just transitioned into 2/2" evaluation
  /// guard see the pair as already-complete on the very first new capture,
  /// silently skipping the new cycle's evaluation entirely (the same class
  /// of bug this method exists to fix, one layer deeper).
  Future<void> startNewAfterSession() async {
    if (!afterModeAvailable) return;
    final project = _project;
    if (project == null) return;
    await _ref.read(proProjectStoreProvider.notifier).updateRoomState(
          projectId,
          project.roomState.copyWith(after: RoomMeasurementSnapshot.empty),
        );
    state = const RoomMeasurementState(mode: RoomMeasurementPhase.after);
  }

  void markReady() {
    if (currentSide == null) return;
    state =
        state.copyWith(phase: RoomMeasurementPhaseUi.ready, clearError: true);
  }

  // ── Capture / Retry / Accept ─────────────────────────────────────────────

  Future<void> capture() async {
    if (state.phase != RoomMeasurementPhaseUi.ready || currentSide == null) {
      return;
    }
    state = state.copyWith(
        phase: RoomMeasurementPhaseUi.capturing, clearError: true);

    final profile = _project?.selectedMicrophoneProfile;
    final micNotifier = _ref.read(mic.micMeasurementProvider.notifier);
    micNotifier.reset();
    await micNotifier.startRoomMeasurement(
      leftActive: currentSide == RoomSystemSide.left,
      bleWarmup: bleWarmupNeeded,
      calibrationCurve: profile?.calibrationCurve,
    );
    final micState = _ref.read(mic.micMeasurementProvider);

    if (micState.status == mic.MeasurementStatus.error) {
      state = state.copyWith(
        phase: RoomMeasurementPhaseUi.ready,
        error: micState.error ?? '측정 실패',
      );
      return;
    }
    if (micState.frequencyResponse.isEmpty) {
      state = state.copyWith(
        phase: RoomMeasurementPhaseUi.ready,
        error: '측정 데이터가 비어 있습니다. 다시 시도하세요.',
      );
      return;
    }

    state = state.copyWith(
      phase: RoomMeasurementPhaseUi.captured,
      capturedResponse: micState.frequencyResponse,
      capturedRawResponse: micState.rawFrequencyResponse,
      capturedCalibrationStatus: micState.calibrationStatus,
      capturedCalibrationCurveChecksum: micState.calibrationCurveChecksum,
      capturedCalibrationWarnings: micState.calibrationWarnings,
      capturedMicrophoneSnapshot: profile != null
          ? MeasurementMicrophoneSnapshot.of(
              profile,
              sampleRate: mic.MicMeasurementController.sampleRate,
            )
          : null,
    );
  }

  /// Discards the current capture. Nothing is persisted — a retry never
  /// touches roomState.
  void retry() {
    state = state.copyWith(
      phase: RoomMeasurementPhaseUi.ready,
      clearCapturedResponse: true,
      clearError: true,
    );
  }

  Future<void> accept() async {
    final response = state.capturedResponse;
    final side = currentSide;
    if (response == null || side == null) return;

    // Stale-preview guard: identical rationale to
    // LiveMeasurementController.accept() — if the selected microphone
    // profile changed after this preview was captured, reject the accept
    // rather than persist data captured under a no-longer-selected profile.
    final capturedChecksum = state.capturedMicrophoneSnapshot?.profileChecksum;
    final currentChecksum = _project?.selectedMicrophoneProfile?.checksum;
    if (capturedChecksum != currentChecksum) {
      state = state.copyWith(
        phase: RoomMeasurementPhaseUi.ready,
        clearCapturedResponse: true,
        error: '측정 마이크 프로필이 변경되었습니다 — 다시 Capture하세요.',
      );
      return;
    }

    final data = _toParsedMeasurementData(
      calibrated: response,
      raw: state.capturedRawResponse ?? response,
      calibrationStatus:
          state.capturedCalibrationStatus ?? CalibrationStatus.legacyUnknown,
      calibrationCurveChecksum: state.capturedCalibrationCurveChecksum,
      microphoneSnapshot: state.capturedMicrophoneSnapshot,
    );
    final measurement = RoomSystemMeasurement(
      side: side,
      phase: state.mode,
      frd: data,
      capturedAt: DateTime.now(),
      sampleRate: mic.MicMeasurementController.sampleRate,
      source: RoomMeasurementSource.live,
      projectId: projectId,
    );

    final project = _project;
    if (project == null) return;
    final currentRoom = project.roomState;
    final wasCompleteBefore = _snapshotFor(state.mode).isComplete;
    final updatedSnapshot =
        _snapshotFor(state.mode).withSide(side, measurement);
    final updatedRoom = state.mode == RoomMeasurementPhase.before
        ? currentRoom.copyWith(before: updatedSnapshot)
        : currentRoom.copyWith(after: updatedSnapshot);
    await _ref
        .read(proProjectStoreProvider.notifier)
        .updateRoomState(projectId, updatedRoom);

    // Evaluate exactly once: only on the transition into After 2/2, never
    // on an already-complete pair (defensive — accept() is structurally
    // unreachable a third time per mode since currentSide becomes null once
    // stepIndex >= steps.length, but this guard makes the "evaluate exactly
    // once" contract explicit and independent of that).
    RoomClosedLoopResult? evaluation;
    if (state.mode == RoomMeasurementPhase.after &&
        !wasCompleteBefore &&
        updatedSnapshot.isComplete) {
      evaluation = RoomClosedLoopEvaluator.evaluate(
        projectId: projectId,
        before: currentRoom.before,
        after: updatedRoom.after,
      );
    }

    _ref.read(mic.micMeasurementProvider.notifier).reset();
    state = state.copyWith(
      stepIndex: state.stepIndex + 1,
      phase: RoomMeasurementPhaseUi.idle,
      clearCapturedResponse: true,
      clearError: true,
      closedLoopResult: evaluation,
    );
  }

  ParsedMeasurementData _toParsedMeasurementData({
    required List<Map<String, double>> calibrated,
    required List<Map<String, double>> raw,
    required CalibrationStatus calibrationStatus,
    String? calibrationCurveChecksum,
    MeasurementMicrophoneSnapshot? microphoneSnapshot,
  }) {
    final now = DateTime.now();
    List<MeasurementDataPoint> toPoints(List<Map<String, double>> src) => [
          for (final m in src)
            if (m['frequency'] != null)
              MeasurementDataPoint(
                  frequencyHz: m['frequency']!, magnitudeDb: m['db']),
        ];
    return ParsedMeasurementData(
      id: 'room_live_${now.microsecondsSinceEpoch}',
      sourceFileName: 'Room Live Measurement '
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}',
      fileType: AcousticFileType.frd,
      importedAt: now,
      points: toPoints(calibrated),
      rawPoints: toPoints(raw),
      microphoneSnapshot: microphoneSnapshot,
      calibrationStatus: calibrationStatus,
      calibrationCurveChecksum: calibrationCurveChecksum,
      calibrationAppliedAt: calibrationCurveChecksum != null ? now : null,
    );
  }
}
