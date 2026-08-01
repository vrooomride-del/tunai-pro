import 'acoustic_problem_classifier.dart';
import 'candidate_optimizer.dart';

/// Candidate Safety v1 — apply-permission gate between [OptimizedSelection]
/// and the tuning-state write path ([PeqChannelState.fillNextFreeSlot]).
///
/// Responsibilities:
///   - Per-candidate invariant checks (no boost, cut depth, frequency range,
///     deepNull guard)
///   - Selection-level band-budget check (selected.length ≤ availableSlots)
///   - Upstream-status propagation (nothingSelected / propagated → blocked)
///
/// [applyPermitted] is true only when every check passes. On failure
/// [verifiedCandidates] is empty so callers cannot reach the write path
/// by accident.
///
/// This layer produces no DSP addresses, biquad coefficients, register
/// payloads, hardware commands, optimizer calls, or scoring changes.

// ── Policy ────────────────────────────────────────────────────────────────────

class CandidateSafetyPolicyException implements Exception {
  final String message;
  CandidateSafetyPolicyException(this.message);
  @override
  String toString() => 'CandidateSafetyPolicyException: $message';
}

/// Numerical thresholds that govern the safety validation pass.
/// Carries no DSP address, hardware value, or biquad coefficient.
class CandidateSafetyPolicy {
  final String id;
  final int version;

  /// Maximum allowed cut magnitude (dB, positive value).
  /// Candidates with |gainDb| > maxCutDb are rejected with [cutTooDeep].
  final double maxCutDb;

  /// Device-specific gain envelope; shared defaults remain unchanged.
  final double minGainDb;
  final double maxGainDb;

  /// Lower bound of the valid frequency range (Hz, inclusive).
  final double minFrequencyHz;

  /// Upper bound of the valid frequency range (Hz, inclusive).
  final double maxFrequencyHz;

  /// Maximum number of bands this validator will approve in one selection.
  /// Typically equal to [PeqChannelState.bandCount] minus already-used slots.
  final int availableSlots;

  const CandidateSafetyPolicy({
    required this.id,
    required this.version,
    required this.maxCutDb,
    this.minGainDb = double.negativeInfinity,
    this.maxGainDb = 0.0,
    required this.minFrequencyHz,
    required this.maxFrequencyHz,
    required this.availableSlots,
  });

  CandidateSafetyPolicy copyWith({double? maxCutDb}) => CandidateSafetyPolicy(
        id: id,
        version: version,
        maxCutDb: maxCutDb ?? this.maxCutDb,
        minGainDb: minGainDb,
        maxGainDb: maxGainDb,
        minFrequencyHz: minFrequencyHz,
        maxFrequencyHz: maxFrequencyHz,
        availableSlots: availableSlots,
      );

  void validate() {
    if (id.isEmpty) {
      throw CandidateSafetyPolicyException('id must not be empty.');
    }
    if (version < 1) {
      throw CandidateSafetyPolicyException('version must be >= 1.');
    }
    if (!maxCutDb.isFinite || maxCutDb <= 0) {
      throw CandidateSafetyPolicyException('maxCutDb must be finite and > 0.');
    }
    if (minGainDb.isNaN || maxGainDb.isNaN || minGainDb > maxGainDb) {
      throw CandidateSafetyPolicyException(
          'gain envelope must have minGainDb <= maxGainDb.');
    }
    if (!minFrequencyHz.isFinite || minFrequencyHz <= 0) {
      throw CandidateSafetyPolicyException(
          'minFrequencyHz must be finite and > 0.');
    }
    if (!maxFrequencyHz.isFinite || maxFrequencyHz <= minFrequencyHz) {
      throw CandidateSafetyPolicyException(
          'maxFrequencyHz must be finite and > minFrequencyHz.');
    }
    if (availableSlots < 1) {
      throw CandidateSafetyPolicyException('availableSlots must be >= 1.');
    }
  }

  /// PRO provisional safety policy.
  /// maxCutDb matches [CandidatePolicy.proProvisional]; frequency range spans
  /// the full audible band; slots align with [PeqChannelState.bandCount].
  factory CandidateSafetyPolicy.proProvisional() => const CandidateSafetyPolicy(
        id: 'pro_provisional',
        version: 1,
        maxCutDb: 9.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 10,
      );

  factory CandidateSafetyPolicy.adau1701Icp5() => const CandidateSafetyPolicy(
        id: 'adau1701_icp5',
        version: 1,
        maxCutDb: 6.0,
        minGainDb: -6.0,
        maxGainDb: 3.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 10,
      );
}

// ── Violation ─────────────────────────────────────────────────────────────────

/// Reason codes for blocking issues. All codes are blocking in v1 (no
/// warning-only severity yet).
enum CandidateSafetyViolationCode {
  /// gainDb > 0: acoustic engine must never produce a boost. Hard guard.
  noBoostGuard,

  /// |gainDb| > maxCutDb: cut magnitude exceeds the safety ceiling.
  cutTooDeep,

  /// Candidate gain is outside the target device envelope.
  gainOutOfRange,

  /// frequencyHz < minFrequencyHz or > maxFrequencyHz.
  frequencyOutOfRange,

  /// featureType == deepNull: generation must never produce a deepNull candidate.
  deepNullGuard,

  /// selected.length > availableSlots: would overflow the DSP band budget.
  bandBudgetExceeded,

  /// Upstream [OptimizationStatus] is not [OptimizationStatus.ok]; no
  /// candidates are available for application.
  propagatedStatus,
}

/// A single blocking safety issue found during validation.
class CandidateSafetyIssue {
  final CandidateSafetyViolationCode code;

