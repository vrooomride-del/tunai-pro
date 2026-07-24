/// Deterministic Measurement Confidence Engine.
///
/// Answers ONE question before any analysis/correction runs: *is this
/// measurement trustworthy enough to act on?* It never produces a DSP value or
/// a correction — only evidence-backed confidence metrics, a grade, and the
/// reasons behind them.
///
/// Design split (so PRO and Consumer can share the MATH but inject their own
/// POLICY):
///   • [MeasurementConfidenceMetrics] — the raw evidence a caller actually has.
///     A metric that was not measured is ABSENT, never invented.
///   • [MeasurementConfidencePolicy] — product thresholds/weights/grades.
///   • [MeasurementConfidenceResult] — overall + per-metric outcomes + reasons.
///
/// Reusable math note: the repeatability score generalises the Consumer
/// `audio_analyzer._splitHalfAgreement` — mean absolute dB difference between
/// two power-spectrum halves over a band, mapped `clamp(1 − meanAbsDiffDb /
/// ceilingDb, 0, 1)`. Here it is generalised to N≥2 spectra (all unique pairs)
/// on a shared grid, in the dB domain, with the band and ceiling supplied by
/// policy. The Consumer ceiling of 6 dB is the one evidence-backed constant;
/// every other threshold/weight below is PROVISIONAL and marked as such.
library;

import 'dart:math' as math;

/// Which evidence a confidence result can draw on.
enum ConfidenceMetric { repeatability, snr, validBandCoverage, clipping }

/// Availability of one metric. `unavailable` (not measured) is distinct from
/// `invalid` (measured but nonsensical) and from a low `available` score.
enum MetricStatus { available, unavailable, invalid }

/// Overall trustworthiness of the input.
enum ConfidenceStatus { valid, insufficientEvidence, invalid }

/// Human-facing grade. `unavailable` means "could not be scored", never "bad".
enum ConfidenceGrade { excellent, good, usable, poor, unavailable }

/// One metric's outcome: its status, its 0..1 score when available, and the
/// raw domain value (meanAbsDiffDb / snrDb / clipping ratio / coverage).
class MetricOutcome {
  final ConfidenceMetric metric;
  final MetricStatus status;
  final double? score;
  final double? rawValue;
  final String? note;

  const MetricOutcome({
    required this.metric,
    required this.status,
    this.score,
    this.rawValue,
    this.note,
  });

  MetricOutcome.available(this.metric,
      {required double this.score, this.rawValue, this.note})
      : status = MetricStatus.available;

  const MetricOutcome.unavailable(this.metric, [this.note])
      : status = MetricStatus.unavailable,
        score = null,
        rawValue = null;

  const MetricOutcome.invalid(this.metric, String this.note)
      : status = MetricStatus.invalid,
        score = null,
        rawValue = null;

  bool get isAvailable => status == MetricStatus.available;
}

/// Grade cut-points on the 0..1 overall score. Anything below [usableMin] is
/// `poor`. Must be descending and within [0, 1].
class ConfidenceGradeThresholds {
  final double excellentMin;
  final double goodMin;
  final double usableMin;

  const ConfidenceGradeThresholds({
    required this.excellentMin,
    required this.goodMin,
    required this.usableMin,
  });

  ConfidenceGrade gradeFor(double score) {
    if (score >= excellentMin) return ConfidenceGrade.excellent;
    if (score >= goodMin) return ConfidenceGrade.good;
    if (score >= usableMin) return ConfidenceGrade.usable;
    return ConfidenceGrade.poor;
  }
}

/// Product policy: which metrics are required, how metrics map to scores, how
/// scores weight into the overall, and where the grade lines sit.
class MeasurementConfidencePolicy {
  final String id;
  final int version;

  /// Metrics that MUST be available; if any is missing the result is
  /// [ConfidenceStatus.insufficientEvidence] (never a confident pass).
  final Set<ConfidenceMetric> requiredMetrics;

