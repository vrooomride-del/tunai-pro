import 'dart:math' as math;

/// Result of comparing a simulated response to a target curve.
///
/// All values are derived from a per-point error (`response − target`, in dB)
/// over a shared log-frequency grid. Analysis only — nothing here writes DSP.
class ResponseErrorResult {
  /// Unweighted root-mean-square of the per-point dB error.
  final double rmsDb;

  /// Largest absolute per-point deviation (dB) and the frequency it occurs at.
  final double maxDeviationDb;
  final double maxDeviationHz;

  /// RMS after applying per-point frequency weights.
  final double weightedRmsDb;

  /// 0–100 quality score derived from [weightedRmsDb] (100 = on-target).
  final double score;

  const ResponseErrorResult({
    required this.rmsDb,
    required this.maxDeviationDb,
    required this.maxDeviationHz,
    required this.weightedRmsDb,
    required this.score,
  });
}

/// Frequency-domain error metrics for the simulation optimizer.
abstract final class ProResponseError {
  /// dB of weighted RMS error that maps to a score of ~37 (1/e). Smaller =
  /// stricter scoring. Chosen so 0 dB → 100, ~3 dB → ~61, 6 dB → ~37.
  static const double scoreScaleDb = 6.0;

  /// Default frequency weighting: full weight across the vocal/critical band
  /// (~80 Hz–12 kHz), tapering at the extremes where target intent is looser.
  static List<double> defaultWeights(List<double> freqs) => [
        for (final f in freqs)
          if (f < 40)
            0.3
          else if (f < 80)
            0.3 + 0.7 * ((f - 40) / 40)
          else if (f <= 12000)
            1.0
          else if (f <= 18000)
            1.0 - 0.6 * ((f - 12000) / 6000)
          else
            0.4,
      ];

  /// Compares [responseDb] to [targetDb] point-for-point. When [weights] is
  /// omitted, [defaultWeights] over [freqs] is used.
  static ResponseErrorResult analyze({
    required List<double> freqs,
    required List<double> responseDb,
    required List<double> targetDb,
    List<double>? weights,
  }) {
    final n = freqs.length;
    assert(responseDb.length == n && targetDb.length == n,
        'response/target must match the frequency grid');
    final w = weights ?? defaultWeights(freqs);

    var sumSq = 0.0;
    var wSumSq = 0.0;
    var wSum = 0.0;
    var maxDev = 0.0;
    var maxDevHz = n == 0 ? 0.0 : freqs.first;

    for (var i = 0; i < n; i++) {
      final err = responseDb[i] - targetDb[i];
      sumSq += err * err;
      final wi = w[i];
      wSumSq += wi * err * err;
      wSum += wi;
      if (err.abs() > maxDev) {
        maxDev = err.abs();
        maxDevHz = freqs[i];
      }
    }

    final rms = n == 0 ? 0.0 : math.sqrt(sumSq / n);
    final wRms = wSum == 0 ? 0.0 : math.sqrt(wSumSq / wSum);
    final score = (100.0 * math.exp(-wRms / scoreScaleDb)).clamp(0.0, 100.0);

    return ResponseErrorResult(
      rmsDb: rms,
      maxDeviationDb: maxDev,
      maxDeviationHz: maxDevHz,
      weightedRmsDb: wRms,
      score: score,
    );
  }

  /// Convenience: unweighted RMS dB error between two equal-length curves.
  static double rmsError(List<double> responseDb, List<double> targetDb) {
    final n = responseDb.length;
    if (n == 0) return 0.0;
    var sumSq = 0.0;
    for (var i = 0; i < n; i++) {
      final err = responseDb[i] - targetDb[i];
      sumSq += err * err;
    }
    return math.sqrt(sumSq / n);
  }
}
