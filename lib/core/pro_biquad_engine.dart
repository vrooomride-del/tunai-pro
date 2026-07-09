// ── TUNAI PRO Phase J — Biquad Coefficient Engine Draft ──────────────────────
// Floating-point RBJ Audio EQ Cookbook coefficient calculation.
// No hardware write. No ADAU fixed-point conversion. No DSP register addresses.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:math' as math;
import 'pro_dsp_target_data.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum BiquadFilterType {
  peakingEq,
  lowPass,
  highPass,
  lowShelf,
  highShelf,
  allPass,
  bypass;

  String get label => switch (this) {
    BiquadFilterType.peakingEq  => 'Peaking EQ',
    BiquadFilterType.lowPass    => 'Low-Pass',
    BiquadFilterType.highPass   => 'High-Pass',
    BiquadFilterType.lowShelf   => 'Low Shelf',
    BiquadFilterType.highShelf  => 'High Shelf',
    BiquadFilterType.allPass    => 'All-Pass',
    BiquadFilterType.bypass     => 'Bypass',
  };

  bool get isSupported => switch (this) {
    BiquadFilterType.peakingEq => true,
    BiquadFilterType.lowPass   => true,
    BiquadFilterType.highPass  => true,
    _                          => false,
  };

  String toJson() => name;
  static BiquadFilterType fromJson(String s) =>
      BiquadFilterType.values.firstWhere((e) => e.name == s,
          orElse: () => BiquadFilterType.bypass);
}

// ── Models ────────────────────────────────────────────────────────────────────

class BiquadDesignInput {
  final BiquadFilterType type;
  final double sampleRateHz;
  final double frequencyHz;
  final double gainDb;
  final double q;
  final bool enabled;
  final String? sourceDescription;

  const BiquadDesignInput({
    required this.type,
    required this.sampleRateHz,
    required this.frequencyHz,
    this.gainDb = 0.0,
    this.q = 0.707,
    this.enabled = true,
    this.sourceDescription,
  });

  double get nyquist => sampleRateHz / 2.0;

  String? validate() {
    if (!enabled) return null;
    if (sampleRateHz <= 0) return 'Sample rate must be > 0.';
    if (frequencyHz <= 0) return 'Frequency must be > 0 Hz.';
    if (frequencyHz >= nyquist) {
      return 'Frequency ${frequencyHz.toStringAsFixed(1)} Hz exceeds Nyquist '
          '(${nyquist.toStringAsFixed(0)} Hz) for ${sampleRateHz.toStringAsFixed(0)} Hz sample rate.';
    }
    if (q <= 0) return 'Q must be > 0.';
    return null;
  }
}

class BiquadDesignResult {
  final BiquadCoefficientSet coefficients;
  final bool normalized;
  final bool stable;
  final String? warning;
  final String summary;

  const BiquadDesignResult({
    required this.coefficients,
    this.normalized = true,
    this.stable = true,
    this.warning,
    required this.summary,
  });

  bool get isCalculated =>
      coefficients.status == BiquadDraftStatus.calculatedDraft;
}

// ── Engine ────────────────────────────────────────────────────────────────────

class ProBiquadEngine {
  static const _draftWarning =
      'Draft floating-point coefficient. Not converted to target DSP fixed-point format.';
  static const _verifyWarning =
      'Coefficient requires acoustic and hardware verification before deployment.';

  // ── Public entry point ────────────────────────────────────────────────────

  static BiquadDesignResult calculate(BiquadDesignInput input) {
    if (!input.enabled) return _bypass('Filter disabled.');

    final validationError = input.validate();
    if (validationError != null) {
      return _fallback(BiquadDraftStatus.requiresVerification, validationError);
    }

    if (input.type == BiquadFilterType.bypass) {
      return _bypass('Bypass requested.');
    }

    if (!input.type.isSupported) {
      return _fallback(
        BiquadDraftStatus.requiresVerification,
        '${input.type.label} not yet implemented — placeholder returned. $_verifyWarning',
      );
    }

    return switch (input.type) {
      BiquadFilterType.peakingEq => _peakingEq(input),
      BiquadFilterType.highPass  => _highPass(input),
      BiquadFilterType.lowPass   => _lowPass(input),
      _                          => _fallback(
          BiquadDraftStatus.requiresVerification,
          '${input.type.label} not yet implemented. $_verifyWarning',
        ),
    };
  }

  // ── RBJ Peaking EQ ───────────────────────────────────────────────────────

