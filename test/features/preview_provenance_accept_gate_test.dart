// Phase 3-D3A-2 — Preview Provenance + Actual Capture WAV Metadata Accept
// Gate: Factory/Room integration coverage.
//
// Exercises the REAL LiveMeasurementController/RoomMeasurementController
// capture()/accept() paths (never a mocked gate) to prove:
//   - a valid, unchanged capture still saves normally
//   - every identity dimension that changes between capture and accept
//     blocks the save entirely (zero writes)
//   - an actual WAV format that doesn't match the quality policy (44.1kHz,
//     or stereo) blocks the save even though every OTHER identity field is
//     unchanged
//   - a blocked accept clears the stale preview and surfaces an error,
//     rather than leaving a misleading "still previewing" state

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/live_measurement_controller.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';
import '../support/capture_gate_fixtures.dart';

class _FakeMicController extends mic.MicMeasurementController {
  int fakeActualSampleRate = mic.MicMeasurementController.sampleRate;
  int fakeActualChannelCount = 1;

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
      actualSampleRate: fakeActualSampleRate,
      actualChannelCount: fakeActualChannelCount,
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
      actualSampleRate: fakeActualSampleRate,
      actualChannelCount: fakeActualChannelCount,
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

ProProject _project({String id = 'proj-provgate-1'}) => withGateReadySetup(
      ProProject(
        id: id,
        name: 'Provenance Gate Test',
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
      ),
    );

Future<ProviderContainer> _seed(ProProject project) async {
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) => _FakeMicController(ref)),
  ]);
  await container.read(proProjectStoreProvider.notifier).addProject(project);
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

  group('Factory: valid capture', () {
    test('unchanged state -> Accept saves FRD', () async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-provgate-1').notifier);

      ctrl.markReady();
      await ctrl.capture();
      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-1');
      expect(saved.acousticState.driverChannels.first.frdData, isNotNull);
    });
  });

  group('Factory: identity changes between capture and accept -> save 0', () {
    test('profile change -> save 0, error surfaced, preview cleared', () async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-provgate-1').notifier);

      ctrl.markReady();
      await ctrl.capture();

      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile(
              'proj-provgate-1', gateReadyProfile().copyWith(model: 'Other'));

      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-1');
      expect(saved.acousticState.driverChannels.first.frdData, isNull);
      final state =
          container.read(liveMeasurementControllerProvider('proj-provgate-1'));
      expect(state.phase, LiveMeasurementPhase.ready);
      expect(state.capturedResponse, isNull);
      expect(state.error, isNotNull);
    });

    test('orientation change -> save 0', () async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-provgate-1').notifier);

      ctrl.markReady();
      await ctrl.capture();

      final baseCurve = gateReadyCalibrationCurve();
      final reoriented = gateReadyProfile().copyWith(
          calibrationCurve: CalibrationCurve(
        points: baseCurve.points,
        angle: CalibrationAngle.ninetyDegree,
        validMinFrequencyHz: baseCurve.validMinFrequencyHz,
        validMaxFrequencyHz: baseCurve.validMaxFrequencyHz,
        sourceIdentity: baseCurve.sourceIdentity,
        checksum: baseCurve.checksum,
      ));
      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-provgate-1', reoriented);

      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-1');
      expect(saved.acousticState.driverChannels.first.frdData, isNull);
    });

    test('input device change -> save 0', () async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-provgate-1').notifier);

      ctrl.markReady();
      await ctrl.capture();

      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedInputDevice(
              'proj-provgate-1',
              MeasurementInputDeviceSelection.specificDevice(
                deviceId: 'a-different-device',
                labelSnapshot: 'Different Mic',
                selectedAt: DateTime.utc(2026, 1, 1),
              ));

      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-1');
      expect(saved.acousticState.driverChannels.first.frdData, isNull);
    });

    test('setup generation change (re-run setup check) -> save 0', () async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-provgate-1').notifier);

      ctrl.markReady();
      await ctrl.capture();

      final projectNow = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-1');
      await refreshGateReadiness(
          container.read(proProjectStoreProvider.notifier), projectNow);

      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-1');
      expect(saved.acousticState.driverChannels.first.frdData, isNull);
    });
  });

  group('Factory: actual WAV format mismatch -> save 0 regardless of identity',
      () {
    test('actual 44.1kHz capture blocks Accept', () async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      final fake = container.read(mic.micMeasurementProvider.notifier)
          as _FakeMicController;
      fake.fakeActualSampleRate = 44100;
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-provgate-1').notifier);

      ctrl.markReady();
      await ctrl.capture();
      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-1');
      expect(saved.acousticState.driverChannels.first.frdData, isNull);
      final state =
          container.read(liveMeasurementControllerProvider('proj-provgate-1'));
      expect(state.error, isNotNull);
    });

    test('actual stereo capture blocks Accept', () async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      final fake = container.read(mic.micMeasurementProvider.notifier)
          as _FakeMicController;
      fake.fakeActualChannelCount = 2;
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-provgate-1').notifier);

      ctrl.markReady();
      await ctrl.capture();
      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-1');
      expect(saved.acousticState.driverChannels.first.frdData, isNull);
    });

    test('actual 48000/1 capture passes -> Accept saves normally', () async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      final fake = container.read(mic.micMeasurementProvider.notifier)
          as _FakeMicController;
      fake.fakeActualSampleRate = 48000;
      fake.fakeActualChannelCount = 1;
      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-provgate-1').notifier);

      ctrl.markReady();
      await ctrl.capture();
      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-1');
      expect(saved.acousticState.driverChannels.first.frdData, isNotNull);
    });
  });

  group('Room: valid capture', () {
    test('unchanged state -> Accept saves roomState', () async {
      final container = await _seed(_project(id: 'proj-provgate-room-1'));
      addTearDown(container.dispose);
      final ctrl = container.read(
          roomMeasurementControllerProvider('proj-provgate-room-1').notifier);

      ctrl.markReady();
      await ctrl.capture();
      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-room-1');
      expect(saved.roomState.before.readyCount, 1);
    });
  });

  group('Room: identity changes between capture and accept -> save 0', () {
    test('profile change -> readyCount 0, roomState untouched', () async {
      final container = await _seed(_project(id: 'proj-provgate-room-2'));
      addTearDown(container.dispose);
      final ctrl = container.read(
          roomMeasurementControllerProvider('proj-provgate-room-2').notifier);

      ctrl.markReady();
      await ctrl.capture();

      await container
          .read(proProjectStoreProvider.notifier)
          .updateSelectedMicrophoneProfile('proj-provgate-room-2',
              gateReadyProfile().copyWith(model: 'Other'));

      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-room-2');
      expect(saved.roomState.before.readyCount, 0);
      final state = container
          .read(roomMeasurementControllerProvider('proj-provgate-room-2'));
      expect(state.phase, RoomMeasurementPhaseUi.ready);
      expect(state.capturedResponse, isNull);
      expect(state.closedLoopResult, isNull);
    });

    test('setup generation change -> readyCount 0', () async {
      final container = await _seed(_project(id: 'proj-provgate-room-3'));
      addTearDown(container.dispose);
      final ctrl = container.read(
          roomMeasurementControllerProvider('proj-provgate-room-3').notifier);

      ctrl.markReady();
      await ctrl.capture();

      final projectNow = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-room-3');
      await refreshGateReadiness(
          container.read(proProjectStoreProvider.notifier), projectNow);

      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-room-3');
      expect(saved.roomState.before.readyCount, 0);
    });
  });

  group('Room: actual WAV format mismatch -> save 0', () {
    test('actual 44.1kHz capture blocks Accept, readyCount stays 0', () async {
      final container = await _seed(_project(id: 'proj-provgate-room-4'));
      addTearDown(container.dispose);
      final fake = container.read(mic.micMeasurementProvider.notifier)
          as _FakeMicController;
      fake.fakeActualSampleRate = 44100;
      final ctrl = container.read(
          roomMeasurementControllerProvider('proj-provgate-room-4').notifier);

      ctrl.markReady();
      await ctrl.capture();
      await ctrl.accept();

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-provgate-room-4');
      expect(saved.roomState.before.readyCount, 0);
    });
  });
}
