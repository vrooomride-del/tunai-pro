// Phase 3-D3B — RoomMeasurementQualityGate (individual) pure contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/orchestrator/room_measurement_quality_gate.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';

const _points = [
  CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
  CalibrationPoint(frequencyHz: 300, correctionDb: -0.5),
  CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
];

CalibrationCurve _validCurve() => CalibrationCurve(
      points: _points,
      angle: CalibrationAngle.zeroDegree,
      validMinFrequencyHz: 10,
      validMaxFrequencyHz: 22000,
      sourceIdentity: 'test',
      checksum: CalibrationCurve.checksumFor(_points),
    );

MeasurementMicrophoneSnapshot _micSnapshot({CalibrationCurve? curve}) =>
    MeasurementMicrophoneSnapshot(
      profileId: 'mic-1',
      profileChecksum: 'chk-1',
      manufacturer: 'ACME',
      model: 'M1',
      calibrationSource: CalibrationSource.userImported,
      calibrationCurve: curve ?? _validCurve(),
      sampleRate: 48000,
      capturedAt: DateTime.utc(2026, 1, 1),
    );

MeasurementCaptureProvenance _provenance({
  String projectId = 'proj-1',
  String microphoneProfileChecksum = 'chk-1',
  String? calibrationCurveChecksum = 'curve-1',
  String? calibrationAngle = 'zeroDegree',
  String inputDeviceSelectionIdentity = 'device:usb-1',
  int actualSampleRate = 48000,
  int actualChannelCount = 1,
  String qualityPolicyVersion = 'provisional-1',
}) =>
    MeasurementCaptureProvenance(
      projectId: projectId,
      microphoneProfileChecksum: microphoneProfileChecksum,
      calibrationCurveChecksum: calibrationCurveChecksum,
      calibrationAngle: calibrationAngle,
      inputDeviceSelectionIdentity: inputDeviceSelectionIdentity,
      setupReadinessGenerationId: 'gen-1',
      qualityPolicyVersion: qualityPolicyVersion,
      actualSampleRate: actualSampleRate,
      actualChannelCount: actualChannelCount,
      capturedAt: DateTime.utc(2026, 1, 1),
    );

MeasurementSetupReadinessSnapshot _readiness() =>
    MeasurementSetupReadinessSnapshot(
      identity: const MeasurementSetupReadinessIdentity(
        projectId: 'proj-1',
        profileChecksum: 'chk-1',
        calibrationCurveChecksum: 'curve-1',
        calibrationAngle: 'zeroDegree',
        inputDeviceIdentity: 'device:usb-1',
        expectedSampleRate: 48000,
        expectedChannelCount: 1,
        qualityPolicyVersion: 'provisional-1',
      ),
      generationId: 'gen-1',
      blockers: const [],
      warnings: const [],
      checkedAt: DateTime.utc(2026, 1, 1),
      expiresAt: DateTime.utc(2026, 1, 2),
      isReady: true,
    );

MeasurementQualitySnapshot _qualitySnapshot(
        {MeasurementCaptureProvenance? provenance}) =>
    MeasurementQualitySnapshotBuilder.build(
      provenance: provenance ?? _provenance(),
      readiness: _readiness(),
    );

RoomSystemMeasurement _measurement({
  RoomSystemSide side = RoomSystemSide.left,
  MeasurementQualitySnapshot? qualitySnapshot,
  bool includeQualitySnapshot = true,
  CalibrationStatus calibrationStatus = CalibrationStatus.calibrated,
  MeasurementMicrophoneSnapshot? micSnapshot,
  String projectId = 'proj-1',
}) =>
    RoomSystemMeasurement(
      side: side,
      phase: RoomMeasurementPhase.before,
      frd: ParsedMeasurementData(
        id: 'm1',
        sourceFileName: 'm1.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2026, 1, 1),
        points: const [
          MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -1.0),
        ],
        calibrationStatus: calibrationStatus,
        microphoneSnapshot: micSnapshot ?? _micSnapshot(),
        qualitySnapshot: includeQualitySnapshot
            ? (qualitySnapshot ?? _qualitySnapshot())
            : null,
      ),
      capturedAt: DateTime.utc(2026, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: projectId,
    );

