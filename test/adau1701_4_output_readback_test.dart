// ADAU1701 4-Output Readback — decoder + offset separation + UI helper tests.
//
// Verifies that the 513-byte 0x2202 payload is split into 4 independent output
// channels at the correct byte offsets, and that UI binding helpers convert the
// decoded bands correctly.
//
// Offset layout (capture-proven Ch0; Ch1-3 stride-60 candidates):
//   Ch0 Band0: payload[19]  Ch1 Band0: payload[79]
//   Ch2 Band0: payload[139] Ch3 Band0: payload[199]
//
// Band encoding (6 bytes each):
//   +0 freqLo  +1 freqHi  +2 gain(int8×0.1dB)  +3 pad  +4 Q(uint8×0.1)  +5 prop08
//
// Groups:
//   1. 4-output decode structure   — outputs length, bands per output, index
//   2. Output offset separation    — independent values at each channel offset
//   3. Ch0 Band1 regression        — 1800 Hz / 0.0 dB / Q1.20 unchanged
//   4. Graph binding helpers       — peqBandsToResponseBands / peqReferenceToBands

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_state_decoder.dart';
import 'package:tunai_pro/core/transport/adau1701_peq_band_decoder.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_dsp_state_read_card.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_peq_reference.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';

// Encodes one band into a payload at the given base offset.
void _writeBand(List<int> p, int base,
    {required int freqHz, required double gainDb, required double q}) {
  p[base] = freqHz & 0xFF;
  p[base + 1] = (freqHz >> 8) & 0xFF;
  final gainRaw = (gainDb * 10).round();
  p[base + 2] = gainRaw < 0 ? gainRaw + 256 : gainRaw;
  p[base + 4] = (q * 10).round();
}

// Builds a 513-byte payload with distinct Band0 values at each channel's offset.
// Page-boundary markers at offsets 154/308/462 allow all 4 pages to be accepted.
List<int> _buildMultiOutputPayload({
  ({int freqHz, double gainDb, double q}) ch0 = (
    freqHz: 1800,
    gainDb: 0.0,
    q: 1.2
  ),
  ({int freqHz, double gainDb, double q}) ch1 = (
    freqHz: 1800,
    gainDb: 0.0,
    q: 1.2
  ),
  ({int freqHz, double gainDb, double q}) ch2 = (
    freqHz: 1800,
    gainDb: 0.0,
    q: 1.2
  ),
  ({int freqHz, double gainDb, double q}) ch3 = (
    freqHz: 1800,
    gainDb: 0.0,
    q: 1.2
  ),
}) {
  final p = List<int>.filled(513, 0);
  p[154] = 0x01;
  p[308] = 0x02;
  p[462] = 0x03;
  _writeBand(p, 19, freqHz: ch0.freqHz, gainDb: ch0.gainDb, q: ch0.q);
  _writeBand(p, 79, freqHz: ch1.freqHz, gainDb: ch1.gainDb, q: ch1.q);
  _writeBand(p, 139, freqHz: ch2.freqHz, gainDb: ch2.gainDb, q: ch2.q);
  _writeBand(p, 199, freqHz: ch3.freqHz, gainDb: ch3.gainDb, q: ch3.q);
  return p;
}

