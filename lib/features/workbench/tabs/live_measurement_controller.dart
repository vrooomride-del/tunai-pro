// Live measurement session — sequences existing engines, writes into the
// existing project store. No new measurement engine, no new Auto PEQ engine,
// no direct DSP/transport write.
//
// Channel isolation is manual for this phase: there is no per-channel
// mute/solo primitive in the ADAU1701 ICP5 write path (only a master mute),
// and adding one — or faking isolation via writeOutputGain — was explicitly
// ruled out. The user isolates the channel under test themselves (Hardware
// tab / speaker wiring) before pressing "준비 완료".
//
// Reuses, unmodified:
//   - MicMeasurementController.startMeasurement() for playback+record+FFT
//   - ProProjectStoreNotifier.updateAcousticState() for Before storage
//   - FullSystemAfterFrdInput + ProGuidedAiController.submitAfterFourChannelFrd
//     for After storage (identical sequence to guided_ai_screen.dart's
//     file-import path — this just feeds it live captures instead)
//   - ProGuidedAiController.frdReadiness() for readiness — never re-derived

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/acoustic/acoustic_apply_engine.dart'
    show TuningApplyStatus;
import '../../../core/calibration/calibration_types.dart';
import '../../../core/deploy/pro_hardware_context_provider.dart';
import '../../../core/orchestrator/full_system_after_frd_input.dart';
import '../../../core/orchestrator/pro_guided_ai_controller.dart';
import '../../../core/orchestrator/pro_guided_ai_state.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_correction_cycle.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
// MeasurementStatus collides with pro_acoustic_data.dart's DriverChannel
// status enum of the same name — prefix this import and qualify the one
// symbol actually needed from it (MicMeasurementController's recording
// status), everything else here is unprefixed pro_acoustic_data.dart.
import '../../mic/mic_measurement_controller.dart' as mic;

// ── Types ─────────────────────────────────────────────────────────────────────

enum LiveMeasurementMode { before, after }

enum LiveMeasurementPhase {
  /// Waiting for the user to confirm manual channel isolation.
  idle,

  /// User confirmed isolation; Capture is enabled.
  ready,

  /// MicMeasurementController is running (playback/record/FFT).
  capturing,

  /// Capture finished; preview shown, Accept/Retry available.
  captured,
}

/// Which physical path pink-noise playback will go out over. Reuses the
/// same active-context signal the Deploy path already established this
/// session (activeAdau1701ContextProvider != null => BLE is the live ICP5
/// connection) — no new detection mechanism.
enum TransportKind { ble, usb, local }

class LiveMeasurementState {
  final LiveMeasurementMode mode;
  final int channelIndex;
  final LiveMeasurementPhase phase;

  /// Calibrated response shown in the preview — same field/meaning as
  /// before Phase 3-B (numerically identical to [capturedRawResponse] when
  /// no calibration curve was in effect).
  final List<Map<String, double>>? capturedResponse;
  final List<Map<String, double>>? capturedRawResponse;
  final CalibrationStatus? capturedCalibrationStatus;
  final String? capturedCalibrationCurveChecksum;
  final List<String> capturedCalibrationWarnings;
  final MeasurementMicrophoneSnapshot? capturedMicrophoneSnapshot;

  final String? error;
  final CorrectionCycle? lastCompletedCycle;
  final String? submitBlockedReason;

  const LiveMeasurementState({
    this.mode = LiveMeasurementMode.before,
    this.channelIndex = 0,
    this.phase = LiveMeasurementPhase.idle,
    this.capturedResponse,
    this.capturedRawResponse,
    this.capturedCalibrationStatus,
    this.capturedCalibrationCurveChecksum,
    this.capturedCalibrationWarnings = const [],
    this.capturedMicrophoneSnapshot,
    this.error,
    this.lastCompletedCycle,
    this.submitBlockedReason,
  });

