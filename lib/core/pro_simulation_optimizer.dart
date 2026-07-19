// ── TUNAI PRO — Simulation PEQ Optimizer (local, deterministic) ───────────────
// Greedy, error-driven PEQ suggestion engine. Simulation only: it reads the
// measured response + current PEQ, compares against the target curve, and emits
// OptimizerSuggestion(addPeqBand) objects for the existing review/apply flow.
// No cloud AI. No DSP write / mapping / deployment.

import 'dart:math' as math;

import 'adau1701_peq_response.dart';
import 'pro_acoustic_data.dart';
import 'pro_optimizer_data.dart';
import 'pro_response_error.dart';
import 'pro_target_curve.dart';
import 'pro_tuning_data.dart';

/// Per-mode bounds that shape how aggressively the greedy pass corrects.
class _ModeProfile {
  final int maxNewBands; // cap on suggestions per driver, per run
  final double gainScale; // fraction of the measured deviation to correct
  final double q; // proposed band Q
  final double minCorrectableDb; // stop once residual deviation is below this

  const _ModeProfile({
    required this.maxNewBands,
    required this.gainScale,
    required this.q,
    required this.minCorrectableDb,
  });

  static _ModeProfile of(OptimizerMode mode) => switch (mode) {
        OptimizerMode.conservative =>
          const _ModeProfile(maxNewBands: 2, gainScale: 0.6, q: 1.0, minCorrectableDb: 1.5),
        OptimizerMode.balanced =>
          const _ModeProfile(maxNewBands: 3, gainScale: 0.8, q: 1.4, minCorrectableDb: 1.0),
        OptimizerMode.aggressive =>
          const _ModeProfile(maxNewBands: 5, gainScale: 1.0, q: 2.0, minCorrectableDb: 0.7),
        OptimizerMode.manualReview =>
          const _ModeProfile(maxNewBands: 1, gainScale: 0.7, q: 1.2, minCorrectableDb: 1.5),
      };
}

/// Result of optimizing one driver: the proposed suggestions plus the
/// before/after scores (for surfacing "score improved" context if wanted).
class DriverOptimizeResult {
  final List<OptimizerSuggestion> suggestions;
  final ResponseErrorResult before;
  final ResponseErrorResult after;

  const DriverOptimizeResult({
    required this.suggestions,
    required this.before,
    required this.after,
  });
}

abstract final class ProSimulationOptimizer {
  /// Number of log-spaced evaluation points across 20 Hz–20 kHz.
  static const int gridPoints = 128;

  /// Greedily proposes PEQ bands for a single [driver] so its simulated
  /// response approaches [target]. Bounded by [config] (mode, band budget,
  /// max boost/cut). When the driver has no parsed FRD, a flat baseline is
  /// assumed and suggestions are marked low-confidence draft-only.
  static DriverOptimizeResult optimizeDriver({
    required DriverChannel driver,
    required PeqChannelState currentPeq,
    required TargetCurvePreset target,
    required OptimizerRunConfig config,
    required String Function() nextId,
  }) {
    final profile = _ModeProfile.of(config.mode);
    final freqs = Adau1701PeqResponse.logFrequencyPoints(count: gridPoints);
    final weights = ProResponseError.defaultWeights(freqs);
    final targetCurve = ProTargetCurve.curve(target, freqs);

    final hasFrd = driver.hasParsedFrd;
    // Measured baseline (level-normalized so PEQ targets shape, not absolute
    // level), or a flat baseline when no measurement is available.
    final baseline = hasFrd
        ? _levelNormalize(_sampleFrd(driver.frdData!, freqs))
        : List<double>.filled(freqs.length, 0.0);

    // Existing enabled PEQ bands already contribute to the response.
    final workingBands = <PeqResponseBand>[
      for (final b in currentPeq.bands)
        if (b.enabled)
          PeqResponseBand(frequencyHz: b.frequencyHz, gainDb: b.gainDb, q: b.q),
    ];

    List<double> responseFor(List<PeqResponseBand> bands) {
      final peq = Adau1701PeqResponse.combinedCurve(bands, freqs);
      return [for (var i = 0; i < freqs.length; i++) baseline[i] + peq[i]];
    }

    final before = ProResponseError.analyze(
      freqs: freqs,
      responseDb: responseFor(workingBands),
      targetDb: targetCurve,
      weights: weights,
    );

    final suggestions = <OptimizerSuggestion>[];
    final budget = config.maxPeqBandsPerChannel - workingBands.length;
    if (budget <= 0) {
      return DriverOptimizeResult(
          suggestions: suggestions, before: before, after: before);
    }
    final maxNew = math.min(budget, profile.maxNewBands);

    // Running error curve: response − target. Adding a corrective band shifts
    // this by the band's own response, letting us re-target the next-worst spot.
    var error = [
      for (var i = 0; i < freqs.length; i++)
        responseFor(workingBands)[i] - targetCurve[i]
    ];

    final confidence =
        hasFrd ? OptimizerConfidence.medium : OptimizerConfidence.low;

    for (var n = 0; n < maxNew; n++) {
      // Worst weighted deviation.
      var worst = 0.0;
      var worstIdx = -1;
      for (var i = 0; i < freqs.length; i++) {
        final wErr = weights[i] * error[i].abs();
        if (wErr > worst) {
          worst = wErr;
          worstIdx = i;
        }
      }
      if (worstIdx < 0) break;
      final devDb = error[worstIdx];
      if (devDb.abs() < profile.minCorrectableDb) break;

      final f = freqs[worstIdx];
      // Correct toward target: positive deviation (too loud) → cut.
      final rawGain = -devDb * profile.gainScale;
      final gain = rawGain.clamp(-config.maxCutDb, config.maxBoostDb);
      if (gain.abs() < 0.1) break;

      final band = PeqResponseBand(frequencyHz: f, gainDb: gain, q: profile.q);
      workingBands.add(band);

      final gainText = '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB';
      final reason = hasFrd
          ? 'Measured response deviates ${devDb >= 0 ? '+' : ''}'
              '${devDb.toStringAsFixed(1)} dB from ${target.label} target near '
              '${_hz(f)}.'
          : 'No measurement (FRD) imported — flat baseline assumed. Draft only; '
              'import FRD for verified optimization.';

      suggestions.add(OptimizerSuggestion(
        id: nextId(),
        type: OptimizerSuggestionType.addPeqBand,
        confidence: confidence,
        channelId: driver.id,
        title: 'PEQ ${_hz(f)} on ${driver.name}',
        description:
            'Draft PEQ band at ${_hz(f)} ($gainText, Q ${profile.q.toStringAsFixed(1)})'
            '${hasFrd ? '' : ' — measurement recommended'}.',
        reason: reason,
        proposedFrequencyHz: f,
        proposedGainDb: gain.toDouble(),
        proposedQ: profile.q,
      ));

      // Fold the new band into the error curve for the next iteration.
      final bandResp = Adau1701PeqResponse.bandCurve(band, freqs);
      for (var i = 0; i < freqs.length; i++) {
        error[i] += bandResp[i];
      }
    }

    final after = ProResponseError.analyze(
      freqs: freqs,
      responseDb: responseFor(workingBands),
      targetDb: targetCurve,
      weights: weights,
    );

    return DriverOptimizeResult(
        suggestions: suggestions, before: before, after: after);
  }

