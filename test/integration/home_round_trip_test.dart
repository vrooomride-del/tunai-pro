// Phase 3-F2 §3/§10 — Home round-trip and CTA routing across the workflow.
//
// Two properties, checked at every stage of the golden path:
//   - Home's four sections agree with the provider (no stage claims completion
//     the model does not have, and no completed stage is asked for again);
//   - the Continue CTA reaches the place that work actually happens, with the
//     one-shot MeasurementEntryIntent consumed by the destination.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/measurement_entry_intent.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_presentation.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';
import 'package:tunai_pro/features/home/home_navigation.dart';
import 'package:tunai_pro/features/home/widgets/home_primitives.dart';
import 'package:tunai_pro/features/home/workspace_home.dart';
import 'package:tunai_pro/features/workbench/tabs/measure_tab.dart';

import '../support/golden_workflow_fixtures.dart';
import 'golden_workflow_test.dart' show GoldenWalk;

Future<void> _pumpHome(WidgetTester tester, ProviderContainer c,
    {Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: WorkspaceHome()),
  ));
  await tester.pump();
}

/// Every stage of the golden path, with a builder that reaches it. Declared
/// with an explicit type because the later entries reference earlier ones.
typedef _StageBuilder = Future<GoldenWalk> Function();

final Map<String, _StageBuilder> _stages = <String, _StageBuilder>{
  'selectMicrophone': () async {
    final w = await GoldenWalk.start();
    await w.createProject();
    return w;
  },
  'selectInputDevice': () async {
    final w = await GoldenWalk.start();
    await w.createProject();
    await w.selectMicrophone();
    return w;
  },
  'checkMeasurementSetup': () async {
    final w = await GoldenWalk.start();
    await w.createProject();
    await w.selectMicrophone();
    await w.selectInputDevice();
    return w;
  },
  'measureFactoryDrivers': () async {
    final w = await GoldenWalk.start();
    await w.createProject();
    await w.selectMicrophone();
    await w.selectInputDevice();
    await w.runSetupCheck();
    return w;
  },
  'runFactoryGuidedTuning': () async {
    final w = await _stages['measureFactoryDrivers']!();
    await w.measureDrivers(count: 4);
    return w;
  },
  'measureRoomBefore': () async {
    final w = await _stages['runFactoryGuidedTuning']!();
    await w.completeFactoryTuning();
    return w;
  },
  'generateRoomAutoPeq': () async {
    final w = await _stages['measureRoomBefore']!();
    await w.measureRoomBefore(count: 2);
    return w;
  },
  'deployRoomCorrection': () async {
    final w = await _stages['generateRoomAutoPeq']!();
    await w.approveAutoPeq();
    return w;
  },
  'measureRoomAfter': () async {
    final w = await _stages['deployRoomCorrection']!();
    await goldenConnectHardware(w.c);
    await w.deploy();
    return w;
  },
  'reviewClosedLoop': () async {
    final w = await _stages['measureRoomAfter']!();
    await w.measureRoomAfter(count: 2);
    return w;
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. Home agrees with the provider at every stage (§10)', () {
    for (final entry in _stages.entries) {
      testWidgets('at ${entry.key}', (tester) async {
        final w = await entry.value();
        addTearDown(w.c.dispose);
        await _pumpHome(tester, w.c);

        final r = w.readiness;
        expect(r.nextRecommendedAction.name, entry.key,
            reason: 'the fixture must actually reach this stage');

        // Continue Tuning renders exactly the model's action, once.
        expect(
            find.widgetWithText(HomePrimaryButton,
                measurementWorkflowActionTitle(r.nextRecommendedAction)),
            findsOneWidget);
        expect(find.byType(HomePrimaryButton), findsOneWidget,
            reason: 'one primary action, always');

        // Progress never exceeds what the model actually completed.
        expect(find.text('${r.completedStages}'), findsWidgets);
        expect(r.completedStages, lessThanOrEqualTo(r.totalStages));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('2. completed work is never asked for again (§10)', () {
    test('Factory is not re-requested once a cycle completed', () async {
      final w = await _stages['measureRoomBefore']!();
      addTearDown(w.c.dispose);
      expect(w.readiness.factoryTuningCompleted, isTrue);
      expect(w.action, isNot(MeasurementWorkflowAction.measureFactoryDrivers));
      expect(w.action, isNot(MeasurementWorkflowAction.runFactoryGuidedTuning));
      expect(w.readiness.stage(MeasurementWorkflowStage.factoryTuning),
          MeasurementWorkflowStageState.complete);
    });

    test('Room Before is not re-requested once 2/2 and quality-clean',
        () async {
      final w = await _stages['generateRoomAutoPeq']!();
      addTearDown(w.c.dispose);
      expect(w.action, isNot(MeasurementWorkflowAction.measureRoomBefore));
      expect(w.action,
          isNot(MeasurementWorkflowAction.resolveRoomMeasurementQuality));
    });

    test('Deploy is not re-requested once readback-verified', () async {
      final w = await _stages['measureRoomAfter']!();
      addTearDown(w.c.dispose);
      expect(w.readiness.correctionDeployedAndVerified, isTrue);
      expect(w.action, isNot(MeasurementWorkflowAction.deployRoomCorrection));
    });

    test(
        'an incomparable After is never Complete, and Verification is not '
        'finished without a verdict', () async {
      final w = await _stages['measureRoomAfter']!();
      addTearDown(w.c.dispose);
      await w.measureRoomAfter(count: 2, mismatched: true);

      expect(w.action, MeasurementWorkflowAction.resolveBeforeAfterMismatch);
      expect(w.action, isNot(MeasurementWorkflowAction.complete));
      expect(w.readiness.stage(MeasurementWorkflowStage.verification),
          MeasurementWorkflowStageState.blocked);
      expect(w.readiness.completedStages, lessThan(w.readiness.totalStages));
    });

    test('a comparable pair with no verdict leaves Verification unfinished',
        () async {
      final w = await _stages['reviewClosedLoop']!();
      addTearDown(w.c.dispose);
      expect(w.readiness.beforeAfterComparable, isTrue);
      expect(w.readiness.closedLoopComplete, isFalse);
      expect(w.readiness.stage(MeasurementWorkflowStage.verification),
          isNot(MeasurementWorkflowStageState.complete));
    });

    testWidgets('hardware disconnected is never rendered as ready',
        (tester) async {
      final w = await _stages['deployRoomCorrection']!();
      addTearDown(w.c.dispose);
      await _pumpHome(tester, w.c);

      expect(w.readiness.hardwareReadyForDeploy, isFalse);
      expect(find.textContaining('하드웨어 준비 완료'), findsNothing);
      expect(find.text('하드웨어가 연결되지 않았습니다.'), findsOneWidget);
      // And the Deploy step explains why it cannot proceed.
      expect(find.text('먼저 하드웨어를 연결하고 준비 상태를 확인하세요.'), findsOneWidget);
    });
  });

  group('3. every CTA reaches real work — no dead CTA (§3)', () {
    for (final entry in _stages.entries) {
      testWidgets('${entry.key} routes and consumes its intent',
          (tester) async {
        final w = await entry.value();
        addTearDown(w.c.dispose);
        await _pumpHome(tester, w.c);

        final action = w.readiness.nextRecommendedAction;
        final destination = homeActionDestination(action);
        expect(destination, isA<HomeWorkbenchDestination>());
        final dest = destination as HomeWorkbenchDestination;

        // Record every intent the CTA raises. Reading the provider after the
        // tap is not enough: pushing WorkbenchShell mounts MeasureTab, which
        // correctly CONSUMES the intent on its first frame — so the raise is
        // only observable as a transition.
        final raised = <MeasurementEntryRequest>[];
        final sub = w.c.listen<MeasurementEntryRequest?>(
          measurementEntryIntentProvider,
          (_, next) {
            if (next != null) raised.add(next);
          },
        );
        addTearDown(sub.close);

        await tester.tap(find.byType(HomePrimaryButton));
        await tester.pump();

        // The tab really moved to the destination.
        expect(w.c.read(workbenchTabProvider), dest.tabIndex,
            reason: action.name);

        if (dest.intent == null) {
          expect(raised, isEmpty, reason: action.name);
        } else {
          expect(raised, hasLength(1), reason: action.name);
          expect(raised.single.intent, dest.intent, reason: action.name);
          expect(raised.single.projectId, kGoldenProjectId);
        }
        // One-shot either way: nothing stale is left behind.
        expect(w.c.read(measurementEntryIntentProvider), isNull,
            reason: 'consumed by the destination, or never raised');
      });
    }

    testWidgets(
        'tapping the microphone CTA lands on Measure with the manager open',
        (tester) async {
      final w = await _stages['selectMicrophone']!();
      addTearDown(w.c.dispose);
      await _pumpHome(tester, w.c);

      await tester.tap(find.byType(HomePrimaryButton));
      await tester.pumpAndSettle();

      // The whole point of the deep link: the user does not have to hunt for
      // the microphone settings after arriving.
      expect(find.byType(MeasureTab), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(w.c.read(measurementEntryIntentProvider), isNull,
          reason: 'one-shot — consumed on arrival');
      expect(tester.takeException(), isNull);
    });

    test('every action in the enum has a real destination', () {
      for (final a in MeasurementWorkflowAction.values) {
        final d = homeActionDestination(a);
        if (d is HomeWorkbenchDestination) {
          expect(d.tabIndex, inInclusiveRange(0, kTabReport), reason: a.name);
        } else {
          expect(a, MeasurementWorkflowAction.createOrOpenProject);
        }
      }
    });
  });

  group('4. hardware session loss mid-workflow (§15-F)', () {
    testWidgets('losing the session updates Home without losing progress',
        (tester) async {
      final w = await _stages['measureRoomAfter']!();
      addTearDown(w.c.dispose);
      await _pumpHome(tester, w.c);
      expect(w.readiness.hardwareReadyForDeploy, isTrue);
      expect(w.action, MeasurementWorkflowAction.measureRoomAfter);

      goldenDisconnectHardware(w.c);
      await tester.pump();

      expect(w.readiness.hardwareReadyForDeploy, isFalse);
      expect(find.text('하드웨어가 연결되지 않았습니다.'), findsOneWidget);
      expect(w.action, MeasurementWorkflowAction.measureRoomAfter,
          reason: 'a written correction is not undone by a dropped session');
      expect(tester.takeException(), isNull);
    });
  });
}
