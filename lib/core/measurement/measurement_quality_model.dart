// ── TUNAI PRO Phase 3-D1 — measurement quality typed model ──────────────────
//
// Pure evaluation only. No UI text, no Capture gating — that wiring is
// Phase 3-D2/3-D3's job. This module turns PCM-level facts + policy
// thresholds into a typed judgement a future gate can consume.
library;

import '../calibration/calibration_types.dart' show CalibrationStatus;
import 'measurement_input_device.dart';
import 'measurement_pcm_quality_analyzer.dart';
import 'measurement_quality_policy.dart';

/// Every reason a setup/capture might not be usable. Multiple statuses can
/// apply to the same capture at once — see [MeasurementQualityEvaluation].
enum MeasurementQualityStatus {
  ready,
  permissionDenied,
  inputDeviceUnavailable,
  malformedCapture,
  captureTooShort,
  sampleRateMismatch,
  channelMismatch,
  inputLevelTooLow,
  inputLevelTooHigh,
  clipping,
  noiseFloorTooHigh,
  signalToNoiseTooLow;

  String toJson() => name;
  static MeasurementQualityStatus fromJson(String s) =>
      MeasurementQualityStatus.values.firstWhere((e) => e.name == s,
          orElse: () => MeasurementQualityStatus.malformedCapture);
}

/// What kind of capture [MeasurementQualityEvaluator.evaluate] is judging —
/// determines which checks are even MEANINGFUL to run, not just which
/// thresholds to use. A single evaluate() call is always about ONE of these,
/// never a mix.
///
///  - [signalCapture]: an actual test-signal / real measurement capture.
///    Every existing check applies unchanged: input level too low/high,
///    signal-to-noise (against a genuinely separate, prior background
///    capture), clipping.
///  - [noiseFloorCapture]: a background-noise-ONLY capture (silence, no
///    signal playing). Only checks that are actually about "is this
///    recording usable as a noise floor" apply: capture validity (format/
///    duration/sample-rate/channel), the noise-floor-level threshold
///    ([MeasurementQualityStatus.noiseFloorTooHigh]), and raw sample
///    clipping (a genuine hardware/gain artifact, not signal-level
///    dependent — a clipping noise-floor capture is still a real gain
///    problem). Input-level-too-low/too-high and signal-to-noise are
///    SIGNAL-RELATIVE-TO-EXPECTED-LEVEL checks that make no sense applied to
///    a capture that was never expected to contain a signal at all — a
///    quiet, correctly-behaving noise floor is, by definition, always far
///    below [MeasurementQualityPolicy.minimumSignalRmsDbFs], and comparing
///    a noise floor's RMS to itself for SNR is a meaningless self-compare
///    (see the P0 fix this mode replaces — computeSignalToNoise).
enum MeasurementQualityEvaluationMode { signalCapture, noiseFloorCapture }

/// The full measured record for one setup-check/capture — the typed
/// equivalent of the brief's `MeasurementQualityMetrics`. Immutable; safe to
/// embed verbatim into a captured measurement in a later phase.
class MeasurementQualityMetrics {
  final double peakDbFs;
  final double rmsDbFs;
  final int clippedSampleCount;
  final double clippedSampleRatio;

  /// Null until a noise-floor capture has actually been run and combined
  /// with this one — never a placeholder value.
  final double? noiseFloorDbFs;
  final double? signalToNoiseDb;

  final Duration duration;
  final int actualSampleRate;
  final int actualChannelCount;
  final MeasurementInputDeviceSnapshot? inputDeviceSnapshot;
  final CalibrationStatus? calibrationStatus;
  final DateTime capturedAt;

  /// Which check produced these metrics — `'wavCapture'` (the real,
  /// clipping-verified WAV-based check) or `'liveMeter'` (the Live Level
  /// Check's sustained-GOOD evidence, never clipping-verified — see
  /// live_level_check.dart's header comment). Display/diagnostics only;
  /// never used to change readiness logic itself. Null for older persisted
  /// snapshots from before this field existed — always treated as
  /// 'wavCapture' by any code that cares, since that was the only source at
  /// the time.
  final String? source;