  /// Fewer valid in-band bins than this fails closed as insufficient evidence.
  final int minValidBinCount;

  /// Coverage below this adds a warning (coverage already lowers the score).
  final double minValidBandCoverage;

  /// dB of mean half-to-half disagreement mapped to repeatability 0. The one
  /// evidence-backed constant (Consumer `_disagreementCeilingDb`).
  final double repeatabilityCeilingDb;

  /// Repeatability score below this adds a warning. PROVISIONAL.
  final double repeatabilityThreshold;

  /// SNR (dB) at which the SNR score reaches 1.0. PROVISIONAL.
  final double snrScoreCeilingDb;

  /// Clipping ratio at which the clipping score reaches 0.0. PROVISIONAL.
  final double clippingCeilingRatio;

  /// Weights for available metrics; re-normalised over whatever is available.
  final Map<ConfidenceMetric, double> weights;

  final ConfidenceGradeThresholds gradeThresholds;

  const MeasurementConfidencePolicy({
    required this.id,
    required this.version,
    required this.requiredMetrics,
    required this.minValidBinCount,
    required this.minValidBandCoverage,
    required this.repeatabilityCeilingDb,
    required this.repeatabilityThreshold,
    required this.snrScoreCeilingDb,
    required this.clippingCeilingRatio,
    required this.weights,
    required this.gradeThresholds,
  });

  /// PRO provisional policy. Only [repeatabilityCeilingDb] (6 dB) is
  /// evidence-backed (from the Consumer split-half implementation). Every other
  /// number here is a CONSERVATIVE PROVISIONAL default awaiting real
  /// mic/measurement validation — do not treat as final.
  factory MeasurementConfidencePolicy.proProvisional() =>
      const MeasurementConfidencePolicy(
        id: 'pro_provisional',
        version: 1,
        requiredMetrics: {ConfidenceMetric.repeatability},
        minValidBinCount: 8,
        minValidBandCoverage: 0.5,
        repeatabilityCeilingDb: 6.0, // evidence-backed
        repeatabilityThreshold: 0.5, // provisional
        snrScoreCeilingDb: 20.0, // provisional
        clippingCeilingRatio: 0.01, // provisional
        weights: {
          ConfidenceMetric.repeatability: 0.5,
          ConfidenceMetric.validBandCoverage: 0.3,
          ConfidenceMetric.snr: 0.15,
          ConfidenceMetric.clipping: 0.05,
        },
        gradeThresholds: ConfidenceGradeThresholds(
          excellentMin: 0.85, // provisional
          goodMin: 0.70, // provisional
          usableMin: 0.50, // provisional
        ),
      );
}

/// The raw evidence a caller supplies. Absent fields mean "not measured" and
/// yield an `unavailable` metric — they are never defaulted to a passing value.
class MeasurementConfidenceMetrics {
  /// Shared, strictly-ascending, positive, finite frequency grid (Hz).
  final List<double> frequencies;

  /// One or more repeated magnitude spectra (dB), each aligned to
  /// [frequencies]. Repeatability needs ≥2; a single spectrum leaves
  /// repeatability `unavailable` (NOT 1.0).
  final List<List<double>> spectraDb;

  /// Requested valid band (Hz), inclusive.
  final double minBandHz;
  final double maxBandHz;

  /// Linear signal/noise power for SNR. Both required, else SNR is unavailable.
  final double? signalPower;
  final double? noisePower;

  /// Clipped and total sample counts. Both required, else clipping is
  /// unavailable.
  final int? clippedSamples;
  final int? totalSamples;

  const MeasurementConfidenceMetrics({
    required this.frequencies,
    required this.spectraDb,
    required this.minBandHz,
    required this.maxBandHz,
    this.signalPower,
    this.noisePower,
    this.clippedSamples,
    this.totalSamples,
  });
}

