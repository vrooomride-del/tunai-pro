import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/speaker_profile.dart';
import '../../core/profiles/system_profile.dart';
import '../../features/dsp/dsp_state.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fftea/fftea.dart';
import '../auth/auth_controller.dart' show authProvider;
import '../../core/akg/measurement_session.dart';
import '../../core/calibration/calibration_applicator.dart';
import '../../core/calibration/calibration_types.dart';
import '../../core/pro_acoustic_data.dart' show MeasurementDataPoint;
import '../../core/measurement/live_level_check.dart';
import '../../core/measurement/measurement_input_device.dart';
import '../../core/measurement/measurement_input_device_service.dart';
import '../../core/measurement/measurement_pcm_quality_analyzer.dart';
import '../../core/measurement/measurement_quality_model.dart';
import '../../core/measurement/measurement_quality_policy.dart';
import '../../core/measurement/measurement_setup_capture_result.dart';
import '../../core/measurement/measurement_wav_parser.dart';

enum MeasurementStatus { idle, playing, recording, analyzing, done, error }

class MicMeasurementState {
  final MeasurementStatus status;
  final String message;

  /// Calibrated response (or numerically identical to
  /// [rawFrequencyResponse] when no calibration curve was supplied) — same
  /// field name/shape/meaning every existing consumer already reads.
  final List<Map<String, double>> frequencyResponse;

  /// The response BEFORE calibration was applied. Always populated
  /// alongside [frequencyResponse] once a measurement completes.
  final List<Map<String, double>> rawFrequencyResponse;

  /// Null until a measurement completes. Never
  /// [CalibrationStatus.calibrated] unless a real curve actually covered the
  /// full range — see CalibrationApplicator.apply.
  final CalibrationStatus? calibrationStatus;
  final String? calibrationCurveChecksum;
  final List<String> calibrationWarnings;

  final Map<int, List<Map<String, double>>> channelResponses; // 채널별 측정
  final List<double?> recommendedCrossovers; // 추천 크로스오버 주파수
  final String? error;

  /// The ACTUAL sample rate / channel count read from the recorded WAV's own
  /// fmt chunk (Phase 3-D3A-2) — never the requested RecordConfig value.
  /// Defaults to the nominal production values so fakes/tests that stub
  /// [MicMeasurementController.startMeasurement]/[startRoomMeasurement]
  /// without touching a real WAV keep behaving as "nominal capture" rather
  /// than spuriously reporting a format mismatch; the real capture path
  /// (`_readAndParseRecordedWav`) always overwrites these with the value
  /// actually parsed from the recording.
  final int actualSampleRate;
  final int actualChannelCount;

  const MicMeasurementState({
    this.status = MeasurementStatus.idle,
    this.message = '',
    this.frequencyResponse = const [],
    this.rawFrequencyResponse = const [],
    this.calibrationStatus,
    this.calibrationCurveChecksum,
    this.calibrationWarnings = const [],
    this.channelResponses = const {},
    this.recommendedCrossovers = const [],
    this.error,
    this.actualSampleRate = MicMeasurementController.sampleRate,
    this.actualChannelCount = 1,
  });

  MicMeasurementState copyWith({
    MeasurementStatus? status,
    String? message,
    List<Map<String, double>>? frequencyResponse,
    List<Map<String, double>>? rawFrequencyResponse,
    CalibrationStatus? calibrationStatus,
    String? calibrationCurveChecksum,
    List<String>? calibrationWarnings,
    Map<int, List<Map<String, double>>>? channelResponses,
    List<double?>? recommendedCrossovers,
    String? error,
    int? actualSampleRate,
    int? actualChannelCount,
  }) =>
      MicMeasurementState(
        status: status ?? this.status,
        message: message ?? this.message,
        frequencyResponse: frequencyResponse ?? this.frequencyResponse,
        rawFrequencyResponse: rawFrequencyResponse ?? this.rawFrequencyResponse,
        calibrationStatus: calibrationStatus ?? this.calibrationStatus,
        calibrationCurveChecksum:
            calibrationCurveChecksum ?? this.calibrationCurveChecksum,
        calibrationWarnings: calibrationWarnings ?? this.calibrationWarnings,
        channelResponses: channelResponses ?? this.channelResponses,
        recommendedCrossovers:
            recommendedCrossovers ?? this.recommendedCrossovers,
        error: error ?? this.error,
        actualSampleRate: actualSampleRate ?? this.actualSampleRate,
        actualChannelCount: actualChannelCount ?? this.actualChannelCount,
      );
}

final micMeasurementProvider =
    StateNotifierProvider<MicMeasurementController, MicMeasurementState>(
  (ref) => MicMeasurementController(ref),
);

class MicMeasurementController extends StateNotifier<MicMeasurementState> {
  final Ref _ref;
  MicMeasurementController(this._ref) : super(const MicMeasurementState());

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  static const int sampleRate = 48000;
  static const int fftSize = 65536;
  static const int durationSec = 10;
  // BLE A2DP codec initializes silently for ~1-2s after play() is called.
  // Pre-rolling for this many seconds before starting the recorder captures
  // only the stable portion of the signal.
  static const int _bleWarmupSec = 2;

  // Real-hardware evidence (Final QA closure #2): a fixed 2s pre-roll is not
  // always enough for real A2DP connection/codec negotiation — on a real
  // Bluetooth speaker the recorder can start before audible playback has
  // actually stabilized, producing a capture whose Peak is elevated (some
  // real tone did land) but whose RMS stays at the noise floor (most of the
  // window was still silence/settling). Rather than raising the shared
  // _bleWarmupSec (which every BLE capture path uses, and which cannot be
  // tuned to a single "correct" number for all devices), runInputLevelCheck
  // records an EXTRA settling margin beyond the nominal check duration and
  // analyzes only the trailing steady-state window — the tone keeps playing
  // for the whole extended recording, so whichever portion is actually
  // stable ends up inside the analyzed tail regardless of exact BLE timing.
  static const Duration _levelCheckSettlingMargin = Duration(seconds: 2);

  // ── Measurement Setup Live Level Check ──────────────────────────────────
  // Single-session bookkeeping: at most one live level-check session may be
  // active at a time, and it must never overlap with any other use of
  // _recorder/_player (background noise, the WAV-based level check, Factory/
  // Room measurement). See stopLiveLevelCheck()'s doc comment and every
  // other capture method's "exclusivity guard" call at its own top.
  bool _liveLevelCheckActive = false;
  String? _liveLevelCheckTempPath;
  StreamController<LiveLevelReading>? _liveLevelController;

  // Retained (deliberately NOT cleared by stopLiveLevelCheck — see that
  // method's doc comment) so buildLiveLevelPassEvidence() can still build
  // evidence using the session that JUST ended, after the caller has
  // already stopped it per the exclusivity contract. Overwritten by the
  // next startLiveLevelCheck() call; never persisted, never resources
  // needing cleanup.
  MeasurementInputDeviceDescriptor? _lastLiveLevelResolvedDevice;
  MeasurementInputDeviceSelection? _lastLiveLevelInputSelection;

