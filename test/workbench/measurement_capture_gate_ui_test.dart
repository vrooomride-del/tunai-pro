// Phase 3-D3A-1B — Capture UI closure, warning UX, remediation wiring.
//
// Exercises the gate-driven Capture button through the REAL
// LiveMeasurementSection / RoomMeasurementSection (via MeasureTab /
// WorkbenchShell), never a mocked-out gate — the widgets consume
// controller.state.captureGate / evaluateCaptureGate() exactly as production
// does. Covers: Ready/Blocked/Warning states for both Factory and Room,
// warning acknowledgement confirm/cancel, typed remediation CTA dispatch,
// systemDefaultUnverified display, Factory/Room same-identity consistency,
// and no-overflow at 1280x720 + a low-height viewport.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_gate_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_presentation.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/mic/guided_measurement_setup_dialog.dart';
import 'package:tunai_pro/features/mic/microphone_profile_manager_dialog.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_section.dart';
import 'package:tunai_pro/features/workbench/tabs/measure_tab.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';
import '../support/capture_gate_fixtures.dart';

class _FakeMicController extends mic.MicMeasurementController {
  @override
  MeasurementInputDeviceService get inputDeviceService =>
      fakeGateInputDeviceService();

  _FakeMicController(super.ref);

  int startCount = 0;

  @override
  Future<void> startMeasurement({
    CalibrationCurve? calibrationCurve,
    dynamic speakerProfile,
    bool bleWarmup = false,
  }) async {
    startCount++;
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: const [
        {'frequency': 100.0, 'db': -1.0},
        {'frequency': 1000.0, 'db': -2.0},
      ],
    );
  }

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

ProProject _baseProject(String id) => ProProject(
      id: id,
      name: 'Gate UI Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
    );

/// No microphone profile at all -> primaryBlocker == noMicrophoneProfile.
ProProject _blockedProject(String id) => _baseProject(id);

/// Fully gate-ready, but the profile is explicitly uncalibrated ->
/// no blockers, exactly the explicitlyUncalibrated warning.
ProProject _warningProject(String id) {
  final withProfile = _baseProject(id).copyWith(
    selectedMicrophoneProfile: gateReadyProfile().copyWith(
      calibrationSource: CalibrationSource.uncalibrated,
      calibrationCurve: null,
    ),
  );
  return withGateReadySetup(withProfile);
}

