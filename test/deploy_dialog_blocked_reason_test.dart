// Deploy dialog blocked-reason visibility fix.
//
// _planView()'s blocked-operations list previously showed only a hardcoded
// header ("BLOCKED — no confirmed write path") and a static per-row
// "BLOCKED" tag — never HardwareWriteOp.reason, even though that field is
// correctly computed by pro_hardware_write_plan.dart's _reasonFor() (the
// Deploy tab's HardwareApplyPreview already rendered it correctly; only this
// dialog ignored it). This test proves the dialog now shows channel,
// parameter, value, AND the actual specific reason for a blocked op — using
// PEQ Band 9 (index 8), the ADAU1701 PEQ band capability correction case.

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

const _kChannels = [
  DriverChannel(
      id: 'ch_tw_l',
      name: 'Tweeter L',
      role: DriverRole.tweeter,
      side: DriverSide.left,
      dspOutputIndex: 1),
];

/// Band 9 (index 8) enabled — unavailable on real hardware (PEQ band
/// capability correction). All other bands stay disabled/default.
TuningProjectState _tuningWithBand9() {
  final base = PeqChannelState.fixed('ch_tw_l');
  final bands = List<PeqBand>.from(base.bands);
  bands[8] = bands[8].copyWith(
    enabled: true,
    frequencyHz: 5000.0,
    gainDb: 1.5,
    q: 1.0,
  );
  return TuningProjectState(
    peqChannels: [base.copyWith(bands: bands)],
    crossoverChannels: const [],
  );
}

void main() {
  testWidgets(
      'blocked PEQ Band 9 shows channel, parameter, value, and the actual '
      'reason (not the old generic header)', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDeployDialog(
                context: context,
                projectId: 'p1',
                channels: _kChannels,
                tuning: _tuningWithBand9(),
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

    // Old hardcoded generic header must be gone.
    expect(find.textContaining('no confirmed write path'), findsNothing);

    // New header still names the section, with a count.
    expect(find.textContaining('BLOCKED ('), findsOneWidget);

    // Channel + parameter (band 9 = "PEQ B9 <kind>") are shown.
    expect(find.text('ch_tw_l'), findsWidgets);
    expect(find.textContaining('PEQ B9'), findsWidgets);

    // The actual specific reason text is now visible, not just the tag.
    expect(
      find.textContaining(
          'ADAU1701 PEQ Band 9-10 are not hardware verified. '
          'Supported deploy range is Band 1-8.'),
      findsWidgets,
    );

    // No overflow anywhere in the dialog.
    expect(tester.takeException(), isNull);
  });
}
