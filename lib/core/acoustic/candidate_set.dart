import 'acoustic_problem_classifier.dart';
import 'correction_plan.dart';

/// Candidate Generation v1 — turns a [CorrectionPlan]'s correctable directives
/// into deterministic [PeqCandidate] proposals.
///
/// A candidate is a DSP-shaped proposal (frequencyHz / gainDb / q) that still
/// requires [TuneSafetyValidator] approval before any DSP write. This layer is
/// deliberately value-only: no addresses, biquad coefficients, register
/// payloads, hardware commands, optimizer calls, or scoring.
///
/// Only [CorrectionDisposition.correctable] directives produce candidates.
/// [AcousticFeatureType.deepNull] is unconditionally skipped regardless of
/// disposition. Same plan + result + policy always produces identical output.

// ── Status ───────────────────────────────────────────────────────────────────

enum CandidateSetStatus {
  /// At least one candidate was generated.
  ok,

  /// Plan was ok but no correctable directive survived all filters.
  noCorrectableDirectives,

  /// Propagated from [CorrectionPlanStatus.insufficientEvidence].
  insufficientEvidence,

  /// Propagated from any other non-ok plan status.
  invalidPlan,
}

// ── Policy ───────────────────────────────────────────────────────────────────

class CandidatePolicyException implements Exception {
  final String message;
  CandidatePolicyException(this.message);
  @override
  String toString() => 'CandidatePolicyException: $message';
}

/// Numerical bounds that govern how observation measurements are translated into
/// candidate proposals. Carries no DSP address or register payload.
class CandidatePolicy {
  final String id;
  final int version;

  /// Maximum cut magnitude a single candidate may carry (dB, positive value).
  final double maxCutDb;

  /// Q bounds applied to cut candidates derived from [AcousticObservedFeature.estimatedQ].
  final double minQ;
  final double maxQ;

  /// Fraction of observed deviation applied to the proposed gain (0 < scale ≤ 1).
  /// A value of 1.0 proposes the full measured deviation as the correction.
  final double gainScale;

  /// Fixed Q used for [CorrectionIntent.broadShape] candidates.
  final double broadQ;

  /// Candidates whose scaled gain magnitude falls below this threshold are
  /// dropped — too small to be acoustically meaningful.
  final double minimumGainDb;

  const CandidatePolicy({
    required this.id,
    required this.version,
    required this.maxCutDb,
    required this.minQ,
    required this.maxQ,
    required this.gainScale,
    required this.broadQ,
    required this.minimumGainDb,
  });

  void validate() {
    if (id.isEmpty) {
      throw CandidatePolicyException('id must not be empty.');
    }
    if (version < 1) {
      throw CandidatePolicyException('version must be >= 1.');
    }
    if (!maxCutDb.isFinite || maxCutDb <= 0) {
      throw CandidatePolicyException('maxCutDb must be finite and > 0.');
    }
    if (!minQ.isFinite || minQ <= 0) {
      throw CandidatePolicyException('minQ must be finite and > 0.');
    }
    if (!maxQ.isFinite || maxQ < minQ) {
      throw CandidatePolicyException('maxQ must be finite and >= minQ.');
    }
    if (!gainScale.isFinite || gainScale <= 0 || gainScale > 1) {
      throw CandidatePolicyException('gainScale must be in (0, 1].');
    }
    if (!broadQ.isFinite || broadQ < minQ || broadQ > maxQ) {
      throw CandidatePolicyException('broadQ must be in [minQ, maxQ].');
    }
    if (!minimumGainDb.isFinite ||
        minimumGainDb <= 0 ||
        minimumGainDb > maxCutDb) {
      throw CandidatePolicyException(
          'minimumGainDb must be in (0, maxCutDb].');
    }
  }

  /// PRO provisional policy. Conservative defaults awaiting real-world
  /// validation. Full-scale correction (gainScale = 1.0); tight Q range
  /// matches the PRO target hardware envelope.
  factory CandidatePolicy.proProvisional() => const CandidatePolicy(
        id: 'pro_provisional',
        version: 1,
        maxCutDb: 9.0,
        minQ: 0.5,
        maxQ: 10.0,
        gainScale: 1.0,
        broadQ: 1.0,
        minimumGainDb: 1.0,
      );
}

