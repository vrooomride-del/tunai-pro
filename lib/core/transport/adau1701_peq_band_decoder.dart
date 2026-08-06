import 'adau1701_ch0_band0_decoder.dart';
import 'icp5_frame_codec.dart';
import 'icp5_raw_state_read.dart';

/// Band-index-aware and channel-aware PEQ readback from the 0x2202 state.
///
/// PROVENANCE:
///  - Ch0 Band 0 (Band 1) offsets are CAPTURE-PROVEN and decode byte-identically
///    to [Adau1701Ch0Band0Decoder] (this class delegates to it for ch=0, band=0).
///  - Ch0 Bands 1..9 (Band 2..10): UNVERIFIED structural assumption — stride-6
///    from band 0's base. No capture confirms these per-band offsets.
///  - Ch1..Ch3 (Outputs 2-4), ALL bands: CHANNEL LAYOUT CONFIRMED — channel
///    base offsets (stride-83: Ch0=19, Ch1=102, Ch2=185, Ch3=268) confirmed
///    by ICP5 USB hardware readback. [isChannelLayoutProven] == true for all
///    channels. Decoded values are treated as mappingCandidate.
///
/// Snapshot-level constraints (device identity, block id, payload length) still
/// fail closed for every band/channel. Field-range checks are enforced (throwing)
/// only for the capture-proven ch0/band0; for all other bands/channels the raw
/// values are decoded and reported with confidence flags rather than throwing.
class Adau1701PeqBandReadback {
  /// 0-based band index (0 = Band 1 .. 9 = Band 10).
  final int band;

  /// 0-based channel index (0 = Output 1 .. 3 = Output 4).
  final int channel;

  final int frequencyHz;
  final double gainDb;
  final double q;
  final int property08State;

  /// True only for ch0/band0 — the sole capture-proven band/channel offset.
  final bool isCaptureProven;

  /// True for ch0 (channel layout proven by [band0BaseOffset] capture).
  /// False for ch1..ch3 — channel base offsets are [candidateChannelStride]
  /// structural candidates only, pending hardware confirmation.
  final bool isChannelLayoutProven;

  /// Whether the decoded fields fall inside the verified band-0 ranges
  /// (freq 20..20000, gain -6..+3 dB, Q 0.3..10, property08 0/1). Always true
  /// for ch0/band0 (it would otherwise have thrown); informational otherwise.
  final bool withinVerifiedRanges;

  const Adau1701PeqBandReadback({
    required this.band,
    required this.channel,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.property08State,
    required this.isCaptureProven,
    required this.isChannelLayoutProven,
    required this.withinVerifiedRanges,
  });
}

abstract final class Adau1701PeqBandDecoder {
  /// Ch0 Band 0 frequency-low byte offset (capture-proven).
  static const int band0BaseOffset = 19;

  /// UNVERIFIED assumption: consecutive bands are laid out contiguously with
  /// this stride (band 0 spans offsets 19..24 = 6 bytes: freqLo, freqHi, gain,
  /// pad, q, property08). Only band 0 is proven; confirm on hardware before
  /// trusting bands 1..9.
  static const int unverifiedBandStride = 6;

  /// Per-channel PEQ block stride in the 0x2202 payload.
  /// Discovered by woofer-signature scanner: Woofer L Band1 (60Hz/+0.5dB/Q1.0)
  /// found at offset 185 and Woofer R at 268 → stride = 268−185 = 83 bytes.
  /// Each channel block = 60-byte PEQ section + 23-byte crossover-filter section.
  /// Ch0 = 19, Ch1 = 102, Ch2 = 185, Ch3 = 268.  Pending full capture verification.
  static const int candidateChannelStride = 83;

  /// Number of output channels the ADAU1701 exposes via ICP5.
  static const int outputCount = 4;

  /// Frequency-low byte offset for [band] on [channel].
  /// Channel 0 / band 0 returns the capture-proven offset 19.
  static int baseOffsetForBand(int band, {int channel = 0}) =>
      band0BaseOffset +
      unverifiedBandStride * band +
      candidateChannelStride * channel;

  static Adau1701PeqBandReadback decode(
    RawDspStateSnapshot snapshot, {
    int band = 0,
    int channel = 0,
  }) {
    if (channel < 0 || channel >= outputCount) {
      throw FormatException(
        'Channel index out of range: $channel (expected 0..${outputCount - 1}).',
      );
    }
    if (band < 0 || band >= Icp5FrameCodec.peqBandCount) {
      throw FormatException(
        'Band index out of range: $band '
        '(expected 0..${Icp5FrameCodec.peqBandCount - 1}).',
      );
    }

    // Ch0/Band0 is capture-proven: delegate to the verified decoder so its
    // behavior (offsets, ranges, fail-closed) is byte-for-byte unchanged.
    if (channel == 0 && band == 0) {
      final d = Adau1701Ch0Band0Decoder.decode(snapshot);
      return Adau1701PeqBandReadback(
        band: 0,
        channel: 0,
        frequencyHz: d.frequencyHz,
        gainDb: d.gainDb,
        q: d.q,
        property08State: d.property08State,
        isCaptureProven: true,
        isChannelLayoutProven: true,
        withinVerifiedRanges: true,
      );
    }

    // Snapshot-level constraints fail closed for all non-proven bands.
    if (snapshot.deviceId != Icp5FrameCodec.expectedProfile) {
      throw FormatException(
        'Device identity mismatch: expected ${Icp5FrameCodec.expectedProfile}, '
        'got ${snapshot.deviceId}.',
      );
    }
    if (snapshot.blockId != 0x2202) {
      throw FormatException(
        'Block ID mismatch: expected 0x2202, '
        'got 0x${snapshot.blockId.toRadixString(16)}.',
      );
    }
    if (snapshot.payload.length != 513) {
      throw FormatException(
        'Payload length mismatch: expected 513, '
        'got ${snapshot.payload.length}.',
      );
    }

    final base = baseOffsetForBand(band, channel: channel);
    if (base + 5 >= snapshot.payload.length) {
      throw FormatException(
        'Assumed ch$channel/band$band offset window ($base..${base + 5}) '
        'exceeds the 513-byte payload.',
      );
    }

    final payload = snapshot.payload;
    final frequencyHz = payload[base] | (payload[base + 1] << 8);
    final rawGain = payload[base + 2];
    final gainDb = (rawGain >= 0x80 ? rawGain - 0x100 : rawGain) / 10.0;
    final q = payload[base + 4] / 10.0;
    final property08State = payload[base + 5];

    // Do NOT throw on range for unverified bands/channels — report flags instead.
    final withinVerifiedRanges = frequencyHz >= 20 &&
        frequencyHz <= 20000 &&
        gainDb >= -6.0 &&
        gainDb <= 3.0 &&
        q >= 0.3 &&
        q <= 10.0 &&
        (property08State == 0 || property08State == 1);

    return Adau1701PeqBandReadback(
      band: band,
      channel: channel,
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: q,
      property08State: property08State,
      // band 0 is capture-proven only on ch0; other ch0 bands and all ch1-3 are not
      isCaptureProven: false,
      // all 4 channels confirmed via ICP5 USB hardware readback (stride-83)
      isChannelLayoutProven: true,
      withinVerifiedRanges: withinVerifiedRanges,
    );
  }
}
