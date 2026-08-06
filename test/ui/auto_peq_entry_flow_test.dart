// ADAU1701 release-closure — Auto PEQ entry-point wiring.
//
// Covers what test/auto_peq_entry_point_test.dart (source-text regression
// guard) cannot: real widget/provider-level behaviour.
//
//   1. AutoPeqTab -> Guided AI keeps the same project selected (structural:
//      WorkbenchShell passes one projectId to every tab, tab switching only
//      changes workbenchTabProvider's index — this pins that down so a
//      future refactor can't quietly break it).
//   2. The 4-channel FRD gate reflects true readiness, not "any FRD parsed":
//      missing channels are named, and the entry action is disabled until
//      all four are present.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/features/ai/guided_ai_screen.dart';
import 'package:tunai_pro/features/workbench/tabs/auto_peq_tab.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';

const _kProjectsKey = 'tunai_pro_projects';
const _kProjectId = 'release-closure-proj';

DriverChannel _channelWithFrd(String id, DriverRole role, DriverSide side) =>
    DriverChannel(
      id: id,
      name: id,
      role: role,
      side: side,
      frdData: ParsedMeasurementData(
        id: '$id-frd',
        sourceFileName: '$id.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2025, 1, 1),
        points: const [
          MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 85.0),
        ],
      ),
    );

DriverChannel _channelWithoutFrd(String id, DriverRole role, DriverSide side) =>
    DriverChannel(id: id, name: id, role: role, side: side);

ProProject _fourChannelReadyProject() => ProProject(
      id: _kProjectId,
      name: 'Release Closure Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      acousticState: MeasurementProjectState(driverChannels: [
        _channelWithFrd('ch_tw_l', DriverRole.tweeter, DriverSide.left),
        _channelWithFrd('ch_wf_l', DriverRole.woofer, DriverSide.left),
        _channelWithFrd('ch_tw_r', DriverRole.tweeter, DriverSide.right),
        _channelWithFrd('ch_wf_r', DriverRole.woofer, DriverSide.right),
      ]),
    );

ProProject _partialProject() => ProProject(
      id: _kProjectId,
      name: 'Release Closure Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      acousticState: MeasurementProjectState(driverChannels: [
        _channelWithFrd('ch_tw_l', DriverRole.tweeter, DriverSide.left),
        _channelWithFrd('ch_wf_l', DriverRole.woofer, DriverSide.left),
        // ch_tw_r imported but no FRD parsed yet; ch_wf_r never imported.
        _channelWithoutFrd('ch_tw_r', DriverRole.tweeter, DriverSide.right),
      ]),
    );

void _seedProject(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AutoPeqTab -> Guided AI project continuity', () {
    testWidgets(
        'tapping the entry action switches to Guided AI without losing '
        'the selected project', (tester) async {
      _seedProject(_fourChannelReadyProject());
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: WorkbenchShell(projectId: _kProjectId)),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Auto PEQ'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Auto PEQ'));
      await tester.pumpAndSettle();

      final autoPeqTab = tester.widget<AutoPeqTab>(find.byType(AutoPeqTab));
      expect(autoPeqTab.projectId, _kProjectId);

      await tester.ensureVisible(find.text('Guided AI에서 실행'));
      await tester.pump();
      await tester.tap(find.text('Guided AI에서 실행'));
      await tester.pumpAndSettle();

      // Same shell, same projectId — GuidedAiScreen now visible for the
      // exact project AutoPeqTab was showing, not a different/default one.
      expect(find.byType(GuidedAiScreen), findsOneWidget);
      final guidedAi =
          tester.widget<GuidedAiScreen>(find.byType(GuidedAiScreen));
      expect(guidedAi.projectId, _kProjectId);
      expect(find.text('Release Closure Project'), findsAtLeastNWidgets(1));
    });

    testWidgets('workbenchTabProvider index changes; projectId does not',
        (tester) async {
      _seedProject(_fourChannelReadyProject());
      int? lastTabIndex;
      await tester.pumpWidget(ProviderScope(
        child: Consumer(builder: (context, ref, _) {
          ref.listen<int>(workbenchTabProvider, (_, v) => lastTabIndex = v);
          return const MaterialApp(
              home: WorkbenchShell(projectId: _kProjectId));
        }),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Auto PEQ'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Auto PEQ'));
      await tester.pumpAndSettle();
      expect(lastTabIndex, kTabAutoPeq);

      await tester.ensureVisible(find.text('Guided AI에서 실행'));
      await tester.pump();
      await tester.tap(find.text('Guided AI에서 실행'));
      await tester.pumpAndSettle();
      expect(lastTabIndex, kTabGuidedAi);

      // The shell itself was never rebuilt with a different projectId —
      // there is only one WorkbenchShell instance in this tree.
      expect(find.byType(WorkbenchShell), findsOneWidget);
      expect(
          tester.widget<WorkbenchShell>(find.byType(WorkbenchShell)).projectId,
          _kProjectId);
    });
  });

  group('AutoPeqTab 4-channel FRD readiness gate', () {
    testWidgets(
        'all 4 channels ready -> entry action enabled, no missing '
        'channel list', (tester) async {
      _seedProject(_fourChannelReadyProject());
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: AutoPeqTab(projectId: _kProjectId)),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('4/4'), findsOneWidget);
      expect(find.textContaining('FRD 없음'), findsNothing);
      final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Guided AI에서 실행'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ));
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
        'partial FRD -> entry action disabled and the exact missing '
        'channels are named', (tester) async {
      _seedProject(_partialProject());
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: AutoPeqTab(projectId: _kProjectId)),
      ));
      await tester.pumpAndSettle();

      // ch_tw_l / ch_wf_l ready; ch_tw_r (no FRD) / ch_wf_r (not imported)
      // missing — must show 2/4, not "any FRD parsed" style readiness.
      expect(find.textContaining('2/4'), findsOneWidget);
      expect(find.textContaining('FRD 없음'), findsWidgets);

      final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Guided AI에서 실행'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ));
      expect(button.onPressed, isNull,
          reason: 'must not offer to enter Guided AI until all 4 required '
              'channels have parsed FRD');
    });

    testWidgets('no project selected -> not ready, action disabled',
        (tester) async {
      // Empty store: AutoPeqTab is given a projectId that resolves to null.
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: AutoPeqTab(projectId: 'unknown-project')),
      ));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Guided AI에서 실행'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ));
      expect(button.onPressed, isNull);
    });
  });
}
