// Phase 3-D3A-3 §12 — After Capture must use the SAME Phase 3-D3A-2
// provenance/Accept gate as Before. Dual-gate PASS at capture time is not a
// bypass for the Accept-time provenance check: a valid WAV still accepts,
// but a wrong actual format or an identity change after capture still
// blocks — exactly like Before.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/room_auto_peq_controller.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import '../support/capture_gate_fixtures.dart';

class _FakeMicController extends mic.MicMeasurementController {
  int fakeActualSampleRate = mic.MicMeasurementController.sampleRate;
  int fakeActualChannelCount = 1;

  @override
  MeasurementInputDeviceService get inputDeviceService =>
      fakeGateInputDeviceService();

  _FakeMicController(super.ref);

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
      actualSampleRate: fakeActualSampleRate,
      actualChannelCount: fakeActualChannelCount,
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

ProProject _project({String id = 'room-after-prov-1'}) =>
    withGateReadySetup(ProProject(
      id: id,
      name: 'Room After Provenance Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      tuningState: TuningProjectState(peqChannels: const []),
    ));

HardwareWriteExecutionResult _verifiedResultFor(String packageId) =>
    HardwareWriteExecutionResult(
      planId: '$packageId@2026-01-01T00:00:00.000Z',
      executed: true,
      rejectionReason: null,
      outcomes: [
        const HardwareWriteOpOutcome(
          op: HardwareWriteOp(
            channelId: 'ch_wf_l',
            parameterKind: HardwareParamKind.peqGain,
            bandIndex: 0,
            targetValue: -1.0,
            verification: HardwareParamVerification.captureProven,
            writable: true,
            reason: 'test',
          ),
          status: HardwareWriteOpStatus.written,
          report: null,
          message: 'ok',
        ),
      ],
    );

class _Harness {
  final ProviderContainer container;
  final _FakeMicController fakeMic;
  final String projectId;
  const _Harness(this.container, this.fakeMic, this.projectId);

  RoomMeasurementController get ctrl =>
      container.read(roomMeasurementControllerProvider(projectId).notifier);
  RoomMeasurementState get state =>
      container.read(roomMeasurementControllerProvider(projectId));
  ProProject get project => container
      .read(proProjectStoreProvider)
      .projects
      .firstWhere((p) => p.id == projectId);

  void authorizeHardware({String packageId = 'approved-room-pkg'}) {
    container.read(roomAutoPeqControllerProvider(projectId).notifier).state =
        RoomAutoPeqState(approvedPackageId: packageId);
    container.read(lastHardwareWriteResultProvider.notifier).state =
        _verifiedResultFor(packageId);
  }

  Future<void> goAfter() async {
    ctrl.setMode(RoomMeasurementPhase.after);
    ctrl.markReady();
  }
}

Future<_Harness> _buildHarness(ProProject project) async {
  late _FakeMicController fakeMicInstance;
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) {
      fakeMicInstance = _FakeMicController(ref);
      return fakeMicInstance;
    }),
  ]);
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  container.read(mic.micMeasurementProvider);
  return _Harness(container, fakeMicInstance, project.id);
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

  test('dual gate PASS + valid WAV -> Accept persists to roomState.after',
      () async {
    final h = await _buildHarness(_project());
    addTearDown(h.container.dispose);
    h.authorizeHardware();
    await h.goAfter();

    await h.ctrl.capture();
    await h.ctrl.accept();

    expect(h.project.roomState.after.readyCount, 1);
  });

  test('dual gate PASS + actual 44.1kHz WAV -> Accept blocked, save 0',
      () async {
    final h = await _buildHarness(_project());
    addTearDown(h.container.dispose);
    h.authorizeHardware();
    h.fakeMic.fakeActualSampleRate = 44100;
    await h.goAfter();

    await h.ctrl.capture();
    await h.ctrl.accept();

    expect(h.project.roomState.after.readyCount, 0);
    expect(h.state.error, isNotNull);
  });

  test('dual gate PASS + actual stereo WAV -> Accept blocked, save 0',
      () async {
    final h = await _buildHarness(_project());
    addTearDown(h.container.dispose);
    h.authorizeHardware();
    h.fakeMic.fakeActualChannelCount = 2;
    await h.goAfter();

    await h.ctrl.capture();
    await h.ctrl.accept();

    expect(h.project.roomState.after.readyCount, 0);
  });

  test(
      'profile changed after capture (dual gate still would have passed at '
      'capture time) -> Accept blocked, save 0', () async {
    final h = await _buildHarness(_project());
    addTearDown(h.container.dispose);
    h.authorizeHardware();
    await h.goAfter();

    await h.ctrl.capture();

    await h.container
        .read(proProjectStoreProvider.notifier)
        .updateSelectedMicrophoneProfile(
            h.projectId, gateReadyProfile().copyWith(model: 'Other'));

    await h.ctrl.accept();

    expect(h.project.roomState.after.readyCount, 0);
  });

  test('setup generation changed after capture -> Accept blocked, save 0',
      () async {
    final h = await _buildHarness(_project());
    addTearDown(h.container.dispose);
    h.authorizeHardware();
    await h.goAfter();

    await h.ctrl.capture();

    await refreshGateReadiness(
        h.container.read(proProjectStoreProvider.notifier), h.project);

    await h.ctrl.accept();

    expect(h.project.roomState.after.readyCount, 0);
  });
}
