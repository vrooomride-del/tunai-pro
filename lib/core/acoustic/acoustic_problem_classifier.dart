import 'dart:math' as math;

import 'acoustic_classification_policy.dart';
import 'measurement_confidence.dart'
    show ConfidenceGrade, ConfidenceStatus, MeasurementConfidenceResult;
import 'measurement_evidence.dart' show MeasurementDomain, MeasurementSource;

/// Acoustic Problem Classifier v1 — OBSERVED features only.
///
/// From a measured magnitude response and its target it extracts the residual
/// and reports what is OBSERVABLE (narrow/broad peaks and dips, deep nulls,
/// broad trends) plus a default Actionability per feature. It never asserts a
/// CAUSE (room mode / boundary / crossover / phase), and it never produces a
/// DSP band, gain, Q, coefficient, or address — those belong to a later
/// Correction Plan layer. Pure and deterministic: same input + policy → same
/// result and ids.

// ── Enums ─────────────────────────────────────────────────────────────────────

enum AcousticFeatureType {
  narrowPeak,
  broadPeak,
  narrowDip,
  broadDip,
  deepNull,
  risingTrend,
  fallingTrend,
}

/// How much to trust a single feature.
enum AcousticFeatureQuality { confident, tentative }

enum AcousticActionability {
  safePeqCutCandidate,
  cautiousBroadCorrection,
  informationalOnly,
  doNotBoost,
  inspectPlacementOrPhase,
  requiresExpertReview,
  remeasureRequired,
  noAutomaticCorrection,
}

enum AcousticClassificationStatus {
  ok,
  insufficientEvidence,
  invalidMeasurement
}

/// How the measurement confidence gates automatic correction.
enum MeasurementConfidenceInterpretation {
  correctableAllowed,
  conservative,
  analysisOnly,
  remeasure,
}

// ── Input / output models ─────────────────────────────────────────────────────

class AcousticClassificationInput {
  final List<double> frequenciesHz;
  final List<double> measuredMagnitudeDb;
  final List<double> targetMagnitudeDb;
  final MeasurementConfidenceResult measurementConfidence;
  final MeasurementSource measurementSource;
  final MeasurementDomain measurementDomain;
  final List<String> evidenceRefs;

  const AcousticClassificationInput({
    required this.frequenciesHz,
    required this.measuredMagnitudeDb,
    required this.targetMagnitudeDb,
    required this.measurementConfidence,
    required this.measurementSource,
    required this.measurementDomain,
    this.evidenceRefs = const [],
  });
}

class AcousticObservedFeature {
  final String featureId;
  final AcousticFeatureType type;
  final double startHz;
  final double centerHz;
  final double endHz;

  /// Signed original residual (dB) at the feature center. Positive = above
  /// target. An OBSERVATION, not a correction command.
  final double deviationDb;

  /// Local prominence (dB) above/below the smoothed baseline.
  final double prominenceDb;
  final double bandwidthHz;
  final double bandwidthOctaves;
  final double estimatedQ;
  final AcousticFeatureQuality quality;
  final AcousticActionability actionability;
  final List<String> reasons;
  final List<String> warnings;

  const AcousticObservedFeature({
    required this.featureId,
    required this.type,
    required this.startHz,
    required this.centerHz,
    required this.endHz,
    required this.deviationDb,
    required this.prominenceDb,
    required this.bandwidthHz,
    required this.bandwidthOctaves,
    required this.estimatedQ,
    required this.quality,
    required this.actionability,
    this.reasons = const [],
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
        'featureId': featureId,
        'type': type.name,
        'startHz': startHz,
        'centerHz': centerHz,
        'endHz': endHz,
        'deviationDb': deviationDb,
        'prominenceDb': prominenceDb,
        'bandwidthHz': bandwidthHz,
        'bandwidthOctaves': bandwidthOctaves,
        'estimatedQ': estimatedQ,
        'quality': quality.name,
        'actionability': actionability.name,
        'reasons': reasons,
        'warnings': warnings,
      };
}

class ResidualSummary {
  final double rmsDb;
  final double maxAbsDeviationDb;
  final double maxAbsDeviationHz;
  const ResidualSummary({
    required this.rmsDb,
    required this.maxAbsDeviationDb,
    required this.maxAbsDeviationHz,
  });