  static BiquadDesignResult _peakingEq(BiquadDesignInput inp) {
    final w0 = 2.0 * math.pi * inp.frequencyHz / inp.sampleRateHz;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final alpha = sinW0 / (2.0 * inp.q);
    final A = math.pow(10.0, inp.gainDb / 40.0).toDouble();

    final b0r = 1.0 + alpha * A;
    final b1r = -2.0 * cosW0;
    final b2r = 1.0 - alpha * A;
    final a0r = 1.0 + alpha / A;
    final a1r = -2.0 * cosW0;
    final a2r = 1.0 - alpha / A;

    return _normalizeAndValidate(
      b0r, b1r, b2r, a0r, a1r, a2r,
      'Peaking EQ  ${inp.frequencyHz.toStringAsFixed(0)} Hz  '
      '${inp.gainDb >= 0 ? '+' : ''}${inp.gainDb.toStringAsFixed(2)} dB  '
      'Q${inp.q.toStringAsFixed(3)}  '
      '@ ${(inp.sampleRateHz / 1000).toStringAsFixed(0)} kHz',
    );
  }

  // ── RBJ High-Pass ────────────────────────────────────────────────────────

  static BiquadDesignResult _highPass(BiquadDesignInput inp) {
    final w0 = 2.0 * math.pi * inp.frequencyHz / inp.sampleRateHz;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final alpha = sinW0 / (2.0 * inp.q);

    final b0r = (1.0 + cosW0) / 2.0;
    final b1r = -(1.0 + cosW0);
    final b2r = (1.0 + cosW0) / 2.0;
    final a0r = 1.0 + alpha;
    final a1r = -2.0 * cosW0;
    final a2r = 1.0 - alpha;

    return _normalizeAndValidate(
      b0r, b1r, b2r, a0r, a1r, a2r,
      'HPF  ${inp.frequencyHz.toStringAsFixed(0)} Hz  '
      'Q${inp.q.toStringAsFixed(3)}  '
      '@ ${(inp.sampleRateHz / 1000).toStringAsFixed(0)} kHz',
    );
  }

  // ── RBJ Low-Pass ─────────────────────────────────────────────────────────

  static BiquadDesignResult _lowPass(BiquadDesignInput inp) {
    final w0 = 2.0 * math.pi * inp.frequencyHz / inp.sampleRateHz;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final alpha = sinW0 / (2.0 * inp.q);

    final b0r = (1.0 - cosW0) / 2.0;
    final b1r = 1.0 - cosW0;
    final b2r = (1.0 - cosW0) / 2.0;
    final a0r = 1.0 + alpha;
    final a1r = -2.0 * cosW0;
    final a2r = 1.0 - alpha;

    return _normalizeAndValidate(
      b0r, b1r, b2r, a0r, a1r, a2r,
      'LPF  ${inp.frequencyHz.toStringAsFixed(0)} Hz  '
      'Q${inp.q.toStringAsFixed(3)}  '
      '@ ${(inp.sampleRateHz / 1000).toStringAsFixed(0)} kHz',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static BiquadDesignResult _normalizeAndValidate(
    double b0r, double b1r, double b2r,
    double a0r, double a1r, double a2r,
    String summary,
  ) {
    if (a0r == 0.0 || !a0r.isFinite) {
      return _fallback(BiquadDraftStatus.requiresVerification,
          'Degenerate denominator (a0=0 or non-finite). $_verifyWarning');
    }

    final b0 = b0r / a0r;
    final b1 = b1r / a0r;
    final b2 = b2r / a0r;
    final a1 = a1r / a0r;
    final a2 = a2r / a0r;

    for (final v in [b0, b1, b2, a1, a2]) {
      if (!v.isFinite) {
        return _fallback(BiquadDraftStatus.requiresVerification,
            'Non-finite coefficient generated. $_verifyWarning');
      }
    }

    return BiquadDesignResult(
      coefficients: BiquadCoefficientSet(
        b0: b0, b1: b1, b2: b2, a1: a1, a2: a2,
        status: BiquadDraftStatus.calculatedDraft,
        warning: '$_draftWarning $_verifyWarning',
      ),
      normalized: true,
      stable: true,
      summary: summary,
    );
  }

  static BiquadDesignResult _bypass(String reason) => BiquadDesignResult(
    coefficients: const BiquadCoefficientSet(
      b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0,
      status: BiquadDraftStatus.notRequired,
    ),
    normalized: true,
    stable: true,
    summary: 'Bypass — $reason',
  );

  static BiquadDesignResult _fallback(BiquadDraftStatus status, String warning) =>
      BiquadDesignResult(
        coefficients: BiquadCoefficientSet(
          b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0,
          status: status,
          warning: warning,
        ),
        normalized: true,
        stable: false,
        warning: warning,
        summary: 'Fallback: $warning',
      );
}
