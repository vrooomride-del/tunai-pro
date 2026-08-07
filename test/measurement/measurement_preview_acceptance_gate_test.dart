// Phase 3-D3A-2 — MeasurementPreviewAcceptanceGate pure contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_preview_acceptance_gate.dart';
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

final _device = MeasurementInputDeviceSelection.specificDevice(
  deviceId: 'usb-1',
  labelSnapshot: 'USB Mic',
  selectedAt: DateTime.utc(2026, 1, 1),
);

final _readiness = MeasurementSetupReadinessSnapshot(
  identity: MeasurementSetupReadinessIdentity(
    projectId: 'proj-1',
    profileChecksum: _profile().checksum,
    calibrationCurveChecksum: _curve().checksum,
    calibrationAngle: _curve().angle.name,
    inputDeviceIdentity: 'device:usb-1',
    expectedSampleRate: 48000,
    expectedChannelCount: 1,
    qualityPolicyVersion: MeasurementQualityPolicy.proProvisional().version,
  ),
  generationId: 'gen-1',
  blockers: const [],
  warnings: const [],
  checkedAt: DateTime.utc(2026, 1, 1),
  expiresAt: DateTime.utc(2026, 1, 2),
  isReady: true,
);

ProProject _project({
  String id = 'proj-1',
  MeasurementMicrophoneProfile? profile,
  MeasurementInputDeviceSelection? device,
  MeasurementSetupReadinessSnapshot? readiness,
}) =>
    ProProject(
      id: id,
      name: 'Gate Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      selectedMicrophoneProfile: profile ?? _profile(),
      selectedInputDevice: device ?? _device,
      currentSetupReadiness: readiness ?? _readiness,
    );

MeasurementCaptureProvenance _validProvenance() =>
    MeasurementCaptureProvenanceBuilder.build(
      project: _project(),
      actualSampleRate: 48000,
      actualChannelCount: 1,
    );

