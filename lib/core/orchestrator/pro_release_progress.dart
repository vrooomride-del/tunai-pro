// Pro release-flow progress — a single, pure read model over EXISTING
// provider/store state. Not a new state store: nothing here is persisted,
// nothing here decides anything: it only classifies the already-live state
// of ProProject + ProGuidedAiState + the shared hardware-write-result
// provider + live After-measurement progress into one linear stage enum,
// so the UI has one place to ask "where is this project in the release
// flow" instead of re-deriving it ad hoc in three different tabs.
//
// Deliberately conservative: a stage is only reported once its real
// evidence exists (frdReadiness, an actual ProGuidedAiState, an actual
// HardwareWriteExecutionResult). No stage is inferred or guessed.

import '../acoustic/closed_loop_evaluator.dart' show ImprovementVerdict;
import '../deploy/pro_hardware_write_executor.dart'
    show HardwareWriteExecutionResult;
import '../pro_project.dart';
import 'pro_guided_ai_controller.dart';
import 'pro_guided_ai_state.dart';

enum ReleaseStage {
  /// No project open, or the project has no configured channels at all.
  noProject,

  /// Fewer than the required channels have parsed FRD.
  measuring,

  /// All required channels have FRD — Auto PEQ / Guided AI can start.
  frdReady,

  /// Guided AI is running and has produced candidates awaiting the user's
  /// explicit confirm/cancel.
  awaitingApproval,

  /// User approved; a HardwareWritePlan exists but hardware has not
  /// actually been written yet (still needs Deploy tab's own
  /// approve+apply gate).
  deployReady,

  /// HardwareWriteExecutor actually wrote to the DSP and every op
  /// succeeded (written or ack-only).
  applied,

  /// After mode is available and at least one (but not all) required
  /// channels have been captured/imported.
  afterInProgress,

  /// All required channels' After data collected; CorrectionCycleEvaluator
  /// has produced a decision.
  closedLoopComplete,
}

class ReleaseProgress {
  final ReleaseStage stage;
  final FrdReadiness frdReadiness;
  final int afterReadyCount;
  final HardwareWriteExecutionResult? lastHardwareWrite;
  final ImprovementVerdict? loopVerdict;

  const ReleaseProgress({
    required this.stage,
    required this.frdReadiness,
    required this.afterReadyCount,
    required this.lastHardwareWrite,
    required this.loopVerdict,
  });

  static ReleaseProgress compute({
    required ProProject? project,
    required ProGuidedAiState guidedAiState,
    required HardwareWriteExecutionResult? lastHardwareWrite,
    required int afterAcceptedCount,
  }) {
    if (project == null || project.acousticState.driverChannels.isEmpty) {
      return ReleaseProgress(
        stage: ReleaseStage.noProject,
        frdReadiness:
            const FrdReadiness(requiredChannelIds: [], missingChannels: []),
        afterReadyCount: 0,
        lastHardwareWrite: lastHardwareWrite,
        loopVerdict: null,
      );
    }

    final readiness = ProGuidedAiController.frdReadiness(project);
    final requiredCount = readiness.requiredChannelIds.length;

    if (!readiness.isFullyReady) {
      return ReleaseProgress(
        stage: ReleaseStage.measuring,
        frdReadiness: readiness,
        afterReadyCount: 0,
        lastHardwareWrite: lastHardwareWrite,
        loopVerdict: null,
      );
    }

    if (guidedAiState is ProGuidedAiConfirmPending) {
      return ReleaseProgress(
        stage: ReleaseStage.awaitingApproval,
        frdReadiness: readiness,
        afterReadyCount: 0,
        lastHardwareWrite: lastHardwareWrite,
        loopVerdict: null,
      );
    }

    if (guidedAiState is ProGuidedAiCompleted) {
      final applied = lastHardwareWrite?.allWritten == true;
      if (applied) {
        if (guidedAiState.loopPhase == ProClosedLoopPhase.cycleComplete) {
          return ReleaseProgress(
            stage: ReleaseStage.closedLoopComplete,
            frdReadiness: readiness,
            afterReadyCount: requiredCount,
            lastHardwareWrite: lastHardwareWrite,
            loopVerdict: guidedAiState.loopVerdict,
          );
        }
        if (afterAcceptedCount > 0 && afterAcceptedCount < requiredCount) {
          return ReleaseProgress(
            stage: ReleaseStage.afterInProgress,
            frdReadiness: readiness,
            afterReadyCount: afterAcceptedCount,
            lastHardwareWrite: lastHardwareWrite,
            loopVerdict: guidedAiState.loopVerdict,
          );
        }
        return ReleaseProgress(
          stage: ReleaseStage.applied,
          frdReadiness: readiness,
          afterReadyCount: afterAcceptedCount,
          lastHardwareWrite: lastHardwareWrite,
          loopVerdict: guidedAiState.loopVerdict,
        );
      }
      if (guidedAiState.hardwareWritePlan != null) {
        return ReleaseProgress(
          stage: ReleaseStage.deployReady,
          frdReadiness: readiness,
          afterReadyCount: 0,
          lastHardwareWrite: lastHardwareWrite,
          loopVerdict: null,
        );
      }
    }

    return ReleaseProgress(
      stage: ReleaseStage.frdReady,
      frdReadiness: readiness,
      afterReadyCount: 0,
      lastHardwareWrite: lastHardwareWrite,
      loopVerdict: null,
    );
  }

  String label({bool ko = true}) => switch (stage) {
        ReleaseStage.noProject => ko ? '프로젝트 없음' : 'No project',
        ReleaseStage.measuring => ko
            ? 'FRD ${frdReadiness.readyCount}/${frdReadiness.requiredChannelIds.length}'
            : 'FRD ${frdReadiness.readyCount}/${frdReadiness.requiredChannelIds.length}',
        ReleaseStage.frdReady => ko ? 'Auto PEQ 준비됨' : 'Auto PEQ ready',
        ReleaseStage.awaitingApproval => ko ? '승인 대기' : 'Awaiting approval',
        ReleaseStage.deployReady => ko ? 'Deploy 준비됨' : 'Deploy ready',
        ReleaseStage.applied => ko ? '적용 완료' : 'Applied',
        ReleaseStage.afterInProgress =>
          'After $afterReadyCount/${frdReadiness.requiredChannelIds.length}',
        ReleaseStage.closedLoopComplete =>
          ko ? 'Closed Loop 완료' : 'Closed Loop complete',
      };
}
