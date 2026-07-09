// TUNAI PRO — Phase J biquad engine sanity checks.
// Verifies RBJ coefficient calculation correctness and guard behavior.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_biquad_engine.dart';
import 'package:tunai_pro/core/pro_dsp_target_data.dart';

void main() {
  group('ProBiquadEngine', () {
    // ── Peaking EQ ──────────────────────────────────────────────────────────

    test('peaking EQ returns finite calculatedDraft coefficients', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.peakingEq,
        sampleRateHz: 48000,
        frequencyHz: 1000,
        gainDb: 6.0,
        q: 1.0,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.calculatedDraft);
      expect(result.stable, isTrue);
      _assertFinite(result);
    });

    test('peaking EQ 0 dB gain is approximately unity (bypass-like)', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.peakingEq,
        sampleRateHz: 48000,
        frequencyHz: 1000,
        gainDb: 0.0,
        q: 1.0,
      ));
      final c = result.coefficients;
      expect(c.b0, closeTo(1.0, 1e-6));
      expect(c.b1, closeTo(c.a1, 1e-6));
      expect(c.b2, closeTo(c.a2, 1e-6));
    });

    // ── High-Pass ────────────────────────────────────────────────────────────

    test('high-pass returns finite calculatedDraft coefficients', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.highPass,
        sampleRateHz: 48000,
        frequencyHz: 80,
        q: 0.707,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.calculatedDraft);
      expect(result.stable, isTrue);
      _assertFinite(result);
    });

    test('high-pass DC gain is approximately 0 (b0+b1+b2 ≈ 0)', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.highPass,
        sampleRateHz: 48000,
        frequencyHz: 1000,
        q: 0.707,
      ));
      final c = result.coefficients;
      // At DC (z=1): H(1) = (b0+b1+b2)/(1+a1+a2) ≈ 0 for HPF
      final dcNum = c.b0 + c.b1 + c.b2;
      expect(dcNum.abs(), lessThan(1e-6));
    });

    // ── Low-Pass ─────────────────────────────────────────────────────────────

    test('low-pass returns finite calculatedDraft coefficients', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.lowPass,
        sampleRateHz: 48000,
        frequencyHz: 500,
        q: 0.707,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.calculatedDraft);
      expect(result.stable, isTrue);
      _assertFinite(result);
    });

    test('low-pass DC gain is approximately 1.0', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.lowPass,
        sampleRateHz: 48000,
        frequencyHz: 1000,
        q: 0.707,
      ));
      final c = result.coefficients;
      // At DC (z=1): H(1) = (b0+b1+b2)/(1+a1+a2) ≈ 1 for LPF
      final dcNum = c.b0 + c.b1 + c.b2;
      final dcDen = 1.0 + c.a1 + c.a2;
      expect(dcNum / dcDen, closeTo(1.0, 1e-4));
    });

    // ── Disabled filter ───────────────────────────────────────────────────────

    test('disabled filter returns notRequired bypass', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.peakingEq,
        sampleRateHz: 48000,
        frequencyHz: 1000,
        gainDb: 6.0,
        q: 1.0,
        enabled: false,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.notRequired);
      expect(result.coefficients.b0, 1.0);
      expect(result.coefficients.b1, 0.0);
      expect(result.coefficients.b2, 0.0);
    });

    // ── Frequency above Nyquist ───────────────────────────────────────────────

    test('frequency at Nyquist returns requiresVerification with warning', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.highPass,
        sampleRateHz: 48000,
        frequencyHz: 24000, // == Nyquist
        q: 0.707,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.requiresVerification);
      expect(result.stable, isFalse);
      expect(result.warning, isNotNull);
    });

    test('frequency above Nyquist returns requiresVerification with warning', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.peakingEq,
        sampleRateHz: 48000,
        frequencyHz: 30000, // above Nyquist
        gainDb: 3.0,
        q: 1.0,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.requiresVerification);
      expect(result.stable, isFalse);
    });

    // ── Invalid frequency ─────────────────────────────────────────────────────

    test('zero frequency returns requiresVerification with warning', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.lowPass,
        sampleRateHz: 48000,
        frequencyHz: 0,
        q: 0.707,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.requiresVerification);
      expect(result.warning, isNotNull);
    });

    test('negative frequency returns requiresVerification', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.lowPass,
        sampleRateHz: 48000,
        frequencyHz: -100,
        q: 0.707,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.requiresVerification);
    });

    // ── Bypass ────────────────────────────────────────────────────────────────

    test('bypass type returns notRequired bypass coefficients', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.bypass,
        sampleRateHz: 48000,
        frequencyHz: 1000,
        q: 0.707,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.notRequired);
      _assertBypass(result);
    });

    // ── Unsupported types ─────────────────────────────────────────────────────

    test('allPass returns requiresVerification (not yet implemented)', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.allPass,
        sampleRateHz: 48000,
        frequencyHz: 1000,
        q: 0.707,
      ));
      expect(result.coefficients.status, BiquadDraftStatus.requiresVerification);
    });

    // ── No hardware content ───────────────────────────────────────────────────

    test('calculated draft warning mentions floating-point and not fixed-point', () {
      final result = ProBiquadEngine.calculate(const BiquadDesignInput(
        type: BiquadFilterType.peakingEq,
        sampleRateHz: 48000,
        frequencyHz: 1000,
        gainDb: 3.0,
        q: 1.0,
      ));
      final w = result.coefficients.warning ?? '';
      expect(w.toLowerCase(), contains('floating-point'));
      expect(w.toLowerCase(), isNot(contains('safeload')));
      expect(w.toLowerCase(), isNot(contains('adau address')));
      expect(w.toLowerCase(), isNot(contains('register')));
    });
  });
}

void _assertFinite(BiquadDesignResult r) {
  final c = r.coefficients;
  for (final v in [c.b0, c.b1, c.b2, c.a1, c.a2]) {
    expect(v.isFinite, isTrue,
        reason: 'Expected finite coefficient, got $v');
  }
}

void _assertBypass(BiquadDesignResult r) {
  expect(r.coefficients.b0, 1.0);
  expect(r.coefficients.b1, 0.0);
  expect(r.coefficients.b2, 0.0);
  expect(r.coefficients.a1, 0.0);
  expect(r.coefficients.a2, 0.0);
}
