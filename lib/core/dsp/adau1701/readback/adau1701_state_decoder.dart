// ADAU1701 Full DSP State Readback Decoder — Phase 2: 4-Output Layout
//
// Decodes a 513-byte RawDspStateSnapshot into a structured Adau1701StateSnapshot
// for all 4 output channels.
//
// Provenance tiers (ascending confidence):
//   channelLayoutCandidate — (reserved; no bands currently assigned this tier)
//   mappingCandidate — Ch0 Bands 2..10 and Ch1..Ch3 all bands: stride-6/stride-83
//       confirmed by ICP5 USB hardware readback (Ch0=19, Ch1=102, Ch2=185, Ch3=268).
//   verified — Ch0 Band 1 (bandIndex 0): capture-proven against MiUMAX hardware.
//
// Read-only. Never writes. No deploy or transport state changes.

import '../../../transport/adau1701_peq_band_decoder.dart';
import '../../../transport/icp5_frame_codec.dart';
import '../../../transport/icp5_raw_state_read.dart';

// ── Verification status ───────────────────────────────────────────────────────

enum PeqBandVerificationStatus {
  // Byte offsets confirmed by physical hardware capture (Ch0 Band 1 / bandIndex 0).
  // MiUMAX: EQ Band1 Freq 1800 Hz, Gain 0.0 dB, Q 1.20 — matches decoder.
  verified,

  // Ch0 bands 2..10: stride-6 structural assumption from band0 base.
  // Pending independent hardware confirmation.
  mappingCandidate,

  // Reserved — channel offsets now confirmed for all 4 channels via ICP5 USB
  // hardware readback. No bands are currently assigned this tier.
  channelLayoutCandidate,
}

// ── Band state ────────────────────────────────────────────────────────────────

class PeqBandState {
  // 0-based band index (0 = Band 1 .. 9 = Band 10).
  final int bandIndex;
  final int frequencyHz;
  final double gainDb;
  final double q;

  // Raw property08 value (0 or 1 for verified band; may be any byte for candidates).
  final int property08;

  final PeqBandVerificationStatus verificationStatus;

  // Whether decoded fields fall inside the validated band-0 ranges
  // (freq 20..20000, gain −6..+3 dB, Q 0.3..10, property08 0/1).
  // Always true for [PeqBandVerificationStatus.verified].
  // Informational for [PeqBandVerificationStatus.mappingCandidate]:
  // false indicates likely wrong offset, not a hardware fault.
  final bool withinVerifiedRanges;

  const PeqBandState({
    required this.bandIndex,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.property08,
    required this.verificationStatus,
    required this.withinVerifiedRanges,
  });
}

// ── Output state ──────────────────────────────────────────────────────────────

// Decoded state for one ADAU1701 output channel.
//
// Only PEQ bands are included. Gain, delay, and mute field offsets are unknown
// and will be added once hardware capture confirms their layout.
class OutputState {
  // 0-based output index (0 = Output 1 / Ch0 .. 3 = Output 4 / Ch3).
  final int outputIndex;
  final List<PeqBandState> peqBands;

  // Whether the channel base offset in the 0x2202 payload is confirmed by
  // hardware capture. True for Ch0 only; false for Ch1..Ch3.
  final bool isChannelLayoutProven;

  OutputState({
    required this.outputIndex,
    required List<PeqBandState> peqBands,
    required this.isChannelLayoutProven,
  }) : peqBands = List.unmodifiable(peqBands);
}

// ── Full state snapshot ───────────────────────────────────────────────────────

// Full decoded ADAU1701 DSP state from a single 513-byte snapshot.
//
// Contains 4 outputs: Ch0 (channel-layout proven), Ch1..Ch3 (channel-layout
// candidates — offsets at candidateChannelStride × channel from band0BaseOffset).
class Adau1701StateSnapshot {
  final List<OutputState> outputs;
  final RawDspStateSnapshot rawSnapshot;
  final DateTime decodedAt;

  Adau1701StateSnapshot({
    required List<OutputState> outputs,
    required this.rawSnapshot,
    required this.decodedAt,
  }) : outputs = List.unmodifiable(outputs);
}

// ── Decoder ───────────────────────────────────────────────────────────────────

// Decodes all 4 outputs from a [RawDspStateSnapshot].
//
// Provenance contract:
//   Ch0 Band0 — throws on field range violations (capture-proven).
//   Ch0 Bands 1..9 — range violations surface as withinVerifiedRanges=false.
//   Ch1..Ch3 all bands — range violations surface as withinVerifiedRanges=false;
//     marked mappingCandidate (channel offsets confirmed via ICP5 USB readback).
abstract final class Adau1701StateDecoder {
  static Adau1701StateSnapshot decode(RawDspStateSnapshot snapshot) {
    final outputs = <OutputState>[];
    for (var ch = 0; ch < Adau1701PeqBandDecoder.outputCount; ch++) {
      final bands = <PeqBandState>[];
      for (var band = 0; band < Icp5FrameCodec.peqBandCount; band++) {
        final rb = Adau1701PeqBandDecoder.decode(snapshot,
            band: band, channel: ch);
        final status = rb.isCaptureProven
            ? PeqBandVerificationStatus.verified
            : rb.isChannelLayoutProven
                ? PeqBandVerificationStatus.mappingCandidate
                : PeqBandVerificationStatus.channelLayoutCandidate;
        bands.add(PeqBandState(
          bandIndex: band,
          frequencyHz: rb.frequencyHz,
          gainDb: rb.gainDb,
          q: rb.q,
          property08: rb.property08State,
          verificationStatus: status,
          withinVerifiedRanges: rb.withinVerifiedRanges,
        ));
      }
      outputs.add(OutputState(
        outputIndex: ch,
        peqBands: bands,
        isChannelLayoutProven: true,
      ));
    }
    return Adau1701StateSnapshot(
      outputs: outputs,
      rawSnapshot: snapshot,
      decodedAt: DateTime.now(),
    );
  }
}
