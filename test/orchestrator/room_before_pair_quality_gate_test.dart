// Phase 3-D3B — RoomBeforePairQualityGate pure contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/orchestrator/room_before_pair_quality_gate.dart';
import 'package:tunai_pro/core/orchestrator/room_measurement_quality_gate.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';

const _points = [
  CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
  CalibrationPoint(frequencyHz: 300, correctionDb: -0.5),
  CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
];

CalibrationCurve _validCurve({String checksum = 'curve-1'}) => CalibrationCurve(
      points: _points,
      angle: CalibrationAngle.zeroDegree,
      validMinFrequencyHz: 10,
      validMaxFrequencyHz: 22000,
      sourceIdentity: 'test',
      checksum: checksum,
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
  String setupReadinessGenerationId = 'gen-1',
  String qualityPolicyVersion = 'provisional-1',
}) =>
    MeasurementCaptureProvenance(
      projectId: projectId,
      microphoneProfileChecksum: microphoneProfileChecksum,
      calibrationCurveChecksum: calibrationCurveChecksum,
      calibrationAngle: calibrationAngle,
      inputDeviceSelectionIdentity: inputDeviceSelectionIdentity,
      setupReadinessGenerationId: setupReadinessGenerationId,
      qualityPolicyVersion: qualityPolicyVersion,
      actualSampleRate: 48000,
      actualChannelCount: 1,
      capturedAt: DateTime.utc(2026, 1, 1),
    );

MeasurementSetupReadinessSnapshot _readiness({String generationId = 'gen-1'}) =>
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
      generationId: generationId,
      blockers: const [],
      warnings: const [],
      checkedAt: DateTime.utc(2026, 1, 1),
      expiresAt: DateTime.utc(2026, 1, 2),
      isReady: true,
    );

RoomSystemMeasurement _measurement({
  required RoomSystemSide side,
  MeasurementCaptureProvenance? provenance,
  String generationId = 'gen-1',
  CalibrationCurve? curve,
  bool includeQualitySnapshot = true,
}) {
  final p = provenance ?? _provenance(setupReadinessGenerationId: generationId);
  return RoomSystemMeasurement(
    side: side,
    phase: RoomMeasurementPhase.before,
    frd: ParsedMeasurementData(
      id: 'm-${side.name}',
      sourceFileName: 'm.frd',
      fileType: AcousticFileType.frd,
      importedAt: DateTime.utc(2026, 1, 1),
      points: const [MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -1.0)],
      calibrationStatus: CalibrationStatus.calibrated,
      microphoneSnapshot: _micSnapshot(curve: curve),
      qualitySnapshot: includeQualitySnapshot
          ? MeasurementQualitySnapshotBuilder.build(
              provenance: p,
              readiness: _readiness(generationId: generationId),
            )
          : null,
    ),
    capturedAt: DateTime.utc(2026, 1, 1),
    sampleRate: 48000,
    source: RoomMeasurementSource.live,
    projectId: p.projectId,
  );
}

