// EXPERIMENTAL / ISOLATED HARNESS — NOT part of the proven production suite.
//
// Purpose: exercise the existing, currently-unreachable
// lib/core/dsp/adau1701_adapter.dart "direct PRAM write" path in isolation,
// to see and log the exact bytes it would send, WITHOUT touching any real
// transport and WITHOUT going anywhere near the Workbench Deploy flow
// (lib/features/workbench/, lib/core/deploy/). No file under those two
// directories is imported here.
//
// ── Two separate ADAU1701 write paths exist in this repo — do not conflate ──
//
// 1. PROVEN, PRODUCTION path (unrelated to this file):
//    lib/core/transport/icp5_frame_codec.dart + lib/core/deploy/*
//    Frame: 0x55, length, 0x1C, 0,0,0, paramID, payload..., checksum.
//    "Parameter ID" abstraction (0x10 master volume, 0x12 mute, 0x14 gain,
//    0x15 filter cutoff FREQUENCY ONLY, 0x17 delay, 0x18 PEQ). Every one of
//    these IDs has real USB packet-capture evidence
//    (lib/core/transport/icp5_protocol_evidence.dart). This is the only
//    path wired into the running app (WorkbenchShell, showDeployDialog).
//    NO type/slope/coefficient parameter ID exists in this path.
//
// 2. UNPROVEN CANDIDATE path (what this harness exercises):
//    lib/core/dsp/adau1701_adapter.dart + lib/core/dsp_engine.dart
//    Frame: 0xAA, addr(2B BE), data(5 words x 4B BE, 5.23 fixed-point),
//    XOR checksum, 0x55. Writes raw ADAU1701 PRAM cells directly — no
//    "parameter ID" abstraction at all, so it CAN reach biquad coefficient
//    cells (which the proven path structurally cannot). The specific PRAM
//    addresses (16-55, one 5-word block per HPF/LPF per DAC) come from
//    SigmaStudio EXPORT-FILE analysis and the user's own schematic
//    inspection (see HANDOFF.md) — NOT from a live hardware packet capture,
//    and NOT ACK-confirmed. This whole subsystem (Adau1701Adapter,
//    DspController, DspScreen, ConnectScreen) is unreachable from
//    lib/main.dart today — confirmed by grep: nothing outside
//    lib/features/dsp//lib/features/connect/ references it.
//
// This file does not change that evidence status. It only proves the code
// *compiles and runs* end-to-end and shows exactly what bytes it would
// produce, so a human reviewer (or a future real capture) has something
// concrete to compare against — it does not, and must not be read as,
// confirmation that these addresses/frames are correct on real hardware.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/dsp/adau1701_adapter.dart';
import 'package:tunai_pro/core/dsp/adau1701_crossover_filter_engine.dart'
    as fe;
import 'package:tunai_pro/core/dsp/dsp_adapter.dart' as legacy;
import 'package:tunai_pro/core/pro_tuning_data.dart' show FilterSide, CrossoverFilterType, CrossoverSlope;

/// Records every frame the adapter attempts to send, in order. Never touches
/// a real transport — this is the whole point of "isolated".
class _RecordingSink {
  final List<List<int>> sentFrames = [];
  Future<bool> send(List<int> bytes) async {
    sentFrames.add(List<int>.unmodifiable(bytes));
    return true;
  }
}

