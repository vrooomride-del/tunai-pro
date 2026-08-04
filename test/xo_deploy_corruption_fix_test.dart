// P0 forensic fix regression, updated for Phase 7-4A (ADAU1701 XO Deploy
// Restore — diff-based safe apply).
//
// Real-hardware incident: a single 3 kHz LR24 crossover edit, deployed over
// ICP5 BLE, corrupted HPF/LPF and PEQ state across unrelated channels on
// MiUMAX. Root cause (see pro_hardware_capability.dart for the full
// rationale):
//   1. The old combined buildAdau1701PeqXoExportBlocks() was a full-state
//      resend — it emitted a block for every channel with ANY configured
//      PEQ/XO in tuningState on every deploy, not a diff against what was
//      last applied to hardware.
//   2. deploy_dialog.dart bundles Gain + PEQ + XO + Mute into one package
//      per deploy, so an XO-only edit still re-sent every channel's PEQ.
//   3. CrossoverFilter.type / .slope (e.g. "LR24") are never read by the
//      export builder — only frequencyHz is sent; filter type/slope has
//      never had a capture-proven write path.
//
// P0 fix (superseded by Phase 7-4A): downgraded crossoverHighPass/LowPass to
// `unavailable` (fail-closed) until the export path itself was fixed.
//
// Phase 7-4A fix: split the combined builder into buildAdau1701PeqExportBlocks
// (PEQ, unchanged, full-state) and buildAdau1701XoExportBlocks (XO, diff-only
// against DeployProjectState.appliedXoByChannel). With the export path itself
// now structurally incapable of resending an unrelated channel or leaking
// into PEQ, crossoverHighPass/LowPass are restored to captureProven.
//
// Covers (still valid after the split):
//  1. A tuningState with only an XO edit (no PEQ channels at all) never
//     produces a PEQ block or PEQ op.
//  2. A crossover channel with only LPF configured never produces an HPF op
//     (highPass key omitted from the export block) — and the LPF op is
//     writable (captureProven), since the diff export itself is now the
//     safety mechanism.
//  3. Only channels passed to the builder are included — an XO-configured
//     channel outside the requested channel list is never emitted.
//  4. A channel with no frequency change (only type/slope differ, or
//     nothing differs) versus previousAppliedXo produces no XO block/op —
//     the diff is frequency-only, exactly as documented, regardless of
//     type/slope.
//  5. Gain-only deploy (no PEQ/XO configured) is completely unaffected —
//     the channelGain op is still captureProven and writable.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_deploy_package_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _kChTwL = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);
const _kChWfL = DriverChannel(
  id: 'ch_wf_l',
  name: 'Woofer L',
  role: DriverRole.woofer,
  side: DriverSide.left,
  dspOutputIndex: 2,
);

