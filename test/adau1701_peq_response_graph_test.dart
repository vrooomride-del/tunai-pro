import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_peq_response_graph.dart';
import 'package:tunai_pro/features/workbench/widgets/graph_overlay_models.dart';

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

  // ── v3-1: Graph Overlay Foundation ────────────────────────────────────────

  group('v3-1 overlay/difference — API additions', () {
    testWidgets(
        'default single-mode regression: overlayCurves omitted behaves '
        'exactly like before v3-1', (tester) async {
      await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(
        bands: _bands(enabledCount: 3),
        selectedBandIndex: 1,
        baselineBands: _bands(enabledCount: 1),
      )));
      expect(find.byType(Adau1701PeqResponseGraph), findsOneWidget);
      // No mode header is built when overlayCurves is absent.
      expect(find.text('Single'), findsNothing);
      expect(find.text('Overlay'), findsNothing);
      expect(find.text('Difference'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mode defaults to single even if overlayCurves is an empty list',
        (tester) async {
      await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(
        bands: _bands(enabledCount: 2),
        overlayCurves: const [],
        mode: PeqGraphMode.overlay,
      )));
      // Empty overlayCurves list still keeps the graph in its original,
      // header-less single-channel layout.
      expect(find.text('Overlay'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('overlay mode renders 2 named curves with a mode header',
        (tester) async {
      final curves = [
        PeqGraphCurve(label: 'Woofer L', bands: _bands(enabledCount: 2)),
        PeqGraphCurve(label: 'Woofer R', bands: _bands(enabledCount: 4)),
      ];
      await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(
        bands: _bands(enabledCount: 2),
        overlayCurves: curves,
        mode: PeqGraphMode.overlay,
      )));
      expect(find.text('Single'), findsOneWidget);
      expect(find.text('Overlay'), findsOneWidget);
      expect(find.text('Difference'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('difference mode with exactly 2 curves renders without error',
        (tester) async {
      final curves = [
        PeqGraphCurve(label: 'Woofer L', bands: _bands(enabledCount: 3)),
        PeqGraphCurve(label: 'Woofer R', bands: _bands(enabledCount: 1)),
      ];
      await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(
        bands: _bands(enabledCount: 2),
        overlayCurves: curves,
        mode: PeqGraphMode.difference,
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'difference mode with != 2 curves renders grid-only (no crash, no '
        'curve) — insufficient data is not shown', (tester) async {
      final curves = [
        PeqGraphCurve(label: 'Woofer L', bands: _bands(enabledCount: 3)),
      ];
      await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(
        bands: _bands(enabledCount: 2),
        overlayCurves: curves,
        mode: PeqGraphMode.difference,
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a mode button calls onModeChanged with that mode',
        (tester) async {
      PeqGraphMode? tapped;
      final curves = [
        PeqGraphCurve(label: 'A', bands: _bands(enabledCount: 1)),
        PeqGraphCurve(label: 'B', bands: _bands(enabledCount: 2)),
      ];
      await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(
        bands: _bands(enabledCount: 1),
        overlayCurves: curves,
        mode: PeqGraphMode.single,
        onModeChanged: (m) => tapped = m,
      )));
      await tester.tap(find.text('Overlay'));
      await tester.pump();
      expect(tapped, PeqGraphMode.overlay);
    });

    testWidgets('null onModeChanged renders header inertly (no crash on tap)',
        (tester) async {
      final curves = [
        PeqGraphCurve(label: 'A', bands: _bands(enabledCount: 1)),
        PeqGraphCurve(label: 'B', bands: _bands(enabledCount: 2)),
      ];
      await tester.pumpWidget(_wrap(Adau1701PeqResponseGraph(
        bands: _bands(enabledCount: 1),
        overlayCurves: curves,
        mode: PeqGraphMode.overlay,
      )));
      await tester.tap(find.text('Difference'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('v3-1 PeqGraphOverlayMath.difference — pure unit tests', () {
    test('same-length curves: point-wise a - b', () {
      final result = PeqGraphOverlayMath.difference(
          const [1.0, 2.0, 3.0], const [0.5, 0.5, 0.5]);
      expect(result, [0.5, 1.5, 2.5]);
    });

    test('identical curves produce an all-zero difference', () {
      final result =
          PeqGraphOverlayMath.difference(const [3.0, -2.0], const [3.0, -2.0]);
      expect(result, [0.0, 0.0]);
    });

    test('mismatched lengths return null (no difference curve)', () {
      final result =
          PeqGraphOverlayMath.difference(const [1.0, 2.0], const [1.0]);
      expect(result, isNull);
    });

    test('either curve empty returns null', () {
      expect(PeqGraphOverlayMath.difference(const [], const [1.0]), isNull);
      expect(PeqGraphOverlayMath.difference(const [1.0], const []), isNull);
      expect(PeqGraphOverlayMath.difference(const [], const []), isNull);
    });

    test('PeqGraphCurve.curveFor delegates to Adau1701PeqResponse.combinedCurve '
        '(no reimplemented calculation)', () {
      final points = Adau1701PeqResponse.logFrequencyPoints(count: 32);
      final bands = _bands(enabledCount: 3);
      final curve = PeqGraphCurve(label: 'X', bands: bands);
      expect(curve.curveFor(points),
          Adau1701PeqResponse.combinedCurve(bands, points));
    });
  });
}
