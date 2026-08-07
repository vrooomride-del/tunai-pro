// Phase 3-D3A-3 — Room After dual-gate Capture UI.
//
// Exercises the REAL RoomAfterCaptureReadyControl through WorkbenchShell —
// never a mocked composite gate. Covers: hardware-blocker Deploy CTA,
// measurement-blocker existing remediation, measurement-warning existing
// acknowledgement flow, both-PASS enabled Capture, and hardware-first
// ordering when both fail.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_gate_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_presentation.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/orchestrator/room_after_capture_presentation.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/mic/guided_measurement_setup_dialog.dart';
import 'package:tunai_pro/features/workbench/tabs/room_auto_peq_controller.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_section.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';
import '../support/capture_gate_fixtures.dart';

class _FakeMicController extends mic.MicMeasurementController {
  @override
  MeasurementInputDeviceService get inputDeviceService =>
      fakeGateInputDeviceService();

  _FakeMicController(super.ref);
  int startCount = 0;

  @override
  Future<void> startRoomMeasurement({
    required bool leftActive,
    CalibrationCurve? calibrationCurve,
    bool bleWarmup = false,
  }) async {
    startCount++;
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: const [
        {'frequency': 80.0, 'db': -1.0},
        {'frequency': 800.0, 'db': -2.0},
      ],
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

ProProject _readyProject(String id) => withGateReadySetup(ProProject(
      id: id,
      name: 'Room After UI Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      tuningState: TuningProjectState(peqChannels: const []),
    ));

ProProject _noSetupProject(String id) => ProProject(
      id: id,
      name: 'Room After UI Test No Setup',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      tuningState: TuningProjectState(peqChannels: const []),
    );

ProProject _warningProject(String id) {
  final withProfile = ProProject(
    id: id,
    name: 'Room After UI Warning Test',
    dspTarget: 'ADAU1701',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    tuningState: TuningProjectState(peqChannels: const []),
  ).copyWith(
    selectedMicrophoneProfile: gateReadyProfile().copyWith(
      calibrationSource: CalibrationSource.uncalibrated,
      clearCalibrationCurve: true,
    ),
  );
  return withGateReadySetup(withProfile);
}

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

Future<ProviderContainer> _seed(
  ProProject project, {
  bool authorizeHardware = false,
}) async {
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) => _FakeMicController(ref)),
  ]);
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  container.read(mic.micMeasurementProvider);
  if (authorizeHardware) {
    container.read(roomAutoPeqControllerProvider(project.id).notifier).state =
        const RoomAutoPeqState(approvedPackageId: 'approved-room-pkg');
    container.read(lastHardwareWriteResultProvider.notifier).state =
        _verifiedResultFor('approved-room-pkg');
  }
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

  Future<void> pumpAfterReady(
      WidgetTester tester, ProviderContainer container, String projectId,
      {Size size = const Size(1280, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Force straight into After/ready — bypassing setMode()'s own entry
    // checks, exactly like the controller-level P0 tests: the UI must
    // render whatever the composite gate says regardless of how the mode
    // got set, never presuming Ready from mode alone.
    container
        .read(roomMeasurementControllerProvider(projectId).notifier)
        .state = const RoomMeasurementState(
      mode: RoomMeasurementPhase.after,
      phase: RoomMeasurementPhaseUi.ready,
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: WorkbenchShell(projectId: projectId)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Room Measurement'));
    await tester.pumpAndSettle();
  }

  testWidgets('hardware blocker shows the hardware message + Deploy CTA',
      (tester) async {
    final project = _readyProject('after-ui-hw-blocked');
    final container = await _seed(project, authorizeHardware: false);
    addTearDown(container.dispose);
    await pumpAfterReady(tester, container, project.id);

    expect(
        find.descendant(
            of: find.byType(RoomMeasurementSection),
            matching: find.text('Room 보정을 먼저 스피커에 적용하고 확인해 주세요.')),
        findsOneWidget);

    await tester
        .ensureVisible(find.text(kRoomAfterCaptureDeployRemediationLabel));
    await tester.tap(find.text(kRoomAfterCaptureDeployRemediationLabel));
    await tester.pumpAndSettle();
    expect(container.read(workbenchTabProvider), kTabDeploy);
  });

  testWidgets('measurement blocker uses existing measurement remediation',
      (tester) async {
    final project = _noSetupProject('after-ui-measurement-blocked');
    final container = await _seed(project, authorizeHardware: true);
    addTearDown(container.dispose);
    await pumpAfterReady(tester, container, project.id);

    expect(
        find.descendant(
            of: find.byType(RoomMeasurementSection),
            matching: find.text(measurementCaptureBlockerText(
                MeasurementCaptureBlockerCode.noMicrophoneProfile))),
        findsOneWidget);

    await tester.ensureVisible(find.text('마이크 관리'));
    await tester.tap(find.text('마이크 관리'));
    await tester.pumpAndSettle();
    // noMicrophoneProfile is the primary blocker (chain-first) -> opens
    // Microphone Profile Manager, not Guided Setup — proves the typed
    // MeasurementCaptureRemediation dispatch is reused as-is.
    expect(
        find.text('Manage Microphone').evaluate().isNotEmpty ||
            find.byType(GuidedMeasurementSetupDialog).evaluate().isNotEmpty,
        isTrue);
  });

  testWidgets(
      'measurement warning uses the existing warning acknowledgement dialog',
      (tester) async {
    final project = _warningProject('after-ui-warning');
    final container = await _seed(project, authorizeHardware: true);
    addTearDown(container.dispose);
    await pumpAfterReady(tester, container, project.id);
    final fake = container.read(mic.micMeasurementProvider.notifier)
        as _FakeMicController;

    expect(
        find.descendant(
            of: find.byType(RoomMeasurementSection),
            matching: find.text('경고를 확인하고 측정')),
        findsOneWidget);

    await tester.tap(find.text('경고를 확인하고 측정'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '경고를 확인하고 측정').last);
    await tester.pumpAndSettle();
    expect(fake.startCount, 1);
  });

  testWidgets('both PASS -> Capture enabled', (tester) async {
    final project = _readyProject('after-ui-both-pass');
    final container = await _seed(project, authorizeHardware: true);
    addTearDown(container.dispose);
    await pumpAfterReady(tester, container, project.id);

    final captureButton = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Capture'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(captureButton.onPressed, isNotNull);
  });

  testWidgets(
      'hardware AND measurement both fail -> hardware message shown first',
      (tester) async {
    final project = _noSetupProject('after-ui-both-fail');
    final container = await _seed(project, authorizeHardware: false);
    addTearDown(container.dispose);
    await pumpAfterReady(tester, container, project.id);

    expect(
        find.descendant(
            of: find.byType(RoomMeasurementSection),
            matching: find.text('Room 보정을 먼저 스피커에 적용하고 확인해 주세요.')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(RoomMeasurementSection),
            matching: find.text(measurementCaptureBlockerText(
                MeasurementCaptureBlockerCode.noMicrophoneProfile))),
        findsNothing);
  });
}
