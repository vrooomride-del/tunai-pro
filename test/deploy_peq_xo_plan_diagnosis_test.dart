// Regression tests for the PEQ/XO deploy plan pipeline.
//
// Findings (plist-verified, ADAU1701 project 1785372179650):
//   peqChannels:       1 channel (ch_tw_l), 10 bands, 0 enabled
//   crossoverChannels: [] (none stored)
//
// Since the semantic bypass fix: disabled bands export with gain_db=0.0
// (bypassed=true) instead of being skipped entirely. Tests 1a/1c/2 updated
// to reflect the new behavior.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _kChannels = [
  DriverChannel(id: 'ch_tw_l', name: 'Tweeter L', role: DriverRole.tweeter, side: DriverSide.left),
  DriverChannel(id: 'ch_wf_l', name: 'Woofer L',  role: DriverRole.woofer,  side: DriverSide.left),
  DriverChannel(id: 'ch_tw_r', name: 'Tweeter R', role: DriverRole.tweeter, side: DriverSide.right),
  DriverChannel(id: 'ch_wf_r', name: 'Woofer R',  role: DriverRole.woofer,  side: DriverSide.right),
];

/// Mirrors the stored state: ch_tw_l has 10 slot bands (all enabled=false).
/// The other 3 channels have no PEQ state stored at all.
TuningProjectState _storedTuningState() => TuningProjectState(
      peqChannels: [PeqChannelState.fixed('ch_tw_l')], // 10 slots, all enabled=false
      crossoverChannels: const [],                      // nothing configured
    );

