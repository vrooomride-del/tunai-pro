// ── TUNAI PRO Phase 3-D1 — pure PCM quality analyzer ────────────────────────
//
// Deliberately separate from the FFT/FRD engine (fftea-based analysis in
// mic_measurement_controller.dart) — this module answers "is this recording
// technically usable" (level, clipping, duration), never "what does this
// measure acoustically." No frequency-domain analysis happens here.
//
// Normalization contract: input samples are PCM16 values normalized to
// [-1.0, 1.0] by dividing the signed 16-bit integer by 32768.0 — the exact
// convention MeasurementWavParser.extractNormalizedSamples uses. 0 dBFS
// corresponds to a normalized amplitude of 1.0.
library;

import 'dart:math' as math;

/// Named floor used instead of -infinity when a signal is exact digital
/// silence (amplitude 0). -120 dBFS is far below any real noise floor this
/// hardware chain can produce, so it reads unambiguously as "no signal
/// detected" without ever producing -infinity/NaN downstream.
const double kMeasurementDbFsSilenceFloor = -120.0;

/// Amplitude threshold (normalized, near full-scale) above which a PCM16
/// sample is considered clipped. Set just below the true full-scale value
/// (1.0) rather than exactly at it, since a genuinely clipped digital
/// signal typically pins at or very near max code repeatedly, and integer
/// quantization means "exactly 1.0" is rarely hit even by real clipping —
/// checking ">=" this threshold catches the flat-topped run without
/// requiring bit-exact full scale.
const double kMeasurementClippingAmplitudeThreshold = 0.98;

class MeasurementPcmQualityMetrics {
  final double peakAmplitude;
  final double peakDbFs;
  final double rmsAmplitude;
  final double rmsDbFs;
  final int clippedSampleCount;
  final double clippedSampleRatio;
  final int sampleCount;
  final Duration duration;

  const MeasurementPcmQualityMetrics({
    required this.peakAmplitude,
    required this.peakDbFs,
    required this.rmsAmplitude,
    required this.rmsDbFs,
    required this.clippedSampleCount,
    required this.clippedSampleRatio,
    required this.sampleCount,
    required this.duration,
  });
}

class MeasurementPcmQualityAnalysisResult {
  final MeasurementPcmQualityMetrics? metrics;
  final List<String> errors;

  const MeasurementPcmQualityAnalysisResult(
      {this.metrics, this.errors = const []});

  bool get isSuccess => metrics != null && errors.isEmpty;
}

abstract final class MeasurementPcmQualityAnalyzer {
  /// Computes peak/RMS/clipping metrics over [samples] (normalized
  /// [-1.0, 1.0] PCM16 values, interleaved if multi-channel — clipping and
  /// level statistics are computed across all channels together since a
  /// clip on any channel makes the whole capture suspect).
  ///
  /// [clippingAmplitudeThreshold] and [minimumDuration] are supplied by the
  /// caller (from a [MeasurementQualityPolicy]) rather than hardcoded here —
  /// this module has no opinion on what counts as "too short" or "clipped",
  /// only on how to compute the numbers a policy judges.
  static MeasurementPcmQualityAnalysisResult analyze({
    required List<double> samples,
    required int sampleRate,
    required int channelCount,
    required Duration minimumDuration,
    double clippingAmplitudeThreshold = kMeasurementClippingAmplitudeThreshold,
  }) {
    if (samples.isEmpty) {
      return const MeasurementPcmQualityAnalysisResult(
          errors: ['No samples to analyze (empty capture).']);
    }
    if (sampleRate <= 0 || channelCount <= 0) {
      return const MeasurementPcmQualityAnalysisResult(
          errors: ['Invalid sampleRate/channelCount.']);
    }
    for (final s in samples) {
      if (!s.isFinite) {
        return const MeasurementPcmQualityAnalysisResult(
            errors: ['Non-finite sample value encountered — malformed PCM.']);
      }
    }

    final frameCount = samples.length ~/ channelCount;
    if (frameCount == 0) {
      return const MeasurementPcmQualityAnalysisResult(errors: [
        'Sample count is smaller than one frame — malformed '
            'channel alignment.'
      ]);
    }
    final duration = Duration(
        microseconds:
            (frameCount / sampleRate * Duration.microsecondsPerSecond).round());
    if (duration < minimumDuration) {
      return MeasurementPcmQualityAnalysisResult(errors: [
        'Capture duration (${duration.inMilliseconds}ms) is shorter than '
            'the minimum required (${minimumDuration.inMilliseconds}ms).'
      ]);
    }

    var peak = 0.0;
    var sumSquares = 0.0;
    var clippedCount = 0;
    for (final s in samples) {
      final abs = s.abs();
      if (abs > peak) peak = abs;
      sumSquares += s * s;
      if (abs >= clippingAmplitudeThreshold) clippedCount++;
    }
    final rms = math.sqrt(sumSquares / samples.length);
    final clippedRatio = clippedCount / samples.length;

    return MeasurementPcmQualityAnalysisResult(
      metrics: MeasurementPcmQualityMetrics(
        peakAmplitude: peak,
        peakDbFs: _amplitudeToDbFs(peak),
        rmsAmplitude: rms,
        rmsDbFs: _amplitudeToDbFs(rms),
        clippedSampleCount: clippedCount,
        clippedSampleRatio: clippedRatio,
        sampleCount: samples.length,
        duration: duration,
      ),
    );
  }

  /// log(0) is never evaluated directly — an exact-zero amplitude maps to
  /// [kMeasurementDbFsSilenceFloor] instead of -infinity.
  static double _amplitudeToDbFs(double amplitude) {
    if (amplitude <= 0.0) return kMeasurementDbFsSilenceFloor;
    final db = 20.0 * (math.log(amplitude) / math.ln10);
    if (!db.isFinite) return kMeasurementDbFsSilenceFloor;
    return db < kMeasurementDbFsSilenceFloor
        ? kMeasurementDbFsSilenceFloor
        : db;
  }
}
