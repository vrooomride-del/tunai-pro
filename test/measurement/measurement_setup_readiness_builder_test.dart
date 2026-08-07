// Phase 3-D2 — measurement_setup_readiness_builder.dart: blocker/warning
// composition tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/microphone_profile_edit_rules.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_model.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness_builder.dart';

MeasurementSetupReadinessIdentity _identity() =>
    const MeasurementSetupReadinessIdentity(
      projectId: 'p1',
      profileChecksum: 'c1',
      calibrationCurveChecksum: 'curve1',
      calibrationAngle: 'zeroDegree',
      inputDeviceIdentity: 'device:dev1',
      expectedSampleRate: 48000,
      expectedChannelCount: 1,
      qualityPolicyVersion: 'provisional-1',
    );

MeasurementQualityEvaluation _evaluation(
        Set<MeasurementQualityStatus> statuses) =>
    MeasurementQualityEvaluation(
      statuses: statuses,
      metrics: MeasurementQualityMetrics(
        peakDbFs: -10,
        rmsDbFs: -20,
        clippedSampleCount: 0,
        clippedSampleRatio: 0,
        duration: const Duration(seconds: 3),
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
      ),
    );

void main() {
  final ready = _evaluation({MeasurementQualityStatus.ready});

  group('fully ready path', () {
    test(
        'calibrated mic + selected available device + permission + both '
        'evaluations ready -> isReady', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isTrue);
      expect(snapshot.blockers, isEmpty);
    });
  });

  group('microphone state', () {
    test('notSelected -> blocked with the exact message', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.notSelected,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
      expect(snapshot.blockers, contains('Select a measurement microphone.'));
    });

    test('invalid calibration -> blocked', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.invalid,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
      expect(snapshot.blockers, contains('Calibration profile is invalid.'));
    });

    test('explicitly uncalibrated WITHOUT acknowledgement blocks', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.explicitlyUncalibrated,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        explicitWarningAcknowledgement: false,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
    });

    test(
        'explicitly uncalibrated WITH acknowledgement warns but does not '
        'block, and never claims "Calibrated"', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.explicitlyUncalibrated,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        explicitWarningAcknowledgement: true,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isTrue);
      expect(snapshot.warnings.any((w) => w.contains('without calibration')),
          isTrue);
      expect(
          snapshot.warnings.any((w) => w.toLowerCase().contains('calibrated')),
          isFalse);
    });
  });

  group('permission and device', () {
    test('permission denied blocks regardless of everything else', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: false,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.blockers, contains('Allow microphone access.'));
    });

    test('no device selected blocks', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: false,
        inputDeviceAvailable: false,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.blockers, contains('Select an input device.'));
    });

    test('device selected but unavailable blocks with a distinct message', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: false,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      expect(
          snapshot.blockers, contains('Selected input device is unavailable.'));
    });
  });

  group('quality evaluation problems propagate as blockers/warnings', () {
    test('clipping in the level check blocks', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: _evaluation({MeasurementQualityStatus.clipping}),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
      expect(snapshot.blockers.any((b) => b.contains('clipping')), isTrue);
    });

    test('low input level blocks', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation:
            _evaluation({MeasurementQualityStatus.inputLevelTooLow}),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.blockers.any((b) => b.contains('too low')), isTrue);
    });

    test('high noise floor is a WARNING, not a blocker', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation:
            _evaluation({MeasurementQualityStatus.noiseFloorTooHigh}),
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isTrue);
      expect(snapshot.warnings, isNotEmpty);
    });

    test('sample rate mismatch blocks with the exact message', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation:
            _evaluation({MeasurementQualityStatus.sampleRateMismatch}),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.blockers, contains('Sample rate does not match.'));
    });

    test('channel mismatch blocks with the exact message', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation:
            _evaluation({MeasurementQualityStatus.channelMismatch}),
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.blockers, contains('Channel count does not match.'));
    });

    test('low SNR blocks', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation:
            _evaluation({MeasurementQualityStatus.signalToNoiseTooLow}),
        validity: const Duration(minutes: 30),
      );
      expect(
          snapshot.blockers.any((b) => b.contains('Signal-to-noise')), isTrue);
    });
  });

  group('missing checks block', () {
    test('no noise-floor evaluation yet -> blocked, distinct message', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: null,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
      expect(
          snapshot.blockers.any(
              (b) => b.contains('Background-noise check has not been run')),
          isTrue);
    });

    test('no level-check evaluation yet -> blocked, distinct message', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: null,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.isReady, isFalse);
      expect(
          snapshot.blockers
              .any((b) => b.contains('Input-level check has not been run')),
          isTrue);
    });
  });

  group('multiple simultaneous blockers', () {
    test('several problems all appear, not just the first one found', () {
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.notSelected,
        inputDeviceSelected: false,
        inputDeviceAvailable: false,
        permissionGranted: false,
        noiseFloorEvaluation: null,
        levelCheckEvaluation: null,
        validity: const Duration(minutes: 30),
      );
      expect(snapshot.blockers.length, greaterThan(2));
      expect(snapshot.isReady, isFalse);
    });
  });

  group('expiresAt derivation', () {
    test('expiresAt = checkedAt + validity', () {
      final now = DateTime.utc(2026, 1, 1, 10, 0, 0);
      final snapshot = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
        now: now,
      );
      expect(snapshot.checkedAt, now);
      expect(snapshot.expiresAt, now.add(const Duration(minutes: 30)));
    });

    test('every successful build produces a unique generationId', () {
      final a = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      final b = MeasurementSetupReadinessBuilder.build(
        identity: _identity(),
        microphoneState: MicrophoneDisplayState.calibrationReady,
        inputDeviceSelected: true,
        inputDeviceAvailable: true,
        permissionGranted: true,
        noiseFloorEvaluation: ready,
        levelCheckEvaluation: ready,
        validity: const Duration(minutes: 30),
      );
      expect(a.generationId, isNot(b.generationId));
    });
  });
}
