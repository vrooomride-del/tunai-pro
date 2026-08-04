// ── ADAU1701 Crossover Filter Engine — Phase 7-P0 (Full Runtime Filter) ───────
// Pure DSP math: computes digital biquad coefficients for Linkwitz-Riley,
// Butterworth, and Bessel crossover filters at any order this app's
// CrossoverSlope models (12/24/36/48 dB/oct today).
//
// This file performs NO hardware write, references NO DSP parameter address,
// and is not wired into any deploy/export path. It exists to (1) prepare a
// coefficient set that can be compared against a real SigmaStudio capture
// once one exists (see Adau1701CoefficientCaptureComparison below), and
// (2) be available for a more accurate crossover response preview than the
// existing idealized analog-prototype approximation in
// pro_crossover_response.dart (which explicitly documents that Bessel reuses
// the Butterworth magnitude shape as a placeholder).
//
// No memorized/tabulated filter-design constants are used anywhere in this
// file. Butterworth pole angles are closed-form (standard, verifiable by
// inspection). Bessel poles are derived at runtime from the reverse Bessel
// polynomial recurrence and a numerical root finder — see
// _besselAnalogSections() for why, and the accompanying test file for a
// closed-form cross-check (2nd-order Bessel Q = 1/sqrt(3) is provably exact
// and is asserted against this engine's numerically-derived value).

import 'dart:math' as math;

import '../pro_tuning_data.dart' show CrossoverFilterType, CrossoverSlope, FilterSide;

// ── Digital biquad ───────────────────────────────────────────────────────────