// ── Output models ─────────────────────────────────────────────────────────────

/// A single PEQ correction proposal — NOT safety-validated.
///
/// [gainDb] is always ≤ 0 (cut). [frequencyHz] is the observed feature centre
/// — an observation reference, not a DSP register value. No biquad coefficients,
/// addresses, or hardware commands appear here.
class PeqCandidate {
  /// Deterministic identifier: `'candidate:<featureId>'`.
  final String candidateId;
  final String featureId;
  final AcousticFeatureType featureType;

  /// Observed feature centre frequency (Hz). NOT a DSP frequency command.
  final double frequencyHz;

  /// Proposed gain (dB ≤ 0). Clamped to [−maxCutDb, −minimumGainDb].
  final double gainDb;

  /// Proposed Q. Clamped to [minQ, maxQ] for cuts; policy.broadQ for broad shapes.
  final double q;

  final CorrectionIntent intent;

  /// Human-readable rationale; no DSP semantics.
  final String reason;

  const PeqCandidate({
    required this.candidateId,
    required this.featureId,
    required this.featureType,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.intent,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'candidateId': candidateId,
        'featureId': featureId,
        'featureType': featureType.name,
        'frequencyHz': frequencyHz,
        'gainDb': gainDb,
        'q': q,
        'intent': intent.name,
        'reason': reason,
      };
}

/// A directive that was examined but excluded from candidate generation, and why.
class SkippedDirective {
  final String featureId;
  final AcousticFeatureType featureType;
  final CorrectionDisposition disposition;
  final String reason;

  const SkippedDirective({
    required this.featureId,
    required this.featureType,
    required this.disposition,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'featureId': featureId,
        'featureType': featureType.name,
        'disposition': disposition.name,
        'reason': reason,
      };
}

/// The full result of one candidate-generation pass.
class CandidateSet {
  final CandidateSetStatus status;
  final List<PeqCandidate> candidates;
  final List<SkippedDirective> skippedDirectives;
  final List<String> reasons;
  final String policyId;
  final int policyVersion;
  final List<String> evidenceRefs;