/// Decodes an Adau1701Adapter/DspEngine PRAM frame back into its fields,
/// purely for test assertions/logging — mirrors _buildFrame's ACTUAL byte
/// layout (see dsp_engine.dart:_buildFrame), does not modify it.
///
/// AUDIT FINDING (discovered by this harness, not assumed going in): the
/// header comment in both adau1701_adapter.dart and dsp_engine.dart claims
/// "[0xAA][Addr 2B][Data 20B][XOR][0x55] = 27바이트", but 1+2+20+1+1 = 25,
/// not 27. _buildFrame allocates Uint8List(27) yet only ever writes indices
/// 0..24 — indices 25 and 26 are left at Dart's default zero-fill and are
/// NOT the checksum/trailer. The real checksum is at index 23, the real
/// trailer at index 24, and the frame carries two trailing zero bytes that
/// don't appear in the docstring at all. This is a genuine, previously
/// undocumented inconsistency in this (already-unproven, already-dead-code)
/// path — one more reason it needs real hardware verification, not reuse
/// as-is, before ever being resurrected.
({int addr, List<int> rawWords, int checksum, int trailer, List<int> trailingPadding})
    _decodeFrame(List<int> frame) {
  expect(frame.length, 27, reason: 'buffer is allocated as 27 bytes');
  expect(frame[0], 0xAA);
  final addr = (frame[1] << 8) | frame[2];
  final words = <int>[];
  for (var w = 0; w < 5; w++) {
    final base = 3 + w * 4;
    words.add((frame[base] << 24) |
        (frame[base + 1] << 16) |
        (frame[base + 2] << 8) |
        frame[base + 3]);
  }
  var checksum = 0;
  for (var i = 0; i < 23; i++) {
    checksum ^= frame[i];
  }
  expect(frame[23], checksum, reason: 'XOR checksum (actual offset 23, not 25)');
  expect(frame[24], 0x55, reason: 'trailer byte (actual offset 24, not 26)');
  expect(frame[25], 0, reason: 'AUDIT: byte 25 is unwritten padding, not protocol data');
  expect(frame[26], 0, reason: 'AUDIT: byte 26 is unwritten padding, not protocol data');
  return (
    addr: addr,
    rawWords: words,
    checksum: checksum,
    trailer: frame[24],
    trailingPadding: [frame[25], frame[26]],
  );
}

/// Converts a raw 5.23 fixed-point word (as encoded by DspEngine.toFixed523)
/// back to a double, for cross-checking against the independently-computed
/// filter-engine coefficient.
double _decodeFixed523(int raw) {
  // toFixed523 wraps negative values into 28-bit two's complement.
  final signed = raw >= 0x08000000 ? raw - 0x10000000 : raw;
  return signed / 8388608.0; // / 2^23
}

