// TUNAI PRO UI/UX v3 Phase V3-3.5 — Shared Current Driver Header.
//
// Covers:
//   - CurrentDriverHeader renders the selected driver's identity
//   - CurrentDriverHeader renders the compare driver when compare is active
//   - fallback to the first driver when the stored channelId is stale/missing
//   - migrated PEQ/XO/Gain/Delay tab controls still work (bypass/reset,
//     polarity, mute/solo, delay step) after the identity block moved into
//     the shared header
//   - mounting the header / switching the selected channel never mutates
//     PeqChannelState/CrossoverChannelState/ChannelControlState

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/channel_compare_provider.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/features/workbench/tabs/delay_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/gain_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/peq_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/xo_tab.dart';
import 'package:tunai_pro/features/workbench/widgets/current_driver_header.dart';

const _kProjectsKey = 'tunai_pro_projects';

const _kChannels = [
  DriverChannel(
      id: 'ch_wf_l', name: 'Woofer L', role: DriverRole.woofer,
      side: DriverSide.left, dspOutputIndex: 1),
  DriverChannel(
      id: 'ch_wf_r', name: 'Woofer R', role: DriverRole.woofer,
      side: DriverSide.right, dspOutputIndex: 2),
];

Widget _headerHost(Widget child, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );

ProProject _project(List<DriverChannel> channels) => ProProject(
      id: 'p1',
      name: 'Current driver header test',
      createdAt: DateTime.utc(2026, 8, 5),
      updatedAt: DateTime.utc(2026, 8, 5),
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: channels),
    );

void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

