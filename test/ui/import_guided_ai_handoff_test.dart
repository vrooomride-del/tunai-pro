// Import → Guided AI channel handoff tests.
//
// Cases:
//   A  One eligible channel            — bottom AI button always enabled (4-channel mode)
//   B  Multiple eligible channels      — bottom button enabled, new hint text shown
//   C  Per-channel "Expert 단일 채널 분석" — exact channelId stored, GuidedAi shows matching FRD
//   D  Invalid / missing channelId     — GuidedAi shows blocked state or 4-channel panel
//   E  Existing single-FRD navigation still works (global button → null targetChannelId)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_state.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/features/ai/guided_ai_screen.dart';
import 'package:tunai_pro/features/workbench/tabs/import_tab.dart';

// ── Fake controller ────────────────────────────────────────────────────────────

class _FakeGuidedAiController extends ProGuidedAiController {
  _FakeGuidedAiController(ProGuidedAiState initial) {
    state = initial;
  }
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kProjectsKey = 'tunai_pro_projects';

// Stub FRD data + file ref — minimal, parse-valid.
AcousticFileRef _frdRef(String fileName) => AcousticFileRef(
      id: 'ref-${fileName.hashCode}',
      fileName: fileName,
      type: AcousticFileType.frd,
      importedAt: DateTime.utc(2025, 1, 1),
      parseStatus: MeasurementParseStatus.parsed,
    );

ParsedMeasurementData _frdData(String fileName) => ParsedMeasurementData(
      id: 'frd-${fileName.hashCode}',
      sourceFileName: fileName,
      fileType: AcousticFileType.frd,
      importedAt: DateTime.utc(2025, 1, 1),
      points: const [MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 85.0)],
    );

// Woofer L with FRD + one repeat sweep (the QA scenario).
final _chWfL = DriverChannel(
  id: 'ch_wf_l',
  name: 'Woofer L',
  role: DriverRole.coaxWoofer,
  side: DriverSide.left,
  frdFile: _frdRef('DC130BS-4@0all.frd'),
  frdData: _frdData('DC130BS-4@0all.frd'),
  additionalFrdSweeps: const [
    FrdSweepEntry(fileName: 'DC130BS-4@15.frd', content: '', contentHash: '')
  ],
);

// Tweeter L with FRD only, no repeat sweep.
final _chTwL = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.coaxTweeter,
  side: DriverSide.left,
  frdFile: _frdRef('DC28F-8@0all.frd'),
  frdData: _frdData('DC28F-8@0all.frd'),
);

// Woofer R with FRD + repeat sweep (for multi-eligible scenario).
final _chWfR = DriverChannel(
  id: 'ch_wf_r',
  name: 'Woofer R',
  role: DriverRole.coaxWoofer,
  side: DriverSide.right,
  frdFile: _frdRef('DC130BS-4-R@0all.frd'),
  frdData: _frdData('DC130BS-4-R@0all.frd'),
  additionalFrdSweeps: const [
    FrdSweepEntry(fileName: 'DC130BS-4-R@15.frd', content: '', contentHash: '')
  ],
);

ProProject _project(List<DriverChannel> channels) => ProProject(
      id: 'test-proj',
      name: 'Test Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      acousticState: MeasurementProjectState(driverChannels: channels),
      tuningState: TuningProjectState(
        peqChannels: [for (final ch in channels) PeqChannelState.empty(ch.id)],
      ),
    );

void _seed(List<DriverChannel> channels) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([_project(channels)]),
  });
}

// Helper: find an OutlinedButton (including OutlinedButton.icon) by its label text.
// OutlinedButton.icon returns _OutlinedButtonWithIcon (a subtype), so bySubtype is needed.
Finder _outlinedBtnWith(String label) => find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<OutlinedButton>(),
    );

// ── Widget helpers ─────────────────────────────────────────────────────────────

Widget _importScreen(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: ImportTab(projectId: 'test-proj')),
      ),
    );

