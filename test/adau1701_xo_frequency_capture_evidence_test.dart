// Phase 7-5A/7-5B — ADAU1701 XO Frequency Capture Evidence Integration.
//
// Ground truth, all three independently checksum-verified before either fix:
//   LPF 3000 Hz: 55 0B 1C 00 00 00 15 03 02 01 B8 0B 5A
//   HPF 3100 Hz: 55 0B 1C 00 00 00 15 03 02 00 1C 0C BE
//   LPF 3100 Hz: 55 0B 1C 00 00 00 15 03 02 01 1C 0C BF
//
// Phase 7-5A fixed the property byte (frame index 9) from the caller's
// `band` (always 0x00) to a believed-fixed 0x01 — correct in VALUE (it
// matched the one capture available) but WRONG in explanation: with only an
// LPF capture, there was no way to tell whether that byte was a fixed
// "frequency property" constant or a side selector that happened to be 0x01
// for LPF. Phase 7-5B's HPF capture (byte=0x00) resolved this: frame index 9
// is the FILTER SIDE (HPF=0x00, LPF=0x01), and every crossoverHighPass write
// before 7-5B silently used the LPF byte — a real, previously undiscovered
// production bug, now fixed by threading `isHighPass` through
// writeFilterFrequency end-to-end (transport interface, real impl,
// Adau1701Icp5PeqWritePort's crossover branch).
//
// No slope/type/coefficient work in either phase — frequency-only, per
// scope; slope/type deployment was NOT implemented in 7-5B because the
// evidence provided for them (unlike frequency) has no complete,
// checksum-verifiable example frame — see the Phase 7-5B report.
//
// DAC3 == channel index 3 == ch_wf_r (Woofer R) in
// Adau1701HardwareContext._adau1701ChannelMap — LPF is the correct role for
// a woofer channel, which is an independent sanity check that the existing
// channel-index mapping lines up with real hardware DAC numbering.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_deploy_package_data.dart';
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
  group('Phase 7-5A/7-5B: DAC3 capture evidence — exact byte tests', () {
    test('DAC3 LPF 3000Hz matches the captured frame exactly, including checksum',
        () {
      final frame = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(3, 3000);
      expect(
        frame,
        [0x55, 0x0B, 0x1C, 0x00, 0x00, 0x00, 0x15, 0x03, 0x02, 0x01, 0xB8, 0x0B, 0x5A],
      );
    });

    test('DAC3 HPF 3100Hz matches the captured frame exactly, including checksum',
        () {
      final frame = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(3, 3100,
          isHighPass: true);
      expect(
        frame,
        [0x55, 0x0B, 0x1C, 0x00, 0x00, 0x00, 0x15, 0x03, 0x02, 0x00, 0x1C, 0x0C, 0xBE],
      );
    });

    test('DAC3 LPF 3100Hz matches the captured frame exactly, including checksum',
        () {
      final frame = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(3, 3100,
          isHighPass: false);
      expect(
        frame,
        [0x55, 0x0B, 0x1C, 0x00, 0x00, 0x00, 0x15, 0x03, 0x02, 0x01, 0x1C, 0x0C, 0xBF],
      );
    });

    test('HPF and LPF at the same frequency differ only in the side byte', () {
      final hpf = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(3, 3100,
          isHighPass: true);
      final lpf = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(3, 3100,
          isHighPass: false);
      expect(hpf[9], 0x00);
      expect(lpf[9], 0x01);
      expect(hpf.sublist(0, 9), lpf.sublist(0, 9));
      expect(hpf.sublist(10, 12), lpf.sublist(10, 12)); // same frequency bytes
    });

    test('channel byte 0x03 corresponds to ch_wf_r (Woofer R) — LPF role is consistent',
        () {
      expect(Adau1701HardwareContext.defaultChannelResolver('ch_wf_r'), 3);
    });

    test('DAC3 LPF 3000 -> 2800 diff export: single XO op, no PEQ, no other '
        'channel (uses the Phase 7-4A diff-only pipeline)', () {
      final tuning = TuningProjectState(
        peqChannels: const [], // isolates the "no PEQ op" claim
        crossoverChannels: const [
          CrossoverChannelState(
            channelId: 'ch_wf_r',
            lowPass: CrossoverFilter(side: FilterSide.lowPass, frequencyHz: 2800.0),
          ),
        ],
      );
      final previousAppliedXo = {
        'ch_wf_r': const AppliedXoChannelState(channelId: 'ch_wf_r', lowPassFrequency: 3000.0),
      };

      final peqBlocks = buildAdau1701PeqExportBlocks(channels: _kChannels, tuning: tuning);
      final xoBlocks = buildAdau1701XoExportBlocks(
        channels: _kChannels,
        tuning: tuning,
        previousAppliedXo: previousAppliedXo,
      );
      expect(peqBlocks, isEmpty, reason: 'no PEQ configured — nothing to export');
      expect(xoBlocks.length, 1, reason: 'only ch_wf_r LPF changed');
      expect(xoBlocks.single.channelId, 'ch_wf_r');
      expect(xoBlocks.single.parameters.containsKey('highPass'), isFalse);
      expect(xoBlocks.single.parameters['lowPass'], {'freq_hz': 2800.0});

      final plan = buildHardwareWritePlan(
        DspExportPackage(id: 'pkg', parameterBlocks: [...peqBlocks, ...xoBlocks]),
        HardwareDeviceProfiles.adau1701Icp5,
      );
      final xoOps = plan.operations
          .where((o) =>
              o.parameterKind == HardwareParamKind.crossoverHighPass ||
              o.parameterKind == HardwareParamKind.crossoverLowPass)
          .toList();
      expect(xoOps.length, 1);
      expect(xoOps.single.channelId, 'ch_wf_r');
      expect(xoOps.single.parameterKind, HardwareParamKind.crossoverLowPass);
      expect(xoOps.single.targetValue, 2800.0);
      expect(xoOps.single.writable, isTrue);
      expect(
        plan.operations.any((o) =>
            o.parameterKind == HardwareParamKind.peqGain ||
            o.parameterKind == HardwareParamKind.peqFrequency ||
            o.parameterKind == HardwareParamKind.peqQ),
        isFalse,
        reason: 'no PEQ operation from an XO-only change',
      );
      expect(
        plan.operations.any((o) => o.channelId != 'ch_wf_r'),
        isFalse,
        reason: 'no other channel produced any operation',
      );

      // The actual frame this deploy would emit, using the just-fixed codec —
      // note this is a DIFFERENT frequency (2800) than the raw capture
      // (3000), so it is a consistency/encoding check, not a re-assertion of
      // the literal captured bytes (that's the first test in this file).
      final frame = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(3, 2800);
      expect(frame[9], 0x01, reason: 'fixed property byte, per capture evidence');
      expect(frame.sublist(10, 12), [2800 & 0xFF, (2800 >> 8) & 0xFF]);
    });
  });
}
