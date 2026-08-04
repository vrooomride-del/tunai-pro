// Phase 7-4A — ADAU1701 XO Deploy Restore (Diff-based Safe Apply).
//
// Covers exactly the four required scenarios:
//   Test 1: Woofer L LPF 3000 → 2800 produces exactly one XO operation —
//           no PEQ operation, no other channel's XO operation.
//   Test 2: A PEQ change (Band 1 gain) produces PEQ operations only — no XO.
//   Test 3: Gain-change regression — existing PASS behavior is preserved.
//   Test 4: A Guided-AI-style applied candidate (tuningState populated the
//           same way GuidedAiProjectApply would) goes through the identical
//           buildAdau1701PeqExportBlocks / buildAdau1701XoExportBlocks /
//           buildHardwareWritePlan pipeline as a manual UI edit — there is
//           no separate Guided AI export path to diverge.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_deploy_package_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _kChannels = [
  DriverChannel(id: 'ch_tw_l', name: 'Tweeter L', role: DriverRole.tweeter, side: DriverSide.left),
  DriverChannel(id: 'ch_wf_l', name: 'Woofer L',  role: DriverRole.woofer,  side: DriverSide.left),
  DriverChannel(id: 'ch_tw_r', name: 'Tweeter R', role: DriverRole.tweeter, side: DriverSide.right),
  DriverChannel(id: 'ch_wf_r', name: 'Woofer R',  role: DriverRole.woofer,  side: DriverSide.right),
];

/// Mirrors deploy_dialog.dart's _buildPlan(): Gain (diff) + PEQ (full-state)
/// + XO (diff) assembled into one plan, exactly as the real Deploy button
/// does — used here to prove end-to-end plan behavior, not just the
/// individual builder functions in isolation.
HardwareWritePlan _buildPlan(
  TuningProjectState tuning, {
  Map<String, double> previousAppliedGains = const {},
  Map<String, AppliedXoChannelState> previousAppliedXo = const {},
}) {
  final gainPkg = buildAdau1701GainExportPackage(
    channels: _kChannels,
    tuning: tuning,
    previousAppliedGains: previousAppliedGains.isEmpty ? null : previousAppliedGains,
  );
  final peqBlocks = buildAdau1701PeqExportBlocks(channels: _kChannels, tuning: tuning);
  final xoBlocks = buildAdau1701XoExportBlocks(
    channels: _kChannels,
    tuning: tuning,
    previousAppliedXo: previousAppliedXo,
  );
  final allBlocks = [...gainPkg.parameterBlocks, ...peqBlocks, ...xoBlocks];
  final pkg = gainPkg.copyWith(
    status: allBlocks.isEmpty ? ExportStatus.notReady : ExportStatus.draftReady,
    parameterBlocks: allBlocks,
  );
  return buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
}

