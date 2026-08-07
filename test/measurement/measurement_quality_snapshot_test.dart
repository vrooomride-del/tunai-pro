// Phase 3-D3B — measurement_quality_snapshot.dart: typed model, round-trip,
// corrupt-field isolation, builder, no-PCM-payload check, setup-vs-actual
// provenance separation.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_model.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';

MeasurementQualityEvaluation _evaluation() => MeasurementQualityEvaluation(
      statuses: const {MeasurementQualityStatus.ready},
      metrics: MeasurementQualityMetrics(
        peakDbFs: -10,
        rmsDbFs: -20,
        clippedSampleCount: 0,
        clippedSampleRatio: 0,
        noiseFloorDbFs: -55,
        signalToNoiseDb: 35,
        duration: const Duration(seconds: 3),
        actualSampleRate: 44100, // deliberately DIFFERENT from the capture's
        actualChannelCount: 2, // actual format, to prove no mixing occurs
        inputDeviceSnapshot: MeasurementInputDeviceSnapshot(
          deviceId: 'dev1',
          label: 'USB Mic',
          isSystemDefault: false,
          platform: 'macos',
          actualSampleRate: 44100,
          actualChannelCount: 2,
          capturedAt: DateTime.utc(2026, 1, 1),
        ),
        calibrationStatus: CalibrationStatus.calibrated,
        capturedAt: DateTime.utc(2026, 1, 1),
      ),
    );

MeasurementSetupReadinessSnapshot _readySnapshot() {
  final at = DateTime.utc(2026, 1, 1, 12, 0, 0);
  return MeasurementSetupReadinessSnapshot(
    identity: const MeasurementSetupReadinessIdentity(
      projectId: 'p1',
      profileChecksum: 'checksum-a',
      calibrationCurveChecksum: 'curve-a',
      calibrationAngle: 'zeroDegree',
      inputDeviceIdentity: 'device:dev1',
      expectedSampleRate: 48000,
      expectedChannelCount: 1,
      qualityPolicyVersion: 'provisional-1',
    ),
    generationId: 'gen-1',
    noiseFloorEvaluation: _evaluation(),
    levelCheckEvaluation: _evaluation(),
    deviceSnapshot: _evaluation().metrics.inputDeviceSnapshot,
    blockers: const [],
    warnings: const [],
    checkedAt: at,
    expiresAt: at.add(const Duration(minutes: 30)),
    isReady: true,
  );
}

