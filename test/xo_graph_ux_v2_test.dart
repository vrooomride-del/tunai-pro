// TUNAI PRO UI/UX v3 Phase V3-4 — XO Graph UX v2.
//
// Presentation-layer additions only:
//   - "CROSSOVER" summary card (per-filter role/side/freq/type/slope) in
//     xo_tab.dart, reusing ProSectionHeader/ProStatChip.
//   - "Crossover Alignment" quality readout, reusing XoAlignmentStatus's
//     existing GOOD/CHECK/MISALIGN classification (display only, mapped to
//     friendlier wording locally — no change to the enum or algorithm).
//   - ProCrossoverResponseGraph: emphasized summed-response curve/legend,
//     stronger selected-driver highlighting, and a crossover-frequency
//     marker drawn from the already-public XoAlignmentPair.crossoverHz.
//   - "PHASE (°) — simulation preview" renamed to "PHASE ALIGNMENT (°)".
//
// None of CrossoverResponse, CrossoverPhase, or XoPhaseAlignment's
// computations were touched — these tests confirm the UI reads their output
// correctly and that no tuning/export/deploy state is mutated by the new
// cards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/features/workbench/tabs/xo_tab.dart';
import 'package:tunai_pro/features/workbench/widgets/pro_crossover_response_graph.dart';

const _kProjectsKey = 'tunai_pro_projects';

const _kChannels = [
  DriverChannel(
      id: 'ch_wf_l', name: 'Woofer L', role: DriverRole.woofer,
      side: DriverSide.left, dspOutputIndex: 1),
  DriverChannel(
      id: 'ch_tw_l', name: 'Tweeter L', role: DriverRole.tweeter,
      side: DriverSide.left, dspOutputIndex: 2),
];

// Woofer LPF and Tweeter HPF at the same frequency/slope/type, zero delay
// and zero phase offset on both — an in-phase, well-aligned crossover pair
// (GOOD / "Excellent" once mapped for display).
TuningProjectState _tuningWithCrossovers() =>
    TuningProjectState.createDefault().copyWith(crossoverChannels: [
      const CrossoverChannelState(channelId: 'ch_wf_l').copyWith(
        lowPass: const CrossoverFilter(
            side: FilterSide.lowPass,
            type: CrossoverFilterType.linkwitzRiley,
            slope: CrossoverSlope.db24,
            frequencyHz: 2500),
      ),
      const CrossoverChannelState(channelId: 'ch_tw_l').copyWith(
        highPass: const CrossoverFilter(
            side: FilterSide.highPass,
            type: CrossoverFilterType.linkwitzRiley,
            slope: CrossoverSlope.db24,
            frequencyHz: 2500),
      ),
    ]);

ProProject _project() => ProProject(
      id: 'p1',
      name: 'XO v2 test',
      createdAt: DateTime.utc(2026, 8, 5),
      updatedAt: DateTime.utc(2026, 8, 5),
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: _kChannels),
      tuningState: _tuningWithCrossovers(),
    );

void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

Widget _host() => const ProviderScope(
      child: MaterialApp(home: Scaffold(body: XoTab(projectId: 'p1'))),
    );

void main() {
  group('XO Graph UX v2', () {
    testWidgets('XO summary card renders per-filter role/freq/type/slope',
        (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('CROSSOVER'), findsOneWidget);
      expect(find.text('Woofer LPF'), findsOneWidget);
      expect(find.text('Tweeter HPF'), findsOneWidget);
      expect(find.textContaining('2.5 kHz'), findsWidgets);
      expect(find.textContaining('LR24'), findsWidgets);
    });

    testWidgets('summed response is passed to and rendered by the graph',
        (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // The "SUMMED RESPONSE" legend text is canvas-drawn inside the
      // CustomPainter (not a separate Text widget), so this asserts the
      // graph mounts and paints with the new emphasis/marker logic without
      // throwing, rather than searching canvas-drawn text.
      expect(find.byType(ProCrossoverResponseGraph), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'alignment status renders as a friendly label (Excellent for an '
        'in-phase pair)', (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Crossover Alignment'), findsOneWidget);
      // Both _XoAlignmentQualityCard and _AlignmentRow now use friendly
      // labels — expect at least one "Excellent" (may be two if the phase
      // alignment row is also in-phase).
      expect(find.text('Excellent'), findsWidgets);
    });

    testWidgets(
        'alignment quality card shows the empty-state message when no '
        'crossover pair exists', (tester) async {
      final project = _project().copyWith(
        tuningState: TuningProjectState.createDefault(),
      );
      _seed(project);
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Crossover Alignment'), findsOneWidget);
      expect(find.text('No overlapping crossover to analyze'), findsOneWidget);
      expect(find.text('Excellent'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'existing XO graph regression: magnitude + renamed phase panels '
        'still render, no "simulation preview" wording remains',
        (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('MAGNITUDE (dB)'), findsOneWidget);
      // The graph panel's own label (exact match) — distinct from the
      // pre-existing, untouched _PhaseAlignmentCard title which also reads
      // "PHASE ALIGNMENT".
      expect(find.text('PHASE ALIGNMENT (°)'), findsOneWidget);
      expect(find.textContaining('simulation preview'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'no tuning/export/deploy state mutation from the new summary/quality '
        'cards or from selecting a different channel', (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(XoTab)),
          listen: false);
      TuningProjectState tuningOf() => container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1')
          .tuningState;

      final before = tuningOf();

      // Selecting a different channel should only move the shared selection
      // provider — never write crossoverChannels/tuningRevision.
      await tester.tap(find.text('Tweeter L').first);
      await tester.pumpAndSettle();

      final after = tuningOf();
      expect(after.tuningRevision, before.tuningRevision,
          reason: 'rendering the new CROSSOVER summary/quality cards and '
              'switching channels must never write tuning state');
      expect(after.crossoverChannels, before.crossoverChannels);
    });

    testWidgets(
        'existing bypass/polarity edit controls still work end-to-end after '
        'the new cards were inserted above them', (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
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
          .firstWhere((c) => c.channelId == 'ch_wf_l')
          .polarityInverted;

      expect(invertedOf(), isFalse);

      final toggle = find.text('∅ NORMAL');
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(invertedOf(), isTrue);
      expect(find.text('∅ INVERTED'), findsOneWidget);
    });
  });
}