/// The full, explainable confidence outcome.
class MeasurementConfidenceResult {
  final ConfidenceStatus status;
  final ConfidenceGrade grade;

  /// 0..1 when scorable, else null (`unavailable`). Never NaN/Infinity.
  final double? overallScore;

  final MetricOutcome repeatability;
  final MetricOutcome snr;
  final MetricOutcome validBandCoverage;
  final MetricOutcome clipping;

  final int validBinCount;
  final int requestedBinCount;
  final double? usableMinHz;
  final double? usableMaxHz;

  final List<String> reasons;
  final List<String> warnings;
  final List<ConfidenceMetric> unavailableMetrics;

  final String policyId;
  final int policyVersion;

  const MeasurementConfidenceResult({
    required this.status,
    required this.grade,
    required this.overallScore,
    required this.repeatability,
    required this.snr,
    required this.validBandCoverage,
    required this.clipping,
    required this.validBinCount,
    required this.requestedBinCount,
    required this.usableMinHz,
    required this.usableMaxHz,
    required this.reasons,
    required this.warnings,
    required this.unavailableMetrics,
    required this.policyId,
    required this.policyVersion,
  });
}

/// Pure, deterministic confidence evaluation. No DateTime, no random, no
/// global state, no I/O. Same input + policy → same result.
abstract final class MeasurementConfidenceEngine {
  static MeasurementConfidenceResult evaluate(
    MeasurementConfidenceMetrics input,
    MeasurementConfidencePolicy policy,
  ) {
    // ── Structural validation (malformed input fails closed as invalid) ──────
    final structural = _validateStructure(input);
    if (structural != null) {
      return _invalid(policy, structural,
          requestedBinCount: 0, validBinCount: 0);
    }

    final freqs = input.frequencies;
    final n = freqs.length;

    // In-band + valid (finite across all spectra) bin bookkeeping.
    final inBand = <int>[];
    for (var i = 0; i < n; i++) {
      if (freqs[i] >= input.minBandHz && freqs[i] <= input.maxBandHz) {
        inBand.add(i);
      }
    }
    final requestedBinCount = inBand.length;
    if (requestedBinCount == 0) {
      return _invalid(policy, 'requested band contains no grid bins.',
          requestedBinCount: 0, validBinCount: 0);
    }

    final validIdx = <int>[];
    for (final i in inBand) {
      var ok = true;
      for (final s in input.spectraDb) {
        if (!s[i].isFinite) {
          ok = false;
          break;
        }
      }
      if (ok) validIdx.add(i);
    }
    final validBinCount = validIdx.length;
    final usableMinHz = validIdx.isEmpty ? null : freqs[validIdx.first];
    final usableMaxHz = validIdx.isEmpty ? null : freqs[validIdx.last];

    final reasons = <String>[];
    final warnings = <String>[];

    // Too few valid bins → insufficient evidence (fail closed, D3).
    if (validBinCount < policy.minValidBinCount) {
      reasons.add(
          'only $validBinCount valid in-band bins (< ${policy.minValidBinCount}).');
      return _insufficient(policy,
          repeatability:
              const MetricOutcome.unavailable(ConfidenceMetric.repeatability),
          snr: const MetricOutcome.unavailable(ConfidenceMetric.snr),
          coverage: MetricOutcome.available(ConfidenceMetric.validBandCoverage,
              score: (validBinCount / requestedBinCount).clamp(0.0, 1.0),
              rawValue: validBinCount / requestedBinCount),
          clipping: const MetricOutcome.unavailable(ConfidenceMetric.clipping),
          validBinCount: validBinCount,
          requestedBinCount: requestedBinCount,
          usableMinHz: usableMinHz,
          usableMaxHz: usableMaxHz,
          reasons: reasons,
          warnings: warnings);
    }

    // ── Per-metric outcomes ──────────────────────────────────────────────────
    final coverageRatio = validBinCount / requestedBinCount;
    final coverage = MetricOutcome.available(ConfidenceMetric.validBandCoverage,
        score: coverageRatio.clamp(0.0, 1.0), rawValue: coverageRatio);
    if (coverageRatio < policy.minValidBandCoverage) {
      warnings.add(
          'valid-band coverage ${_pct(coverageRatio)} below ${_pct(policy.minValidBandCoverage)}.');
    }

    final repeatability = _repeatability(input, policy, validIdx, warnings);
    final snr = _snr(input, policy, reasons);
    final clipping = _clipping(input, policy, reasons);

    final outcomes = <ConfidenceMetric, MetricOutcome>{
      ConfidenceMetric.repeatability: repeatability,
      ConfidenceMetric.validBandCoverage: coverage,
      ConfidenceMetric.snr: snr,
      ConfidenceMetric.clipping: clipping,
    };

    final unavailable = [
      for (final e in outcomes.entries)
        if (e.value.status == MetricStatus.unavailable) e.key,
    ];

    // ── Required metrics ─────────────────────────────────────────────────────
    final missingRequired = [
      for (final m in policy.requiredMetrics)
        if (!(outcomes[m]?.isAvailable ?? false)) m,
    ];
    if (missingRequired.isNotEmpty) {
      reasons.add(
          'required metric(s) unavailable: ${missingRequired.map((e) => e.name).join(', ')}.');
      return MeasurementConfidenceResult(
        status: ConfidenceStatus.insufficientEvidence,
        grade: ConfidenceGrade.unavailable,
        overallScore: null,
        repeatability: repeatability,
        snr: snr,
        validBandCoverage: coverage,
        clipping: clipping,
        validBinCount: validBinCount,
        requestedBinCount: requestedBinCount,
        usableMinHz: usableMinHz,
        usableMaxHz: usableMaxHz,
        reasons: reasons,
        warnings: warnings,
        unavailableMetrics: unavailable,
        policyId: policy.id,
        policyVersion: policy.version,
      );
    }

    // ── Weighted overall over AVAILABLE metrics only ─────────────────────────
    var weightSum = 0.0;
    var weighted = 0.0;
    for (final e in outcomes.entries) {
      if (!e.value.isAvailable) continue;
      final w = policy.weights[e.key] ?? 0.0;
      if (w <= 0) continue;
      weightSum += w;
      weighted += w * (e.value.score ?? 0.0);
    }

    if (weightSum <= 0) {
      reasons.add('no weighted metric available to score.');
      return MeasurementConfidenceResult(
        status: ConfidenceStatus.insufficientEvidence,
        grade: ConfidenceGrade.unavailable,
        overallScore: null,
        repeatability: repeatability,
        snr: snr,
        validBandCoverage: coverage,
        clipping: clipping,
        validBinCount: validBinCount,
        requestedBinCount: requestedBinCount,
        usableMinHz: usableMinHz,
        usableMaxHz: usableMaxHz,
        reasons: reasons,
        warnings: warnings,
        unavailableMetrics: unavailable,
        policyId: policy.id,
        policyVersion: policy.version,
      );
    }

    final overall = (weighted / weightSum).clamp(0.0, 1.0);
    // Overall is a mean of finite 0..1 scores over a positive weight sum, so it
    // is always finite; assert as a guardrail.
    assert(overall.isFinite);

    if (repeatability.isAvailable &&
        (repeatability.score ?? 0) < policy.repeatabilityThreshold) {
      warnings.add(
          'repeatability ${_fmt(repeatability.score!)} below ${_fmt(policy.repeatabilityThreshold)}.');
    }
    reasons.add(
        'scored on ${weightSum == 0 ? 0 : outcomes.values.where((o) => o.isAvailable).length} '
        'available metric(s).');

    return MeasurementConfidenceResult(
      status: ConfidenceStatus.valid,
      grade: policy.gradeThresholds.gradeFor(overall),
      overallScore: overall,
      repeatability: repeatability,
      snr: snr,
      validBandCoverage: coverage,
      clipping: clipping,
      validBinCount: validBinCount,
      requestedBinCount: requestedBinCount,
      usableMinHz: usableMinHz,
      usableMaxHz: usableMaxHz,
      reasons: reasons,
      warnings: warnings,
      unavailableMetrics: unavailable,
      policyId: policy.id,
      policyVersion: policy.version,
    );
  }

