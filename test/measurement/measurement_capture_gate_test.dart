// Phase 3-D3 §1/§12 — shared Factory/Room MeasurementCaptureGate.
//
// The gate is fail-closed: every unknown (no setup check, unrecoverable
// calibration provenance, a readiness snapshot that no longer describes the
// current chain, unknown device availability, unknown permission) blocks.
// Warnings never bypass implicitly — they need a typed acknowledgement bound
// to project + profile + device + readiness generation.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_gate.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_gate_types.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_policy.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness_project_identity.dart';
import 'package:tunai_pro/core/measurement/measurement_warning_acknowledgement.dart';
import 'package:tunai_pro/core/pro_project.dart';

final _now = DateTime.utc(2026, 8, 7, 12);
final _policy = MeasurementQualityPolicy.proProvisional();

CalibrationCurve _curve({
  String checksum = 'curve-1',
  CalibrationAngle angle = CalibrationAngle.zeroDegree,
  double minHz = 10,
  double maxHz = 20000,
}) =>
    CalibrationCurve(
      points: const [
        CalibrationPoint(frequencyHz: 20, correctionDb: 1.0),
        CalibrationPoint(frequencyHz: 1000, correctionDb: 0.0),
        CalibrationPoint(frequencyHz: 10000, correctionDb: -1.0),
      ],
      angle: angle,
      validMinFrequencyHz: minHz,
      validMaxFrequencyHz: maxHz,
      sourceIdentity: 'test.txt',
      checksum: checksum,
      interpolationPolicy: CalibrationInterpolationPolicy.logFrequencyLinearDb,
    );

MeasurementMicrophoneProfile _profile({
  CalibrationSource source = CalibrationSource.manufacturerFile,
  CalibrationCurve? curve,
  bool noCurve = false,
}) =>
    MeasurementMicrophoneProfile(
      id: 'mic-1',
      manufacturer: 'TUNAI',
      model: 'REF-1',
      connectionType: 'usb',
      calibrationSource: source,
      calibrationCurve: noCurve ? null : (curve ?? _curve()),
      createdAt: _now,
      updatedAt: _now,
    );

MeasurementInputDeviceSelection _specificDevice({String id = 'dev-1'}) =>
    MeasurementInputDeviceSelection.specificDevice(
        deviceId: id, labelSnapshot: 'USB Mic', selectedAt: _now);

/// Builds a project whose persisted readiness matches its own current
/// identity — the "everything lines up" baseline each test then perturbs.
ProProject _project({
  MeasurementMicrophoneProfile? profile,
  MeasurementInputDeviceSelection? device,
  bool withReadiness = true,
  bool readinessIsReady = true,
  List<String> readinessBlockers = const [],
  List<String> readinessWarnings = const [],
  DateTime? expiresAt,
  MeasurementSetupReadinessIdentity Function(MeasurementSetupReadinessIdentity)?
      mutateIdentity,
  String generationId = 'gen-1',
}) {
  final base = ProProject(
    id: 'proj-1',
    name: 'Gate Test',
    dspTarget: 'ADAU1701',
    createdAt: _now,
    updatedAt: _now,
    selectedMicrophoneProfile: profile,
    selectedInputDevice: device,
  );
  if (!withReadiness) return base;
  final identity = MeasurementSetupReadinessProjectIdentity.forProject(base,
      policy: _policy);
  return base.copyWith(
    currentSetupReadiness: MeasurementSetupReadinessSnapshot(
      identity: mutateIdentity == null ? identity : mutateIdentity(identity),
      generationId: generationId,
      blockers: readinessBlockers,
      warnings: readinessWarnings,
      checkedAt: _now.subtract(const Duration(minutes: 1)),
      expiresAt: expiresAt ?? _now.add(const Duration(minutes: 30)),
      isReady: readinessIsReady,
    ),
  );
}