  /// True while a live level-check session (started by
  /// [startLiveLevelCheck]) is active. Exposed so callers/tests can assert
  /// exclusivity without reaching into private state.
  bool get isLiveLevelCheckActive => _liveLevelCheckActive;

  /// Starts a CONTINUOUS live level-check session: loops a short pink-noise
  /// test signal (never a single finite play — see the LoopMode.one usage
  /// below) while continuously polling the resolved [inputSelection]'s real
  /// input level via the SAME fail-closed device-resolution path every
  /// other capture method uses (never a system-default silent fallback —
  /// device unavailable throws [MeasurementInputDeviceUnavailable]).
  ///
  /// Returns a broadcast [Stream] of [LiveLevelReading] classified against
  /// [policy]'s existing WAV-based-check thresholds (see
  /// [classifyLiveLevel]) — no new arbitrary numbers.
  ///
  /// Any previously-active live session (or any other _recorder/_player use)
  /// must already be stopped — this method always starts from a clean
  /// exclusivity guard by calling [stopLiveLevelCheck] first, so calling it
  /// again while already active safely restarts rather than colliding.
  Future<Stream<LiveLevelReading>> startLiveLevelCheck({
    required MeasurementInputDeviceSelection inputSelection,
    MeasurementQualityPolicy? policy,
    MeasurementLevelCheckSignal signal = MeasurementLevelCheckSignal.leftOnly,
    Duration pollInterval = const Duration(milliseconds: 200),
  }) async {
    final effectivePolicy = policy ?? MeasurementQualityPolicy.proProvisional();

    // Exclusivity guard (item 5): never start over an existing session.
    await stopLiveLevelCheck();

    final hasPermission = await inputDeviceService.hasPermission();
    if (!hasPermission) {
      throw StateError('MIC_PERMISSION_DENIED');
    }

    // Fail-closed device resolution — identical path to every other capture
    // method. Never a silent system-default fallback for a specific
    // selection: throws MeasurementInputDeviceUnavailable if absent.
    final resolvedDevice =
        await inputDeviceService.resolveForRecording(inputSelection);

    // A short, fixed-length tone looped via LoopMode.one — genuinely
    // continuous playback for as long as the live session runs, not one
    // finite play with a live meter that keeps running after it ends.
    const toneSeconds = 3;
    final toneFile = signal == MeasurementLevelCheckSignal.mono
        ? await _generatePinkNoise(totalSec: toneSeconds)
        : await _generateStereoPinkNoise(
            leftActive: signal == MeasurementLevelCheckSignal.leftOnly,
            totalSec: toneSeconds,
          );

    final dir = await getTemporaryDirectory();
    final tempPath = '${dir.path}/tunai_pro_live_level_check_'
        '${DateTime.now().millisecondsSinceEpoch}.wav';

    try {
      await _player.setFilePath(toneFile.path);
      await _player.setLoopMode(LoopMode.one);
      // Same just_audio lifecycle contract fixed in Closure #3: play()'s
      // Future only completes when playback FINISHES, never when it starts
      // — must not be awaited, or a looped track would never return control
      // here at all.
      unawaited(_player.play().catchError((_) {}));

      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: 1,
          device:
              MeasurementInputDeviceService.toRecordConfigDevice(resolvedDevice),
        ),
        path: tempPath,
      );
    } catch (e) {
      // Start failed partway through — clean up whatever did succeed before
      // rethrowing, so no orphaned player/recorder state survives.
      await stopLiveLevelCheck();
      rethrow;
    }

    _liveLevelCheckActive = true;
    _liveLevelCheckTempPath = tempPath;
    _lastLiveLevelResolvedDevice = resolvedDevice;
    _lastLiveLevelInputSelection = inputSelection;

    final controller = StreamController<LiveLevelReading>.broadcast();
    _liveLevelController = controller;

    _recorder.onAmplitudeChanged(pollInterval).listen(
      (amp) {
        if (!_liveLevelCheckActive || controller.isClosed) return;
        final reading = LiveLevelReading(
          currentDbFs: amp.current,
          status: classifyLiveLevel(amp.current, effectivePolicy),
          at: DateTime.now(),
        );
        controller.add(reading);
      },
      onError: (Object _, StackTrace __) {
        // Non-fatal: a metering glitch must not tear down the session or
        // crash the UI — the next tick simply tries again.
      },
    );

    return controller.stream;
  }

  /// Stops the live level-check session started by [startLiveLevelCheck]:
  /// cancels the amplitude stream, stops player+recorder, restores the
  /// player's loop mode to its default (off — every other playback path in
  /// this controller expects LoopMode.off), and deletes the temp WAV file.
  /// Safe to call when no session is active (no-op) and safe to call
  /// multiple times. Every step is wrapped so one failure (e.g. the temp
  /// file already gone) never skips the rest of cleanup — mirrors
  /// [_safeStopRecorderAndPlayer]'s own swallow-and-continue shape.
  Future<void> stopLiveLevelCheck() async {
    if (!_liveLevelCheckActive &&
        _liveLevelController == null &&
        _liveLevelCheckTempPath == null) {
      return;
    }

    await _liveLevelController?.close();
    _liveLevelController = null;

    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _player.setLoopMode(LoopMode.off);
    } catch (_) {}

    final tempPath = _liveLevelCheckTempPath;
    if (tempPath != null) {
      try {
        final f = File(tempPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    _liveLevelCheckActive = false;
    _liveLevelCheckTempPath = null;
  }

  /// Builds Input Level PASS evidence DIRECTLY from a sustained-GOOD live
  /// level-check run — the fix for the double-verification bug where a live
  /// PASS was being silently overwritten by an automatically re-triggered
  /// legacy WAV check. The stable-GOOD window itself IS the verification;
  /// this never runs a second real capture.
  ///
  /// Reuses the EXACT existing [MeasurementQualityEvaluation] /
  /// [MeasurementQualityMetrics] / [MeasurementInputDeviceSnapshot] shapes
  /// [runInputLevelCheck] already produces — not a parallel evidence system.
  /// [MeasurementSetupReadinessBuilder] and every downstream consumer
  /// (persistence, invalidation, display) treat this identically to a WAV
  /// check's evidence, because it IS the same type.
  ///
  /// [statuses] is always exactly `{ready}` — this must only ever be called
  /// after [LiveLevelStabilityTracker.isStableGood] is true, which by
  /// construction means every tracked tick was already GOOD (never tooLow/
  /// tooHigh). [clippedSampleCount]/[clippedSampleRatio] are always 0 and
  /// [noiseFloorDbFs]/[signalToNoiseDb] are always null — this evidence
  /// deliberately makes NO clipping or SNR claim (see live_level_check.dart's
  /// header comment on why clipping cannot be proven from a live meter);
  /// those remain the separate noise-floor evaluation's and the real WAV
  /// analyzer's job respectively.
  ///
  /// Must be called with the SAME [inputSelection] the just-stopped live
  /// session used — safe to call after [stopLiveLevelCheck] (this reads the
  /// retained `_lastLiveLevel*` fields, not live session state).
  MeasurementSetupCaptureResult buildLiveLevelPassEvidence({
    required MeasurementInputDeviceSelection inputSelection,
    required double representativeDbFs,
    required double peakDbFs,
    required Duration stableDuration,
    DateTime? capturedAt,
  }) {
    if (_lastLiveLevelInputSelection == null) {
      return MeasurementSetupCaptureResult.failure(
          'No live level-check session has run yet.');
    }

    final now = capturedAt ?? DateTime.now();
    final deviceSnapshot = MeasurementInputDeviceSnapshot(
      deviceId: _lastLiveLevelResolvedDevice?.id,
      label: _lastLiveLevelResolvedDevice?.label ?? inputSelection.labelSnapshot,
      isSystemDefault: inputSelection.useSystemDefault,
      platform: Platform.operatingSystem,
      actualSampleRate: sampleRate,
      actualChannelCount: 1,
      capturedAt: now,
    );

    final metrics = MeasurementQualityMetrics(
      peakDbFs: peakDbFs,
      rmsDbFs: representativeDbFs,
      clippedSampleCount: 0,
      clippedSampleRatio: 0.0,
      duration: stableDuration,
      actualSampleRate: sampleRate,
      actualChannelCount: 1,
      inputDeviceSnapshot: deviceSnapshot,
      capturedAt: now,
      source: 'liveMeter',
    );

    return MeasurementSetupCaptureResult.success(
      MeasurementQualityEvaluation(
        statuses: const {MeasurementQualityStatus.ready},
        metrics: metrics,
      ),
    );
  }

  /// Overridable seam for tests: the real implementation wraps this
  /// controller's own [_recorder]. A test fake can override this getter to
  /// return a service backed by a fake [MeasurementInputDeviceApi] without
  /// needing a real platform channel.
  MeasurementInputDeviceService get inputDeviceService =>
      MeasurementInputDeviceService(RecordPackageInputDeviceApi(_recorder));

  static Future<bool> checkAndRequestPermission() async {
    final recorder = AudioRecorder();
    final ok = await recorder.hasPermission();
    await recorder.dispose();
    return ok;
  }

  static void openMicSettings() {
    if (Platform.isMacOS) {
      Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone'
      ]);
    } else if (Platform.isWindows) {
      Process.run('ms-settings:privacy-microphone', [], runInShell: true);
    }
  }

  Future<void> startMeasurement({
    CalibrationCurve? calibrationCurve,
    SpeakerProfile? speakerProfile,
    bool bleWarmup = false,
  }) async {
    // Exclusivity guard (Live Level Check item 5): a live session must never
    // overlap with an actual measurement capture on the shared
    // _recorder/_player instances.
    await stopLiveLevelCheck();
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        state = state.copyWith(
          status: MeasurementStatus.error,
          error: 'MIC_PERMISSION_DENIED',
        );
        return;
      }

      // 핑크노이즈 생성 + 저장 (BLE 모드는 warmup 구간 포함)
      state = state.copyWith(
          status: MeasurementStatus.playing, message: '핑크노이즈 생성 중...');
      final warmup = bleWarmup ? _bleWarmupSec : 0;
      final wavFile = await _generatePinkNoise(totalSec: warmup + durationSec);

      final dir = await getTemporaryDirectory();
      final recPath = '${dir.path}/tunai_pro_measurement.wav';

      // try/finally: 예외·취소가 재생 시작과 정지 사이 어디서 나든 recorder와
      // player가 켜진 채로 남지 않도록 보장한다. (정상 경로에서도 이 finally가
      // 유일한 정지 지점이므로 아래에 별도 stop() 호출은 없다.)
      try {
        if (bleWarmup) {
          // BLE A2DP: 재생 먼저 → 코덱 초기화 대기 → 녹음 시작.
          // 코덱이 깨어나는 동안 녹음하면 무음/팝이 섞이므로 반드시 이 순서.
          //
          // Closure #3 root cause (confirmed via real-hardware temporal
          // trace on runInputLevelCheck + just_audio source):
          // AudioPlayer.play()'s Future does NOT complete when playback
          // starts — it completes only when playback FINISHES (or is
          // paused/stopped/superseded). Awaiting it here previously blocked
          // this whole branch until the tone had already fully played out,
          // so the warmup delay and recorder.start() below only ran AFTER
          // playback was already over — the recorder never overlapped with
          // the tone at all. Fire-and-forget (unawaited) so control
          // proceeds immediately, matching the intended "record while the
          // tone plays" design.
          await _player.setFilePath(wavFile.path);
          unawaited(_player.play().catchError((_) {}));
          state = state.copyWith(message: 'BLE 오디오 초기화 중... ($_bleWarmupSec초)');
          await Future.delayed(Duration(seconds: warmup));
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: sampleRate,
              numChannels: 1,
            ),
            path: recPath,
          );
        } else {
          // 일반(USB/유선) 측정 — 기존 순서 그대로 보존: 녹음 먼저 시작 후 재생.
          // See the bleWarmup branch above for why play() must not be
          // awaited: doing so previously blocked until the tone fully
          // finished, so the subsequent measurement-duration wait recorded a
          // second, fully silent segment AFTER playback had already ended.
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: sampleRate,
              numChannels: 1,
            ),
            path: recPath,
          );
          await _player.setFilePath(wavFile.path);
          unawaited(_player.play().catchError((_) {}));
        }

        state = state.copyWith(message: '측정 중... ($durationSec초)');
        await Future.delayed(const Duration(seconds: durationSec));
      } finally {
        await _safeStopRecorderAndPlayer();
      }

      // FFT 분석 — 항상 raw(uncalibrated) 1/3옥타브 응답을 생성한다.
      state = state.copyWith(
          status: MeasurementStatus.analyzing, message: 'FFT 분석 중...');
      final wavResult = await _readAndParseRecordedWav(recPath);
      final rawResponse =
          _analyzeFFT(wavResult.samples, speakerProfile: speakerProfile);
      final calibration =
          _applyCalibration(rawResponse: rawResponse, curve: calibrationCurve);

      state = state.copyWith(
        status: MeasurementStatus.done,
        message: '측정 완료',
        frequencyResponse: calibration.calibrated,
        rawFrequencyResponse: rawResponse,
        calibrationStatus: calibration.status,
        calibrationCurveChecksum: calibration.curveChecksum,
        calibrationWarnings: calibration.warnings,
        actualSampleRate: wavResult.actualSampleRate,
        actualChannelCount: wavResult.actualChannelCount,
      );
      _recordSession(channelCount: 1);
    } catch (e) {
      state = state.copyWith(
        status: MeasurementStatus.error,
        error: e.toString(),
      );
    }
  }

  // 채널별 순차 측정 (각 채널 솔로 → 측정 → 크로스오버 추천)
  Future<void> startChannelMeasurement({
    required List<String> channelNames,
    required List<ChannelType> channelTypes,
    required Future<void> Function(int) muteAllExcept,
    required Future<void> Function() unmuteAll,
    required Function(int, CrossoverFilter) applyLp,
    required Function(int, CrossoverFilter) applyHp,
    required CrossoverType xoverType,
    bool bleWarmup = false,
  }) async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      state = state.copyWith(
          status: MeasurementStatus.error, error: 'MIC_PERMISSION_DENIED');
      return;
    }

    final channelResponses = <int, List<Map<String, double>>>{};
    final n = channelNames.length;

    try {
      for (int i = 0; i < n; i++) {
        state = state.copyWith(
          status: MeasurementStatus.playing,
          message: '채널 ${i + 1}/$n — ${channelNames[i]} 측정 중...',
        );

        await muteAllExcept(i);
        await Future.delayed(const Duration(milliseconds: 300)); // DSP 적용 대기

        final response = await _measureOnce(bleWarmup: bleWarmup);
        channelResponses[i] = response;
      }

      await unmuteAll();

      // 크로스오버 추천 계산
      final crossovers = _recommendCrossovers(channelTypes, channelResponses);

      // DSP 자동 적용
      for (int i = 0; i < n; i++) {
        final type = channelTypes[i];
        final xFreq = _getCrossoverFreq(i, channelTypes, crossovers);
        if (xFreq == null) continue;

        switch (type) {
          case ChannelType.woofer:
          case ChannelType.subwoofer:
            applyLp(i, CrossoverFilter(type: xoverType, frequency: xFreq));
          case ChannelType.tweeter:
            applyHp(i, CrossoverFilter(type: xoverType, frequency: xFreq));
          case ChannelType.mid:
            final lpFreq = _getCrossoverFreqAbove(i, channelTypes, crossovers);
            applyHp(i, CrossoverFilter(type: xoverType, frequency: xFreq));
            if (lpFreq != null) {
              applyLp(i, CrossoverFilter(type: xoverType, frequency: lpFreq));
            }
          case ChannelType.fullRange:
            break;
        }
      }

      // 전체 합성 응답도 저장
      final combined = channelResponses.values.first;
      state = state.copyWith(
        status: MeasurementStatus.done,
        message: '채널별 측정 완료 — 크로스오버 자동 적용됨',
        frequencyResponse: combined,
        channelResponses: channelResponses,
        recommendedCrossovers: crossovers,
      );
      _recordSession(channelCount: channelResponses.length);
    } catch (e) {
      await unmuteAll();
      state =
          state.copyWith(status: MeasurementStatus.error, error: e.toString());
    }
  }

  Future<List<Map<String, double>>> _measureOnce({
    bool bleWarmup = false,
  }) async {
    // Exclusivity guard (Live Level Check item 5).
    await stopLiveLevelCheck();
    final warmup = bleWarmup ? _bleWarmupSec : 0;
    final wavFile = await _generatePinkNoise(totalSec: warmup + durationSec);
    final dir = await getTemporaryDirectory();
    final recPath =
        '${dir.path}/tunai_ch_${DateTime.now().millisecondsSinceEpoch}.wav';

    // try/finally: startMeasurement()와 동일한 이유 — 예외가 어디서 나든
    // recorder/player가 켜진 채로 남지 않도록 보장.
    try {
      if (bleWarmup) {
        // BLE A2DP: 재생 먼저 → 코덱 초기화 대기 → 녹음 시작.
        // See startMeasurement()'s bleWarmup branch for why play() must not
        // be awaited (just_audio's play() Future only completes when
        // playback finishes, not when it starts).
        await _player.setFilePath(wavFile.path);
        unawaited(_player.play().catchError((_) {}));
        await Future.delayed(Duration(seconds: warmup));
        await _recorder.start(
          const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: sampleRate,
              numChannels: 1),
          path: recPath,
        );
      } else {
        // 일반(USB/유선) 측정 — 기존 순서 그대로 보존: 녹음 먼저 시작 후 재생.
        await _recorder.start(
          const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: sampleRate,
              numChannels: 1),
          path: recPath,
        );
        await _player.setFilePath(wavFile.path);
        unawaited(_player.play().catchError((_) {}));
      }
      await Future.delayed(const Duration(seconds: durationSec));
    } finally {
      await _safeStopRecorderAndPlayer();
    }

    final wavResult = await _readAndParseRecordedWav(recPath);
    return _analyzeFFT(wavResult.samples);
  }

  List<double?> _recommendCrossovers(
    List<ChannelType> types,
    Map<int, List<Map<String, double>>> responses,
  ) {
    final crossovers = List<double?>.filled(types.length - 1, null);
    for (int i = 0; i < types.length - 1; i++) {
      final lowerResp = responses[i];
      final upperResp = responses[i + 1];
      if (lowerResp == null || upperResp == null) continue;

      // 두 채널이 교차하는 주파수 찾기
      double? crossFreq;
      double minDiff = double.infinity;
      for (final point in lowerResp) {
        final f = point['frequency']!;
        final lowerDb = point['db']!;
        final upperDb = upperResp.firstWhere(
          (p) => (p['frequency']! - f).abs() < 50,
          orElse: () => {'frequency': f, 'db': -999.0},
        )['db']!;
        final diff = (lowerDb - upperDb).abs();
        if (diff < minDiff) {
          minDiff = diff;
          crossFreq = f;
        }
      }
      crossovers[i] = crossFreq;
    }
    return crossovers;
  }

  double? _getCrossoverFreq(
      int idx, List<ChannelType> types, List<double?> crossovers) {
    // 이 채널 아래쪽 크로스오버 주파수
    if (idx > 0 && idx - 1 < crossovers.length) return crossovers[idx - 1];
    if (idx < crossovers.length) return crossovers[idx];
    return null;
  }

  double? _getCrossoverFreqAbove(
      int idx, List<ChannelType> types, List<double?> crossovers) {
    if (idx < crossovers.length) return crossovers[idx];
    return null;
  }

  void reset() => state = const MicMeasurementState();

  /// 녹음 시작~정지 구간 어디서 예외/취소가 나든 recorder/player를 켜진
  /// 채로 방치하지 않기 위한 정리. 이미 멈춰 있는 상태에서 stop()을 다시
  /// 호출해도 안전하지만, 방어적으로 개별 실패는 서로를 막지 않게 분리한다.
  /// DSP mute 상태는 건드리지 않는다 — 채널 격리는 사용자가 수동으로 한다.
  Future<void> _safeStopRecorderAndPlayer() async {
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
  }

  // ── Phase 3-D1: setup-check captures ─────────────────────────────────────
  //
  // Neither method below touches MicMeasurementState — a setup check is not
  // a live/FFT measurement and does not participate in that state machine.
  // Both reuse the existing recorder/player fields and BLE-warmup/lifecycle
  // ordering already established above (never re-derived here), and both
  // resolve the input device fresh, immediately before recording — never
  // trusting a previously cached device list.

  /// Records [MeasurementQualityPolicy.silenceCaptureDuration] of ambient
  /// silence (no playback) on [inputSelection] and returns its measured RMS
  /// as [MeasurementQualityMetrics.noiseFloorDbFs] — never a hardcoded
  /// placeholder. Fails closed on missing permission, an unavailable
  /// selected device, or a malformed capture.
  Future<MeasurementSetupCaptureResult> measureNoiseFloor({
    required MeasurementInputDeviceSelection inputSelection,
    MeasurementQualityPolicy? policy,
  }) async {
    final effectivePolicy = policy ?? MeasurementQualityPolicy.proProvisional();
    // Exclusivity guard (Live Level Check item 5).
    await stopLiveLevelCheck();
    try {
      final hasPermission = await inputDeviceService.hasPermission();
      if (!hasPermission) {
        return MeasurementSetupCaptureResult.failure('MIC_PERMISSION_DENIED');
      }

      final resolvedDevice =
          await inputDeviceService.resolveForRecording(inputSelection);

      final dir = await getTemporaryDirectory();
      final recPath = '${dir.path}/tunai_pro_noise_floor_'
          '${DateTime.now().millisecondsSinceEpoch}.wav';

      try {
        final config = RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: 1,
          device: MeasurementInputDeviceService.toRecordConfigDevice(
              resolvedDevice),
        );
        await _recorder.start(config, path: recPath);
        await Future.delayed(effectivePolicy.silenceCaptureDuration);
      } finally {
        await _safeStopRecorderAndPlayer();
      }

      return _evaluateSetupCapture(
        recPath: recPath,
        policy: effectivePolicy,
        inputSelection: inputSelection,
        resolvedDevice: resolvedDevice,
        priorNoiseFloorDbFs: null,
        selfIsNoiseFloor: true,
      );
    } on MeasurementInputDeviceUnavailable catch (e) {
      return MeasurementSetupCaptureResult.failure(e.toString());
    } catch (e) {
      return MeasurementSetupCaptureResult.failure(e.toString());
    }
  }

  /// Plays a short pink-noise test signal (mono, or one channel of a
  /// stereo pair per [signal] — the same generators
  /// startMeasurement()/startRoomMeasurement() already use, never a new
  /// signal engine) and records it on [inputSelection], evaluating actual
  /// PCM level/clipping and, if [priorNoiseFloorDbFs] is supplied from an
  /// earlier [measureNoiseFloor] call, SNR. Reuses the exact BLE-warmup
  /// ordering (play-then-record) vs local/USB ordering (record-then-play)
  /// established by startMeasurement() — never reordered here.
  Future<MeasurementSetupCaptureResult> runInputLevelCheck({
    required MeasurementInputDeviceSelection inputSelection,
    MeasurementQualityPolicy? policy,
    MeasurementLevelCheckSignal signal = MeasurementLevelCheckSignal.mono,
    bool bleWarmup = false,
    double? priorNoiseFloorDbFs,
  }) async {
    final effectivePolicy = policy ?? MeasurementQualityPolicy.proProvisional();
    // Exclusivity guard (Live Level Check item 5).
    await stopLiveLevelCheck();
    try {
      final hasPermission = await inputDeviceService.hasPermission();
      if (!hasPermission) {
        return MeasurementSetupCaptureResult.failure('MIC_PERMISSION_DENIED');
      }

      final resolvedDevice =
          await inputDeviceService.resolveForRecording(inputSelection);

      final warmup = bleWarmup ? _bleWarmupSec : 0;
      // Record for an extra settling margin beyond the nominal check
      // duration on the BLE path only — see _levelCheckSettlingMargin's doc
      // comment. The local/USB path is unaffected: its existing
      // record-then-play ordering has no equivalent codec-negotiation delay.
      final recordDuration = bleWarmup
          ? effectivePolicy.levelCheckDuration + _levelCheckSettlingMargin
          : effectivePolicy.levelCheckDuration;
      final totalSec = warmup + recordDuration.inSeconds;
      final wavFile = signal == MeasurementLevelCheckSignal.mono
          ? await _generatePinkNoise(totalSec: totalSec)
          : await _generateStereoPinkNoise(
              leftActive: signal == MeasurementLevelCheckSignal.leftOnly,
              totalSec: totalSec,
            );

      final dir = await getTemporaryDirectory();
      final recPath = '${dir.path}/tunai_pro_level_check_'
          '${DateTime.now().millisecondsSinceEpoch}.wav';

      try {
        final config = RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: 1,
          device: MeasurementInputDeviceService.toRecordConfigDevice(
              resolvedDevice),
        );
        if (bleWarmup) {
          // Same order as startMeasurement(): play first, wait for BLE A2DP
          // codec warmup, then start recording.
          //
          // Closure #3 root cause (confirmed via real-hardware temporal
          // trace + just_audio source): AudioPlayer.play()'s Future does
          // NOT complete when playback starts — it awaits an internal
          // playCompleter that only completes when playback FINISHES (or is
          // paused/stopped/superseded). Awaiting it here previously blocked
          // this whole branch until the tone had already fully played out,
          // so the warmup delay and recorder.start() below only ran AFTER
          // playback was already over — the recorder never overlapped with
          // the audible tone at all. Fire-and-forget (unawaited) so control
          // proceeds immediately, matching the intended "record while the
          // tone plays" design.
          await _player.setFilePath(wavFile.path);
          unawaited(_player.play().catchError((_) {}));
          await Future.delayed(Duration(seconds: warmup));
          await _recorder.start(config, path: recPath);
        } else {
          // Same order as startMeasurement(): record first, then play.
          // See the bleWarmup branch above for why play() must not be
          // awaited: doing so previously blocked until the tone fully
          // finished, so the subsequent record-duration wait recorded a
          // second, fully silent segment AFTER playback had already ended —
          // diluting the analyzed window with ~50% silence.
          await _recorder.start(config, path: recPath);
          await _player.setFilePath(wavFile.path);
          unawaited(_player.play().catchError((_) {}));
        }
        await Future.delayed(recordDuration);
      } finally {
        await _safeStopRecorderAndPlayer();
      }

      final result = await _evaluateSetupCapture(
        recPath: recPath,
        policy: effectivePolicy,
        inputSelection: inputSelection,
        resolvedDevice: resolvedDevice,
        priorNoiseFloorDbFs: priorNoiseFloorDbFs,
        selfIsNoiseFloor: false,
        // Discard the leading settling margin from the RECORDED samples —
        // the tone played continuously through it, but on BLE it may still
        // be silence/transient at the app's clock if real A2DP audio
        // started later than the fixed _bleWarmupSec pre-roll assumed.
        // Only the trailing, guaranteed-steady levelCheckDuration window is
        // analyzed. No-op (0) on the local/USB path.
        trimLeadingDuration:
            bleWarmup ? _levelCheckSettlingMargin : Duration.zero,
      );
      return result;
    } on MeasurementInputDeviceUnavailable catch (e) {
      return MeasurementSetupCaptureResult.failure(e.toString());
    } catch (e) {
      return MeasurementSetupCaptureResult.failure(e.toString());
    }
  }

  /// Shared tail for both setup-check methods: reads the recorded file,
  /// parses its actual WAV metadata (never assumes byte offset 44), runs
  /// the PCM quality analyzer, and evaluates against [policy].
  ///
  /// [trimLeadingDuration] discards that much of the START of the recorded
  /// samples before analysis — used by [runInputLevelCheck]'s BLE path to
  /// exclude a settling window that may still be silence at the app's
  /// clock even though the tone was already playing (see
  /// [_levelCheckSettlingMargin]). Zero (the default) analyzes the full
  /// capture unchanged, exactly as before this existed.
  Future<MeasurementSetupCaptureResult> _evaluateSetupCapture({
    required String recPath,
    required MeasurementQualityPolicy policy,
    required MeasurementInputDeviceSelection inputSelection,
    required MeasurementInputDeviceDescriptor? resolvedDevice,
    required double? priorNoiseFloorDbFs,
    required bool selfIsNoiseFloor,
    Duration trimLeadingDuration = Duration.zero,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await File(recPath).readAsBytes();
    } catch (e) {
      return MeasurementSetupCaptureResult.failure(
          'Failed to read capture file: $e');
    }

    final wav = MeasurementWavParser.parse(bytes);
    if (!wav.isSuccess) {
      return MeasurementSetupCaptureResult.failure(
          'Malformed capture: ${wav.errors.join('; ')}');
    }

    var samples = MeasurementWavParser.extractNormalizedSamples(bytes, wav);
    if (trimLeadingDuration > Duration.zero) {
      // Mono only (both setup-check callers always record numChannels: 1),
      // so one sample == one frame — no interleave math needed.
      final trimSamples =
          (trimLeadingDuration.inMilliseconds * wav.sampleRate! / 1000).round();
      if (trimSamples > 0 && trimSamples < samples.length) {
        samples = samples.sublist(trimSamples);
      }
    }

    final pcmResult = MeasurementPcmQualityAnalyzer.analyze(
      samples: samples,
      sampleRate: wav.sampleRate!,
      channelCount: wav.channelCount!,
      minimumDuration: policy.minimumCaptureDuration,
      clippingAmplitudeThreshold: policy.clippingAmplitudeThreshold,
    );
    if (!pcmResult.isSuccess) {
      return MeasurementSetupCaptureResult.failure(
          'Malformed capture: ${pcmResult.errors.join('; ')}');
    }
    final pcm = pcmResult.metrics!;

    final deviceSnapshot = MeasurementInputDeviceSnapshot(
      deviceId: resolvedDevice?.id,
      label: resolvedDevice?.label ?? inputSelection.labelSnapshot,
      isSystemDefault: inputSelection.useSystemDefault,
      platform: Platform.operatingSystem,
      actualSampleRate: wav.sampleRate,
      actualChannelCount: wav.channelCount,
      capturedAt: DateTime.now(),
    );

    final evaluation = MeasurementQualityEvaluator.evaluate(
      pcm: pcm,
      actualSampleRate: wav.sampleRate!,
      actualChannelCount: wav.channelCount!,
      noiseFloorDbFs: selfIsNoiseFloor ? pcm.rmsDbFs : priorNoiseFloorDbFs,
      inputDeviceSnapshot: deviceSnapshot,
      policy: policy,
      // P0 root-cause fix: a noise-floor-only capture must never compute
      // SNR against itself, nor apply signal-relative-to-expected-level
      // checks (inputLevelTooLow/TooHigh) that assume a signal was
      // actually expected — see MeasurementQualityEvaluationMode's doc
      // comment. The real level-check path (selfIsNoiseFloor: false) stays
      // at the default signalCapture mode — completely unaffected, every
      // existing check (RMS bounds, SNR against a genuine prior background
      // capture, clipping) runs exactly as before.
      mode: selfIsNoiseFloor
          ? MeasurementQualityEvaluationMode.noiseFloorCapture
          : MeasurementQualityEvaluationMode.signalCapture,
    );

    return MeasurementSetupCaptureResult.success(evaluation);
  }

  /// The single place every FFT-bound capture (Factory startMeasurement,
  /// per-channel _measureOnce, Room startRoomMeasurement) reads its
  /// recorded file. Phase 3-D2 P0: replaces the old hardcoded "data starts
  /// at byte 44" assumption with MeasurementWavParser's real chunk walk —
  /// same normalization contract as MeasurementWavParser
  /// .extractNormalizedSamples (PCM16 / 32768.0), so this is a pure
  /// plumbing change, not a different analysis. Fails closed (throws) on a
  /// malformed/unsupported recording rather than misinterpreting bytes;
  /// every call site already wraps this in its existing try/catch, which
  /// surfaces the failure as MeasurementStatus.error exactly as before.
  ///
  /// Only PCM16 is supported this phase (matches
  /// kSupportedBitsPerSample) — this codebase's recorder always requests
  /// AudioEncoder.wav, which is PCM16 on every platform this app ships to.
  ///
  /// Sample-rate/channel MISMATCH (actual vs. this controller's expected
  /// sampleRate/mono) is still only debugPrint'd here — this function stays
  /// the single WAV-parsing chokepoint and does not itself decide policy.
  /// The actual parsed `sampleRate`/`channelCount` ARE now returned (Phase
  /// 3-D3A-2) so callers can pin them into capture provenance / the Accept
  /// gate; nothing re-parses the WAV a second time to get them.
  Future<
      ({
        Float64List samples,
        int actualSampleRate,
        int actualChannelCount,
      })> _readAndParseRecordedWav(String recPath) async {
    final pcmBytes = await File(recPath).readAsBytes();
    final wav = MeasurementWavParser.parse(pcmBytes);
    if (!wav.isSuccess) {
      throw StateError('Malformed recording (${recPath.split('/').last}): '
          '${wav.errors.join('; ')}');
    }
    if (wav.sampleRate != sampleRate || wav.channelCount != 1) {
      debugPrint('MicMeasurementController: recorded WAV actual format '
          '(${wav.sampleRate}Hz/${wav.channelCount}ch) differs from '
          'expected (${sampleRate}Hz/1ch).');
    }
    final normalized =
        MeasurementWavParser.extractNormalizedSamples(pcmBytes, wav);
    return (
      samples: Float64List.fromList(normalized),
      actualSampleRate: wav.sampleRate ?? sampleRate,
      actualChannelCount: wav.channelCount ?? 1,
    );
  }

  List<Map<String, double>> _analyzeFFT(Float64List samples,
      {SpeakerProfile? speakerProfile}) {
    final input = Float64List(fftSize);
    final copyLen = min(samples.length, fftSize);
    for (int i = 0; i < copyLen; i++) {
      final window = 0.5 * (1 - cos(2 * pi * i / (copyLen - 1)));
      input[i] = samples[i] * window;
    }

    final fft = FFT(fftSize);
    final freq = fft.realFft(input);
    final result = <Map<String, double>>[];
    const nyquist = fftSize ~/ 2;

    // 1/3 옥타브 밴딩으로 스무딩
    final bands = <double, List<double>>{};
    for (int i = 1; i < nyquist; i++) {
      final f = i * sampleRate / fftSize.toDouble();
      if (f < 20 || f > 20000) continue;
      final re = freq[i].x;
      final im = freq[i].y;
      final mag = sqrt(re * re + im * im) / fftSize;
      if (mag <= 0) continue;
      final db = 20 * log(mag) / ln10;

      // 1/3 옥타브 밴드 중심 주파수로 그룹화
      final band = _nearestThirdOctave(f);
      bands.putIfAbsent(band, () => []).add(db);
    }

    final sortedBands = bands.keys.toList()..sort();
    for (int i = 0; i < sortedBands.length; i++) {
      final f = sortedBands[i];
      final dbs = bands[f]!;
      final avgDb = dbs.reduce((a, b) => a + b) / dbs.length;
      result.add({'frequency': f, 'db': avgDb});
    }

    return result;
  }

  /// Applies [curve] (if any) to a raw 1/3-octave response, producing both
  /// the raw and calibrated `List<Map<frequency,db>>` shapes this
  /// controller's state already uses. This is the ONLY place in this file
  /// calibration is applied — the same [CalibrationApplicator] a future
  /// Log Sweep/IR path will call too, so the correction logic itself is
  /// never duplicated.
  ///
  /// A null [curve] always means [CalibrationStatus.explicitlyUncalibrated]
  /// here: this is a fresh, live capture, never a decode of old persisted
  /// data, so [CalibrationStatus.legacyUnknown] never applies at this call
  /// site — only a caller decoding a past project would use that status.
  ({
    List<Map<String, double>> calibrated,
    CalibrationStatus status,
    String? curveChecksum,
    List<String> warnings,
  }) _applyCalibration({
    required List<Map<String, double>> rawResponse,
    CalibrationCurve? curve,
  }) {
    final rawPoints = [
      for (final m in rawResponse)
        if (m['frequency'] != null)
          MeasurementDataPoint(
              frequencyHz: m['frequency']!, magnitudeDb: m['db']),
    ];

    final result = curve != null
        ? CalibrationApplicator.apply(rawPoints: rawPoints, curve: curve)
        : CalibrationApplicator.passthrough(
            rawPoints: rawPoints,
            status: CalibrationStatus.explicitlyUncalibrated,
          );

    return (
      calibrated: [
        for (final p in result.calibratedPoints)
          {'frequency': p.frequencyHz, 'db': p.magnitudeDb ?? 0.0},
      ],
      status: result.status,
      curveChecksum: result.curveChecksum,
      warnings: result.warnings,
    );
  }

  double _nearestThirdOctave(double freq) {
    // 1/3 옥타브 밴드 중심 주파수 (ISO 표준)
    const centers = [
      20,
      25,
      31.5,
      40,
      50,
      63,
      80,
      100,
      125,
      160,
      200,
      250,
      315,
      400,
      500,
      630,
      800,
      1000,
      1250,
      1600,
      2000,
      2500,
      3150,
      4000,
      5000,
      6300,
      8000,
      10000,
      12500,
      16000,
      20000
    ];
    double nearest = centers[0].toDouble();
    double minDist = (freq - nearest).abs();
    for (final c in centers) {
      final dist = (freq - c).abs();
      if (dist < minDist) {
        minDist = dist;
        nearest = c.toDouble();
      }
    }
    return nearest;
  }

  Future<File> _generatePinkNoise({int totalSec = durationSec}) async {
    final dir = await getTemporaryDirectory();
    // 일반(BLE 웜업 없음) 측정은 기존 파일명(pink_noise_pro.wav)을 그대로 쓴다.
    // BLE 웜업 구간이 붙어 길이가 달라질 때만 구분용 접미사를 붙인다.
    final fileName = totalSec == durationSec
        ? 'pink_noise_pro.wav'
        : 'pink_noise_pro_${totalSec}s.wav';
    final file = File('${dir.path}/$fileName');
    final wavBytes = buildPinkNoiseWavBytes(totalSec: totalSec);
    await file.writeAsBytes(wavBytes);
    return file;
  }

  // ── Phase 2: Stereo Room Measurement ─────────────────────────────────────

  /// Whole-system Left or Right measurement: plays a STEREO pink-noise WAV
  /// with only [leftActive]'s channel carrying signal (the other channel is
  /// exact zero PCM, so the opposite speaker is silent for the whole test —
  /// no DSP mute/output-gain write involved). The woofer and tweeter on the
  /// active side play together through the existing crossover, exactly as
  /// wired today.
  ///
  /// Recording/FFT is untouched: the microphone capture stays mono (it
  /// records the room's acoustic response, not the stereo file being
  /// played), so this reuses the identical record → FFT pipeline as
  /// [startMeasurement] — only the WAV fed to the player changes.
  Future<void> startRoomMeasurement({
    required bool leftActive,
    CalibrationCurve? calibrationCurve,
    bool bleWarmup = false,
  }) async {
    // Exclusivity guard (Live Level Check item 5).
    await stopLiveLevelCheck();
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        state = state.copyWith(
          status: MeasurementStatus.error,
          error: 'MIC_PERMISSION_DENIED',
        );
        return;
      }

      state = state.copyWith(
          status: MeasurementStatus.playing, message: '핑크노이즈 생성 중...');
      final warmup = bleWarmup ? _bleWarmupSec : 0;
      final wavFile = await _generateStereoPinkNoise(
        leftActive: leftActive,
        totalSec: warmup + durationSec,
      );

      final dir = await getTemporaryDirectory();
      final recPath = '${dir.path}/tunai_pro_room_measurement.wav';

      try {
        if (bleWarmup) {
          // Same BLE A2DP warm-up order as startMeasurement(): play first,
          // wait for codec init, then start recording.
          // See startMeasurement()'s bleWarmup branch for why play() must
          // not be awaited (just_audio's play() Future only completes when
          // playback finishes, not when it starts).
          await _player.setFilePath(wavFile.path);
          unawaited(_player.play().catchError((_) {}));
          state = state.copyWith(message: 'BLE 오디오 초기화 중... ($_bleWarmupSec초)');
          await Future.delayed(Duration(seconds: warmup));
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: sampleRate,
              numChannels: 1,
            ),
            path: recPath,
          );
        } else {
          // Same Local/USB order as startMeasurement(): recorder first, then
          // playback.
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: sampleRate,
              numChannels: 1,
            ),
            path: recPath,
          );
          await _player.setFilePath(wavFile.path);
          unawaited(_player.play().catchError((_) {}));
        }

        state = state.copyWith(message: '측정 중... ($durationSec초)');
        await Future.delayed(const Duration(seconds: durationSec));
      } finally {
        await _safeStopRecorderAndPlayer();
      }

      state = state.copyWith(
          status: MeasurementStatus.analyzing, message: 'FFT 분석 중...');
      final wavResult = await _readAndParseRecordedWav(recPath);
      final rawResponse = _analyzeFFT(wavResult.samples);
      final calibration =
          _applyCalibration(rawResponse: rawResponse, curve: calibrationCurve);

      state = state.copyWith(
        status: MeasurementStatus.done,
        message: '측정 완료',
        frequencyResponse: calibration.calibrated,
        rawFrequencyResponse: rawResponse,
        calibrationStatus: calibration.status,
        calibrationCurveChecksum: calibration.curveChecksum,
        calibrationWarnings: calibration.warnings,
        actualSampleRate: wavResult.actualSampleRate,
        actualChannelCount: wavResult.actualChannelCount,
      );
      _recordSession(channelCount: 1);
    } catch (e) {
      state = state.copyWith(
        status: MeasurementStatus.error,
        error: e.toString(),
      );
    }
  }

  Future<File> _generateStereoPinkNoise({
    required bool leftActive,
    int totalSec = durationSec,
  }) async {
    final dir = await getTemporaryDirectory();
    final side = leftActive ? 'l' : 'r';
    final file = File('${dir.path}/pink_noise_room_${side}_${totalSec}s.wav');
    final wavBytes = buildStereoPinkNoiseWavBytes(
        leftActive: leftActive, totalSec: totalSec);
    await file.writeAsBytes(wavBytes);
    return file;
  }

  /// Pure function, same Paul Kellet pink-noise algorithm and coefficients
  /// as [buildPinkNoiseWavBytes] — only the PCM layout changes: interleaved
  /// stereo with the inactive channel forced to exact-zero samples so the
  /// opposite speaker gets no signal at all (not just attenuated).
  @visibleForTesting
  static Uint8List buildStereoPinkNoiseWavBytes({
    required bool leftActive,
    int totalSec = durationSec,
  }) {
    final totalSamples = sampleRate * totalSec;
    final pcm = Int16List(totalSamples * 2); // interleaved L,R,L,R,...

    double b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
    final rng = Random();
    for (int i = 0; i < totalSamples; i++) {
      final white = rng.nextDouble() * 2 - 1;
      b0 = 0.99886 * b0 + white * 0.0555179;
      b1 = 0.99332 * b1 + white * 0.0750759;
      b2 = 0.96900 * b2 + white * 0.1538520;
      b3 = 0.86650 * b3 + white * 0.3104856;
      b4 = 0.55000 * b4 + white * 0.5329522;
      b5 = -0.7616 * b5 - white * 0.0168980;
      final pink = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
      b6 = white * 0.115926;
      final sample = (pink.clamp(-1.0, 1.0) * 32767).round();
      if (leftActive) {
        pcm[i * 2] = sample;
        pcm[i * 2 + 1] = 0;
      } else {
        pcm[i * 2] = 0;
        pcm[i * 2 + 1] = sample;
      }
    }

    const numChannels = 2;
    final dataSize = totalSamples * numChannels * 2;
    final header = ByteData(44);
    void setStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    setStr(0, 'RIFF');
    header.setUint32(4, 36 + dataSize, Endian.little);
    setStr(8, 'WAVE');
    setStr(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * numChannels * 2, Endian.little);
    header.setUint16(32, numChannels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    setStr(36, 'data');
    header.setUint32(40, dataSize, Endian.little);

    final wavBytes = BytesBuilder();
    wavBytes.add(header.buffer.asUint8List());
    wavBytes.add(pcm.buffer.asUint8List());
    return wavBytes.toBytes();
  }

  /// 순수 함수: 파일시스템/플랫폼 채널에 닿지 않고 핑크노이즈 WAV 바이트를 만든다.
  /// [_generatePinkNoise]에서 그대로 추출한 것 — 바이트 단위로 동일하며 동작 변경
  /// 없음. totalSec으로부터 만들어지는 파일 길이(=바이트 수)를 플러그인 없이
  /// 단위 테스트할 수 있도록 분리했다.
  @visibleForTesting
  static Uint8List buildPinkNoiseWavBytes({int totalSec = durationSec}) {
    final totalSamples = sampleRate * totalSec;
    final pcm = Int16List(totalSamples);

    // Paul Kellet 핑크노이즈
    double b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
    final rng = Random();
    for (int i = 0; i < totalSamples; i++) {
      final white = rng.nextDouble() * 2 - 1;
      b0 = 0.99886 * b0 + white * 0.0555179;
      b1 = 0.99332 * b1 + white * 0.0750759;
      b2 = 0.96900 * b2 + white * 0.1538520;
      b3 = 0.86650 * b3 + white * 0.3104856;
      b4 = 0.55000 * b4 + white * 0.5329522;
      b5 = -0.7616 * b5 - white * 0.0168980;
      final pink = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
      b6 = white * 0.115926;
      pcm[i] = (pink.clamp(-1.0, 1.0) * 32767).round();
    }

    // WAV 헤더 생성
    final dataSize = totalSamples * 2;
    final header = ByteData(44);
    void setStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    setStr(0, 'RIFF');
    header.setUint32(4, 36 + dataSize, Endian.little);
    setStr(8, 'WAVE');
    setStr(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    setStr(36, 'data');
    header.setUint32(40, dataSize, Endian.little);

    final wavBytes = BytesBuilder();
    wavBytes.add(header.buffer.asUint8List());
    wavBytes.add(pcm.buffer.asUint8List());
    return wavBytes.toBytes();
  }

  /// 측정 1회 완료 시 AKG-ready 이력에 기록(fire-and-forget) — 지금 당장 아무도
  /// 이 데이터를 읽지 않지만, 나중에 AIE/Measurement History가 참조할 수 있도록
  /// 저장만 해둔다. 실패해도 측정 자체 흐름에는 영향 없음.
  void _recordSession({required int channelCount}) {
    () async {
      try {
        final profile = _ref.read(systemProfileProvider);
        final session = MeasurementSession(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          userId: _ref.read(authProvider).userId,
          systemProfileId: profile.id.name,
          channelCount: channelCount,
        );
        await MeasurementSessionStore.append(session);
      } catch (_) {
        // 이력 저장 실패는 무시 — 측정 기능 자체를 막지 않음
      }
    }();
  }

  @override
  void dispose() {
    // Live Level Check cleanup (item 5: dialog close/dispose gets the same
    // cleanup as an explicit stop). dispose() is sync, so this can't await
    // _recorder.stop()/_player.stop() — but disposing them immediately below
    // already tears down any in-flight session, and the temp file delete is
    // fire-and-forget best-effort (a leftover temp WAV is not a correctness
    // issue, just disk clutter).
    _liveLevelController?.close();
    _liveLevelController = null;
    _liveLevelCheckActive = false;
    final leftoverTempPath = _liveLevelCheckTempPath;
    _liveLevelCheckTempPath = null;
    if (leftoverTempPath != null) {
      unawaited(File(leftoverTempPath).delete().catchError((_) => File('')));
    }
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }
}
