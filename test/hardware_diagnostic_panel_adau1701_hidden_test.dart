// Phase 7-2 regression: the ADAU1466 USBi "operational diagnostic" panels in
// delay_tab.dart and xo_tab.dart previously rendered unconditionally,
// regardless of the current project's dspTarget. On a real ADAU1701 project
// (which tunes delay/XO through the ICP5 Deploy path, not USBi) this showed
// an irrelevant "ADAU1466 Operational Delay" / "ADAU1466 XO Hardware
// Mapping" card, including its confusing "last ACK not written" placeholder
// text. Both panels must now only render when dspTarget == 'ADAU1466'.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/features/workbench/tabs/delay_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/gain_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/xo_tab.dart';

const _kProjectsKey = 'tunai_pro_projects';

const _kChannels = [
  DriverChannel(
      id: 'ch_tw_l',
      name: 'Tweeter L',
      role: DriverRole.tweeter,
      side: DriverSide.left,
      dspOutputIndex: 1),
];

ProProject _project(String dspTarget) => ProProject(
      id: 'p1',
      name: 'Panel visibility test',
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      dspTarget: dspTarget,
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: _kChannels),
    );

ProProject _nullTargetProject() => ProProject(
      id: 'p1',
      name: 'No target',
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: _kChannels),
    );

// Seeding SharedPreferences directly (rather than racing the store's own
// async load with a manual addProject call) is the pattern already used by
// other tab-widget tests in this suite (see target_tab_custom_coming_soon_test.dart).
void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

void main() {
  group('Delay tab — ADAU1466 diagnostic panel visibility', () {
    testWidgets('hidden on an ADAU1701 project', (tester) async {
      _seed(_project('ADAU1701'));
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: DelayTab(projectId: 'p1')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ADAU1466 Operational Delay'), findsNothing);
      expect(find.textContaining('not written'), findsNothing);
      // The real ADAU1701 delay editor is still shown.
      expect(find.text('Delay / Alignment'), findsOneWidget);
    });

    testWidgets('shown on an ADAU1466 project as collapsed section',
        (tester) async {
      _seed(_project('ADAU1466'));
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: DelayTab(projectId: 'p1')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ADVANCED HARDWARE DIAGNOSTICS'), findsOneWidget);
      expect(find.text('ADAU1466 Operational Delay'), findsNothing);

      await tester.tap(find.text('ADVANCED HARDWARE DIAGNOSTICS'));
      await tester.pumpAndSettle();
      expect(find.text('ADAU1466 Operational Delay'), findsOneWidget);
    });
  });

  group('XO tab — ADAU1466 diagnostic panel visibility', () {
    testWidgets('hidden on an ADAU1701 project', (tester) async {
      _seed(_project('ADAU1701'));
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: XoTab(projectId: 'p1')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ADAU1466 XO Hardware Mapping'), findsNothing);
      expect(find.textContaining('not written'), findsNothing);
    });

    testWidgets('shown on an ADAU1466 project as collapsed section',
        (tester) async {
      _seed(_project('ADAU1466'));
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: XoTab(projectId: 'p1')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ADVANCED HARDWARE DIAGNOSTICS'), findsOneWidget);
      expect(find.text('ADAU1466 XO Hardware Mapping'), findsNothing);

      await tester.tap(find.text('ADVANCED HARDWARE DIAGNOSTICS'));
      await tester.pumpAndSettle();
      expect(find.text('ADAU1466 XO Hardware Mapping'), findsOneWidget);
    });
  });

  group('Gain tab — ADAU1466 diagnostic panel visibility', () {
    testWidgets('hidden on an ADAU1701 project', (tester) async {
      _seed(_project('ADAU1701'));
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: GainTab(projectId: 'p1')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ADVANCED HARDWARE DIAGNOSTICS'), findsNothing);
      expect(find.text('Operational ADAU1466 Gain Controls'), findsNothing);
      expect(find.text('Gain / Trim'), findsOneWidget);
    });

    testWidgets('hidden when dspTarget is null', (tester) async {
      _seed(_nullTargetProject());
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: GainTab(projectId: 'p1')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ADVANCED HARDWARE DIAGNOSTICS'), findsNothing);
      expect(find.text('Operational ADAU1466 Gain Controls'), findsNothing);
    });

    testWidgets('shown on an ADAU1466 project as collapsed section',
        (tester) async {
      _seed(_project('ADAU1466'));
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: GainTab(projectId: 'p1')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ADVANCED HARDWARE DIAGNOSTICS'), findsOneWidget);
      expect(find.text('Operational ADAU1466 Gain Controls'), findsNothing);
    });

    testWidgets('diagnostic panel accessible after expanding', (tester) async {
      _seed(_project('ADAU1466'));
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: GainTab(projectId: 'p1')),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADVANCED HARDWARE DIAGNOSTICS'));
      await tester.pumpAndSettle();

      expect(find.text('Operational ADAU1466 Gain Controls'), findsOneWidget);
      expect(find.byKey(const Key('adau1466-gain-diagnostics-section')),
          findsOneWidget);
    });
  });
}
