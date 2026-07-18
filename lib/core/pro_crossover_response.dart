import 'dart:math' as math;

import 'pro_tuning_data.dart';

/// Crossover magnitude-response math for the XO editor graph.
///
/// Analog-prototype approximation for visualisation only — no DSP write, no
/// coefficient/address mapping. Butterworth and Linkwitz-Riley magnitudes are
/// exact; Bessel (and the linear-phase placeholder) reuse the Butterworth
/// magnitude shape because their defining benefit is phase / group delay, which
/// is shown separately as a phase-preview placeholder. Phase is not modelled.
abstract final class CrossoverResponse {
  static const double minHz = 20;
  static const double maxHz = 20000;

  /// Logarithmically-spaced frequency points across [minHz]..[maxHz].
  static List<double> logFrequencyPoints({int count = 256}) {
    if (count < 2) throw ArgumentError.value(count, 'count', 'Must be >= 2.');
    final logMin = math.log(minHz);
    final logMax = math.log(maxHz);
    final step = (logMax - logMin) / (count - 1);
    return [for (var i = 0; i < count; i++) math.exp(logMin + step * i)];
  }

  /// Total filter order for a slope (6 dB/oct per order): 12→2, 24→4, 36→6, 48→8.
  static int orderFor(CrossoverSlope slope) => switch (slope) {
        CrossoverSlope.db12 => 2,
        CrossoverSlope.db24 => 4,
        CrossoverSlope.db36 => 6,
        CrossoverSlope.db48 => 8,
      };

  static double _log10(double x) => math.log(x) / math.ln10;

  /// Butterworth magnitude (linear) of [order] at normalised [ratio]
  /// (ratio = fc/f for high-pass, f/fc for low-pass).
  static double _butterworthLinear(double ratio, num order) =>
      1 / math.sqrt(1 + math.pow(ratio, 2 * order));

  /// Magnitude (dB) of one crossover [filter] at frequency [f] (Hz).
  /// Returns 0 dB for a disabled filter (passes signal).
  static double filterMagnitudeDb(CrossoverFilter filter, double f) {
    if (!filter.enabled) return 0;
    final order = orderFor(filter.slope);
    final ratio = filter.side == FilterSide.highPass
        ? filter.frequencyHz / f
        : f / filter.frequencyHz;
    switch (filter.type) {
      case CrossoverFilterType.linkwitzRiley:
        // Order-N LR = two cascaded order-N/2 Butterworths → magnitude squared
        // (−6 dB at fc), so summed LR crossovers are flat.
        return 40 * _log10(_butterworthLinear(ratio, order / 2));
      case CrossoverFilterType.butterworth:
      case CrossoverFilterType.bessel:
      case CrossoverFilterType.linearPhasePlaceholder:
        return 20 * _log10(_butterworthLinear(ratio, order));
    }
  }

  /// Combined magnitude (dB) for a driver's crossover [channel] at [f] — the
  /// cascade of its enabled HPF and LPF. A bypassed channel is flat (0 dB).
  static double channelMagnitudeDb(CrossoverChannelState channel, double f) {
    if (channel.bypassed) return 0;
    var db = 0.0;
    final hp = channel.highPass;
    final lp = channel.lowPass;
    if (hp != null) db += filterMagnitudeDb(hp, f);
    if (lp != null) db += filterMagnitudeDb(lp, f);
    return db;
  }

  /// Per-point channel curve (dB) over [freqs].
  static List<double> channelCurve(
          CrossoverChannelState channel, List<double> freqs) =>
      [for (final f in freqs) channelMagnitudeDb(channel, f)];

  /// Power sum (dB) of several channel magnitudes at one frequency.
  static double powerSumDb(Iterable<double> channelDb) {
    var power = 0.0;
    for (final db in channelDb) {
      power += math.pow(10, db / 10);
    }
    if (power <= 0) return -120;
    return 10 * _log10(power);
  }

  /// Power-summed curve (dB) across [channelCurves] (each same length as freqs).
  static List<double> summedCurve(List<List<double>> channelCurves) {
    if (channelCurves.isEmpty) return const [];
    final n = channelCurves.first.length;
    return [
      for (var i = 0; i < n; i++)
        powerSumDb([for (final curve in channelCurves) curve[i]]),
    ];
  }
}
