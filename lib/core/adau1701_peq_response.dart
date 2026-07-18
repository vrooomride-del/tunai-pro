import 'dart:math' as math;

/// One parametric (peaking) PEQ band for response visualisation.
///
/// This is a display/editing model only — it does not read or write hardware
/// and introduces no DSP parameter mapping. `enabled` controls whether the band
/// contributes to the combined curve (disabled bands are excluded); it is not a
/// hardware enable/bypass write.
class PeqResponseBand {
  final double frequencyHz;
  final double gainDb;
  final double q;
  final bool enabled;

  const PeqResponseBand({
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    this.enabled = true,
  });

  PeqResponseBand copyWith({
    double? frequencyHz,
    double? gainDb,
    double? q,
    bool? enabled,
  }) =>
      PeqResponseBand(
        frequencyHz: frequencyHz ?? this.frequencyHz,
        gainDb: gainDb ?? this.gainDb,
        q: q ?? this.q,
        enabled: enabled ?? this.enabled,
      );
}

/// Frequency-response math for a bank of peaking PEQ bands.
///
/// The magnitude uses the standard RBJ peaking biquad evaluated on the unit
/// circle at a fixed display sample rate ([sampleRateHz]). This is a rendering
/// model for the graph only; it is not a device coefficient mapping.
abstract final class Adau1701PeqResponse {
  static const double minHz = 20;
  static const double maxHz = 20000;

  /// Nominal display sample rate. The ADAU1701 typically runs at 48 kHz; this
  /// only affects the shape of the rendered curve, never any hardware write.
  static const double sampleRateHz = 48000;

  /// Logarithmically-spaced frequency points across [minHz]..[maxHz].
  static List<double> logFrequencyPoints({int count = 256}) {
    if (count < 2) {
      throw ArgumentError.value(count, 'count', 'Must be >= 2.');
    }
    final logMin = math.log(minHz);
    final logMax = math.log(maxHz);
    final step = (logMax - logMin) / (count - 1);
    return [for (var i = 0; i < count; i++) math.exp(logMin + step * i)];
  }

  /// Peaking-biquad magnitude (dB) of a single [band] at frequency [f] (Hz).
  /// Returns 0 dB for a disabled band or zero gain.
  static double peakingMagnitudeDb(PeqResponseBand band, double f) {
    if (!band.enabled || band.gainDb == 0) return 0;
    final a = math.pow(10, band.gainDb / 40).toDouble(); // amplitude sqrt(gain)
    final q = band.q <= 0 ? 0.0001 : band.q;
    final w0 = 2 * math.pi * band.frequencyHz / sampleRateHz;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);

    final b0 = 1 + alpha * a;
    final b1 = -2 * cosW0;
    final b2 = 1 - alpha * a;
    final a0 = 1 + alpha / a;
    final a1 = -2 * cosW0;
    final a2 = 1 - alpha / a;

    final w = 2 * math.pi * f / sampleRateHz;
    final cosW = math.cos(w), sinW = math.sin(w);
    final cos2W = math.cos(2 * w), sin2W = math.sin(2 * w);

    final numRe = b0 + b1 * cosW + b2 * cos2W;
    final numIm = -(b1 * sinW + b2 * sin2W);
    final denRe = a0 + a1 * cosW + a2 * cos2W;
    final denIm = -(a1 * sinW + a2 * sin2W);

    final numMag = math.sqrt(numRe * numRe + numIm * numIm);
    final denMag = math.sqrt(denRe * denRe + denIm * denIm);
    if (denMag == 0) return 0;
    return 20 * (math.log(numMag / denMag) / math.ln10);
  }

  /// Combined magnitude (dB) at [f] summing only the ENABLED bands.
  static double combinedMagnitudeDb(Iterable<PeqResponseBand> bands, double f) {
    var sum = 0.0;
    for (final band in bands) {
      if (band.enabled) sum += peakingMagnitudeDb(band, f);
    }
    return sum;
  }

  /// Combined curve (dB per point) over [freqPoints], enabled bands only.
  static List<double> combinedCurve(
    Iterable<PeqResponseBand> bands,
    List<double> freqPoints,
  ) =>
      [for (final f in freqPoints) combinedMagnitudeDb(bands, f)];

  /// Single-band curve (dB per point) over [freqPoints].
  static List<double> bandCurve(
    PeqResponseBand band,
    List<double> freqPoints,
  ) =>
      [for (final f in freqPoints) peakingMagnitudeDb(band, f)];

  /// Number of enabled bands in [bands].
  static int enabledCount(Iterable<PeqResponseBand> bands) =>
      bands.where((b) => b.enabled).length;
}
