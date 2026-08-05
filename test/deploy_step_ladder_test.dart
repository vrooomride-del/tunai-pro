// TUNAI PRO UI/UX v3 Phase V3-6A — Deploy Step Ladder.
//
// Presentation-only: verifies the ladder renders exactly the five required
// step labels, in order, and reflects the DeployStepStatus a caller passes
// in. No deploy/write logic lives in this widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/features/workbench/widgets/deploy_step_ladder.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('DeployStepLadder', () {
    testWidgets('renders all five required step labels in order',
        (tester) async {
      await tester.pumpWidget(_host(const DeployStepLadder(steps: [
        DeployStepInfo(kind: DeployStepKind.projectCheck, status: DeployStepStatus.complete),
        DeployStepInfo(kind: DeployStepKind.writePlan, status: DeployStepStatus.active),
        DeployStepInfo(kind: DeployStepKind.backupRestore, status: DeployStepStatus.pending),
        DeployStepInfo(kind: DeployStepKind.apply, status: DeployStepStatus.pending),
        DeployStepInfo(kind: DeployStepKind.result, status: DeployStepStatus.pending),
      ])));

      expect(find.text('PROJECT CHECK'), findsOneWidget);
      expect(find.text('WRITE PLAN'), findsOneWidget);
      expect(find.text('BACKUP/RESTORE'), findsOneWidget);
      expect(find.text('APPLY'), findsOneWidget);
      expect(find.text('RESULT'), findsOneWidget);

      final texts = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(DeployStepLadder), matching: find.byType(Text)))
          .map((t) => t.data)
          .toList();
      final order = [
        'PROJECT CHECK',
        'WRITE PLAN',
        'BACKUP/RESTORE',
        'APPLY',
        'RESULT',
      ];
      final foundOrder = texts.where(order.contains).toList();
      expect(foundOrder, order);
    });

    testWidgets('shows optional detail text under a step', (tester) async {
      await tester.pumpWidget(_host(const DeployStepLadder(steps: [
        DeployStepInfo(
          kind: DeployStepKind.writePlan,
          status: DeployStepStatus.active,
          detail: '128 operation(s) · 3 blocked',
        ),
      ])));

      expect(find.text('128 operation(s) · 3 blocked'), findsOneWidget);
    });

    testWidgets('renders with no detail line when detail is null',
        (tester) async {
      await tester.pumpWidget(_host(const DeployStepLadder(steps: [
        DeployStepInfo(kind: DeployStepKind.apply, status: DeployStepStatus.pending),
      ])));

      expect(find.text('APPLY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders an empty ladder without throwing', (tester) async {
      await tester.pumpWidget(_host(const DeployStepLadder(steps: [])));
      expect(find.byType(DeployStepLadder), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