void main() {
  group('P0 XO corruption fix (Phase 7-4A diff export)', () {
    test('1. XO-only edit never emits a PEQ block or PEQ op', () {
      final tuning = TuningProjectState(
        peqChannels: const [], // no PEQ configured anywhere
        crossoverChannels: const [
          CrossoverChannelState(
            channelId: 'ch_tw_l',
            highPass: CrossoverFilter(
              side: FilterSide.highPass,
              type: CrossoverFilterType.linkwitzRiley,
              slope: CrossoverSlope.db24,
              frequencyHz: 3000.0,
            ),
          ),
        ],
      );

      final peqBlocks = buildAdau1701PeqExportBlocks(
          channels: const [_kChTwL], tuning: tuning);
      final xoBlocks = buildAdau1701XoExportBlocks(
          channels: const [_kChTwL], tuning: tuning);

      expect(peqBlocks, isEmpty,
          reason: 'no PEQ channel state exists — no PEQ block may appear');
      expect(xoBlocks.length, 1);
      expect(xoBlocks.single.type, ExportBlockType.crossover);

      final pkg = DspExportPackage(
        id: 'pkg',
        targetPlatform: DspTargetPlatform.adau1701,
        status: ExportStatus.draftReady,
        parameterBlocks: [...peqBlocks, ...xoBlocks],
      );
      final plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
      expect(
        plan.operations.any((o) =>
            o.parameterKind == HardwareParamKind.peqGain ||
            o.parameterKind == HardwareParamKind.peqFrequency ||
            o.parameterKind == HardwareParamKind.peqQ),
        isFalse,
        reason: 'a single XO edit must never produce a PEQ operation',
      );
    });

    test('2. LPF-only edit never emits an HPF operation, and is writable', () {
      final tuning = TuningProjectState(
        peqChannels: const [],
        crossoverChannels: const [
          CrossoverChannelState(
            channelId: 'ch_wf_l',
            lowPass: CrossoverFilter(
              side: FilterSide.lowPass,
              frequencyHz: 2800.0,
            ),
            // highPass intentionally omitted.
          ),
        ],
      );

      final blocks = buildAdau1701XoExportBlocks(
          channels: const [_kChWfL], tuning: tuning);
      expect(blocks.length, 1);
      expect(blocks.single.parameters.containsKey('highPass'), isFalse,
          reason: 'HPF must not be sent when only LPF was configured');
      expect(blocks.single.parameters.containsKey('lowPass'), isTrue);

      final pkg = DspExportPackage(
        id: 'pkg',
        targetPlatform: DspTargetPlatform.adau1701,
        status: ExportStatus.draftReady,
        parameterBlocks: blocks,
      );
      final plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
      expect(
        plan.operations
            .any((o) => o.parameterKind == HardwareParamKind.crossoverHighPass),
        isFalse,
        reason: 'an LPF-only edit must never produce an HPF operation',
      );
      final lpOp = plan.operations
          .singleWhere((o) => o.parameterKind == HardwareParamKind.crossoverLowPass);
      expect(lpOp.channelId, 'ch_wf_l');
      expect(lpOp.targetValue, 2800.0);
      // Phase 7-4A: writable again — safety now comes from the diff export,
      // not a blanket capability block.
      expect(lpOp.writable, isTrue);
      expect(lpOp.verification, HardwareParamVerification.captureProven);
    });

    test('3. Only channels passed to the builder are included', () {
      final tuning = TuningProjectState(
        peqChannels: const [],
        crossoverChannels: const [
          CrossoverChannelState(
            channelId: 'ch_tw_l',
            highPass: CrossoverFilter(side: FilterSide.highPass, frequencyHz: 3000.0),
          ),
          CrossoverChannelState(
            channelId: 'ch_wf_l',
            lowPass: CrossoverFilter(side: FilterSide.lowPass, frequencyHz: 2800.0),
          ),
        ],
      );

      // Only ch_tw_l is requested — ch_wf_l's configured XO must not appear,
      // even though it exists in tuningState (this is the "only intended
      // linked channels" guarantee; it does not depend on which channel the
      // user most recently edited).
      final blocks = buildAdau1701XoExportBlocks(
          channels: const [_kChTwL], tuning: tuning);

      expect(blocks.length, 1);
      expect(blocks.single.channelId, 'ch_tw_l');
      expect(blocks.any((b) => b.channelId == 'ch_wf_l'), isFalse);
    });

    test(
        '4. A channel with no frequency change vs previousAppliedXo produces '
        'no XO block, regardless of type/slope', () {
      // Same frequency as previously applied (3000 Hz), but a different
      // type/slope recorded — the diff is frequency-only, so this must
      // still be treated as unchanged and produce nothing to write.
      final tuning = TuningProjectState(
        peqChannels: const [],
        crossoverChannels: const [
          CrossoverChannelState(
            channelId: 'ch_tw_l',
            highPass: CrossoverFilter(
              side: FilterSide.highPass,
              type: CrossoverFilterType.butterworth,
              slope: CrossoverSlope.db12,
              frequencyHz: 3000.0,
            ),
          ),
        ],
      );
      final previousAppliedXo = {
        'ch_tw_l': const AppliedXoChannelState(
          channelId: 'ch_tw_l',
          highPassFrequency: 3000.0,
          filterType: CrossoverFilterType.linkwitzRiley,
          slope: CrossoverSlope.db24,
        ),
      };

      final blocks = buildAdau1701XoExportBlocks(
        channels: const [_kChTwL],
        tuning: tuning,
        previousAppliedXo: previousAppliedXo,
      );
      expect(blocks, isEmpty,
          reason: 'frequency unchanged — type/slope-only differences do '
              'not trigger a write (no capture-proven mapping for them)');
    });

    test('5. Gain-only deploy is unaffected by the XO diff-export change', () {
      final tuning = TuningProjectState.createDefault();
      final ctrl =
          tuning.getOrCreateControl('ch_tw_l').copyWith(gainDb: -6.0);
      final gainTuning = tuning.replaceControl(ctrl);

      final gainPkg = buildAdau1701GainExportPackage(
          channels: const [_kChTwL], tuning: gainTuning);
      final peqBlocks = buildAdau1701PeqExportBlocks(
          channels: const [_kChTwL], tuning: gainTuning);
      final xoBlocks = buildAdau1701XoExportBlocks(
          channels: const [_kChTwL], tuning: gainTuning);
      expect(peqBlocks, isEmpty, reason: 'no PEQ configured — nothing to export');
      expect(xoBlocks, isEmpty, reason: 'no XO configured — nothing to export');

      final plan = buildHardwareWritePlan(
          gainPkg, HardwareDeviceProfiles.adau1701Icp5);
      expect(plan.writableOperations.length, 1);
      final op = plan.writableOperations.single;
      expect(op.parameterKind, HardwareParamKind.channelGain);
      expect(op.verification, HardwareParamVerification.captureProven);
      expect(op.writable, isTrue);
      expect(op.targetValue, -6.0);
    });
  });
}
