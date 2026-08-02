import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/shared/components/stat_chip.dart';
import 'package:tunai_pro/shared/design/pro_tokens.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ProStatChip', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_host(
        const ProStatChip(label: 'PEQ BANDS', value: '10'),
      ));
      expect(find.text('PEQ BANDS'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('applies valueColor and renders an optional icon',
        (tester) async {
      await tester.pumpWidget(_host(
        const ProStatChip(
          label: 'Status',
          value: 'OK',
          valueColor: ProColors.green,
          icon: Icons.check_circle_outline,
        ),
      ));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      final text = tester.widget<Text>(find.text('OK'));
      expect(text.style?.color, ProColors.green);
    });
  });
}
