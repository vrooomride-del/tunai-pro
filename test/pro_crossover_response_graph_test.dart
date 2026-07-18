import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/features/workbench/widgets/pro_crossover_response_graph.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 480, height: 260, child: child)),
    );

XoGraphChannel _tweeter() => XoGraphChannel(
      label: 'Tweeter',
      role: DriverRole.tweeter,
      selected: true,
      channel: const CrossoverChannelState(channelId: 'tw').copyWith(
        highPass: const CrossoverFilter(
            side: FilterSide.highPass,
            type: CrossoverFilterType.linkwitzRiley,
            slope: CrossoverSlope.db24,
            frequencyHz: 2500),
      ),
    );

XoGraphChannel _woofer() => XoGraphChannel(
      label: 'Woofer',
      role: DriverRole.woofer,
      channel: const CrossoverChannelState(channelId: 'wf').copyWith(
        lowPass: const CrossoverFilter(
            side: FilterSide.lowPass,
            type: CrossoverFilterType.linkwitzRiley,
            slope: CrossoverSlope.db24,
            frequencyHz: 2500),
      ),
    );

void main() {
  testWidgets('renders with no channels (empty project)', (tester) async {
    await tester
        .pumpWidget(_wrap(const ProCrossoverResponseGraph(channels: [])));
    expect(find.byType(ProCrossoverResponseGraph), findsOneWidget);
    // Magnitude + phase panels both present.
    expect(find.text('MAGNITUDE (dB)'), findsOneWidget);
    expect(find.textContaining('PHASE (°)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders woofer + tweeter (+ summed) magnitude and phase',
      (tester) async {
    await tester.pumpWidget(_wrap(
        ProCrossoverResponseGraph(channels: [_woofer(), _tweeter()])));
    expect(find.byType(ProCrossoverResponseGraph), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.textContaining('PHASE (°)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders with a per-driver delay applied (phase sim)',
      (tester) async {
    final delayedWoofer = XoGraphChannel(
      label: 'Woofer',
      role: DriverRole.woofer,
      delayMs: 0.5,
      channel: const CrossoverChannelState(channelId: 'wf').copyWith(
        lowPass: const CrossoverFilter(
            side: FilterSide.lowPass,
            type: CrossoverFilterType.linkwitzRiley,
            slope: CrossoverSlope.db24,
            frequencyHz: 2500),
      ),
    );
    await tester.pumpWidget(_wrap(
        ProCrossoverResponseGraph(channels: [delayedWoofer, _tweeter()])));
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates when channels change (repaint)', (tester) async {
    await tester
        .pumpWidget(_wrap(ProCrossoverResponseGraph(channels: [_woofer()])));
    await tester.pumpWidget(_wrap(
        ProCrossoverResponseGraph(channels: [_woofer(), _tweeter()])));
    expect(tester.takeException(), isNull);
  });
}
