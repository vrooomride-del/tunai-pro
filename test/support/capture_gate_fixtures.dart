// Shared fixtures for tests whose subject is downstream of the Phase 3-D3
// MeasurementCaptureGate (Factory/Room capture, stale-preview, room Auto PEQ,
// Room UI). Capture is now fail-closed: it needs a microphone profile, a
// selected input device, a still-valid setup readiness matching the current
// identity, granted permission, and a fresh enumeration containing the
// device. Tests that exercise capture MECHANICS (retry/accept/persistence)
// are not testing the gate, so they seed a known-good chain from here rather
// than each re-deriving one — and any future gate condition only needs
// adding in one place.

import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_policy.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness_project_identity.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';

const kGateTestDeviceId = 'gate-test-device';

/// An input-device API that reports permission granted and exactly one
/// device — the one [gateReadyDevice] selects.
class FakeGateInputDeviceApi implements MeasurementInputDeviceApi {
  bool permissionGranted;
  List<MeasurementInputDeviceDescriptor> devices;

  FakeGateInputDeviceApi({
    this.permissionGranted = true,
    this.devices = const [
      MeasurementInputDeviceDescriptor(
          id: kGateTestDeviceId, label: 'Gate Test Mic'),
    ],
  });

  @override
  Future<bool> hasPermission({bool request = true}) async => permissionGranted;

  @override
  Future<List<MeasurementInputDeviceDescriptor>> listInputDevices() async =>
      devices;
}

MeasurementInputDeviceService fakeGateInputDeviceService(
        [FakeGateInputDeviceApi? api]) =>
    MeasurementInputDeviceService(api ?? FakeGateInputDeviceApi());

CalibrationCurve gateReadyCalibrationCurve() => const CalibrationCurve(
      points: [
        CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
        CalibrationPoint(frequencyHz: 1000, correctionDb: 0.0),
        CalibrationPoint(frequencyHz: 20000, correctionDb: -0.5),
      ],
      angle: CalibrationAngle.zeroDegree,
      validMinFrequencyHz: 10,
      validMaxFrequencyHz: 22000,
      sourceIdentity: 'gate-test-curve.txt',
      checksum: 'gate-test-curve',
      interpolationPolicy: CalibrationInterpolationPolicy.logFrequencyLinearDb,
    );

MeasurementMicrophoneProfile gateReadyProfile() => MeasurementMicrophoneProfile(
      id: 'gate-test-mic',
      manufacturer: 'TUNAI',
      model: 'Gate Test',
      connectionType: 'usb',
      calibrationSource: CalibrationSource.manufacturerFile,
      calibrationCurve: gateReadyCalibrationCurve(),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

MeasurementInputDeviceSelection gateReadyDevice() =>
    MeasurementInputDeviceSelection.specificDevice(
      deviceId: kGateTestDeviceId,
      labelSnapshot: 'Gate Test Mic',
      selectedAt: DateTime.utc(2026, 1, 1),
    );

/// Returns [project] with a microphone profile, input device, and a valid
/// non-expired setup readiness whose identity matches the resulting project —
/// i.e. a chain MeasurementCaptureGate accepts.
/// Re-runs the equivalent of a successful Guided Measurement Setup check for
/// whatever chain the stored project currently has. Needed after a test
/// changes the microphone/device mid-flow: that change invalidates the prior
/// readiness by design, so the gate blocks the next capture until the user
/// re-checks. Tests whose subject is downstream of that re-check call this
/// instead of asserting the (correct) blocked state.
Future<void> refreshGateReadiness(
  ProProjectStoreNotifier store,
  ProProject project,
) async {
  final identity = MeasurementSetupReadinessProjectIdentity.forProject(
    project,
    policy: MeasurementQualityPolicy.proProvisional(),
  );
  final now = DateTime.now();
  await store.updateSetupReadiness(
    project.id,
    MeasurementSetupReadinessSnapshot(
      identity: identity,
      generationId: 'gate-test-generation-${now.microsecondsSinceEpoch}',
      blockers: const [],
      warnings: const [],
      checkedAt: now.subtract(const Duration(seconds: 1)),
      expiresAt: now.add(const Duration(hours: 12)),
      isReady: true,
    ),
  );
}

/// A project that already carries its own microphone profile keeps it — the
/// stale-preview tests make the profile their subject, and the readiness
/// identity is then derived from THAT profile so the chain still matches.
ProProject withGateReadySetup(ProProject project) {
  final withChain = project.copyWith(
    selectedMicrophoneProfile:
        project.selectedMicrophoneProfile ?? gateReadyProfile(),
    selectedInputDevice: project.selectedInputDevice ?? gateReadyDevice(),
  );
  final identity = MeasurementSetupReadinessProjectIdentity.forProject(
    withChain,
    policy: MeasurementQualityPolicy.proProvisional(),
  );
  final now = DateTime.now();
  return withChain.copyWith(
    currentSetupReadiness: MeasurementSetupReadinessSnapshot(
      identity: identity,
      generationId: 'gate-test-generation',
      blockers: const [],
      warnings: const [],
      checkedAt: now.subtract(const Duration(minutes: 1)),
      expiresAt: now.add(const Duration(hours: 12)),
      isReady: true,
    ),
  );
}