void main() {
  group('valid Left+Right', () {
    test('identical identity, same generation -> canGenerate true', () {
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(side: RoomSystemSide.left),
        right: _measurement(side: RoomSystemSide.right),
      );
      expect(result.canGenerate, isTrue);
      expect(result.blockers, isEmpty);
    });

    test(
        'different generation but same identity -> canGenerate true '
        '(generationId is NOT required to match)', () {
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(side: RoomSystemSide.left, generationId: 'gen-1'),
        right: _measurement(side: RoomSystemSide.right, generationId: 'gen-2'),
      );
      expect(result.canGenerate, isTrue);
    });
  });

  group('individual failures propagate', () {
    test('left missing quality -> leftQualityFailed', () {
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(
            side: RoomSystemSide.left, includeQualitySnapshot: false),
        right: _measurement(side: RoomSystemSide.right),
      );
      expect(result.canGenerate, isFalse);
      expect(
          result.hasBlocker(RoomBeforePairQualityBlockerCode.leftQualityFailed),
          isTrue);
    });

    test('right missing quality -> rightQualityFailed', () {
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(side: RoomSystemSide.left),
        right: _measurement(
            side: RoomSystemSide.right, includeQualitySnapshot: false),
      );
      expect(result.canGenerate, isFalse);
      expect(
          result
              .hasBlocker(RoomBeforePairQualityBlockerCode.rightQualityFailed),
          isTrue);
    });
  });

  group('pair identity mismatches', () {
    test(
        'a project mismatch is caught at the INDIVIDUAL gate, before the '
        'pair-level differentProject check is even reached — both sides '
        'must already match the pair\'s own expectedProjectId to be '
        'individually valid, so a genuine left-vs-right project mismatch '
        'is structurally unreachable at the pair-comparison stage', () {
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(
            side: RoomSystemSide.left,
            provenance: _provenance(projectId: 'proj-2')),
        right: _measurement(side: RoomSystemSide.right),
      );
      expect(result.canGenerate, isFalse);
      expect(result.leftResult.isValid, isFalse);
      expect(
          result.leftResult
              .hasBlocker(RoomMeasurementQualityBlockerCode.projectMismatch),
          isTrue);
      // The pair-level differentProject code is never added here — the
      // individual leftQualityFailed blocker already covers it.
      expect(
          result.hasBlocker(RoomBeforePairQualityBlockerCode.differentProject),
          isFalse);
    });

    test('different microphone profile -> differentMicrophoneProfile', () {
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(
            side: RoomSystemSide.left,
            provenance: _provenance(microphoneProfileChecksum: 'chk-A')),
        right: _measurement(
            side: RoomSystemSide.right,
            provenance: _provenance(microphoneProfileChecksum: 'chk-B')),
      );
      expect(result.canGenerate, isFalse);
      expect(
          result.hasBlocker(
              RoomBeforePairQualityBlockerCode.differentMicrophoneProfile),
          isTrue);
    });

    test('different calibration curve -> differentCalibrationCurve', () {
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(
            side: RoomSystemSide.left,
            provenance: _provenance(calibrationCurveChecksum: 'curve-A')),
        right: _measurement(
            side: RoomSystemSide.right,
            provenance: _provenance(calibrationCurveChecksum: 'curve-B')),
      );
      expect(result.canGenerate, isFalse);
      expect(
          result.hasBlocker(
              RoomBeforePairQualityBlockerCode.differentCalibrationCurve),
          isTrue);
    });

    test('different orientation -> differentCalibrationOrientation', () {
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(
            side: RoomSystemSide.left,
            provenance: _provenance(calibrationAngle: 'zeroDegree')),
        right: _measurement(
            side: RoomSystemSide.right,
            provenance: _provenance(calibrationAngle: 'ninetyDegree')),
      );
      expect(result.canGenerate, isFalse);
      expect(
          result.hasBlocker(
              RoomBeforePairQualityBlockerCode.differentCalibrationOrientation),
          isTrue);
    });

    test('different input device -> differentInputDevice', () {
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(
            side: RoomSystemSide.left,
            provenance:
                _provenance(inputDeviceSelectionIdentity: 'device:usb-1')),
        right: _measurement(
            side: RoomSystemSide.right,
            provenance:
                _provenance(inputDeviceSelectionIdentity: 'device:usb-2')),
      );
      expect(result.canGenerate, isFalse);
      expect(
          result.hasBlocker(
              RoomBeforePairQualityBlockerCode.differentInputDevice),
          isTrue);
    });

    test('different policy version -> differentPolicyVersion', () {
      // Same structural point as the differentProject case above: the
      // individual gate already requires an exact match to the CURRENT
      // policy version to be valid, so a right side on a different version
      // fails there (unsupportedPolicyVersion) before the pair-level
      // differentPolicyVersion comparison is reached.
      final result = RoomBeforePairQualityGate.evaluate(
        projectId: 'proj-1',
        left: _measurement(
            side: RoomSystemSide.left,
            provenance: _provenance(qualityPolicyVersion: 'provisional-1')),
        right: _measurement(
            side: RoomSystemSide.right,
            provenance: _provenance(qualityPolicyVersion: 'provisional-2')),
      );
      expect(result.canGenerate, isFalse);
      expect(result.rightResult.isValid, isFalse);
      expect(
          result.rightResult.hasBlocker(
              RoomMeasurementQualityBlockerCode.unsupportedPolicyVersion),
          isTrue);
    });
  });
}