RawDspStateSnapshot _buildSnapshot(List<int> payload) => RawDspStateSnapshot(
      deviceId: _kDeviceId,
      timestamp: DateTime.utc(2026, 8, 5),
      blockId: 0x2202,
      payload: payload,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Group 1: 4-output decode structure ──────────────────────────────────────

  group('4-output decode structure', () {
    late Adau1701StateSnapshot snap;

    setUp(() {
      snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(),
      ));
    });

    test('decode() produces exactly 4 output entries', () {
      expect(snap.outputs.length, 4);
    });

    test('each output has exactly 10 PEQ bands', () {
      for (final out in snap.outputs) {
        expect(out.peqBands.length, 10,
            reason: 'output ${out.outputIndex} has wrong band count');
      }
    });

    test('outputIndex matches position in list', () {
      for (var i = 0; i < snap.outputs.length; i++) {
        expect(snap.outputs[i].outputIndex, i);
      }
    });

    test('Ch0 is channel-layout proven; Ch1-3 are not', () {
      expect(snap.outputs[0].isChannelLayoutProven, isTrue);
      expect(snap.outputs[1].isChannelLayoutProven, isFalse);
      expect(snap.outputs[2].isChannelLayoutProven, isFalse);
      expect(snap.outputs[3].isChannelLayoutProven, isFalse);
    });

    test('Band0 of each output has bandIndex 0', () {
      for (final out in snap.outputs) {
        expect(out.peqBands.first.bandIndex, 0,
            reason: 'output ${out.outputIndex} Band0 wrong bandIndex');
      }
    });

    test('Band9 of each output has bandIndex 9', () {
      for (final out in snap.outputs) {
        expect(out.peqBands.last.bandIndex, 9,
            reason: 'output ${out.outputIndex} Band9 wrong bandIndex');
      }
    });
  });

  // ── Group 2: Output offset separation ────────────────────────────────────────

  group('output offset separation', () {
    // Each channel gets a unique Band0 so that decoding the wrong offset
    // produces a visible mismatch in freq.
    late Adau1701StateSnapshot snap;

    setUp(() {
      snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(
          ch0: (freqHz: 1800, gainDb: 0.0, q: 1.2),  // Tweeter L confirmed
          ch1: (freqHz: 2400, gainDb: 0.5, q: 1.0),  // Tweeter R candidate
          ch2: (freqHz: 60, gainDb: 0.5, q: 1.0),    // Woofer L candidate
          ch3: (freqHz: 60, gainDb: 0.5, q: 1.0),    // Woofer R candidate
        ),
      ));
    });

    test('Ch0 Band0 decodes from offset 19 → 1800 Hz', () {
      expect(snap.outputs[0].peqBands[0].frequencyHz, 1800);
    });

    test('Ch1 Band0 decodes from offset 79 → 2400 Hz (independent of Ch0)', () {
      expect(snap.outputs[1].peqBands[0].frequencyHz, 2400);
    });

    test('Ch2 Band0 decodes from offset 139 → 60 Hz (Woofer L)', () {
      expect(snap.outputs[2].peqBands[0].frequencyHz, 60);
    });

    test('Ch3 Band0 decodes from offset 199 → 60 Hz (Woofer R)', () {
      expect(snap.outputs[3].peqBands[0].frequencyHz, 60);
    });

    test('Ch2/Ch3 Band0 gain decodes to 0.5 dB', () {
      expect(snap.outputs[2].peqBands[0].gainDb, closeTo(0.5, 0.01));
      expect(snap.outputs[3].peqBands[0].gainDb, closeTo(0.5, 0.01));
    });

    test('Ch2/Ch3 Band0 Q decodes to 1.0', () {
      expect(snap.outputs[2].peqBands[0].q, closeTo(1.0, 0.01));
      expect(snap.outputs[3].peqBands[0].q, closeTo(1.0, 0.01));
    });

    test('Ch0 and Ch1 Band0 frequencies are different (no bleed between channels)',
        () {
      expect(snap.outputs[0].peqBands[0].frequencyHz,
          isNot(snap.outputs[1].peqBands[0].frequencyHz));
    });

    test('Ch1 and Ch2 Band0 frequencies are different', () {
      expect(snap.outputs[1].peqBands[0].frequencyHz,
          isNot(snap.outputs[2].peqBands[0].frequencyHz));
    });

    test('baseOffsetForBand returns 19 for ch0/band0', () {
      expect(Adau1701PeqBandDecoder.baseOffsetForBand(0, channel: 0), 19);
    });

    test('baseOffsetForBand returns 79 for ch1/band0', () {
      expect(Adau1701PeqBandDecoder.baseOffsetForBand(0, channel: 1), 79);
    });

    test('baseOffsetForBand returns 139 for ch2/band0', () {
      expect(Adau1701PeqBandDecoder.baseOffsetForBand(0, channel: 2), 139);
    });

    test('baseOffsetForBand returns 199 for ch3/band0', () {
      expect(Adau1701PeqBandDecoder.baseOffsetForBand(0, channel: 3), 199);
    });
  });

  // ── Group 3: Ch0 Band1 regression ────────────────────────────────────────────

  group('Ch0 Band1 regression', () {
    test('Ch0 Band0 hardware-confirmed values unchanged (1800 Hz / 0.0 dB / Q1.20)',
        () {
      final snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(ch0: (freqHz: 1800, gainDb: 0.0, q: 1.2)),
      ));
      final band = snap.outputs[0].peqBands[0];
      expect(band.frequencyHz, 1800);
      expect(band.gainDb, closeTo(0.0, 0.01));
      expect(band.q, closeTo(1.2, 0.01));
    });

    test('Ch0 Band0 is marked verified', () {
      final snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(ch0: (freqHz: 1800, gainDb: 0.0, q: 1.2)),
      ));
      expect(snap.outputs[0].peqBands[0].verificationStatus,
          PeqBandVerificationStatus.verified);
    });

    test('Ch0 Band0 changes do NOT affect Ch1 Band0 (no cross-channel bleed)', () {
      final snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(
          ch0: (freqHz: 9999, gainDb: 2.0, q: 5.0),
          ch1: (freqHz: 2400, gainDb: 0.5, q: 1.0),
        ),
      ));
      expect(snap.outputs[0].peqBands[0].frequencyHz, 9999);
      expect(snap.outputs[1].peqBands[0].frequencyHz, 2400);
    });
  });

  // ── Group 4: Graph binding helpers ───────────────────────────────────────────

  group('graph binding helpers', () {
    test('peqBandsToResponseBands converts all 10 bands for each output', () {
      final snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(ch2: (freqHz: 60, gainDb: 0.5, q: 1.0)),
      ));
      for (final out in snap.outputs) {
        final responseBands = peqBandsToResponseBands(out.peqBands);
        expect(responseBands.length, 10,
            reason: 'output ${out.outputIndex} wrong response band count');
      }
    });

    test('peqBandsToResponseBands preserves Ch0 Band0 frequency', () {
      final snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(ch0: (freqHz: 1800, gainDb: 0.0, q: 1.2)),
      ));
      final rb = peqBandsToResponseBands(snap.outputs[0].peqBands);
      expect(rb[0].frequencyHz, closeTo(1800.0, 0.1));
    });

    test('peqBandsToResponseBands preserves Ch2 Band0 frequency (60 Hz Woofer)', () {
      final snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(ch2: (freqHz: 60, gainDb: 0.5, q: 1.0)),
      ));
      final rb = peqBandsToResponseBands(snap.outputs[2].peqBands);
      expect(rb[0].frequencyHz, closeTo(60.0, 0.1));
    });

    test('peqBandsToResponseBands all bands enabled=true', () {
      final snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(),
      ));
      for (final b in peqBandsToResponseBands(snap.outputs[0].peqBands)) {
        expect(b.enabled, isTrue);
      }
    });

    test('peqReferenceToBands produces 10 bands from Ch0 reference', () {
      final refs = Adau1701MiuMaxPeqReference.forChannel(0)!;
      final bands = peqReferenceToBands(refs);
      expect(bands.length, 10);
    });

    test('peqReferenceToBands Ch0 Band0 frequency is 1800 Hz', () {
      final refs = Adau1701MiuMaxPeqReference.forChannel(0)!;
      final bands = peqReferenceToBands(refs);
      expect(bands[0].frequencyHz, closeTo(1800.0, 0.1));
    });

    test('peqReferenceToBands Ch2 (Woofer L) Band0 frequency is 60 Hz', () {
      final refs = Adau1701MiuMaxPeqReference.forChannel(2)!;
      final bands = peqReferenceToBands(refs);
      expect(bands[0].frequencyHz, closeTo(60.0, 0.1));
    });

    test('output selector drives different data: Ch0 vs Ch2 Band0 freq differ', () {
      final snap = Adau1701StateDecoder.decode(_buildSnapshot(
        _buildMultiOutputPayload(
          ch0: (freqHz: 1800, gainDb: 0.0, q: 1.2),
          ch2: (freqHz: 60, gainDb: 0.5, q: 1.0),
        ),
      ));
      // Simulate: user selects output 0, then output 2
      final ch0Bands = peqBandsToResponseBands(snap.outputs[0].peqBands);
      final ch2Bands = peqBandsToResponseBands(snap.outputs[2].peqBands);
      expect(ch0Bands[0].frequencyHz, isNot(ch2Bands[0].frequencyHz));
      expect(ch0Bands[0].frequencyHz, closeTo(1800.0, 0.1));
      expect(ch2Bands[0].frequencyHz, closeTo(60.0, 0.1));
    });
  });
}
