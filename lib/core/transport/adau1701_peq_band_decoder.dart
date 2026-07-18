import 'adau1701_ch0_band0_decoder.dart';
import 'icp5_frame_codec.dart';
import 'icp5_raw_state_read.dart';

/// Band-index-aware PEQ readback of one channel-0 band from the 0x2202 state.
///
/// PROVENANCE:
///  - Band 0 (Band 1) offsets are CAPTURE-PROVEN and decode byte-identically to
///    [Adau1701Ch0Band0Decoder] (this class delegates to it for band 0).
///  - Bands 1..9 (Band 2..10) offsets are an UNVERIFIED structural assumption:
///    a fixed [unverifiedBandStride] from band 0's base. No capture confirms the
///    per-band layout, so decoded values for these bands are returned with
///    [Adau1701PeqBandReadback.isCaptureProven] == false and MUST be treated as
///    "hardware verification pending" until a real device readback proves them.
///
/// Snapshot-level constraints (device identity, block id, payload length) still
/// fail closed for every band. Field-range checks are enforced (throwing) only
/// for the capture-proven band 0; for bands 1..9 the raw values are decoded and
/// reported alongside a [Adau1701PeqBandReadback.withinVerifiedRanges] flag
/// rather than throwing — a wrong/unconfirmed offset surfaces as out-of-range,
/// never as a fabricated pass.
class Adau1701PeqBandReadback {
  /// 0-based band index (0 = Band 1 .. 9 = Band 10).
  final int band;
  final int frequencyHz;
  final double gainDb;
  final double q;
  final int property08State;

  /// True only for band 0 — the sole capture-proven band offset.
  final bool isCaptureProven;

  /// Whether the decoded fields fall inside the verified band-0 ranges
  /// (freq 20..20000, gain -6..+3 dB, Q 0.3..10, property08 0/1). Always true
  /// for band 0 (it would otherwise have thrown); informational for bands 1..9.
  final bool withinVerifiedRanges;

  const Adau1701PeqBandReadback({
    required this.band,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.property08State,
    required this.isCaptureProven,
    required this.withinVerifiedRanges,
  });
}

abstract final class Adau1701PeqBandDecoder {
  /// Band 0 frequency-low byte offset (capture-proven).
  static const int band0BaseOffset = 19;

  /// UNVERIFIED assumption: consecutive bands are laid out contiguously with
  /// this stride (band 0 spans offsets 19..24 = 6 bytes: freqLo, freqHi, gain,
  /// pad, q, property08). Only band 0 is proven; confirm on hardware before
  /// trusting bands 1..9. Band N frequency-low offset = base + stride * N.
  static const int unverifiedBandStride = 6;

  /// Frequency-low byte offset for [band]. Band 0 is the proven value.
  static int baseOffsetForBand(int band) =>
      band0BaseOffset + unverifiedBandStride * band;

  static Adau1701PeqBandReadback decode(RawDspStateSnapshot snapshot,
      {int band = 0}) {
    if (band < 0 || band >= Icp5FrameCodec.peqBandCount) {
      throw FormatException(
        'Band index out of range: $band '
        '(expected 0..${Icp5FrameCodec.peqBandCount - 1}).',
      );
    }

    // Band 0 is capture-proven: delegate to the verified decoder so its
    // behavior (offsets, ranges, fail-closed) is byte-for-byte unchanged.
    if (band == 0) {
      final d = Adau1701Ch0Band0Decoder.decode(snapshot);
      return Adau1701PeqBandReadback(
        band: 0,
        frequencyHz: d.frequencyHz,
        gainDb: d.gainDb,
        q: d.q,
        property08State: d.property08State,
        isCaptureProven: true,
        withinVerifiedRanges: true,
      );
    }

    // Snapshot-level constraints still fail closed for bands 1..9.
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

    final base = baseOffsetForBand(band);
    // Bounds-check the assumed offset window (freqLo..property08 = base+5).
    if (base + 5 >= snapshot.payload.length) {
      throw FormatException(
        'Assumed band $band offset window ($base..${base + 5}) exceeds the '
        '513-byte payload.',
      );
    }

    final payload = snapshot.payload;
    final frequencyHz = payload[base] | (payload[base + 1] << 8);
    final rawGain = payload[base + 2];
    final gainDb = (rawGain >= 0x80 ? rawGain - 0x100 : rawGain) / 10.0;
    final q = payload[base + 4] / 10.0;
    final property08State = payload[base + 5];

    // Do NOT throw on range for unverified bands — report the flag instead.
    final withinVerifiedRanges = frequencyHz >= 20 &&
        frequencyHz <= 20000 &&
        gainDb >= -6.0 &&
        gainDb <= 3.0 &&
        q >= 0.3 &&
        q <= 10.0 &&
        (property08State == 0 || property08State == 1);

    return Adau1701PeqBandReadback(
      band: band,
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: q,
      property08State: property08State,
      isCaptureProven: false,
      withinVerifiedRanges: withinVerifiedRanges,
    );
  }
}
