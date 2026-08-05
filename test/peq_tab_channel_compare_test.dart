// TUNAI PRO UI/UX v3 Phase V3-2 — Channel Compare Layer.
//
// Widget tests for peq_tab.dart's Compare section:
//   - compare OFF: identical to pre-v3-2 single-channel graph (regression)
//   - compare ON + pair checked: overlayCurves passed to the v3-1 graph,
//     [Single][Overlay][Difference] header + Channel Match readout shown
//   - no same-role/opposite-side pair -> Compare section absent
//   - PEQ write/export path unaffected: tuningRevision only advances on
//     explicit band edits, never from toggling compare UI state

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/features/workbench/tabs/peq_tab.dart';

const _kProjectsKey = 'tunai_pro_projects';

const _kStereoChannels = [
  DriverChannel(
      id: 'ch_wf_l', name: 'Woofer L', role: DriverRole.woofer,
      side: DriverSide.left, dspOutputIndex: 1),
  DriverChannel(
      id: 'ch_wf_r', name: 'Woofer R', role: DriverRole.woofer,
      side: DriverSide.right, dspOutputIndex: 2),
];

const _kMonoChannel = [
  DriverChannel(
      id: 'ch_sw', name: 'Subwoofer', role: DriverRole.subwoofer,
      side: DriverSide.mono, dspOutputIndex: 1),
];

ProProject _project(List<DriverChannel> channels, {TuningProjectState? tuning}) =>
    ProProject(
      id: 'p1',
      name: 'Channel compare test',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: channels),
      tuningState: tuning ?? TuningProjectState.createDefault(),
    );

void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

Widget _host(String projectId) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: PeqTab(projectId: projectId)),
      ),
    );

/// The PEQ editor content is a SingleChildScrollView taller than the default
/// test viewport — scroll a target into view before tapping it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Compare section visibility', () {
    testWidgets('shown when the selected channel has a role+side pair',
        (tester) async {
      _seed(_project(_kStereoChannels));
      await tester.pumpWidget(_host('p1'));
      await tester.pumpAndSettle();

      expect(find.text('Compare'), findsOneWidget);
      expect(find.text('Woofer R'), findsWidgets); // channel list + checkbox
    });

    testWidgets('absent for a mono channel with no pair', (tester) async {
      _seed(_project(_kMonoChannel));
      await tester.pumpWidget(_host('p1'));
      await tester.pumpAndSettle();

      expect(find.text('Compare'), findsNothing);
    });
  });

  group('Compare OFF — regression: identical to pre-v3-2 single graph', () {
    testWidgets('no overlay header, no Channel Match readout', (tester) async {
      _seed(_project(_kStereoChannels));
      await tester.pumpWidget(_host('p1'));
      await tester.pumpAndSettle();

      // Compare defaults to OFF.
      expect(find.text('OFF'), findsOneWidget);
      expect(find.text('Single'), findsNothing);
      expect(find.text('Overlay'), findsNothing);
      expect(find.text('Difference'), findsNothing);
      expect(find.textContaining('Channel Match'), findsNothing);
      expect(find.textContaining('Difference:'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Compare ON + pair checked — overlay curves reach the v3-1 graph', () {
    testWidgets(
        'checking the pair shows the graph mode header and a Channel Match '
        'readout', (tester) async {
      _seed(_project(_kStereoChannels));
      await tester.pumpWidget(_host('p1'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('OFF'));
      expect(find.text('ON'), findsOneWidget);

      // Check the pair (Woofer R) checkbox.
      await _tapVisible(tester, find.text('Woofer R').last);

      // The v3-1 graph's own [Single][Overlay][Difference] header appears
      // once overlayCurves is non-empty.
      expect(find.text('Single'), findsOneWidget);
      expect(find.text('Overlay'), findsOneWidget);
      expect(find.text('Difference'), findsOneWidget);

      // Identical bands on both channels -> Channel Match: Excellent, 0.0dB.
      expect(find.textContaining('Channel Match'), findsOneWidget);
      expect(find.textContaining('Excellent'), findsOneWidget);
      expect(find.textContaining('Difference: 0.0dB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping Difference switches the graph mode without error',
        (tester) async {
      _seed(_project(_kStereoChannels));
      await tester.pumpWidget(_host('p1'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('OFF'));
      await _tapVisible(tester, find.text('Woofer R').last);

      await _tapVisible(tester, find.text('Difference'));
      expect(tester.takeException(), isNull);
    });
  });

  group('No unintended PEQ write/export impact', () {
    testWidgets(
        'toggling Compare ON/OFF and checking the pair channel never '
        'advances tuningRevision (no PEQ write triggered)', (tester) async {
      final tuning = TuningProjectState.createDefault();
      _seed(_project(_kStereoChannels, tuning: tuning));
      await tester.pumpWidget(_host('p1'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(PeqTab)),
          listen: false);
      int revisionOf() => container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1')
          .tuningState
          .tuningRevision;
      final before = revisionOf();

      await _tapVisible(tester, find.text('OFF'));
      await _tapVisible(tester, find.text('Woofer R').last);
      await _tapVisible(tester, find.text('Difference'));

      expect(revisionOf(), before,
          reason: 'compare UI interactions must never write PEQ tuning state');
    });
  });
}