  LiveMeasurementState copyWith({
    LiveMeasurementMode? mode,
    int? channelIndex,
    LiveMeasurementPhase? phase,
    List<Map<String, double>>? capturedResponse,
    bool clearCapturedResponse = false,
    List<Map<String, double>>? capturedRawResponse,
    CalibrationStatus? capturedCalibrationStatus,
    String? capturedCalibrationCurveChecksum,
    List<String>? capturedCalibrationWarnings,
    MeasurementMicrophoneSnapshot? capturedMicrophoneSnapshot,
    String? error,
    bool clearError = false,
    CorrectionCycle? lastCompletedCycle,
    String? submitBlockedReason,
    bool clearSubmitBlockedReason = false,
  }) =>
      LiveMeasurementState(
        mode: mode ?? this.mode,
        channelIndex: channelIndex ?? this.channelIndex,
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
        lastCompletedCycle: lastCompletedCycle ?? this.lastCompletedCycle,
        submitBlockedReason: clearSubmitBlockedReason
            ? null
            : (submitBlockedReason ?? this.submitBlockedReason),
      );
}

// ── Controller ────────────────────────────────────────────────────────────────

final liveMeasurementControllerProvider = StateNotifierProvider.family<
    LiveMeasurementController, LiveMeasurementState, String>(
  (ref, projectId) => LiveMeasurementController(ref, projectId),
);

class LiveMeasurementController extends StateNotifier<LiveMeasurementState> {
  final Ref _ref;
  final String projectId;
  FullSystemAfterFrdInput? _afterInput;

  LiveMeasurementController(this._ref, this.projectId)
      : super(const LiveMeasurementState());