void main() {
  group('exact same identity -> PASS', () {
    test('canAccept true, no blockers, not stale', () {
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(),
      );
      expect(result.canAccept, isTrue);
      expect(result.stale, isFalse);
      expect(result.blockers, isEmpty);
      expect(result.primaryBlocker, isNull);
    });
  });

  group('missing provenance', () {
    test('null provenance -> blocked with missingProvenance', () {
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: null,
        currentProject: _project(),
      );
      expect(result.canAccept, isFalse);
      expect(result.stale, isTrue);
      expect(result.primaryBlocker!.code,
          MeasurementPreviewAcceptanceBlockerCode.missingProvenance);
    });
  });

  group('identity-dimension changes each block Accept', () {
    test('project changed', () {
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(id: 'proj-2'),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.projectChanged),
          isTrue);
    });

    test('current project null -> projectChanged', () {
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: null,
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.projectChanged),
          isTrue);
    });

    test('microphone profile changed (different checksum)', () {
      final differentProfile = _profile().copyWith(model: 'M2');
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(profile: differentProfile),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.microphoneProfileChanged),
          isTrue);
    });

    test('serial number change -> microphoneProfileChanged (via checksum)', () {
      final resernaled = _profile().copyWith(serialNumber: 'SN-2');
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(profile: resernaled),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.microphoneProfileChanged),
          isTrue);
    });

    test('calibration curve changed', () {
      const newPoints = [
        CalibrationPoint(frequencyHz: 20, correctionDb: 3.0),
        CalibrationPoint(frequencyHz: 20000, correctionDb: -3.0),
      ];
      final recalibrated = _profile().copyWith(
        calibrationCurve: CalibrationCurve(
          points: newPoints,
          angle: CalibrationAngle.zeroDegree,
          validMinFrequencyHz: 20,
          validMaxFrequencyHz: 20000,
          sourceIdentity: 'test2',
          checksum: CalibrationCurve.checksumFor(newPoints),
        ),
      );
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(profile: recalibrated),
      );
      expect(result.canAccept, isFalse);
      // A different curve also changes the profile checksum, so both fire —
      // the important thing is calibrationCurveChanged is among them.
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.calibrationCurveChanged),
          isTrue);
    });

    test('orientation changed', () {
      final reoriented = _profile().copyWith(
          calibrationCurve: _curve(angle: CalibrationAngle.ninetyDegree));
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(profile: reoriented),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(MeasurementPreviewAcceptanceBlockerCode
              .calibrationOrientationChanged),
          isTrue);
    });

    test('input device id changed (profile unchanged)', () {
      final otherDevice = MeasurementInputDeviceSelection.specificDevice(
        deviceId: 'usb-2',
        labelSnapshot: 'Other Mic',
        selectedAt: DateTime.utc(2026, 1, 1),
      );
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(device: otherDevice),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.inputDeviceChanged),
          isTrue);
      // Profile-level checks must NOT fire when only the device changed.
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.microphoneProfileChanged),
          isFalse);
    });

    test('specific -> system-default is a device change', () {
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(
            device: MeasurementInputDeviceSelection.systemDefault(
                selectedAt: DateTime.utc(2026, 1, 1))),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.inputDeviceChanged),
          isTrue);
    });

    test('system-default -> specific is a device change', () {
      final systemDefaultProject = _project(
          device: MeasurementInputDeviceSelection.systemDefault(
              selectedAt: DateTime.utc(2026, 1, 1)));
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: systemDefaultProject,
        actualSampleRate: 48000,
        actualChannelCount: 1,
      );
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: provenance,
        currentProject: _project(device: _device),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.inputDeviceChanged),
          isTrue);
    });

    test('setup generation changed', () {
      final newerReadiness = MeasurementSetupReadinessSnapshot(
        identity: _readiness.identity,
        generationId: 'gen-2',
        blockers: const [],
        warnings: const [],
        checkedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 2),
        isReady: true,
      );
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(readiness: newerReadiness),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.setupGenerationChanged),
          isTrue);
    });

    test('policy version changed', () {
      const bumpedPolicy = MeasurementQualityPolicy(
        expectedSampleRate: 48000,
        expectedChannelCount: 1,
        minimumCaptureDuration: Duration(seconds: 1),
        clippingAmplitudeThreshold: 0.98,
        clippingSampleCountThreshold: 10,
        clippingRatioThreshold: 0.0001,
        minimumSignalRmsDbFs: -40.0,
        maximumSignalRmsDbFs: -6.0,
        maximumNoiseFloorDbFs: -50.0,
        minimumSignalToNoiseDb: 20.0,
        silenceCaptureDuration: Duration(seconds: 3),
        levelCheckDuration: Duration(seconds: 3),
        setupCheckValidity: Duration(minutes: 30),
        version: 'provisional-2',
      );
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: _validProvenance(),
        currentProject: _project(),
        policy: bumpedPolicy,
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.qualityPolicyChanged),
          isTrue);
    });
  });

  group('actual WAV format mismatches always block, regardless of identity',
      () {
    test('actual sample rate mismatch', () {
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: _project(),
        actualSampleRate: 44100,
        actualChannelCount: 1,
      );
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: provenance,
        currentProject: _project(),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(
              MeasurementPreviewAcceptanceBlockerCode.actualSampleRateMismatch),
          isTrue);
    });

    test('actual channel count mismatch (stereo)', () {
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: _project(),
        actualSampleRate: 48000,
        actualChannelCount: 2,
      );
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: provenance,
        currentProject: _project(),
      );
      expect(result.canAccept, isFalse);
      expect(
          result.hasBlocker(MeasurementPreviewAcceptanceBlockerCode
              .actualChannelCountMismatch),
          isTrue);
    });

    test('48000/1 actual format passes format checks', () {
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: _project(),
        actualSampleRate: 48000,
        actualChannelCount: 1,
      );
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: provenance,
        currentProject: _project(),
      );
      expect(result.canAccept, isTrue);
    });
  });

  group('primaryBlocker ordering', () {
    test('project change is reported before device/format when both apply', () {
      final provenance = MeasurementCaptureProvenanceBuilder.build(
        project: _project(),
        actualSampleRate: 44100,
        actualChannelCount: 2,
      );
      final result = MeasurementPreviewAcceptanceGate.evaluate(
        provenance: provenance,
        currentProject: _project(id: 'proj-2'),
      );
      expect(result.primaryBlocker!.code,
          MeasurementPreviewAcceptanceBlockerCode.projectChanged);
    });
  });
}
