// Pure, deterministic before/after FRD comparison for one correction cycle.
//
// No DSP write, no hardware reference, no Riverpod, no I/O.
// Same inputs always produce the same result.

import '../frd_parser.dart';
import '../pro_correction_cycle.dart';
import 'tools/adapters/frd_grid_aligner.dart';

// ── Policy ────────────────────────────────────────────────────────────────────

/// Thresholds that govern correction-cycle verdict classification.
class CorrectionCyclePolicy {
  final String id;
  final int version;

  /// Minimum number of common-grid points required for a valid comparison.
  final int minCommonPoints;

  /// Mean absolute residual delta >= this is "improved" (positive = better).
  final double improvementThresholdDb;

  /// Mean absolute residual delta <= this is "worsened" (negative = worse).
  final double worseningThresholdDb;

  /// If improvement delta >= this, the cycle is marked
  /// [CorrectionCycleDecision.improvedAndComplete]; otherwise
  /// [CorrectionCycleDecision.improvedNeedsAnotherCycle].
  final double completeThresholdDb;

  /// Worsened-band fraction above this adds a warning note.
  final double worsenedBandFractionWarn;

  /// Require a deploy-ACK reference; if missing, use
  /// [CorrectionCycleDecision.insufficientEvidence].
  final bool requireDeployAck;

  const CorrectionCyclePolicy({
    required this.id,
    required this.version,
    required this.minCommonPoints,
    required this.improvementThresholdDb,
    required this.worseningThresholdDb,
    required this.completeThresholdDb,
    required this.worsenedBandFractionWarn,
    required this.requireDeployAck,
  });

  factory CorrectionCyclePolicy.proProvisional() => const CorrectionCyclePolicy(
        id: 'cycle_pro_provisional',
        version: 1,
        minCommonPoints: 8,
        improvementThresholdDb: 0.5,
        worseningThresholdDb: -0.5,
        completeThresholdDb: 2.0,
        worsenedBandFractionWarn: 0.3,
        requireDeployAck: false,
      );
}

// ── Input ─────────────────────────────────────────────────────────────────────

class CorrectionCycleEvalInput {
  final String projectId;
  final String channelId;
  final List<FrdPoint> beforeFrd;
  final String beforeMeasurementRef;
  final List<FrdPoint> afterFrd;
  final String afterMeasurementRef;
  final String afterMeasurementFileName;
  final String? deployAckRef;

  const CorrectionCycleEvalInput({
    required this.projectId,
    required this.channelId,
    required this.beforeFrd,
    required this.beforeMeasurementRef,
    required this.afterFrd,
    required this.afterMeasurementRef,
    required this.afterMeasurementFileName,
    this.deployAckRef,
  });
}

// ── Evaluator ─────────────────────────────────────────────────────────────────