/// One digital biquad section, RBJ Audio EQ Cookbook convention:
/// H(z) = (b0 + b1 z^-1 + b2 z^-2) / (1 + a1 z^-1 + a2 z^-2)  (a0 already
/// normalized to 1.0). A first-order section sets b2 = 0, a2 = 0.
class Adau1701BiquadCoefficients {
  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  const Adau1701BiquadCoefficients({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  /// Magnitude response in dB at [freqHz] for [sampleRateHz] — used only for
  /// self-verification in tests (e.g. confirming a section is at -3.01 dB at
  /// its own design cutoff). Never used to derive a coefficient value.
  double magnitudeDb(double freqHz, double sampleRateHz) {
    final w = 2 * math.pi * freqHz / sampleRateHz;
    final numRe = b0 + b1 * math.cos(w) + b2 * math.cos(2 * w);
    final numIm = -b1 * math.sin(w) - b2 * math.sin(2 * w);
    final denRe = 1 + a1 * math.cos(w) + a2 * math.cos(2 * w);
    final denIm = -a1 * math.sin(w) - a2 * math.sin(2 * w);
    final numMag2 = numRe * numRe + numIm * numIm;
    final denMag2 = denRe * denRe + denIm * denIm;
    return 10 * (math.log(numMag2 / denMag2) / math.ln10);
  }

  @override
  String toString() =>
      'Biquad(b0=$b0, b1=$b1, b2=$b2, a1=$a1, a2=$a2)';
}

/// One analog prototype section, normalized so a single 2nd-order section has
/// unity natural frequency at the *overall filter's* -3 dB point (Butterworth)
/// or at its own scaled cutoff (Bessel, see below). [q] is null for a
/// first-order section (used for odd-order cascades).
class _AnalogSection {
  final double cutoffHz;
  final double? q;
  const _AnalogSection({required this.cutoffHz, this.q});
}

// ── Public API ────────────────────────────────────────────────────────────────

abstract final class Adau1701CrossoverFilterEngine {
  /// Total filter order for a slope (6 dB/oct per order) — same mapping
  /// pro_crossover_response.dart already uses, kept consistent deliberately.
  static int orderFor(CrossoverSlope slope) => switch (slope) {
        CrossoverSlope.db6 => 1,
        CrossoverSlope.db12 => 2,
        CrossoverSlope.db24 => 4,
        CrossoverSlope.db36 => 6,
        CrossoverSlope.db48 => 8,
      };

  /// Designs the cascaded biquad sections for one HPF or LPF leg.
  ///
  /// Throws [UnsupportedError] for a combination with no standard definition
  /// — e.g. Linkwitz-Riley requires an even total order divisible into two
  /// equal Butterworth halves; [CrossoverFilterType.linearPhasePlaceholder]
  /// has no filter design at all (its own name says so).
  static List<Adau1701BiquadCoefficients> design({
    required FilterSide side,
    required CrossoverFilterType type,
    required CrossoverSlope slope,
    required double frequencyHz,
    double sampleRateHz = 48000,
  }) {
    if (frequencyHz <= 0 || frequencyHz >= sampleRateHz / 2) {
      throw ArgumentError.value(frequencyHz, 'frequencyHz',
          'Must be within (0, nyquist) for sampleRateHz=$sampleRateHz.');
    }
    final order = orderFor(slope);
    final analogSections = switch (type) {
      CrossoverFilterType.butterworth => _butterworthAnalogSections(order, frequencyHz),
      CrossoverFilterType.linkwitzRiley => _linkwitzRileyAnalogSections(order, frequencyHz),
      CrossoverFilterType.bessel => _besselAnalogSections(order, frequencyHz, side),
      CrossoverFilterType.linearPhasePlaceholder => throw UnsupportedError(
          'linearPhasePlaceholder has no filter design — it is a UI '
          'placeholder only (see CrossoverFilterType).'),
    };
    return [
      for (final s in analogSections) _biquadFromAnalogSection(s, side, sampleRateHz),
    ];
  }

  // ── Butterworth (closed-form) ─────────────────────────────────────────────
  //
  // Order-N Butterworth poles (normalized, cutoff=1) lie on the unit circle
  // at angles evenly spaced around the left half-plane. Pairing them into
  // conjugate pairs gives the standard per-section Q:
  //   Q_k = 1 / (2 sin((2k-1)pi / (2N)))   for k = 1 .. floor(N/2)
  // (an odd real pole, Q undefined/first-order, is added for odd N — not
  // used by any slope this app currently models, but implemented generally).
  // Self-check possible without any external reference: for N=2 this gives
  // Q=1/sqrt(2)=0.7071 and for N=4 it gives Q1=0.5412, Q2=1.3066 — both
  // reproducible by direct substitution into the formula above, not quoted
  // from a table.
  static List<_AnalogSection> _butterworthAnalogSections(int order, double cutoffHz) {
    final sections = <_AnalogSection>[];
    final pairCount = order ~/ 2;
    for (var k = 1; k <= pairCount; k++) {
      final q = 1 / (2 * math.sin((2 * k - 1) * math.pi / (2 * order)));
      sections.add(_AnalogSection(cutoffHz: cutoffHz, q: q));
    }
    if (order.isOdd) {
      sections.add(_AnalogSection(cutoffHz: cutoffHz)); // first-order, q=null
    }
    return sections;
  }

  // ── Linkwitz-Riley ────────────────────────────────────────────────────────
  //
  // LR-N is, by definition, the cascade of two identical Butterworth-(N/2)
  // filters — the classic construction that makes the summed LP+HP output
  // flat (each leg is -6 dB at the crossover point, not -3 dB). Only defined
  // for even N with N/2 itself a valid order (i.e. every slope this app
  // models today: 12, 24, 36, 48).
  static List<_AnalogSection> _linkwitzRileyAnalogSections(int order, double cutoffHz) {
    if (order.isOdd || order < 2) {
      throw UnsupportedError(
          'Linkwitz-Riley is only defined for an even total order '
          '(cascade of two equal Butterworth halves); got order=$order.');
    }
    final half = _butterworthAnalogSections(order ~/ 2, cutoffHz);
    return [...half, ...half];
  }

  // ── Bessel (derived at runtime — see file header) ─────────────────────────
  static List<_AnalogSection> _besselAnalogSections(
      int order, double cutoffHz, FilterSide side) {
    final rawCoeffs = _reverseBesselPolynomial(order); // descending, monic
    final rawPoles = _polynomialRoots(rawCoeffs);

    // Pair conjugates (positive-imaginary member of each pair) and collect
    // any real pole (odd order). Each entry keeps its RAW (un-frequency-
    // normalized) natural frequency and its Q, which is scale-invariant.
    final pairs = <({double qRaw, double omegaRaw})>[];
    double? realPoleOmegaRaw;
    final used = List<bool>.filled(rawPoles.length, false);
    for (var i = 0; i < rawPoles.length; i++) {
      if (used[i]) continue;
      final p = rawPoles[i];
      if (p.im.abs() < 1e-9) {
        realPoleOmegaRaw = p.re.abs();
        used[i] = true;
        continue;
      }
      if (p.im < 0) continue; // will be picked up as the conjugate of its pair
      final omega = p.abs;
      final alpha = -p.re; // poles are in the left half-plane: re < 0
      pairs.add((qRaw: omega / (2 * alpha), omegaRaw: omega));
      used[i] = true;
    }

    // Find the -3 dB point of the RAW (unscaled) cascade via bisection —
    // computed, not looked up. The poles (and Q values) are shared between
    // the lowpass and highpass prototypes — only the numerator differs
    // (constant vs s^2 per section) — see e.g. Butterworth's identical
    // pole set producing a symmetric -3dB point for both sides. Bessel's
    // poles are NOT symmetric the way Butterworth's are (they don't all
    // share |pole|=1), so the lowpass and highpass -3dB points must be
    // solved for independently; reusing the lowpass scale for highpass is
    // wrong and was caught by this file's own test (growing highpass error
    // with order — see git history / test file for the failure this fixed).
    double magSquaredAt(double omega) {
      var mag2 = 1.0;
      for (final s in pairs) {
        // Lowpass 2nd-order section: |H(jw)|^2 = wn^4 / ((wn^2-w^2)^2 + (wn*w/Q)^2)
        // Highpass: same denominator, numerator w^4 instead of wn^4.
        final wn = s.omegaRaw, q = s.qRaw;
        final re = wn * wn - omega * omega;
        final im = (wn / q) * omega;
        final denom = re * re + im * im;
        final numerator = side == FilterSide.lowPass
            ? wn * wn * wn * wn
            : omega * omega * omega * omega;
        mag2 *= numerator / denom;
      }
      if (realPoleOmegaRaw != null) {
        final wn = realPoleOmegaRaw;
        final denom = wn * wn + omega * omega;
        mag2 *= side == FilterSide.lowPass ? (wn * wn) / denom : (omega * omega) / denom;
      }
      return mag2;
    }

    var lo = 1e-3, hi = 1e3;
    // Lowpass magnitude decreases with omega (1 -> 0); highpass increases
    // (0 -> 1) — the bisection must narrow toward 0.5 from the correct side
    // for each.
    final lowpassLike = side == FilterSide.lowPass;
    for (var i = 0; i < 200; i++) {
      final mid = (lo + hi) / 2;
      final above = magSquaredAt(mid) > 0.5;
      if (above == lowpassLike) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final omegaMinus3dbRaw = (lo + hi) / 2;
    final scale = 1.0 / omegaMinus3dbRaw; // normalizes so scaled -3dB is at 1

    final sections = <_AnalogSection>[];
    for (final s in pairs) {
      sections.add(_AnalogSection(
        cutoffHz: cutoffHz * s.omegaRaw * scale,
        q: s.qRaw, // Q is scale-invariant
      ));
    }
    if (realPoleOmegaRaw != null) {
      sections.add(_AnalogSection(cutoffHz: cutoffHz * realPoleOmegaRaw * scale));
    }
    return sections;
  }

  /// Reverse Bessel polynomial theta_n(x), monic, descending coefficients.
  /// Recurrence (exact, integer coefficients — no tabulated data):
  ///   theta_0(x) = 1
  ///   theta_1(x) = x + 1
  ///   theta_n(x) = (2n-1) theta_{n-1}(x) + x^2 theta_{n-2}(x)
  static List<double> _reverseBesselPolynomial(int n) {
    if (n == 0) return [1];
    var prev2 = <double>[1]; // theta_0, degree 0
    var prev1 = <double>[1, 1]; // theta_1 = x + 1, degree 1
    if (n == 1) return prev1;
    for (var k = 2; k <= n; k++) {
      final termA = prev1.map((c) => c * (2 * k - 1)).toList(); // degree k-1
      final termAPadded = [0.0, ...termA]; // degree k
      final termB = [...prev2, 0.0, 0.0]; // x^2 * theta_{k-2}, degree k
      final theta = List<double>.generate(k + 1, (i) => termAPadded[i] + termB[i]);
      prev2 = prev1;
      prev1 = theta;
    }
    return prev1;
  }

  /// Durand-Kerner (Weierstrass) simultaneous root finder for a monic
  /// polynomial given in descending-coefficient form. Reliable for the low
  /// degrees this engine needs (<=8). 300 iterations is well past
  /// convergence for well-separated roots (Bessel poles are always simple,
  /// never repeated).
  static List<_Complex> _polynomialRoots(List<double> coeffsDescending) {
    final n = coeffsDescending.length - 1;
    if (n == 1) {
      return [_Complex(-coeffsDescending[1] / coeffsDescending[0], 0)];
    }
    _Complex evalP(_Complex x) {
      var result = _Complex(coeffsDescending[0], 0);
      for (var i = 1; i < coeffsDescending.length; i++) {
        result = result * x + _Complex(coeffsDescending[i], 0);
      }
      return result;
    }

    var roots = List<_Complex>.generate(n, (k) {
      var r = const _Complex(1, 0);
      const base = _Complex(0.4, 0.9);
      for (var i = 0; i < k; i++) {
        r = r * base;
      }
      return r + const _Complex(0.7, 0.3);
    });

    for (var iter = 0; iter < 300; iter++) {
      final next = List<_Complex>.from(roots);
      for (var k = 0; k < n; k++) {
        var denom = const _Complex(1, 0);
        for (var j = 0; j < n; j++) {
          if (j == k) continue;
          denom = denom * (roots[k] - roots[j]);
        }
        next[k] = roots[k] - evalP(roots[k]) / denom;
      }
      roots = next;
    }
    return roots;
  }

  // ── Analog section → digital biquad (RBJ Audio EQ Cookbook, bilinear) ────
  static Adau1701BiquadCoefficients _biquadFromAnalogSection(
      _AnalogSection s, FilterSide side, double sampleRateHz) {
    final w0 = 2 * math.pi * s.cutoffHz / sampleRateHz;
    final cosw0 = math.cos(w0);
    if (s.q != null) {
      final alpha = math.sin(w0) / (2 * s.q!);
      final a0 = 1 + alpha;
      final a1 = -2 * cosw0;
      final a2 = 1 - alpha;
      final double b0, b1, b2;
      if (side == FilterSide.lowPass) {
        b0 = (1 - cosw0) / 2;
        b1 = 1 - cosw0;
        b2 = (1 - cosw0) / 2;
      } else {
        b0 = (1 + cosw0) / 2;
        b1 = -(1 + cosw0);
        b2 = (1 + cosw0) / 2;
      }
      return Adau1701BiquadCoefficients(
        b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0,
      );
    }
    // First-order section — bilinear-transformed single real pole.
    final k = math.tan(w0 / 2);
    final norm = k + 1;
    if (side == FilterSide.lowPass) {
      return Adau1701BiquadCoefficients(
        b0: k / norm, b1: k / norm, b2: 0, a1: (k - 1) / norm, a2: 0,
      );
    }
    return Adau1701BiquadCoefficients(
      b0: 1 / norm, b1: -1 / norm, b2: 0, a1: (k - 1) / norm, a2: 0,
    );
  }
}

// ── Minimal complex arithmetic (Durand-Kerner needs it; not exposed) ─────────
class _Complex {
  final double re;
  final double im;
  const _Complex(this.re, this.im);

  _Complex operator +(_Complex o) => _Complex(re + o.re, im + o.im);
  _Complex operator -(_Complex o) => _Complex(re - o.re, im - o.im);
  _Complex operator *(_Complex o) =>
      _Complex(re * o.re - im * o.im, re * o.im + im * o.re);
  _Complex operator /(_Complex o) {
    final d = o.re * o.re + o.im * o.im;
    return _Complex((re * o.re + im * o.im) / d, (im * o.re - re * o.im) / d);
  }

  double get abs => math.sqrt(re * re + im * im);
}

// ── Capture comparison structure (Phase 5 prep — no data yet) ────────────────

/// Compares an engine-computed [Adau1701BiquadCoefficients] section against a
/// real captured value from hardware, once one exists. [captured] is null
/// until real SigmaStudio/ICP5 capture evidence is available — there is
/// currently none, and [matchesWithinTolerance] deliberately returns false
/// (never a false "match") when there is nothing to compare against.
class Adau1701CoefficientCaptureComparison {
  final Adau1701BiquadCoefficients computed;
  final Adau1701BiquadCoefficients? captured;
  final double toleranceRatio;

  const Adau1701CoefficientCaptureComparison({
    required this.computed,
    this.captured,
    this.toleranceRatio = 0.01,
  });

  bool get hasCaptureEvidence => captured != null;

  /// Relative difference per coefficient; null when there's nothing captured
  /// to compare against yet.
  Map<String, double>? relativeDifferences() {
    final c = captured;
    if (c == null) return null;
    double rel(double a, double b) => b.abs() < 1e-12 ? (a - b).abs() : (a - b).abs() / b.abs();
    return {
      'b0': rel(computed.b0, c.b0),
      'b1': rel(computed.b1, c.b1),
      'b2': rel(computed.b2, c.b2),
      'a1': rel(computed.a1, c.a1),
      'a2': rel(computed.a2, c.a2),
    };
  }

  bool get matchesWithinTolerance {
    final diffs = relativeDifferences();
    if (diffs == null) return false;
    return diffs.values.every((d) => d <= toleranceRatio);
  }
}
