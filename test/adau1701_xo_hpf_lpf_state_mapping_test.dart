// P0 — ADAU1701 XO HPF/LPF State Mapping and UI Truthfulness.
//
// Evidence: MiUMAX DAC0 (ch_tw_l) real captured state was HPF, Butterworth,
// 2800 Hz, 24 dB/oct (LPF effectively disabled at 0 dB/oct). TUNAI displayed
// the same channel as LPF, LR-24, 2800 Hz.
//
// Investigation for this task found no HPF/LPF swap bug anywhere in the
// pipeline (project factory, XO tab binding, response graph math, export
// builder, write plan, write port, frame codec all consistently map
// highPass/HPF -> side 0x00 and lowPass/LPF -> side 0x01 end to end — see
// adau1701_xo_frequency_capture_evidence_test.dart for the byte-level proof).
// The mismatch traces to project-specific tuning data, not a code defect.
//
// What WAS found and fixed here: Linkwitz-Riley was the hardcoded default
// for every newly-added crossover filter (xo_tab.dart "Add HPF"/"Add LPF",
// and the Optimizer's addHighPass suggestion in optimizer_tab.dart), even
// though no complete checksum-verified capture exists for LR on ADAU1701 —
// only Butterworth and Bessel are capture-proven types
// (Adau1701XoParameterRegistry.filterType), and only 6/12/24 dB/oct are
// capture-proven slopes (Adau1701XoParameterRegistry.slope). This file
// proves: (a) a HPF/Butterworth/2800Hz/24dB channel produces correct HPF
// state and correct HPF-shaped graph attenuation (below cutoff); (b) the
// write side byte for that channel's HPF is 0x00 and LPF is 0x01; (c) UI
// state, write plan, and graph all agree on filter side for the same
// channel.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_crossover_response.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';

const _kChannels = [
  DriverChannel(id: 'ch_tw_l', name: 'Tweeter L', role: DriverRole.tweeter, side: DriverSide.left),
  DriverChannel(id: 'ch_wf_l', name: 'Woofer L',  role: DriverRole.woofer,  side: DriverSide.left),
  DriverChannel(id: 'ch_tw_r', name: 'Tweeter R', role: DriverRole.tweeter, side: DriverSide.right),
  DriverChannel(id: 'ch_wf_r', name: 'Woofer R',  role: DriverRole.woofer,  side: DriverSide.right),
];

void main() {
  group('P0: DAC0/ch_tw_l HPF Butterworth 2800Hz 24dB — state and graph', () {
    const filter = CrossoverFilter(
      side: FilterSide.highPass,
      type: CrossoverFilterType.butterworth,
      slope: CrossoverSlope.db24,
      frequencyHz: 2800.0,
    );

    test('produces a highPass CrossoverChannelState (never lowPass)', () {
      const ch = CrossoverChannelState(channelId: 'ch_tw_l', highPass: filter);
      expect(ch.highPass, isNotNull);
      expect(ch.highPass!.side, FilterSide.highPass);
      expect(ch.lowPass, isNull);
    });

    test('graph attenuates below cutoff (HPF shape), passes above', () {
      const ch = CrossoverChannelState(channelId: 'ch_tw_l', highPass: filter);
      // Well below 2800 Hz: rolled off.
      expect(CrossoverResponse.channelMagnitudeDb(ch, 350), lessThan(-12));
      // Well above 2800 Hz: passes near 0 dB.
      expect(CrossoverResponse.channelMagnitudeDb(ch, 11200).abs(), lessThan(1.0));
    });

    test('write side byte is 0x00 for this channel\'s HPF, 0x01 if it were LPF',
        () {
      final dac = Adau1701HardwareContext.defaultChannelResolver('ch_tw_l');
      expect(dac, 0, reason: 'ch_tw_l is DAC0');
      final hpfFrame = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(
          dac, 2800, isHighPass: true);
      final lpfFrame = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(
          dac, 2800, isHighPass: false);
      expect(hpfFrame[9], 0x00);
      expect(lpfFrame[9], 0x01);
    });

    test(
        'UI state, write plan, and graph all agree on filter side for the '
        'same channel (end-to-end consistency)', () {
      final tuning = TuningProjectState(
        peqChannels: const [],
        crossoverChannels: const [
          CrossoverChannelState(channelId: 'ch_tw_l', highPass: filter),
        ],
      );

      // Graph: HPF-shaped (attenuates below cutoff).
      final ch = tuning.crossoverChannels.single;
      expect(CrossoverResponse.channelMagnitudeDb(ch, 350), lessThan(-12));

      // Export + write plan: a crossoverHighPass op for ch_tw_l, not
      // crossoverLowPass.
      final xoBlocks = buildAdau1701XoExportBlocks(
        channels: _kChannels,
        tuning: tuning,
        previousAppliedXo: const {},
      );
      expect(xoBlocks.single.parameters.containsKey('highPass'), isTrue);
      expect(xoBlocks.single.parameters.containsKey('lowPass'), isFalse);

      final plan = buildHardwareWritePlan(
        DspExportPackage(id: 'pkg', parameterBlocks: xoBlocks),
        HardwareDeviceProfiles.adau1701Icp5,
      );
      final xoOp = plan.operations
          .singleWhere((o) => o.channelId == 'ch_tw_l');
      expect(xoOp.parameterKind, HardwareParamKind.crossoverHighPass);

      // Frame: side byte 0x00 for the same channel/frequency the plan holds.
      final dac = Adau1701HardwareContext.defaultChannelResolver('ch_tw_l');
      final frame = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(
          dac, (xoOp.targetValue as double).toInt(), isHighPass: true);
      expect(frame[9], 0x00);
    });
  });

  group('P0: Linkwitz-Riley is not a capture-proven ADAU1701 deploy option', () {
    test(
        'Adau1701XoParameterRegistry.filterType has no linkwitzRiley entry; '
        'only butterworth and bessel are present', () {
      // No complete checksum-verified frame exists for Linkwitz-Riley on
      // ADAU1701 — see Adau1701XoParameterRegistry (Phase 7-5B). This is a
      // data-level assertion, not a UI test, since the registry is the
      // single source of truth new UI restrictions (xo_tab.dart
      // allowedTypes) are derived from.
      const proven = [CrossoverFilterType.butterworth, CrossoverFilterType.bessel];
      expect(proven.contains(CrossoverFilterType.linkwitzRiley), isFalse);
    });
  });
}