  Map<String, dynamic> toJson() => {
        'rmsDb': rmsDb,
        'maxAbsDeviationDb': maxAbsDeviationDb,
        'maxAbsDeviationHz': maxAbsDeviationHz,
      };
}

class AcousticClassificationResult {
  final AcousticClassificationStatus status;
  final ResidualSummary? residualSummary;
  final List<AcousticObservedFeature> observedFeatures;
  final double? analysisMinHz;
  final double? analysisMaxHz;
  final MeasurementConfidenceInterpretation confidenceInterpretation;

  /// Feature types that must NOT be auto-corrected under the current
  /// confidence/observation (e.g. deepNull always; everything under
  /// analysisOnly/remeasure).
  final List<AcousticFeatureType> blockedAutomaticCorrections;
  final List<String> suggestedNextActions;
  final List<String> reasons;
  final List<String> warnings;
  final String policyId;
  final int policyVersion;
  final List<String> evidenceRefs;

  const AcousticClassificationResult({
    required this.status,
    required this.residualSummary,
    required this.observedFeatures,
    required this.analysisMinHz,
    required this.analysisMaxHz,
    required this.confidenceInterpretation,
    required this.blockedAutomaticCorrections,
    required this.suggestedNextActions,
    required this.reasons,
    required this.warnings,
    required this.policyId,
    required this.policyVersion,
    required this.evidenceRefs,
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        if (residualSummary != null)
          'residualSummary': residualSummary!.toJson(),
        'observedFeatures': [for (final f in observedFeatures) f.toJson()],
        if (analysisMinHz != null) 'analysisMinHz': analysisMinHz,
        if (analysisMaxHz != null) 'analysisMaxHz': analysisMaxHz,
        'confidenceInterpretation': confidenceInterpretation.name,
        'blockedAutomaticCorrections': [
          for (final t in blockedAutomaticCorrections) t.name
        ],
        'suggestedNextActions': suggestedNextActions,
        'reasons': reasons,
        'warnings': warnings,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'evidenceRefs': evidenceRefs,
      };
}

// ── Classifier ────────────────────────────────────────────────────────────────

abstract final class AcousticProblemClassifier {
  static AcousticClassificationResult classify(
    AcousticClassificationInput input,
    AcousticClassificationPolicy policy,
  ) {
    policy.validate();
    final interp = _interpret(input.measurementConfidence);

    // ── Structural validation → invalidMeasurement ───────────────────────────
    final invalid = _validateStructure(input);
    if (invalid != null) {
      return _terminal(AcousticClassificationStatus.invalidMeasurement, invalid,
          policy, interp, input.evidenceRefs);
    }

    final freqs = input.frequenciesHz;
    final n = freqs.length;

    // In-band indices.
    final band = <int>[];
    for (var i = 0; i < n; i++) {
      if (freqs[i] >= policy.analysisMinHz &&
          freqs[i] <= policy.analysisMaxHz) {
        band.add(i);
      }
    }
    if (band.length < policy.minimumBins) {
      return _terminal(
          AcousticClassificationStatus.insufficientEvidence,
          'only ${band.length} in-band bins (< ${policy.minimumBins}).',
          policy,
          interp,
          input.evidenceRefs);
    }

    // residual and log2f over the band.
    final idx = band;
    final f = [for (final i in idx) freqs[i]];
    final log2f = [for (final v in f) math.log(v) / math.ln2];
    final residual = [
      for (final i in idx)
        input.measuredMagnitudeDb[i] - input.targetMagnitudeDb[i]
    ];

    final residualSummary = _summary(f, residual);
    final warnings = <String>[];

    // ── Broad trend (linear fit over log2f) ──────────────────────────────────
    final span = log2f.last - log2f.first;
    final fit = _linearFit(log2f, residual);
    final trendFeatures = <AcousticObservedFeature>[];
    if (span >= policy.trendMinimumSpanOctaves &&
        fit.slope.abs() >= policy.trendSlopeThresholdDbPerOctave) {
      trendFeatures.add(_trendFeature(f, fit.slope));
    } else if (span < policy.trendMinimumSpanOctaves) {
      warnings.add(
          'analysis span ${span.toStringAsFixed(2)} oct below trend minimum '
          '${policy.trendMinimumSpanOctaves} — no trend asserted.');
    }

    // Detrended residual (remove the broad shape before local detection).
    final detrended = [
      for (var k = 0; k < residual.length; k++)
        residual[k] - (fit.intercept + fit.slope * log2f[k])
    ];

    // Local baseline (mean within ±window octaves), then local deviation.
    final localDev = _localDeviation(log2f, detrended,
        windowOct: policy.localBaselineWindowOctaves);

    // ── Region-grow features where |localDev| >= prominence ──────────────────
    final localFeatures = _detectRegions(
      f: f,
      log2f: log2f,
      residual: residual,
      localDev: localDev,
      policy: policy,
      warnings: warnings,
    );

    // Confidence-gate each feature's actionability, and collect blocked types.
    final blocked = <AcousticFeatureType>{};
    final features = <AcousticObservedFeature>[
      for (final feat in [...trendFeatures, ...localFeatures])
        _applyInterpretation(feat, interp, blocked),
    ];

    final nextActions = _nextActions(interp, features);
    final reasons = <String>[
      'analysed ${band.length} in-band bins; ${features.length} feature(s).',
      _interpretationReason(interp),
    ];

    return AcousticClassificationResult(
      status: AcousticClassificationStatus.ok,
      residualSummary: residualSummary,
      observedFeatures: features,
      analysisMinHz: f.first,
      analysisMaxHz: f.last,
      confidenceInterpretation: interp,
      blockedAutomaticCorrections: blocked.toList()
        ..sort((a, b) => a.index.compareTo(b.index)),
      suggestedNextActions: nextActions,
      reasons: reasons,
      warnings: warnings,
      policyId: policy.id,
      policyVersion: policy.version,
      evidenceRefs: input.evidenceRefs,
    );
  }

