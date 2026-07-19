import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_simulation_optimizer.dart';
import 'package:tunai_pro/core/pro_target_curve.dart';
import 'package:tunai_pro/features/workbench/widgets/optimizer_preview_graph.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 480, height: 320, child: child)),
    );

void main() {
  testWidgets('renders target/before/after curves and legend', (tester) async {
    final freqs = ProSimulationOptimizer.previewFrequencies();
    final target = ProTargetCurve.curve(TargetCurvePreset.flat, freqs);
    final before = [for (final f in freqs) (f < 1000) ? 3.0 : -2.0];
    final after = List<double>.filled(freqs.length, 0.0);

    await tester.pumpWidget(_wrap(OptimizerPreviewGraph(
        freqs: freqs, target: target, before: before, after: after)));

    expect(find.byType(OptimizerPreviewGraph), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('OPTIMIZER PREVIEW'), findsOneWidget);
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After (predicted)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles empty/mismatched curves without throwing',
      (tester) async {
    await tester.pumpWidget(_wrap(const OptimizerPreviewGraph(
        freqs: [], target: [], before: [], after: [])));
    expect(tester.takeException(), isNull);
  });
}
