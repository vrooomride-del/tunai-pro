// Phase 3-F1 §8/§9 — how the hardware session reads on Home.
//
// The wording contract: "준비 완료" belongs to readyForDeploy alone, "확인
// 필요" means nobody checked (neutral, not a failure), and no state ever
// claims Connected/Verified without the full contract holding.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/hardware/hardware_connection_readiness.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_presentation.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';
import 'package:tunai_pro/features/home/widgets/home_primitives.dart';
import 'package:tunai_pro/features/home/widgets/system_readiness_panel.dart';
import 'package:tunai_pro/features/home/workspace_home.dart';
import 'package:tunai_pro/shared/design/pro_tokens.dart';

MeasurementWorkflowReadiness _readiness(HardwareConnectionState state) =>
    MeasurementWorkflowReadiness(
      hasProject: true,
      projectId: 'p1',
      projectName: 'HW',
      microphoneSelected: false,
      calibrationStatus: MeasurementWorkflowCalibrationState.none,
      inputSelected: false,
      inputSelectionKind: MeasurementWorkflowInputSelectionKind.none,
      runtimeAvailabilityKnown: false,
      runtimeAvailability: MeasurementWorkflowInputAvailability.unknown,
      setupState: MeasurementWorkflowSetupState.notChecked,
      setupWarnings: const [],
      requiredDriverCount: 0,
      measuredDriverCount: 0,
      driverMeasurementReady: false,
      guidedTuningReady: false,
      factoryTuningCompleted: false,
      beforeCount: 0,
      beforeMeasurementComplete: false,
      beforeQualityReady: false,
      roomAutoPeqReady: false,
      roomAutoPeqApproved: false,
      correctionDeployedAndVerified: false,
      afterAvailable: false,
      afterCount: 0,
      afterMeasurementComplete: false,
      beforeAfterComparable: false,
      closedLoopComplete: false,
      closedLoopWarnings: const [],
      hardwareConnectionState: state,
      hardwareReadyForDeploy: state == HardwareConnectionState.readyForDeploy,
      hardwareTargetCompatible: state != HardwareConnectionState.incompatible,
      roomCorrectionVerified: false,
      nextRecommendedAction: MeasurementWorkflowAction.selectMicrophone,
      warnings: const [],
      stages: const {},
    );

