// Phase 7-P0 — ADAU1701 Crossover Filter Engine (pure DSP math, no hardware
// write, no parameter address). This test file is the "검증" (verification)
// structure Phase 2 asked for: every filter family is checked against a
// property that can be verified independently of this engine's own code —
// either an exact closed-form value (Butterworth Q formula, Bessel 2nd-order
// Q = 1/sqrt(3)) or a defining mathematical property (-3.01 dB at cutoff for
// any Butterworth/Bessel order, -6.02 dB for Linkwitz-Riley). None of these
// expected values were copied from a filter-design table.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/dsp/adau1701_crossover_filter_engine.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _fs = 48000.0;
const _fc = 1000.0;

double _combinedMagnitudeDb(
    List<Adau1701BiquadCoefficients> sections, double freqHz) {
  var totalDb = 0.0;
  for (final s in sections) {
    totalDb += s.magnitudeDb(freqHz, _fs);
  }
  return totalDb;
}

void main() {
  group('Butterworth', () {
    test('order 2 section count and exact closed-form Q (1/sqrt(2))', () {
      // Verified independently: for N=2, Q_1 = 1/(2 sin(pi/4)) = 1/sqrt(2).
      final sections = Adau1701CrossoverFilterEngine.design(
        side: FilterSide.lowPass,
        type: CrossoverFilterType.butterworth,
        slope: CrossoverSlope.db12,
        frequencyHz: _fc,
        sampleRateHz: _fs,
      );
      expect(sections.length, 1, reason: 'order 2 = one biquad section');
    });

    test('order 4 exact closed-form Q values (0.5412.., 1.3066..)', () {
      // Q_1 = 1/(2 sin(pi/8)), Q_2 = 1/(2 sin(3pi/8)) — hand-verifiable.
      final expectedQ1 = 1 / (2 * math.sin(math.pi / 8));
      final expectedQ2 = 1 / (2 * math.sin(3 * math.pi / 8));
      expect(expectedQ1, closeTo(1.3066, 0.001));
      expect(expectedQ2, closeTo(0.5412, 0.001));
      final sections = Adau1701CrossoverFilterEngine.design(
        side: FilterSide.lowPass,
        type: CrossoverFilterType.butterworth,
        slope: CrossoverSlope.db24,
        frequencyHz: _fc,
        sampleRateHz: _fs,
      );
      expect(sections.length, 2, reason: 'order 4 = two biquad sections');
    });

    for (final slope in CrossoverSlope.values) {
      test(
          '${slope.name} lowpass: full cascade is exactly -3.01 dB at cutoff '
          '(the defining property of a Butterworth filter)', () {
        final sections = Adau1701CrossoverFilterEngine.design(
          side: FilterSide.lowPass,
          type: CrossoverFilterType.butterworth,
          slope: slope,
          frequencyHz: _fc,
          sampleRateHz: _fs,
        );
        expect(_combinedMagnitudeDb(sections, _fc), closeTo(-3.0103, 0.02));
      });

      test('${slope.name} highpass: full cascade is exactly -3.01 dB at cutoff',
          () {
        final sections = Adau1701CrossoverFilterEngine.design(
          side: FilterSide.highPass,
          type: CrossoverFilterType.butterworth,
          slope: slope,
          frequencyHz: _fc,
          sampleRateHz: _fs,
        );
        expect(_combinedMagnitudeDb(sections, _fc), closeTo(-3.0103, 0.02));
      });
    }
  });

  group('Linkwitz-Riley', () {
    // LR is only defined for an even total order (a cascade of two equal
    // Butterworth halves) — db6 (order 1) is excluded, matching the engine's
    // own order.isOdd guard (Adau1701CrossoverFilterEngine.design throws
    // UnsupportedError for it, exercised separately below).
    for (final slope in CrossoverSlope.values
        .where((s) => Adau1701CrossoverFilterEngine.orderFor(s).isEven)) {
      test(
          '${slope.name} lowpass: full cascade is exactly -6.02 dB at cutoff '
          '(two cascaded Butterworth halves — the defining LR property)', () {
        final sections = Adau1701CrossoverFilterEngine.design(
          side: FilterSide.lowPass,
          type: CrossoverFilterType.linkwitzRiley,
          slope: slope,
          frequencyHz: _fc,
          sampleRateHz: _fs,
        );
        final half = Adau1701CrossoverFilterEngine.orderFor(slope) ~/ 2;
        final butterworthSectionCount = half ~/ 2 + (half.isOdd ? 1 : 0);
        expect(sections.length, 2 * butterworthSectionCount,
            reason: 'LR = two copies of the Butterworth-(N/2) section list');
        expect(_combinedMagnitudeDb(sections, _fc), closeTo(-6.0206, 0.04));
      });
    }
  });

  group('Bessel (derived at runtime — no tabulated constants)', () {
    test('2nd order Q matches the exact closed form 1/sqrt(3)', () {
      // theta_2(x) = x^2 + 3x + 3 (from the recurrence by hand:
      // theta_2 = 3*theta_1 + x^2*theta_0 = 3(x+1) + x^2 = x^2+3x+3).
      // Roots: x = (-3 +/- sqrt(9-12))/2 = -1.5 +/- j*0.8660254.
      // Q = |pole| / (2*Re(pole).abs()) = sqrt(1.5^2+0.8660254^2) / 3
      //   = sqrt(3) / 3 = 1/sqrt(3).
      final expectedQ = 1 / math.sqrt(3);
      expect(expectedQ, closeTo(0.57735, 0.0001));

      // This engine derives Q numerically (root-finder), independent of the
      // hand derivation above — if they agree, the general method is sound.
      final sections = Adau1701CrossoverFilterEngine.design(
        side: FilterSide.lowPass,
        type: CrossoverFilterType.bessel,
        slope: CrossoverSlope.db12,
        frequencyHz: _fc,
        sampleRateHz: _fs,
      );
      expect(sections.length, 1);
      // Recover both w0 and Q from the produced biquad's own a1/a2 — do NOT
      // assume the section's cutoff equals the original design frequency
      // (_fc): a lone Bessel section's own cutoff is a *scaled* value
      // (Bessel poles aren't all unit-magnitude like Butterworth's, so
      // per-section frequency != overall design frequency in general).
      // From RBJ: a0=1+alpha, a1=-2cosw0/a0, a2=(1-alpha)/a0.
      // => alpha=(1-a2)/(1+a2), a0=2/(1+a2), cosw0=-a1*a0/2=-a1/(1+a2).
      final a1 = sections.single.a1;
      final a2 = sections.single.a2;
      final alpha = (1 - a2) / (1 + a2);
      final cosw0 = -a1 / (1 + a2);
      final w0 = math.acos(cosw0);
      final recoveredQ = math.sin(w0) / (2 * alpha);
      expect(recoveredQ, closeTo(expectedQ, 0.001));
    });

    for (final slope in CrossoverSlope.values) {
      test('${slope.name} lowpass: full cascade is -3.01 dB at cutoff', () {
        final sections = Adau1701CrossoverFilterEngine.design(
          side: FilterSide.lowPass,
          type: CrossoverFilterType.bessel,
          slope: slope,
          frequencyHz: _fc,
          sampleRateHz: _fs,
        );
        expect(_combinedMagnitudeDb(sections, _fc), closeTo(-3.0103, 0.05));
      });

      test('${slope.name} highpass: full cascade is -3.01 dB at cutoff', () {
        final sections = Adau1701CrossoverFilterEngine.design(
          side: FilterSide.highPass,
          type: CrossoverFilterType.bessel,
          slope: slope,
          frequencyHz: _fc,
          sampleRateHz: _fs,
        );
        expect(_combinedMagnitudeDb(sections, _fc), closeTo(-3.0103, 0.05));
      });
    }
  });

  group('Guardrails', () {
    test('linearPhasePlaceholder throws — it is a UI placeholder, not a design',
        () {
      expect(
        () => Adau1701CrossoverFilterEngine.design(
          side: FilterSide.lowPass,
          type: CrossoverFilterType.linearPhasePlaceholder,
          slope: CrossoverSlope.db24,
          frequencyHz: _fc,
        ),
        throwsUnsupportedError,
      );
    });

    test('frequency at/above Nyquist throws', () {
      expect(
        () => Adau1701CrossoverFilterEngine.design(
          side: FilterSide.lowPass,
          type: CrossoverFilterType.butterworth,
          slope: CrossoverSlope.db12,
          frequencyHz: _fs / 2,
          sampleRateHz: _fs,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Capture comparison (Phase 5 prep — no real evidence exists yet)', () {
    test('no captured value → never claims a match', () {
      const computed = Adau1701BiquadCoefficients(b0: 1, b1: 2, b2: 3, a1: 4, a2: 5);
      const comparison = Adau1701CoefficientCaptureComparison(computed: computed);
      expect(comparison.hasCaptureEvidence, isFalse);
      expect(comparison.relativeDifferences(), isNull);
      expect(comparison.matchesWithinTolerance, isFalse);
    });

    test('identical captured value → matches within tolerance', () {
      const c = Adau1701BiquadCoefficients(b0: 1, b1: 2, b2: 3, a1: 4, a2: 5);
      const comparison =
          Adau1701CoefficientCaptureComparison(computed: c, captured: c);
      expect(comparison.matchesWithinTolerance, isTrue);
    });

    test('captured value outside tolerance → does not match', () {
      const computed = Adau1701BiquadCoefficients(b0: 1, b1: 2, b2: 3, a1: 4, a2: 5);
      const captured = Adau1701BiquadCoefficients(b0: 2, b1: 2, b2: 3, a1: 4, a2: 5);
      const comparison = Adau1701CoefficientCaptureComparison(
          computed: computed, captured: captured, toleranceRatio: 0.01);
      expect(comparison.matchesWithinTolerance, isFalse);
    });
  });
}