void main() {
  group('MeasurementQualitySnapshotBuilder.build', () {
    test('setup* fields come from the setup check, never the capture', () {
      final provenance = MeasurementCaptureProvenance(
        projectId: 'p1',
        microphoneProfileChecksum: 'checksum-a',
        calibrationCurveChecksum: 'curve-a',
        calibrationAngle: 'zeroDegree',
        inputDeviceSelectionIdentity: 'device:dev1',
        setupReadinessGenerationId: 'gen-1',
        qualityPolicyVersion: 'provisional-1',
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 2),
      );
      final snapshot = MeasurementQualitySnapshotBuilder.build(
        provenance: provenance,
        readiness: _readySnapshot(),
      );

      // The capture's own actual format lives ONLY on provenance.
      expect(snapshot.provenance.actualSampleRate, 48000);
      expect(snapshot.provenance.actualChannelCount, 1);
      // The setup check's own (different) numbers stay separate, never
      // overwriting or being confused with the capture's actual format.
      expect(snapshot.setupPeakDbFs, -10);
      expect(snapshot.setupRmsDbFs, -20);
      expect(snapshot.setupNoiseFloorDbFs, -55);
      expect(snapshot.setupSignalToNoiseDb, 35);
      expect(snapshot.setupCalibrationStatus, CalibrationStatus.calibrated);
      expect(snapshot.setupInputDeviceSnapshot?.actualSampleRate, 44100);
      expect(snapshot.setupCheckedAt, DateTime.utc(2026, 1, 1, 12, 0, 0));
    });

    test(
        'no level-check metrics -> setup metrics fall back to defaults, '
        'never to provenance values', () {
      final readiness = MeasurementSetupReadinessSnapshot(
        identity: _readySnapshot().identity,
        generationId: 'gen-2',
        blockers: const [],
        warnings: const [],
        checkedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 2),
        isReady: true,
      );
      final snapshot = MeasurementQualitySnapshotBuilder.build(
        provenance: MeasurementCaptureProvenance(
          projectId: 'p1',
          microphoneProfileChecksum: 'chk',
          calibrationCurveChecksum: null,
          calibrationAngle: null,
          inputDeviceSelectionIdentity: 'system-default',
          setupReadinessGenerationId: 'gen-2',
          qualityPolicyVersion: 'provisional-1',
          actualSampleRate: 48000,
          actualChannelCount: 1,
          capturedAt: DateTime.utc(2026, 1, 1),
        ),
        readiness: readiness,
      );
      expect(snapshot.setupPeakDbFs, 0.0);
      expect(snapshot.setupRmsDbFs, 0.0);
      expect(snapshot.setupClippedSampleCount, 0);
      expect(snapshot.setupInputDeviceSnapshot, isNull);
    });
  });

  group('JSON round-trip', () {
    test('round-trips every field including nested provenance', () {
      final provenance = MeasurementCaptureProvenance(
        projectId: 'p1',
        microphoneProfileChecksum: 'checksum-a',
        calibrationCurveChecksum: 'curve-a',
        calibrationAngle: 'zeroDegree',
        inputDeviceSelectionIdentity: 'device:dev1',
        setupReadinessGenerationId: 'gen-1',
        qualityPolicyVersion: 'provisional-1',
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 2),
      );
      final original = MeasurementQualitySnapshotBuilder.build(
        provenance: provenance,
        readiness: _readySnapshot(),
      );
      final decoded = MeasurementQualitySnapshot.fromJson(original.toJson());
      expect(decoded, isNotNull);
      expect(decoded!.provenance, original.provenance);
      expect(decoded.setupPeakDbFs, original.setupPeakDbFs);
      expect(decoded.setupRmsDbFs, original.setupRmsDbFs);
      expect(decoded.setupNoiseFloorDbFs, original.setupNoiseFloorDbFs);
      expect(decoded.setupSignalToNoiseDb, original.setupSignalToNoiseDb);
      expect(decoded.setupClippedSampleCount, original.setupClippedSampleCount);
      expect(decoded.setupClippedSampleRatio, original.setupClippedSampleRatio);
      expect(decoded.setupCalibrationStatus, original.setupCalibrationStatus);
      expect(decoded.setupInputDeviceSnapshot?.deviceId,
          original.setupInputDeviceSnapshot?.deviceId);
      expect(decoded.setupCheckedAt, original.setupCheckedAt);
    });

    test('no PCM/WAV payload anywhere in the JSON shape', () {
      final snapshot = MeasurementQualitySnapshotBuilder.build(
        provenance: MeasurementCaptureProvenance(
          projectId: 'p1',
          microphoneProfileChecksum: 'chk',
          calibrationCurveChecksum: null,
          calibrationAngle: null,
          inputDeviceSelectionIdentity: 'system-default',
          setupReadinessGenerationId: 'gen-1',
          qualityPolicyVersion: 'provisional-1',
          actualSampleRate: 48000,
          actualChannelCount: 1,
          capturedAt: DateTime.utc(2026, 1, 1),
        ),
        readiness: _readySnapshot(),
      );
      final json = snapshot.toJson();
      const forbiddenKeys = ['pcm', 'wav', 'samples', 'bytes', 'audio'];
      void checkNoPayload(dynamic value) {
        if (value is Map) {
          for (final key in value.keys) {
            for (final forbidden in forbiddenKeys) {
              expect(key.toString().toLowerCase().contains(forbidden), isFalse,
                  reason: 'unexpected payload-shaped key: $key');
            }
            checkNoPayload(value[key]);
          }
        }
      }

      checkNoPayload(json);
    });
  });

  group('corrupt-field isolation', () {
    test('missing provenance -> fromJson returns null (no synthetic identity)',
        () {
      final decoded = MeasurementQualitySnapshot.fromJson({
        'setupPeakDbFs': -10.0,
        'setupRmsDbFs': -20.0,
      });
      expect(decoded, isNull);
    });

    test('corrupt setupInputDeviceSnapshot falls back to null, rest survives',
        () {
      final provenanceJson = MeasurementCaptureProvenance(
        projectId: 'p1',
        microphoneProfileChecksum: 'chk',
        calibrationCurveChecksum: null,
        calibrationAngle: null,
        inputDeviceSelectionIdentity: 'system-default',
        setupReadinessGenerationId: 'gen-1',
        qualityPolicyVersion: 'provisional-1',
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
      ).toJson();
      final decoded = MeasurementQualitySnapshot.fromJson({
        'provenance': provenanceJson,
        'setupPeakDbFs': -10.0,
        'setupRmsDbFs': -20.0,
        'setupInputDeviceSnapshot': 'not-a-map',
      });
      expect(decoded, isNotNull);
      expect(decoded!.setupInputDeviceSnapshot, isNull);
      expect(decoded.setupPeakDbFs, -10.0);
      expect(decoded.provenance.projectId, 'p1');
    });

    test('corrupt setupCalibrationStatus falls back to null', () {
      final provenanceJson = MeasurementCaptureProvenance(
        projectId: 'p1',
        microphoneProfileChecksum: 'chk',
        calibrationCurveChecksum: null,
        calibrationAngle: null,
        inputDeviceSelectionIdentity: 'system-default',
        setupReadinessGenerationId: 'gen-1',
        qualityPolicyVersion: 'provisional-1',
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
      ).toJson();
      final decoded = MeasurementQualitySnapshot.fromJson({
        'provenance': provenanceJson,
        'setupPeakDbFs': -10.0,
        'setupRmsDbFs': -20.0,
        'setupCalibrationStatus': 12345,
      });
      expect(decoded, isNotNull);
      expect(decoded!.setupCalibrationStatus, isNull);
    });
  });
}
