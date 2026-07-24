/// Policy for turning an [AcousticClassificationResult] into a Correction Plan.
///
/// The classifier already folded measurement confidence into each feature's
/// actionability, so this policy only tunes REVIEW behaviour — how strict the
/// plan is about flagging things for a human. It holds no DSP value and no
/// acoustic threshold (those live in the classification policy).
///
/// Both toggles here are CONSERVATIVE PROVISIONAL defaults; do not gate Apply
/// on them or present them as production-ready before real validation.
library;

class CorrectionPolicyException implements Exception {
  final String message;
  CorrectionPolicyException(this.message);
  @override
  String toString() => 'CorrectionPolicyException: $message';
}

class CorrectionPolicy {
  final String id;
  final int version;

  /// A tentative-quality feature that would otherwise be correctable is instead
  /// flagged for manual review. PROVISIONAL (default true — cautious).
  final bool treatTentativeAsManualReview;

  /// A broad-shape correction (from cautiousBroadCorrection) is flagged for
  /// manual review rather than auto-correctable. PROVISIONAL (default false).
  final bool treatBroadCorrectionAsManualReview;

  const CorrectionPolicy({
    required this.id,
    required this.version,
    required this.treatTentativeAsManualReview,
    required this.treatBroadCorrectionAsManualReview,
  });

  void validate() {
    if (id.isEmpty) {
      throw CorrectionPolicyException('id must not be empty.');
    }
    if (version < 1) {
      throw CorrectionPolicyException('version must be >= 1.');
    }
  }

  /// PRO provisional review policy. Cautious by default: tentative features go
  /// to manual review; broad corrections remain (auto-)correctable.
  factory CorrectionPolicy.proProvisional() => const CorrectionPolicy(
        id: 'pro_provisional',
        version: 1,
        treatTentativeAsManualReview: true,
        treatBroadCorrectionAsManualReview: false,
      );
}
