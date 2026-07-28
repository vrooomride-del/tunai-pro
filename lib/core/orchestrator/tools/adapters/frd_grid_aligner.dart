/// Aligns multiple FRD sweep point lists onto a deterministic common frequency grid.
///
/// Algorithm:
///   1. Each sweep is sorted by frequency.
///   2. Intersection range = [max(minFreqs), min(maxFreqs)].
///      Returns null when no overlap exists.
///   3. Common grid = frequency points of the sweep with the most points in
///      the intersection range (no tie-breaking needed in practice; first-max wins).
///   4. Every sweep is linearly interpolated onto the common grid.
///      No extrapolation: only the intersection range is covered.
///
/// Pure and deterministic — same inputs always produce the same output.
abstract final class FrdGridAligner {
  static ({List<double> frequencies, List<List<double>> spectraDb})? align(
    List<({List<double> freqs, List<double> mags})> sweeps,
  ) {
    if (sweeps.isEmpty) return null;
    if (sweeps.length == 1) {
      return (frequencies: sweeps[0].freqs, spectraDb: [sweeps[0].mags]);
    }

    final sorted = [for (final s in sweeps) _sort(s.freqs, s.mags)];

    // Intersection range.
    var rangeMin = double.negativeInfinity;
    var rangeMax = double.infinity;
    for (final s in sorted) {
      if (s.freqs.isEmpty) continue;
      if (s.freqs.first > rangeMin) rangeMin = s.freqs.first;
      if (s.freqs.last < rangeMax) rangeMax = s.freqs.last;
    }
    if (!rangeMin.isFinite || !rangeMax.isFinite || rangeMin >= rangeMax) {
      return null;
    }

    // Common grid: sweep with most points in [rangeMin, rangeMax].
    List<double>? commonGrid;
    var maxPoints = 0;
    for (final s in sorted) {
      final inRange = [
        for (final f in s.freqs)
          if (f >= rangeMin && f <= rangeMax) f,
      ];
      if (inRange.length > maxPoints) {
        maxPoints = inRange.length;
        commonGrid = inRange;
      }
    }
    if (commonGrid == null || commonGrid.length < 2) return null;

    // Interpolate each sweep onto the common grid.
    final spectra = <List<double>>[];
    for (final s in sorted) {
      spectra.add([for (final gf in commonGrid) _linterp(s.freqs, s.mags, gf)]);
    }
    return (frequencies: List.unmodifiable(commonGrid), spectraDb: spectra);
  }

  static ({List<double> freqs, List<double> mags}) _sort(
    List<double> freqs,
    List<double> mags,
  ) {
    if (freqs.length <= 1) return (freqs: freqs, mags: mags);
    final n = freqs.length;
    final idx = List.generate(n, (i) => i)
      ..sort((a, b) => freqs[a].compareTo(freqs[b]));
    return (
      freqs: [for (final i in idx) freqs[i]],
      mags: [for (final i in idx) mags[i]],
    );
  }

  /// Linear interpolation. Clamps to boundary values — no extrapolation.
  static double _linterp(List<double> freqs, List<double> mags, double target) {
    if (freqs.isEmpty) return double.nan;
    if (target <= freqs.first) return mags.first;
    if (target >= freqs.last) return mags.last;
    int lo = 0, hi = freqs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (freqs[mid] <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (target - freqs[lo]) / (freqs[hi] - freqs[lo]);
    return mags[lo] + t * (mags[hi] - mags[lo]);
  }
}
