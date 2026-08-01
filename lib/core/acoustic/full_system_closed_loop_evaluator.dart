import '../pro_correction_cycle.dart';
import '../pro_project.dart';
import '../pro_tuning_data.dart';
import 'full_system_candidate_evaluator.dart';

class FullSystemNextCycleDraft {
  final int cycleNumber;
  final ProProject beforeProject;
  final bool alignmentReevaluationAllowed;
  final bool requiresUserApproval;

  const FullSystemNextCycleDraft({
    required this.cycleNumber,
    required this.beforeProject,
    required this.alignmentReevaluationAllowed,
    this.requiresUserApproval = true,
  });
}

class FullSystemClosedLoopEvaluation {
  final CorrectionCycleDecision decision;
  final double beforeWeightedRmsDb;
  final double afterWeightedRmsDb;
  final double improvementDb;
  final bool approved;
  final bool converged;
  final bool rollbackSuggested;
  final TuningProjectState? rollbackTuningState;
  final FullSystemNextCycleDraft? nextCycle;
  final FullSystemSummationMode mode;
  final List<String> evidenceRefs;
  final List<String> reasons;

  const FullSystemClosedLoopEvaluation({
    required this.decision,
    required this.beforeWeightedRmsDb,
    required this.afterWeightedRmsDb,
    required this.improvementDb,
    required this.approved,
    required this.converged,
    required this.rollbackSuggested,
    required this.rollbackTuningState,
    required this.nextCycle,
    required this.mode,
    required this.evidenceRefs,
    required this.reasons,
  });
}

abstract final class FullSystemClosedLoopEvaluator {
  static const maxCycles = 3;
  static const minimumImprovementDb = 0.25;
  static const regressionThresholdDb = 0.10;
  static const completeRmsDb = 1.0;

  static FullSystemClosedLoopEvaluation evaluate({
    required ProProject beforeProject,
    required ProProject afterProject,
    required TuningProjectState previousTuningState,
    required TuningProjectState deployedTuningState,
    required int cycleNumber,
    required bool safetyPassed,
    required Map<String, String> beforeEvidenceRefs,
    required Map<String, String> afterEvidenceRefs,
  }) {
    final evidence = <String>[
      for (final id in FullSystemCandidateEvaluator.requiredChannelIds)
        if (beforeEvidenceRefs[id] != null) beforeEvidenceRefs[id]!,
      for (final id in FullSystemCandidateEvaluator.requiredChannelIds)
        if (afterEvidenceRefs[id] != null) afterEvidenceRefs[id]!,
    ];
    final completeEvidence = FullSystemCandidateEvaluator.requiredChannelIds
            .every(beforeEvidenceRefs.containsKey) &&
        FullSystemCandidateEvaluator.requiredChannelIds
            .every(afterEvidenceRefs.containsKey);
    final before = completeEvidence
        ? FullSystemCandidateEvaluator.measure(
            project: beforeProject, applyTuning: false)
        : null;
    final after = completeEvidence
        ? FullSystemCandidateEvaluator.measure(
            project: afterProject, applyTuning: false)
        : null;
    if (before == null || after == null || cycleNumber < 1) {
      return FullSystemClosedLoopEvaluation(
        decision: CorrectionCycleDecision.insufficientEvidence,
        beforeWeightedRmsDb: before?.weightedRmsDb ?? double.infinity,
        afterWeightedRmsDb: after?.weightedRmsDb ?? double.infinity,
        improvementDb: 0,
        approved: false,
        converged: false,
        rollbackSuggested: false,
        rollbackTuningState: null,
        nextCycle: null,
        mode: after?.mode ?? FullSystemSummationMode.magnitudeOnly,
        evidenceRefs: List.unmodifiable(evidence),
        reasons: const ['all four Before and After FRD channels are required.'],
      );
    }

    final improvement = before.weightedRmsDb - after.weightedRmsDb;
    if (!safetyPassed) {
      return FullSystemClosedLoopEvaluation(
        decision: CorrectionCycleDecision.insufficientEvidence,
        beforeWeightedRmsDb: before.weightedRmsDb,
        afterWeightedRmsDb: after.weightedRmsDb,
        improvementDb: improvement,
        approved: false,
        converged: false,
        rollbackSuggested: false,
        rollbackTuningState: null,
        nextCycle: null,
        mode: after.mode,
        evidenceRefs: List.unmodifiable(evidence),
        reasons: const [
          'Safety must pass before a measured result is approved.'
        ],
      );
    }

    if (improvement < -regressionThresholdDb) {
      return FullSystemClosedLoopEvaluation(
        decision: CorrectionCycleDecision.worsened,
        beforeWeightedRmsDb: before.weightedRmsDb,
        afterWeightedRmsDb: after.weightedRmsDb,
        improvementDb: improvement,
        approved: false,
        converged: false,
        rollbackSuggested: true,
        rollbackTuningState: previousTuningState,
        nextCycle: null,
        mode: after.mode,
        evidenceRefs: List.unmodifiable(evidence),
        reasons: const [
          'composite weighted RMS worsened; rollback is proposed.'
        ],
      );
    }

    if (improvement < minimumImprovementDb) {
      return FullSystemClosedLoopEvaluation(
        decision: CorrectionCycleDecision.noMeaningfulImprovement,
        beforeWeightedRmsDb: before.weightedRmsDb,
        afterWeightedRmsDb: after.weightedRmsDb,
        improvementDb: improvement,
        approved: true,
        converged: true,
        rollbackSuggested: false,
        rollbackTuningState: null,
        nextCycle: null,
        mode: after.mode,
        evidenceRefs: List.unmodifiable(evidence),
        reasons: const ['improvement is below the convergence threshold.'],
      );
    }

    final maxReached = cycleNumber >= maxCycles;
    final complete = after.weightedRmsDb <= completeRmsDb || maxReached;
    return FullSystemClosedLoopEvaluation(
      decision: complete
          ? CorrectionCycleDecision.improvedAndComplete
          : CorrectionCycleDecision.improvedNeedsAnotherCycle,
      beforeWeightedRmsDb: before.weightedRmsDb,
      afterWeightedRmsDb: after.weightedRmsDb,
      improvementDb: improvement,
      approved: true,
      converged: complete,
      rollbackSuggested: false,
      rollbackTuningState: null,
      nextCycle: complete
          ? null
          : FullSystemNextCycleDraft(
              cycleNumber: cycleNumber + 1,
              beforeProject:
                  afterProject.copyWith(tuningState: deployedTuningState),
              alignmentReevaluationAllowed:
                  after.mode == FullSystemSummationMode.phaseAware,
            ),
      mode: after.mode,
      evidenceRefs: List.unmodifiable(evidence),
      reasons: [
        if (maxReached)
          'maximum of three correction cycles reached.'
        else
          'measured result approved.',
      ],
    );
  }
}
