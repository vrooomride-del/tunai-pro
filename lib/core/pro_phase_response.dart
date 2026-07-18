import 'dart:math' as math;

import 'pro_crossover_response.dart';
import 'pro_tuning_data.dart';

/// Minimal complex number for crossover phase math.
class Complex {
  final double re;
  final double im;
  const Complex(this.re, this.im);

  Complex operator +(Complex o) => Complex(re + o.re, im + o.im);
  Complex operator -(Complex o) => Complex(re - o.re, im - o.im);
  Complex operator *(Complex o) =>
      Complex(re * o.re - im * o.im, re * o.im + im * o.re);
  Complex operator /(Complex o) {
    final d = o.re * o.re + o.im * o.im;
    return Complex((re * o.re + im * o.im) / d, (im * o.re - re * o.im) / d);
  }

  double get abs => math.sqrt(re * re + im * im);
  double get argDeg => math.atan2(im, re) * 180 / math.pi;

  /// Unit-magnitude phasor from an angle in degrees.
  static Complex unitDeg(double deg) {
    final r = deg * math.pi / 180;
    return Complex(math.cos(r), math.sin(r));
  }
}

/// Crossover PHASE math for the XO phase-simulation graph.
///
/// Analog-prototype approximation for visualisation only — no DSP write, no
/// coefficient/address mapping. Combines analog filter phase (Butterworth / LR;
/// Bessel and linear-phase reuse Butterworth), driver polarity (±180°), a static
/// phase offset, and pure delay (linear phase). Phase is wrapped to −180..+180°.
abstract final class CrossoverPhase {
  /// Speed of sound used for distance ↔ delay conversion.
  static const double speedOfSoundMps = 343.0;

  /// Distance (mm) corresponding to a one-way [delayMs] at [speedOfSoundMps].
  static double distanceMmFromDelayMs(double delayMs) =>
      delayMs / 1000.0 * speedOfSoundMps * 1000.0;

  /// Delay (ms) corresponding to a one-way [distanceMm] at [speedOfSoundMps].
  static double delayMsFromDistanceMm(double distanceMm) =>
      distanceMm / 1000.0 / speedOfSoundMps * 1000.0;

  /// Linear phase (deg) contributed by a pure [delayMs] at frequency [f].
  static double delayPhaseDeg(double f, double delayMs) =>
      -360.0 * f * (delayMs / 1000.0);

  /// Wraps [deg] to the (−180, 180] interval.
  static double wrapDeg(double deg) {
    var d = deg % 360.0;
    if (d > 180.0) d -= 360.0;
    if (d <= -180.0) d += 360.0;
    return d;
  }

  /// Complex response of one Butterworth section of [order] at [f] (Hz).
  static Complex _butterworthComplex(
      double f, double fc, int order, FilterSide side) {
    final omega = f / fc;
    final jOmega = Complex(0, omega);
    var h = const Complex(1, 0);
    for (var k = 1; k <= order; k++) {
      final theta = math.pi / 2 + (2 * k - 1) * math.pi / (2 * order);
      final sk = Complex(math.cos(theta), math.sin(theta));
      final numerator =
          side == FilterSide.highPass ? jOmega : const Complex(0, 0) - sk;
      h = h * (numerator / (jOmega - sk));
    }
    return h;
  }

  /// Complex response of one crossover [filter] at [f]. Unity for disabled.
  static Complex filterComplex(CrossoverFilter filter, double f) {
    if (!filter.enabled) return const Complex(1, 0);
    final order = CrossoverResponse.orderFor(filter.slope);
    switch (filter.type) {
      case CrossoverFilterType.linkwitzRiley:
        final bw =
            _butterworthComplex(f, filter.frequencyHz, order ~/ 2, filter.side);
        return bw * bw;
      case CrossoverFilterType.butterworth:
      case CrossoverFilterType.bessel:
      case CrossoverFilterType.linearPhasePlaceholder:
        return _butterworthComplex(f, filter.frequencyHz, order, filter.side);
    }
  }

  /// Full complex response of a driver at [f]: crossover filters × polarity ×
  /// (phase offset + delay). Magnitude matches [CrossoverResponse]; the phasor
  /// carries polarity/offset/delay so complex summing is meaningful.
  static Complex driverComplex({
    required CrossoverChannelState channel,
    required double delayMs,
    required double phaseOffsetDeg,
    required double f,
  }) {
    var h = const Complex(1, 0);
    if (!channel.bypassed) {
      final hp = channel.highPass;
      final lp = channel.lowPass;
      if (hp != null) h = h * filterComplex(hp, f);
      if (lp != null) h = h * filterComplex(lp, f);
    }
    if (channel.polarityInverted) h = const Complex(0, 0) - h;
    final extraDeg = phaseOffsetDeg + delayPhaseDeg(f, delayMs);
    return h * Complex.unitDeg(extraDeg);
  }

  /// Driver phase (deg, wrapped) at [f].
  static double driverPhaseDeg({
    required CrossoverChannelState channel,
    required double delayMs,
    required double phaseOffsetDeg,
    required double f,
  }) =>
      wrapDeg(driverComplex(
        channel: channel,
        delayMs: delayMs,
        phaseOffsetDeg: phaseOffsetDeg,
        f: f,
      ).argDeg);

  /// Per-point driver phase curve (deg) over [freqs].
  static List<double> driverPhaseCurve({
    required CrossoverChannelState channel,
    required double delayMs,
    required double phaseOffsetDeg,
    required List<double> freqs,
  }) =>
      [
        for (final f in freqs)
          driverPhaseDeg(
              channel: channel,
              delayMs: delayMs,
              phaseOffsetDeg: phaseOffsetDeg,
              f: f)
      ];

  /// Complex-summed phase (deg) of several drivers over [freqs] — the argument
  /// of the vector sum of each driver's complex response (magnitude + phase).
  static List<double> summedPhaseCurve({
    required List<XoPhaseDriver> drivers,
    required List<double> freqs,
  }) =>
      [
        for (final f in freqs)
          wrapDeg(drivers
              .map((d) => driverComplex(
                    channel: d.channel,
                    delayMs: d.delayMs,
                    phaseOffsetDeg: d.phaseOffsetDeg,
                    f: f,
                  ))
              .fold(const Complex(0, 0), (a, b) => a + b)
              .argDeg)
      ];
}

/// Per-driver inputs for a phase simulation.
class XoPhaseDriver {
  final CrossoverChannelState channel;
  final double delayMs;
  final double phaseOffsetDeg;
  const XoPhaseDriver({
    required this.channel,
    this.delayMs = 0.0,
    this.phaseOffsetDeg = 0.0,
  });
}
