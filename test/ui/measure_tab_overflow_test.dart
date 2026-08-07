// Measure tab bottom RenderFlex overflow — smoke-test regression guard.
//
// Bug: on a ~1360x1080 Mac window, the Measure tab's fixed header cards
// (orientation bar, workflow progress, driver readiness, Live Measurement)
// plus the session list/detail row could together exceed the height
// WorkbenchShell hands the tab (no scrolling, a vertical Expanded(Row(...))
// as the last Column child) -> "BOTTOM OVERFLOWED BY 55 PIXELS" right below
// the Live Measurement card, with the Capture/Retry/Accept controls and
// session panels below it inaccessible.
//
// Fix: MeasureTab's body is now LayoutBuilder + SingleChildScrollView +
// ConstrainedBox(minHeight:) with the tab-level scroll owning all overflow;
// the former vertical Expanded(Row(...)) is now IntrinsicHeight(Row(...))
// (Expanded still used, but only horizontally, inside that Row), and
// _SessionListPanel's internal ListView.builder is shrinkWrap +
// NeverScrollableScrollPhysics so it no longer needs a bounded height either.
//
// This file checks, at three real small-Mac-window sizes and across the
// Live Measurement Before / captured(preview) / 4-of-4-complete states, that
// no overflow (or any other) exception is thrown, and that the
// Capture/Retry/Accept controls remain reachable by scrolling.

import 'package:flutter/material.dart';
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
import 'package:tunai_pro/features/workbench/tabs/measure_tab.dart';

// ── Fixtures (same shape as live_measurement_controller_test.dart /
//    release_flow_integration_test.dart) ────────────────────────────────────

DriverChannel _channel(String id) => DriverChannel(
      id: id,
      name: id,
      role: id.contains('tw') ? DriverRole.tweeter : DriverRole.woofer,
      side: id.endsWith('l') ? DriverSide.left : DriverSide.right,
    );

ProProject _project({String id = 'proj-overflow'}) => ProProject(
      id: id,
      name: 'Overflow Test Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      acousticState: MeasurementProjectState(driverChannels: [
        _channel('ch_tw_l'),
        _channel('ch_wf_l'),
        _channel('ch_tw_r'),
        _channel('ch_wf_r'),
      ]),
      tuningState: TuningProjectState(peqChannels: []),
    );

// _FakeMicController: same technique as live_measurement_controller_test.dart
// -- MicMeasurementController's real superclass touches record/just_audio
// platform channels unconditionally, which have no handler in a plain test
// host, so startMeasurement is fully overridden and dispose() is a no-op.
class _FakeMicController extends mic.MicMeasurementController {
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
        {'frequency': 100.0, 'db': -1.0},
        {'frequency': 1000.0, 'db': -2.0},
        {'frequency': 10000.0, 'db': -1.5},
      ],
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

Widget _measureTab(ProviderContainer container, String projectId) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: MeasureTab(projectId: projectId)),
      ),
    );

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

  Future<ProviderContainer> seededContainer() async {
    final container = ProviderContainer(overrides: [
      mic.micMeasurementProvider.overrideWith((ref) => _FakeMicController(ref)),
    ]);
    await container
        .read(proProjectStoreProvider.notifier)
        .addProject(_project());
    return container;
  }

  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  const sizes = [
    Size(1280, 720),
    Size(1280, 800),
    Size(1440, 900),
  ];

  group('1. Live Measurement "Before" state renders with no overflow', () {
    for (final size in sizes) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await setViewport(tester, size);
        final container = await seededContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_measureTab(container, 'proj-overflow'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'Before state must not overflow at '
                '${size.width.toInt()}x${size.height.toInt()}');
      });
    }
  });

  group('2. Live Measurement "captured" (preview) state — 1280x720', () {
    testWidgets(
        'no overflow, and Retry/Accept are reachable and tappable after scroll',
        (tester) async {
      await setViewport(tester, const Size(1280, 720));
      final container = await seededContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_measureTab(container, 'proj-overflow'));
      await tester.pumpAndSettle();

      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-overflow').notifier);
      ctrl.markReady();
      await ctrl.capture();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'captured/preview state must not overflow');
      expect(
          container
              .read(liveMeasurementControllerProvider('proj-overflow'))
              .phase,
          LiveMeasurementPhase.captured);

      final retry = find.widgetWithText(OutlinedButton, 'Retry');
      final accept = find.widgetWithText(FilledButton, 'Accept');
      expect(retry, findsOneWidget);
      expect(accept, findsOneWidget);

      await tester.ensureVisible(accept);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Accept must be tappable post-scroll with no overflow');
    });
  });

  group('3. Live Measurement 4/4 complete state — 1280x720', () {
    testWidgets(
        'no overflow, and the next-step CTA is reachable and tappable after '
        'scroll', (tester) async {
      await setViewport(tester, const Size(1280, 720));
      final container = await seededContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_measureTab(container, 'proj-overflow'));
      await tester.pumpAndSettle();

      final ctrl = container
          .read(liveMeasurementControllerProvider('proj-overflow').notifier);
      for (var i = 0; i < 4; i++) {
        ctrl.markReady();
        await ctrl.capture();
        await ctrl.accept();
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: '4/4-complete state must not overflow');

      // OutlinedButton.icon() builds a private OutlinedButton subclass, so
      // find.widgetWithText(OutlinedButton, ...) (exact-type match) would
      // miss it -- match on the label text itself instead.
      final nextCta = find.text('Auto PEQ로 이동');
      expect(nextCta, findsOneWidget);
      await tester.ensureVisible(nextCta);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(nextCta);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'the next-step CTA must be tappable post-scroll with no '
              'overflow');
    });
  });

  group('4. Larger viewports render the same states with no overflow', () {
    for (final size in [const Size(1280, 800), const Size(1440, 900)]) {
      testWidgets(
          'captured state at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await setViewport(tester, size);
        final container = await seededContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_measureTab(container, 'proj-overflow'));
        await tester.pumpAndSettle();

        final ctrl = container
            .read(liveMeasurementControllerProvider('proj-overflow').notifier);
        ctrl.markReady();
        await ctrl.capture();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
