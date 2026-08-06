// P1 fix regression guard: Guided AI must never auto-consume a mic capture
// as the closed-loop "After" result just because it completed while
// loopPhase == awaitingMeasurement. The old ref.listen(micMeasurementProvider)
// in guided_ai_screen.dart did exactly that -- it could not tell a real
// "After 측정하기" capture apart from a Before capture, a Retry capture, or
// any other capture happening on the Measure tab (which stays mounted
// alongside Guided AI inside WorkbenchShell's IndexedStack). That listener
// has been removed; the only production After path is now
// LiveMeasurementController's explicit Accept -> 4/4 ->
// submitAfterFourChannelFrd() (see live_measurement_controller_test.dart
// groups 10-12) and the file-based After FRD import in guided_ai_screen.dart
// (_importAfterFrd).
//
// This file guards against the cross-contamination path ever coming back.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_state.dart';
import 'package:tunai_pro/core/orchestrator/pro_local_orchestrator_session.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/workbench_shell.dart';

// ── Structural guard ─────────────────────────────────────────────────────────

void main() {
  group('structural guard', () {
    test('guided_ai_screen.dart no longer listens to micMeasurementProvider',
        () {
      final src =
          File('lib/features/ai/guided_ai_screen.dart').readAsStringSync();
      expect(src.contains('ref.listen(micMeasurementProvider'), isFalse,
          reason: 'Guided AI must not auto-consume raw mic completion '
              'events as the After result -- it cannot distinguish a real '
              '"After 측정하기" capture from Before/Retry/any other capture '
              'on the Measure tab.');
    });

    test('the obsolete single-bin submitAfterMeasurementFromBins API is gone',
        () {
      final src = File('lib/core/orchestrator/pro_guided_ai_controller.dart')
          .readAsStringSync();
      expect(src.contains('submitAfterMeasurementFromBins'), isFalse,
          reason: 'This method had exactly one caller (the removed '
              'listener) and no test coverage -- keeping it around as dead '
              'API risks it being silently re-wired later.');
    });

    test('the explicit 4-channel After path is still intact', () {
      final controllerSrc =
          File('lib/features/workbench/tabs/live_measurement_controller.dart')
              .readAsStringSync();
      expect(controllerSrc.contains('submitAfterFourChannelFrd'), isTrue,
          reason: 'LiveMeasurementController must still call the explicit, '
              'Accept-only 4-channel After submission.');
      final screenSrc =
          File('lib/features/ai/guided_ai_screen.dart').readAsStringSync();
      expect(screenSrc.contains('submitAfterFourChannelFrd'), isTrue,
          reason: 'The file-based After FRD import path must remain.');
    });
  });

  group('IndexedStack co-mount: mic completion never reaches Guided AI', () {
    testWidgets(
        'Guided AI + Measure co-mounted in WorkbenchShell; a mic capture '
        'completing (Before/Retry/general -- indistinguishable at this '
        'layer) does not change guidedAiProvider state while '
        'awaitingMeasurement', (tester) async {
      const projectId = 'proj-isolation';
      SharedPreferences.setMockInitialValues({});

      const awaitingState = ProGuidedAiCompleted(
        outcome: _stubOutcome,
        explanation: _stubExplanation,
        loopPhase: ProClosedLoopPhase.awaitingMeasurement,
      );
      final fakeAi = _FakeGuidedAiController(awaitingState);

      // MicMeasurementController's real superclass constructs real
      // record/just_audio plugin objects; stub their platform channels so
      // construction/dispose don't throw in a plugin-less test host (same
      // technique as live_measurement_controller_test.dart).
      const recordChannel = MethodChannel('com.llfbandit.record/messages');
      const justAudioChannel =
          MethodChannel('com.ryanheise.just_audio.methods');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(recordChannel, (call) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(justAudioChannel, (call) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(recordChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(justAudioChannel, null);
      });

      late _FakeMicController fakeMic;
      final scopedContainer = ProviderContainer(overrides: [
        guidedAiProvider.overrideWith((ref) => fakeAi),
        mic.micMeasurementProvider.overrideWith((ref) {
          fakeMic = _FakeMicController(ref);
          return fakeMic;
        }),
      ]);
      addTearDown(scopedContainer.dispose);
      await scopedContainer.read(proProjectStoreProvider.notifier).addProject(
            ProProject(
              id: projectId,
              name: 'Isolation Test',
              createdAt: DateTime.utc(2025, 1, 1),
              updatedAt: DateTime.utc(2025, 1, 1),
              acousticState: MeasurementProjectState.createDefault(),
            ),
          );
      // Force the override's mic instance to construct before the widget
      // tree (which may not eagerly read it depending on which tab is
      // initially visible) and before this test reaches for it below.
      scopedContainer.read(mic.micMeasurementProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scopedContainer,
          child: const MaterialApp(
            home: WorkbenchShell(projectId: projectId),
          ),
        ),
      );
      await tester.pump();

      final beforeState = scopedContainer.read(guidedAiProvider);
      expect(beforeState, same(awaitingState));

      // Simulate a mic capture completing -- this is exactly the event the
      // old listener reacted to, regardless of which tab/action triggered
      // it (Before capture, Retry, or an unrelated Measure-tab capture).
      fakeMic.completeWith(const [
        {'frequency': 1000.0, 'db': -2.0},
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final afterState = scopedContainer.read(guidedAiProvider);
      expect(afterState, same(beforeState),
          reason: 'guidedAiProvider state must be completely untouched by '
              'a mic capture completion -- only the explicit Accept -> 4/4 '
              '-> submitAfterFourChannelFrd() path (or file import) may '
              'produce a verdict.');
      expect((afterState as ProGuidedAiCompleted).loopPhase,
          ProClosedLoopPhase.awaitingMeasurement);
      expect(afterState.loopVerdict, isNull);
    });
  });
}

// ── Fakes ─────────────────────────────────────────────────────────────────────

const _stubOutcome = ProLocalOrchestratorOutcome(
  sessionId: 'sess-isolation',
  finalStatus: ProOrchestratorOutcomeStatus.completed,
  stepRecords: [],
);

const _stubExplanation = ProExplanation(
  title: 'stub',
  summary: 'stub',
  explanationLevel: ProExplanationLevel.intermediate,
);

class _FakeGuidedAiController extends ProGuidedAiController {
  _FakeGuidedAiController(ProGuidedAiState initial) {
    state = initial;
  }
}

class _FakeMicController extends mic.MicMeasurementController {
  _FakeMicController(super.ref);

  void completeWith(List<Map<String, double>> response) {
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: response,
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {
    // See live_measurement_controller_test.dart's _FakeMicController for
    // rationale: the real superclass's dispose() reaches real record/
    // just_audio plugin objects this fake never started.
  }
}
