// Phase 3-D2 — measurement_quality_snapshot.dart: typed model, round-trip,
// corrupt-field isolation, fromSetupReadiness helper, no-PCM-payload check.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
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
        actualSampleRate: 48000,
        actualChannelCount: 1,
        inputDeviceSnapshot: MeasurementInputDeviceSnapshot(
          deviceId: 'dev1',
          label: 'USB Mic',
          isSystemDefault: false,
          platform: 'macos',
          actualSampleRate: 48000,
          actualChannelCount: 1,
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
  group('fromSetupReadiness', () {
    test('builds a snapshot carrying the level-check\'s metrics', () {
      final readiness = _readySnapshot();
      final snapshot = MeasurementQualitySnapshot.fromSetupReadiness(
        readiness,
        qualityPolicyVersion: 'provisional-1',
        capturedAt: DateTime.utc(2026, 1, 1, 12, 10, 0),
      );
      expect(snapshot.setupGenerationId, 'gen-1');
      expect(snapshot.peakDbFs, -10);
      expect(snapshot.rmsDbFs, -20);
      expect(snapshot.noiseFloorDbFs, -55);
      expect(snapshot.signalToNoiseDb, 35);
      expect(snapshot.actualSampleRate, 48000);
      expect(snapshot.actualChannelCount, 1);
      expect(snapshot.profileChecksum, 'checksum-a');
      expect(snapshot.calibrationStatus, CalibrationStatus.calibrated);
      expect(snapshot.inputDeviceSnapshot?.deviceId, 'dev1');
      expect(snapshot.setupCheckedAt, readiness.checkedAt);
    });
  });

  group('JSON round-trip', () {
    test('a full snapshot round-trips exactly', () {
      final readiness = _readySnapshot();
      final snapshot = MeasurementQualitySnapshot.fromSetupReadiness(
        readiness,
        qualityPolicyVersion: 'provisional-1',
        capturedAt: DateTime.utc(2026, 1, 1, 12, 10, 0),
      );
      final decoded = MeasurementQualitySnapshot.fromJson(snapshot.toJson());
      expect(decoded.setupGenerationId, snapshot.setupGenerationId);
      expect(decoded.peakDbFs, snapshot.peakDbFs);
      expect(decoded.rmsDbFs, snapshot.rmsDbFs);
      expect(decoded.noiseFloorDbFs, snapshot.noiseFloorDbFs);
      expect(decoded.signalToNoiseDb, snapshot.signalToNoiseDb);
      expect(decoded.clippedSampleCount, snapshot.clippedSampleCount);
      expect(decoded.clippedSampleRatio, snapshot.clippedSampleRatio);
      expect(decoded.actualSampleRate, snapshot.actualSampleRate);
      expect(decoded.actualChannelCount, snapshot.actualChannelCount);
      expect(decoded.profileChecksum, snapshot.profileChecksum);
      expect(decoded.calibrationStatus, snapshot.calibrationStatus);
      expect(decoded.inputDeviceSnapshot?.deviceId,
          snapshot.inputDeviceSnapshot?.deviceId);
      expect(decoded.qualityPolicyVersion, snapshot.qualityPolicyVersion);
    });
  });

  group('backward compatibility / corrupt-field isolation', () {
    test('an empty JSON object decodes to safe defaults, never throws', () {
      final decoded = MeasurementQualitySnapshot.fromJson(const {});
      expect(decoded.setupGenerationId, '');
      expect(decoded.inputDeviceSnapshot, isNull);
      expect(decoded.calibrationStatus, isNull);
      expect(decoded.peakDbFs, 0.0);
      expect(decoded.rmsDbFs, 0.0);
    });

    test('a corrupt inputDeviceSnapshot does not fail the whole decode', () {
      final json = {
        'setupGenerationId': 'gen-1',
        'inputDeviceSnapshot': 'not-a-map',
        'peakDbFs': -10.0,
        'rmsDbFs': -20.0,
      };
      final decoded = MeasurementQualitySnapshot.fromJson(json);
      expect(decoded.setupGenerationId, 'gen-1');
      expect(decoded.inputDeviceSnapshot, isNull);
      expect(decoded.peakDbFs, -10.0);
    });

    test(
        'a corrupt calibrationStatus value falls back to null, not a '
        'thrown exception', () {
      final json = {
        'setupGenerationId': 'gen-1',
        'calibrationStatus': 12345, // wrong type
        'peakDbFs': -10.0,
        'rmsDbFs': -20.0,
      };
      final decoded = MeasurementQualitySnapshot.fromJson(json);
      expect(decoded.calibrationStatus, isNull);
    });
  });

  group('no PCM payload', () {
    test('toJson never contains a raw sample/PCM-shaped key', () {
      final readiness = _readySnapshot();
      final snapshot = MeasurementQualitySnapshot.fromSetupReadiness(
        readiness,
        qualityPolicyVersion: 'provisional-1',
      );
      final json = snapshot.toJson();
      const forbidden = {
        'samples',
        'pcm',
        'rawdata',
        'frequencies',
        'magnitudes',
      };
      for (final key in json.keys) {
        expect(forbidden.contains(key.toLowerCase()), isFalse,
            reason: 'MeasurementQualitySnapshot must never carry raw PCM — '
                'found forbidden key "$key"');
      }
    });
  });
}