  // ── Confidence interpretation ──────────────────────────────────────────────

  static MeasurementConfidenceInterpretation _interpret(
      MeasurementConfidenceResult c) {
    switch (c.status) {
      case ConfidenceStatus.invalid:
        return MeasurementConfidenceInterpretation.remeasure;
      case ConfidenceStatus.insufficientEvidence:
        return MeasurementConfidenceInterpretation.analysisOnly;
      case ConfidenceStatus.valid:
        return (c.grade == ConfidenceGrade.excellent ||
                c.grade == ConfidenceGrade.good)
            ? MeasurementConfidenceInterpretation.correctableAllowed
            : MeasurementConfidenceInterpretation.conservative;
    }
  }

  static String _interpretationReason(MeasurementConfidenceInterpretation i) =>
      switch (i) {
        MeasurementConfidenceInterpretation.correctableAllowed =>
          'measurement confidence sufficient for correction candidates.',
        MeasurementConfidenceInterpretation.conservative =>
          'usable/poor confidence — conservative, expert review advised.',
        MeasurementConfidenceInterpretation.analysisOnly =>
          'insufficient evidence (e.g. no repeatability) — analysis only, no automatic correction.',
        MeasurementConfidenceInterpretation.remeasure =>
          'invalid measurement confidence — remeasure required.',
      };

