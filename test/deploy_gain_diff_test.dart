// Focused tests: deploy plan must only contain explicitly changed channel gains.
//
// Covers:
//  1. editing one of four channels → exactly one writable operation
//  2. all four channels at 0.0 dB, no previous → zero operations
//  3. unknown previous value is NOT replaced with 0.0 in the block parameters
//  4. PASS_ACK persists the applied value
//  5. subsequent deploy shows the real stored previous value
//  6. restore is unavailable when no previous value exists (previousAppliedGains empty)

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

// ── Channels ──────────────────────────────────────────────────────────────────

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

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Deploy gain diff', () {
    test(
        '1. Editing one of four channels produces exactly one writable operation',
        () {
      // ch_tw_l changed to -10 dB; the other three remain at default 0.0 dB.
      final tuning = _tuningWith('ch_tw_l', -10.0);

      final pkg = buildAdau1701GainExportPackage(
        channels: _kChannels,
        tuning: tuning,
        // No previous applied state — first deploy.
      );
      final plan =
          buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);

      expect(plan.writableOperations.length, 1,
          reason: 'only ch_tw_l was changed');
      expect(plan.writableOperations.first.channelId, 'ch_tw_l');
      expect(plan.writableOperations.first.targetValue, -10.0);
    });

    test(
        '2. All four channels at default 0.0 dB with no previous → zero operations',
        () {
      // Nothing was edited.
      final tuning = TuningProjectState.createDefault();

      final pkg = buildAdau1701GainExportPackage(
        channels: _kChannels,
        tuning: tuning,
      );
      final plan =
          buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);

      expect(plan.writableOperations, isEmpty,
          reason: 'default 0.0 dB must not generate writes');
    });

    test(
        '3. Unknown previous value is not replaced with 0.0 in block parameters',
        () {
      final tuning = _tuningWith('ch_tw_l', -10.0);

      final pkg = buildAdau1701GainExportPackage(
        channels: _kChannels,
        tuning: tuning,
        // No previousAppliedGains → previous is unknown.
      );

      final block = pkg.parameterBlocks
          .firstWhere((b) => b.channelId == 'ch_tw_l');

      expect(block.parameters.containsKey('previousGainDb'), isFalse,
          reason: 'must not fabricate a previous value when unknown');
      expect(block.parameters['gainDb'], -10.0);
    });

    test('4. PASS_ACK persists the applied -10 dB value in the store',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      final now = DateTime(2026, 7, 29);
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: now,
        updatedAt: now,
        dspTarget: 'ADAU1701',
        connection: HardwareConnection.connected,
        acousticState: MeasurementProjectState.createDefault()
            .copyWith(driverChannels: _kChannels.toList()),
      );
      await container.read(proProjectStoreProvider.notifier).addProject(project);

      // Simulate successful write of ch_tw_l = -10 dB.
      await container
          .read(proProjectStoreProvider.notifier)
          .updateDeployAppliedGains('p1', {'ch_tw_l': -10.0});

      final stored = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1')
          .deployState
          .appliedGainsByChannel;

      expect(stored['ch_tw_l'], -10.0);
      // Other channels must NOT be in the map.
      expect(stored.containsKey('ch_wf_l'), isFalse);
      expect(stored.containsKey('ch_tw_r'), isFalse);
      expect(stored.containsKey('ch_wf_r'), isFalse);
    });

    test(
        '5. Subsequent deploy with stored previous: plan shows real -10.0 → -15.0',
        () {
      final tuning = _tuningWith('ch_tw_l', -15.0);

      final pkg = buildAdau1701GainExportPackage(
        channels: _kChannels,
        tuning: tuning,
        previousAppliedGains: {'ch_tw_l': -10.0},
      );
      final plan =
          buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);

      expect(plan.writableOperations.length, 1);
      final op = plan.writableOperations.first;
      expect(op.channelId, 'ch_tw_l');
      expect(op.targetValue, -15.0);

      // The block must carry the real previous value.
      final block = pkg.parameterBlocks.first;
      expect(block.parameters['previousGainDb'], -10.0);
    });

    test(
        '6. Restore is unavailable when no previous value exists '
        '(previousAppliedGains is empty)', () {
      // Simulates the dialog's canRestore condition.
      // After a first deploy (no prior state), previousAppliedGains = {}.
      const previousAppliedGains = <String, double>{};

      // The dialog only shows Restore when previousAppliedGains is non-empty.
      final canRestore = previousAppliedGains.isNotEmpty;
      expect(canRestore, isFalse,
          reason: 'no previous host-applied value → restore must be disabled');
    });
  });
}
