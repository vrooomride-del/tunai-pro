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
  }) {
    final now = capturedAt ?? DateTime.now();
    final signalToNoiseDb =
        noiseFloorDbFs == null ? null : pcm.rmsDbFs - noiseFloorDbFs;

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
    if (pcm.clippedSampleCount >= policy.clippingSampleCountThreshold ||
        pcm.clippedSampleRatio >= policy.clippingRatioThreshold) {
      statuses.add(MeasurementQualityStatus.clipping);
    }
    if (pcm.rmsDbFs < policy.minimumSignalRmsDbFs) {
      statuses.add(MeasurementQualityStatus.inputLevelTooLow);
    }
    if (pcm.rmsDbFs > policy.maximumSignalRmsDbFs) {
      statuses.add(MeasurementQualityStatus.inputLevelTooHigh);
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
