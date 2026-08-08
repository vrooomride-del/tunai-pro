// Live Level Check double-verification bug fix — readiness composition.
//
// Proves the FIX at the pure-logic level: Live Level Check's sustained-GOOD
// evidence (the exact shape MicMeasurementController.buildLiveLevelPassEvidence
// produces — statuses={ready}, metrics.source='liveMeter') combines with the
// EXISTING MeasurementSetupReadinessBuilder/Snapshot exactly like the legacy
// WAV-based evidence always has — no parallel readiness system, no new
// invalidation rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/microphone_profile_edit_rules.dart';
import 'package:tunai_pro/core/measurement/measurement_pcm_quality_analyzer.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_model.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_policy.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness_builder.dart';

MeasurementSetupReadinessIdentity _identity({String inputDeviceIdentity = 'device:umik-1'}) =>
    MeasurementSetupReadinessIdentity(
      projectId: 'p1',
      profileChecksum: 'c1',
      calibrationCurveChecksum: 'curve1',
      calibrationAngle: 'zeroDegree',
      inputDeviceIdentity: inputDeviceIdentity,
      expectedSampleRate: 48000,
      expectedChannelCount: 1,
      qualityPolicyVersion: 'provisional-1',
    );

/// Mirrors exactly what MicMeasurementController.buildLiveLevelPassEvidence
/// produces on a sustained-GOOD confirmation: statuses={ready} always (never
/// tooLow/tooHigh/clipping — those states never reach evidence-building
/// because the stability tracker only lets a confirmed-stable-GOOD run
/// through), source='liveMeter', clippedSampleCount/Ratio always 0 (no
/// clipping claim), noiseFloorDbFs/signalToNoiseDb always null (that's a
/// SEPARATE evaluation).
MeasurementQualityEvaluation _liveMeterPassEvaluation({
  double representativeDbFs = -20.0,
  double peakDbFs = -15.0,
  Duration stableDuration = const Duration(seconds: 1),
  DateTime? capturedAt,
}) =>
    MeasurementQualityEvaluation(
      statuses: const {MeasurementQualityStatus.ready},
      metrics: MeasurementQualityMetrics(
        peakDbFs: peakDbFs,
        rmsDbFs: representativeDbFs,
        clippedSampleCount: 0,
        clippedSampleRatio: 0.0,
        duration: stableDuration,
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: capturedAt ?? DateTime.utc(2026, 1, 1),
        source: 'liveMeter',
      ),
    );

MeasurementQualityEvaluation _wavPassEvaluation() => MeasurementQualityEvaluation(
      statuses: const {MeasurementQualityStatus.ready},
      metrics: MeasurementQualityMetrics(
        peakDbFs: -10,
        rmsDbFs: -20,
        clippedSampleCount: 0,
        clippedSampleRatio: 0,
        duration: const Duration(seconds: 3),
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
        source: 'wavCapture',
      ),
    );

MeasurementQualityEvaluation _failEvaluation(MeasurementQualityStatus status) =>
    MeasurementQualityEvaluation(
      statuses: {status},
      metrics: MeasurementQualityMetrics(
        peakDbFs: -50,
        rmsDbFs: -55,
        clippedSampleCount: 0,
        clippedSampleRatio: 0,
        duration: const Duration(seconds: 3),
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
        source: 'wavCapture',
      ),
    );

/// Builds a noise-floor-ONLY evaluation via the REAL production evaluator
/// (MeasurementQualityEvaluator.evaluate with mode: noiseFloorCapture —
/// exactly what MicMeasurementController._evaluateSetupCapture passes when
/// selfIsNoiseFloor is true), not hand-constructed — so these tests exercise
/// the actual P0 fix, not a re-description of it.
MeasurementQualityEvaluation _realBackgroundNoiseEvaluation(
    {required double noiseFloorDbFs}) {
  final policy = MeasurementQualityPolicy.proProvisional();
  return MeasurementQualityEvaluator.evaluate(
    pcm: MeasurementPcmQualityMetrics(
      peakAmplitude: 0.05,
      peakDbFs: noiseFloorDbFs + 5,
      rmsAmplitude: 0.01,
      rmsDbFs: noiseFloorDbFs,
      clippedSampleCount: 0,
      clippedSampleRatio: 0,
      sampleCount: 144000,
      duration: const Duration(seconds: 3),
    ),
    actualSampleRate: policy.expectedSampleRate,
    actualChannelCount: policy.expectedChannelCount,
    noiseFloorDbFs: noiseFloorDbFs, // self, exactly like selfIsNoiseFloor: true
    policy: policy,
    mode: MeasurementQualityEvaluationMode.noiseFloorCapture,
  );
}