Future<void> _pumpPanel(
  WidgetTester tester,
  HardwareConnectionState state, {
  Size size = const Size(1280, 720),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SystemReadinessPanel(
            readiness: _readiness(state),
            onOpenSetup: () {},
            onOpenHardware: () {},
            onOpenMicrophone: () {},
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. every state has its own honest wording', () {
    const expected = {
      HardwareConnectionState.unknown: '하드웨어 상태 확인 필요',
      HardwareConnectionState.disconnected: '하드웨어가 연결되지 않았습니다.',
      HardwareConnectionState.connecting: '하드웨어 연결 중',
      HardwareConnectionState.connected: '하드웨어 연결됨',
      HardwareConnectionState.readyForDeploy: '하드웨어 준비 완료',
      HardwareConnectionState.incompatible: '프로젝트와 연결된 DSP가 일치하지 않습니다.',
      HardwareConnectionState.error: '하드웨어 연결을 확인해 주세요.',
    };

    for (final entry in expected.entries) {
      testWidgets(entry.key.name, (tester) async {
        await _pumpPanel(tester, entry.key);
        expect(find.text(entry.value), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    test('every state maps to non-empty title and detail', () {
      for (final s in HardwareConnectionState.values) {
        final t = measurementWorkflowHardwareText(s);
        expect(t.title, isNotEmpty, reason: s.name);
        expect(t.detail, isNotEmpty, reason: s.name);
        expect(t.title, isNot(contains(s.name)));
      }
    });
  });

  group('2. no false readiness claims', () {
    testWidgets('only readyForDeploy may say 준비 완료 / 적용 가능', (tester) async {
      for (final s in HardwareConnectionState.values) {
        final t = measurementWorkflowHardwareText(s);
        final claimsReady =
            t.title.contains('준비 완료') || t.detail.contains('적용할 수 있습니다');
        expect(claimsReady, s == HardwareConnectionState.readyForDeploy,
            reason: s.name);
      }
    });

    testWidgets('connected-but-not-ready never reads as ready', (tester) async {
      await _pumpPanel(tester, HardwareConnectionState.connected);
      expect(find.text('하드웨어 연결됨'), findsOneWidget);
      expect(find.textContaining('준비 완료'), findsNothing);
      expect(find.textContaining('Verified'), findsNothing);
      expect(find.text('DSP 준비 상태를 확인하고 있습니다.'), findsOneWidget);
    });

    testWidgets('unknown is neutral grey, not a failure colour',
        (tester) async {
      await _pumpPanel(tester, HardwareConnectionState.unknown);
      final detail =
          tester.widget<Text>(find.text('DSP 연결 상태는 Hardware에서 확인할 수 있습니다.'));
      expect(detail.style?.color, ProColors.textTertiary);
      expect(detail.style?.color, isNot(ProColors.red));
      expect(detail.style?.color, isNot(ProColors.amber));
    });

    testWidgets('readyForDeploy is the only green hardware row',
        (tester) async {
      await _pumpPanel(tester, HardwareConnectionState.readyForDeploy);
      final detail = tester.widget<Text>(find.text('보정을 적용할 수 있습니다.'));
      expect(detail.style?.color, ProColors.green);
    });
  });

  group('3. layout', () {
    for (final s in HardwareConnectionState.values) {
      testWidgets('no overflow at 1280x720 — ${s.name}', (tester) async {
        await _pumpPanel(tester, s);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('4. the hardware CTA opens the Hardware tab', () {
    testWidgets('tapping the hardware row focuses Hardware', (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(proProjectStoreProvider.notifier).addProject(ProProject(
            id: 'p1',
            name: 'HW',
            dspTarget: 'ADAU1701',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ));
      await c.read(proProjectStoreProvider.notifier).setCurrentProject('p1');

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: WorkspaceHome()),
      ));
      await tester.pump();

      expect(c.read(workbenchTabProvider), kTabProject);
      await tester.tap(find.text('하드웨어가 연결되지 않았습니다.'));
      await tester.pump();
      expect(c.read(workbenchTabProvider), kTabHardware);
    });
  });

  group('5. Deploy step surfaces the hardware blocker (§9)', () {
    MeasurementWorkflowReadiness atDeploy(HardwareConnectionState s) {
      final base = _readiness(s);
      return MeasurementWorkflowReadiness(
        hasProject: true,
        projectId: base.projectId,
        projectName: base.projectName,
        microphoneSelected: true,
        calibrationStatus: MeasurementWorkflowCalibrationState.calibrated,
        inputSelected: true,
        inputSelectionKind:
            MeasurementWorkflowInputSelectionKind.specificDevice,
        runtimeAvailabilityKnown: true,
        runtimeAvailability:
            MeasurementWorkflowInputAvailability.lastKnownValid,
        setupState: MeasurementWorkflowSetupState.ready,
        setupWarnings: const [],
        requiredDriverCount: 4,
        measuredDriverCount: 4,
        driverMeasurementReady: true,
        guidedTuningReady: true,
        factoryTuningCompleted: true,
        beforeCount: 2,
        beforeMeasurementComplete: true,
        beforeQualityReady: true,
        roomAutoPeqReady: true,
        roomAutoPeqApproved: true,
        correctionDeployedAndVerified: false,
        afterAvailable: false,
        afterCount: 0,
        afterMeasurementComplete: false,
        beforeAfterComparable: false,
        closedLoopComplete: false,
        closedLoopWarnings: const [],
        hardwareConnectionState: s,
        hardwareReadyForDeploy: s == HardwareConnectionState.readyForDeploy,
        hardwareTargetCompatible: s != HardwareConnectionState.incompatible,
        roomCorrectionVerified: false,
        nextRecommendedAction: MeasurementWorkflowAction.deployRoomCorrection,
        primaryBlocker:
            MeasurementWorkflowBlockerCode.roomCorrectionNotDeployed,
        warnings: const [],
        stages: const {},
      );
    }

    test('a not-ready session produces a hardware blocker line', () {
      expect(
          measurementWorkflowHardwareBlockerText(
              atDeploy(HardwareConnectionState.disconnected)),
          '먼저 하드웨어를 연결하고 준비 상태를 확인하세요.');
      expect(
          measurementWorkflowHardwareBlockerText(
              atDeploy(HardwareConnectionState.incompatible)),
          '프로젝트와 연결된 DSP가 일치하지 않습니다.');
    });

    test('a ready session produces none', () {
      expect(
          measurementWorkflowHardwareBlockerText(
              atDeploy(HardwareConnectionState.readyForDeploy)),
          isNull);
    });

    test('earlier workflow steps never show it', () {
      for (final s in HardwareConnectionState.values) {
        expect(measurementWorkflowHardwareBlockerText(_readiness(s)), isNull,
            reason: 'selectMicrophone step must stay about the microphone '
                '(${s.name})');
      }
    });

    testWidgets('the Deploy CTA still owns the only primary action',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(builder: (context) {
                return Column(children: [
                  Text(measurementWorkflowActionTitle(
                      MeasurementWorkflowAction.deployRoomCorrection)),
                  Text(measurementWorkflowHardwareBlockerText(
                          atDeploy(HardwareConnectionState.disconnected)) ??
                      ''),
                ]);
              }),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('먼저 하드웨어를 연결하고 준비 상태를 확인하세요.'), findsOneWidget);
      expect(find.byType(HomePrimaryButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
