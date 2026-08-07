// Phase 3-E §22 — Workspace Home.
//
// Home's contract: it renders MeasurementWorkflowReadiness and nothing else.
// These tests pin the four things that would quietly break that —
//  - exactly ONE primary CTA, and it is the readiness model's next action,
//  - the Journey never invents progress or a percentage,
//  - hardware that nobody checked never reads as connected/verified,
//  - no internal DSP terminology reaches the beginner surface —
// plus zero overflow at the supported window sizes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_presentation.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_provider.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';
import 'package:tunai_pro/features/home/home_navigation.dart';
import 'package:tunai_pro/features/home/widgets/expert_tools_section.dart';
import 'package:tunai_pro/features/home/widgets/home_primitives.dart';
import 'package:tunai_pro/features/home/workspace_home.dart';

import '../support/capture_gate_fixtures.dart';

ProProject _project(String id, {bool setupReady = false}) {
  final base = ProProject(
    id: id,
    name: 'TUNAI ONE Prototype',
    speakerModel: 'TUNAI ONE',
    dspTarget: 'ADAU1701',
    channelConfig: '2-way stereo',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
  return setupReady ? withGateReadySetup(base) : base;
}

Future<ProviderContainer> _seed({ProProject? project}) async {
  final c = ProviderContainer();
  if (project != null) {
    await c.read(proProjectStoreProvider.notifier).addProject(project);
    await c
        .read(proProjectStoreProvider.notifier)
        .setCurrentProject(project.id);
  }
  return c;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer c, {
  Size size = const Size(1440, 900),
}) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. no project', () {
    testWidgets('offers New/Open/Demo and shows no fabricated progress',
        (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      await _pump(tester, c);

      expect(find.text('새 프로젝트'), findsOneWidget);
      expect(find.text('프로젝트 열기'), findsOneWidget);
      expect(find.text('데모 살펴보기'), findsOneWidget);

      // No stage counter, and no Journey at all — there is nothing to be
      // partway through.
      expect(find.text('단계 완료'), findsNothing);
      expect(find.text('튜닝 진행 상황'), findsNothing);
      expect(find.textContaining('/ 5'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the next action is create/open the project', (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      await _pump(tester, c);

      expect(
          find.text(measurementWorkflowActionTitle(
              MeasurementWorkflowAction.createOrOpenProject)),
          findsWidgets);
    });
  });

  group('2. project active', () {
    testWidgets('hero shows identity, configuration and whole-stage progress',
        (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      final r = c.read(measurementWorkflowReadinessProvider);
      expect(find.text('TUNAI ONE Prototype'), findsOneWidget);
      expect(find.text('2-way stereo · ADAU1701'), findsOneWidget);
      expect(find.text('${r.completedStages}'), findsWidgets);
      expect(find.text(' / 5'), findsOneWidget);
      expect(find.text('단계 완료'), findsOneWidget);
    });

    testWidgets('exactly one primary CTA, and it is the readiness action',
        (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      final action =
          c.read(measurementWorkflowReadinessProvider).nextRecommendedAction;
      expect(action, MeasurementWorkflowAction.measureFactoryDrivers);
      expect(find.byType(HomePrimaryButton), findsOneWidget,
          reason: 'Continue Tuning owns the only primary action on Home');
      expect(
          find.widgetWithText(
              HomePrimaryButton, measurementWorkflowActionTitle(action)),
          findsOneWidget);
    });

    testWidgets('the four sections do not repeat each other', (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      // Section identity: one hero name, one Continue label, one Journey,
      // one Readiness panel.
      expect(find.text('TUNAI ONE Prototype'), findsOneWidget);
      expect(find.text('다음 단계'), findsOneWidget);
      expect(find.text('튜닝 진행 상황'), findsOneWidget);
      expect(find.text('준비 상태'), findsOneWidget);
    });
  });

  group('3. tuning journey', () {
    testWidgets('renders 5 stages with no percentage anywhere', (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      for (final s in MeasurementWorkflowStage.values) {
        expect(find.text(measurementWorkflowStageTitle(s)), findsOneWidget,
            reason: s.name);
      }
      expect(find.textContaining('%'), findsNothing,
          reason: 'no fabricated precision — whole stages only');
    });

    testWidgets('stage states are visually distinguished', (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      final r = c.read(measurementWorkflowReadinessProvider);
      expect(r.stage(MeasurementWorkflowStage.measurementSetup),
          MeasurementWorkflowStageState.complete);
      expect(r.stage(MeasurementWorkflowStage.factoryTuning),
          MeasurementWorkflowStageState.notStarted);
      expect(find.text('완료'), findsWidgets);
      expect(find.text('시작 전'), findsWidgets);
    });

    testWidgets('a stage expands to beginner-level detail', (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      await tester.tap(find.text(measurementWorkflowStageTitle(
          MeasurementWorkflowStage.measurementSetup)));
      await tester.pump();

      expect(find.textContaining('측정 마이크:'), findsOneWidget);
      expect(find.textContaining('마이크 보정:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('4. system readiness', () {
    testWidgets('shows mic, input, setup and hardware', (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      expect(find.text('측정 마이크'), findsWidgets);
      expect(find.text('입력'), findsOneWidget);
      expect(find.text('측정 준비 확인'), findsOneWidget);
      expect(find.text('하드웨어'), findsOneWidget);
    });

    testWidgets('unchecked hardware is never Connected/Verified/Ready',
        (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      expect(c.read(measurementWorkflowReadinessProvider).hardwareConnected,
          isNull);
      expect(find.text('확인 필요'), findsWidgets);
      for (final claim in ['Connected', '연결됨', 'Verified', '검증됨']) {
        expect(find.textContaining(claim), findsNothing, reason: claim);
      }
    });

    testWidgets('a project with no microphone says so, without a red failure',
        (tester) async {
      final c = await _seed(project: _project('p1'));
      addTearDown(c.dispose);
      await _pump(tester, c);

      expect(find.text('선택되지 않음'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('5. expert tools', () {
    testWidgets('every workbench tab stays reachable', (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      expect(find.text('EXPERT TOOLS'), findsOneWidget);
      await tester.tap(find.text('EXPERT TOOLS'));
      await tester.pump();

      expect(find.text('PEQ'), findsOneWidget);
      expect(find.text('Crossover'), findsOneWidget);
      expect(find.text('Deploy'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('the tool list covers every real tab index exactly once', () {
      final indices = [
        for (final g in kExpertToolGroups)
          for (final t in g.tools) t.tabIndex,
      ];
      expect(indices.toSet().length, indices.length,
          reason: 'no tab is listed twice');
      // Every index must be a real tab (the shell defines 19).
      for (final i in indices) {
        expect(i, inInclusiveRange(0, kTabReport));
      }
    });
  });

  group('6. simulated data', () {
    testWidgets('no simulated/placeholder surface appears on Home',
        (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      for (final term in ['SIMULATED', 'Simulated', 'placeholder', '시뮬레이션']) {
        expect(find.textContaining(term), findsNothing, reason: term);
      }
      // And it contributes nothing to progress.
      expect(
          c.read(measurementWorkflowReadinessProvider).measuredDriverCount, 0);
    });
  });

  group('7. responsive', () {
    for (final size in [
      const Size(1280, 720),
      const Size(1440, 900),
      const Size(1920, 1080),
    ]) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        final c = await _seed(project: _project('p1', setupReady: true));
        addTearDown(c.dispose);
        await _pump(tester, c, size: size);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a short window scrolls instead of overflowing',
        (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c, size: const Size(1280, 560));

      expect(find.byType(SingleChildScrollView), findsWidgets);
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, -300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long project name truncates safely', (tester) async {
      final long = _project('p1', setupReady: true).copyWith(
        name: 'A' * 200,
      );
      final c = await _seed(project: long);
      addTearDown(c.dispose);
      await _pump(tester, c, size: const Size(1280, 720));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the narrow layout stacks Continue above Readiness',
        (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c, size: const Size(900, 900));
      await tester.pumpAndSettle();
      expect(find.text('다음 단계'), findsOneWidget);
      expect(find.text('준비 상태'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('8. navigation mapping (§6/§21)', () {
    test('every action resolves to a real destination', () {
      for (final a in MeasurementWorkflowAction.values) {
        final d = homeActionDestination(a);
        switch (d) {
          case HomeProjectListDestination():
            expect(a, MeasurementWorkflowAction.createOrOpenProject);
          case HomeWorkbenchDestination(:final tabIndex):
            expect(tabIndex, inInclusiveRange(0, kTabReport), reason: a.name);
        }
      }
    });

    test('each action lands where that work actually happens', () {
      int tabOf(MeasurementWorkflowAction a) =>
          (homeActionDestination(a) as HomeWorkbenchDestination).tabIndex;

      expect(tabOf(MeasurementWorkflowAction.selectMicrophone), kTabMeasure);
      expect(tabOf(MeasurementWorkflowAction.fixCalibration), kTabMeasure);
      expect(tabOf(MeasurementWorkflowAction.selectInputDevice), kTabMeasure);
      expect(
          tabOf(MeasurementWorkflowAction.checkMeasurementSetup), kTabMeasure);
      expect(
          tabOf(MeasurementWorkflowAction.measureFactoryDrivers), kTabMeasure);
      expect(tabOf(MeasurementWorkflowAction.runFactoryGuidedTuning),
          kTabGuidedAi);
      expect(tabOf(MeasurementWorkflowAction.measureRoomBefore), kTabMeasure);
      expect(tabOf(MeasurementWorkflowAction.resolveRoomMeasurementQuality),
          kTabMeasure);
      expect(tabOf(MeasurementWorkflowAction.generateRoomAutoPeq), kTabAutoPeq);
      expect(tabOf(MeasurementWorkflowAction.deployRoomCorrection), kTabDeploy);
      expect(tabOf(MeasurementWorkflowAction.measureRoomAfter), kTabMeasure);
      expect(tabOf(MeasurementWorkflowAction.resolveBeforeAfterMismatch),
          kTabMeasure);
      expect(tabOf(MeasurementWorkflowAction.reviewClosedLoop), kTabMeasure);
      expect(tabOf(MeasurementWorkflowAction.complete), kTabReport);
    });

    testWidgets('tapping the primary CTA focuses the right tab',
        (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      expect(c.read(workbenchTabProvider), kTabProject);
      await tester.tap(find.byType(HomePrimaryButton));
      await tester.pump();

      // measureFactoryDrivers -> Measure tab, set before the shell opens.
      expect(c.read(workbenchTabProvider), kTabMeasure);
    });
  });

  group('9. beginner copy', () {
    testWidgets('no internal DSP terminology on the beginner surface',
        (tester) async {
      final c = await _seed(project: _project('p1', setupReady: true));
      addTearDown(c.dispose);
      await _pump(tester, c);

      // Expert Tools deliberately carries the professional tab NAMES (PEQ,
      // Crossover, ...) and is collapsed by default, so the beginner surface
      // is what is on screen here.
      const forbidden = [
        'biquad',
        'Biquad',
        'FFT',
        'register',
        'checksum',
        'provenance',
        'dBFS',
        'SNR',
        '0x',
      ];
      for (final term in forbidden) {
        expect(find.textContaining(term), findsNothing, reason: term);
      }
    });
  });
}