MeasurementCaptureGateResult _evaluate(
  ProProject? project, {
  MeasurementRuntimeInputAvailability? availability =
      MeasurementRuntimeInputAvailability.available,
  bool? permission = true,
  MeasurementWarningAcknowledgement? ack,
}) =>
    MeasurementCaptureGate.evaluate(
      project: project,
      now: _now,
      policy: _policy,
      inputAvailability: availability,
      microphonePermissionGranted: permission,
      acknowledgement: ack,
    );

void main() {
  group('1. blocked: chain prerequisites', () {
    test('no project', () {
      final r = _evaluate(null);
      expect(r.canCapture, isFalse);
      expect(r.primaryBlocker?.code, MeasurementCaptureBlockerCode.noProject);
      expect(r.primaryBlocker?.remediation,
          MeasurementCaptureRemediation.createOrOpenProject);
    });

    test('no microphone profile', () {
      final r = _evaluate(_project(device: _specificDevice()));
      expect(r.canCapture, isFalse);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.noMicrophoneProfile),
          isTrue);
      expect(r.primaryBlocker?.remediation,
          MeasurementCaptureRemediation.manageMicrophone);
    });

    test('no input device selected', () {
      final r = _evaluate(_project(profile: _profile()));
      expect(r.canCapture, isFalse);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.noInputDeviceSelected),
          isTrue);
    });

    test('specific device unavailable', () {
      final r = _evaluate(
          _project(profile: _profile(), device: _specificDevice()),
          availability: MeasurementRuntimeInputAvailability.unavailable);
      expect(r.canCapture, isFalse);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.inputDeviceUnavailable),
          isTrue);
      expect(
          r.blockers
              .firstWhere((b) =>
                  b.code ==
                  MeasurementCaptureBlockerCode.inputDeviceUnavailable)
              .remediation,
          MeasurementCaptureRemediation.checkInputDeviceAgain);
    });

    test('unknown device availability blocks (never assumed present)', () {
      final r = _evaluate(
          _project(profile: _profile(), device: _specificDevice()),
          availability: null);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.inputDeviceUnavailable),
          isTrue);
    });

    test('system-default is attemptable only as systemDefaultUnverified', () {
      final project = _project(
        profile: _profile(),
        device: MeasurementInputDeviceSelection.systemDefault(selectedAt: _now),
      );
      final r = _evaluate(project,
          availability:
              MeasurementRuntimeInputAvailability.systemDefaultUnverified);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.inputDeviceUnavailable),
          isFalse);
      expect(r.canCapture, isTrue);
      expect(r.inputAvailability,
          MeasurementRuntimeInputAvailability.systemDefaultUnverified,
          reason: 'never upgraded to "available" -- the OS default input '
              'cannot be preflight-verified');
    });

    test('permission denied, and unknown permission also blocks', () {
      final project = _project(profile: _profile(), device: _specificDevice());
      for (final p in [false, null]) {
        final r = _evaluate(project, permission: p);
        expect(r.canCapture, isFalse);
        expect(
            r.hasBlocker(
                MeasurementCaptureBlockerCode.microphonePermissionDenied),
            isTrue);
      }
    });
  });

  group('1b. P0 — system-default input is never assumed present', () {
    const specific = MeasurementInputDeviceDescriptor(id: 'dev-1', label: 'A');
    const other = MeasurementInputDeviceDescriptor(id: 'dev-2', label: 'B');

    test('resolveInputAvailability: empty enumeration is always unavailable',
        () {
      for (final sel in [
        _specificDevice(),
        MeasurementInputDeviceSelection.systemDefault(selectedAt: _now),
      ]) {
        expect(
            MeasurementCaptureGate.resolveInputAvailability(
                selection: sel, freshDevices: const []),
            MeasurementRuntimeInputAvailability.unavailable);
      }
    });

    test(
        'resolveInputAvailability: system default with devices present is '
        'systemDefaultUnverified, never available', () {
      final r = MeasurementCaptureGate.resolveInputAvailability(
        selection:
            MeasurementInputDeviceSelection.systemDefault(selectedAt: _now),
        freshDevices: const [specific, other],
      );
      expect(r, MeasurementRuntimeInputAvailability.systemDefaultUnverified);
      expect(r, isNot(MeasurementRuntimeInputAvailability.available));
    });

    test('resolveInputAvailability: specific device matched / vanished', () {
      expect(
          MeasurementCaptureGate.resolveInputAvailability(
              selection: _specificDevice(), freshDevices: const [specific]),
          MeasurementRuntimeInputAvailability.available);
      expect(
          MeasurementCaptureGate.resolveInputAvailability(
              selection: _specificDevice(), freshDevices: const [other]),
          MeasurementRuntimeInputAvailability.unavailable);
    });

    test('system default + no input devices at all -> blocked', () {
      final project = _project(
        profile: _profile(),
        device: MeasurementInputDeviceSelection.systemDefault(selectedAt: _now),
      );
      final availability = MeasurementCaptureGate.resolveInputAvailability(
          selection: project.selectedInputDevice, freshDevices: const []);
      final r = _evaluate(project, availability: availability);
      expect(r.canCapture, isFalse);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.inputDeviceUnavailable),
          isTrue);
    });

    test('system default + permission denied -> blocked', () {
      final project = _project(
        profile: _profile(),
        device: MeasurementInputDeviceSelection.systemDefault(selectedAt: _now),
      );
      final r = _evaluate(project,
          availability:
              MeasurementRuntimeInputAvailability.systemDefaultUnverified,
          permission: false);
      expect(r.canCapture, isFalse);
      expect(
          r.hasBlocker(
              MeasurementCaptureBlockerCode.microphonePermissionDenied),
          isTrue);
    });

    test('system default with no prior setup check -> setupNotChecked', () {
      final project = _project(
        profile: _profile(),
        device: MeasurementInputDeviceSelection.systemDefault(selectedAt: _now),
        withReadiness: false,
      );
      final r = _evaluate(project,
          availability:
              MeasurementRuntimeInputAvailability.systemDefaultUnverified);
      expect(r.canCapture, isFalse);
      expect(
          r.hasBlocker(MeasurementCaptureBlockerCode.setupNotChecked), isTrue);
    });

    test(
        'a setup check performed on a SPECIFIC device does not authorise a '
        'later system-default capture', () {
      // Readiness recorded under 'device:dev-1'; the project now selects
      // system default -> identity mismatch, not silently accepted.
      final project = _project(
        profile: _profile(),
        device: MeasurementInputDeviceSelection.systemDefault(selectedAt: _now),
        mutateIdentity: (i) =>
            _identity(i, inputDeviceIdentity: 'device:dev-1'),
      );
      final r = _evaluate(project,
          availability:
              MeasurementRuntimeInputAvailability.systemDefaultUnverified);
      expect(r.canCapture, isFalse);
      expect(
          r.hasBlocker(MeasurementCaptureBlockerCode.setupInputDeviceMismatch),
          isTrue);
    });

    test(
        'system default + valid setup on the same selection + devices present '
        '-> capture attempt allowed (recorder start remains the authority)',
        () {
      final project = _project(
        profile: _profile(),
        device: MeasurementInputDeviceSelection.systemDefault(selectedAt: _now),
      );
      final availability = MeasurementCaptureGate.resolveInputAvailability(
          selection: project.selectedInputDevice,
          freshDevices: const [specific]);
      final r = _evaluate(project, availability: availability);
      expect(r.canCapture, isTrue);
      expect(r.inputAvailability,
          MeasurementRuntimeInputAvailability.systemDefaultUnverified,
          reason: 'attemptable, but still not "confirmed"');
    });
  });

  group('2. blocked: calibration provenance', () {
    test('invalid calibration curve blocks', () {
      const invalid = CalibrationCurve(
        points: [CalibrationPoint(frequencyHz: 20, correctionDb: 1.0)],
        angle: CalibrationAngle.zeroDegree,
        validMinFrequencyHz: 5000, // min > max -> structurally invalid
        validMaxFrequencyHz: 100,
        sourceIdentity: 'bad.txt',
        checksum: 'bad',
        interpolationPolicy:
            CalibrationInterpolationPolicy.logFrequencyLinearDb,
      );
      final r = _evaluate(_project(
          profile: _profile(curve: invalid), device: _specificDevice()));
      expect(r.canCapture, isFalse);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.invalidCalibration),
          isTrue);
    });

    test('calibrated source with no curve = legacy unknown, blocks', () {
      final r = _evaluate(_project(
          profile: _profile(noCurve: true), device: _specificDevice()));
      expect(r.canCapture, isFalse);
      expect(
          r.hasBlocker(MeasurementCaptureBlockerCode.legacyUnknownCalibration),
          isTrue);
      expect(
          r.blockers
              .firstWhere((b) =>
                  b.code ==
                  MeasurementCaptureBlockerCode.legacyUnknownCalibration)
              .remediation,
          MeasurementCaptureRemediation.manageMicrophone);
    });
  });

  group('3. blocked: setup readiness', () {
    test('setup never checked', () {
      final r = _evaluate(_project(
          profile: _profile(),
          device: _specificDevice(),
          withReadiness: false));
      expect(r.canCapture, isFalse);
      expect(
          r.hasBlocker(MeasurementCaptureBlockerCode.setupNotChecked), isTrue);
      expect(r.activeGenerationId, isNull);
    });

    test('setup not ready forwards the check\'s own blockers verbatim', () {
      final r = _evaluate(_project(
        profile: _profile(),
        device: _specificDevice(),
        readinessIsReady: false,
        readinessBlockers: const ['입력 신호가 클리핑되었습니다.'],
      ));
      expect(r.canCapture, isFalse);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.setupNotReady), isTrue);
      expect(
          r.blockers.any((b) =>
              b.code == MeasurementCaptureBlockerCode.setupQuality &&
              b.message == '입력 신호가 클리핑되었습니다.'),
          isTrue);
    });

    test('expired setup', () {
      final r = _evaluate(_project(
        profile: _profile(),
        device: _specificDevice(),
        expiresAt: _now.subtract(const Duration(minutes: 1)),
      ));
      expect(r.canCapture, isFalse);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.setupExpired), isTrue);
      expect(r.primaryBlocker?.remediation,
          MeasurementCaptureRemediation.runSetupCheck);
    });

    test('each identity component mismatch is reported specifically', () {
      final cases = <MeasurementCaptureBlockerCode,
          MeasurementSetupReadinessIdentity Function(
              MeasurementSetupReadinessIdentity)>{
        MeasurementCaptureBlockerCode.setupProjectMismatch: (i) =>
            _identity(i, projectId: 'other-project'),
        MeasurementCaptureBlockerCode.setupProfileMismatch: (i) =>
            _identity(i, profileChecksum: 'other-profile'),
        MeasurementCaptureBlockerCode.setupCalibrationCurveMismatch: (i) =>
            _identity(i, calibrationCurveChecksum: 'other-curve'),
        MeasurementCaptureBlockerCode.setupOrientationMismatch: (i) =>
            _identity(i, calibrationAngle: 'ninetyDegree'),
        MeasurementCaptureBlockerCode.setupInputDeviceMismatch: (i) =>
            _identity(i, inputDeviceIdentity: 'device:other'),
        MeasurementCaptureBlockerCode.setupPolicyVersionMismatch: (i) =>
            _identity(i, qualityPolicyVersion: 'v0-ancient'),
        MeasurementCaptureBlockerCode.setupSampleRateMismatch: (i) =>
            _identity(i, expectedSampleRate: 44100),
        MeasurementCaptureBlockerCode.setupChannelMismatch: (i) =>
            _identity(i, expectedChannelCount: 2),
      };

      cases.forEach((code, mutate) {
        final r = _evaluate(_project(
          profile: _profile(),
          device: _specificDevice(),
          mutateIdentity: mutate,
        ));
        expect(r.canCapture, isFalse, reason: code.name);
        expect(r.hasBlocker(code), isTrue, reason: code.name);
        expect(r.blockers.firstWhere((b) => b.code == code).remediation,
            MeasurementCaptureRemediation.runSetupCheck,
            reason: code.name);
      });
    });
  });

  group('4. warnings need an explicit, identity-bound acknowledgement', () {
    ProProject uncalibratedProject() => _project(
          profile:
              _profile(source: CalibrationSource.uncalibrated, noCurve: true),
          device: _specificDevice(),
        );

    test('explicitly uncalibrated warns and blocks capture until acked', () {
      final r = _evaluate(uncalibratedProject());
      expect(r.blockers, isEmpty);
      expect(r.hasWarning(MeasurementCaptureWarningCode.explicitlyUncalibrated),
          isTrue);
      expect(r.requiresExplicitWarningAcknowledgement, isTrue);
      expect(r.canCapture, isFalse,
          reason: 'a warning must never be bypassed implicitly');
    });

    test('setup-check warnings are forwarded and also require an ack', () {
      final r = _evaluate(_project(
        profile: _profile(),
        device: _specificDevice(),
        readinessWarnings: const ['SNR이 권장치보다 낮습니다.'],
      ));
      expect(r.blockers, isEmpty);
      expect(r.hasWarning(MeasurementCaptureWarningCode.setupQuality), isTrue);
      expect(r.canCapture, isFalse);
    });

    test('a matching acknowledgement unlocks capture', () {
      final project = uncalibratedProject();
      final ack = MeasurementWarningAcknowledgement(
        projectId: 'proj-1',
        profileIdentity: project.selectedMicrophoneProfile!.checksum,
        deviceIdentity: 'device:dev-1',
        readinessGenerationId: 'gen-1',
        warningCodes: const {
          MeasurementCaptureWarningCode.explicitlyUncalibrated
        },
        acknowledgedAt: _now,
      );
      final r = _evaluate(project, ack: ack);
      expect(r.canCapture, isTrue);
      expect(r.requiresExplicitWarningAcknowledgement, isFalse);
      expect(r.activeGenerationId, 'gen-1');
    });

    test('acknowledgement does not carry across a new setup generation', () {
      final project = uncalibratedProject();
      final ack = MeasurementWarningAcknowledgement(
        projectId: 'proj-1',
        profileIdentity: project.selectedMicrophoneProfile!.checksum,
        deviceIdentity: 'device:dev-1',
        readinessGenerationId: 'gen-OLD',
        warningCodes: const {
          MeasurementCaptureWarningCode.explicitlyUncalibrated
        },
        acknowledgedAt: _now,
      );
      expect(_evaluate(project, ack: ack).canCapture, isFalse);
    });

    test('acknowledgement does not carry across a device change', () {
      final project = uncalibratedProject();
      final ack = MeasurementWarningAcknowledgement(
        projectId: 'proj-1',
        profileIdentity: project.selectedMicrophoneProfile!.checksum,
        deviceIdentity: 'device:SOME-OTHER-DEVICE',
        readinessGenerationId: 'gen-1',
        warningCodes: const {
          MeasurementCaptureWarningCode.explicitlyUncalibrated
        },
        acknowledgedAt: _now,
      );
      expect(_evaluate(project, ack: ack).canCapture, isFalse);
    });

    test('an ack for a different warning kind does not cover a new one', () {
      final project = uncalibratedProject();
      final ack = MeasurementWarningAcknowledgement(
        projectId: 'proj-1',
        profileIdentity: project.selectedMicrophoneProfile!.checksum,
        deviceIdentity: 'device:dev-1',
        readinessGenerationId: 'gen-1',
        warningCodes: const {MeasurementCaptureWarningCode.setupQuality},
        acknowledgedAt: _now,
      );
      expect(_evaluate(project, ack: ack).canCapture, isFalse);
    });

    test('an acknowledgement never overrides a blocker', () {
      final project = _project(
        profile:
            _profile(source: CalibrationSource.uncalibrated, noCurve: true),
        device: _specificDevice(),
        expiresAt: _now.subtract(const Duration(minutes: 1)),
      );
      final ack = MeasurementWarningAcknowledgement(
        projectId: 'proj-1',
        profileIdentity: project.selectedMicrophoneProfile!.checksum,
        deviceIdentity: 'device:dev-1',
        readinessGenerationId: 'gen-1',
        warningCodes: const {
          MeasurementCaptureWarningCode.explicitlyUncalibrated
        },
        acknowledgedAt: _now,
      );
      final r = _evaluate(project, ack: ack);
      expect(r.canCapture, isFalse);
      expect(r.hasBlocker(MeasurementCaptureBlockerCode.setupExpired), isTrue);
    });

    test('acknowledgement JSON round-trip preserves identity binding', () {
      final ack = MeasurementWarningAcknowledgement(
        projectId: 'proj-1',
        profileIdentity: 'profile-1',
        deviceIdentity: 'device:dev-1',
        readinessGenerationId: 'gen-1',
        warningCodes: const {
          MeasurementCaptureWarningCode.explicitlyUncalibrated,
          MeasurementCaptureWarningCode.setupQuality,
        },
        acknowledgedAt: _now,
      );
      final decoded = MeasurementWarningAcknowledgement.fromJson(ack.toJson());
      expect(decoded.projectId, ack.projectId);
      expect(decoded.profileIdentity, ack.profileIdentity);
      expect(decoded.deviceIdentity, ack.deviceIdentity);
      expect(decoded.readinessGenerationId, ack.readinessGenerationId);
      expect(decoded.warningCodes, ack.warningCodes);
      expect(decoded.acknowledgedAt, ack.acknowledgedAt);
    });
  });

  group('5. fully valid chain', () {
    test('everything aligned -> canCapture with identity exposed', () {
      final r =
          _evaluate(_project(profile: _profile(), device: _specificDevice()));
      expect(r.canCapture, isTrue);
      expect(r.blockers, isEmpty);
      expect(r.warnings, isEmpty);
      expect(r.requiresExplicitWarningAcknowledgement, isFalse);
      expect(r.activeGenerationId, 'gen-1');
      expect(r.profileIdentity, isNotNull);
      expect(r.deviceIdentity, 'device:dev-1');
    });

    test('blockers are ordered by measurement-chain position', () {
      // No profile AND no device AND no setup check: the microphone is the
      // earliest chain step, so it is what the user is told to fix first.
      final r = _evaluate(_project(withReadiness: false));
      expect(r.primaryBlocker?.code,
          MeasurementCaptureBlockerCode.noMicrophoneProfile);
    });
  });
}

MeasurementSetupReadinessIdentity _identity(
  MeasurementSetupReadinessIdentity base, {
  String? projectId,
  String? profileChecksum,
  String? calibrationCurveChecksum,
  String? calibrationAngle,
  String? inputDeviceIdentity,
  int? expectedSampleRate,
  int? expectedChannelCount,
  String? qualityPolicyVersion,
}) =>
    MeasurementSetupReadinessIdentity(
      projectId: projectId ?? base.projectId,
      profileChecksum: profileChecksum ?? base.profileChecksum,
      calibrationCurveChecksum:
          calibrationCurveChecksum ?? base.calibrationCurveChecksum,
      calibrationAngle: calibrationAngle ?? base.calibrationAngle,
      inputDeviceIdentity: inputDeviceIdentity ?? base.inputDeviceIdentity,
      expectedSampleRate: expectedSampleRate ?? base.expectedSampleRate,
      expectedChannelCount: expectedChannelCount ?? base.expectedChannelCount,
      qualityPolicyVersion: qualityPolicyVersion ?? base.qualityPolicyVersion,
    );
