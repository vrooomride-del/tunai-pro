import 'dart:math' as math;
import 'candidate_scoring.dart';

/// Candidate Optimizer v1 — deterministically selects from [ScoredCandidateSet]
/// candidates that survive grade, band-budget, and frequency-clustering filters.
///
/// This layer is purely a selection gate. It reads [ScoredCandidate] fields
/// already available from the scorer and produces an [OptimizedSelection].
/// No FRD simulation, no DSP application, no biquad coefficients, no hardware
/// commands, and no legacy optimizer calls are made here.
///
/// Selection algorithm (applied in rank order, rank 1 first):
///   1. Grade threshold  — reject if grade rank is worse than minimumGrade.
///   2. Band budget      — reject if selected count ≥ maxNewBands.
///   3. Frequency spacing — reject if |log2(f_candidate) − log2(f_selected)|
///                          < minFrequencySpacingOctaves for any selected band.
///   4. Otherwise select; applicationOrder = selected.length (1-based).
///
/// Same inputs always produce the same output (deterministic).

// ── Policy ────────────────────────────────────────────────────────────────────

class OptimizerPolicyException implements Exception {
  final String message;
  OptimizerPolicyException(this.message);
  @override
  String toString() => 'OptimizerPolicyException: $message';
}

/// Thresholds that govern optimizer candidate selection.
/// Carries no DSP address, hardware value, or biquad coefficient.
class OptimizerPolicy {
  final String id;
  final int version;

  /// Maximum number of new PEQ bands the optimizer may select.
  final int maxNewBands;

  /// Minimum [CandidateScoreGrade] a candidate must achieve to be selected.
  /// Candidates graded worse than this are rejected with [OptimizationRejectionReason.gradeThreshold].
  final CandidateScoreGrade minimumGrade;

  /// Minimum octave spacing between any two selected band centre frequencies.
  /// Candidates too close to an already-selected band are rejected with
  /// [OptimizationRejectionReason.frequencyClustering].
  final double minFrequencySpacingOctaves;

  const OptimizerPolicy({
    required this.id,
    required this.version,
    required this.maxNewBands,
    required this.minimumGrade,
    required this.minFrequencySpacingOctaves,
  });

  void validate() {
    if (id.isEmpty) {
      throw OptimizerPolicyException('id must not be empty.');
    }
    if (version < 1) {
      throw OptimizerPolicyException('version must be >= 1.');
    }
    if (maxNewBands < 1) {
      throw OptimizerPolicyException('maxNewBands must be >= 1.');
    }
    if (!minFrequencySpacingOctaves.isFinite || minFrequencySpacingOctaves < 0) {
      throw OptimizerPolicyException(
          'minFrequencySpacingOctaves must be finite and >= 0.');
    }
  }

  /// PRO provisional optimizer policy.
  factory OptimizerPolicy.proProvisional() => const OptimizerPolicy(
        id: 'pro_provisional',
        version: 1,
        maxNewBands: 3,
        minimumGrade: CandidateScoreGrade.marginal,
        minFrequencySpacingOctaves: 0.5,
      );
}

// ── Status / reason enums ────────────────────────────────────────────────────

enum OptimizationStatus {
  /// At least one candidate was selected.
  ok,

  /// Optimizer ran but all candidates were filtered out.
  nothingSelected,

  /// Upstream [ScoredCandidateSetStatus] was not processable; no selection
  /// was attempted.
  propagated,
}

enum OptimizationRejectionReason {
  /// Candidate grade is worse than [OptimizerPolicy.minimumGrade].
  gradeThreshold,

  /// Band budget ([OptimizerPolicy.maxNewBands]) already exhausted.
  bandBudgetExceeded,

  /// Candidate centre frequency is too close to an already-selected band.
  frequencyClustering,
}

// ── Output models ─────────────────────────────────────────────────────────────

/// A [ScoredCandidate] that was admitted by the optimizer.
class SelectedCandidate {
  final ScoredCandidate scoredCandidate;

  /// 1-based order in which this band should be applied to the DSP channel.
  final int applicationOrder;

  /// Human-readable rationale for selection; no DSP semantics.
  final String selectionReason;

  const SelectedCandidate({
    required this.scoredCandidate,
    required this.applicationOrder,
    required this.selectionReason,
  });

  Map<String, dynamic> toJson() => {
        'candidateId': scoredCandidate.candidate.candidateId,
        'featureId': scoredCandidate.candidate.featureId,
        'featureType': scoredCandidate.candidate.featureType.name,
        'frequencyHz': scoredCandidate.candidate.frequencyHz,
        'gainDb': scoredCandidate.candidate.gainDb,
        'q': scoredCandidate.candidate.q,
        'intent': scoredCandidate.candidate.intent.name,
        'compositeScore': scoredCandidate.compositeScore,
        'grade': scoredCandidate.grade.name,
        'rank': scoredCandidate.rank,
        'applicationOrder': applicationOrder,
        'selectionReason': selectionReason,
      };
}

/// A [ScoredCandidate] that was rejected by the optimizer, and why.
class RejectedEntry {
  final ScoredCandidate scoredCandidate;
  final OptimizationRejectionReason rejectionReason;
  final String detail;