  const MeasurementQualityMetrics({
    required this.peakDbFs,
    required this.rmsDbFs,
    required this.clippedSampleCount,
    required this.clippedSampleRatio,
    this.noiseFloorDbFs,
    this.signalToNoiseDb,
    required this.duration,
    required this.actualSampleRate,
    required this.actualChannelCount,
    this.inputDeviceSnapshot,
    this.calibrationStatus,
    required this.capturedAt,
    this.source,
  });

  Map<String, dynamic> toJson() => {
        'peakDbFs': peakDbFs,
        'rmsDbFs': rmsDbFs,
        'clippedSampleCount': clippedSampleCount,
        'clippedSampleRatio': clippedSampleRatio,
        if (noiseFloorDbFs != null) 'noiseFloorDbFs': noiseFloorDbFs,
        if (signalToNoiseDb != null) 'signalToNoiseDb': signalToNoiseDb,
        'durationMs': duration.inMilliseconds,
        'actualSampleRate': actualSampleRate,
        'actualChannelCount': actualChannelCount,
        if (inputDeviceSnapshot != null)
          'inputDeviceSnapshot': inputDeviceSnapshot!.toJson(),
        if (calibrationStatus != null)
          'calibrationStatus': calibrationStatus!.toJson(),
        'capturedAt': capturedAt.toIso8601String(),
        if (source != null) 'source': source,
      };

  factory MeasurementQualityMetrics.fromJson(Map<String, dynamic> j) =>
      MeasurementQualityMetrics(
        peakDbFs: (j['peakDbFs'] as num).toDouble(),
        rmsDbFs: (j['rmsDbFs'] as num).toDouble(),
        clippedSampleCount: j['clippedSampleCount'] as int? ?? 0,
        clippedSampleRatio:
            (j['clippedSampleRatio'] as num?)?.toDouble() ?? 0.0,
        noiseFloorDbFs: (j['noiseFloorDbFs'] as num?)?.toDouble(),
        signalToNoiseDb: (j['signalToNoiseDb'] as num?)?.toDouble(),
        duration: Duration(milliseconds: j['durationMs'] as int? ?? 0),
        actualSampleRate: j['actualSampleRate'] as int? ?? 0,
        actualChannelCount: j['actualChannelCount'] as int? ?? 0,
        inputDeviceSnapshot: j['inputDeviceSnapshot'] != null
            ? MeasurementInputDeviceSnapshot.fromJson(
                Map<String, dynamic>.from(j['inputDeviceSnapshot'] as Map))
            : null,
        calibrationStatus: j['calibrationStatus'] != null
            ? CalibrationStatus.fromJson(j['calibrationStatus'] as String)
            : null,
        capturedAt: DateTime.tryParse(j['capturedAt'] as String? ?? '') ??
            DateTime.now(),
        source: j['source'] as String?,
      );
}

/// Result of judging a [MeasurementQualityMetrics] against a
/// [MeasurementQualityPolicy]. [statuses] contains [MeasurementQualityStatus
/// .ready] alone when nothing is wrong, or one-or-more problem statuses
/// otherwise — never both `ready` and a problem status together.
class MeasurementQualityEvaluation {
  final Set<MeasurementQualityStatus> statuses;
  final MeasurementQualityMetrics metrics;

  const MeasurementQualityEvaluation({
    required this.statuses,
    required this.metrics,
  });

  bool get isReady =>
      statuses.length == 1 && statuses.single == MeasurementQualityStatus.ready;
}

