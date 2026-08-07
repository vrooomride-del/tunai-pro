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
import '../../../core/measurement/measurement_capture_gate.dart';
import '../../../core/measurement/measurement_capture_presentation.dart';
import '../../../core/measurement/measurement_capture_preflight.dart';
import '../../../core/measurement/measurement_capture_provenance.dart';
import '../../../core/measurement/measurement_preview_acceptance_gate.dart';
import '../../../core/measurement/measurement_quality_snapshot.dart';
import '../../../core/measurement/measurement_warning_acknowledgement.dart';
import '../../../core/orchestrator/room_after_capture_gate.dart';
import '../../../core/orchestrator/room_after_gate.dart';
import '../../../core/orchestrator/room_before_after_comparison_gate.dart';
import '../../../core/orchestrator/room_closed_loop.dart';
import '../../../core/pro_acoustic_data.dart'
    show
        AcousticFileType,
        MeasurementDataPoint,
        MeasurementDataSource,
        ParsedMeasurementData;
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

  /// The identity/actual-format snapshot pinned the moment THIS preview was
  /// captured (Phase 3-D3A-2) — see LiveMeasurementState.capturedProvenance
  /// for the identical rationale.
  final MeasurementCaptureProvenance? capturedProvenance;

  /// Phase 3-D3B — same rationale as LiveMeasurementState
  /// .capturedQualitySnapshot: pinned at capture time alongside
  /// [capturedProvenance] (same provenance instance embedded inside).
  final MeasurementQualitySnapshot? capturedQualitySnapshot;

  final String? error;

  /// The most recent capture-gate verdict, recomputed by [capture]'s
  /// preflight. Rendered by the UI so the button state and the controller's
  /// refusal reason are literally the same value (Phase 3-D3A-1 §7).
  final MeasurementCaptureGateResult? captureGate;

  /// Populated exactly once, the moment After reaches 2/2 — never
  /// re-evaluated afterward (see accept()'s transition guard).
  final RoomClosedLoopResult? closedLoopResult;

  /// The provenance verdict computed at that same 2/2 transition (Phase
  /// 3-D3C-2). When `canEvaluate` is false, [closedLoopResult] is
  /// deliberately null and the UI must render THIS instead — a blocked
  /// comparison is a distinct state from a "worsened" verdict.
  final RoomBeforeAfterComparisonGateResult? closedLoopComparison;

  /// The most recent DUAL (hardware AND measurement) gate verdict from
  /// [capture]'s After-mode preflight (Phase 3-D3A-3). Null in Before mode —
  /// Before never requires the hardware condition, so [captureGate] alone
  /// (the measurement-only verdict) is authoritative there. The UI renders
  /// THIS instead of separately AND-ing hardwareGate/measurementGate itself.
  final RoomAfterCaptureGateResult? afterCaptureGate;

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
    this.capturedProvenance,
    this.capturedQualitySnapshot,
    this.error,
    this.captureGate,
    this.closedLoopResult,
    this.closedLoopComparison,
    this.afterCaptureGate,
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
    MeasurementCaptureProvenance? capturedProvenance,
    MeasurementQualitySnapshot? capturedQualitySnapshot,
    String? error,
    bool clearError = false,
    MeasurementCaptureGateResult? captureGate,
    RoomClosedLoopResult? closedLoopResult,
    RoomBeforeAfterComparisonGateResult? closedLoopComparison,
    RoomAfterCaptureGateResult? afterCaptureGate,
    bool clearAfterCaptureGate = false,
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
        capturedProvenance: clearCapturedResponse
            ? null
            : (capturedProvenance ?? this.capturedProvenance),
        capturedQualitySnapshot: clearCapturedResponse
            ? null
            : (capturedQualitySnapshot ?? this.capturedQualitySnapshot),
        error: clearError ? null : (error ?? this.error),
        captureGate: captureGate ?? this.captureGate,
        closedLoopResult: closedLoopResult ?? this.closedLoopResult,
        closedLoopComparison: closedLoopComparison ?? this.closedLoopComparison,
        afterCaptureGate: clearAfterCaptureGate
            ? null
            : (afterCaptureGate ?? this.afterCaptureGate),
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

  /// Session-scoped only, deliberately NOT persisted on ProProject: a
  /// warning acknowledgement must never survive an app restart and quietly
  /// re-authorise a capture the user agreed to in an earlier session. It is
  /// also invalidated automatically by any project/profile/device/generation
  /// change, because the gate re-checks [MeasurementWarningAcknowledgement
  /// .covers] on every evaluation rather than trusting a stored flag.
  MeasurementWarningAcknowledgement? _warningAck;

  MeasurementWarningAcknowledgement? get warningAcknowledgement => _warningAck;

  MeasurementCapturePreflight get _preflight => MeasurementCapturePreflight(
        inputDeviceService:
            _ref.read(mic.micMeasurementProvider.notifier).inputDeviceService,
      );

  /// Records the user's explicit "I understand, measure anyway" for exactly
  /// the warnings [gate] raised, bound to the chain identity it was raised
  /// under. Never called automatically — only from an explicit UI action.
  /// No-op if the verdict has blockers (a warning ack can never override a
  /// blocker) or raised no warnings at all.
  void acknowledgeWarnings(MeasurementCaptureGateResult gate) {
    if (gate.blockers.isNotEmpty || gate.warnings.isEmpty) return;
    final project = _project;
    if (project == null || gate.activeGenerationId == null) return;
    _warningAck = MeasurementWarningAcknowledgement(
      projectId: project.id,
      profileIdentity: gate.profileIdentity,
      deviceIdentity: gate.deviceIdentity ?? '',
      readinessGenerationId: gate.activeGenerationId!,
      warningCodes: gate.warningCodes,
      acknowledgedAt: DateTime.now(),
    );
  }

  /// Fresh runtime evaluation — permission and device enumeration are
  /// re-read here, never taken from whatever the UI cached at render time.
  Future<MeasurementCaptureGateResult> evaluateCaptureGate() =>
      _preflight.evaluate(project: _project, acknowledgement: _warningAck);

  /// Fresh hardware-write gate — identical evaluation [_afterGate] already
  /// performs for the mode-entry checks, exposed here so both the UI and
  /// [capture]'s own preflight read the SAME fresh computation rather than
  /// each re-deriving it.
  RoomAfterGateResult get _hardwareGate {
    final approvedPackageId =
        _ref.read(roomAutoPeqControllerProvider(projectId)).approvedPackageId;
    // Phase 3-D3A-3 §11 (rollback identity risk): this MUST always be the
    // correction's approvedPackageId, never rollbackApprovedPackageId.
    // RoomAfterGate.evaluate is deliberately generic to both purposes (see
    // its own doc comment — auto_peq_tab.dart's rollback-status indicator
    // legitimately calls it with the rollback id), so nothing inside the
    // gate itself can tell them apart; today's separation is entirely this
    // call site reading the right field. A rollback's hardware result must
    // never be misread as evidence a fresh correction is ready for After
    // measurement — this assertion is the guard against a future "harmless"
    // simplification (e.g. `approvedPackageId ?? rollbackApprovedPackageId`)
    // silently reopening that hole.
    assert(
      approvedPackageId == null ||
          !approvedPackageId.startsWith('room-rollback-'),
      '_hardwareGate must read the CORRECTION approvedPackageId, not a '
      'rollback package id — see Phase 3-D3A-3 §11.',
    );
    return RoomAfterGate.evaluate(
      approvedPackageId: approvedPackageId,
      lastResult: _ref.read(lastHardwareWriteResultProvider),
    );
  }

  /// Phase 3-D3A-3 — the composite Room After dual gate (hardware AND
  /// measurement), both evaluated FRESH on every call. This is what
  /// [capture] itself checks in After mode — never only the measurement
  /// gate — and what the UI should render for After's Capture control
  /// instead of separately AND-ing the two gates itself.
  Future<RoomAfterCaptureGateResult> evaluateAfterCaptureGate() async {
    final hardwareGate = _hardwareGate;
    final measurementGate = await evaluateCaptureGate();
    return RoomAfterCaptureGate.evaluate(
      hardwareGate: hardwareGate,
      measurementGate: measurementGate,
    );
  }

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

  RoomAfterGateResult get _afterGate => _hardwareGate;

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

    final isAfter = state.mode == RoomMeasurementPhase.after;
    MeasurementCaptureGateResult measurementGate;
    RoomAfterCaptureGateResult? afterGate;

    if (isAfter) {
      // Dual preflight (Phase 3-D3A-3 §5/§6): re-evaluate BOTH the hardware
      // gate and the measurement gate FRESH, right here, before any
      // recorder/player/BLE-warmup work — never trust whatever setMode(after)
      // / startNewAfterSession() established earlier. A direct capture()
      // call while already in After mode is gated exactly as strictly as
      // going through the UI toggle; the mode being `after` is never itself
      // sufficient authority.
      afterGate = await evaluateAfterCaptureGate();
      measurementGate = afterGate.measurementGate;
      if (!afterGate.canCapture) {
        state = state.copyWith(
          phase: RoomMeasurementPhaseUi.ready,
          captureGate: measurementGate,
          afterCaptureGate: afterGate,
          error: afterGate.primaryBlocker?.message ?? '측정을 시작할 수 없습니다.',
        );
        return;
      }
    } else {
      // Before mode never requires the hardware condition (Phase 3-D3A-3
      // §5) — identical fail-closed measurement-only gate as before.
      measurementGate = await evaluateCaptureGate();
      if (!measurementGate.canCapture) {
        state = state.copyWith(
          phase: RoomMeasurementPhaseUi.ready,
          captureGate: measurementGate,
          clearAfterCaptureGate: true,
          error: measurementGate.requiresExplicitWarningAcknowledgement
              ? '측정 전 경고 확인이 필요합니다.'
              : (measurementGate.primaryBlocker?.message ?? '측정을 시작할 수 없습니다.'),
        );
        return;
      }
    }

    state = state.copyWith(
      phase: RoomMeasurementPhaseUi.capturing,
      captureGate: measurementGate,
      afterCaptureGate: afterGate,
      clearAfterCaptureGate: !isAfter,
      clearError: true,
    );

    // Pinned NOW — see LiveMeasurementController.capture()'s identical
    // rationale (Phase 3-D3A-2 §5).
    final projectAtCapture = _project;
    final profile = projectAtCapture?.selectedMicrophoneProfile;
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

    // Same shared-instance rationale as LiveMeasurementController.capture()
    // (Phase 3-D3B §3).
    final provenanceAtCapture = projectAtCapture != null
        ? MeasurementCaptureProvenanceBuilder.build(
            project: projectAtCapture,
            actualSampleRate: micState.actualSampleRate,
            actualChannelCount: micState.actualChannelCount,
          )
        : null;
    final readinessAtCapture = projectAtCapture?.currentSetupReadiness;
    final qualitySnapshotAtCapture =
        (provenanceAtCapture != null && readinessAtCapture != null)
            ? MeasurementQualitySnapshotBuilder.build(
                provenance: provenanceAtCapture,
                readiness: readinessAtCapture,
              )
            : null;

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
      capturedProvenance: provenanceAtCapture,
      capturedQualitySnapshot: qualitySnapshotAtCapture,
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

    // Accept-time provenance gate (Phase 3-D3A-2): identical rationale to
    // LiveMeasurementController.accept() — supersedes the earlier Phase 3-C
    // profileChecksum-only stale guard with the full identity +
    // actual-WAV-format comparison.
    final acceptance = MeasurementPreviewAcceptanceGate.evaluate(
      provenance: state.capturedProvenance,
      currentProject: _project,
    );
    if (!acceptance.canAccept) {
      state = state.copyWith(
        phase: RoomMeasurementPhaseUi.ready,
        clearCapturedResponse: true,
        error: measurementPreviewAcceptanceBlockerText(
            acceptance.primaryBlocker!.code),
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
      qualitySnapshot: state.capturedQualitySnapshot,
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
    RoomBeforeAfterComparisonGateResult? comparison;
    if (state.mode == RoomMeasurementPhase.after &&
        !wasCompleteBefore &&
        updatedSnapshot.isComplete) {
      // OUTERMOST provenance gate (Phase 3-D3C-2 §5). A Before/After pair
      // that is not provenance-comparable is not a worse or better result —
      // it is not a result. Blocking here is what guarantees
      // RoomClosedLoopEvaluator (and therefore CorrectionCycleEvaluator)
      // never runs on it, so no improved/worsened verdict, no next-cycle
      // suggestion and no rollback recommendation can be produced from a
      // meaningless comparison. The pre-apply rollback snapshot is left
      // untouched, so the user can simply re-measure After and get a valid
      // comparison.
      comparison = RoomBeforeAfterComparisonGate.evaluateSnapshots(
        before: currentRoom.before,
        after: updatedRoom.after,
      );
      if (comparison.canEvaluate) {
        evaluation = RoomClosedLoopEvaluator.evaluate(
          projectId: projectId,
          before: currentRoom.before,
          after: updatedRoom.after,
        );
      }
    }

    _ref.read(mic.micMeasurementProvider.notifier).reset();
    state = state.copyWith(
      stepIndex: state.stepIndex + 1,
      phase: RoomMeasurementPhaseUi.idle,
      clearCapturedResponse: true,
      clearError: true,
      closedLoopResult: evaluation,
      closedLoopComparison: comparison,
    );
  }

  ParsedMeasurementData _toParsedMeasurementData({
    required List<Map<String, double>> calibrated,
    required List<Map<String, double>> raw,
    required CalibrationStatus calibrationStatus,
    String? calibrationCurveChecksum,
    MeasurementMicrophoneSnapshot? microphoneSnapshot,
    MeasurementQualitySnapshot? qualitySnapshot,
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
      qualitySnapshot: qualitySnapshot,
      source: MeasurementDataSource.liveCapture,
    );
  }
}
