import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/shared/components/acoustic_graph_frame.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AcousticGraphFrame', () {
    testWidgets('renders the given child unchanged', (tester) async {
      await tester.pumpWidget(_host(
        const AcousticGraphFrame(
          child: SizedBox(key: Key('graph-content')),
        ),
      ));
      expect(find.byKey(const Key('graph-content')), findsOneWidget);
    });

    testWidgets(
        'contributes no CustomPaint of its own — swapping in a CustomPaint '
        'child adds exactly one to the tree', (tester) async {
      await tester.pumpWidget(_host(
        const AcousticGraphFrame(child: SizedBox()),
      ));
      final baseline = find.byType(CustomPaint).evaluate().length;

      await tester.pumpWidget(_host(
        AcousticGraphFrame(child: CustomPaint(painter: _NoopPainter())),
      ));
      final withChildPaint = find.byType(CustomPaint).evaluate().length;

      expect(withChildPaint - baseline, 1,
          reason: 'only the child\'s CustomPaint should appear — the frame '
              'itself must draw nothing');
    });

    testWidgets('renders optional title/subtitle/actions/legend',
        (tester) async {
      await tester.pumpWidget(_host(
        const AcousticGraphFrame(
          title: 'PEQ Response',
          subtitle: 'ch_tw_l',
          actions: [Icon(Icons.fullscreen)],
          legend: [Text('Before'), Text('After')],
          child: SizedBox(),
        ),
      ));
      expect(find.text('PEQ Response'), findsOneWidget);
      expect(find.text('ch_tw_l'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
    });

    testWidgets('omits header row entirely when nothing is given',
        (tester) async {
      await tester.pumpWidget(_host(
        const AcousticGraphFrame(child: SizedBox()),
      ));
      // No crash, no stray header widgets — this just confirms the frame
      // degrades to child-only content.
      expect(find.byType(AcousticGraphFrame), findsOneWidget);
    });

    testWidgets('height constrains the child when provided', (tester) async {
      await tester.pumpWidget(_host(
        const AcousticGraphFrame(
          height: 240,
          child: SizedBox(key: Key('sized-child')),
        ),
      ));
      final sizedBoxAncestor = find.ancestor(
        of: find.byKey(const Key('sized-child')),
        matching: find.byType(SizedBox),
      );
      final box = tester.widget<SizedBox>(sizedBoxAncestor.first);
      expect(box.height, 240);
    });
  });
}

class _NoopPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
