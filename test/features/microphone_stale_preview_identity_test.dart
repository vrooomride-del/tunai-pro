// Phase 3-C Final Closure Check — stale-preview identity coverage.
//
// The stale-preview guard in LiveMeasurementController/RoomMeasurementController
// .accept() compares MeasurementMicrophoneSnapshot.profileChecksum (captured
// at capture time) against the CURRENT MeasurementMicrophoneProfile.checksum.
// This file proves that guard actually fires for every field that changes a
// profile's measurement-relevant identity, not just "swapped to a different
// profile object" (already covered by microphone_stale_preview_test.dart).
//
// Orientation is the one dimension that lives on CalibrationCurve, not
// MeasurementMicrophoneProfile directly, and CalibrationCurve.checksum
// hashes points only — so it was the one genuinely at risk of NOT being
// caught. calibration_types_test.dart proves the checksum fix at the pure
// level; this file proves it actually blocks Accept end-to-end.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/live_measurement_controller.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import '../support/capture_gate_fixtures.dart';

const _points = [
  CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
  CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
];

CalibrationCurve _curve(
        {CalibrationAngle angle = CalibrationAngle.unspecified}) =>
    CalibrationCurve(
      points: _points,
      angle: angle,
      validMinFrequencyHz: 20,
      validMaxFrequencyHz: 20000,
      sourceIdentity: 'test',
      checksum: CalibrationCurve.checksumFor(_points),
    );

MeasurementMicrophoneProfile _baseProfile() => MeasurementMicrophoneProfile(
      id: 'mic-1',
      manufacturer: 'ACME',
      model: 'M1',
      serialNumber: 'SN-1',
      connectionType: 'USB',
      inputDeviceId: 'device-a',
      calibrationSource: CalibrationSource.userImported,
      calibrationCurve: _curve(),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class _FakeMicController extends mic.MicMeasurementController {
  // Capture is gated (Phase 3-D3): the gate's runtime preflight asks this
  // service for permission + a fresh device list. Serve the known-good chain
  // the shared fixtures seed, so these tests exercise capture mechanics
  // rather than re-testing the gate.
  @override
  MeasurementInputDeviceService get inputDeviceService =>
      fakeGateInputDeviceService();

  _FakeMicController(super.ref);

  @override
  Future<void> startMeasurement({
    CalibrationCurve? calibrationCurve,
    dynamic speakerProfile,
    bool bleWarmup = false,
  }) async {
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: const [
        {'frequency': 1000.0, 'db': -1.0},
      ],
      rawFrequencyResponse: const [
        {'frequency': 1000.0, 'db': -1.0},
      ],
      calibrationStatus: calibrationCurve != null
          ? CalibrationStatus.calibrated
          : CalibrationStatus.explicitlyUncalibrated,
      calibrationCurveChecksum: calibrationCurve?.checksum,
    );
  }

  @override
  Future<void> startRoomMeasurement({
    required bool leftActive,
    CalibrationCurve? calibrationCurve,
    bool bleWarmup = false,
  }) async {
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: const [
        {'frequency': 80.0, 'db': -1.0},
        {'frequency': 800.0, 'db': -2.0},
      ],
      rawFrequencyResponse: const [
        {'frequency': 80.0, 'db': -1.0},
        {'frequency': 800.0, 'db': -2.0},
      ],
      calibrationStatus: calibrationCurve != null
          ? CalibrationStatus.calibrated
          : CalibrationStatus.explicitlyUncalibrated,
      calibrationCurveChecksum: calibrationCurve?.checksum,
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

DriverChannel _channel(String id) => DriverChannel(
      id: id,
      name: id,
      role: id.contains('tw') ? DriverRole.tweeter : DriverRole.woofer,
      side: id.endsWith('l') ? DriverSide.left : DriverSide.right,
    );

ProProject _project({required MeasurementMicrophoneProfile profile}) =>
    withGateReadySetup(ProProject(
      id: 'proj-identity-1',
      name: 'Identity Test Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      acousticState: MeasurementProjectState(driverChannels: [
        _channel('ch_tw_l'),
        _channel('ch_wf_l'),
        _channel('ch_tw_r'),
        _channel('ch_wf_r'),
      ]),
      tuningState: TuningProjectState(peqChannels: const []),
      selectedMicrophoneProfile: profile,
    ));