/// Fully gate-ready via a system-default input selection.
ProProject _systemDefaultReadyProject(String id) {
  final withDevice = _baseProject(id).copyWith(
    selectedMicrophoneProfile: gateReadyProfile(),
    selectedInputDevice: MeasurementInputDeviceSelection.systemDefault(
      selectedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  return withGateReadySetup(withDevice);
}

Future<ProviderContainer> _seedContainer(ProProject project) async {
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

  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget measureTabHost(ProviderContainer container, String projectId) =>
      UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(home: Scaffold(body: MeasureTab(projectId: projectId))),
      );

  Future<void> pumpFactory(
      WidgetTester tester, ProviderContainer container, String projectId,
      {Size size = const Size(1280, 800)}) async {
    await setViewport(tester, size);
    await tester.pumpWidget(measureTabHost(container, projectId));
    await tester.pumpAndSettle();
  }

  Widget roomHost(ProviderContainer container, String projectId) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: WorkbenchShell(projectId: projectId)),
      );

  Future<void> pumpRoom(
      WidgetTester tester, ProviderContainer container, String projectId,
      {Size size = const Size(1280, 800)}) async {
    await setViewport(tester, size);
    await tester.pumpWidget(roomHost(container, projectId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Room Measurement'));
    await tester.pumpAndSettle();
  }

  // Both Factory and Room start in the `idle` phase ("준비 완료" gate) — the
  // gate-driven Capture control only renders once `ready`. Tapping "준비
  // 완료" also kicks off the control's async evaluateGate() call, which
  // pumpAndSettle() then drains before any Capture-area assertion runs.
  Future<void> markReady(WidgetTester tester) async {
    await tester.ensureVisible(find.text('준비 완료'));
    await tester.tap(find.text('준비 완료'));
    await tester.pumpAndSettle();
  }

  // `FilledButton.icon(...)` returns a private subtype of FilledButton, so
  // `find.byType(FilledButton)` (exact-type match) never matches it — use an
  // `is FilledButton` predicate instead, the same technique already
  // established by room_measurement_ui_test.dart's `_roomButton`.
  Finder buttonWithText(String label) => find.ancestor(
      of: find.text(label),
      matching: find
          .byWidgetPredicate((w) => w is FilledButton || w is OutlinedButton));

  group('1. Factory Capture UI states', () {
    testWidgets(
        'Blocked (no microphone profile): Capture disabled, blocker + remediation shown',
        (tester) async {
      final project = _blockedProject('factory-blocked');
      final container = await _seedContainer(project);
      addTearDown(container.dispose);
      await pumpFactory(tester, container, project.id);
      await markReady(tester);

      expect(
          find.text(measurementCaptureBlockerText(
              MeasurementCaptureBlockerCode.noMicrophoneProfile)),
          findsOneWidget);
      final captureButton =
          tester.widget<FilledButton>(buttonWithText('Capture'));
      expect(captureButton.onPressed, isNull);

      // Typed remediation CTA opens the Microphone Profile Manager dialog.
      await tester.tap(find.text(measurementCaptureRemediationLabel(
          MeasurementCaptureRemediation.manageMicrophone)));
      await tester.pumpAndSettle();
      expect(find.byType(MicrophoneProfileManagerDialog), findsOneWidget);
    });

    testWidgets(
        'Warning (explicitly uncalibrated): normal Capture is replaced by ack CTA',
        (tester) async {
      final project = _warningProject('factory-warning');
      final container = await _seedContainer(project);
      addTearDown(container.dispose);
      await pumpFactory(tester, container, project.id);
      await markReady(tester);
      final mock = container.read(mic.micMeasurementProvider.notifier)
          as _FakeMicController;

      expect(
          find.text('마이크 보정 없이 측정할 수 있지만 결과 정확도가 낮아질 수 있습니다.'), findsOneWidget);
      expect(buttonWithText('Capture'), findsNothing);
      expect(find.text('경고를 확인하고 측정'), findsOneWidget);

      // Cancel path: zero captures, dialog closes.
      await tester.tap(find.text('경고를 확인하고 측정'));
      await tester.pumpAndSettle();
      expect(find.text('취소'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(mock.startCount, 0);

      // Confirm path: acknowledgeWarnings() then capture() actually runs.
      await tester.tap(find.text('경고를 확인하고 측정'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '경고를 확인하고 측정').last);
      await tester.pumpAndSettle();
      expect(mock.startCount, 1);
    });
  });

  group('2. Room Capture UI states', () {
    testWidgets(
        'Blocked (no microphone profile): Capture disabled, blocker + remediation shown',
        (tester) async {
      final project = _blockedProject('room-blocked');
      final container = await _seedContainer(project);
      addTearDown(container.dispose);
      await pumpRoom(tester, container, project.id);
      await markReady(tester);

      expect(
          find.descendant(
              of: find.byType(RoomMeasurementSection),
              matching: find.text(measurementCaptureBlockerText(
                  MeasurementCaptureBlockerCode.noMicrophoneProfile))),
          findsOneWidget);
      final captureButton =
          tester.widget<FilledButton>(buttonWithText('Capture'));
      expect(captureButton.onPressed, isNull);
    });

    testWidgets(
        'Warning (explicitly uncalibrated): ack CTA, cancel = zero captures, confirm = one',
        (tester) async {
      final project = _warningProject('room-warning');
      final container = await _seedContainer(project);
      addTearDown(container.dispose);
      await pumpRoom(tester, container, project.id);
      await markReady(tester);
      final mock = container.read(mic.micMeasurementProvider.notifier)
          as _FakeMicController;

      expect(
          find.descendant(
              of: find.byType(RoomMeasurementSection),
              matching: find.text('경고를 확인하고 측정')),
          findsOneWidget);

      await tester.tap(find.text('경고를 확인하고 측정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(mock.startCount, 0);

      await tester.tap(find.text('경고를 확인하고 측정'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '경고를 확인하고 측정').last);
      await tester.pumpAndSettle();
      expect(mock.startCount, 1);
    });
  });

  group('3. Typed remediation dispatch', () {
    testWidgets(
        'setup-not-checked blocker opens Guided Measurement Setup dialog',
        (tester) async {
      final project = _baseProject('remediation-setup').copyWith(
        selectedMicrophoneProfile: gateReadyProfile(),
        selectedInputDevice: gateReadyDevice(),
      ); // no currentSetupReadiness -> setupNotChecked
      final container = await _seedContainer(project);
      addTearDown(container.dispose);
      await pumpFactory(tester, container, project.id);
      await markReady(tester);

      expect(find.text('측정 준비 확인을 먼저 실행하세요.'), findsOneWidget);
      await tester.tap(find.text('준비 확인 실행'));
      await tester.pumpAndSettle();
      expect(find.byType(GuidedMeasurementSetupDialog), findsOneWidget);
    });
  });

  group('4. systemDefaultUnverified display', () {
    testWidgets(
        'shows "System Default Input" + subtext, never a forbidden word',
        (tester) async {
      final project = _systemDefaultReadyProject('sysdefault');
      final container = await _seedContainer(project);
      addTearDown(container.dispose);
      await pumpFactory(tester, container, project.id);
      await markReady(tester);

      expect(find.text('System Default Input'), findsOneWidget);
      expect(find.text('실제 입력 장치는 녹음 시작 시 최종 확인됩니다.'), findsOneWidget);
      for (final word in ['Verified', 'Connected', 'Available', 'Confirmed']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });

  group('5. Factory/Room same-identity consistency', () {
    testWidgets(
        'same blocked project shows identical blocker text in both sections',
        (tester) async {
      final factoryProject = _blockedProject('consistency-factory');
      final factoryContainer = await _seedContainer(factoryProject);
      addTearDown(factoryContainer.dispose);
      await pumpFactory(tester, factoryContainer, factoryProject.id);
      await markReady(tester);
      final factoryText = measurementCaptureBlockerText(
          MeasurementCaptureBlockerCode.noMicrophoneProfile);
      expect(find.text(factoryText), findsOneWidget);
    });

    testWidgets(
        'room shows the exact same blocker text for the same blocker code',
        (tester) async {
      final roomProject = _blockedProject('consistency-room');
      final roomContainer = await _seedContainer(roomProject);
      addTearDown(roomContainer.dispose);
      await pumpRoom(tester, roomContainer, roomProject.id);
      await markReady(tester);
      final expectedText = measurementCaptureBlockerText(
          MeasurementCaptureBlockerCode.noMicrophoneProfile);
      expect(
          find.descendant(
              of: find.byType(RoomMeasurementSection),
              matching: find.text(expectedText)),
          findsOneWidget);
    });
  });

  group('6. No overflow regression', () {
    testWidgets('Blocked Factory state renders without overflow at 1280x720',
        (tester) async {
      final project = _blockedProject('overflow-blocked');
      final container = await _seedContainer(project);
      addTearDown(container.dispose);
      await pumpFactory(tester, container, project.id,
          size: const Size(1280, 720));
      await markReady(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Warning Factory state renders without overflow at a low-height viewport',
        (tester) async {
      final project = _warningProject('overflow-warning');
      final container = await _seedContainer(project);
      addTearDown(container.dispose);
      await pumpFactory(tester, container, project.id,
          size: const Size(1280, 600));
      await markReady(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