  const RejectedEntry({
    required this.scoredCandidate,
    required this.rejectionReason,
    required this.detail,
  });

  Map<String, dynamic> toJson() => {
        'candidateId': scoredCandidate.candidate.candidateId,
        'featureId': scoredCandidate.candidate.featureId,
        'rejectionReason': rejectionReason.name,
        'detail': detail,
      };
}

/// The full result of one optimizer selection pass.
class OptimizedSelection {
  final OptimizationStatus status;

  /// Selected candidates in [applicationOrder] order (1 first).
  final List<SelectedCandidate> selected;

  /// Candidates that were examined but not selected, in rank order.
  final List<RejectedEntry> rejected;

  final List<String> reasons;
  final String policyId;
  final int policyVersion;

  /// Evidence references propagated from the upstream [ScoredCandidateSet].
  final List<String> evidenceRefs;

  const OptimizedSelection({
    required this.status,
    required this.selected,
    required this.rejected,
    required this.reasons,
    required this.policyId,
    required this.policyVersion,
    required this.evidenceRefs,
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'selected': [for (final s in selected) s.toJson()],
        'rejected': [for (final r in rejected) r.toJson()],
        'reasons': reasons,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'evidenceRefs': evidenceRefs,
      };
}

// ── Optimizer ─────────────────────────────────────────────────────────────────

abstract final class CandidateOptimizer {
  /// Select candidates from [scoredSet] according to [policy].
  ///
  /// Iterates [ScoredCandidateSet.scoredCandidates] in rank order and applies
  /// four sequential filters. Pure and deterministic.
  static OptimizedSelection select(
    ScoredCandidateSet scoredSet,
    OptimizerPolicy policy,
  ) {
    policy.validate();

    // Propagate non-processable upstream statuses immediately.
    if (scoredSet.status == ScoredCandidateSetStatus.noCorrectableDirectives ||
        scoredSet.status == ScoredCandidateSetStatus.insufficientEvidence ||
        scoredSet.status == ScoredCandidateSetStatus.invalidPlan) {
      return OptimizedSelection(
        status: OptimizationStatus.propagated,
        selected: const [],
        rejected: const [],
        reasons: [
          'scored set status ${scoredSet.status.name} — no selection attempted.',
        ],
        policyId: policy.id,
        policyVersion: policy.version,
        evidenceRefs: scoredSet.evidenceRefs,
      );
    }

    // Process ScoredCandidateSetStatus.ok and .allRejected.
    final selected = <SelectedCandidate>[];
    final rejected = <RejectedEntry>[];

    for (final sc in scoredSet.scoredCandidates) {
      // 1. Grade threshold.
      if (sc.grade.index > policy.minimumGrade.index) {
        rejected.add(RejectedEntry(
          scoredCandidate: sc,
          rejectionReason: OptimizationRejectionReason.gradeThreshold,
          detail: 'grade ${sc.grade.name} is worse than '
              'minimumGrade ${policy.minimumGrade.name}.',
        ));
        continue;
      }

      // 2. Band budget.
      if (selected.length >= policy.maxNewBands) {
        rejected.add(RejectedEntry(
          scoredCandidate: sc,
          rejectionReason: OptimizationRejectionReason.bandBudgetExceeded,
          detail: 'band budget of ${policy.maxNewBands} already exhausted.',
        ));
        continue;
      }

      // 3. Frequency clustering — check against every already-selected band.
      String? clusterDetail;
      for (final sel in selected) {
        final spacing = _spacingOctaves(
          sc.candidate.frequencyHz,
          sel.scoredCandidate.candidate.frequencyHz,
        );
        if (spacing < policy.minFrequencySpacingOctaves) {
          clusterDetail =
              '${spacing.toStringAsFixed(2)} oct from '
              '${sel.scoredCandidate.candidate.featureId}'
              '@${sel.scoredCandidate.candidate.frequencyHz.round()}Hz '
              '(min ${policy.minFrequencySpacingOctaves} oct).';
          break;
        }
      }
      if (clusterDetail != null) {
        rejected.add(RejectedEntry(
          scoredCandidate: sc,
          rejectionReason: OptimizationRejectionReason.frequencyClustering,
          detail: clusterDetail,
        ));
        continue;
      }

      // 4. Select.
      selected.add(SelectedCandidate(
        scoredCandidate: sc,
        applicationOrder: selected.length + 1,
        selectionReason: 'rank ${sc.rank}, grade ${sc.grade.name}, '
            'score ${sc.compositeScore.toStringAsFixed(1)}.',
      ));
    }

    final status =
        selected.isEmpty ? OptimizationStatus.nothingSelected : OptimizationStatus.ok;

    return OptimizedSelection(
      status: status,
      selected: selected,
      rejected: rejected,
      reasons: [
        '${selected.length} of ${scoredSet.scoredCandidates.length} '
            'candidate(s) selected.',
      ],
      policyId: policy.id,
      policyVersion: policy.version,
      evidenceRefs: scoredSet.evidenceRefs,
    );
  }

  /// Octave distance between two centre frequencies.
  static double _spacingOctaves(double f1, double f2) {
    if (f1 <= 0 || f2 <= 0) return double.infinity;
    return (math.log(f1) - math.log(f2)).abs() / math.ln2;
  }
}
