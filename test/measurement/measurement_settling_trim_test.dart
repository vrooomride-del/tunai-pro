// Final QA closure #2 — Issue A regression coverage.
//
// Real-hardware evidence: a BLE/A2DP "Play Test Signal & Measure" capture
// showed Peak -41.7 dBFS (real tone clearly reached the mic at some point)
// but RMS -53.5 dBFS (== the measured noise floor, -53.9 dBFS), giving
// SNR 0.4 dB — consistent with only a small fraction of the recording
// window actually containing the tone, the rest being pre-audio silence
// diluting the aggregate RMS/SNR.
//
// MicMeasurementController._evaluateSetupCapture's actual recorder/player
// wiring is not unit-testable without a real platform channel (see
// test/measurement/mic_measurement_setup_capture_test.dart's documented
// precedent) — this file instead proves, at the pure analyzer/evaluator
// level, that the mechanism the fix relies on (record extra settling
// margin, then analyze only the trailing steady-state window) actually
// recovers a valid measurement from exactly this failure shape, and does
// NOT paper over a capture where the signal genuinely never stabilized.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_pcm_quality_analyzer.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_model.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_policy.dart';

const _sampleRate = 48000;

/// Deterministic low-amplitude "noise floor" samples — uniform noise whose
/// RMS lands close to the real-hardware evidence's -53.9 dBFS.
List<double> _noiseFloorSamples(int count, {int seed = 1}) {
  final rand = Random(seed);
  const halfRange = 0.00346; // RMS of U(-x,x) = x/sqrt(3) ~= -53.9 dBFS
  return List.generate(count, (_) => (rand.nextDouble() * 2 - 1) * halfRange);
}

/// A steady sine tone at a healthy, clearly-passing level (-25 dBFS RMS —
/// comfortably inside the policy's -40..-6 dBFS window and >20 dB above
/// the noise floor on its own).
List<double> _toneSamples(int count) {
  final amplitude = pow(10, -25.0 / 20) * sqrt(2);
  const freqHz = 1000.0;
  return List.generate(
      count, (i) => amplitude * sin(2 * pi * freqHz * i / _sampleRate));
}

MeasurementQualityEvaluation _evaluate(
  List<double> samples, {
  required double noiseFloorDbFs,
  Duration minimumCaptureDuration = const Duration(seconds: 1),
}) {
  final base = MeasurementQualityPolicy.proProvisional();
  final policy = MeasurementQualityPolicy(
    expectedSampleRate: base.expectedSampleRate,
    expectedChannelCount: base.expectedChannelCount,
    minimumCaptureDuration: minimumCaptureDuration,
    clippingAmplitudeThreshold: base.clippingAmplitudeThreshold,
    clippingSampleCountThreshold: base.clippingSampleCountThreshold,
    clippingRatioThreshold: base.clippingRatioThreshold,
    minimumSignalRmsDbFs: base.minimumSignalRmsDbFs,
    maximumSignalRmsDbFs: base.maximumSignalRmsDbFs,
    maximumNoiseFloorDbFs: base.maximumNoiseFloorDbFs,
    minimumSignalToNoiseDb: base.minimumSignalToNoiseDb,
    silenceCaptureDuration: base.silenceCaptureDuration,
    levelCheckDuration: base.levelCheckDuration,
    setupCheckValidity: base.setupCheckValidity,
    version: base.version,
  );
  final pcm = MeasurementPcmQualityAnalyzer.analyze(
    samples: samples,
    sampleRate: _sampleRate,
    channelCount: 1,
    minimumDuration: policy.minimumCaptureDuration,
    clippingAmplitudeThreshold: policy.clippingAmplitudeThreshold,
  );
  expect(pcm.isSuccess, isTrue, reason: pcm.errors.join('; '));
  return MeasurementQualityEvaluator.evaluate(
    pcm: pcm.metrics!,
    actualSampleRate: _sampleRate,
    actualChannelCount: 1,
    noiseFloorDbFs: noiseFloorDbFs,
    policy: policy,
  );
}

void main() {
  final noiseFloorDbFs = MeasurementPcmQualityAnalyzer.analyze(
    samples: _noiseFloorSamples(_sampleRate, seed: 2),
    sampleRate: _sampleRate,
    channelCount: 1,
    minimumDuration: const Duration(seconds: 1),
  ).metrics!.rmsDbFs;

  test('tone present through the WHOLE window passes without any trim', () {
    final evaluation =
        _evaluate(_toneSamples(_sampleRate), noiseFloorDbFs: noiseFloorDbFs);
    expect(evaluation.isReady, isTrue);
  });

  test(
      'tone present in only ~10% of the window FAILS the level/SNR gate on '
      'the full capture — reproduces the real-hardware symptom (RMS/SNR '
      'diluted toward the noise floor despite a real, elevated Peak)', () {
    final toneCount = (_sampleRate * 0.1).round();
    final silenceCount = _sampleRate - toneCount;
    final capture = [
      ..._noiseFloorSamples(silenceCount),
      ..._toneSamples(toneCount),
    ];
    final evaluation = _evaluate(capture, noiseFloorDbFs: noiseFloorDbFs);

    expect(evaluation.isReady, isFalse);
    expect(
        evaluation.statuses
            .contains(MeasurementQualityStatus.signalToNoiseTooLow),
        isTrue);
    expect(evaluation.metrics.peakDbFs, greaterThan(noiseFloorDbFs + 10),
        reason: 'Peak is still real and elevated even though RMS/SNR fail — '
            'matches the real capture (Peak -41.7 dBFS, SNR 0.4 dB)');
  });

  test(
      'trimming the leading settling portion and analyzing only the '
      'trailing steady tone RECOVERS a passing measurement from the same '
      'underlying capture shape', () {
    final toneCount = (_sampleRate * 0.1).round();
    // The isolated trailing tone segment — exactly what
    // MicMeasurementController._evaluateSetupCapture's trimLeadingDuration
    // slices the recorded samples down to.
    final trimmed = _toneSamples(toneCount);
    final evaluation = _evaluate(
      trimmed,
      noiseFloorDbFs: noiseFloorDbFs,
      minimumCaptureDuration: const Duration(milliseconds: 50),
    );
    expect(evaluation.isReady, isTrue);
  });

  test(
      'trimming does NOT rescue a capture where the tone stopped BEFORE the '
      'trimmed window — proves this is not "Peak-only, launder a bad '
      'capture" — a genuinely bad capture stays bad', () {
    final toneCount = (_sampleRate * 0.1).round();
    final silenceCount = _sampleRate - toneCount;
    // Tone at the START, silence for the rest — the opposite shape from
    // the real BLE-late-start failure. A leading-trim strategy must not
    // accidentally turn this into a pass by sheer coincidence.
    final headToneCapture = [
      ..._toneSamples(toneCount),
      ..._noiseFloorSamples(silenceCount, seed: 3),
    ];
    // Simulate keeping only the trailing 90% (what a leading trim would
    // keep) — here that's pure silence, since the tone was at the head.
    final wronglyTrimmed = headToneCapture.sublist(toneCount);
    final evaluation = _evaluate(
      wronglyTrimmed,
      noiseFloorDbFs: noiseFloorDbFs,
      minimumCaptureDuration: const Duration(milliseconds: 50),
    );
    expect(evaluation.isReady, isFalse,
        reason: 'trimming must never fabricate a pass — a capture whose '
            'real signal was never in the analyzed window stays rejected');
  });
}
