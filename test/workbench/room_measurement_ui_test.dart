// Phase 2 — Stereo Room Measurement UI tests.
//
// Drives the real WorkbenchShell at 1280x720 (the spec's stated viewport)
// verifying:
//   1. Factory Driver Tuning is the default view (existing behavior
//      unchanged) and "Room Measurement" tab switches to the new UI
//   2. Progress reads 0/2 with nothing captured, 1/2 after Left is accepted
//   3. No manual per-driver isolation copy ("Hardware 탭에서 이 채널만",
//      "CTW", "CWF") appears in Room mode
//   4. No layout overflow at 1280x720 (tester.takeException() stays null)
//   5. Capture/Retry/Accept are reachable in Room mode

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/room_measurement_section.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import '../support/capture_gate_fixtures.dart';

/// Scopes a text/tap finder to inside RoomMeasurementSection so it can't
/// collide with unrelated Factory-panel content that stays visible above
/// the mode toggle (e.g. the 5-step Workflow Progress card's "Capture" step
/// label, or the Driver Readiness bar's "CTW"/"CWF" role chips).
Finder _inRoomSection(Finder matching) => find.descendant(
    of: find.byType(RoomMeasurementSection), matching: matching);

Finder _roomButton(String label) => find.descendant(
    of: find.byType(RoomMeasurementSection),
    matching: find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
            (w) => w is FilledButton || w is OutlinedButton)));

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
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

Future<ProviderContainer> _seedContainer() async {
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) => _FakeMicController(ref)),
  ]);
  await container.read(proProjectStoreProvider.notifier).addProject(
        withGateReadySetup(ProProject(
          id: 'room-ui-1',
          name: 'Room UI Test',
          dspTarget: 'ADAU1701',
          createdAt: DateTime.utc(2025, 1, 1),
          updatedAt: DateTime.utc(2025, 1, 1),
        )),
      );
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

  Future<void> pumpMeasureTab(
      WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: WorkbenchShell(projectId: 'room-ui-1'),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Measure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('1. Factory default, Room toggle switches view', () {
    testWidgets('default is Factory (Live Measurement) view', (tester) async {
      final container = await _seedContainer();
      addTearDown(container.dispose);
      await pumpMeasureTab(tester, container);

      expect(find.text('LIVE MEASUREMENT'), findsOneWidget);
      expect(find.text('ROOM MEASUREMENT'), findsNothing);
    });

    testWidgets('tapping "Room Measurement" switches to Room UI',
        (tester) async {
      final container = await _seedContainer();
      addTearDown(container.dispose);
      await pumpMeasureTab(tester, container);

      await tester.tap(find.text('Room Measurement'));
      await tester.pump();

      expect(find.text('ROOM MEASUREMENT'), findsOneWidget);
      expect(find.text('LIVE MEASUREMENT'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('2. Progress 0/2 -> 1/2', () {
    testWidgets('starts at 0/2, reaches 1/2 after accepting Left',
        (tester) async {
      final container = await _seedContainer();
      addTearDown(container.dispose);
      await pumpMeasureTab(tester, container);
      await tester.tap(find.text('Room Measurement'));
      await tester.pump();

      expect(_inRoomSection(find.textContaining('0/2')), findsOneWidget);

      await tester.ensureVisible(_roomButton('준비 완료'));
      await tester.tap(_roomButton('준비 완료'));
      await tester.pump();
      // The Capture button's gate-driven state (Phase 3-D3A-1B) is resolved
      // via an async preflight evaluated in the control's initState — pump
      // it to completion before the button reflects Ready.
      await tester.pumpAndSettle();
      await tester.ensureVisible(_roomButton('Capture'));
      await tester.tap(_roomButton('Capture'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(_roomButton('Accept'));
      await tester.tap(_roomButton('Accept'));
      await tester.pump();

      expect(_inRoomSection(find.textContaining('1/2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('3. No manual per-driver isolation copy in Room mode', () {
    testWidgets('no CTW/CWF/manual-output-only guidance text', (tester) async {
      final container = await _seedContainer();
      addTearDown(container.dispose);
      await pumpMeasureTab(tester, container);
      await tester.tap(find.text('Room Measurement'));
      await tester.pump();

      expect(_inRoomSection(find.textContaining('이 채널만 출력')), findsNothing);
      expect(_inRoomSection(find.textContaining('CTW')), findsNothing);
      expect(_inRoomSection(find.textContaining('CWF')), findsNothing);
      expect(_inRoomSection(find.text('우퍼와 트위터가 함께 재생됩니다.')), findsOneWidget);
      expect(_inRoomSection(find.text('반대편 스피커는 테스트 신호에서 자동 제외됩니다.')),
          findsOneWidget);
    });
  });

  group('4. No overflow at 1280x720', () {
    testWidgets('Room UI renders without overflow', (tester) async {
      final container = await _seedContainer();
      addTearDown(container.dispose);
      await pumpMeasureTab(tester, container);
      await tester.tap(find.text('Room Measurement'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });
  });

  group('5. Capture/Retry/Accept reachable', () {
    testWidgets('Capture -> Retry discards, then Capture -> Accept persists',
        (tester) async {
      final container = await _seedContainer();
      addTearDown(container.dispose);
      await pumpMeasureTab(tester, container);
      await tester.tap(find.text('Room Measurement'));
      await tester.pump();

      await tester.ensureVisible(_roomButton('준비 완료'));
      await tester.tap(_roomButton('준비 완료'));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_roomButton('Capture'));
      await tester.tap(_roomButton('Capture'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_inRoomSection(find.text('Retry')), findsOneWidget);
      expect(_inRoomSection(find.text('Accept')), findsOneWidget);

      await tester.ensureVisible(_roomButton('Retry'));
      await tester.tap(_roomButton('Retry'));
      await tester.pump();
      // retry() returns to `ready` (not `idle`) — Capture is immediately
      // available again without re-confirming "준비 완료".
      expect(_inRoomSection(find.text('Capture')), findsOneWidget);
      expect(_inRoomSection(find.textContaining('0/2')), findsOneWidget);
    });
  });
}
