// Focused acceptance tests for the DEPLOY button flow:
//
// ADAU1701 project → ICP5 PASS_HANDSHAKE → change Tweeter L gain 0→-10 dB
// → build plan → approve → writeOutputGain → PASS_ACK → applied state -10 dB
// → Restore returns to 0 dB with PASS_ACK
//
// Covers:
//  1. ADAU1701 project with one channel-gain change generates export package
//  2. Deploy plan contains channelGain writable operation
//  3. Approval over the plan invokes writeOutputGain with correct args
//  4. PASS_ACK updates applied host state
//  5. Restore invokes writeOutputGain with previous (rollback) value
//  6. Missing channel-gain change produces empty plan
//  7. Factory Profile ineligibility does NOT block engineering gain write

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_approval.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// ── Fake write port (bypasses preflight — hardware-free test double) ──────────
//
// The real write port requires a live DSP state read for preflight.
// This test double skips that: it records output-gain writes and always ACKs.

class _FakeWritePort implements Icp5PeqWritePort {
  final List<(int, double)> outputGainWrites = [];

  int _resolve(String channelId) {
    const map = {'ch_tw_l': 1, 'ch_wf_l': 2, 'ch_tw_r': 3, 'ch_wf_r': 4};
    return map[channelId] ?? 0;
  }

  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op) async {
    if (op.parameterKind == HardwareParamKind.channelGain) {
      outputGainWrites.add((_resolve(op.channelId), op.targetValue.toDouble()));
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
        message: 'ACK (test double)',
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kTweeterL = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

TuningProjectState _tuningWith(String channelId, double gainDb) {
  final base = TuningProjectState.createDefault();
  final ctrl = base.getOrCreateControl(channelId).copyWith(gainDb: gainDb);
  return base.replaceControl(ctrl);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  final now = DateTime(2026, 7, 29);

  ProProject testProject({ProfileStatus profile = ProfileStatus.draft}) =>
      ProProject(
        id: 'proj_deploy_test',
        name: 'Deploy Test',
        createdAt: now,
        updatedAt: now,
        dspTarget: 'ADAU1701',
        connection: HardwareConnection.connected,
        profileStatus: profile,
        acousticState: MeasurementProjectState.createDefault()
            .copyWith(driverChannels: [_kTweeterL]),
      );

  test(
      '1. ADAU1701 project with Tweeter L gain change generates '
      'export package with one block', () {
    final tuning = _tuningWith('ch_tw_l', -10.0);
    final pkg = buildAdau1701GainExportPackage(
      channels: [_kTweeterL],
      tuning: tuning,
    );
    expect(pkg.status, ExportStatus.draftReady);
    expect(pkg.parameterBlocks.length, 1);
    expect(pkg.parameterBlocks.first.channelId, 'ch_tw_l');
    expect(pkg.parameterBlocks.first.parameters['gainDb'], -10.0);
  });

  test('2. Deploy plan contains channelGain writable operation', () {
    final tuning = _tuningWith('ch_tw_l', -10.0);
    final pkg = buildAdau1701GainExportPackage(
      channels: [_kTweeterL],
      tuning: tuning,
    );
    final plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
    expect(plan.writableOperations, isNotEmpty);
    final op = plan.writableOperations.first;
    expect(op.parameterKind, HardwareParamKind.channelGain);
    expect(op.channelId, 'ch_tw_l');
    expect(op.targetValue, -10.0);
  });

  test('3. Approval + executor call writeOutputGain with channel 1, -10.0 dB',
      () async {
    final port = _FakeWritePort();
    final executor = HardwareWriteExecutor(port);

    final tuning = _tuningWith('ch_tw_l', -10.0);
    final pkg = buildAdau1701GainExportPackage(
      channels: [_kTweeterL],
      tuning: tuning,
    );
    final plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
    final approval = HardwareWriteApproval.approve(plan, approver: 'test');
    final result = await executor.execute(approval);

    expect(result.executed, isTrue);
    expect(result.allWritten, isTrue);
    // Channel 1 = Tweeter L dspOutputIndex
    expect(port.outputGainWrites, contains((1, -10.0)));
  });

  test('4. PASS_ACK: updateDeployAppliedGains persists -10 dB for ch_tw_l',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(proProjectStoreProvider);
    await pumpEventQueue();
    await container
        .read(proProjectStoreProvider.notifier)
        .addProject(testProject());

    await container
        .read(proProjectStoreProvider.notifier)
        .updateDeployAppliedGains('proj_deploy_test', {'ch_tw_l': -10.0});

    final proj = container
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'proj_deploy_test');
    expect(proj.deployState.appliedGainsByChannel['ch_tw_l'], -10.0);
  });

  test('5. Restore: writeOutputGain called with previous value (0 dB)',
      () async {
    final port = _FakeWritePort();
    final executor = HardwareWriteExecutor(port);

    // Previous applied = 0 dB. Restore package writes that back.
    final restoreBlocks = [
      ExportParameterBlock(
        id: 'restore_ch_tw_l',
        type: ExportBlockType.gain,
        channelId: 'ch_tw_l',
        title: 'Tweeter L Restore',
        summary: '+0.0 dB',
        parameters: {'gainDb': 0.0},
      ),
    ];
    final restorePkg = DspExportPackage(
      id: 'restore_test',
      targetPlatform: DspTargetPlatform.adau1701,
      format: ExportFormat.hardwareWritePlanPlaceholder,
      status: ExportStatus.draftReady,
      projectName: 'Restore',
      tuningRevision: 0,
      protectionRevision: 0,
      optimizerRevision: 0,
      parameterBlocks: restoreBlocks,
    );
    final plan = buildHardwareWritePlan(restorePkg, HardwareDeviceProfiles.adau1701Icp5);
    final approval =
        HardwareWriteApproval.approve(plan, approver: 'test-restore');
    final result = await executor.execute(approval);

    expect(result.allWritten, isTrue);
    expect(port.outputGainWrites, contains((1, 0.0)));
  });

  test('6. No change since last deploy → empty writable plan', () {
    // Previous applied and current tuning are identical: 0.0 dB.
    final tuning = _tuningWith('ch_tw_l', 0.0);
    final pkg = buildAdau1701GainExportPackage(
      channels: [_kTweeterL],
      tuning: tuning,
      previousAppliedGains: {'ch_tw_l': 0.0},
    );
    final plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
    expect(plan.writableOperations, isEmpty);
  });

  test(
      '7. Factory Profile ineligibility does NOT block engineering gain write',
      () async {
    // Profile is draft (not deployed/eligible for Factory write).
    // Engineering path must still produce a writable plan.
    final port = _FakeWritePort();
    final executor = HardwareWriteExecutor(port);

    final project = testProject(profile: ProfileStatus.draft);
    final tuning = _tuningWith('ch_tw_l', -6.0);

    final pkg = buildAdau1701GainExportPackage(
      channels: project.acousticState.driverChannels,
      tuning: tuning,
    );
    expect(pkg.status, ExportStatus.draftReady,
        reason: 'Draft profile must not block engineering gain export');

    final plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
    expect(plan.writableOperations, isNotEmpty);

    final approval = HardwareWriteApproval.approve(plan, approver: 'test');
    final result = await executor.execute(approval);
    expect(result.allWritten, isTrue);
    expect(port.outputGainWrites, contains((1, -6.0)));
  });
}