void main() {
  group('Deploy PEQ/XO plan diagnosis', () {
    // ── 1. PEQ path ───────────────────────────────────────────────────────────

    test('1a. ch_tw_l with 10 disabled slots → 1 PEQ block with 10 bypass entries (gain=0.0)', () {
      final tuning = _storedTuningState();
      // Verify the stored structure matches plist: 10 bands, all disabled.
      final twL = tuning.peqChannels.first;
      expect(twL.channelId, 'ch_tw_l');
      expect(twL.bands.length, 10);
      expect(twL.bands.where((b) => b.enabled).length, 0,
          reason: 'plist confirmed 0 enabled bands');

      final blocks = buildAdau1701PeqExportBlocks(
          channels: _kChannels, tuning: tuning);
      final peqBlocks = blocks.where((b) => b.type == ExportBlockType.peq).toList();
      expect(peqBlocks.length, 1,
          reason: 'all 10 bands disabled → semantic bypass → 1 block with 10 gain=0.0 entries');
      final bandsMap = peqBlocks.first.parameters['bands'] as Map;
      expect(bandsMap.length, 10);
      for (final v in bandsMap.values) {
        expect((v as Map)['gain_db'], 0.0, reason: 'each disabled band → bypass gain 0.0 dB');
        expect((v)['bypassed'], true);
      }
    });

    test('1b. empty crossoverChannels → no XO blocks', () {
      final tuning = _storedTuningState();
      expect(tuning.crossoverChannels, isEmpty,
          reason: 'plist confirmed no crossoverChannels key');

      final blocks = buildAdau1701XoExportBlocks(
          channels: _kChannels, tuning: tuning);
      expect(blocks, isEmpty, reason: 'loop never runs → 0 XO blocks');
    });

    test('1c. buildAdau1701PeqExportBlocks() returns 1 PEQ bypass block for stored state', () {
      final tuning = _storedTuningState();
      final blocks = buildAdau1701PeqExportBlocks(
          channels: _kChannels, tuning: tuning);
      // ch_tw_l has 10 disabled bands → 1 PEQ block with bypass entries.
      expect(blocks, hasLength(1));
      expect(blocks.first.type, ExportBlockType.peq);
      expect(blocks.first.channelId, 'ch_tw_l');
    });

    // ── 2. Combined allBlocks before buildHardwareWritePlan ──────────────────

    test('2. allBlocks: gain block + PEQ bypass block; XO block count = 0', () {
      final tuning = _storedTuningState();
      // Simulate a non-zero gain so gainPkg has at least one block.
      final ctrl = tuning.getOrCreateControl('ch_tw_l').copyWith(gainDb: -3.0);
      final tuningWithGain = tuning.replaceControl(ctrl);

      final gainPkg = buildAdau1701GainExportPackage(
          channels: _kChannels, tuning: tuningWithGain);
      final peqBlocks = buildAdau1701PeqExportBlocks(
          channels: _kChannels, tuning: tuningWithGain);
      final xoBlocks = buildAdau1701XoExportBlocks(
          channels: _kChannels, tuning: tuningWithGain);

      expect(gainPkg.parameterBlocks.length, 1,
          reason: 'one gain block for ch_tw_l at -3.0 dB');
      expect(gainPkg.parameterBlocks.first.type, ExportBlockType.gain);

      expect(peqBlocks, hasLength(1),
          reason: 'ch_tw_l: 10 disabled bands → 1 PEQ bypass block');
      expect(peqBlocks.first.type, ExportBlockType.peq);
      expect(xoBlocks, isEmpty, reason: 'no crossoverChannels configured');

      final allBlocks = [...gainPkg.parameterBlocks, ...peqBlocks, ...xoBlocks];
      expect(allBlocks.length, 2);
      expect(allBlocks.where((b) => b.type == ExportBlockType.peq).length, 1);
      expect(allBlocks.where((b) => b.type == ExportBlockType.crossover).length, 0);
    });

    // ── 3. Capability layer (would work if blocks existed) ────────────────────

    test('3a. PEQ Band 1 (index 0) gain is captureProven on adau1701Icp5', () {
      final v = HardwareDeviceProfiles.adau1701Icp5
          .verificationFor(HardwareParamKind.peqGain, bandIndex: 0);
      expect(v, HardwareParamVerification.captureProven);
    });

    test('3b. PEQ Band 1 (index 0) frequency is captureProven — param 0x18 property 0x02', () {
      final v = HardwareDeviceProfiles.adau1701Icp5
          .verificationFor(HardwareParamKind.peqFrequency, bandIndex: 0);
      // Consumer-production-proven: param 0x18 property 0x02 → offset 19:20.
      // param 0x15 = crossover filter cutoff (different DSP block).
      expect(v, HardwareParamVerification.captureProven);
    });

    // Phase 7-4A (ADAU1701 XO Deploy Restore): restored to captureProven now
    // that XO export is diff-only (buildAdau1701XoExportBlocks). The P0
    // incident's root cause — a full-state resend touching every configured
    // channel's XO and PEQ — is fixed at the export-builder level, not by
    // relaxing this capability check without a matching safety change.
    test('3c. crossoverHighPass is captureProven on adau1701Icp5', () {
      final v = HardwareDeviceProfiles.adau1701Icp5
          .verificationFor(HardwareParamKind.crossoverHighPass);
      expect(v, HardwareParamVerification.captureProven);
    });

    test('3d. crossoverLowPass is captureProven on adau1701Icp5', () {
      final v = HardwareDeviceProfiles.adau1701Icp5
          .verificationFor(HardwareParamKind.crossoverLowPass);
      expect(v, HardwareParamVerification.captureProven);
    });

    test('3e. PEQ Band 2+ (index 1) gain is captureProven (Consumer-production-proven, ACK-only at port)', () {
      final v = HardwareDeviceProfiles.adau1701Icp5
          .verificationFor(HardwareParamKind.peqGain, bandIndex: 1);
      expect(v, HardwareParamVerification.captureProven);
      expect(v.isWriteEligible, isTrue);
    });

    // ── 4. End-to-end: enabling Band 1 WOULD produce writable PEQ ops ────────

    test('4. Enabling Band 1 on ch_tw_l: both peqGain and peqFrequency are writable', () {
      // peqFrequency band 0 is Consumer-production-proven (param 0x18 property 0x02).
      // Both peqGain (band 0) and peqFrequency (band 0) reach writableOperations.
      final base = PeqChannelState.fixed('ch_tw_l');
      final updatedBands = List<PeqBand>.from(base.bands);
      updatedBands[0] = updatedBands[0].copyWith(
        enabled: true,
        frequencyHz: 1000.0,
        gainDb: -3.0,
        q: 1.0,
      );

      final tuning = TuningProjectState(
        peqChannels: [base.copyWith(bands: updatedBands)],
        crossoverChannels: const [],
      );

      final blocks = buildAdau1701PeqExportBlocks(
          channels: _kChannels, tuning: tuning);
      expect(blocks.length, 1, reason: 'one PEQ block for ch_tw_l Band 1');
      expect(blocks.first.type, ExportBlockType.peq);

      final gainPkg = buildAdau1701GainExportPackage(
          channels: _kChannels, tuning: tuning);
      final mergedPkg = gainPkg.copyWith(
        parameterBlocks: [...gainPkg.parameterBlocks, ...blocks],
        status: ExportStatus.draftReady,
      );
      final plan = buildHardwareWritePlan(
          mergedPkg, HardwareDeviceProfiles.adau1701Icp5);

      // Band 0 (enabled): peqGain and peqFrequency are writable and captureProven.
      // Bands 1–9 (disabled): now export via semantic bypass with gain=0.0 dB.
      // So total gain+freq ops include band 0 active values + bands 1–9 bypass values.
      final band0GainOp = plan.writableOperations.firstWhere(
          (o) => o.parameterKind == HardwareParamKind.peqGain && o.bandIndex == 0);
      final band0FreqOp = plan.writableOperations.firstWhere(
          (o) => o.parameterKind == HardwareParamKind.peqFrequency && o.bandIndex == 0);

      expect(band0GainOp.writable, isTrue);
      expect(band0GainOp.verification, HardwareParamVerification.captureProven);
      expect(band0GainOp.targetValue, -3.0,
          reason: 'Band 0 active: stored gain −3.0 dB');

      expect(band0FreqOp.writable, isTrue);
      expect(band0FreqOp.verification, HardwareParamVerification.captureProven);
      expect(band0FreqOp.targetValue, 1000.0,
          reason: 'Band 0 active: stored freq 1000 Hz');

      // Bands 1–9 (disabled, bypass): gain ops have targetValue=0.0.
      final bypassGainOps = plan.writableOperations.where(
          (o) => o.parameterKind == HardwareParamKind.peqGain && o.bandIndex! > 0).toList();
      expect(bypassGainOps.length, 9,
          reason: 'Bands 1–9 each produce a bypass gain=0.0 op');
      for (final op in bypassGainOps) {
        expect(op.targetValue, 0.0,
            reason: 'Bypass band ${op.bandIndex}: gain must be 0.0 dB');
        expect(op.writable, isTrue);
        expect(op.verification, HardwareParamVerification.captureProven);
      }
    });

    // ── 5. End-to-end: configured XO HPF produces a captureProven op ─────────
    // (Phase 7-4A: XO is writable again, but only via the diff-only builder.)

    test(
        '5. First-time (no previousAppliedXo) configured XO HPF produces a '
        'captureProven, writable op', () {
      final tuning = TuningProjectState(
        peqChannels: const [],
        crossoverChannels: [
          const CrossoverChannelState(
            channelId: 'ch_wf_l',
            highPass: CrossoverFilter(
              side: FilterSide.highPass,
              frequencyHz: 80.0,
            ),
          ),
        ],
      );

      final blocks = buildAdau1701XoExportBlocks(
          channels: _kChannels, tuning: tuning);
      expect(blocks.length, 1, reason: 'one XO block for ch_wf_l');
      expect(blocks.first.type, ExportBlockType.crossover);

      final gainPkg = buildAdau1701GainExportPackage(
          channels: _kChannels, tuning: tuning);
      final mergedPkg = gainPkg.copyWith(
        parameterBlocks: [...gainPkg.parameterBlocks, ...blocks],
        status: ExportStatus.draftReady,
      );
      final plan = buildHardwareWritePlan(
          mergedPkg, HardwareDeviceProfiles.adau1701Icp5);

      final xoOps = plan.operations
          .where((o) => o.parameterKind == HardwareParamKind.crossoverHighPass)
          .toList();
      expect(xoOps.length, 1);
      expect(xoOps.first.writable, isTrue);
      expect(xoOps.first.verification, HardwareParamVerification.captureProven);
      expect(xoOps.first.channelId, 'ch_wf_l');
      expect(xoOps.first.targetValue, 80.0);
      expect(
          plan.writableOperations.any(
              (o) => o.parameterKind == HardwareParamKind.crossoverHighPass),
          isTrue);
    });
  });
}