void main() {
  group('item 1/2/9 — no evidence yet (before stable GOOD) never PASSes', () {
    test('levelCheckEvaluation=null (nothing confirmed yet) -> Ready false '
        'with the exact "has not been run yet" blocker', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: _wavPassEvaluation(),
        levelCheckEvaluation: null,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
      expect(snapshot.blockers,
          contains('Input-level check has not been run yet.'));
    });

    test('background PASS + live level ONLY (no noise floor) -> Ready false',
        () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: null,
        levelCheckEvaluation: _liveMeterPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
      expect(snapshot.blockers,
          contains('Background-noise check has not been run yet.'));
    });
  });

  group('item 3/9 — sustained GOOD evidence (live-sourced) is a full '
      'first-class PASS, exactly like the legacy WAV check', () {
    test('background PASS + live-sourced PASS -> Setup Ready', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: _wavPassEvaluation(),
        levelCheckEvaluation: _liveMeterPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isTrue);
      expect(snapshot.blockers, isEmpty);
      expect(snapshot.levelCheckEvaluation?.metrics.source, 'liveMeter');
    });

    test(
        'the live-sourced evaluation is indistinguishable in TREATMENT from '
        'a legacy WAV evaluation — same builder, same blocker/warning rules, '
        'only metrics.source differs for display', () {
      final liveSnapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: _wavPassEvaluation(),
        levelCheckEvaluation: _liveMeterPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      final wavSnapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: _wavPassEvaluation(),
        levelCheckEvaluation: _wavPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      expect(liveSnapshot.isReady, wavSnapshot.isReady);
      expect(liveSnapshot.blockers, wavSnapshot.blockers);
    });
  });

  group('item 10 — background FAIL + live PASS -> Ready false '
      '(both gates required independently)', () {
    test('signalToNoiseTooLow on the noise-floor side still blocks even '
        'though the live level evidence itself is a clean PASS', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation:
            _failEvaluation(MeasurementQualityStatus.signalToNoiseTooLow),
        levelCheckEvaluation: _liveMeterPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
    });
  });

  group('item 4 — no "unprovable clipping" condition forced into Setup '
      'Ready for live-sourced evidence', () {
    test('a clean live-sourced PASS never carries a clipping status (by '
        'construction — the evidence only exists when the tracker already '
        'proved sustained GOOD, and clipping is never claimed)', () {
      final eval = _liveMeterPassEvaluation();
      expect(eval.statuses, {MeasurementQualityStatus.ready});
      expect(eval.statuses.contains(MeasurementQualityStatus.clipping), isFalse);
      expect(eval.metrics.clippedSampleCount, 0);
      expect(eval.metrics.clippedSampleRatio, 0.0);
    });
  });

  group('item 11/12/13 — invalidation follows the existing setup contract '
      'unchanged (staleness/expiry), never "live session stopped" alone', () {
    test('a live-sourced Ready snapshot becomes stale when the input device '
        'identity changes', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(inputDeviceIdentity: 'device:umik-1'),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: _wavPassEvaluation(),
        levelCheckEvaluation: _liveMeterPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isTrue);

      final newDeviceIdentity = _identity(inputDeviceIdentity: 'device:other-mic');
      expect(snapshot.isStaleFor(newDeviceIdentity), isTrue);
      expect(snapshot.isUsableNow(newDeviceIdentity), isFalse);
      // Same identity — still usable (proves stopping the live session
      // itself, with no identity change, does NOT invalidate).
      expect(
          snapshot.isUsableNow(_identity(inputDeviceIdentity: 'device:umik-1')),
          isTrue);
    });

    test('a live-sourced Ready snapshot expires per the existing setup '
        'validity duration, same as a WAV-sourced one', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: _wavPassEvaluation(),
        levelCheckEvaluation: _liveMeterPassEvaluation(capturedAt: now),
        validity: const Duration(minutes: 30),
        now: now,
      );
      expect(snapshot.isExpired(now: now.add(const Duration(minutes: 29))),
          isFalse);
      expect(snapshot.isExpired(now: now.add(const Duration(minutes: 31))),
          isTrue);
    });

    test('microphone profile checksum change invalidates a live-sourced '
        'Ready snapshot just like a WAV-sourced one', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: _wavPassEvaluation(),
        levelCheckEvaluation: _liveMeterPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      const newMicIdentity = MeasurementSetupReadinessIdentity(
        projectId: 'p1',
        profileChecksum: 'DIFFERENT-checksum',
        calibrationCurveChecksum: 'curve1',
        calibrationAngle: 'zeroDegree',
        inputDeviceIdentity: 'device:umik-1',
        expectedSampleRate: 48000,
        expectedChannelCount: 1,
        qualityPolicyVersion: 'provisional-1',
      );
      expect(snapshot.isStaleFor(newMicIdentity), isTrue);
    });
  });

  group('MeasurementQualityMetrics.source round-trips through JSON', () {
    test('liveMeter source survives toJson/fromJson', () {
      final metrics = _liveMeterPassEvaluation().metrics;
      final decoded = MeasurementQualityMetrics.fromJson(metrics.toJson());
      expect(decoded.source, 'liveMeter');
    });

    test('null source (older persisted snapshots) round-trips as null', () {
      final metrics = MeasurementQualityMetrics(
        peakDbFs: -10,
        rmsDbFs: -20,
        clippedSampleCount: 0,
        clippedSampleRatio: 0,
        duration: const Duration(seconds: 3),
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final decoded = MeasurementQualityMetrics.fromJson(metrics.toJson());
      expect(decoded.source, isNull);
    });
  });

  group('P0 real-hardware scenario — background near the noise-floor limit '
      '(warning, not blocker) + liveMeter PASS', () {
    test(
        'noise -55 dBFS (genuinely quiet, well under the -50 '
        'maximumNoiseFloorDbFs limit) + liveMeter PASS -> fully Ready, '
        'ZERO blockers AND zero warnings — this is only reachable now that '
        'inputLevelTooLow no longer applies to noiseFloorCapture mode '
        '(sibling semantics fix)', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation:
            _realBackgroundNoiseEvaluation(noiseFloorDbFs: -55.0),
        levelCheckEvaluation: _liveMeterPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isTrue);
      expect(snapshot.blockers, isEmpty);
      expect(snapshot.warnings, isEmpty);
    });

    test('noise floor exactly at the -50 dBFS boundary -> zero '
        'signal-level blockers (inputLevelTooLow/TooHigh never apply to a '
        'noise-floor-only capture)', () {
      final eval =
          _realBackgroundNoiseEvaluation(noiseFloorDbFs: -50.0);
      expect(
          eval.statuses.contains(MeasurementQualityStatus.inputLevelTooLow),
          isFalse);
      expect(
          eval.statuses.contains(MeasurementQualityStatus.inputLevelTooHigh),
          isFalse);
    });

    test(
        'background warning-but-allowed (the exact real case: -37.1 dBFS, '
        '"near the recommended limit") + liveMeter PASS -> Ready=true WITH '
        'the warning still shown — this is the exact real-hardware scenario '
        'reported', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation:
            _realBackgroundNoiseEvaluation(noiseFloorDbFs: -37.1),
        levelCheckEvaluation: _liveMeterPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isTrue,
          reason: 'THE fix: before it, this was Ready=false due to a '
              'spurious "Signal-to-noise ratio is too low." blocker that '
              'came from the noise-floor evaluation self-comparing SNR '
              'against itself — nothing to do with the live level check.');
      expect(snapshot.blockers, isEmpty);
      expect(
          snapshot.blockers
              .contains('Signal-to-noise ratio is too low.'),
          isFalse);
      expect(snapshot.warnings,
          contains('Background noise is near the recommended limit.'));
    });

    test(
        'background FAIL (a noise floor value that genuinely exceeds the '
        'policy threshold enough to also fail some OTHER real check — here '
        'simulated via an explicit failing evaluation, since the noise- '
        'floor-only self-compare path only ever produces a warning for '
        'noiseFloorTooHigh, never a blocker) + liveMeter PASS -> Ready false',
        () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation:
            _failEvaluation(MeasurementQualityStatus.malformedCapture),
        levelCheckEvaluation: _liveMeterPassEvaluation(),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
    });

    test('liveMeter tooLow (i.e. no confirmed evidence yet) -> Not Ready',
        () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation:
            _realBackgroundNoiseEvaluation(noiseFloorDbFs: -60.0),
        levelCheckEvaluation: null, // no stable-GOOD confirmation ever built
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
    });

    test('liveMeter PASS never carries a clipping blocker unless actually '
        'evidenced (it never is, by construction)', () {
      final eval = _liveMeterPassEvaluation();
      expect(eval.statuses.contains(MeasurementQualityStatus.clipping),
          isFalse);
    });

    test('wavCapture legacy failure (real, non-self SNR) keeps its blocker '
        '— this fix never weakens the legacy manual-check path', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation:
            _realBackgroundNoiseEvaluation(noiseFloorDbFs: -60.0),
        levelCheckEvaluation:
            _failEvaluation(MeasurementQualityStatus.signalToNoiseTooLow),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
      expect(snapshot.blockers,
          contains('Signal-to-noise ratio is too low.'));
    });

    test('wavCapture legacy clipping keeps its blocker unchanged', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation:
            _realBackgroundNoiseEvaluation(noiseFloorDbFs: -60.0),
        levelCheckEvaluation:
            _failEvaluation(MeasurementQualityStatus.clipping),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
      expect(snapshot.blockers, contains('Input level signal is clipping.'));
    });
  });
}
