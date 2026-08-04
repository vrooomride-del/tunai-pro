// Phase 7-4A (ADAU1701 XO Deploy Restore): the P0 fix's blocking banner
// ("XO hardware deployment temporarily blocked — mapping validation
// required.") must no longer appear for a normal XO deploy now that XO is
// captureProven again via the diff-only export builder. Both Gain and XO
// pending writes are shown normally, and XO is listed as "Channel Gain"'s
// sibling pending write, not as a blocked op.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/workbench/widgets/deploy_dialog.dart';

class _FakePort implements Icp5PeqWritePort {
  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op) async =>
      Adau1701DeploymentReport(
        attemptedAt: DateTime(2026, 8, 1),
        originalStateAvailable: false,
        preflightStatus: Adau1701PreflightStatus.passed,
        deploymentAllowed: true,
        isAckOnly: true,
        deploymentResult: const Icp5PhaseCResult(
          success: true,
          wasActualWrite: true,
          writeMayHaveReachedDevice: true,
          message: 'ok',
        ),
      );
}

const _kTweeterL = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

TuningProjectState _tuningGainAndXo() {
  final base = TuningProjectState(
    peqChannels: const [],
    crossoverChannels: const [
      CrossoverChannelState(
        channelId: 'ch_tw_l',
        highPass: CrossoverFilter(side: FilterSide.highPass, frequencyHz: 3000.0),
      ),
    ],
  );
  final ctrl = base.getOrCreateControl('ch_tw_l').copyWith(gainDb: -6.0);
  return base.replaceControl(ctrl);
}

void main() {
  testWidgets(
      'no XO block banner; both Gain and XO listed as normal pending writes',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDeployDialog(
                context: context,
                projectId: 'p1',
                channels: const [_kTweeterL],
                tuning: _tuningGainAndXo(),
                previousAppliedGains: const {},
                overridePort: _FakePort(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
          'XO hardware deployment temporarily blocked — mapping validation required.'),
      findsNothing,
    );
    expect(find.textContaining('BLOCKED'), findsNothing);
    // Both pending writes listed normally.
    expect(find.text('Channel Gain'), findsOneWidget);
    expect(find.text('XO HPF'), findsOneWidget);
  });
}
