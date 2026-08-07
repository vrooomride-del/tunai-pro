// Phase 3-D1 — measurement_pcm_quality_analyzer.dart pure metrics tests.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_pcm_quality_analyzer.dart';

List<double> _sine({
  required double amplitude,
  required int sampleRate,
  required Duration duration,
  double freqHz = 1000,
}) {
  final count = (sampleRate * duration.inMilliseconds / 1000).round();
  return [
    for (var i = 0; i < count; i++)
      amplitude * math.sin(2 * math.pi * freqHz * i / sampleRate),
  ];
}

void main() {
  group('digital silence', () {
    test('exact zero samples produce the silence floor, not -infinity', () {
      final samples = List<double>.filled(48000, 0.0);
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: samples,
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: const Duration(seconds: 1),
      );
      expect(result.isSuccess, isTrue);
      expect(result.metrics!.peakDbFs, kMeasurementDbFsSilenceFloor);
      expect(result.metrics!.rmsDbFs, kMeasurementDbFsSilenceFloor);
      expect(result.metrics!.peakDbFs.isFinite, isTrue);
      expect(result.metrics!.rmsDbFs.isFinite, isTrue);
      expect(result.metrics!.clippedSampleCount, 0);
    });
  });

  group('known-RMS fixture', () {
    test(
        'a full-scale sine wave has RMS close to amplitude/sqrt(2) '
        '(-3.01 dBFS for a 1.0-amplitude sine)', () {
      final samples = _sine(
          amplitude: 0.99,
          sampleRate: 48000,
          duration: const Duration(seconds: 2));
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: samples,
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: const Duration(seconds: 1),
      );
      expect(result.isSuccess, isTrue);
      // RMS of a sine of amplitude A is A/sqrt(2).
      final expectedRms = 0.99 / math.sqrt(2);
      expect(result.metrics!.rmsAmplitude, closeTo(expectedRms, 0.01));
      expect(result.metrics!.peakAmplitude, closeTo(0.99, 0.01));
    });

    test(
        'a half-amplitude sine reads about 6dB quieter in RMS than '
        'full-amplitude', () {
      final fullResult = MeasurementPcmQualityAnalyzer.analyze(
        samples: _sine(
            amplitude: 0.8,
            sampleRate: 48000,
            duration: const Duration(seconds: 1)),
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: const Duration(seconds: 1),
      );
      final halfResult = MeasurementPcmQualityAnalyzer.analyze(
        samples: _sine(
            amplitude: 0.4,
            sampleRate: 48000,
            duration: const Duration(seconds: 1)),
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: const Duration(seconds: 1),
      );
      final delta = fullResult.metrics!.rmsDbFs - halfResult.metrics!.rmsDbFs;
      expect(delta, closeTo(6.02, 0.1));
    });
  });

  group(
      'level classification inputs (raw metrics only — thresholds live '
      'in the policy/evaluator, not here)', () {
    test('a low-level signal produces a low rmsDbFs', () {
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: _sine(
            amplitude: 0.001,
            sampleRate: 48000,
            duration: const Duration(seconds: 1)),
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: const Duration(seconds: 1),
      );
      expect(result.metrics!.rmsDbFs, lessThan(-40));
    });

    test('a hot signal near full scale produces a high rmsDbFs', () {
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: _sine(
            amplitude: 0.95,
            sampleRate: 48000,
            duration: const Duration(seconds: 1)),
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: const Duration(seconds: 1),
      );
      expect(result.metrics!.rmsDbFs, greaterThan(-6));
    });
  });

  group('clipping', () {
    test('samples at/above the clipping threshold are counted', () {
      final samples = [
        for (var i = 0; i < 100; i++) i < 10 ? 0.99 : 0.1,
      ];
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: samples,
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: Duration.zero,
        clippingAmplitudeThreshold: 0.98,
      );
      expect(result.metrics!.clippedSampleCount, 10);
      expect(result.metrics!.clippedSampleRatio, closeTo(0.1, 1e-9));
    });

    test('no samples reach the threshold -> zero clipping', () {
      final samples = List<double>.filled(1000, 0.5);
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: samples,
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: Duration.zero,
      );
      expect(result.metrics!.clippedSampleCount, 0);
      expect(result.metrics!.clippedSampleRatio, 0.0);
    });

    test('a custom (lower) clipping threshold changes the count', () {
      final samples = List<double>.filled(100, 0.5);
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: samples,
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: Duration.zero,
        clippingAmplitudeThreshold: 0.4,
      );
      expect(result.metrics!.clippedSampleCount, 100);
    });
  });

  group('rejections', () {
    test('empty samples are rejected', () {
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: const [],
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: Duration.zero,
      );
      expect(result.isSuccess, isFalse);
      expect(result.metrics, isNull);
    });

    test('invalid sampleRate/channelCount are rejected', () {
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: [0.1, 0.2],
        sampleRate: 0,
        channelCount: 1,
        minimumDuration: Duration.zero,
      );
      expect(result.isSuccess, isFalse);
    });

    test('a NaN/Infinite sample is rejected as malformed', () {
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: [0.1, double.nan, 0.2],
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: Duration.zero,
      );
      expect(result.isSuccess, isFalse);
    });

    test('too-short capture (below minimumDuration) is rejected', () {
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: List<double>.filled(100, 0.1), // ~2ms at 48kHz
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: const Duration(seconds: 1),
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('shorter than')), isTrue);
    });

    test(
        'malformed channel alignment (fewer samples than one frame) is '
        'rejected', () {
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: [0.1], // 1 sample, but channelCount=2 needs >=2 per frame
        sampleRate: 48000,
        channelCount: 2,
        minimumDuration: Duration.zero,
      );
      expect(result.isSuccess, isFalse);
    });
  });

  group('finite-only output guarantee', () {
    test('every numeric field in the result is finite for a normal signal', () {
      final result = MeasurementPcmQualityAnalyzer.analyze(
        samples: _sine(
            amplitude: 0.3,
            sampleRate: 48000,
            duration: const Duration(seconds: 1)),
        sampleRate: 48000,
        channelCount: 1,
        minimumDuration: const Duration(seconds: 1),
      );
      final m = result.metrics!;
      expect(m.peakAmplitude.isFinite, isTrue);
      expect(m.peakDbFs.isFinite, isTrue);
      expect(m.rmsAmplitude.isFinite, isTrue);
      expect(m.rmsDbFs.isFinite, isTrue);
      expect(m.clippedSampleRatio.isFinite, isTrue);
    });
  });
}
