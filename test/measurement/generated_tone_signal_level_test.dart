// FINAL QA CLOSURE #3 follow-up — "INPUT LEVEL CLOSURE, IDENTIFY LOW LEVEL
// SOURCE" §2: audit whether the generated test-signal itself is too quiet.
//
// Real-hardware evidence (after the play()-lifecycle fix landed and was
// confirmed PASS): tone-window block RMS is still ~-49 to -54 dBFS, almost
// identical to the ~-53.8 dBFS UMIK background noise floor. This test
// decodes buildPinkNoiseWavBytes' own output through the SAME
// parser/analyzer the real capture path uses (MeasurementWavParser +
// MeasurementPcmQualityAnalyzer) and asserts its peak/RMS sit at a healthy,
// close-to-full-scale level — ruling out "the generated file itself is too
// quiet" as the low-level root cause, so investigation can stay focused on
// device binding / playback / room-acoustic factors instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_pcm_quality_analyzer.dart';
import 'package:tunai_pro/core/measurement/measurement_wav_parser.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart';

void main() {
  test(
      'buildPinkNoiseWavBytes generates a signal with peak within 6dB of '
      'full scale — not an inherently quiet source file', () {
    final bytes = MicMeasurementController.buildPinkNoiseWavBytes(
      totalSec: 3,
    );
    final wav = MeasurementWavParser.parse(bytes);
    expect(wav.isSuccess, isTrue);

    final samples = MeasurementWavParser.extractNormalizedSamples(bytes, wav);
    final metrics = MeasurementPcmQualityAnalyzer.analyze(
      samples: samples,
      sampleRate: wav.sampleRate!,
      channelCount: wav.channelCount!,
      minimumDuration: Duration.zero,
      clippingAmplitudeThreshold: 0.98,
    ).metrics!;

    // Real measured value at time of writing: peak ~-1.9dBFS, RMS ~-14dBFS.
    // A generous bound (not a tight pin) so minor algorithm tweaks don't
    // spuriously fail this — the point is "not effectively silent", not an
    // exact number.
    expect(metrics.peakDbFs, greaterThan(-6.0),
        reason: 'Generated tone peak is far below full scale — if this '
            'ever regresses, the SOURCE file itself would explain a low '
            'capture level, not device binding or playback.');
    expect(metrics.rmsDbFs, greaterThan(-20.0),
        reason: 'Generated tone RMS is far below what a healthy pink-noise '
            'test signal should be.');
  });

  test('buildStereoPinkNoiseWavBytes (leftActive) generates the same '
      'healthy signal level on the active channel', () {
    final bytes = MicMeasurementController.buildStereoPinkNoiseWavBytes(
      leftActive: true,
      totalSec: 3,
    );
    final wav = MeasurementWavParser.parse(bytes);
    expect(wav.isSuccess, isTrue);
    expect(wav.channelCount, 2);

    final samples = MeasurementWavParser.extractNormalizedSamples(bytes, wav);
    // De-interleave the active (left) channel only.
    final left = <double>[
      for (var i = 0; i < samples.length; i += 2) samples[i],
    ];
    final metrics = MeasurementPcmQualityAnalyzer.analyze(
      samples: left,
      sampleRate: wav.sampleRate!,
      channelCount: 1,
      minimumDuration: Duration.zero,
      clippingAmplitudeThreshold: 0.98,
    ).metrics!;

    expect(metrics.peakDbFs, greaterThan(-6.0));
    expect(metrics.rmsDbFs, greaterThan(-20.0));
  });
}
