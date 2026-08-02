import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/shared/components/section_header.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ProSectionHeader', () {
    testWidgets('renders title only by default', (tester) async {
      await tester.pumpWidget(_host(
        const ProSectionHeader(title: 'Deploy Readiness'),
      ));
      expect(find.text('Deploy Readiness'), findsOneWidget);
    });

    testWidgets('does not force uppercase — renders text verbatim',
        (tester) async {
      await tester.pumpWidget(_host(
        const ProSectionHeader(title: 'Deploy readiness'),
      ));
      expect(find.text('Deploy readiness'), findsOneWidget);
      expect(find.text('DEPLOY READINESS'), findsNothing);
    });

    testWidgets('renders optional icon, subtitle, and trailing',
        (tester) async {
      await tester.pumpWidget(_host(
        const ProSectionHeader(
          title: 'PEQ',
          icon: Icons.tune_outlined,
          subtitle: '4 channels active',
          trailing: Icon(Icons.more_horiz),
        ),
      ));
      expect(find.byIcon(Icons.tune_outlined), findsOneWidget);
      expect(find.text('4 channels active'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });

    testWidgets('shows a divider only when showDivider is true',
        (tester) async {
      await tester.pumpWidget(_host(
        const ProSectionHeader(title: 'A'),
      ));
      expect(find.byType(Divider), findsNothing);

      await tester.pumpWidget(_host(
        const ProSectionHeader(title: 'B', showDivider: true),
      ));
      expect(find.byType(Divider), findsOneWidget);
    });
  });
}