abstract final class MeasurementQualityEvaluator {
  /// Judges a completed PCM analysis against [policy]. This does not itself
  /// run the analyzer — callers pass already-computed
  /// [MeasurementPcmQualityMetrics] (from
  /// [MeasurementPcmQualityAnalyzer.analyze]) plus the actual sample
  /// rate/channel count read back from the WAV file.
  static MeasurementQualityEvaluation evaluate({
    required MeasurementPcmQualityMetrics pcm,
    required int actualSampleRate,
    required int actualChannelCount,
    double? noiseFloorDbFs,
    MeasurementInputDeviceSnapshot? inputDeviceSnapshot,
    CalibrationStatus? calibrationStatus,
    required MeasurementQualityPolicy policy,
    DateTime? capturedAt,
    // P0 fix: which checks are even meaningful depends on what kind of
    // capture this is — see [MeasurementQualityEvaluationMode]'s doc
    // comment. Defaults to [MeasurementQualityEvaluationMode.signalCapture]
    // so every existing signal-capture call site (Factory/Room actual
    // measurement, the legacy WAV level check) is completely unchanged.
    // Only the noise-floor-only call site passes [noiseFloorCapture].
    MeasurementQualityEvaluationMode mode =
        MeasurementQualityEvaluationMode.signalCapture,
  }) {
    final isNoiseFloorCapture =
        mode == MeasurementQualityEvaluationMode.noiseFloorCapture;
    final now = capturedAt ?? DateTime.now();
    final signalToNoiseDb = (isNoiseFloorCapture || noiseFloorDbFs == null)
        ? null
        : pcm.rmsDbFs - noiseFloorDbFs;

    final metrics = MeasurementQualityMetrics(
      peakDbFs: pcm.peakDbFs,
      rmsDbFs: pcm.rmsDbFs,
      clippedSampleCount: pcm.clippedSampleCount,
      clippedSampleRatio: pcm.clippedSampleRatio,
      noiseFloorDbFs: noiseFloorDbFs,
      signalToNoiseDb: signalToNoiseDb,
      duration: pcm.duration,
      actualSampleRate: actualSampleRate,
      actualChannelCount: actualChannelCount,
      inputDeviceSnapshot: inputDeviceSnapshot,
      calibrationStatus: calibrationStatus,
      capturedAt: now,
    );

    final statuses = <MeasurementQualityStatus>{};

    if (pcm.duration < policy.minimumCaptureDuration) {
      statuses.add(MeasurementQualityStatus.captureTooShort);
    }
    if (actualSampleRate != policy.expectedSampleRate) {
      statuses.add(MeasurementQualityStatus.sampleRateMismatch);
    }
    if (actualChannelCount != policy.expectedChannelCount) {
      statuses.add(MeasurementQualityStatus.channelMismatch);
    }
    // Raw sample clipping is a hardware/gain artifact independent of
    // whether a signal was expected — it's checked for BOTH modes. A
    // clipping noise-floor capture still indicates a real gain problem
    // (input gain far too high even with nothing playing).
    if (pcm.clippedSampleCount >= policy.clippingSampleCountThreshold ||
        pcm.clippedSampleRatio >= policy.clippingRatioThreshold) {
      statuses.add(MeasurementQualityStatus.clipping);
    }
    // inputLevelTooLow/TooHigh are SIGNAL-relative-to-expected-level checks
    // — meaningless for a noise-floor-only capture, which is never expected
    // to contain a signal at all. A quiet, correctly-behaving noise floor
    // is by definition almost always below minimumSignalRmsDbFs; applying
    // this check there was a structural false-positive, not a threshold
    // problem (see MeasurementQualityEvaluationMode's doc comment).
    if (!isNoiseFloorCapture) {
      if (pcm.rmsDbFs < policy.minimumSignalRmsDbFs) {
        statuses.add(MeasurementQualityStatus.inputLevelTooLow);
      }
      if (pcm.rmsDbFs > policy.maximumSignalRmsDbFs) {
        statuses.add(MeasurementQualityStatus.inputLevelTooHigh);
      }
    }
    if (noiseFloorDbFs != null &&
        noiseFloorDbFs > policy.maximumNoiseFloorDbFs) {
      statuses.add(MeasurementQualityStatus.noiseFloorTooHigh);
    }
    if (signalToNoiseDb != null &&
        signalToNoiseDb < policy.minimumSignalToNoiseDb) {
      statuses.add(MeasurementQualityStatus.signalToNoiseTooLow);
    }

    if (statuses.isEmpty) statuses.add(MeasurementQualityStatus.ready);

    return MeasurementQualityEvaluation(statuses: statuses, metrics: metrics);
  }
}
