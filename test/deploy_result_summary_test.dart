// TUNAI PRO UI/UX v3 Phase V3-6A — Deploy Result Summary.
//
// Presentation-only: verifies the shared result-wording widget never labels
// an ack-only result as "Verified", and correctly renders the "Verified"
// state only when every outcome reached HardwareWriteOpStatus.written.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/features/workbench/widgets/deploy_result_summary.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

HardwareWriteOp _op() => const HardwareWriteOp(
      channelId: 'ch_tw_l',
      parameterKind: HardwareParamKind.peqGain,
      bandIndex: 0,
      targetValue: -3.0,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );

HardwareWriteOpOutcome _outcome(HardwareWriteOpStatus status) =>
    HardwareWriteOpOutcome(op: _op(), status: status, report: null, message: status.name);

HardwareWriteExecutionResult _result(List<HardwareWriteOpStatus> statuses,
        {bool executed = true}) =>
    HardwareWriteExecutionResult(
      planId: 'p',
      executed: executed,
      rejectionReason: executed ? null : 'not approved',
      outcomes: [for (final s in statuses) _outcome(s)],
    );

void main() {
  group('DeployResultSummary', () {
    testWidgets('renders nothing for a null result', (tester) async {
      await tester.pumpWidget(_host(const DeployResultSummary(result: null)));
      expect(find.text('Verified'), findsNothing);
      expect(find.textContaining('PASS_ACK'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an all-ack-only result never shows "Verified"',
        (tester) async {
      final r = _result(List.filled(3, HardwareWriteOpStatus.ackOnly));
      await tester.pumpWidget(_host(DeployResultSummary(result: r)));

      expect(find.text('PASS_ACK (not DSP-verified)'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });

    testWidgets(
        'a mixed written+ackOnly result (no failures) still stays in the '
        'not-DSP-verified state, never "Verified"', (tester) async {
      final r = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.ackOnly]);
      await tester.pumpWidget(_host(DeployResultSummary(result: r)));

      expect(find.text('PASS_ACK (not DSP-verified)'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });

    testWidgets('a fully-written result shows "Verified"', (tester) async {
      final r = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.written]);
      await tester.pumpWidget(_host(DeployResultSummary(result: r)));

      expect(find.text('Verified'), findsOneWidget);
      expect(find.textContaining('PASS_ACK'), findsNothing);
    });

    testWidgets('a result with failures uses the default BLOCKED wording',
        (tester) async {
      final r = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.failed]);
      await tester.pumpWidget(_host(DeployResultSummary(result: r)));

      expect(find.text('Verified'), findsNothing);
      expect(find.textContaining('PASS_ACK'), findsNothing);
      expect(find.textContaining('blocked or failed'), findsOneWidget);
    });

    testWidgets('an unexecuted result shows the rejection reason',
        (tester) async {
      final r = _result(const [], executed: false);
      await tester.pumpWidget(_host(DeployResultSummary(result: r)));

      expect(find.text('not approved'), findsOneWidget);
    });

    testWidgets('a custom failureBuilder overrides the default failure pill',
        (tester) async {
      final r = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.failed]);
      await tester.pumpWidget(_host(DeployResultSummary(
        result: r,
        failureBuilder: (_) => const Text('CUSTOM FAILURE TEXT'),
      )));

      expect(find.text('CUSTOM FAILURE TEXT'), findsOneWidget);
      expect(find.textContaining('blocked or failed'), findsNothing);
    });

    test('labelFor never returns "Verified" for an ack-only result', () {
      final r = _result(List.filled(2, HardwareWriteOpStatus.ackOnly));
      expect(DeployResultSummary.labelFor(r), 'PASS_ACK (not DSP-verified)');
    });

    test('labelFor returns "Verified" only when every outcome is written',
        () {
      final r = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.written]);
      expect(DeployResultSummary.labelFor(r), 'Verified');
    });
  });
}
