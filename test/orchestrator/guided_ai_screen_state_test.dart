// Phase 15-D — GuidedAiScreen UI state rendering tests.
//
// Verifies that:
//   1. completed state renders apply result labels without DSP values
//   2. awaitingMeasurement state renders the required UI text
//   3. No DSP-forbidden strings appear in any rendered text
//
// These are widget integration tests: the real GuidedAiScreen is pumped with
// provider overrides so no network, SharedPreferences, or hardware is touched.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_state.dart';
import 'package:tunai_pro/core/orchestrator/pro_local_orchestrator_session.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/features/ai/guided_ai_screen.dart';

// ── Fake controller ───────────────────────────────────────────────────────────

/// Subclass that starts the notifier with a pre-set state instead of Idle.
class _FakeGuidedAiController extends ProGuidedAiController {
  _FakeGuidedAiController(ProGuidedAiState initial) {
    state = initial;
  }
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _stubChannel = PeqChannelState(
  channelId: 'ch_wf_l',
  bands: [
    PeqBand(id: 'b0', frequencyHz: 200.0, gainDb: -3.0, q: 1.5),
  ],
);

const _stubApplyResult = TuningApplyResult(
  status: TuningApplyStatus.ok,
  updatedChannel: _stubChannel,
  applied: [
    AppliedBand(
      candidateId: 'cand-0',
      featureId: 'feat-0',
      frequencyHz: 200.0,
      gainDb: -3.0,
      q: 1.5,
      applicationOrder: 1,
    ),
  ],
  skipped: [],
  channelId: 'ch_wf_l',
  safetyPolicyId: 'stub-policy',
  safetyPolicyVersion: 1,
  evidenceRefs: [],
  reasons: [],
);

const _stubExplanation = ProExplanation(
  title: '분석 완료',
  summary: '음향 분석이 완료되었습니다.',
  explanationLevel: ProExplanationLevel.intermediate,
);

const _stubOutcome = ProLocalOrchestratorOutcome(
  sessionId: 'test-session',
  finalStatus: ProOrchestratorOutcomeStatus.completed,
  stepRecords: [],
);

ProGuidedAiCompleted _completedState({
  TuningApplyResult? applyResult,
  ProClosedLoopPhase? loopPhase,
}) =>
    ProGuidedAiCompleted(
      outcome: _stubOutcome,
      explanation: _stubExplanation,
      applyResult: applyResult,
      loopPhase: loopPhase,
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _screen(ProGuidedAiState initialState) => ProviderScope(
      overrides: [
        guidedAiProvider.overrideWith(
          (ref) => _FakeGuidedAiController(initialState),
        ),
      ],
      child: const MaterialApp(home: GuidedAiScreen()),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── 1. completed 상태 렌더링 ──────────────────────────────────────────────

  group('1. completed state rendering', () {
    testWidgets('apply result label "적용 완료" is shown', (tester) async {
      final state = _completedState(
        applyResult: _stubApplyResult,
        loopPhase: null,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      expect(find.textContaining('적용 완료'), findsAtLeastNWidgets(1));
    });

    testWidgets('applied band count is shown in UI text', (tester) async {
      final state = _completedState(
        applyResult: _stubApplyResult,
        loopPhase: null,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      // "1밴드 적용" from _ApplyResultCard
      expect(find.textContaining('1밴드'), findsAtLeastNWidgets(1));
    });

    testWidgets('explanation summary is rendered', (tester) async {
      final state = _completedState(
        applyResult: _stubApplyResult,
        loopPhase: null,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      expect(find.text('음향 분석이 완료되었습니다.'), findsOneWidget);
    });

    testWidgets('reset button is shown in completed state', (tester) async {
      final state = _completedState(
        applyResult: null,
        loopPhase: null,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      expect(find.text('처음으로'), findsOneWidget);
    });
  });

  // ── 2. awaitingMeasurement 상태 렌더링 ───────────────────────────────────

  group('2. awaitingMeasurement state rendering', () {
    testWidgets('"스피커 적용 완료" header is shown', (tester) async {
      final state = _completedState(
        applyResult: _stubApplyResult,
        loopPhase: ProClosedLoopPhase.awaitingMeasurement,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      expect(find.text('스피커 적용 완료'), findsOneWidget);
    });

    testWidgets('"개선 확인을 위한 재측정을 기다리는 중" subtitle is shown',
        (tester) async {
      final state = _completedState(
        applyResult: _stubApplyResult,
        loopPhase: ProClosedLoopPhase.awaitingMeasurement,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      expect(find.text('개선 확인을 위한 재측정을 기다리는 중'), findsOneWidget);
    });

    testWidgets('next-step guidance text is shown', (tester) async {
      final state = _completedState(
        applyResult: _stubApplyResult,
        loopPhase: ProClosedLoopPhase.awaitingMeasurement,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      expect(find.textContaining('다시 측정'), findsAtLeastNWidgets(1));
    });

    testWidgets('evaluated phase shows "Closed Loop 평가 완료"', (tester) async {
      final state = _completedState(
        applyResult: _stubApplyResult,
        loopPhase: ProClosedLoopPhase.evaluated,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      expect(find.textContaining('Closed Loop 평가 완료'), findsOneWidget);
    });
  });

  // ── 3. DSP forbidden 문자열 없음 ─────────────────────────────────────────

  group('3. no DSP-forbidden strings in rendered UI', () {
    const dspTerms = [
      'frequency',
      'gainDb',
      'gaindb',
      'biquad',
      'coefficient',
      'register',
      'address',
      'payload',
      '0x',
    ];

    testWidgets('completed state contains no DSP terms in text widgets',
        (tester) async {
      final state = _completedState(
        applyResult: _stubApplyResult,
        loopPhase: ProClosedLoopPhase.awaitingMeasurement,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      for (final widget in textWidgets) {
        final raw = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        for (final term in dspTerms) {
          expect(
            raw.toLowerCase(),
            isNot(contains(term.toLowerCase())),
            reason: 'Text widget contains DSP term "$term": "$raw"',
          );
        }
      }
    });

    testWidgets('awaitingMeasurement phase text contains no DSP terms',
        (tester) async {
      final state = _completedState(
        applyResult: _stubApplyResult,
        loopPhase: ProClosedLoopPhase.awaitingMeasurement,
      );

      await tester.pumpWidget(_screen(state));
      await tester.pump();

      // Explicitly check the two key strings
      const awaitingTitle = '스피커 적용 완료';
      const awaitingSubtitle = '개선 확인을 위한 재측정을 기다리는 중';

      for (final term in dspTerms) {
        expect(awaitingTitle.toLowerCase(), isNot(contains(term.toLowerCase())));
        expect(awaitingSubtitle.toLowerCase(),
            isNot(contains(term.toLowerCase())));
      }
    });

    testWidgets('apply result status labels contain no DSP terms',
        (tester) async {
      final labels = [
        switch (_stubApplyResult.status) {
          TuningApplyStatus.ok => '적용 완료',
          TuningApplyStatus.partiallyApplied => '일부 적용',
          TuningApplyStatus.noSlotAvailable => '슬롯 부족',
          TuningApplyStatus.notPermitted => '적용 차단',
        }
      ];

      for (final label in labels) {
        for (final term in dspTerms) {
          expect(label.toLowerCase(), isNot(contains(term.toLowerCase())),
              reason: 'Label "$label" contains DSP term "$term"');
        }
      }
    });
  });
}