  /// Base actionability by feature type, then downgraded by interpretation.
  static AcousticObservedFeature _applyInterpretation(
    AcousticObservedFeature f,
    MeasurementConfidenceInterpretation interp,
    Set<AcousticFeatureType> blocked,
  ) {
    var action = _baseAction(f.type);
    final warnings = [...f.warnings];

    // Tentative features never stay auto-correction candidates.
    if (f.quality == AcousticFeatureQuality.tentative &&
        (action == AcousticActionability.safePeqCutCandidate ||
            action == AcousticActionability.cautiousBroadCorrection)) {
      action = AcousticActionability.requiresExpertReview;
    }

    switch (interp) {
      case MeasurementConfidenceInterpretation.correctableAllowed:
        break;
      case MeasurementConfidenceInterpretation.conservative:
        if (action == AcousticActionability.safePeqCutCandidate) {
          action = AcousticActionability.cautiousBroadCorrection;
        }
        break;
      case MeasurementConfidenceInterpretation.analysisOnly:
        if (action == AcousticActionability.safePeqCutCandidate ||
            action == AcousticActionability.cautiousBroadCorrection) {
          action = AcousticActionability.noAutomaticCorrection;
        }
        break;
      case MeasurementConfidenceInterpretation.remeasure:
        action = AcousticActionability.remeasureRequired;
        break;
    }

    // deepNull is ALWAYS doNotBoost regardless of interpretation.
    if (f.type == AcousticFeatureType.deepNull) {
      action = AcousticActionability.doNotBoost;
    }

    if (action != AcousticActionability.safePeqCutCandidate &&
        action != AcousticActionability.cautiousBroadCorrection) {
      blocked.add(f.type);
    }

    return AcousticObservedFeature(
      featureId: f.featureId,
      type: f.type,
      startHz: f.startHz,
      centerHz: f.centerHz,
      endHz: f.endHz,
      deviationDb: f.deviationDb,
      prominenceDb: f.prominenceDb,
      bandwidthHz: f.bandwidthHz,
      bandwidthOctaves: f.bandwidthOctaves,
      estimatedQ: f.estimatedQ,
      quality: f.quality,
      actionability: action,
      reasons: f.reasons,
      warnings: warnings,
    );
  }

  static AcousticActionability _baseAction(AcousticFeatureType t) =>
      switch (t) {
        AcousticFeatureType.narrowPeak =>
          AcousticActionability.safePeqCutCandidate,
        AcousticFeatureType.broadPeak =>
          AcousticActionability.cautiousBroadCorrection,
        AcousticFeatureType.narrowDip =>
          AcousticActionability.informationalOnly,
        AcousticFeatureType.broadDip =>
          AcousticActionability.requiresExpertReview,
        AcousticFeatureType.deepNull => AcousticActionability.doNotBoost,
        AcousticFeatureType.risingTrend =>
          AcousticActionability.cautiousBroadCorrection,
        AcousticFeatureType.fallingTrend =>
          AcousticActionability.cautiousBroadCorrection,
      };

  static List<String> _nextActions(MeasurementConfidenceInterpretation interp,
      List<AcousticObservedFeature> features) {
    final out = <String>[];
    if (interp == MeasurementConfidenceInterpretation.remeasure) {
      out.add('Remeasure — current measurement confidence is invalid.');
    } else if (interp == MeasurementConfidenceInterpretation.analysisOnly) {
      out.add(
          'Collect repeated/calibrated measurements before automatic correction.');
    }
    if (features.any((f) => f.type == AcousticFeatureType.deepNull)) {
      out.add('Inspect placement/phase for the deep null(s) — do not boost.');
    }
    return out;
  }

  // ── Feature detection helpers ──────────────────────────────────────────────

  static List<AcousticObservedFeature> _detectRegions({
    required List<double> f,
    required List<double> log2f,
    required List<double> residual,
    required List<double> localDev,
    required AcousticClassificationPolicy policy,
    required List<String> warnings,
  }) {
    final n = f.length;
    // sign mask above prominence.
    final sign = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (localDev[i] >= policy.minimumProminenceDb) {
        sign[i] = 1;
      } else if (localDev[i] <= -policy.minimumProminenceDb) {
        sign[i] = -1;
      }
    }

    // Grow same-sign runs.
    final runs = <List<int>>[]; // [start, end, sign]
    var i = 0;
    while (i < n) {
      if (sign[i] == 0) {
        i++;
        continue;
      }
      final s = sign[i];
      var j = i;
      while (j + 1 < n && sign[j + 1] == s) {
        j++;
      }
      runs.add([i, j, s]);
      i = j + 1;
    }

