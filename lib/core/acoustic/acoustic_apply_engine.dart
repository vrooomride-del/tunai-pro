import '../pro_tuning_data.dart';
import 'candidate_safety.dart';

/// Acoustic Apply Engine v1 — converts [CandidateSafetyResult.verifiedCandidates]
/// into an updated [PeqChannelState] value ready for the tuning-state write path.
///
/// This layer is a pure function bridge between the acoustic engine and the
/// tuning data model. It calls [PeqChannelState.fillNextFreeSlot] for each
/// verified candidate in [applicationOrder] sequence, detecting success by
/// comparing [PeqChannelState.activeBandCount] before and after each fill.
///
/// The returned [TuningApplyResult.updatedChannel] is NOT committed to any
/// store by this layer. The caller is responsible for integrating it into
/// [TuningProjectState] and calling the appropriate persistence method.
///
/// No DSP writes, biquad coefficients, hardware addresses, transport calls,
/// or optimizer invocations are performed here.

// ── Status ────────────────────────────────────────────────────────────────────

enum TuningApplyStatus {
  /// All verified candidates were applied to the channel.
  ok,

  /// At least one candidate was applied but one or more were skipped due to
  /// insufficient free slots.
  partiallyApplied,

  /// No candidates were applied because the channel had no free slots.
  noSlotAvailable,

  /// [CandidateSafetyResult.applyPermitted] was false; no changes were made.
  notPermitted,
}

// ── Band records ─────────────────────────────────────────────────────────────

/// Audit record for a candidate that was successfully applied to a PEQ slot.
class AppliedBand {
  final String candidateId;
  final String featureId;

  /// Observed feature centre frequency used as the PEQ centre (Hz).
  /// Not a DSP register address.
  final double frequencyHz;

  /// Applied gain (dB ≤ 0). Cut only.
  final double gainDb;

  final double q;

  /// 1-based position in the apply sequence, from [SelectedCandidate.applicationOrder].
  final int applicationOrder;

  const AppliedBand({
    required this.candidateId,
    required this.featureId,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.applicationOrder,
  });

  Map<String, dynamic> toJson() => {
        'candidateId': candidateId,
        'featureId': featureId,
        'frequencyHz': frequencyHz,
        'gainDb': gainDb,
        'q': q,
        'applicationOrder': applicationOrder,
      };
}

/// Audit record for a candidate that could not be applied due to a full channel.
class SkippedBand {
  final String candidateId;
  final String featureId;
  final int applicationOrder;
  final String reason;

  const SkippedBand({
    required this.candidateId,
    required this.featureId,
    required this.applicationOrder,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'candidateId': candidateId,
        'featureId': featureId,
        'applicationOrder': applicationOrder,
        'reason': reason,
      };
}

// ── Result ────────────────────────────────────────────────────────────────────

/// The full outcome of one apply pass over a [CandidateSafetyResult].
///
/// [updatedChannel] is the new [PeqChannelState] with verified candidates
/// filled in. When [status] is [TuningApplyStatus.notPermitted] it equals
/// the input channel unchanged.
class TuningApplyResult {
  final TuningApplyStatus status;

  /// Updated channel ready for [TuningProjectState.copyWith].
  /// NOT yet persisted — the caller must call [updateTuningState].
  final PeqChannelState updatedChannel;

  /// Candidates successfully applied, in [applicationOrder] order.
  final List<AppliedBand> applied;

  /// Candidates not applied because no free slot was available.
  final List<SkippedBand> skipped;

  /// Channel identifier from the input [PeqChannelState].
  final String channelId;

  final String safetyPolicyId;
  final int safetyPolicyVersion;

  /// Evidence references propagated from the upstream [CandidateSafetyResult].
  final List<String> evidenceRefs;

  final List<String> reasons;

  /// Optional deterministic full-system alignment selected before PEQ.
  final TuningProjectState? alignedTuningState;