Future<ProviderContainer> _seed(MeasurementMicrophoneProfile profile) async {
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) => _FakeMicController(ref)),
  ]);
  await container
      .read(proProjectStoreProvider.notifier)
      .addProject(_project(profile: profile));
  container.read(mic.micMeasurementProvider);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  const justAudioChannel = MethodChannel('com.ryanheise.just_audio.methods');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(justAudioChannel, (call) async => null);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(justAudioChannel, null);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Factory: identity-dimension changes block Accept', () {
    test('orientation change after capture blocks Accept', () async {
      final container = await _seed(_baseProfile());
      addTearDown(container.dispose);
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-identity-1').notifier);
      ctrl.markReady();
      await ctrl.capture();

      final reoriented = _baseProfile().copyWith(
          calibrationCurve: _curve(angle: CalibrationAngle.zeroDegree));
      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-identity-1', reoriented);

      await ctrl.accept();
      final state =
          container.read(liveMeasurementControllerProvider('proj-identity-1'));
      expect(state.phase, LiveMeasurementPhase.ready);
      expect(state.error, isNotNull);
    });

    test('serial number change after capture blocks Accept', () async {
      final container = await _seed(_baseProfile());
      addTearDown(container.dispose);
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-identity-1').notifier);
      ctrl.markReady();
      await ctrl.capture();

      final resernaled = _baseProfile().copyWith(serialNumber: 'SN-2');
      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-identity-1', resernaled);

      await ctrl.accept();
      final state =
          container.read(liveMeasurementControllerProvider('proj-identity-1'));
      expect(state.phase, LiveMeasurementPhase.ready);
      expect(state.error, isNotNull);
    });

    test('input device change after capture blocks Accept', () async {
      final container = await _seed(_baseProfile());
      addTearDown(container.dispose);
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-identity-1').notifier);
      ctrl.markReady();
      await ctrl.capture();

      final moved = _baseProfile().copyWith(inputDeviceId: 'device-b');
      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-identity-1', moved);

      await ctrl.accept();
      final state =
          container.read(liveMeasurementControllerProvider('proj-identity-1'));
      expect(state.phase, LiveMeasurementPhase.ready);
      expect(state.error, isNotNull);
    });

    test('calibration curve (points) change after capture blocks Accept',
        () async {
      final container = await _seed(_baseProfile());
      addTearDown(container.dispose);
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-identity-1').notifier);
      ctrl.markReady();
      await ctrl.capture();

      const newPoints = [
        CalibrationPoint(frequencyHz: 20, correctionDb: 3.0),
        CalibrationPoint(frequencyHz: 20000, correctionDb: -3.0),
      ];
      final recalibrated = _baseProfile().copyWith(
        calibrationCurve: CalibrationCurve(
          points: newPoints,
          validMinFrequencyHz: 20,
          validMaxFrequencyHz: 20000,
          sourceIdentity: 'test2',
          checksum: CalibrationCurve.checksumFor(newPoints),
        ),
      );
      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-identity-1', recalibrated);

      await ctrl.accept();
      final state =
          container.read(liveMeasurementControllerProvider('proj-identity-1'));
      expect(state.phase, LiveMeasurementPhase.ready);
      expect(state.error, isNotNull);
    });
  });

  group('Room: identity-dimension changes block Accept', () {
    test('orientation change after capture blocks Accept', () async {
      final container = await _seed(_baseProfile());
      addTearDown(container.dispose);
      final ctrl = container
          .read(roomMeasurementControllerProvider('proj-identity-1').notifier);
      ctrl.markReady();
      await ctrl.capture();

      final reoriented = _baseProfile().copyWith(
          calibrationCurve: _curve(angle: CalibrationAngle.zeroDegree));
      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-identity-1', reoriented);

      await ctrl.accept();
      final state =
          container.read(roomMeasurementControllerProvider('proj-identity-1'));
      expect(state.phase, RoomMeasurementPhaseUi.ready);
      expect(state.error, isNotNull);
    });

    test('serial number change after capture blocks Accept', () async {
      final container = await _seed(_baseProfile());
      addTearDown(container.dispose);
      final ctrl = container
          .read(roomMeasurementControllerProvider('proj-identity-1').notifier);
      ctrl.markReady();
      await ctrl.capture();

      final resernaled = _baseProfile().copyWith(serialNumber: 'SN-2');
      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-identity-1', resernaled);

      await ctrl.accept();
      final state =
          container.read(roomMeasurementControllerProvider('proj-identity-1'));
      expect(state.phase, RoomMeasurementPhaseUi.ready);
      expect(state.error, isNotNull);
    });

    test('input device change after capture blocks Accept', () async {
      final container = await _seed(_baseProfile());
      addTearDown(container.dispose);
      final ctrl = container
          .read(roomMeasurementControllerProvider('proj-identity-1').notifier);
      ctrl.markReady();
      await ctrl.capture();

      final moved = _baseProfile().copyWith(inputDeviceId: 'device-b');
      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-identity-1', moved);

      await ctrl.accept();
      final state =
          container.read(roomMeasurementControllerProvider('proj-identity-1'));
      expect(state.phase, RoomMeasurementPhaseUi.ready);
      expect(state.error, isNotNull);
    });

    test('calibration curve (points) change after capture blocks Accept',
        () async {
      final container = await _seed(_baseProfile());
      addTearDown(container.dispose);
      final ctrl = container
          .read(roomMeasurementControllerProvider('proj-identity-1').notifier);
      ctrl.markReady();
      await ctrl.capture();

      const newPoints = [
        CalibrationPoint(frequencyHz: 20, correctionDb: 3.0),
        CalibrationPoint(frequencyHz: 20000, correctionDb: -3.0),
      ];
      final recalibrated = _baseProfile().copyWith(
        calibrationCurve: CalibrationCurve(
          points: newPoints,
          validMinFrequencyHz: 20,
          validMaxFrequencyHz: 20000,
          sourceIdentity: 'test2',
          checksum: CalibrationCurve.checksumFor(newPoints),
        ),
      );
      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-identity-1', recalibrated);

      await ctrl.accept();
      final state =
          container.read(roomMeasurementControllerProvider('proj-identity-1'));
      expect(state.phase, RoomMeasurementPhaseUi.ready);
      expect(state.error, isNotNull);
    });
  });
}
