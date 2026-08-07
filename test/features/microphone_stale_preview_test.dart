// Phase 3-C — Microphone profile <-> live capture integration.
//
// Verifies:
//  1. The profile currently shown as project.selectedMicrophoneProfile is
//     exactly what capture() passes into MicMeasurementController, for both
//     Factory (LiveMeasurementController) and Room (RoomMeasurementController).
//  2. Changing the profile only affects the NEXT capture — an already
//     accepted measurement is untouched.
//  3. Stale-preview guard: capturing under profile A, then changing the
//     project's selected profile to B before Accept, blocks the accept and
//     requires a fresh capture — it never silently persists data captured
//     under a no-longer-selected profile.

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

CalibrationCurve _curve(String tag) {
  final points = [
    CalibrationPoint(frequencyHz: 20, correctionDb: tag == 'A' ? 0.5 : 1.5),
    const CalibrationPoint(frequencyHz: 20000, correctionDb: 0.0),
  ];
  return CalibrationCurve(
    points: points,
    validMinFrequencyHz: 20,
    validMaxFrequencyHz: 20000,
    sourceIdentity: tag,
    checksum: CalibrationCurve.checksumFor(points),
  );
}

MeasurementMicrophoneProfile _profile(String id, {String tag = 'A'}) =>
    MeasurementMicrophoneProfile(
      id: id,
      manufacturer: 'ACME',
      model: 'M-$id',
      connectionType: 'USB',
      calibrationSource: CalibrationSource.userImported,
      calibrationCurve: _curve(tag),
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
  CalibrationCurve? lastCalibrationCurve;
  int callCount = 0;

  @override
  Future<void> startMeasurement({
    CalibrationCurve? calibrationCurve,
    dynamic speakerProfile,
    bool bleWarmup = false,
  }) async {
    callCount++;
    lastCalibrationCurve = calibrationCurve;
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
    callCount++;
    lastCalibrationCurve = calibrationCurve;
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

ProProject _project({MeasurementMicrophoneProfile? profile}) =>
    withGateReadySetup(ProProject(
      id: 'proj-mic-1',
      name: 'Mic Test Project',
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

Future<
    ({
      ProviderContainer container,
      _FakeMicController fakeMic,
    })> _seed({MeasurementMicrophoneProfile? profile}) async {
  late _FakeMicController fakeMicInstance;
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) {
      fakeMicInstance = _FakeMicController(ref);
      return fakeMicInstance;
    }),
  ]);
  await container
      .read(proProjectStoreProvider.notifier)
      .addProject(_project(profile: profile));
  container.read(mic.micMeasurementProvider);
  return (container: container, fakeMic: fakeMicInstance);
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

  group('Factory: capture uses exactly the currently selected profile', () {
    test('profile A selected -> capture passes profile A\'s curve', () async {
      final seeded = await _seed(profile: _profile('mic-a', tag: 'A'));
      addTearDown(seeded.container.dispose);
      final ctrl = seeded.container
          .read(liveMeasurementControllerProvider('proj-mic-1').notifier);
      ctrl.markReady();
      await ctrl.capture();
      expect(seeded.fakeMic.lastCalibrationCurve?.checksum,
          _profile('mic-a', tag: 'A').calibrationCurve!.checksum);
    });

    test(
        'changing the profile only affects the NEXT capture, not an '
        'already-accepted measurement', () async {
      final seeded = await _seed(profile: _profile('mic-a', tag: 'A'));
      addTearDown(seeded.container.dispose);
      final ctrl = seeded.container
          .read(liveMeasurementControllerProvider('proj-mic-1').notifier);
      ctrl.markReady();
      await ctrl.capture();
      await ctrl.accept();

      final projectStore =
          seeded.container.read(proProjectStoreProvider.notifier);
      final projectBefore = seeded.container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-mic-1');
      final acceptedChecksum = projectBefore.acousticState.driverChannels
          .firstWhere((c) => c.id == 'ch_tw_l')
          .frdData
          ?.calibrationCurveChecksum;
      expect(acceptedChecksum,
          _profile('mic-a', tag: 'A').calibrationCurve!.checksum);

      // Switch to profile B, capture the next channel.
      await projectStore.updateSelectedMicrophoneProfile(
          'proj-mic-1', _profile('mic-b', tag: 'B'));
      // Swapping the microphone invalidates the setup readiness by design
      // (Phase 3-D3 capture gate), so the user re-runs the setup check
      // before the next capture. This test's subject is what the NEXT
      // capture uses, not the (separately tested) blocked-until-recheck
      // state.
      await refreshGateReadiness(
          projectStore,
          seeded.container
              .read(proProjectStoreProvider)
              .projects
              .firstWhere((p) => p.id == 'proj-mic-1'));
      ctrl.markReady();
      await ctrl.capture();
      expect(seeded.fakeMic.lastCalibrationCurve?.checksum,
          _profile('mic-b', tag: 'B').calibrationCurve!.checksum);

      // The earlier accepted measurement's stored calibration checksum is
      // unchanged by the later profile switch.
      final projectAfter = seeded.container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-mic-1');
      final stillA = projectAfter.acousticState.driverChannels
          .firstWhere((c) => c.id == 'ch_tw_l')
          .frdData
          ?.calibrationCurveChecksum;
      expect(stillA, acceptedChecksum);
    });

    test(
        'stale preview: capture under A, switch to B before Accept -> '
        'accept is blocked and nothing is persisted', () async {
      final seeded = await _seed(profile: _profile('mic-a', tag: 'A'));
      addTearDown(seeded.container.dispose);
      final ctrl = seeded.container
          .read(liveMeasurementControllerProvider('proj-mic-1').notifier);
      ctrl.markReady();
      await ctrl.capture();
      expect(
          seeded.container
              .read(liveMeasurementControllerProvider('proj-mic-1'))
              .phase,
          LiveMeasurementPhase.captured);

      await seeded.container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile(
              'proj-mic-1', _profile('mic-b', tag: 'B'));

      await ctrl.accept();

      final state = seeded.container
          .read(liveMeasurementControllerProvider('proj-mic-1'));
      expect(state.phase, LiveMeasurementPhase.ready);
      expect(state.capturedResponse, isNull);
      expect(state.error, isNotNull);

      final project = seeded.container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-mic-1');
      expect(
          project.acousticState.driverChannels
              .firstWhere((c) => c.id == 'ch_tw_l')
              .frdData,
          isNull);
    });

    test('no profile change -> accept succeeds normally', () async {
      final seeded = await _seed(profile: _profile('mic-a', tag: 'A'));
      addTearDown(seeded.container.dispose);
      final ctrl = seeded.container
          .read(liveMeasurementControllerProvider('proj-mic-1').notifier);
      ctrl.markReady();
      await ctrl.capture();
      await ctrl.accept();
      final project = seeded.container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-mic-1');
      expect(
          project.acousticState.driverChannels
              .firstWhere((c) => c.id == 'ch_tw_l')
              .frdData,
          isNotNull);
    });
  });

  group('Room: capture uses exactly the currently selected profile', () {
    test('profile A selected -> capture passes profile A\'s curve', () async {
      final seeded = await _seed(profile: _profile('mic-a', tag: 'A'));
      addTearDown(seeded.container.dispose);
      final ctrl = seeded.container
          .read(roomMeasurementControllerProvider('proj-mic-1').notifier);
      ctrl.markReady();
      await ctrl.capture();
      expect(seeded.fakeMic.lastCalibrationCurve?.checksum,
          _profile('mic-a', tag: 'A').calibrationCurve!.checksum);
    });

    test(
        'stale preview: capture under A, switch to B before Accept -> '
        'accept is blocked and nothing is persisted', () async {
      final seeded = await _seed(profile: _profile('mic-a', tag: 'A'));
      addTearDown(seeded.container.dispose);
      final ctrl = seeded.container
          .read(roomMeasurementControllerProvider('proj-mic-1').notifier);
      ctrl.markReady();
      await ctrl.capture();
      expect(
          seeded.container
              .read(roomMeasurementControllerProvider('proj-mic-1'))
              .phase,
          RoomMeasurementPhaseUi.captured);

      await seeded.container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile(
              'proj-mic-1', _profile('mic-b', tag: 'B'));

      await ctrl.accept();

      final state = seeded.container
          .read(roomMeasurementControllerProvider('proj-mic-1'));
      expect(state.phase, RoomMeasurementPhaseUi.ready);
      expect(state.capturedResponse, isNull);
      expect(state.error, isNotNull);

      final project = seeded.container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-mic-1');
      expect(project.roomState.before.leftSystemFrd, isNull);
    });

    test('no profile change -> accept succeeds normally', () async {
      final seeded = await _seed(profile: _profile('mic-a', tag: 'A'));
      addTearDown(seeded.container.dispose);
      final ctrl = seeded.container
          .read(roomMeasurementControllerProvider('proj-mic-1').notifier);
      ctrl.markReady();
      await ctrl.capture();
      await ctrl.accept();
      final project = seeded.container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-mic-1');
      expect(project.roomState.before.leftSystemFrd, isNotNull);
    });
  });
}
