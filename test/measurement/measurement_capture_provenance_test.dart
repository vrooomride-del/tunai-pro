// Phase 3-D3A-2 — MeasurementCaptureProvenance model + builder contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_policy.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/pro_project.dart';

const _points = [
  CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
  CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
];

CalibrationCurve _curve(
        {CalibrationAngle angle = CalibrationAngle.zeroDegree}) =>
    CalibrationCurve(
      points: _points,
      angle: angle,
      validMinFrequencyHz: 20,
      validMaxFrequencyHz: 20000,
      sourceIdentity: 'test',
      checksum: CalibrationCurve.checksumFor(_points),
    );

MeasurementMicrophoneProfile _profile() => MeasurementMicrophoneProfile(
      id: 'mic-1',
      manufacturer: 'ACME',
      model: 'M1',
      connectionType: 'USB',
      calibrationSource: CalibrationSource.userImported,
      calibrationCurve: _curve(),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

ProProject _baseProject({
  MeasurementMicrophoneProfile? profile,
  MeasurementInputDeviceSelection? device,
  MeasurementSetupReadinessSnapshot? readiness,
}) =>
    ProProject(
      id: 'proj-prov-1',
      name: 'Provenance Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      selectedMicrophoneProfile: profile,
      selectedInputDevice: device,
      currentSetupReadiness: readiness,
    );

void main() {
  group('MeasurementCaptureProvenanceBuilder.build', () {
    test('captures specific-device identity as device:<id>', () {
      final project = _baseProject(
        profile: _profile(),
        device: MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'mic-usb-1',
          labelSnapshot: 'USB Mic',
          selectedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: project,
        actualSampleRate: 48000,
        actualChannelCount: 1,
      );
      expect(provenance.inputDeviceSelectionIdentity, 'device:mic-usb-1');
    });

    test('captures system-default identity as system-default', () {
      final project = _baseProject(
        profile: _profile(),
        device: MeasurementInputDeviceSelection.systemDefault(
          selectedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: project,
        actualSampleRate: 48000,
        actualChannelCount: 1,
      );
      expect(provenance.inputDeviceSelectionIdentity, 'system-default');
    });

    test('null device selection defaults to system-default identity', () {
      final project = _baseProject(profile: _profile());
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: project,
        actualSampleRate: 48000,
        actualChannelCount: 1,
      );
      expect(provenance.inputDeviceSelectionIdentity, 'system-default');
    });

    test('captures calibration angle and curve checksum', () {
      final project = _baseProject(
          profile: _profile().copyWith(
              calibrationCurve: _curve(angle: CalibrationAngle.ninetyDegree)));
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: project,
        actualSampleRate: 48000,
        actualChannelCount: 1,
      );
      expect(provenance.calibrationAngle, CalibrationAngle.ninetyDegree.name);
      expect(provenance.calibrationCurveChecksum,
          CalibrationCurve.checksumFor(_points));
    });

    test('uncalibrated profile -> null calibration curve checksum/angle', () {
      final project = _baseProject(
          profile: _profile().copyWith(
        calibrationSource: CalibrationSource.uncalibrated,
        clearCalibrationCurve: true,
      ));
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: project,
        actualSampleRate: 48000,
        actualChannelCount: 1,
      );
      expect(provenance.calibrationCurveChecksum, isNull);
      expect(provenance.calibrationAngle, isNull);
    });

    test('captures actual (not expected) sample rate and channel count', () {
      final project = _baseProject(profile: _profile());
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: project,
        actualSampleRate: 44100,
        actualChannelCount: 2,
      );
      expect(provenance.actualSampleRate, 44100);
      expect(provenance.actualChannelCount, 2);
    });

    test('captures setup readiness generationId and policy version', () {
      final readiness = MeasurementSetupReadinessSnapshot(
        identity: const MeasurementSetupReadinessIdentity(
          projectId: 'proj-prov-1',
          profileChecksum: null,
          calibrationCurveChecksum: null,
          calibrationAngle: null,
          inputDeviceIdentity: MeasurementSetupReadinessIdentity
              .kSystemDefaultInputDeviceIdentity,
          expectedSampleRate: 48000,
          expectedChannelCount: 1,
          qualityPolicyVersion: 'provisional-1',
        ),
        generationId: 'gen-xyz',
        blockers: const [],
        warnings: const [],
        checkedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 2),
        isReady: true,
      );
      final project = _baseProject(profile: _profile(), readiness: readiness);
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: project,
        actualSampleRate: 48000,
        actualChannelCount: 1,
      );
      expect(provenance.setupReadinessGenerationId, 'gen-xyz');
      expect(provenance.qualityPolicyVersion,
          MeasurementQualityPolicy.proProvisional().version);
    });

    test('no setup readiness -> null generationId', () {
      final project = _baseProject(profile: _profile());
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: project,
        actualSampleRate: 48000,
        actualChannelCount: 1,
      );
      expect(provenance.setupReadinessGenerationId, isNull);
    });
  });

  group('MeasurementCaptureProvenance — JSON round-trip', () {
    test('round-trips every field', () {
      final original = MeasurementCaptureProvenance(
        projectId: 'proj-1',
        microphoneProfileChecksum: 'chk-1',
        calibrationCurveChecksum: 'curve-1',
        calibrationAngle: 'zeroDegree',
        inputDeviceSelectionIdentity: 'device:usb-1',
        setupReadinessGenerationId: 'gen-1',
        qualityPolicyVersion: 'provisional-1',
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      final decoded = MeasurementCaptureProvenance.fromJson(original.toJson());
      expect(decoded, original);
    });

    test('round-trips with nullable fields absent', () {
      final original = MeasurementCaptureProvenance(
        projectId: 'proj-1',
        microphoneProfileChecksum: '',
        calibrationCurveChecksum: null,
        calibrationAngle: null,
        inputDeviceSelectionIdentity: 'system-default',
        setupReadinessGenerationId: null,
        qualityPolicyVersion: 'provisional-1',
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final decoded = MeasurementCaptureProvenance.fromJson(original.toJson());
      expect(decoded, original);
    });
  });

  group('MeasurementCaptureProvenance — immutable value semantics', () {
    test('two instances with identical fields are equal', () {
      MeasurementCaptureProvenance make() => MeasurementCaptureProvenance(
            projectId: 'p',
            microphoneProfileChecksum: 'c',
            calibrationCurveChecksum: 'cc',
            calibrationAngle: 'zeroDegree',
            inputDeviceSelectionIdentity: 'system-default',
            setupReadinessGenerationId: 'g',
            qualityPolicyVersion: 'v1',
            actualSampleRate: 48000,
            actualChannelCount: 1,
            capturedAt: DateTime.utc(2026, 1, 1),
          );
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });

    test('a different actualSampleRate makes instances unequal', () {
      final a = MeasurementCaptureProvenance(
        projectId: 'p',
        microphoneProfileChecksum: 'c',
        calibrationCurveChecksum: null,
        calibrationAngle: null,
        inputDeviceSelectionIdentity: 'system-default',
        setupReadinessGenerationId: null,
        qualityPolicyVersion: 'v1',
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final b = MeasurementCaptureProvenance(
        projectId: a.projectId,
        microphoneProfileChecksum: a.microphoneProfileChecksum,
        calibrationCurveChecksum: a.calibrationCurveChecksum,
        calibrationAngle: a.calibrationAngle,
        inputDeviceSelectionIdentity: a.inputDeviceSelectionIdentity,
        setupReadinessGenerationId: a.setupReadinessGenerationId,
        qualityPolicyVersion: a.qualityPolicyVersion,
        actualSampleRate: 44100,
        actualChannelCount: a.actualChannelCount,
        capturedAt: a.capturedAt,
      );
      expect(a == b, isFalse);
    });
  });
}
