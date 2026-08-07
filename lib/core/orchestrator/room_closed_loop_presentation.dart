// ── TUNAI PRO Phase 3-D3C-3 §0 — Closed Loop verdict presentation ───────────
//
// ONE typed mapping from CorrectionCycleDecision to how the verdict must be
// PRESENTED. The verdict itself is never reinterpreted here — this file has
// no thresholds, no metrics and no access to the evaluator; it only decides
// tone, copy and whether the rollback path applies.
//
// Widgets must render what this returns and must never branch on
// `decision.name` or match strings: a green check on a `worsened` verdict is
// exactly the class of bug this mapping exists to make impossible.

library;

import '../pro_correction_cycle.dart';

/// How strongly a verdict should read. Deliberately three levels, not a
/// boolean: "improved but measure again" is neither a completion nor a
/// problem, and must not borrow either one's styling.
enum ClosedLoopVerdictTone {
  /// The correction is done and measurably better.
  success,

  /// Genuinely positive, but the workflow is NOT finished. Must never use
  /// the success styling or any "완료" wording.
  followUp,

  /// Something is wrong with the result — worse, or not trustworthy.
  /// Never green, never a check icon.
  caution,
}

ClosedLoopVerdictTone closedLoopVerdictTone(CorrectionCycleDecision d) =>
    switch (d) {
      CorrectionCycleDecision.improvedAndComplete =>
        ClosedLoopVerdictTone.success,
      CorrectionCycleDecision.improvedNeedsAnotherCycle ||
      CorrectionCycleDecision.noMeaningfulImprovement =>
        ClosedLoopVerdictTone.followUp,
      CorrectionCycleDecision.worsened ||
      CorrectionCycleDecision.insufficientEvidence ||
      CorrectionCycleDecision.wrongProjectOrChannel =>
        ClosedLoopVerdictTone.caution,
    };

String closedLoopVerdictText(CorrectionCycleDecision d) => switch (d) {
      CorrectionCycleDecision.improvedAndComplete =>
        'Room 보정 완료 — 측정 결과가 개선되었습니다.',
      CorrectionCycleDecision.improvedNeedsAnotherCycle =>
        '개선되었습니다 — 한 번 더 보정하면 더 좋아질 수 있습니다.',
      CorrectionCycleDecision.noMeaningfulImprovement =>
        '의미 있는 변화가 감지되지 않았습니다.',
      CorrectionCycleDecision.worsened =>
        '성능 저하가 감지되었습니다 — 보정 전 상태로 되돌릴 수 있습니다.',
      CorrectionCycleDecision.insufficientEvidence =>
        '판정에 필요한 측정 근거가 부족합니다 — 다시 측정해 주세요.',
      CorrectionCycleDecision.wrongProjectOrChannel =>
        'Before와 After가 서로 다른 대상에서 측정되었습니다.',
    };

/// Only a worsened correction has something to roll back to. Every other
/// verdict — including the untrustworthy ones — leaves the deployed
/// correction in place, so offering rollback there would be misleading.
bool closedLoopVerdictOffersRollback(CorrectionCycleDecision d) =>
    d == CorrectionCycleDecision.worsened;
