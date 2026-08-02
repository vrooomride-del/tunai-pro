import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/shared/components/info_row.dart';
import 'package:tunai_pro/shared/design/pro_tokens.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ProInfoRow', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_host(
        const ProInfoRow(label: 'DSP Target', value: 'ADAU1701'),
      ));
      expect(find.text('DSP Target'), findsOneWidget);
      expect(find.text('ADAU1701'), findsOneWidget);
    });

    testWidgets('applies valueColor to the value text', (tester) async {
      await tester.pumpWidget(_host(
        const ProInfoRow(
            label: 'Safety', value: 'Verified', valueColor: ProColors.green),
      ));
      final text = tester.widget<Text>(find.text('Verified'));
      expect(text.style?.color, ProColors.green);
    });

    testWidgets('renders an optional leading value icon', (tester) async {
      await tester.pumpWidget(_host(
        const ProInfoRow(
            label: 'Connection',
            value: 'Connected',
            icon: Icons.check_circle_outline),
      ));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets(
        'a long label and a long value in a narrow row do not overflow',
        (tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(
          width: 220,
          child: ProInfoRow(
            label: 'Factory Profile',
            value:
                'Not eligible: measurement confidence is insufficient for this channel configuration',
          ),
        ),
      ));
      // A RenderFlex overflow surfaces as an uncaught FlutterError during
      // layout — this only passes if both label and value are properly
      // constrained (Expanded + ellipsis), not left to their natural width.
      expect(tester.takeException(), isNull);
    });
  });
}