  // ── Metric computations ────────────────────────────────────────────────────

  /// Generalised split-half repeatability over all unique spectrum pairs.
  static MetricOutcome _repeatability(
    MeasurementConfidenceMetrics input,
    MeasurementConfidencePolicy policy,
    List<int> validIdx,
    List<String> warnings,
  ) {
    final spectra = input.spectraDb;
    if (spectra.length < 2) {
      return const MetricOutcome.unavailable(ConfidenceMetric.repeatability,
          'a single measurement cannot establish repeatability.');
    }
    var pairSum = 0.0;
    var pairCount = 0;
    for (var a = 0; a < spectra.length; a++) {
      for (var b = a + 1; b < spectra.length; b++) {
        var sum = 0.0;
        var count = 0;
        for (final i in validIdx) {
          final d = (spectra[a][i] - spectra[b][i]).abs();
          if (!d.isFinite) continue;
          sum += d;
          count++;
        }
        if (count == 0) continue;
        pairSum += sum / count;
        pairCount++;
      }
    }
    if (pairCount == 0) {
      return const MetricOutcome.unavailable(ConfidenceMetric.repeatability,
          'no comparable bins across measurements.');
    }
    final meanAbsDiffDb = pairSum / pairCount;
    final score =
        (1 - meanAbsDiffDb / policy.repeatabilityCeilingDb).clamp(0.0, 1.0);
    return MetricOutcome.available(ConfidenceMetric.repeatability,
        score: score, rawValue: meanAbsDiffDb);
  }