  const CandidateSet({
    required this.status,
    required this.candidates,
    required this.skippedDirectives,
    required this.reasons,
    required this.policyId,
    required this.policyVersion,
    required this.evidenceRefs,
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'candidates': [for (final c in candidates) c.toJson()],
        'skippedDirectives': [for (final s in skippedDirectives) s.toJson()],
        'reasons': reasons,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'evidenceRefs': evidenceRefs,
      };
}

// ── Generator ─────────────────────────────────────────────────────────────────

abstract final class CandidateGenerator {
  /// Generate a [CandidateSet] from a [CorrectionPlan] and the
  /// [AcousticClassificationResult] that produced it.
  ///
  /// [result] is required to access feature observation data
  /// ([AcousticObservedFeature.deviationDb], [estimatedQ]) that the plan's
  /// region bounds do not carry. A featureId map is built for O(1) lookup.
  static CandidateSet generate(
    CorrectionPlan plan,
    AcousticClassificationResult result,
    CandidatePolicy policy,
  ) {
    policy.validate();

    // Non-ok plan → propagate without candidates.
    if (plan.status != CorrectionPlanStatus.ok) {
      final status = plan.status == CorrectionPlanStatus.insufficientEvidence
          ? CandidateSetStatus.insufficientEvidence
          : CandidateSetStatus.invalidPlan;
      return CandidateSet(
        status: status,
        candidates: const [],
        skippedDirectives: const [],
        reasons: ['plan status ${plan.status.name} — no candidates generated.'],
        policyId: policy.id,
        policyVersion: policy.version,
        evidenceRefs: plan.evidenceRefs,
      );
    }

    // Build featureId → feature map for observation data lookup.
    final featureMap = <String, AcousticObservedFeature>{
      for (final f in result.observedFeatures) f.featureId: f,
    };

    final candidates = <PeqCandidate>[];
    final skipped = <SkippedDirective>[];

    for (final directive in plan.directives) {
      // deepNull: unconditional guard. The classifier and planner already block
      // these, but generation must never produce a deepNull candidate regardless
      // of what any upstream layer encoded in the directive.
      if (directive.featureType == AcousticFeatureType.deepNull) {
        skipped.add(SkippedDirective(
          featureId: directive.featureId,
          featureType: directive.featureType,
          disposition: directive.disposition,
          reason: 'deepNull — candidate generation is always prohibited.',
        ));
        continue;
      }

      // Only correctable directives produce candidates.
      if (directive.disposition != CorrectionDisposition.correctable) {
        skipped.add(SkippedDirective(
          featureId: directive.featureId,
          featureType: directive.featureType,
          disposition: directive.disposition,
          reason: 'disposition ${directive.disposition.name} — not correctable.',
        ));
        continue;
      }

      // intent=none with correctable should not occur from CorrectionPlanner,
      // but guard defensively so generation is always deterministic.
      if (directive.intent == CorrectionIntent.none) {
        skipped.add(SkippedDirective(
          featureId: directive.featureId,
          featureType: directive.featureType,
          disposition: directive.disposition,
          reason: 'intent is none — no candidate shape defined.',
        ));
        continue;
      }

      // Feature must appear in the paired classification result.
      final feature = featureMap[directive.featureId];
      if (feature == null) {
        skipped.add(SkippedDirective(
          featureId: directive.featureId,
          featureType: directive.featureType,
          disposition: directive.disposition,
          reason:
              'feature "${directive.featureId}" not found in classification result.',
        ));
        continue;
      }

      final candidate = _buildCandidate(directive, feature, policy);
      if (candidate == null) {
        // Gain after scaling fell below minimumGainDb.
        skipped.add(SkippedDirective(
          featureId: directive.featureId,
          featureType: directive.featureType,
          disposition: directive.disposition,
          reason:
              'deviation × gainScale (${(feature.deviationDb.abs() * policy.gainScale).toStringAsFixed(2)} dB) '
              'below minimumGainDb (${policy.minimumGainDb}).',
        ));
        continue;
      }
      candidates.add(candidate);
    }

    final status = candidates.isEmpty
        ? CandidateSetStatus.noCorrectableDirectives
        : CandidateSetStatus.ok;

    return CandidateSet(
      status: status,
      candidates: candidates,
      skippedDirectives: skipped,
      reasons: [
        '${candidates.length} candidate(s) from ${plan.directives.length} directive(s).',
      ],
      policyId: policy.id,
      policyVersion: policy.version,
      evidenceRefs: plan.evidenceRefs,
    );
  }

  /// Returns null when the scaled gain falls below [policy.minimumGainDb].
  static PeqCandidate? _buildCandidate(
    CorrectionDirective directive,
    AcousticObservedFeature feature,
    CandidatePolicy policy,
  ) {
    final rawMagnitude = feature.deviationDb.abs() * policy.gainScale;
    if (rawMagnitude < policy.minimumGainDb) return null;

    // gainDb is always a cut (negative). Clamped within policy bounds.
    final gainDb =
        -(rawMagnitude.clamp(policy.minimumGainDb, policy.maxCutDb));

    // broadShape uses a fixed wide Q; narrow cuts clamp from measured estimatedQ.
    final double q = directive.intent == CorrectionIntent.broadShape
        ? policy.broadQ
        : feature.estimatedQ.clamp(policy.minQ, policy.maxQ).toDouble();

    return PeqCandidate(
      candidateId: 'candidate:${directive.featureId}',
      featureId: directive.featureId,
      featureType: directive.featureType,
      frequencyHz: feature.centerHz,
      gainDb: gainDb,
      q: q,
      intent: directive.intent,
      reason:
          'from ${directive.disposition.name} directive, ${directive.intent.name} intent.',
    );
  }
}
