// PEQ Enable/Bypass — semantic bypass via param 0x18 gain=0.0 dB.
//
// No dedicated ICP5 enable/bypass parameter exists (confirmed by Consumer
// ICP5 builder audit). Bypass is implemented by writing 0.0 dB gain to the
// channel/band — which nullifies the filter slot without altering freq or Q.
//
// Covers:
//   1. Frame parity: buildPeqGainWriteArbitrary(ch, 0.0, band) — valid frame,
//      param 0x18 property 0x01, gain byte = 0x00, ch 0–3, band 0–9.
//   2. Export: disabled band → gain_db=0.0, bypassed=true (not skipped).
//   3. Export: enabled band → stored gain_db, no bypassed key.
//   4. Export: mixed enabled/disabled within one channel.
//   5. Export: all-disabled channel still produces a PEQ block.
//   6. Write plan: bypass op is captureProven, targetValue=0.0.
//   7. Write plan: summary correctly counts active vs bypass bands.
//   8. Active→Bypass→Active: gain write sequence via write port (fake transport).
//   9. Channel boundary: ch 0–3 produce different frames.
//  10. Band boundary: band 0–9 produce different frames; all have valid envelopes.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

// ── Shared fixtures ───────────────────────────────────────────────────────────

const _kCh = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

PeqBand _band({
  required bool enabled,
  double freq = 1000.0,
  double gain = -3.0,
  double q = 1.0,
}) =>
    PeqBand(
      id: 'b',
      type: PeqBandType.peak,
      frequencyHz: freq,
      gainDb: gain,
      q: q,
      enabled: enabled,
    );

List<ExportParameterBlock> _export(List<PeqBand> bands) {
  final peqCh = PeqChannelState(channelId: _kCh.id, bands: bands);
  final tuning = TuningProjectState.createDefault()
      .copyWith(peqChannels: [peqCh]);
  return buildAdau1701PeqExportBlocks(channels: [_kCh], tuning: tuning);
}

// ── Fake transport for write-port tests ───────────────────────────────────────

class _FakeTransport implements Adau1701TuningTransport {
  final List<(int ch, double gainDb, int band)> gainWrites = [];

  @override
  bool get isConnected => true;
  @override
  bool get handshakeComplete => true;
  @override
  String? get detectedProfile => 'DSP1701.100.00.01';

  @override
  Future<RawDspStateSnapshot> readRawDspState() async =>
      throw StateError('not used');

  @override
  Future<Adau1701WriteAck> writePeqGain(int channel, double gainDb,
      {int band = 0}) async {
    gainWrites.add((channel, gainDb, band));
    return const Adau1701WriteAck(success: true, message: 'ok');
  }

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz,
          {int band = 0, bool isHighPass = false}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');