    // Merge same-sign runs closer than the separation threshold.
    final merged = <List<int>>[];
    for (final r in runs) {
      if (merged.isNotEmpty &&
          merged.last[2] == r[2] &&
          (log2f[r[0]] - log2f[merged.last[1]]) <
              policy.minimumFeatureSeparationOctaves) {
        merged.last[1] = r[1];
      } else {
        merged.add([...r]);
      }
    }

    final features = <AcousticObservedFeature>[];
    var featureIndex = 0;
    for (final r in merged) {
      final i0 = r[0], i1 = r[1], s = r[2];
      // center = extremum of |localDev| in the run.
      var c = i0;
      for (var k = i0; k <= i1; k++) {
        if (localDev[k].abs() > localDev[c].abs()) c = k;
      }
      final bwOct = log2f[i1] - log2f[i0];
      final bwHz = f[i1] - f[i0];
      final centerHz = f[c];
      final estimatedQ = bwHz > 0 ? centerHz / bwHz : double.infinity;
      final atEdge = i0 == 0 || i1 == n - 1;
      final bins = i1 - i0 + 1;
      final tentative = atEdge || bins < policy.minimumBinsPerFeature;

      final fWarn = <String>[];
      if (atEdge) {
        fWarn.add(
            'feature touches the analysis edge — bandwidth may be clipped.');
      }
      if (bins < policy.minimumBinsPerFeature) {
        fWarn.add(
            'feature spans only $bins bin(s) — sparse, treat as tentative.');
      }

      final AcousticFeatureType type;
      if (s > 0) {
        type = bwOct <= policy.narrowFeatureMaxWidthOctaves
            ? AcousticFeatureType.narrowPeak
            : AcousticFeatureType.broadPeak;
      } else {
        final isDeepNull = residual[c] <= policy.deepNullDepthDb &&
            bwOct >= policy.deepNullMinimumWidthOctaves &&
            !atEdge;
        if (isDeepNull) {
          type = AcousticFeatureType.deepNull;
        } else {
          type = bwOct <= policy.narrowFeatureMaxWidthOctaves
              ? AcousticFeatureType.narrowDip
              : AcousticFeatureType.broadDip;
        }
      }

      features.add(AcousticObservedFeature(
        featureId: '${type.name}@${centerHz.round()}Hz#$featureIndex',
        type: type,
        startHz: f[i0],
        centerHz: centerHz,
        endHz: f[i1],
        deviationDb: residual[c],
        prominenceDb: localDev[c].abs(),
        bandwidthHz: bwHz,
        bandwidthOctaves: bwOct,
        estimatedQ: estimatedQ,
        quality: tentative
            ? AcousticFeatureQuality.tentative
            : AcousticFeatureQuality.confident,
        actionability: _baseAction(type), // refined later by interpretation
        warnings: fWarn,
      ));
      featureIndex++;
    }
    return features;
  }

  static List<double> _localDeviation(List<double> log2f, List<double> values,
      {required double windowOct}) {
    final n = values.length;
    final out = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      var sum = 0.0;
      var count = 0;
      for (var j = 0; j < n; j++) {
        if ((log2f[j] - log2f[i]).abs() <= windowOct) {
          sum += values[j];
          count++;
        }
      }
      final baseline = count == 0 ? 0.0 : sum / count;
      out[i] = values[i] - baseline;
    }
    return out;
  }