Widget _aiScreen(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GuidedAiScreen(projectId: 'test-proj')),
    );

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── A: One eligible channel ───────────────────────────────────────────────

  group('A. One eligible channel', () {
    // Global "AI로 분석하기" is now always the full 4-channel path.
    // It navigates to Guided AI without setting a targetChannelId.

    testWidgets('bottom AI button is enabled', (tester) async {
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      final btn = _outlinedBtnWith('AI로 분석하기');
      expect(btn, findsOneWidget);
      expect(tester.widget<OutlinedButton>(btn).onPressed, isNotNull);
    });

    testWidgets('tapping AI button clears guidedAiTargetChannelProvider (full-system mode)',
        (tester) async {
      // Full 4-channel path: global button does NOT set a single channelId.
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      final btn = _outlinedBtnWith('AI로 분석하기');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();

      expect(container.read(guidedAiTargetChannelProvider), isNull);
    });

    testWidgets('tapping AI button navigates to kTabGuidedAi', (tester) async {
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      final btn = _outlinedBtnWith('AI로 분석하기');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();

      expect(container.read(workbenchTabProvider), equals(kTabGuidedAi));
    });

    testWidgets('no old selection-required message shown', (tester) async {
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('채널이 여러 개'), findsNothing);
    });
  });

  // ── B: Multiple eligible channels ────────────────────────────────────────

  group('B. Multiple eligible channels', () {
    // Both Woofer L and Woofer R have FRD + repeat sweeps.
    // With 4-channel mode, the global button is always enabled.

    testWidgets('bottom AI button is enabled when multiple eligible channels',
        (tester) async {
      _seed([_chWfL, _chWfR]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      final btn = _outlinedBtnWith('AI로 분석하기');
      expect(btn, findsOneWidget);
      expect(tester.widget<OutlinedButton>(btn).onPressed, isNotNull);
    });

    testWidgets('full-system hint text shown when multiple channels', (tester) async {
      _seed([_chWfL, _chWfR]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('전체 시스템 분석'), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping button navigates to Guided AI with null channelId',
        (tester) async {
      _seed([_chWfL, _chWfR]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      final btn = _outlinedBtnWith('AI로 분석하기');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();

      expect(container.read(workbenchTabProvider), equals(kTabGuidedAi));
      // Full 4-channel path: no single channelId set.
      expect(container.read(guidedAiTargetChannelProvider), isNull);
    });
  });

  // ── C: Per-channel "이 채널 분석" ─────────────────────────────────────────

  group('C. Per-channel "이 채널 분석"', () {
    testWidgets('"이 채널 분석" button visible on FRD channel cards',
        (tester) async {
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      expect(find.text('Expert 단일 채널 분석'), findsNWidgets(2)); // both have FRD
    });

    testWidgets('tapping Woofer L card button sets channelId to ch_wf_l',
        (tester) async {
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      // Woofer L appears first in the list.
      final cardBtn = find.text('Expert 단일 채널 분석').first;
      await tester.ensureVisible(cardBtn);
      await tester.tap(cardBtn);
      await tester.pump();

      expect(container.read(guidedAiTargetChannelProvider), equals('ch_wf_l'));
    });

    testWidgets('tapping card button navigates to kTabGuidedAi',
        (tester) async {
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      final cardBtn = find.text('Expert 단일 채널 분석').first;
      await tester.ensureVisible(cardBtn);
      await tester.tap(cardBtn);
      await tester.pump();

      expect(container.read(workbenchTabProvider), equals(kTabGuidedAi));
    });

    testWidgets('GuidedAiScreen context row shows Woofer L primary FRD filename',
        (tester) async {
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer(overrides: [
        guidedAiProvider.overrideWith(
            (ref) => _FakeGuidedAiController(const ProGuidedAiIdle())),
        guidedAiTargetChannelProvider.overrideWith((ref) => 'ch_wf_l'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_aiScreen(container));
      await tester.pumpAndSettle();

      // Context row must show Woofer L's primary FRD filename, not Tweeter L's.
      expect(find.textContaining('DC130BS-4@0all.frd'), findsAtLeastNWidgets(1));
    });

    testWidgets('GuidedAiScreen context row shows repeat sweep count for Woofer L',
        (tester) async {
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer(overrides: [
        guidedAiProvider.overrideWith(
            (ref) => _FakeGuidedAiController(const ProGuidedAiIdle())),
        guidedAiTargetChannelProvider.overrideWith((ref) => 'ch_wf_l'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_aiScreen(container));
      await tester.pumpAndSettle();

      // Woofer L has 1 repeat sweep → context row shows "스윕 +1".
      expect(find.textContaining('스윕 +1'), findsAtLeastNWidgets(1));
    });

    testWidgets('GuidedAiScreen context row shows Woofer L driver channel label',
        (tester) async {
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer(overrides: [
        guidedAiProvider.overrideWith(
            (ref) => _FakeGuidedAiController(const ProGuidedAiIdle())),
        guidedAiTargetChannelProvider.overrideWith((ref) => 'ch_wf_l'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_aiScreen(container));
      await tester.pumpAndSettle();

      // shortLabel for coaxWoofer·left = "CWF · L"; must not show "CTW · L".
      expect(find.textContaining('CWF · L'), findsAtLeastNWidgets(1));
    });
  });

  // ── D: Invalid / missing channelId ────────────────────────────────────────

  group('D. Invalid / missing channelId', () {
    testWidgets('unknown channelId shows blocked state', (tester) async {
      _seed([_chWfL]);
      final container = ProviderContainer(overrides: [
        guidedAiProvider.overrideWith(
            (ref) => _FakeGuidedAiController(const ProGuidedAiIdle())),
        guidedAiTargetChannelProvider
            .overrideWith((ref) => 'ch_nonexistent'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_aiScreen(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('채널 없음'), findsAtLeastNWidgets(1));
    });

    testWidgets('unknown channelId disables analysis button', (tester) async {
      _seed([_chWfL]);
      final container = ProviderContainer(overrides: [
        guidedAiProvider.overrideWith(
            (ref) => _FakeGuidedAiController(const ProGuidedAiIdle())),
        guidedAiTargetChannelProvider
            .overrideWith((ref) => 'ch_nonexistent'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_aiScreen(container));
      await tester.pumpAndSettle();

      final btns = find.byType(FilledButton);
      if (btns.evaluate().isNotEmpty) {
        final widget = tester.widget<FilledButton>(btns.first);
        expect(widget.onPressed, isNull);
      }
    });

    testWidgets(
        'multiple FRD channels with no channelId shows 4-channel status panel',
        (tester) async {
      // 4-channel default mode: no single-channel selection required.
      // The UI shows the 4-channel FRD status panel instead of a selection prompt.
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer(overrides: [
        guidedAiProvider.overrideWith(
            (ref) => _FakeGuidedAiController(const ProGuidedAiIdle())),
        // No guidedAiTargetChannelProvider override → null.
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_aiScreen(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('4채널 시스템 튜닝'), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'multiple FRD channels with no channelId enables analysis button',
        (tester) async {
      // 4-channel default mode: multiple FRD channels no longer block the button.
      _seed([_chWfL, _chTwL]);
      final container = ProviderContainer(overrides: [
        guidedAiProvider.overrideWith(
            (ref) => _FakeGuidedAiController(const ProGuidedAiIdle())),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_aiScreen(container));
      await tester.pumpAndSettle();

      // Button must be enabled — 4-channel mode allows start with ≥1 FRD.
      final btns = find.byType(FilledButton);
      expect(btns, findsAtLeastNWidgets(1));
      final widget = tester.widget<FilledButton>(btns.first);
      expect(widget.onPressed, isNotNull);
    });
  });

  // ── E: Existing single-FRD navigation still works ────────────────────────

  group('E. Existing Import → Guided AI navigation', () {
    testWidgets('single FRD channel: bottom button is enabled', (tester) async {
      _seed([_chWfL]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      final btn = _outlinedBtnWith('AI로 분석하기');
      expect(btn, findsOneWidget);
      expect(tester.widget<OutlinedButton>(btn).onPressed, isNotNull);
    });

    testWidgets('single FRD channel: navigation goes to Guided AI (null targetChannelId)',
        (tester) async {
      // Global button is 4-channel path; single-channel Expert is via card button.
      _seed([_chWfL]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_importScreen(container));
      await tester.pumpAndSettle();

      final btn = _outlinedBtnWith('AI로 분석하기');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();

      expect(container.read(guidedAiTargetChannelProvider), isNull);
      expect(container.read(workbenchTabProvider), equals(kTabGuidedAi));
    });

    testWidgets('single FRD channel: GuidedAiScreen shows correct FRD filename',
        (tester) async {
      _seed([_chWfL]);
      final container = ProviderContainer(overrides: [
        guidedAiProvider.overrideWith(
            (ref) => _FakeGuidedAiController(const ProGuidedAiIdle())),
        guidedAiTargetChannelProvider.overrideWith((ref) => 'ch_wf_l'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_aiScreen(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('DC130BS-4@0all.frd'), findsAtLeastNWidgets(1));
    });
  });
}
