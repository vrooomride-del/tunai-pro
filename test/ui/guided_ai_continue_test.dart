import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_state.dart';
import 'package:tunai_pro/core/orchestrator/pro_local_orchestrator_session.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/features/ai/guided_ai_screen.dart';

const _ids = ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'];

class _CountingTabs extends WorkbenchTabNotifier {
  int deployCalls = 0;

  @override
  void go(int index) {
    if (index == kTabDeploy) deployCalls++;
    super.go(index);
  }
}

class _ContinueController extends ProGuidedAiController {
  final bool failAfterConfirm;
  final _done = Completer<void>();
  Future<void> Function(String, TuningApplyResult)? _onApply;
  Future<void> Function(String, HardwareWritePlan)? _onWritePlan;
  Future<void> Function(String, DspExportPackage)? _onExport;
  int confirmCalls = 0;
  int applyCalls = 0;
  int writePlanCalls = 0;

  _ContinueController({this.failAfterConfirm = false});

  @override
  Future<void> start({
    required ProProject project,
    required String userGoal,
    String? targetChannelId,
    Future<void> Function(String, TuningApplyResult)? onApply,
    Future<void> Function(String, HardwareWritePlan)? onHardwareWritePlan,
    Future<void> Function(String, DspExportPackage)? onExportPackage,
  }) async {
    _onApply = onApply;
    _onWritePlan = onHardwareWritePlan;
    _onExport = onExportPackage;
    state = const ProGuidedAiConfirmPending(
      request: ProUserConfirmationRequest(
        stepId: 'apply-gate',
        toolId: ProOrchestratorToolId.acousticValidateSafety,
        objective: 'approve',
        explanation: ProExplanation(
          title: 'approve',
          summary: 'approve',
          explanationLevel: ProExplanationLevel.intermediate,
        ),
      ),
      plan: ProOrchestratorPlan(
        planId: 'p', intentRef: 'i', contextRef: 'c', steps: []),
      explanation: ProExplanation(
        title: 'approve',
        summary: 'approve',
        explanationLevel: ProExplanationLevel.intermediate,
      ),
      completedSteps: [],
      fullSystemReady: true,
    );
    await _done.future;
  }

  @override
  void confirm(String stepId) {
    confirmCalls++;
    if (confirmCalls > 1) return;
    Future<void>(() async {
      try {
        if (failAfterConfirm) {
          throw StateError('persistence failed');
        }
        for (final id in _ids) {
          applyCalls++;
          await _onApply?.call(
            'test-proj',
            TuningApplyResult(
              status: TuningApplyStatus.ok,
              updatedChannel: PeqChannelState.fixed(id),
              applied: const [],
              skipped: const [],
              channelId: id,
              safetyPolicyId: 'safe',
              safetyPolicyVersion: 1,
              evidenceRefs: const [],
              reasons: const [],
            ),
          );
        }
        final package = DspExportPackage(
          id: 'pkg',
          parameterBlocks: const [],
        );
        await _onExport?.call('test-proj', package);
        final plan = buildHardwareWritePlan(
            package, HardwareDeviceProfiles.adau1701Icp5);
        writePlanCalls++;
        await _onWritePlan?.call('test-proj', plan);
        // Simulate an accidental duplicate handoff from upstream.
        await _onWritePlan?.call('test-proj', plan);
        state = const ProGuidedAiCompleted(
          outcome: ProLocalOrchestratorOutcome(
            sessionId: 's',
            finalStatus: ProOrchestratorOutcomeStatus.completed,
            stepRecords: [],
          ),
          explanation: ProExplanation(
            title: 'done',
            summary: 'done',
            explanationLevel: ProExplanationLevel.intermediate,
          ),
        );
        _done.complete();
      } catch (error, stack) {
        _done.completeError(error, stack);
      }
    });
  }
}

ProProject _project() {
  final now = DateTime(2026, 8, 1);
  return ProProject(
    id: 'test-proj',
    name: 'test',
    createdAt: now,
    updatedAt: now,
    acousticState: MeasurementProjectState(
      driverChannels: [
        for (var i = 0; i < _ids.length; i++)
          DriverChannel(
            id: _ids[i],
            name: _ids[i],
            role: i.isEven ? DriverRole.coaxTweeter : DriverRole.coaxWoofer,
            side: i < 2 ? DriverSide.left : DriverSide.right,
            frdData: ParsedMeasurementData(
              id: 'frd-${_ids[i]}',
              sourceFileName: '${_ids[i]}.frd',
              fileType: AcousticFileType.frd,
              importedAt: now,
              points: const [
                MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 0),
              ],
            ),
          ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('continue is awaited, single-flight, and keeps app root alive',
      (tester) async {
    final project = _project();
    SharedPreferences.setMockInitialValues({
      'tunai_pro_projects': ProProject.encodeList([project]),
    });
    final controller = _ContinueController();
    final tabs = _CountingTabs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          guidedAiProvider.overrideWith((ref) => controller),
          workbenchTabProvider.overrideWith((ref) => tabs),
        ],
        child: const MaterialApp(
          home: GuidedAiScreen(projectId: 'test-proj'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI 분석 시작'));
    await tester.pump();
    expect(find.text('계속'), findsOneWidget);
    await tester.tap(find.text('계속'));
    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(controller.confirmCalls, 1);
    expect(controller.applyCalls, 4);
    expect(controller.writePlanCalls, 1);
    expect(tabs.deployCalls, 1);
  });

  testWidgets('async apply error becomes Guided AI failure without escaping',
      (tester) async {
    final project = _project();
    SharedPreferences.setMockInitialValues({
      'tunai_pro_projects': ProProject.encodeList([project]),
    });
    final controller = _ContinueController(failAfterConfirm: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [guidedAiProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(
          home: GuidedAiScreen(projectId: 'test-proj'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI 분석 시작'));
    await tester.pump();
    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(controller.state, isA<ProGuidedAiFailed>());
    expect(find.textContaining('적용 처리 실패'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