void main() {
  group('Phase 7-4A diff-based XO deploy', () {
    test(
        'Test 1: Woofer L LPF 3000 → 2800 → exactly one XO op; no PEQ op; '
        'no other channel XO op', () {
      // All four channels have XO configured; only Woofer L's LPF changed.
      final tuning = TuningProjectState(
        peqChannels: const [], // no PEQ configured — isolates the XO-only claim
        crossoverChannels: const [
          CrossoverChannelState(
            channelId: 'ch_tw_l',
            highPass: CrossoverFilter(side: FilterSide.highPass, frequencyHz: 3000.0),
          ),
          CrossoverChannelState(
            channelId: 'ch_wf_l',
            lowPass: CrossoverFilter(side: FilterSide.lowPass, frequencyHz: 2800.0), // changed
          ),
          CrossoverChannelState(
            channelId: 'ch_tw_r',
            highPass: CrossoverFilter(side: FilterSide.highPass, frequencyHz: 3000.0),
          ),
          CrossoverChannelState(
            channelId: 'ch_wf_r',
            lowPass: CrossoverFilter(side: FilterSide.lowPass, frequencyHz: 3000.0), // unchanged
          ),
        ],
      );
      final previousAppliedXo = {
        'ch_tw_l': const AppliedXoChannelState(channelId: 'ch_tw_l', highPassFrequency: 3000.0),
        'ch_wf_l': const AppliedXoChannelState(channelId: 'ch_wf_l', lowPassFrequency: 3000.0), // was 3000
        'ch_tw_r': const AppliedXoChannelState(channelId: 'ch_tw_r', highPassFrequency: 3000.0),
        'ch_wf_r': const AppliedXoChannelState(channelId: 'ch_wf_r', lowPassFrequency: 3000.0),
      };

      final plan = _buildPlan(tuning, previousAppliedXo: previousAppliedXo);

      final xoOps = plan.operations
          .where((o) =>
              o.parameterKind == HardwareParamKind.crossoverHighPass ||
              o.parameterKind == HardwareParamKind.crossoverLowPass)
          .toList();
      expect(xoOps.length, 1, reason: 'only Woofer L LPF changed');
      expect(xoOps.single.channelId, 'ch_wf_l');
      expect(xoOps.single.parameterKind, HardwareParamKind.crossoverLowPass);
      expect(xoOps.single.targetValue, 2800.0);
      expect(xoOps.single.writable, isTrue);
      expect(xoOps.single.verification, HardwareParamVerification.captureProven);

      expect(
        plan.operations.any((o) =>
            o.parameterKind == HardwareParamKind.peqGain ||
            o.parameterKind == HardwareParamKind.peqFrequency ||
            o.parameterKind == HardwareParamKind.peqQ),
        isFalse,
        reason: 'no PEQ operation from an XO-only change',
      );
      expect(
        plan.writableOperations
            .any((o) => o.channelId != 'ch_wf_l'),
        isFalse,
        reason: 'no other channel produced any writable operation',
      );
    });

    test('Test 2: PEQ Band 1 gain change → PEQ operations only, no XO', () {
      final band = PeqBand(
        id: 'b0',
        type: PeqBandType.peak,
        frequencyHz: 1000.0,
        gainDb: -3.0,
        q: 1.0,
        enabled: true,
      );
      final tuning = TuningProjectState(
        peqChannels: [PeqChannelState(channelId: 'ch_tw_l', bands: [band])],
        crossoverChannels: const [], // no XO configured anywhere
      );

      final plan = _buildPlan(tuning);

      expect(
        plan.operations.any((o) =>
            o.parameterKind == HardwareParamKind.crossoverHighPass ||
            o.parameterKind == HardwareParamKind.crossoverLowPass),
        isFalse,
        reason: 'no XO operation from a PEQ-only change',
      );
      final peqOps = plan.writableOperations
          .where((o) =>
              o.parameterKind == HardwareParamKind.peqGain ||
              o.parameterKind == HardwareParamKind.peqFrequency ||
              o.parameterKind == HardwareParamKind.peqQ)
          .toList();
      expect(peqOps, isNotEmpty);
      expect(peqOps.every((o) => o.channelId == 'ch_tw_l'), isTrue);
    });

    test('Test 3: Gain-change regression — existing PASS behavior preserved', () {
      final tuning = TuningProjectState.createDefault();
      final ctrl = tuning.getOrCreateControl('ch_tw_l').copyWith(gainDb: -10.0);
      final gainTuning = tuning.replaceControl(ctrl);

      final plan = _buildPlan(gainTuning);

      expect(plan.writableOperations.length, 1);
      final op = plan.writableOperations.single;
      expect(op.parameterKind, HardwareParamKind.channelGain);
      expect(op.channelId, 'ch_tw_l');
      expect(op.targetValue, -10.0);
      expect(op.writable, isTrue);
      expect(op.verification, HardwareParamVerification.captureProven);
    });

    test(
        'Test 4: a Guided-AI-applied XO candidate goes through the identical '
        'diff pipeline as a manual edit', () {
      // Simulates GuidedAiProjectApply having persisted an XO suggestion into
      // tuningState (the same store field a manual XO tab edit would write
      // to) — there is no separate Guided-AI export function to audit; both
      // paths call buildAdau1701XoExportBlocks with the project's real
      // previousAppliedXo.
      final guidedAiAppliedTuning = TuningProjectState(
        peqChannels: const [],
        crossoverChannels: const [
          CrossoverChannelState(
            channelId: 'ch_wf_l',
            lowPass: CrossoverFilter(side: FilterSide.lowPass, frequencyHz: 2800.0),
          ),
        ],
      );
      final previousAppliedXo = {
        'ch_wf_l': const AppliedXoChannelState(channelId: 'ch_wf_l', lowPassFrequency: 3000.0),
      };

      final plan = _buildPlan(guidedAiAppliedTuning, previousAppliedXo: previousAppliedXo);

      final xoOps = plan.writableOperations
          .where((o) => o.parameterKind == HardwareParamKind.crossoverLowPass)
          .toList();
      expect(xoOps.length, 1);
      expect(xoOps.single.channelId, 'ch_wf_l');
      expect(xoOps.single.targetValue, 2800.0);
      expect(
        plan.operations.any((o) =>
            o.parameterKind == HardwareParamKind.peqGain ||
            o.parameterKind == HardwareParamKind.peqFrequency ||
            o.parameterKind == HardwareParamKind.peqQ),
        isFalse,
        reason: 'Guided AI applying an XO candidate must not touch PEQ',
      );
    });
  });
}