  const TuningApplyResult({
    required this.status,
    required this.updatedChannel,
    required this.applied,
    required this.skipped,
    required this.channelId,
    required this.safetyPolicyId,
    required this.safetyPolicyVersion,
    required this.evidenceRefs,
    required this.reasons,
    this.alignedTuningState,
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'channelId': channelId,
        'appliedCount': applied.length,
        'skippedCount': skipped.length,
        'applied': [for (final b in applied) b.toJson()],
        'skipped': [for (final b in skipped) b.toJson()],
        'safetyPolicyId': safetyPolicyId,
        'safetyPolicyVersion': safetyPolicyVersion,
        'evidenceRefs': evidenceRefs,
        'reasons': reasons,
      };
}

// ── Engine ────────────────────────────────────────────────────────────────────

abstract final class AcousticApplyEngine {
  /// Apply [safetyResult.verifiedCandidates] to [channel] in
  /// [applicationOrder] sequence.
  ///
  /// Returns a [TuningApplyResult] describing what was applied and the
  /// updated [PeqChannelState]. Pure and deterministic.
  /// [maxSlotCount], when provided, caps automatic slot allocation to
  /// indices `0..maxSlotCount-1` (e.g. a hardware target's write-verified
  /// band count) — see [PeqChannelState.fillNextFreeSlot]. Pre-existing
  /// bands beyond the cap are never modified or removed; candidates that
  /// cannot find a free slot within the cap are recorded as skipped.
  static TuningApplyResult apply(
    CandidateSafetyResult safetyResult,
    PeqChannelState channel, {
    int? maxSlotCount,
  }) {
    // Safety gate: block if not permitted.
    if (!safetyResult.applyPermitted) {
      return TuningApplyResult(
        status: TuningApplyStatus.notPermitted,
        updatedChannel: channel,
        applied: const [],
        skipped: const [],
        channelId: channel.channelId,
        safetyPolicyId: safetyResult.policyId,
        safetyPolicyVersion: safetyResult.policyVersion,
        evidenceRefs: safetyResult.evidenceRefs,
        reasons: ['apply not permitted — safety gate blocked.'],
      );
    }

    // Sort by applicationOrder for deterministic fill sequence.
    final sorted = [...safetyResult.verifiedCandidates]
      ..sort((a, b) => a.applicationOrder.compareTo(b.applicationOrder));

    // Nothing to apply.
    if (sorted.isEmpty) {
      return TuningApplyResult(
        status: TuningApplyStatus.ok,
        updatedChannel: channel,
        applied: const [],
        skipped: const [],
        channelId: channel.channelId,
        safetyPolicyId: safetyResult.policyId,
        safetyPolicyVersion: safetyResult.policyVersion,
        evidenceRefs: safetyResult.evidenceRefs,
        reasons: ['0 candidates to apply.'],
      );
    }

    var ch = channel;
    final applied = <AppliedBand>[];
    final skipped = <SkippedBand>[];

    for (final sel in sorted) {
      final c = sel.scoredCandidate.candidate;
      final before = ch.activeBandCount;

      ch = ch.fillNextFreeSlot(
        type: PeqBandType.peak,
        frequencyHz: c.frequencyHz,
        gainDb: c.gainDb,
        q: c.q,
        maxSlotCount: maxSlotCount,
      );

      if (ch.activeBandCount > before) {
        applied.add(AppliedBand(
          candidateId: c.candidateId,
          featureId: c.featureId,
          frequencyHz: c.frequencyHz,
          gainDb: c.gainDb,
          q: c.q,
          applicationOrder: sel.applicationOrder,
        ));
      } else {
        skipped.add(SkippedBand(
          candidateId: c.candidateId,
          featureId: c.featureId,
          applicationOrder: sel.applicationOrder,
          reason: maxSlotCount != null
              ? 'no deployable slot available in channel '
                  '${channel.channelId} within the write-verified '
                  '$maxSlotCount-band limit.'
              : 'no free slot available in channel ${channel.channelId}.',
        ));
      }
    }

    final TuningApplyStatus status;
    if (applied.isEmpty) {
      status = TuningApplyStatus.noSlotAvailable;
    } else if (skipped.isNotEmpty) {
      status = TuningApplyStatus.partiallyApplied;
    } else {
      status = TuningApplyStatus.ok;
    }

    return TuningApplyResult(
      status: status,
      updatedChannel: ch,
      applied: applied,
      skipped: skipped,
      channelId: channel.channelId,
      safetyPolicyId: safetyResult.policyId,
      safetyPolicyVersion: safetyResult.policyVersion,
      evidenceRefs: safetyResult.evidenceRefs,
      reasons: [
        '${applied.length} of ${sorted.length} candidate(s) applied '
            'to channel ${channel.channelId}.',
      ],
    );
  }
}
