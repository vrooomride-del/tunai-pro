// TUNAI PRO UI/UX v3 Phase V3-3 — Shared Channel Context Implementation.
//
// PEQ/XO/Gain/Delay tabs previously each tracked their own private, local
// `_selectedChannelId` — switching tabs never preserved the selected
// channel. All four now source their selection from
// channelCompareProvider.currentChannelId (channel_compare_provider.dart)
// via resolveSelectedChannelId, with the exact pre-v3-3 fallback
// (`drivers.first.id`) preserved for an unset/invalid selection.
//
// Each tab body is fully disposed and recreated on "tab switch" here (not
// kept alive via IndexedStack) — that's the actual proof the selection lives
// in the shared provider, not in any tab's own State object.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/features/workbench/tabs/delay_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/gain_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/peq_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/xo_tab.dart';
import 'package:tunai_pro/shared/components/channel_selector_sidebar.dart';

const _kProjectsKey = 'tunai_pro_projects';

const _kStereoChannels = [
  DriverChannel(
      id: 'ch_wf_l', name: 'Woofer L', role: DriverRole.woofer,
      side: DriverSide.left, dspOutputIndex: 1),
  DriverChannel(
      id: 'ch_wf_r', name: 'Woofer R', role: DriverRole.woofer,
      side: DriverSide.right, dspOutputIndex: 2),
];

const _kOtherProjectChannels = [
  DriverChannel(
      id: 'ch_tw_l', name: 'Tweeter L', role: DriverRole.tweeter,
      side: DriverSide.left, dspOutputIndex: 1),
  DriverChannel(
      id: 'ch_tw_r', name: 'Tweeter R', role: DriverRole.tweeter,
      side: DriverSide.right, dspOutputIndex: 2),
];

ProProject _project(String id, List<DriverChannel> channels) => ProProject(
      id: id,
      name: 'Shared channel context test $id',
      createdAt: DateTime.utc(2026, 8, 5),
      updatedAt: DateTime.utc(2026, 8, 5),
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: channels),
    );

void _seed(List<ProProject> projects) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList(projects),
  });
}

ChannelSelectorSidebar _sidebarIn(WidgetTester tester, Type tabType) =>
    tester.widget<ChannelSelectorSidebar>(find.descendant(
        of: find.byType(tabType), matching: find.byType(ChannelSelectorSidebar)));

/// Recreates (not IndexedStack-preserves) whichever tab body `index` points
/// to — proves the selection survives a tab widget being fully disposed and
/// a new one constructed, i.e. that it truly lives in the shared provider.
class _TabSwitcher extends StatefulWidget {
  final String projectId;
  const _TabSwitcher(this.projectId);

  @override
  State<_TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<_TabSwitcher> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          TextButton(
              onPressed: () => setState(() => _index = 0),
              child: const Text('GOTO_PEQ')),
          TextButton(
              onPressed: () => setState(() => _index = 1),
              child: const Text('GOTO_XO')),
          TextButton(
              onPressed: () => setState(() => _index = 2),
              child: const Text('GOTO_GAIN')),
          TextButton(
              onPressed: () => setState(() => _index = 3),
              child: const Text('GOTO_DELAY')),
        ]),
        Expanded(
          child: switch (_index) {
            0 => PeqTab(projectId: widget.projectId),
            1 => XoTab(projectId: widget.projectId),
            2 => GainTab(projectId: widget.projectId),
            _ => DelayTab(projectId: widget.projectId),
          },
        ),
      ]);
}

class _ProjectSwitcher extends StatefulWidget {
  final String initialProjectId;
  final String otherProjectId;
  const _ProjectSwitcher(
      {required this.initialProjectId, required this.otherProjectId});

  @override
  State<_ProjectSwitcher> createState() => _ProjectSwitcherState();
}

class _ProjectSwitcherState extends State<_ProjectSwitcher> {
  late String _projectId = widget.initialProjectId;

  @override
  Widget build(BuildContext context) => Column(children: [
        TextButton(
            onPressed: () => setState(() => _projectId = widget.otherProjectId),
            child: const Text('SWITCH_PROJECT')),
        Expanded(child: PeqTab(projectId: _projectId)),
      ]);
}

