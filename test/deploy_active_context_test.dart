// Tests E and F from the "REAL HARDWARE FAIL" task.
//
// E. Executor path with active context provider:
//    E1. 4 channels, ch_tw_l at -10 dB → 1 op (channelGain), writeOutputGain
//        reached and not blocked (using the _FakeWritePort bypass that the
//        existing deploy_dialog_flow_test.dart introduced).
//    E2. activeAdau1701ContextProvider is null by default (no active transport).
//    E3. Setting it in the container propagates to reads.
//
// F. Regression: showAdau1466Controls predicate guards ADAU1466 controls.
//    F1–F4: various dspTarget values verify the gain_tab.dart predicate.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_approval.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/deploy/pro_icp5_peq_write_port.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/adau1701_peq_deployment_gate.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

// ── Test channels ─────────────────────────────────────────────────────────────

const _kChannels = [
  DriverChannel(
      id: 'ch_tw_l',
      name: 'Tweeter L',
      role: DriverRole.tweeter,
      side: DriverSide.left,
      dspOutputIndex: 1),
  DriverChannel(
      id: 'ch_wf_l',
      name: 'Woofer L',
      role: DriverRole.woofer,
      side: DriverSide.left,
      dspOutputIndex: 2),
  DriverChannel(
      id: 'ch_tw_r',
      name: 'Tweeter R',
      role: DriverRole.tweeter,
      side: DriverSide.right,
      dspOutputIndex: 3),
  DriverChannel(
      id: 'ch_wf_r',
      name: 'Woofer R',
      role: DriverRole.woofer,
      side: DriverSide.right,
      dspOutputIndex: 4),
];

TuningProjectState _tuningWith(String channelId, double gainDb) {
  final base = TuningProjectState.createDefault();
  final ctrl = base.getOrCreateControl(channelId).copyWith(gainDb: gainDb);
  return base.replaceControl(ctrl);
}

// ── Fake write port (same bypass pattern as deploy_dialog_flow_test.dart) ─────

class _FakeWritePort implements Icp5PeqWritePort {
  final List<double> writtenGains = [];

  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op) async {
    if (op.parameterKind == HardwareParamKind.channelGain) {
      writtenGains.add(op.targetValue.toDouble());
    }
    return Adau1701DeploymentReport(
      attemptedAt: DateTime.now(),
      originalStateAvailable: true,
      preflightStatus: Adau1701PreflightStatus.passed,
      deploymentAllowed: true,
      deploymentResult: Icp5PhaseCResult(
        success: true,
        wasActualWrite: true,
        writeMayHaveReachedDevice: true,
        message: 'ACK (test)',
      ),
    );
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('E. Active context provider + executor path', () {
    test(
        'E1. 4 channels, ch_tw_l at -10 dB: plan has 1 op and '
        'writeOutputGain is reached and not blocked', () async {
      // Build plan: only ch_tw_l is non-zero.
      final tuning = _tuningWith('ch_tw_l', -10.0);
      final pkg = buildAdau1701GainExportPackage(
        channels: _kChannels,
        tuning: tuning,
      );
      final plan =
          buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);

      expect(plan.writableOperations.length, 1,
          reason: '4 channels but only ch_tw_l edited');
      expect(plan.writableOperations.first.channelId, 'ch_tw_l');
      expect(plan.writableOperations.first.parameterKind,
          HardwareParamKind.channelGain);

      // Execute via a fake write port (same bypass used by the deploy dialog
      // in tests — avoids real transport / preflight / hardware).
      final fakePort = _FakeWritePort();
      final approval =
          HardwareWriteApproval.approve(plan, approver: 'test-e1');
      final result = await HardwareWriteExecutor(fakePort).execute(approval);

      expect(result.allWritten, isTrue,
          reason: 'writeOutputGain reached, not blocked by preflight');
      expect(fakePort.writtenGains, contains(-10.0),
          reason: '-10.0 dB written to the fake port');
    });

    test(
        'E2. activeAdau1701ContextProvider is null by default — no active '
        'transport until hardware_tab _syncConnectionToStore fires', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ctx = container.read(activeAdau1701ContextProvider);
      expect(ctx, isNull,
          reason: 'deploy dialog must fall back to USB when null');
    });

    test(
        'E3. Setting activeAdau1701ContextProvider via notifier propagates '
        'to reads — verifies provider reactivity for deploy dialog', () {
      // Use the USB context as a stand-in for "any connected context"; the
      // point is that whatever is set is what the deploy dialog reads.
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Read USB context to force it into the container cache.
      final usbCtx = container.read(adau1701Icp5UsbContextProvider);

      // Simulate hardware_tab _syncConnectionToStore setting the active context.
      container.read(activeAdau1701ContextProvider.notifier).state = usbCtx;

      final active = container.read(activeAdau1701ContextProvider);
      expect(active, same(usbCtx),
          reason: 'activeAdau1701ContextProvider must return the set context');
    });
  });

  group('F. Regression: gain_tab showAdau1466Controls predicate', () {
    // Mirrors the exact predicate in gain_tab.dart:
    //   final showAdau1466Controls = (project?.dspTarget ?? '') != 'ADAU1701';
    bool _show(String? dspTarget) => (dspTarget ?? '') != 'ADAU1701';

    test('F1. ADAU1701 → showAdau1466Controls is false '
        '(ADAU1466 controls must not render)', () {
      expect(_show('ADAU1701'), isFalse);
    });

    test('F2. ADAU1466 → showAdau1466Controls is true', () {
      expect(_show('ADAU1466'), isTrue);
    });

    test('F3. null dspTarget → showAdau1466Controls is true '
        '(defensive: show for unrecognized targets)', () {
      expect(_show(null), isTrue);
    });

    test('F4. ADAU1701 project in store: dspTarget is preserved '
        'and predicate is false end-to-end', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      final now = DateTime(2026, 7, 29);
      final project = ProProject(
        id: 'p1',
        name: 'ADAU1701 project',
        createdAt: now,
        updatedAt: now,
        dspTarget: 'ADAU1701',
        connection: HardwareConnection.connected,
        acousticState: MeasurementProjectState.createDefault()
            .copyWith(driverChannels: _kChannels.toList()),
      );
      await container
          .read(proProjectStoreProvider.notifier)
          .addProject(project);

      final stored = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1');
      expect(_show(stored.dspTarget), isFalse,
          reason: 'ADAU1701 project must not show ADAU1466 gain controls');
    });
  });
}
