/// Thresholds for the Acoustic Problem Classifier, injected (never hard-coded
/// in the algorithm) so PRO / Factory / Consumer can supply their own.
///
/// EVIDENCE vs PROVISIONAL: only [minimumProminenceDb] has a real starting
/// point — the Consumer room-mode peak detector uses avg + 1.5 dB. Everything
/// else here is a CONSERVATIVE PROVISIONAL default awaiting real-measurement
/// validation; do not treat any as final, do not gate Apply on them, and do not
/// present them as production-ready.
library;

class AcousticClassificationPolicyException implements Exception {
  final String message;
  AcousticClassificationPolicyException(this.message);
  @override
  String toString() => 'AcousticClassificationPolicyException: $message';
}

class AcousticClassificationPolicy {
  final String id;
  final int version;

  /// Analysis band. Features outside are ignored.
  final double analysisMinHz;
  final double analysisMaxHz;

  /// Width (octaves) of the smoothed local baseline used to separate local
  /// features from the broad shape.
  final double localBaselineWindowOctaves;

  /// Minimum detrended prominence (dB) for a bump/dip to count as a feature.
  /// Starting point: Consumer's 1.5 dB peak threshold.
  final double minimumProminenceDb;

  /// A feature at or below this octave width is "narrow", else "broad".
  final double narrowFeatureMaxWidthOctaves;

  /// A dip whose ORIGINAL residual is at or below this depth (dB, negative) —
  /// and wide enough — is a deepNull (never boosted).
  final double deepNullDepthDb;
  final double deepNullMinimumWidthOctaves;

  /// A broad trend is only asserted over at least this span and slope.
  final double trendMinimumSpanOctaves;
  final double trendSlopeThresholdDbPerOctave;

  /// Below this many valid in-band bins, analysis is insufficient.
  final int minimumBins;

  /// A feature spanning fewer bins than this is kept but marked tentative.
  final int minimumBinsPerFeature;

  /// Same-sign features closer than this (octaves) are merged.
  final double minimumFeatureSeparationOctaves;

  const AcousticClassificationPolicy({
    required this.id,
    required this.version,
    required this.analysisMinHz,
    required this.analysisMaxHz,
    required this.localBaselineWindowOctaves,
    required this.minimumProminenceDb,
    required this.narrowFeatureMaxWidthOctaves,
    required this.deepNullDepthDb,
    required this.deepNullMinimumWidthOctaves,
    required this.trendMinimumSpanOctaves,
    required this.trendSlopeThresholdDbPerOctave,
    required this.minimumBins,
    required this.minimumBinsPerFeature,
    required this.minimumFeatureSeparationOctaves,
  });

  /// Validates ordering/positivity. Throws on a nonsensical policy.
  void validate() {
    void positive(double v, String n) {
      if (!v.isFinite || v <= 0) {
        throw AcousticClassificationPolicyException(
            '$n must be finite and > 0.');
      }
    }

    positive(analysisMinHz, 'analysisMinHz');
    positive(analysisMaxHz, 'analysisMaxHz');
    if (analysisMaxHz <= analysisMinHz) {
      throw AcousticClassificationPolicyException(
          'analysisMaxHz must exceed analysisMinHz.');
    }
    positive(localBaselineWindowOctaves, 'localBaselineWindowOctaves');
    positive(minimumProminenceDb, 'minimumProminenceDb');
    positive(narrowFeatureMaxWidthOctaves, 'narrowFeatureMaxWidthOctaves');
    if (deepNullDepthDb >= 0) {
      throw AcousticClassificationPolicyException(
          'deepNullDepthDb must be negative (a depth).');
    }
    positive(deepNullMinimumWidthOctaves, 'deepNullMinimumWidthOctaves');
    positive(trendMinimumSpanOctaves, 'trendMinimumSpanOctaves');
    positive(trendSlopeThresholdDbPerOctave, 'trendSlopeThresholdDbPerOctave');
    if (minimumBins < 2) {
      throw AcousticClassificationPolicyException('minimumBins must be >= 2.');
    }
    if (minimumBinsPerFeature < 1) {
      throw AcousticClassificationPolicyException(
          'minimumBinsPerFeature must be >= 1.');
    }
    positive(
        minimumFeatureSeparationOctaves, 'minimumFeatureSeparationOctaves');
  }

  /// PRO provisional policy. Only [minimumProminenceDb] (1.5 dB) has an
  /// evidence starting point (Consumer); every other value is PROVISIONAL and
  /// must NOT gate Apply or be shown as production-ready before real
  /// measurement validation.
  factory AcousticClassificationPolicy.proProvisional() =>
      const AcousticClassificationPolicy(
        id: 'pro_provisional',
        version: 1,
        analysisMinHz: 20, // provisional
        analysisMaxHz: 20000, // provisional
        localBaselineWindowOctaves: 1.0, // provisional
        minimumProminenceDb: 1.5, // Consumer starting point
        narrowFeatureMaxWidthOctaves: 0.33, // provisional (~1/3 octave)
        deepNullDepthDb: -10.0, // provisional
        deepNullMinimumWidthOctaves: 0.1, // provisional
        trendMinimumSpanOctaves: 2.0, // provisional
        trendSlopeThresholdDbPerOctave: 1.0, // provisional
        minimumBins: 8, // provisional
        minimumBinsPerFeature: 3, // provisional
        minimumFeatureSeparationOctaves: 0.25, // provisional
      );
}