void main() {
  test(
      'single ADAU1701 biquad write: Woofer A/B LPF, Butterworth 12 dB/oct '
      '@ 2000 Hz — logs exact frame bytes, no real transport touched',
      () async {
    final sink = _RecordingSink();
    final adapter = Adau1701Adapter(send: sink.send);
    addTearDown(() => Adau1701Adapter.experimentalXoWriteEnabled = true);
    Adau1701Adapter.experimentalXoWriteEnabled = true;

    const targetFreqHz = 2000.0;
    const targetChannel = 0; // Woofer (stereo-linked L/R per adapter model)

    // Independently compute the same filter with the (audited, tested)
    // coefficient engine, so this harness cross-checks two separately
    // implemented Butterworth calculators rather than trusting either alone.
    final independent = fe.Adau1701CrossoverFilterEngine.design(
      side: FilterSide.lowPass,
      type: CrossoverFilterType.butterworth,
      slope: CrossoverSlope.db12,
      frequencyHz: targetFreqHz,
    );
    expect(independent.length, 1,
        reason:
            'a single ADAU1701 filter block holds exactly one biquad stage '
            '(5 words) — only a slope with one section (bw2/lr2, 12 dB/oct) '
            'can map to one block at all; this is the adapter\'s own '
            'documented hardware limit, not a choice made here.');

    await adapter.writeCrossover(
      targetChannel,
      const legacy.CrossoverConfig(
        side: legacy.FilterSide.lpf,
        freqHz: targetFreqHz,
        slope: legacy.CrossoverSlope.bw2, // Butterworth 12 dB/oct, one stage
      ),
    );

    // Woofer LPF = GenFilter1_7 (addr 31) + GenFilter1_8 (addr 51) — the two
    // stereo-linked DAC copies (per adau1701_adapter.dart's _xoBlockBase).
    expect(sink.sentFrames.length, 2,
        reason: 'Pro writes both L/R DAC copies for a stereo-linked channel');

    final expectedAddrs = [31, 51];
    for (var i = 0; i < 2; i++) {
      final frame = sink.sentFrames[i];
      final decoded = _decodeFrame(frame);
      expect(decoded.addr, expectedAddrs[i]);

      // Cross-check b0/b1/b2 (numerator) against this repo's independently
      // implemented, separately-tested engine (Adau1701CrossoverFilterEngine)
      // — these agree exactly, both being the same RBJ-cookbook numerator.
      final decodedB = [
        _decodeFixed523(decoded.rawWords[0]),
        _decodeFixed523(decoded.rawWords[1]),
        _decodeFixed523(decoded.rawWords[2]),
      ];
      final expectedB = [
        independent.single.b0,
        independent.single.b1,
        independent.single.b2,
      ];
      for (var c = 0; c < 3; c++) {
        expect(decodedB[c], closeTo(expectedB[c], 1e-5),
            reason: 'numerator coefficient index $c must agree');
      }

      // AUDIT FINDING (discovered by this harness): a1/a2 do NOT match sign
      // between the two engines. DspEngine._xoBiquad computes RBJ-standard
      // a1=-2cosw0/a0, a2=(1-alpha)/a0, then explicitly NEGATES both before
      // storing them — self-consistent with DspEngine's OWN _evalBiquad
      // (which subtracts: denom = 1 - a1*z^-1 - a2*z^-2), but the OPPOSITE
      // storage convention from Adau1701CrossoverFilterEngine (RBJ-native,
      // denom = 1 + a1*z^-1 + a2*z^-2). Both are internally self-consistent;
      // NEITHER has been checked against what ADAU1701's actual "General 2nd
      // order filter" SigmaStudio cell expects on its A0/A1 parameters. This
      // is an open question the real capture must resolve — do not assume
      // either sign is correct.
      final decodedA1 = _decodeFixed523(decoded.rawWords[3]);
      final decodedA2 = _decodeFixed523(decoded.rawWords[4]);
      expect(decodedA1, closeTo(-independent.single.a1, 1e-5),
          reason: 'a1 magnitude matches but DspEngine stores the opposite '
              'sign from Adau1701CrossoverFilterEngine — see comment above');
      expect(decodedA2, closeTo(-independent.single.a2, 1e-5),
          reason: 'a2 magnitude matches but DspEngine stores the opposite '
              'sign from Adau1701CrossoverFilterEngine — see comment above');

      // Log the exact bytes for a human reviewer / future real-capture
      // comparison. This is the primary deliverable of this harness.
      // ignore: avoid_print
      print('Frame ${i + 1}/2 → addr=0x${decoded.addr.toRadixString(16).padLeft(4, '0')} '
          '(decimal ${decoded.addr}): '
          '${frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
  });

  test(
      'writeCrossover with a >1-stage slope (bw4) is a documented no-op — '
      'the adapter itself refuses rather than send a wrong/shallow filter',
      () async {
    final sink = _RecordingSink();
    final adapter = Adau1701Adapter(send: sink.send);
    addTearDown(() => Adau1701Adapter.experimentalXoWriteEnabled = true);
    Adau1701Adapter.experimentalXoWriteEnabled = true;

    await adapter.writeCrossover(
      0,
      const legacy.CrossoverConfig(
        side: legacy.FilterSide.lpf,
        freqHz: 2000,
        slope: legacy.CrossoverSlope.bw4, // 24 dB/oct — needs 2 stages
      ),
    );

    expect(sink.sentFrames, isEmpty,
        reason: 'each PRAM filter block holds exactly one biquad stage; a '
            '2-stage slope has nowhere documented to put the second stage, '
            'so the adapter sends nothing rather than a wrong filter');
  });

  test('experimentalXoWriteEnabled=false blocks the write entirely', () async {
    final sink = _RecordingSink();
    final adapter = Adau1701Adapter(send: sink.send);
    final original = Adau1701Adapter.experimentalXoWriteEnabled;
    addTearDown(() => Adau1701Adapter.experimentalXoWriteEnabled = original);
    Adau1701Adapter.experimentalXoWriteEnabled = false;

    await adapter.writeCrossover(
      0,
      const legacy.CrossoverConfig(
        side: legacy.FilterSide.lpf,
        freqHz: 2000,
        slope: legacy.CrossoverSlope.bw2,
      ),
    );

    expect(sink.sentFrames, isEmpty);
  });
}