abstract final class CorrectionCycleEvaluator {
  /// Compare [before] and [after] FRD data under [policy].
  ///
  /// Returns a [CorrectionCycleMetrics] + [CorrectionCycleDecision] pair.
  /// Returns null with a [CorrectionCycleDecision.wrongProjectOrChannel]
  /// reason when the project/channel identity does not match.
  ///
  /// Pure and deterministic — no I/O, no DateTime, no global state.
  static ({CorrectionCycleMetrics? metrics, CorrectionCycleDecision decision, List<String> reasons})
      evaluate(
    CorrectionCycleEvalInput input,
    CorrectionCyclePolicy policy,
  ) {
    // ── H: Deploy-ACK gate ──────────────────────────────────────────────────
    if (policy.requireDeployAck && input.deployAckRef == null) {
      return (
        metrics: null,
        decision: CorrectionCycleDecision.insufficientEvidence,
        reasons: [
          'deploy ACK required by policy but absent — cannot finalize comparison.',
        ],
      );
    }

    // ── Validate inputs ──────────────────────────────────────────────────────
    if (input.projectId.isEmpty || input.channelId.isEmpty) {
      return (
        metrics: null,
        decision: CorrectionCycleDecision.wrongProjectOrChannel,
        reasons: ['projectId or channelId is empty.'],
      );
    }
    if (input.beforeFrd.isEmpty || input.afterFrd.isEmpty) {
      return (
        metrics: null,
        decision: CorrectionCycleDecision.insufficientEvidence,
        reasons: ['before or after FRD has no data points.'],
      );
    }

    // ── Grid alignment (FrdGridAligner — no extrapolation) ───────────────────
    final aligned = FrdGridAligner.align([
      (
        freqs: [for (final p in input.beforeFrd) p.frequency],
        mags: [for (final p in input.beforeFrd) p.spl],
      ),
      (
        freqs: [for (final p in input.afterFrd) p.frequency],
        mags: [for (final p in input.afterFrd) p.spl],
      ),
    ]);

    if (aligned == null || aligned.frequencies.length < policy.minCommonPoints) {
      return (
        metrics: null,
        decision: CorrectionCycleDecision.insufficientEvidence,
        reasons: [
          'insufficient common frequency coverage: '
              '${aligned?.frequencies.length ?? 0} points < '
              '${policy.minCommonPoints} required.',
        ],
      );
    }

    final freqs = aligned.frequencies;
    final beforeMags = aligned.spectraDb[0];
    final afterMags = aligned.spectraDb[1];
    final n = freqs.length;

    // ── Compute metrics against flat 0 dB target ─────────────────────────────
    var sumAbsBefore = 0.0;
    var sumAbsAfter = 0.0;
    var peakBefore = 0.0;
    var peakBeforeHz = freqs.first;
    var peakAfter = 0.0;
    var peakAfterHz = freqs.first;
    var worsenedCount = 0;
    var improvedOrSameCount = 0;

    for (var i = 0; i < n; i++) {
      final errBefore = beforeMags[i].abs();
      final errAfter = afterMags[i].abs();
      sumAbsBefore += errBefore;
      sumAbsAfter += errAfter;
      if (errBefore > peakBefore) {
        peakBefore = errBefore;
        peakBeforeHz = freqs[i];
      }
      if (errAfter > peakAfter) {
        peakAfter = errAfter;
        peakAfterHz = freqs[i];
      }
      if (errAfter > errBefore) {
        worsenedCount++;
      } else {
        improvedOrSameCount++;
      }
    }

    final marBefore = sumAbsBefore / n;
    final marAfter = sumAbsAfter / n;
    final delta = marBefore - marAfter;
    final improvementCoverage = n == 0 ? 0.0 : improvedOrSameCount / n;

    final metrics = CorrectionCycleMetrics(
      commonFreqMinHz: freqs.first,
      commonFreqMaxHz: freqs.last,
      commonPointCount: n,
      meanAbsResidualBefore: marBefore,
      meanAbsResidualAfter: marAfter,
      improvementDelta: delta,
      peakErrorBefore: peakBefore,
      peakErrorBeforeHz: peakBeforeHz,
      peakErrorAfter: peakAfter,
      peakErrorAfterHz: peakAfterHz,
      worsenedBandCount: worsenedCount,
      improvementCoverage: improvementCoverage,
    );

    // ── Decision ─────────────────────────────────────────────────────────────
    final reasons = <String>[];
    final worsenedFraction = n == 0 ? 0.0 : worsenedCount / n;
    if (worsenedFraction > policy.worsenedBandFractionWarn) {
      reasons.add(
          '${(worsenedFraction * 100).toStringAsFixed(0)}% of bands worsened.');
    }

    final CorrectionCycleDecision decision;
    if (delta >= policy.improvementThresholdDb) {
      if (delta >= policy.completeThresholdDb) {
        decision = CorrectionCycleDecision.improvedAndComplete;
        reasons.insert(
            0,
            'improvement delta ${delta.toStringAsFixed(2)} dB >= '
            'complete threshold ${policy.completeThresholdDb} dB.');
      } else {
        decision = CorrectionCycleDecision.improvedNeedsAnotherCycle;
        reasons.insert(
            0,
            'improvement delta ${delta.toStringAsFixed(2)} dB improved '
            'but below complete threshold ${policy.completeThresholdDb} dB '
            '— another cycle recommended.');
      }
    } else if (delta <= policy.worseningThresholdDb) {
      decision = CorrectionCycleDecision.worsened;
      reasons.insert(
          0,
          'improvement delta ${delta.toStringAsFixed(2)} dB <= '
          'worsening threshold ${policy.worseningThresholdDb} dB.');
    } else {
      decision = CorrectionCycleDecision.noMeaningfulImprovement;
      reasons.insert(
          0,
          'delta ${delta.toStringAsFixed(2)} dB within neutral band '
          '[${policy.worseningThresholdDb}, ${policy.improvementThresholdDb}].');
    }

    return (metrics: metrics, decision: decision, reasons: reasons);
  }
}
