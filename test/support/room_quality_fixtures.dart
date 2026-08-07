// Shared fixtures for tests downstream of the Phase 3-D3B Room Before
// Left/Right quality/calibration pair gate. Room Auto PEQ's generate() now
// requires trustworthy qualitySnapshot provenance on BOTH sides, not just
// 2/2 completeness — tests whose subject is generate()/approve()/rollback
// mechanics (not the quality gate itself) seed a known-good chain from here
// rather than each re-deriving one.

import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';

const kRoomQualityFixtureCurvePoints = [
  CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
  CalibrationPoint(frequencyHz: 300, correctionDb: -0.3),
  CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
];

CalibrationCurve roomQualityFixtureCurve() => CalibrationCurve(
      points: kRoomQualityFixtureCurvePoints,
      angle: CalibrationAngle.zeroDegree,
      validMinFrequencyHz: 10,
      validMaxFrequencyHz: 22000,
      sourceIdentity: 'room-quality-fixture-curve',
      checksum: CalibrationCurve.checksumFor(kRoomQualityFixtureCurvePoints),
    );

MeasurementMicrophoneSnapshot roomQualityFixtureMicSnapshot() =>
    MeasurementMicrophoneSnapshot(
      profileId: 'room-quality-fixture-mic',
      profileChecksum: 'room-quality-fixture-checksum',
      manufacturer: 'TUNAI',
      model: 'Fixture Mic',
      calibrationSource: CalibrationSource.userImported,
      calibrationCurve: roomQualityFixtureCurve(),
      sampleRate: 48000,
      capturedAt: DateTime.utc(2026, 1, 1),
    );

MeasurementCaptureProvenance roomQualityFixtureProvenance({
  required String projectId,
  String generationId = 'room-quality-fixture-gen',
}) =>
    MeasurementCaptureProvenance(
      projectId: projectId,
      microphoneProfileChecksum: 'room-quality-fixture-checksum',
      calibrationCurveChecksum: roomQualityFixtureCurve().checksum,
      calibrationAngle: CalibrationAngle.zeroDegree.name,
      inputDeviceSelectionIdentity: 'device:room-quality-fixture-device',
      setupReadinessGenerationId: generationId,
      qualityPolicyVersion: 'provisional-1',
      actualSampleRate: 48000,
      actualChannelCount: 1,
      capturedAt: DateTime.utc(2026, 1, 1),
    );

MeasurementSetupReadinessSnapshot roomQualityFixtureReadiness({
  required String projectId,
  String generationId = 'room-quality-fixture-gen',
}) =>
    MeasurementSetupReadinessSnapshot(
      identity: MeasurementSetupReadinessIdentity(
        projectId: projectId,
        profileChecksum: 'room-quality-fixture-checksum',
        calibrationCurveChecksum: roomQualityFixtureCurve().checksum,
        calibrationAngle: CalibrationAngle.zeroDegree.name,
        inputDeviceIdentity: 'device:room-quality-fixture-device',
        expectedSampleRate: 48000,
        expectedChannelCount: 1,
        qualityPolicyVersion: 'provisional-1',
      ),
      generationId: generationId,
      blockers: const [],
      warnings: const [],
      checkedAt: DateTime.utc(2026, 1, 1),
      expiresAt: DateTime.utc(2026, 1, 2),
      isReady: true,
    );

/// A quality snapshot that passes [RoomMeasurementQualityGate.evaluate] for
/// `projectId` outright — the one-call "make this measurement quality-ready"
/// builder, mirroring capture_gate_fixtures.dart's withGateReadySetup.
MeasurementQualitySnapshot roomQualityFixtureSnapshot({
  required String projectId,
  String generationId = 'room-quality-fixture-gen',
}) =>
    MeasurementQualitySnapshotBuilder.build(
      provenance:
          roomQualityFixtureProvenance(projectId: projectId, generationId: generationId),
      readiness:
          roomQualityFixtureReadiness(projectId: projectId, generationId: generationId),
    );