Widget _host(Widget child) =>
    ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

void main() {
  group('Selection persists across tabs (shared provider, not local state)', () {
    testWidgets('selecting a channel in PEQ persists when opening XO',
        (tester) async {
      _seed([_project('p1', _kStereoChannels)]);
      await tester.pumpWidget(_host(const _TabSwitcher('p1')));
      await tester.pumpAndSettle();

      // Default fallback: first driver.
      expect(_sidebarIn(tester, PeqTab).selectedId, 'ch_wf_l');

      await tester.tap(find.text('Woofer R').last);
      await tester.pumpAndSettle();
      expect(_sidebarIn(tester, PeqTab).selectedId, 'ch_wf_r');

      await tester.tap(find.text('GOTO_XO'));
      await tester.pumpAndSettle();

      expect(_sidebarIn(tester, XoTab).selectedId, 'ch_wf_r',
          reason: 'XO tab must show the channel selected in PEQ, not its own '
              'fallback to drivers.first');
    });

    testWidgets('selecting a channel in XO persists when opening Gain',
        (tester) async {
      _seed([_project('p1', _kStereoChannels)]);
      await tester.pumpWidget(_host(const _TabSwitcher('p1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GOTO_XO'));
      await tester.pumpAndSettle();
      expect(_sidebarIn(tester, XoTab).selectedId, 'ch_wf_l');

      await tester.tap(find.text('Woofer R').last);
      await tester.pumpAndSettle();
      expect(_sidebarIn(tester, XoTab).selectedId, 'ch_wf_r');

      await tester.tap(find.text('GOTO_GAIN'));
      await tester.pumpAndSettle();

      expect(_sidebarIn(tester, GainTab).selectedId, 'ch_wf_r');
    });

    testWidgets('selecting a channel in Gain persists when opening Delay',
        (tester) async {
      _seed([_project('p1', _kStereoChannels)]);
      await tester.pumpWidget(_host(const _TabSwitcher('p1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GOTO_GAIN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Woofer R').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('GOTO_DELAY'));
      await tester.pumpAndSettle();

      expect(_sidebarIn(tester, DelayTab).selectedId, 'ch_wf_r');
    });
  });

  group('Fallback when selected channel missing', () {
    testWidgets('no selection yet -> every tab falls back to drivers.first',
        (tester) async {
      _seed([_project('p1', _kStereoChannels)]);
      await tester.pumpWidget(_host(const _TabSwitcher('p1')));
      await tester.pumpAndSettle();
      expect(_sidebarIn(tester, PeqTab).selectedId, 'ch_wf_l');

      await tester.tap(find.text('GOTO_XO'));
      await tester.pumpAndSettle();
      expect(_sidebarIn(tester, XoTab).selectedId, 'ch_wf_l');

      await tester.tap(find.text('GOTO_GAIN'));
      await tester.pumpAndSettle();
      expect(_sidebarIn(tester, GainTab).selectedId, 'ch_wf_l');

      await tester.tap(find.text('GOTO_DELAY'));
      await tester.pumpAndSettle();
      expect(_sidebarIn(tester, DelayTab).selectedId, 'ch_wf_l');
    });
  });

  group('Project change resets an invalid channel', () {
    testWidgets(
        'switching to a project without the previously-selected channel id '
        'falls back cleanly instead of showing a stale/missing channel',
        (tester) async {
      _seed([
        _project('p1', _kStereoChannels),
        _project('p2', _kOtherProjectChannels),
      ]);
      await tester.pumpWidget(_host(
          const _ProjectSwitcher(initialProjectId: 'p1', otherProjectId: 'p2')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Woofer R').last);
      await tester.pumpAndSettle();
      expect(_sidebarIn(tester, PeqTab).selectedId, 'ch_wf_r');

      await tester.tap(find.text('SWITCH_PROJECT'));
      await tester.pumpAndSettle();

      // p2 has no ch_wf_r — must fall back to p2's own first driver, not
      // crash, and not silently keep pointing at a nonexistent channel.
      expect(_sidebarIn(tester, PeqTab).selectedId, 'ch_tw_l');
      expect(find.text('Woofer R'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