  /// Shared log-frequency grid (20 Hz–20 kHz) used by the optimizer and its
  /// preview. Convenience wrapper for visualization callers.
  static List<double> previewFrequencies() =>
      Adau1701PeqResponse.logFrequencyPoints(count: gridPoints);

  /// Simulated magnitude response (level-normalized measured baseline + [bands])
  /// on [freqs]. Read-only helper for the Before/After preview graph — it does
  /// not affect optimization, suggestions, or any DSP write.
  static List<double> simulatedResponse({
    required DriverChannel driver,
    required Iterable<PeqResponseBand> bands,
    required List<double> freqs,
  }) {
    final baseline = driver.hasParsedFrd
        ? _levelNormalize(_sampleFrd(driver.frdData!, freqs))
        : List<double>.filled(freqs.length, 0.0);
    final peq = Adau1701PeqResponse.combinedCurve(bands, freqs);
    return [for (var i = 0; i < freqs.length; i++) baseline[i] + peq[i]];
  }

  /// Samples a measured FRD to the [freqs] grid via linear interpolation in
  /// log-frequency over the points that carry magnitude. Outside the measured
  /// span the nearest endpoint is held.
  static List<double> _sampleFrd(ParsedMeasurementData frd, List<double> freqs) {
    final pts = [
      for (final p in frd.points)
        if (p.magnitudeDb != null) (logf: math.log(p.frequencyHz), db: p.magnitudeDb!)
    ]..sort((a, b) => a.logf.compareTo(b.logf));

    if (pts.isEmpty) return List<double>.filled(freqs.length, 0.0);
    if (pts.length == 1) return List<double>.filled(freqs.length, pts.first.db);

    return [
      for (final f in freqs) _interp(pts, math.log(f)),
    ];
  }

  static double _interp(
      List<({double logf, double db})> pts, double logf) {
    if (logf <= pts.first.logf) return pts.first.db;
    if (logf >= pts.last.logf) return pts.last.db;
    // Binary search for the bracketing interval.
    var lo = 0;
    var hi = pts.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (pts[mid].logf <= logf) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = pts[lo];
    final b = pts[hi];
    final t = (logf - a.logf) / (b.logf - a.logf);
    return a.db + (b.db - a.db) * t;
  }

  /// Removes the overall level (mean) so the optimizer corrects response shape,
  /// not absolute gain (which is the level/gain stage's job, not PEQ).
  static List<double> _levelNormalize(List<double> curve) {
    if (curve.isEmpty) return curve;
    final mean = curve.reduce((a, b) => a + b) / curve.length;
    return [for (final v in curve) v - mean];
  }

  static String _hz(double f) =>
      f >= 1000 ? '${(f / 1000).toStringAsFixed(f % 1000 == 0 ? 0 : 1)} kHz' : '${f.round()} Hz';
}