void main() {
  group('valid measurement -> PASS', () {
    test('all conditions met -> isValid true, no blockers', () {
      final result = RoomMeasurementQualityGate.evaluate(
        measurement: _measurement(),
        expectedProjectId: 'proj-1',
      );
      expect(result.isValid, isTrue);
      expect(result.blockers, isEmpty);
    });
  });

  group('missing measurement / snapshot', () {
    test('null measurement -> missingMeasurement', () {
      final result = RoomMeasurementQualityGate.evaluate(
        measurement: null,
        expectedProjectId: 'proj-1',
      );
      expect(result.isValid, isFalse);
      expect(result.primaryBlocker!.code,
          RoomMeasurementQualityBlockerCode.missingMeasurement);
    });

    test('measurement with no qualitySnapshot -> missingQualitySnapshot', () {
      final result = RoomMeasurementQualityGate.evaluate(
        measurement: _measurement(includeQualitySnapshot: false),
        expectedProjectId: 'proj-1',
      );
      expect(result.isValid, isFalse);
      expect(result.primaryBlocker!.code,
          RoomMeasurementQualityBlockerCode.missingQualitySnapshot);
    });
  });

  group('identity checks', () {
    test('project mismatch (expected differs) -> projectMismatch', () {
      final result = RoomMeasurementQualityGate.evaluate(
        measurement: _measurement(
            qualitySnapshot:
                _qualitySnapshot(provenance: _provenance(projectId: 'proj-1'))),
        expectedProjectId: 'proj-2',
      );
      expect(result.isValid, isFalse);
      expect(
          result.hasBlocker(RoomMeasurementQualityBlockerCode.projectMismatch),
          isTrue);
    });
  });

  group('actual format checks', () {
    test('wrong sample rate -> actualSampleRateMismatch', () {
      final result = RoomMeasurementQualityGate.evaluate(
        measurement: _measurement(
            qualitySnapshot: _qualitySnapshot(
                provenance: _provenance(actualSampleRate: 44100))),
        expectedProjectId: 'proj-1',
      );
      expect(result.isValid, isFalse);
      expect(
          result.hasBlocker(
              RoomMeasurementQualityBlockerCode.actualSampleRateMismatch),
          isTrue);
    });

    test('wrong channel count -> actualChannelCountMismatch', () {
      final result = RoomMeasurementQualityGate.evaluate(
        measurement: _measurement(
            qualitySnapshot: _qualitySnapshot(
                provenance: _provenance(actualChannelCount: 2))),
        expectedProjectId: 'proj-1',
      );
      expect(result.isValid, isFalse);
      expect(
          result.hasBlocker(
              RoomMeasurementQualityBlockerCode.actualChannelCountMismatch),
          isTrue);
    });
  });

  group('calibration checks', () {
    test('calibration coverage insufficient -> blocked', () {
      final narrowCurve = CalibrationCurve(
        points: _points,
        angle: CalibrationAngle.zeroDegree,
        validMinFrequencyHz: 100,
        validMaxFrequencyHz: 20000,
        sourceIdentity: 'test',
        checksum: CalibrationCurve.checksumFor(_points),
      );
      final result = RoomMeasurementQualityGate.evaluate(
        measurement:
            _measurement(micSnapshot: _micSnapshot(curve: narrowCurve)),
        expectedProjectId: 'proj-1',
      );
      expect(result.isValid, isFalse);
      expect(
          result.hasBlocker(RoomMeasurementQualityBlockerCode
              .calibrationCoverageInsufficient),
          isTrue);
    });

    test('legacy calibration status -> blocked', () {
      final result = RoomMeasurementQualityGate.evaluate(
        measurement:
            _measurement(calibrationStatus: CalibrationStatus.legacyUnknown),
        expectedProjectId: 'proj-1',
      );
      expect(result.isValid, isFalse);
      expect(
          result.hasBlocker(RoomMeasurementQualityBlockerCode
              .calibrationCoverageInsufficient),
          isTrue);
    });

    test('explicitly uncalibrated -> blocked', () {
      final result = RoomMeasurementQualityGate.evaluate(
        measurement: _measurement(
            calibrationStatus: CalibrationStatus.explicitlyUncalibrated),
        expectedProjectId: 'proj-1',
      );
      expect(result.isValid, isFalse);
      expect(
          result.hasBlocker(RoomMeasurementQualityBlockerCode
              .calibrationCoverageInsufficient),
          isTrue);
    });
  });

  group('clipping', () {
    test('clipped samples in setup metrics -> clipping blocker', () {
      final readinessWithClip = MeasurementSetupReadinessSnapshot(
        identity: _readiness().identity,
        generationId: 'gen-1',
        blockers: const [],
        warnings: const [],
        checkedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 2),
        isReady: true,
      );
      final snap = MeasurementQualitySnapshot(
        provenance: _provenance(),
        setupPeakDbFs: -1.0,
        setupRmsDbFs: -5.0,
        setupClippedSampleCount: 5,
        setupClippedSampleRatio: 0.01,
        setupCheckedAt: readinessWithClip.checkedAt,
      );
      final result = RoomMeasurementQualityGate.evaluate(
        measurement: _measurement(qualitySnapshot: snap),
        expectedProjectId: 'proj-1',
      );
      expect(result.isValid, isFalse);
      expect(result.hasBlocker(RoomMeasurementQualityBlockerCode.clipping),
          isTrue);
    });
  });
}