Widget _tabHost(Widget child) =>
    ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('CurrentDriverHeader — isolated', () {
    testWidgets('renders the selected driver identity', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(channelCompareProvider.notifier).setCurrentChannel('ch_wf_r');

      await tester.pumpWidget(_headerHost(
          const CurrentDriverHeader(drivers: _kChannels), container));
      await tester.pumpAndSettle();

      expect(find.text('CURRENT DRIVER'), findsOneWidget);
      expect(find.text('Woofer R'), findsOneWidget);
      expect(find.textContaining('Woofer · R'), findsOneWidget);
      expect(find.textContaining('Channel 2'), findsOneWidget);
    });

    testWidgets(
        'falls back to the first driver when the stored channelId is '
        'stale/missing', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(channelCompareProvider.notifier)
          .setCurrentChannel('ch_from_another_project');

      await tester.pumpWidget(_headerHost(
          const CurrentDriverHeader(drivers: _kChannels), container));
      await tester.pumpAndSettle();

      expect(find.text('Woofer L'), findsOneWidget);
      expect(find.text('Woofer R'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing when there are no drivers', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
          _headerHost(const CurrentDriverHeader(drivers: []), container));
      await tester.pumpAndSettle();

      expect(find.text('CURRENT DRIVER'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'shows the compare driver name when compare is enabled and the pair '
        'is checked', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.setCurrentChannel('ch_wf_l');
      notifier.setCompareEnabled(true);
      notifier.toggleCompareChannel('ch_wf_r');

      await tester.pumpWidget(_headerHost(
          const CurrentDriverHeader(drivers: _kChannels), container));
      await tester.pumpAndSettle();

      expect(find.text('Compare:'), findsOneWidget);
      expect(find.text('Woofer R'), findsOneWidget);
    });

    testWidgets(
        'omits the compare row when compare is enabled but the pair is not '
        'checked', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.setCurrentChannel('ch_wf_l');
      notifier.setCompareEnabled(true);

      await tester.pumpWidget(_headerHost(
          const CurrentDriverHeader(drivers: _kChannels), container));
      await tester.pumpAndSettle();

      expect(find.text('Compare:'), findsNothing);
    });
  });

  group('Migrated tab controls still work', () {
    testWidgets('PEQ bypass toggle still flips PeqChannelState.bypassed',
        (tester) async {
      _seed(_project(_kChannels));
      await tester.pumpWidget(_tabHost(const PeqTab(projectId: 'p1')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(PeqTab)),
          listen: false);
      bool bypassedOf() => container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1')
          .tuningState
          .peqChannels
          .firstWhere((c) => c.channelId == 'ch_wf_l',
              orElse: () => PeqChannelState.empty('ch_wf_l'))
          .bypassed;

      expect(bypassedOf(), isFalse);
      expect(find.text('CURRENT DRIVER'), findsOneWidget);

      await _tapVisible(tester, find.text('ACTIVE'));
      expect(bypassedOf(), isTrue);
      expect(find.text('BYPASSED'), findsOneWidget);
    });

    testWidgets('XO polarity toggle still flips CrossoverChannelState',
        (tester) async {
      _seed(_project(_kChannels));
      await tester.pumpWidget(_tabHost(const XoTab(projectId: 'p1')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(XoTab)),
          listen: false);
      bool invertedOf() => container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1')
          .tuningState
          .crossoverChannels
          .firstWhere((c) => c.channelId == 'ch_wf_l',
              orElse: () => CrossoverChannelState.empty('ch_wf_l'))
          .polarityInverted;

      expect(invertedOf(), isFalse);
      expect(find.text('CURRENT DRIVER'), findsOneWidget);

      await _tapVisible(tester, find.text('∅ NORMAL'));
      expect(invertedOf(), isTrue);
      expect(find.text('∅ INVERTED'), findsOneWidget);
    });

    testWidgets('Gain mute toggle still flips ChannelControlState.muted',
        (tester) async {
      _seed(_project(_kChannels));
      await tester.pumpWidget(_tabHost(const GainTab(projectId: 'p1')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(GainTab)),
          listen: false);
      bool mutedOf() => container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1')
          .tuningState
          .getOrCreateControl('ch_wf_l')
          .muted;

      expect(mutedOf(), isFalse);
      expect(find.text('CURRENT DRIVER'), findsOneWidget);

      await _tapVisible(tester, find.text('MUTE'));
      expect(mutedOf(), isTrue);
    });

    testWidgets('Delay step buttons still adjust ChannelControlState.delayMs',
        (tester) async {
      _seed(_project(_kChannels));
      await tester.pumpWidget(_tabHost(const DelayTab(projectId: 'p1')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(DelayTab)),
          listen: false);
      double delayOf() => container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1')
          .tuningState
          .getOrCreateControl('ch_wf_l')
          .delayMs;

      expect(delayOf(), 0.0);
      expect(find.text('CURRENT DRIVER'), findsOneWidget);

      await _tapVisible(tester, find.text('+0.10'));
      expect(delayOf(), closeTo(0.10, 1e-9));
    });
  });

  group('No PEQ/XO/Gain/Delay state mutation from the shared header', () {
    testWidgets(
        'mounting PeqTab (with CurrentDriverHeader) and switching the '
        'selected channel never advances tuningRevision', (tester) async {
      _seed(_project(_kChannels));
      await tester.pumpWidget(_tabHost(const PeqTab(projectId: 'p1')));
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

      // Selecting a different channel only moves channelCompareProvider's
      // currentChannelId — must not write PEQ/tuning data.
      await _tapVisible(tester, find.text('Woofer R').first);

      expect(revisionOf(), before,
          reason: 'selecting a channel (and re-rendering CurrentDriverHeader) '
              'must never write PEQ tuning state');
      expect(find.text('Woofer R'), findsWidgets);
    });

    testWidgets(
        'mounting XoTab/GainTab/DelayTab renders CurrentDriverHeader without '
        'touching their respective channel control state', (tester) async {
      _seed(_project(_kChannels));

      await tester.pumpWidget(_tabHost(const XoTab(projectId: 'p1')));
      await tester.pumpAndSettle();
      var container = ProviderScope.containerOf(
          tester.element(find.byType(XoTab)),
          listen: false);
      expect(
          container
              .read(proProjectStoreProvider)
              .projects
              .firstWhere((p) => p.id == 'p1')
              .tuningState
              .crossoverChannels,
          isEmpty,
          reason: 'rendering the header must not create crossover state');

      await tester.pumpWidget(_tabHost(const GainTab(projectId: 'p1')));
      await tester.pumpAndSettle();
      container = ProviderScope.containerOf(
          tester.element(find.byType(GainTab)),
          listen: false);
      expect(
          container
              .read(proProjectStoreProvider)
              .projects
              .firstWhere((p) => p.id == 'p1')
              .tuningState
              .getOrCreateControl('ch_wf_l')
              .gainDb,
          0.0);

      await tester.pumpWidget(_tabHost(const DelayTab(projectId: 'p1')));
      await tester.pumpAndSettle();
      container = ProviderScope.containerOf(
          tester.element(find.byType(DelayTab)),
          listen: false);
      expect(
          container
              .read(proProjectStoreProvider)
              .projects
              .firstWhere((p) => p.id == 'p1')
              .tuningState
              .getOrCreateControl('ch_wf_l')
              .delayMs,
          0.0);
      expect(tester.takeException(), isNull);
    });
  });
}
