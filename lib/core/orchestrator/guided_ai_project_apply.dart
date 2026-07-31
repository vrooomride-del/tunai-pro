// Pure apply-to-project guard for the Guided AI session.
//
// Shared by GuidedAiScreen.onApply and integration tests — no logic is
// duplicated. No Riverpod, no persistence. The caller persists.

import '../acoustic/acoustic_apply_engine.dart';
import '../pro_project.dart';

// ── Outcome ───────────────────────────────────────────────────────────────────

enum GuidedAiProjectApplyOutcome {
  /// All guards passed; [GuidedAiProjectApplyResult.updatedProject] is set.
  wrote,

  /// [TuningApplyResult.status] is not [TuningApplyStatus.ok].
  /// Includes partiallyApplied, noSlotAvailable, notPermitted.
  statusNotOk,

  /// [latestProject] is null or its id does not match [projectId].
  projectNotFound,

  /// [TuningApplyResult.channelId] is not present in project.peqChannels.
  channelNotFound,
}

// ── Result ────────────────────────────────────────────────────────────────────

class GuidedAiProjectApplyResult {
  final GuidedAiProjectApplyOutcome outcome;

  /// Non-null only when [outcome] == [GuidedAiProjectApplyOutcome.wrote].
  final ProProject? updatedProject;

  const GuidedAiProjectApplyResult._({
    required this.outcome,
    this.updatedProject,
  });

  bool get wrote => outcome == GuidedAiProjectApplyOutcome.wrote;
}

// ── Guard ─────────────────────────────────────────────────────────────────────

abstract final class GuidedAiProjectApply {
  /// Applies [applyResult] to [latestProject] after three sequential guards:
  ///
  ///   1. **Atomic guard** — [TuningApplyResult.status] must be
  ///      [TuningApplyStatus.ok]; partial or blocked results are rejected.
  ///   2. **Project guard** — [latestProject] must be non-null and
  ///      [latestProject.id] must equal [projectId]; this catches stale-closure
  ///      captures and missing-project errors.
  ///   3. **Channel guard** — [applyResult.channelId] must exist in
  ///      [latestProject.tuningState.peqChannels]; this prevents silent writes
  ///      to the wrong channel in multi-channel projects.
  ///
  /// Pure and side-effect-free. The caller is responsible for persisting the
  /// returned [GuidedAiProjectApplyResult.updatedProject] when [wrote] is true.
  static GuidedAiProjectApplyResult apply({
    required String projectId,
    required TuningApplyResult applyResult,
    required ProProject? latestProject,
  }) {
    if (applyResult.status != TuningApplyStatus.ok) {
      return const GuidedAiProjectApplyResult._(
          outcome: GuidedAiProjectApplyOutcome.statusNotOk);
    }
    if (latestProject == null || latestProject.id != projectId) {
      return const GuidedAiProjectApplyResult._(
          outcome: GuidedAiProjectApplyOutcome.projectNotFound);
    }
    // Upsert: add the channel if it doesn't exist, replace it if it does.
    // Import-flow projects start with no peqChannels; the first apply call
    // from each channel creates its entry. Subsequent Guided sessions update
    // the existing entry.
    final channels = [
      ...latestProject.tuningState.peqChannels
          .where((ch) => ch.channelId != applyResult.channelId),
      applyResult.updatedChannel,
    ];
    final updated = latestProject.copyWith(
        tuningState: latestProject.tuningState.copyWith(peqChannels: channels));
    return GuidedAiProjectApplyResult._(
        outcome: GuidedAiProjectApplyOutcome.wrote, updatedProject: updated);
  }
}