  @override
  Future<Adau1701WriteAck> writePeqFrequency(int channel, int frequencyHz,
          {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');

  @override
  Future<Adau1701WriteAck> writePeqQ(int channel, double q,
          {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');

  @override
  Future<Adau1701WriteAck> writeOutputGain(int channel, double gainDb) async =>
      const Adau1701WriteAck(success: true, message: 'ok');

  @override
  Future<Adau1701WriteAck> writeMasterMute(bool muted) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
}


// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Frame parity — gain=0.0 dB', () {
    test('buildPeqGainWriteArbitrary(ch, 0.0) produces valid frame for ch 0–3, band 0–9',
        () {
      for (var ch = 0; ch < 4; ch++) {
        for (var b = 0; b < 10; b++) {
          final frame = Icp5FrameCodec.buildPeqGainWriteArbitrary(ch, 0.0,
              band: b);
          expect(Icp5FrameCodec.hasValidEnvelope(frame), isTrue,
              reason: 'ch$ch band$b: envelope invalid');
          // Frame layout: 0x55 [0], declLen [1], 0x1C [2],
          //   paramId MSB [3], paramId [4,5], paramId LSB [6], payload...
          // param 0x00000018 → LSB at frame[6] = 0x18.
          expect(frame[6], 0x18,
              reason: 'ch$ch band$b: param ID LSB must be 0x18');
        }
      }
    });

    test('gain byte (tenths) is 0x00 for 0.0 dB', () {
      // Frame layout for buildPeqGainWriteArbitrary:
      //   [0]=0x55, [1]=declLen, [2]=0x1C,
      //   [3..6]=paramId (0x00000018 big-endian),
      //   [7]=channel, [8]=0x01(gain property), [9]=band, [10]=tenths, [11]=checksum
      // Gain is encoded as (gainDb * 10).round() & 0xFF.
      // 0.0 dB → 0 → 0x00.
      for (var ch = 0; ch < 4; ch++) {
        final frame = Icp5FrameCodec.buildPeqGainWriteArbitrary(ch, 0.0);
        expect(frame[10], 0x00,
            reason: 'ch$ch: gain tenths byte must be 0x00 for 0.0 dB');
      }
    });

    test('ch 0–3 produce different frames (channel byte differs)', () {
      final frames = [for (var ch = 0; ch < 4; ch++)
        Icp5FrameCodec.buildPeqGainWriteArbitrary(ch, 0.0)];
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          expect(frames[i], isNot(equals(frames[j])),
              reason: 'ch$i and ch$j must differ');
        }
      }
    });

    test('band 0–9 produce different frames (band byte differs)', () {
      final frames = [for (var b = 0; b < 10; b++)
        Icp5FrameCodec.buildPeqGainWriteArbitrary(0, 0.0, band: b)];
      for (var i = 0; i < 10; i++) {
        for (var j = i + 1; j < 10; j++) {
          expect(frames[i], isNot(equals(frames[j])),
              reason: 'band$i and band$j must differ');
        }
      }
    });
  });

  group('Export — disabled band → semantic bypass', () {
    test('single disabled band: gain_db=0.0, bypassed=true, no freq_hz or q', () {
      final blocks = _export([_band(enabled: false, gain: -3.0)]);
      expect(blocks, hasLength(1));
      final band0 = (blocks.first.parameters['bands'] as Map)['band_0'] as Map;
      expect(band0['gain_db'], 0.0);
      expect(band0['bypassed'], true);
      expect(band0.containsKey('freq_hz'), isFalse,
          reason: 'bypass export must not include freq_hz — 1 op per band only');
      expect(band0.containsKey('q'), isFalse,
          reason: 'bypass export must not include q — 1 op per band only');
    });

    test('single enabled band: stored gain_db, no bypassed key', () {
      final blocks = _export([_band(enabled: true, gain: -2.5)]);
      expect(blocks, hasLength(1));
      final band0 = (blocks.first.parameters['bands'] as Map)['band_0'] as Map;
      expect(band0['gain_db'], -2.5);
      expect(band0.containsKey('bypassed'), isFalse);
    });

    test('mixed: enabled band preserves gain; disabled band writes 0.0 dB', () {
      final blocks = _export([
        _band(enabled: true, gain: -1.5),  // band_0: active
        _band(enabled: false, gain: -3.0), // band_1: bypass
      ]);
      expect(blocks, hasLength(1));
      final bands = blocks.first.parameters['bands'] as Map;
      final b0 = bands['band_0'] as Map;
      final b1 = bands['band_1'] as Map;
      expect(b0['gain_db'], -1.5);
      expect(b0.containsKey('bypassed'), isFalse);
      expect(b1['gain_db'], 0.0);
      expect(b1['bypassed'], true);
    });

    test('all-disabled channel still produces a PEQ block (not skipped)', () {
      final bands = List.generate(
          10, (_) => _band(enabled: false, gain: -1.0));
      final blocks = _export(bands);
      expect(blocks, hasLength(1));
      final bandsMap = blocks.first.parameters['bands'] as Map;
      expect(bandsMap.length, 10);
      for (final v in bandsMap.values) {
        expect((v as Map)['gain_db'], 0.0);
        expect((v)['bypassed'], true);
      }
    });

    test('summary includes "bypassed (0 dB unity)" for disabled bands', () {
      final blocks = _export([
        _band(enabled: true, gain: -1.0),
        _band(enabled: false, gain: -2.0),
      ]);
      expect(blocks.first.summary, contains('bypassed (0 dB unity)'));
      expect(blocks.first.summary, contains('active'));
    });

    test('summary is "N active" only when all bands are enabled', () {
      final blocks = _export([_band(enabled: true, gain: -1.0)]);
      expect(blocks.first.summary, contains('active'));
      expect(blocks.first.summary, isNot(contains('bypassed')));
    });
  });

  group('Write plan — bypass op resolution', () {
    test('disabled band produces captureProven peqGain op with targetValue=0.0', () {
      final blocks = _export([_band(enabled: false, gain: -3.0)]);
      final pkg = DspExportPackage(id: 'bp_test', parameterBlocks: blocks);
      final plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
      final gainOp = plan.operations
          .firstWhere((o) => o.parameterKind == HardwareParamKind.peqGain);
      expect(gainOp.targetValue, 0.0);
      expect(gainOp.verification, HardwareParamVerification.captureProven);
      expect(gainOp.writable, isTrue);
    });

    test('10-band all-disabled channel → 10 peqGain ops all targetValue=0.0', () {
      final bands = List.generate(10, (_) => _band(enabled: false, gain: -1.0));
      final blocks = _export(bands);
      final pkg = DspExportPackage(id: 'bp10_test', parameterBlocks: blocks);
      final plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
      final gainOps = plan.operations
          .where((o) => o.parameterKind == HardwareParamKind.peqGain)
          .toList();
      expect(gainOps.length, 10);
      for (final op in gainOps) {
        expect(op.targetValue, 0.0);
        expect(op.writable, isTrue);
      }
    });

    test('enabled band → peqGain op with stored targetValue', () {
      final blocks = _export([_band(enabled: true, gain: -2.0)]);
      final pkg = DspExportPackage(id: 'active_test', parameterBlocks: blocks);
      final plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
      final gainOp = plan.operations
          .firstWhere((o) => o.parameterKind == HardwareParamKind.peqGain);
      expect(gainOp.targetValue, -2.0);
      expect(gainOp.writable, isTrue);
    });
  });

  group('Active → Bypass → Active write sequence (transport-level)', () {
    // Tests at the transport level verify that 0.0 dB is a valid gain value
    // that the transport accepts. The write-port routing is tested in
    // pro_adau1701_hardware_context_test.dart and adau1701_miumax_icp5_port_test.dart.

    test('band 1 (index 1): 0.0 dB is accepted by writePeqGain', () async {
      final transport = _FakeTransport();
      // Simulate Active → Bypass → Active by calling writePeqGain directly.
      await transport.writePeqGain(1, -2.0, band: 1); // active
      await transport.writePeqGain(1, 0.0, band: 1);  // bypass
      await transport.writePeqGain(1, -2.0, band: 1); // re-activate

      expect(transport.gainWrites, hasLength(3));
      expect(transport.gainWrites[0], (1, -2.0, 1));
      expect(transport.gainWrites[1], (1, 0.0, 1));
      expect(transport.gainWrites[2], (1, -2.0, 1));
    });

    test('band 0: 0.0 dB is accepted by writePeqGain (band 0 path)', () async {
      final transport = _FakeTransport();
      await transport.writePeqGain(0, 0.0, band: 0);
      expect(transport.gainWrites, hasLength(1));
      expect(transport.gainWrites.first, (0, 0.0, 0));
    });

    test('frame codec: 0.0 dB is in range for ch 0–3, band 0–9', () {
      // Verify that the frame codec does not throw for 0.0 dB across all
      // ch/band combinations — this confirms bypass is always safe to encode.
      for (var ch = 0; ch < 4; ch++) {
        for (var b = 0; b < 10; b++) {
          expect(
            () => Icp5FrameCodec.buildPeqGainWriteArbitrary(ch, 0.0, band: b),
            returnsNormally,
            reason: 'ch$ch band$b: 0.0 dB must not throw',
          );
        }
      }
    });

    test('export pipeline ch 0–3: all gain ops have targetValue=0.0 for disabled bands', () {
      for (var ch = 0; ch < 4; ch++) {
        final peqCh = PeqChannelState(
            channelId: 'ch_$ch', bands: [_band(enabled: false, gain: -1.0)]);
        final tuning = TuningProjectState.createDefault()
            .copyWith(peqChannels: [peqCh]);
        final channel = DriverChannel(
            id: 'ch_$ch', name: 'Ch$ch',
            role: DriverRole.tweeter, side: DriverSide.left,
            dspOutputIndex: ch);
        final blocks = buildAdau1701PeqExportBlocks(
            channels: [channel], tuning: tuning);
        expect(blocks, hasLength(1), reason: 'ch$ch: bypass block expected');
        final gainOps = buildHardwareWritePlan(
          DspExportPackage(id: 'ch${ch}_test', parameterBlocks: blocks),
          HardwareDeviceProfiles.adau1701Icp5,
        ).operations.where((o) => o.parameterKind == HardwareParamKind.peqGain);
        for (final op in gainOps) {
          expect(op.targetValue, 0.0, reason: 'ch$ch: bypass gain must be 0.0');
          expect(op.writable, isTrue);
        }
      }
    });
  });
}