  ProProject? get _project => _ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == projectId)
      .firstOrNull;

  /// The project's actual configured channels, in the project's own order.
  /// Never a hardcoded 4-id list — whatever the project defines is what
  /// gets measured.
  List<DriverChannel> get channels =>
      _project?.acousticState.driverChannels ?? const [];

  DriverChannel? get currentChannel {
    final list = channels;
    if (state.channelIndex < 0 || state.channelIndex >= list.length) {
      return null;
    }
    return list[state.channelIndex];
  }

  bool get isSequenceComplete =>
      channels.isNotEmpty && state.channelIndex >= channels.length;

  /// After-mode channels accepted so far. Empty outside After mode.
  Map<String, ParsedMeasurementData> get afterByChannel =>
      _afterInput?.afterByChannel ?? const {};

  List<String> get missingAfterChannelIds => [
        for (final ch in channels)
          if (!afterByChannel.containsKey(ch.id)) ch.id,
      ];

  TransportKind get transportKind {
    if (_ref.read(activeAdau1701ContextProvider) != null) {
      return TransportKind.ble;
    }
    final usb = _ref.read(adau1701Icp5UsbContextProvider);
    if (usb.isReady) return TransportKind.usb;
    return TransportKind.local;
  }

  bool get bleWarmupNeeded => transportKind == TransportKind.ble;

  /// True only once hardware has actually been written — not merely once
  /// the Guided AI candidate apply succeeded locally.
  ///
  /// `applyResult.status == ok` only means the local PEQ tuning state was
  /// updated; the real DSP write happens later and separately, when the
  /// user approves+applies in Deploy tab's HardwareApplyFlow. Gating on the
  /// local apply alone would let a user "re-measure" a room that was never
  /// actually changed on the speaker — Deploy tab already avoids this exact
  /// trap for its own file-import After-FRD button (it checks
  /// `_lastHardwareResult.allWritten`); this mirrors that same check via
  /// lastHardwareWriteResultProvider so both paths agree.
  bool get afterModeAvailable {
    final aiState = _ref.read(guidedAiProvider);
    final locallyApplied = aiState is ProGuidedAiCompleted &&
        aiState.applyResult?.status == TuningApplyStatus.ok;
    if (!locallyApplied) return false;
    final hwResult = _ref.read(lastHardwareWriteResultProvider);
    return hwResult?.allWritten == true;
  }

  /// Human-readable reason After mode is unavailable, for display next to
  /// the disabled toggle. Null when it's available.
  String? get afterModeBlockedReason {
    final aiState = _ref.read(guidedAiProvider);
    final locallyApplied = aiState is ProGuidedAiCompleted &&
        aiState.applyResult?.status == TuningApplyStatus.ok;
    if (!locallyApplied) return 'Guided AI Apply 완료 후 사용 가능';
    final hwResult = _ref.read(lastHardwareWriteResultProvider);
    if (hwResult == null) {
      return 'Deploy 탭에서 하드웨어에 실제로 적용해야 사용 가능';
    }
    if (!hwResult.allWritten) {
      return hwResult.executed
          ? 'Deploy 실패 — ${hwResult.failedCount}개 작업 실패. Deploy 탭에서 다시 시도하세요.'
          : 'Deploy가 실행되지 않았습니다 — ${hwResult.rejectionReason ?? "Deploy 탭 확인 필요"}';
    }
    return null;
  }

  // ── Mode / sequencing ─────────────────────────────────────────────────────

  void setMode(LiveMeasurementMode mode) {
    if (mode == state.mode && state.channelIndex == 0) return;
    if (mode == LiveMeasurementMode.after) {
      // Fail closed here too, not just at the UI toggle: a caller must not
      // be able to reach After mode by calling this directly when hardware
      // was never actually written.
      if (!afterModeAvailable) return;
      final project = _project;
      if (project == null) return;
      _afterInput = FullSystemAfterFrdInput(project);
      // Mirror guided_ai_screen.dart's _beginAfterFrd: entering After mode
      // here also moves the shared Guided AI controller into
      // awaitingAfterFrd if it isn't already — same controller, same call,
      // just triggered from this tab instead of GuidedAiScreen's button.
      final aiState = _ref.read(guidedAiProvider);
      if (aiState is ProGuidedAiCompleted &&
          aiState.applyResult?.status == TuningApplyStatus.ok &&
          aiState.loopPhase != ProClosedLoopPhase.awaitingAfterFrd) {
        _ref.read(guidedAiProvider.notifier).enterAwaitingAfterFrd();
      }
    } else {
      _afterInput = null;
    }
    state = LiveMeasurementState(mode: mode);
  }

  void markReady() {
    if (currentChannel == null) return;
    state = state.copyWith(phase: LiveMeasurementPhase.ready, clearError: true);
  }

  // ── Capture / Retry / Accept ─────────────────────────────────────────────

  Future<void> capture() async {
    if (state.phase != LiveMeasurementPhase.ready || currentChannel == null) {
      return;
    }
    state =
        state.copyWith(phase: LiveMeasurementPhase.capturing, clearError: true);

    final profile = _project?.selectedMicrophoneProfile;
    final micNotifier = _ref.read(mic.micMeasurementProvider.notifier);
    micNotifier.reset();
    await micNotifier.startMeasurement(
      bleWarmup: bleWarmupNeeded,
      calibrationCurve: profile?.calibrationCurve,
    );
    final micState = _ref.read(mic.micMeasurementProvider);

    if (micState.status == mic.MeasurementStatus.error) {
      state = state.copyWith(
        phase: LiveMeasurementPhase.ready,
        error: micState.error ?? '측정 실패',
      );
      return;
    }
    if (micState.frequencyResponse.isEmpty) {
      state = state.copyWith(
        phase: LiveMeasurementPhase.ready,
        error: '측정 데이터가 비어 있습니다. 다시 시도하세요.',
      );
      return;
    }

    state = state.copyWith(
      phase: LiveMeasurementPhase.captured,
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

  /// Discards the current capture. Nothing is persisted — the project is
  /// untouched by a retry.
  void retry() {
    state = state.copyWith(
      phase: LiveMeasurementPhase.ready,
      clearCapturedResponse: true,
      clearError: true,
    );
  }

  Future<void> accept() async {
    final response = state.capturedResponse;
    final channel = currentChannel;
    if (response == null || channel == null) return;

    // Stale-preview guard: if the selected microphone profile changed after
    // this preview was captured (e.g. the user edited/switched profiles in
    // the Profile Manager while a preview was pending), the preview's
    // calibration no longer reflects the CURRENTLY selected profile. Reject
    // the accept and force a fresh capture rather than silently persisting
    // data captured under a profile that is no longer selected.
    final capturedChecksum = state.capturedMicrophoneSnapshot?.profileChecksum;
    final currentChecksum = _project?.selectedMicrophoneProfile?.checksum;
    if (capturedChecksum != currentChecksum) {
      state = state.copyWith(
        phase: LiveMeasurementPhase.ready,
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

    if (state.mode == LiveMeasurementMode.before) {
      await _saveBefore(channel.id, data);
    } else {
      final input = _afterInput;
      if (input == null) return;
      try {
        input.add(channelId: channel.id, afterFrd: data);
      } catch (e) {
        state = state.copyWith(error: '$e');
        return;
      }
      if (input.isComplete) {
        await _submitAfterComplete(input);
      }
    }

    _ref.read(mic.micMeasurementProvider.notifier).reset();
    state = state.copyWith(
      channelIndex: state.channelIndex + 1,
      phase: LiveMeasurementPhase.idle,
      clearCapturedResponse: true,
      clearError: true,
    );
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Writes [data] into exactly channel [channelId]'s frdData via the
  /// existing updateAcousticState() path — the same mechanism import_tab.dart
  /// already uses for file-imported FRD. All other channels and every other
  /// project field (tuningState/PEQ/XO/gain/delay, protectionState, etc.) are
  /// untouched because they live outside acousticState entirely.
  Future<void> _saveBefore(String channelId, ParsedMeasurementData data) async {
    final project = _project;
    if (project == null) return;
    final acoustic = project.acousticState;
    final updatedChannels = acoustic.driverChannels.map((ch) {
      if (ch.id != channelId) return ch;
      return ch.copyWith(
        frdData: data,
        measurementStatus: ch.hasZma
            ? MeasurementStatus.validated
            : MeasurementStatus.imported,
      );
    }).toList();
    await _ref.read(proProjectStoreProvider.notifier).updateAcousticState(
          projectId,
          acoustic.copyWith(driverChannels: updatedChannels),
        );
  }

  /// Same sequence as guided_ai_screen.dart's _importAfterFrd once its input
  /// is complete — submitAfterFourChannelFrd then addCorrectionCycle. Not
  /// duplicated logic, the identical two calls with a live-sourced input.
  Future<void> _submitAfterComplete(FullSystemAfterFrdInput input) async {
    final beforeProject = input.beforeProject;
    final cycle =
        _ref.read(guidedAiProvider.notifier).submitAfterFourChannelFrd(
              beforeProject: beforeProject,
              afterProject: input.buildAfterProject(),
              deployedTuningState: beforeProject.tuningState,
              cycleNumber: beforeProject.correctionCycles.length + 1,
              safetyPassed: beforeProject.safetyStatus == SafetyStatus.verified,
              beforeEvidenceRefs: input.beforeEvidenceRefs,
              afterEvidenceRefs: input.afterEvidenceRefs,
            );
    if (cycle == null) {
      state = state.copyWith(
        submitBlockedReason: '적용 결과가 아직 준비되지 않아 제출할 수 없습니다.',
      );
      return;
    }
    await _ref
        .read(proProjectStoreProvider.notifier)
        .addCorrectionCycle(projectId, cycle);
    state = state.copyWith(
      lastCompletedCycle: cycle,
      clearSubmitBlockedReason: true,
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
      id: 'live_${now.microsecondsSinceEpoch}',
      sourceFileName: 'Live Measurement '
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
