import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_peq_response_graph.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, height: 220, child: child)),
    );

List<PeqResponseBand> _bands({required int enabledCount}) => [
      for (var i = 0; i < 10; i++)
        PeqResponseBand(
          frequencyHz: 100.0 * (i + 1),
          gainDb: 4,
          q: 2,
          enabled: i < enabledCount,
        ),
    ];

void main() {
  testWidgets('renders with 0 active bands', (tester) async {
    await tester.pumpWidget(
        _wrap(Adau1701PeqResponseGraph(bands: _bands(enabledCount: 0))));
    expect(find.byType(Adau1701PeqResponseGraph), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders with 1 active band and a highlighted selection',
      (tester) async {
    await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(
      bands: _bands(enabledCount: 1),
      selectedBandIndex: 0,
    )));
    expect(find.byType(Adau1701PeqResponseGraph), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders with multiple active bands + baseline curve',
      (tester) async {
    await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(
      bands: _bands(enabledCount: 5),
      selectedBandIndex: 2,
      baselineBands: _bands(enabledCount: 1),
    )));
    expect(find.byType(Adau1701PeqResponseGraph), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates when the band list changes (repaint)', (tester) async {
    await tester.pumpWidget(
        _wrap(Adau1701PeqResponseGraph(bands: _bands(enabledCount: 1))));
    await tester.pumpWidget(
        _wrap(Adau1701PeqResponseGraph(bands: _bands(enabledCount: 4))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders with a large-boost band (auto-scales to ±12) and with '
      'autoScale disabled', (tester) async {
    final big = [
      const PeqResponseBand(
          frequencyHz: 1000, gainDb: 3, q: 6, enabled: true),
      const PeqResponseBand(
          frequencyHz: 1000, gainDb: 3, q: 6, enabled: true),
      const PeqResponseBand(
          frequencyHz: 1000, gainDb: 3, q: 6, enabled: true),
      const PeqResponseBand(
          frequencyHz: 1000, gainDb: 3, q: 6, enabled: true),
    ];
    await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(bands: big)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
        _wrap(Adau1701PeqResponseGraph(bands: big, autoScale: false)));
    expect(tester.takeException(), isNull);
  });
}