  static AcousticObservedFeature _trendFeature(
      List<double> f, double slopeDbPerOct) {
    final rising = slopeDbPerOct > 0;
    final type = rising
        ? AcousticFeatureType.risingTrend
        : AcousticFeatureType.fallingTrend;
    final bwHz = f.last - f.first;
    final bwOct = (math.log(f.last) - math.log(f.first)) / math.ln2;
    final centerHz = math.sqrt(f.first * f.last);
    return AcousticObservedFeature(
      featureId: '${type.name}@${centerHz.round()}Hz#trend',
      type: type,
      startHz: f.first,
      centerHz: centerHz,
      endHz: f.last,
      deviationDb: slopeDbPerOct * bwOct, // total tilt across the band
      prominenceDb: slopeDbPerOct.abs() * bwOct,
      bandwidthHz: bwHz,
      bandwidthOctaves: bwOct,
      estimatedQ: 0,
      quality: AcousticFeatureQuality.confident,
      actionability: _baseAction(type),
      reasons: [
        'broad ${rising ? 'rising' : 'falling'} trend '
            '${slopeDbPerOct.toStringAsFixed(2)} dB/oct across the band.'
      ],
    );
  }

  static ({double slope, double intercept}) _linearFit(
      List<double> x, List<double> y) {
    final n = x.length;
    if (n < 2) return (slope: 0, intercept: n == 0 ? 0 : y.first);
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      sx += x[i];
      sy += y[i];
      sxx += x[i] * x[i];
      sxy += x[i] * y[i];
    }
    final denom = n * sxx - sx * sx;
    if (denom == 0) return (slope: 0, intercept: sy / n);
    final slope = (n * sxy - sx * sy) / denom;
    final intercept = (sy - slope * sx) / n;
    return (slope: slope, intercept: intercept);
  }

  static ResidualSummary _summary(List<double> f, List<double> residual) {
    var sumSq = 0.0;
    var maxAbs = 0.0;
    var maxHz = f.isEmpty ? 0.0 : f.first;
    for (var i = 0; i < residual.length; i++) {
      sumSq += residual[i] * residual[i];
      if (residual[i].abs() > maxAbs) {
        maxAbs = residual[i].abs();
        maxHz = f[i];
      }
    }
    final rms = residual.isEmpty ? 0.0 : math.sqrt(sumSq / residual.length);
    return ResidualSummary(
        rmsDb: rms, maxAbsDeviationDb: maxAbs, maxAbsDeviationHz: maxHz);
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  static String? _validateStructure(AcousticClassificationInput input) {
    if (input.measurementDomain != MeasurementDomain.acousticResponse) {
      return 'classifier requires acousticResponse domain, got '
          '${input.measurementDomain.name}.';
    }
    if (input.measurementSource == MeasurementSource.importedZma) {
      return 'impedance (ZMA) measurements are not acoustic responses.';
    }
    final f = input.frequenciesHz;
    final m = input.measuredMagnitudeDb;
    final t = input.targetMagnitudeDb;
    if (f.isEmpty) return 'empty frequency grid.';
    if (m.length != f.length || t.length != f.length) {
      return 'measured/target/frequency lengths differ.';
    }
    for (var i = 0; i < f.length; i++) {
      if (!f[i].isFinite || f[i] <= 0) {
        return 'frequency[$i] must be finite and > 0.';
      }
      if (i > 0 && !(f[i] > f[i - 1])) {
        return 'frequencies must be strictly ascending (no duplicates) at $i.';
      }
      if (!m[i].isFinite || !t[i].isFinite) {
        return 'magnitude/target must be finite at $i.';
      }
    }
    return null;
  }

  static AcousticClassificationResult _terminal(
    AcousticClassificationStatus status,
    String reason,
    AcousticClassificationPolicy policy,
    MeasurementConfidenceInterpretation interp,
    List<String> evidenceRefs,
  ) =>
      AcousticClassificationResult(
        status: status,
        residualSummary: null,
        observedFeatures: const [],
        analysisMinHz: null,
        analysisMaxHz: null,
        confidenceInterpretation: interp,
        blockedAutomaticCorrections: const [],
        suggestedNextActions:
            status == AcousticClassificationStatus.invalidMeasurement
                ? const ['Remeasure — measurement is not analysable.']
                : const ['Provide more in-band measurement points.'],
        reasons: [reason],
        warnings: const [],
        policyId: policy.id,
        policyVersion: policy.version,
        evidenceRefs: evidenceRefs,
      );
}
