// Phase 3-D1 — measurement_quality_model.dart: MeasurementQualityEvaluator
// boundary/classification tests. Pure — feeds already-computed
// MeasurementPcmQualityMetrics through the evaluator against a policy.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_pcm_quality_analyzer.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_model.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_policy.dart';

MeasurementPcmQualityMetrics _pcm({
  double peakDbFs = -10,
  double rmsDbFs = -20,
  int clippedSampleCount = 0,
  double clippedSampleRatio = 0.0,
  Duration duration = const Duration(seconds: 3),
}) =>
    MeasurementPcmQualityMetrics(
      peakAmplitude: 0.3,
      peakDbFs: peakDbFs,
      rmsAmplitude: 0.1,
      rmsDbFs: rmsDbFs,
      clippedSampleCount: clippedSampleCount,
      clippedSampleRatio: clippedSampleRatio,
      sampleCount: 144000,
      duration: duration,
    );

void main() {
  final policy = MeasurementQualityPolicy.proProvisional();

  group('ready path', () {
    test('a normal-level, clean, correctly-formatted capture is ready', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(rmsDbFs: -20),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(eval.isReady, isTrue);
      expect(eval.statuses, {MeasurementQualityStatus.ready});
    });
  });

  group('sample rate / channel mismatch', () {
    test('a different actual sample rate than expected is flagged', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(),
        actualSampleRate: 44100,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(
          eval.statuses, contains(MeasurementQualityStatus.sampleRateMismatch));
      expect(eval.isReady, isFalse);
    });

    test('a different actual channel count than expected is flagged', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: 2,
        policy: policy,
      );
      expect(eval.statuses, contains(MeasurementQualityStatus.channelMismatch));
    });
  });

  group('capture too short', () {
    test('duration below policy minimum is flagged', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(duration: const Duration(milliseconds: 200)),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(eval.statuses, contains(MeasurementQualityStatus.captureTooShort));
    });
  });

  group('level boundaries', () {
    test('RMS below minimumSignalRmsDbFs -> inputLevelTooLow', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(rmsDbFs: policy.minimumSignalRmsDbFs - 1),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(
          eval.statuses, contains(MeasurementQualityStatus.inputLevelTooLow));
    });

    test(
        'RMS exactly at minimumSignalRmsDbFs is NOT flagged (boundary is '
        'inclusive-pass)', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(rmsDbFs: policy.minimumSignalRmsDbFs),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(eval.statuses,
          isNot(contains(MeasurementQualityStatus.inputLevelTooLow)));
    });

    test('RMS above maximumSignalRmsDbFs -> inputLevelTooHigh', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(rmsDbFs: policy.maximumSignalRmsDbFs + 1),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(
          eval.statuses, contains(MeasurementQualityStatus.inputLevelTooHigh));
    });
  });

  group('clipping', () {
    test('clippedSampleCount at/above threshold -> clipping', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(clippedSampleCount: policy.clippingSampleCountThreshold),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(eval.statuses, contains(MeasurementQualityStatus.clipping));
    });

    test(
        'clippedSampleRatio at/above threshold -> clipping even with low '
        'absolute count', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(
            clippedSampleCount: 1,
            clippedSampleRatio: policy.clippingRatioThreshold),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(eval.statuses, contains(MeasurementQualityStatus.clipping));
    });

    test('below both clipping thresholds is not flagged', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(clippedSampleCount: 0, clippedSampleRatio: 0.0),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(eval.statuses, isNot(contains(MeasurementQualityStatus.clipping)));
    });
  });

  group('noise floor / SNR', () {
    test('noiseFloorDbFs above policy max -> noiseFloorTooHigh', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        noiseFloorDbFs: policy.maximumNoiseFloorDbFs + 1,
        policy: policy,
      );
      expect(
          eval.statuses, contains(MeasurementQualityStatus.noiseFloorTooHigh));
      expect(eval.metrics.noiseFloorDbFs, policy.maximumNoiseFloorDbFs + 1);
    });

    test('SNR below policy minimum -> signalToNoiseTooLow', () {
      // rms -20, noise floor -25 -> SNR 5dB, below the 20dB minimum.
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(rmsDbFs: -20),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        noiseFloorDbFs: -25,
        policy: policy,
      );
      expect(eval.statuses,
          contains(MeasurementQualityStatus.signalToNoiseTooLow));
      expect(eval.metrics.signalToNoiseDb, closeTo(5.0, 1e-9));
    });

    test('adequate SNR is not flagged', () {
      // rms -20, noise floor -60 -> SNR 40dB, comfortably above minimum.
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(rmsDbFs: -20),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        noiseFloorDbFs: -60,
        policy: policy,
      );
      expect(eval.statuses,
          isNot(contains(MeasurementQualityStatus.signalToNoiseTooLow)));
    });

    test(
        'no noiseFloorDbFs supplied -> signalToNoiseDb stays null, no SNR '
        'status ever raised', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        policy: policy,
      );
      expect(eval.metrics.signalToNoiseDb, isNull);
      expect(eval.statuses,
          isNot(contains(MeasurementQualityStatus.signalToNoiseTooLow)));
    });

    group(
        'mode: noiseFloorCapture (P0 root-cause fix + sibling semantics fix) '
        '— a noise-floor-only capture must never self-compare SNR, nor '
        'apply signal-relative-to-expected-level checks', () {
      test(
          'passing the capture\'s own RMS as noiseFloorDbFs (self-compare, '
          'as measureNoiseFloor() does) with mode: noiseFloorCapture never '
          'raises signalToNoiseTooLow — this reproduces the exact '
          'real-hardware bug (SNR self-compare = 0dB, always below the '
          '20dB minimum, unconditionally blocking every background check)',
          () {
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -37.1),
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          noiseFloorDbFs: -37.1, // self-compare, exactly like selfIsNoiseFloor
          policy: policy,
          mode: MeasurementQualityEvaluationMode.noiseFloorCapture,
        );
        expect(eval.statuses,
            isNot(contains(MeasurementQualityStatus.signalToNoiseTooLow)));
        expect(eval.metrics.signalToNoiseDb, isNull,
            reason: 'a self-compared 0dB is a meaningless placeholder, not '
                'a real SNR value — must stay null, never a fabricated 0.');
      });

      test('the SAME self-compared inputs WOULD have raised the bug at the '
          'default signalCapture mode — proves mode is what fixes this, '
          'not some other change', () {
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -37.1),
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          noiseFloorDbFs: -37.1,
          policy: policy,
          // mode defaults to signalCapture here.
        );
        expect(eval.statuses,
            contains(MeasurementQualityStatus.signalToNoiseTooLow),
            reason: 'sanity check: proves this really was the bug — a '
                'self-compared 0dB SNR is always < the 20dB minimum.');
      });

      test('noiseFloorTooHigh is still correctly raised regardless of mode '
          '— the fix does not touch the noise-floor threshold check at all',
          () {
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -37.1),
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          noiseFloorDbFs: -37.1,
          policy: policy,
          mode: MeasurementQualityEvaluationMode.noiseFloorCapture,
        );
        expect(eval.statuses,
            contains(MeasurementQualityStatus.noiseFloorTooHigh));
        expect(eval.metrics.noiseFloorDbFs, -37.1,
            reason: 'the noise floor VALUE must still be reported for '
                'display, even though SNR is not computed from it.');
      });

      test(
          'sibling fix — noise -55 dBFS (genuinely quiet, under the -50 '
          'maximumNoiseFloorDbFs limit): NO inputLevelTooLow, NO SNR '
          'blocker, fully ready. Before the sibling fix this was '
          'structurally unreachable: minimumSignalRmsDbFs (-40) and '
          'maximumNoiseFloorDbFs (-50) don\'t overlap, so a genuinely quiet '
          'background always tripped inputLevelTooLow.', () {
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -55),
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          noiseFloorDbFs: -55,
          policy: policy,
          mode: MeasurementQualityEvaluationMode.noiseFloorCapture,
        );
        expect(eval.isReady, isTrue);
        expect(eval.statuses, {MeasurementQualityStatus.ready});
      });

      test('noise floor exactly at the -50 dBFS boundary -> zero '
          'signal-level blockers of any kind', () {
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -50),
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          noiseFloorDbFs: -50,
          policy: policy,
          mode: MeasurementQualityEvaluationMode.noiseFloorCapture,
        );
        expect(
            eval.statuses
                .contains(MeasurementQualityStatus.inputLevelTooLow),
            isFalse);
        expect(
            eval.statuses
                .contains(MeasurementQualityStatus.inputLevelTooHigh),
            isFalse);
      });

      test(
          'mode: noiseFloorCapture never adds signalToNoiseTooLow '
          'regardless of how quiet the self-compared floor is — the fix is '
          'unconditional, not just for this one reported -37.1 dBFS case',
          () {
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -60),
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          noiseFloorDbFs: -60,
          policy: policy,
          mode: MeasurementQualityEvaluationMode.noiseFloorCapture,
        );
        expect(eval.statuses,
            isNot(contains(MeasurementQualityStatus.signalToNoiseTooLow)));
        expect(eval.metrics.signalToNoiseDb, isNull);
        expect(
            eval.statuses
                .contains(MeasurementQualityStatus.inputLevelTooLow),
            isFalse,
            reason: 'sibling fix: -60 dBFS would trip inputLevelTooLow at '
                'the default signalCapture mode, but must not in '
                'noiseFloorCapture mode.');
      });

      test(
          'clipping IS still checked in noiseFloorCapture mode — a raw '
          'hardware/gain artifact independent of whether a signal was '
          'expected, not a signal-relative-level check', () {
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -55, clippedSampleCount: 999),
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          noiseFloorDbFs: -55,
          policy: policy,
          mode: MeasurementQualityEvaluationMode.noiseFloorCapture,
        );
        expect(eval.statuses, contains(MeasurementQualityStatus.clipping));
      });

      test('a REAL (non-self) SNR comparison — e.g. the legacy WAV level '
          'check comparing its signal against a genuinely prior, separate '
          'background capture — is completely unaffected: SNR is still '
          'computed and can still legitimately fail', () {
        // rms -20 (a real signal), noise floor -25 (a real, PRIOR, separate
        // background capture) -> SNR 5dB, below the 20dB minimum. This is
        // the wavCapture / legacy manual-check path — mode is left at its
        // default (signalCapture), exactly as _evaluateSetupCapture calls
        // it when selfIsNoiseFloor is false.
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -20),
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          noiseFloorDbFs: -25,
          policy: policy,
        );
        expect(eval.statuses,
            contains(MeasurementQualityStatus.signalToNoiseTooLow));
        expect(eval.metrics.signalToNoiseDb, closeTo(5.0, 1e-9));
      });

      test(
          'a normal SIGNAL capture (default signalCapture mode) still '
          'raises inputLevelTooLow when appropriate — the sibling fix only '
          'suppresses this for noiseFloorCapture mode', () {
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -55), // well below minimumSignalRmsDbFs (-40)
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          policy: policy,
        );
        expect(
            eval.statuses.contains(MeasurementQualityStatus.inputLevelTooLow),
            isTrue);
      });

      test(
          'a normal SIGNAL capture (default signalCapture mode) still '
          'raises inputLevelTooHigh when appropriate', () {
        final eval = MeasurementQualityEvaluator.evaluate(
          pcm: _pcm(rmsDbFs: -1), // above maximumSignalRmsDbFs (-6)
          actualSampleRate: policy.expectedSampleRate,
          actualChannelCount: policy.expectedChannelCount,
          policy: policy,
        );
        expect(
            eval.statuses
                .contains(MeasurementQualityStatus.inputLevelTooHigh),
            isTrue);
      });
    });
  });

  group('multiple simultaneous problems', () {
    test(
        'a capture with several problems reports all of them, not just '
        'one', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(
          rmsDbFs: policy.minimumSignalRmsDbFs - 5,
          clippedSampleCount: policy.clippingSampleCountThreshold + 5,
          duration: const Duration(milliseconds: 100),
        ),
        actualSampleRate: 22050,
        actualChannelCount: 2,
        policy: policy,
      );
      expect(
          eval.statuses,
          containsAll([
            MeasurementQualityStatus.captureTooShort,
            MeasurementQualityStatus.sampleRateMismatch,
            MeasurementQualityStatus.channelMismatch,
            MeasurementQualityStatus.inputLevelTooLow,
            MeasurementQualityStatus.clipping,
          ]));
      expect(eval.statuses, isNot(contains(MeasurementQualityStatus.ready)));
      expect(eval.isReady, isFalse);
    });
  });

  group('JSON round-trip', () {
    test('MeasurementQualityMetrics round-trips through JSON', () {
      final eval = MeasurementQualityEvaluator.evaluate(
        pcm: _pcm(rmsDbFs: -20),
        actualSampleRate: policy.expectedSampleRate,
        actualChannelCount: policy.expectedChannelCount,
        noiseFloorDbFs: -55,
        policy: policy,
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final decoded = MeasurementQualityMetrics.fromJson(eval.metrics.toJson());
      expect(decoded.rmsDbFs, eval.metrics.rmsDbFs);
      expect(decoded.noiseFloorDbFs, eval.metrics.noiseFloorDbFs);
      expect(decoded.signalToNoiseDb, eval.metrics.signalToNoiseDb);
      expect(decoded.actualSampleRate, eval.metrics.actualSampleRate);
    });
  });
}
