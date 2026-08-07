// Phase 2 — Stereo Room Measurement closed loop.
//
// Reuses CorrectionCycleEvaluator (the same evaluator
// ProGuidedAiController.submitAfterFrd already uses for a single channel,
// see pro_guided_ai_controller.dart lines 639-712) once per side, then
// combines Left+Right into one overall decision. No new evaluator, no new
// verdict math — CorrectionCycleDecision is the existing contract.
//
// Evaluates exactly once, only when both Before and After snapshots are
// 2/2 complete. 1/2 always returns null (no evaluation, no partial verdict).

import '../frd_parser.dart' show FrdPoint;
import '../pro_acoustic_data.dart' show ParsedMeasurementData;
import '../pro_correction_cycle.dart'
    show CorrectionCycleDecision, CorrectionCycleMetrics;
import '../room_measurement_data.dart';
import 'correction_cycle_evaluator.dart';

class RoomSideEvaluation {
  final RoomSystemSide side;
  final CorrectionCycleDecision decision;
  final CorrectionCycleMetrics? metrics;
  final List<String> reasons;

  const RoomSideEvaluation({
    required this.side,
    required this.decision,
    required this.metrics,
    required this.reasons,
  });
}

class RoomClosedLoopResult {
  final CorrectionCycleDecision decision;
  final RoomSideEvaluation left;
  final RoomSideEvaluation right;

  const RoomClosedLoopResult({
    required this.decision,
    required this.left,
    required this.right,
  });

  List<String> get reasons => [...left.reasons, ...right.reasons];
}

/// Severity order, most severe first. The combined decision is whichever
/// side's decision is more severe — both sides must independently reach
/// [CorrectionCycleDecision.improvedAndComplete] for the combined result to
/// be complete.
const List<CorrectionCycleDecision> _severityOrder = [
  CorrectionCycleDecision.worsened,
  CorrectionCycleDecision.wrongProjectOrChannel,
  CorrectionCycleDecision.insufficientEvidence,
  CorrectionCycleDecision.noMeaningfulImprovement,
  CorrectionCycleDecision.improvedNeedsAnotherCycle,
  CorrectionCycleDecision.improvedAndComplete,
];

abstract final class RoomClosedLoopEvaluator {
  /// Evaluates the Room closed loop for [projectId]. Returns null (no
  /// evaluation performed) unless BOTH [before] and [after] are 2/2
  /// complete — this is the single gate that prevents evaluating at 1/2 and
  /// prevents evaluating twice for the same complete pair (callers must only
  /// invoke this once per transition into 2/2; see
  /// RoomMeasurementController.accept()).
  ///
  /// Rejects (returns null) if any of the four measurements' projectId
  /// doesn't match, or if a non-null cycleId is supplied and any
  /// measurement's cycleId disagrees with it.
  static RoomClosedLoopResult? evaluate({
    required String projectId,
    required RoomMeasurementSnapshot before,
    required RoomMeasurementSnapshot after,
    String? cycleId,
  }) {
    if (!before.isComplete || !after.isComplete) return null;

    final measurements = [
      before.leftSystemFrd!,
      before.rightSystemFrd!,
      after.leftSystemFrd!,
      after.rightSystemFrd!,
    ];
    for (final m in measurements) {
      if (m.projectId != projectId) return null;
      if (cycleId != null && m.cycleId != null && m.cycleId != cycleId) {
        return null;
      }
    }

    final left = _evaluateSide(
      projectId: projectId,
      side: RoomSystemSide.left,
      before: before.leftSystemFrd!,
      after: after.leftSystemFrd!,
    );
    final right = _evaluateSide(
      projectId: projectId,
      side: RoomSystemSide.right,
      before: before.rightSystemFrd!,
      after: after.rightSystemFrd!,
    );

    final combined = _severityOrder.firstWhere(
      (d) => d == left.decision || d == right.decision,
      orElse: () => CorrectionCycleDecision.noMeaningfulImprovement,
    );

    return RoomClosedLoopResult(decision: combined, left: left, right: right);
  }

  static RoomSideEvaluation _evaluateSide({
    required String projectId,
    required RoomSystemSide side,
    required RoomSystemMeasurement before,
    required RoomSystemMeasurement after,
  }) {
    final input = CorrectionCycleEvalInput(
      projectId: projectId,
      channelId: 'room_${side.name}_system',
      beforeFrd: _toFrdPoints(before.frd),
      beforeMeasurementRef: before.frd.id,
      afterFrd: _toFrdPoints(after.frd),
      afterMeasurementRef: after.frd.id,
      afterMeasurementFileName: after.frd.sourceFileName,
    );
    final result = CorrectionCycleEvaluator.evaluate(
      input,
      CorrectionCyclePolicy.proProvisional(),
    );
    return RoomSideEvaluation(
      side: side,
      decision: result.decision,
      metrics: result.metrics,
      reasons: result.reasons,
    );
  }

  static List<FrdPoint> _toFrdPoints(ParsedMeasurementData data) => [
        for (final p in data.points)
          if (p.magnitudeDb != null)
            FrdPoint(
              frequency: p.frequencyHz,
              spl: p.magnitudeDb!,
              phase: p.phaseDeg ?? 0.0,
            ),
      ];
}