  static MetricOutcome _snr(
    MeasurementConfidenceMetrics input,
    MeasurementConfidencePolicy policy,
    List<String> reasons,
  ) {
    final sig = input.signalPower;
    final noise = input.noisePower;
    if (sig == null || noise == null) {
      reasons.add('SNR unavailable: signal/noise power not provided.');
      return const MetricOutcome.unavailable(ConfidenceMetric.snr,
          'signal and noise power are both required for SNR.');
    }
    if (!sig.isFinite || !noise.isFinite || sig <= 0 || noise <= 0) {
      // Non-positive/non-finite power cannot yield a dB SNR — do not invent one.
      return const MetricOutcome.unavailable(ConfidenceMetric.snr,
          'non-positive or non-finite signal/noise power.');
    }
    final snrDb = 10 * math.log(sig / noise) / math.ln10;
    if (!snrDb.isFinite) {
      return const MetricOutcome.unavailable(
          ConfidenceMetric.snr, 'SNR did not resolve to a finite value.');
    }
    final score = (snrDb / policy.snrScoreCeilingDb).clamp(0.0, 1.0);
    return MetricOutcome.available(ConfidenceMetric.snr,
        score: score, rawValue: snrDb);
  }

  static MetricOutcome _clipping(
    MeasurementConfidenceMetrics input,
    MeasurementConfidencePolicy policy,
    List<String> reasons,
  ) {
    final clipped = input.clippedSamples;
    final total = input.totalSamples;
    if (clipped == null || total == null) {
      reasons.add('clipping unavailable: sample counts not provided.');
      return const MetricOutcome.unavailable(ConfidenceMetric.clipping,
          'clipped and total sample counts are both required.');
    }
    // total<=0 / clipped<0 / clipped>total are validated in _validateStructure.
    final ratio = clipped / total;
    final score = (1 - ratio / policy.clippingCeilingRatio).clamp(0.0, 1.0);
    return MetricOutcome.available(ConfidenceMetric.clipping,
        score: score, rawValue: ratio);
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  /// Returns a reason string if the input is malformed, else null.
  static String? _validateStructure(MeasurementConfidenceMetrics input) {
    final freqs = input.frequencies;
    if (freqs.isEmpty) return 'empty frequency grid.';
    if (input.spectraDb.isEmpty) return 'no spectra provided.';
    for (var s = 0; s < input.spectraDb.length; s++) {
      if (input.spectraDb[s].length != freqs.length) {
        return 'spectrum $s length ${input.spectraDb[s].length} != grid ${freqs.length}.';
      }
    }
    for (var i = 0; i < freqs.length; i++) {
      final f = freqs[i];
      if (!f.isFinite || f <= 0) {
        return 'frequency[$i] must be finite and > 0 (got $f).';
      }
      if (i > 0 && !(f > freqs[i - 1])) {
        return 'frequencies must be strictly ascending (no duplicates) at index $i.';
      }
    }
    if (!(input.minBandHz.isFinite) ||
        !(input.maxBandHz.isFinite) ||
        input.minBandHz <= 0 ||
        !(input.maxBandHz > input.minBandHz)) {
      return 'invalid requested band [${input.minBandHz}, ${input.maxBandHz}].';
    }
    final clipped = input.clippedSamples;
    final total = input.totalSamples;
    if (clipped != null && total != null) {
      if (total <= 0) return 'totalSamples must be > 0 when provided.';
      if (clipped < 0) return 'clippedSamples must be >= 0.';
      if (clipped > total) {
        return 'clippedSamples ($clipped) exceeds totalSamples ($total).';
      }
    }
    return null;
  }

  // ── Result builders ────────────────────────────────────────────────────────

  static MeasurementConfidenceResult _invalid(
    MeasurementConfidencePolicy policy,
    String reason, {
    required int requestedBinCount,
    required int validBinCount,
  }) =>
      MeasurementConfidenceResult(
        status: ConfidenceStatus.invalid,
        grade: ConfidenceGrade.unavailable,
        overallScore: null,
        repeatability:
            const MetricOutcome.unavailable(ConfidenceMetric.repeatability),
        snr: const MetricOutcome.unavailable(ConfidenceMetric.snr),
        validBandCoverage:
            const MetricOutcome.unavailable(ConfidenceMetric.validBandCoverage),
        clipping: const MetricOutcome.unavailable(ConfidenceMetric.clipping),
        validBinCount: validBinCount,
        requestedBinCount: requestedBinCount,
        usableMinHz: null,
        usableMaxHz: null,
        reasons: [reason],
        warnings: const [],
        unavailableMetrics: const [],
        policyId: policy.id,
        policyVersion: policy.version,
      );

  static MeasurementConfidenceResult _insufficient(
    MeasurementConfidencePolicy policy, {
    required MetricOutcome repeatability,
    required MetricOutcome snr,
    required MetricOutcome coverage,
    required MetricOutcome clipping,
    required int validBinCount,
    required int requestedBinCount,
    required double? usableMinHz,
    required double? usableMaxHz,
    required List<String> reasons,
    required List<String> warnings,
  }) =>
      MeasurementConfidenceResult(
        status: ConfidenceStatus.insufficientEvidence,
        grade: ConfidenceGrade.unavailable,
        overallScore: null,
        repeatability: repeatability,
        snr: snr,
        validBandCoverage: coverage,
        clipping: clipping,
        validBinCount: validBinCount,
        requestedBinCount: requestedBinCount,
        usableMinHz: usableMinHz,
        usableMaxHz: usableMaxHz,
        reasons: reasons,
        warnings: warnings,
        unavailableMetrics: const [],
        policyId: policy.id,
        policyVersion: policy.version,
      );

  static String _fmt(double v) => v.toStringAsFixed(2);
  static String _pct(double v) => '${(v * 100).toStringAsFixed(0)}%';
}
