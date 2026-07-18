import 'icp5_frame_codec.dart';

/// A single ADAU1701 PEQ band target for the ICP5 write path.
///
/// Band index maps directly to the confirmed ICP5 band payload byte
/// ([Icp5FrameCodec.peqBandPayloadIndex]): index 0 = Band 1 (capture-proven),
/// indices 1..9 = Band 2..Band 10 (structurally reused, hardware-unverified).
///
/// `enabled` is modelled for completeness but is NOT written to hardware: the
/// ICP5 capture set has no confirmed per-band enable/bypass parameter, so no
/// enable packet is emitted (see the tuning panel).
class Adau1701PeqBand {
  /// 0-based band index (0 = Band 1 .. 9 = Band 10).
  final int index;
  final int? frequencyHz;
  final double? gainDb;
  final double? q;
  final bool enabled;

  const Adau1701PeqBand({
    required this.index,
    this.frequencyHz,
    this.gainDb,
    this.q,
    this.enabled = true,
  });

  /// Band 0 (Band 1) is the only PRO capture-proven band. Gain and frequency
  /// are verified for it; all other bands' writes are hardware-unverified.
  bool get isCaptureProvenBand => index == 0;

  /// 1-based label for UI ("Band 1" .. "Band 10").
  String get label => 'Band ${index + 1}';

  static bool isValidIndex(int index) =>
      index >= 0 && index < Icp5FrameCodec.peqBandCount;

  Adau1701PeqBand copyWith({
    int? frequencyHz,
    double? gainDb,
    double? q,
    bool? enabled,
  }) =>
      Adau1701PeqBand(
        index: index,
        frequencyHz: frequencyHz ?? this.frequencyHz,
        gainDb: gainDb ?? this.gainDb,
        q: q ?? this.q,
        enabled: enabled ?? this.enabled,
      );
}
