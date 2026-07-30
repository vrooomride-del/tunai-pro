// Verifies that the mute polarity diagnostic uses exact capture-proven frames
// and that the normal deploy path continues to reject mute/delay writes.
//
// The polarity judgment (which state = muted) is session-only and never
// auto-saved. These tests verify only the frame encoding correctness and the
// continued deploy-path block.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';

void main() {
  group('Mute polarity frame encoding', () {
    test('State 0 and State 1 produce distinct frames', () {
      final frame0 = Icp5FrameCodec.buildMasterMuteWrite(0);
      final frame1 = Icp5FrameCodec.buildMasterMuteWrite(1);
      expect(frame0, isNot(equals(frame1)));
    });

    test('State 0 frame has payload 01 00 00 and correct parameter ID 0x12', () {
      final frame = Icp5FrameCodec.buildMasterMuteWrite(0);
      // Frame: 55 09 1C 00 00 00 12 01 00 [state=00] [checksum]
      expect(frame[2], 0x1C); // direct write command
      expect(frame[6], 0x12); // parameter ID LSB
      expect(frame[7], 0x01); // payload prefix byte 0
      expect(frame[8], 0x00); // payload prefix byte 1
      expect(frame[9], 0x00); // state = 0
    });

    test('State 1 frame has payload 01 00 01 and correct parameter ID 0x12', () {
      final frame = Icp5FrameCodec.buildMasterMuteWrite(1);
      expect(frame[2], 0x1C);
      expect(frame[6], 0x12);
      expect(frame[7], 0x01);
      expect(frame[8], 0x00);
      expect(frame[9], 0x01); // state = 1
    });

    test('Only state 0 and state 1 are accepted — other values throw', () {
      expect(() => Icp5FrameCodec.buildMasterMuteWrite(2), throwsArgumentError);
      expect(() => Icp5FrameCodec.buildMasterMuteWrite(-1), throwsArgumentError);
    });

    test('Checksum is valid for both state frames', () {
      for (final state in [0, 1]) {
        final frame = Icp5FrameCodec.buildMasterMuteWrite(state);
        expect(Icp5FrameCodec.hasValidEnvelope(frame), isTrue,
            reason: 'State $state frame must have a valid ICP5 envelope');
      }
    });
  });

  group('Normal deploy path now allows mute — polarity confirmed', () {
    const kCh = DriverChannel(
      id: 'ch_tw_l',
      name: 'Tweeter L',
      role: DriverRole.tweeter,
      side: DriverSide.left,
      dspOutputIndex: 1,
    );

    test('muted channel produces captureProven writable op in write plan', () {
      final base = TuningProjectState.createDefault();
      final ctrl = base.getOrCreateControl(kCh.id).copyWith(muted: true);
      final tuning = base.replaceControl(ctrl);
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [kCh],
        tuning: tuning,
      );
      final plan = buildHardwareWritePlan(
        DspExportPackage(id: 'diag_mute_deploy_test', parameterBlocks: blocks),
        HardwareDeviceProfiles.adau1701Icp5,
      );
      final op = plan.operations
          .firstWhere((o) => o.parameterKind == HardwareParamKind.channelMute);
      expect(op.writable, isTrue,
          reason: 'Mute is now captureProven — State 0=MUTED, polarity confirmed');
      expect(op.verification, HardwareParamVerification.captureProven);
    });

    test('delay channel produces unavailable op in write plan', () {
      final base = TuningProjectState.createDefault();
      final ctrl = base.getOrCreateControl(kCh.id).copyWith(delayMs: 2.0);
      final tuning = base.replaceControl(ctrl);
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [kCh],
        tuning: tuning,
      );
      final plan = buildHardwareWritePlan(
        DspExportPackage(id: 'diag_delay_block_test', parameterBlocks: blocks),
        HardwareDeviceProfiles.adau1701Icp5,
      );
      final op = plan.operations
          .firstWhere((o) => o.parameterKind == HardwareParamKind.channelDelay);
      expect(op.writable, isFalse,
          reason: 'Delay must remain blocked in the production deploy path');
      expect(op.verification, HardwareParamVerification.unavailable);
    });
  });

  group('Delay diagnostic frame encoding', () {
    test('Only captured values 1.0 and 0.04 are accepted per channel', () {
      for (var ch = 0; ch < 4; ch++) {
        expect(
            () => Icp5FrameCodec.buildDelayCandidateWrite(ch, 1.0),
            returnsNormally,
            reason: 'ch$ch TEST value 1.0 must be accepted');
        expect(
            () => Icp5FrameCodec.buildDelayCandidateWrite(ch, 0.04),
            returnsNormally,
            reason: 'ch$ch RESTORE value 0.04 must be accepted');
        expect(
            () => Icp5FrameCodec.buildDelayCandidateWrite(ch, 0.5),
            throwsArgumentError,
            reason: 'Arbitrary delay value must be rejected');
      }
    });

    test('TEST and RESTORE frames are distinct for each channel', () {
      for (var ch = 0; ch < 4; ch++) {
        final testFrame = Icp5FrameCodec.buildDelayCandidateWrite(ch, 1.0);
        final restoreFrame = Icp5FrameCodec.buildDelayCandidateWrite(ch, 0.04);
        expect(testFrame, isNot(equals(restoreFrame)),
            reason: 'ch$ch TEST and RESTORE frames must differ');
        expect(Icp5FrameCodec.hasValidEnvelope(testFrame), isTrue);
        expect(Icp5FrameCodec.hasValidEnvelope(restoreFrame), isTrue);
      }
    });

    test('Delay candidate parameter ID is 0x00000017', () {
      final frame = Icp5FrameCodec.buildDelayCandidateWrite(0, 1.0);
      // Bytes [3..6] are the parameter ID in big-endian
      expect(frame[3], 0x00);
      expect(frame[4], 0x00);
      expect(frame[5], 0x00);
      expect(frame[6], 0x17);
    });
  });
}
