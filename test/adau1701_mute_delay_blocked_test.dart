// Verifies that mute and delay channel control state:
//   1. Is exported to ExportParameterBlocks by buildAdau1701MuteDelayExportBlocks()
//   2a. Mute resolves as captureProven (writable) — State 0=MUTED, polarity confirmed.
//   2b. Delay resolves as unavailable (Blocked) — unit unknown, channelDelay not confirmed.
//   3. Disabled PEQ bands export with gain=0.0 dB (semantic bypass) — not skipped.
//      Skipping leaves stale DSP values; 0.0 dB nullifies the filter slot safely.
//
// These tests MUST NOT change the existing captureProven assertions for
// channelGain, PEQ gain/freq/q, and crossover in pro_hardware_write_plan_test.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _kCh = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

TuningProjectState _tuningWith({bool muted = false, double delayMs = 0.0}) {
  final base = TuningProjectState.createDefault();
  final ctrl =
      base.getOrCreateControl(_kCh.id).copyWith(muted: muted, delayMs: delayMs);
  return base.replaceControl(ctrl);
}

HardwareWriteOp _findOp(HardwareWritePlan plan, HardwareParamKind kind) =>
    plan.operations.firstWhere((o) => o.parameterKind == kind);

void main() {
  group('buildAdau1701MuteDelayExportBlocks', () {
    test('emits no blocks when mute=false and delayMs=0', () {
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [_kCh],
        tuning: TuningProjectState.createDefault(),
      );
      expect(blocks, isEmpty);
    });

    test('emits a block with muted=true when channel is muted', () {
      final tuning = _tuningWith(muted: true);
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [_kCh],
        tuning: tuning,
      );
      expect(blocks, hasLength(1));
      expect(blocks.first.channelId, _kCh.id);
      expect(blocks.first.parameters['muted'], isTrue);
      expect(blocks.first.parameters.containsKey('delayMs'), isFalse);
    });

    test('emits a block with delayMs when channel has delay', () {
      final tuning = _tuningWith(delayMs: 1.5);
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [_kCh],
        tuning: tuning,
      );
      expect(blocks, hasLength(1));
      expect(blocks.first.parameters['delayMs'], 1.5);
      expect(blocks.first.parameters.containsKey('muted'), isFalse);
    });

    test('emits one block with both fields when muted and delay are both set', () {
      final tuning = _tuningWith(muted: true, delayMs: 2.0);
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [_kCh],
        tuning: tuning,
      );
      expect(blocks, hasLength(1));
      expect(blocks.first.parameters['muted'], isTrue);
      expect(blocks.first.parameters['delayMs'], 2.0);
    });

    test('emits no block for a channel that does not appear in the channels list', () {
      const other = DriverChannel(
        id: 'ch_wf_r',
        name: 'Woofer R',
        role: DriverRole.woofer,
        side: DriverSide.right,
        dspOutputIndex: 4,
      );
      final tuning = _tuningWith(muted: true);
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [other], // _kCh not listed
        tuning: tuning,
      );
      expect(blocks, isEmpty);
    });
  });

  group('mute → captureProven (writable) in ADAU1701 ICP5 write plan', () {
    test('channelMute op is captureProven — State 0=MUTED, polarity confirmed', () {
      final tuning = _tuningWith(muted: true);
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [_kCh],
        tuning: tuning,
      );
      final plan = buildHardwareWritePlan(
        DspExportPackage(id: 'test_mute', parameterBlocks: blocks),
        HardwareDeviceProfiles.adau1701Icp5,
      );
      final op = _findOp(plan, HardwareParamKind.channelMute);
      expect(op.writable, isTrue);
      expect(op.verification, HardwareParamVerification.captureProven);
      expect(op.targetValue, 1);
    });
  });

  group('delay → unavailable in ADAU1701 ICP5 write plan', () {
    test('channelDelay op is unavailable (Blocked) — channelDelay not confirmed', () {
      final tuning = _tuningWith(delayMs: 3.5);
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [_kCh],
        tuning: tuning,
      );
      final plan = buildHardwareWritePlan(
        DspExportPackage(id: 'test_delay', parameterBlocks: blocks),
        HardwareDeviceProfiles.adau1701Icp5,
      );
      final op = _findOp(plan, HardwareParamKind.channelDelay);
      expect(op.writable, isFalse);
      expect(op.verification, HardwareParamVerification.unavailable);
      expect(op.targetValue, 3.5);
    });

    test('mute op is writable; delay op is unavailable when both present', () {
      final tuning = _tuningWith(muted: true, delayMs: 1.0);
      final blocks = buildAdau1701MuteDelayExportBlocks(
        channels: [_kCh],
        tuning: tuning,
      );
      final plan = buildHardwareWritePlan(
        DspExportPackage(id: 'test_both', parameterBlocks: blocks),
        HardwareDeviceProfiles.adau1701Icp5,
      );
      expect(plan.writableOperations.length, 1); // only mute is writable
      expect(plan.writableOperations.first.parameterKind,
          HardwareParamKind.channelMute);
      expect(plan.summary.unavailableCount, 1); // delay only
    });
  });

  group('PEQ enable/bypass — semantic bypass via gain=0.0 dB', () {
    test('disabled PEQ band exports with gain_db=0.0 (semantic bypass, not skipped)', () {
      final disabledBand = PeqBand(
        id: 'band_0',
        type: PeqBandType.peak,
        frequencyHz: 1000,
        gainDb: -3.0,
        q: 1.0,
        enabled: false,
      );
      final peqCh = PeqChannelState(
        channelId: _kCh.id,
        bands: [disabledBand],
      );
      final tuning = TuningProjectState.createDefault()
          .copyWith(peqChannels: [peqCh]);
      final blocks = buildAdau1701PeqExportBlocks(
        channels: [_kCh],
        tuning: tuning,
      );
      expect(blocks, hasLength(1),
          reason: 'Disabled band exports with 0.0 dB to clear stale DSP values.');
      final bandsMap = blocks.first.parameters['bands'] as Map;
      expect(bandsMap.length, 1);
      final band0 = bandsMap['band_0'] as Map;
      expect(band0['gain_db'], 0.0,
          reason: 'Bypass: gain_db must be 0.0 dB (unity — nullifies filter).');
      expect(band0['bypassed'], true);
      expect(band0.containsKey('freq_hz'), isFalse,
          reason: 'Bypass export must not include freq_hz — only 1 op per band.');
    });

    test('enabled PEQ band exports with stored gain_db', () {
      final enabledBand = PeqBand(
        id: 'band_0',
        type: PeqBandType.peak,
        frequencyHz: 1000,
        gainDb: -3.0,
        q: 1.0,
        enabled: true,
      );
      final peqCh = PeqChannelState(
        channelId: _kCh.id,
        bands: [enabledBand],
      );
      final tuning = TuningProjectState.createDefault()
          .copyWith(peqChannels: [peqCh]);
      final blocks = buildAdau1701PeqExportBlocks(
        channels: [_kCh],
        tuning: tuning,
      );
      expect(blocks, hasLength(1));
      final band0 = (blocks.first.parameters['bands'] as Map)['band_0'] as Map;
      expect(band0['gain_db'], -3.0);
      expect(band0.containsKey('bypassed'), isFalse);
    });

    test('disabled band produces captureProven peqGain op with targetValue=0.0', () {
      final disabledBand = PeqBand(
        id: 'band_0',
        type: PeqBandType.peak,
        frequencyHz: 1000,
        gainDb: -3.0,
        q: 1.0,
        enabled: false,
      );
      final peqCh = PeqChannelState(channelId: _kCh.id, bands: [disabledBand]);
      final tuning = TuningProjectState.createDefault()
          .copyWith(peqChannels: [peqCh]);
      final blocks = buildAdau1701PeqExportBlocks(
          channels: [_kCh], tuning: tuning);
      final pkg = DspExportPackage(id: 'test_bypass', parameterBlocks: blocks);
      final plan =
          buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
      final gainOp = plan.operations
          .firstWhere((o) => o.parameterKind == HardwareParamKind.peqGain);
      expect(gainOp.targetValue, 0.0,
          reason: 'Bypass gain op must target 0.0 dB.');
      expect(gainOp.verification, HardwareParamVerification.captureProven);
      expect(gainOp.writable, isTrue);
    });
  });
}
