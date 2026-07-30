// Diagnostic: why PEQ Band 1 / XO HPF / XO LPF are absent from the deploy plan.
//
// Findings (plist-verified, ADAU1701 project 1785372179650):
//   peqChannels:       1 channel (ch_tw_l), 10 bands, 0 enabled
//   crossoverChannels: [] (none stored)
//
// This file is temporary diagnostic evidence. Delete after the fix is shipped.

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

    test('1a. ch_tw_l with 10 disabled slots → buildAdau1701PeqXoExportBlocks returns []', () {
      final tuning = _storedTuningState();
      // Verify the stored structure matches plist: 10 bands, all disabled.
      final twL = tuning.peqChannels.first;
      expect(twL.channelId, 'ch_tw_l');
      expect(twL.bands.length, 10);
      expect(twL.bands.where((b) => b.enabled).length, 0,
          reason: 'plist confirmed 0 enabled bands');

      final blocks = buildAdau1701PeqXoExportBlocks(
          channels: _kChannels, tuning: tuning);
      expect(blocks.where((b) => b.type == ExportBlockType.peq).length, 0,
          reason: 'all 10 bands disabled → bandsJson.isEmpty → channel skipped');
    });

    test('1b. empty crossoverChannels → no XO blocks', () {
      final tuning = _storedTuningState();
      expect(tuning.crossoverChannels, isEmpty,
          reason: 'plist confirmed no crossoverChannels key');

      final blocks = buildAdau1701PeqXoExportBlocks(
          channels: _kChannels, tuning: tuning);
      expect(blocks.where((b) => b.type == ExportBlockType.crossover).length, 0,
          reason: 'loop never runs → 0 XO blocks');
    });

    test('1c. buildAdau1701PeqXoExportBlocks() is called but returns [] for stored state', () {
      final tuning = _storedTuningState();
      final blocks = buildAdau1701PeqXoExportBlocks(
          channels: _kChannels, tuning: tuning);
      expect(blocks, isEmpty);
    });

    // ── 2. Combined allBlocks before buildHardwareWritePlan ──────────────────

    test('2. allBlocks contains only gain blocks; PEQ/XO block count = 0', () {
      final tuning = _storedTuningState();
      // Simulate a non-zero gain so gainPkg has at least one block.
      final ctrl = tuning.getOrCreateControl('ch_tw_l').copyWith(gainDb: -3.0);
      final tuningWithGain = tuning.replaceControl(ctrl);

      final gainPkg = buildAdau1701GainExportPackage(
          channels: _kChannels, tuning: tuningWithGain);
      final peqXoBlocks = buildAdau1701PeqXoExportBlocks(
          channels: _kChannels, tuning: tuningWithGain);

      expect(gainPkg.parameterBlocks.length, 1,
          reason: 'one gain block for ch_tw_l at -3.0 dB');
      expect(gainPkg.parameterBlocks.first.type, ExportBlockType.gain);

      expect(peqXoBlocks, isEmpty,
          reason: 'PEQ: 0 enabled bands; XO: empty crossoverChannels');

      final allBlocks = [...gainPkg.parameterBlocks, ...peqXoBlocks];
      expect(allBlocks.length, 1);
      expect(allBlocks.where((b) => b.type == ExportBlockType.peq).length, 0);
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

      final blocks = buildAdau1701PeqXoExportBlocks(
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

      // Both peqGain and peqFrequency are writable (band 0 is captureProven).
      final writablePeqOps = plan.writableOperations
          .where((o) => o.parameterKind == HardwareParamKind.peqGain ||
                        o.parameterKind == HardwareParamKind.peqFrequency)
          .toList();
      expect(writablePeqOps.length, 2,
          reason: 'Band 1 gain and frequency are both writable');
      expect(writablePeqOps.map((o) => o.parameterKind),
          containsAll([HardwareParamKind.peqGain, HardwareParamKind.peqFrequency]));

      // Both are captureProven.
      for (final op in writablePeqOps) {
        expect(op.writable, isTrue);
        expect(op.verification, HardwareParamVerification.captureProven);
      }
    });

    // ── 5. End-to-end: configured XO HPF WOULD produce a captureProven op ────

    test('5. Configured XO HPF WOULD produce captureProven op in the plan', () {
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

      final blocks = buildAdau1701PeqXoExportBlocks(
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

      final xoOps = plan.writableOperations
          .where((o) => o.parameterKind == HardwareParamKind.crossoverHighPass)
          .toList();
      expect(xoOps.length, 1);
      expect(xoOps.first.writable, isTrue);
      expect(xoOps.first.channelId, 'ch_wf_l');
      expect(xoOps.first.targetValue, 80.0);
    });
  });
}