  /// Non-null when the issue is tied to a specific candidate.
  final String? candidateId;

  final String detail;

  const CandidateSafetyIssue({
    required this.code,
    this.candidateId,
    required this.detail,
  });

  Map<String, dynamic> toJson() => {
        'code': code.name,
        if (candidateId != null) 'candidateId': candidateId,
        'detail': detail,
      };
}

// ── Result ────────────────────────────────────────────────────────────────────

/// The outcome of one safety validation pass over an [OptimizedSelection].
class CandidateSafetyResult {
  /// True only when every per-candidate and selection-level check passes.
  final bool applyPermitted;

  /// All detected blocking issues, in inspection order.
  final List<CandidateSafetyIssue> issues;

  /// The candidates cleared for downstream apply.
  /// Equals [OptimizedSelection.selected] when [applyPermitted] is true,
  /// and is empty when [applyPermitted] is false.
  final List<SelectedCandidate> verifiedCandidates;

  final String policyId;
  final int policyVersion;

  /// Evidence references propagated from the upstream [OptimizedSelection].
  final List<String> evidenceRefs;

  const CandidateSafetyResult({
    required this.applyPermitted,
    required this.issues,
    required this.verifiedCandidates,
    required this.policyId,
    required this.policyVersion,
    required this.evidenceRefs,
  });

  Map<String, dynamic> toJson() => {
        'applyPermitted': applyPermitted,
        'issues': [for (final i in issues) i.toJson()],
        'verifiedCandidates': [for (final c in verifiedCandidates) c.toJson()],
        'policyId': policyId,
        'policyVersion': policyVersion,
        'evidenceRefs': evidenceRefs,
      };
}

// ── Validator ─────────────────────────────────────────────────────────────────

abstract final class AcousticSelectionValidator {
  /// Validate [selection] against [policy] and return a [CandidateSafetyResult].
  ///
  /// Pure and deterministic: same inputs always produce the same output.
  /// Never writes to DSP, tuning state, or hardware.
  static CandidateSafetyResult validate(
    OptimizedSelection selection,
    CandidateSafetyPolicy policy,
  ) {
    policy.validate();

    // Non-ok upstream status → block immediately, skip per-candidate checks.
    if (selection.status != OptimizationStatus.ok) {
      return CandidateSafetyResult(
        applyPermitted: false,
        issues: [
          CandidateSafetyIssue(
            code: CandidateSafetyViolationCode.propagatedStatus,
            detail: 'optimization status ${selection.status.name} — '
                'no candidates available for application.',
          ),
        ],
        verifiedCandidates: const [],
        policyId: policy.id,
        policyVersion: policy.version,
        evidenceRefs: selection.evidenceRefs,
      );
    }

    final issues = <CandidateSafetyIssue>[];

    // Per-candidate checks.
    for (final sel in selection.selected) {
      final c = sel.scoredCandidate.candidate;

      // 1. No boost — gainDb must be ≤ 0.
      if (c.gainDb > policy.maxGainDb ||
          (c.gainDb > 0 && policy.maxGainDb <= 0)) {
        issues.add(CandidateSafetyIssue(
          code: policy.maxGainDb > 0 && c.gainDb > policy.maxGainDb
              ? CandidateSafetyViolationCode.gainOutOfRange
              : CandidateSafetyViolationCode.noBoostGuard,
          candidateId: c.candidateId,
          detail: 'gainDb ${c.gainDb.toStringAsFixed(2)} dB is positive — '
              'the acoustic engine must never produce a boost.',
        ));
      }

      // 2. Cut depth ceiling.
      if (c.gainDb < policy.minGainDb || c.gainDb < -policy.maxCutDb) {
        issues.add(CandidateSafetyIssue(
          code: CandidateSafetyViolationCode.cutTooDeep,
          candidateId: c.candidateId,
          detail: 'gainDb ${c.gainDb.toStringAsFixed(2)} dB exceeds '
              'maxCutDb limit of −${policy.maxCutDb.toStringAsFixed(1)} dB.',
        ));
      }

      // 3. Frequency range.
      if (c.frequencyHz < policy.minFrequencyHz ||
          c.frequencyHz > policy.maxFrequencyHz) {
        issues.add(CandidateSafetyIssue(
          code: CandidateSafetyViolationCode.frequencyOutOfRange,
          candidateId: c.candidateId,
          detail: 'frequencyHz ${c.frequencyHz.toStringAsFixed(1)} Hz is '
              'outside valid range '
              '[${policy.minFrequencyHz.toStringAsFixed(1)}, '
              '${policy.maxFrequencyHz.toStringAsFixed(1)}] Hz.',
        ));
      }

      // 4. deepNull hard guard.
      if (c.featureType == AcousticFeatureType.deepNull) {
        issues.add(CandidateSafetyIssue(
          code: CandidateSafetyViolationCode.deepNullGuard,
          candidateId: c.candidateId,
          detail: 'featureType deepNull — '
              'candidate generation for deepNull is always prohibited.',
        ));
      }
    }

    // Selection-level: band budget.
    if (selection.selected.length > policy.availableSlots) {
      issues.add(CandidateSafetyIssue(
        code: CandidateSafetyViolationCode.bandBudgetExceeded,
        detail: '${selection.selected.length} selected candidates exceed '
            'availableSlots limit of ${policy.availableSlots}.',
      ));
    }

    final applyPermitted = issues.isEmpty;

    return CandidateSafetyResult(
      applyPermitted: applyPermitted,
      issues: issues,
      verifiedCandidates: applyPermitted ? selection.selected : const [],
      policyId: policy.id,
      policyVersion: policy.version,
      evidenceRefs: selection.evidenceRefs,
    );
  }
}
