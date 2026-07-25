// TRUST BOUNDARY. No DSP write, no BLE, no hardware command.
//
// Converts [MeasurementArtifact] instances to [LoopMeasurementSnapshot]s and
// delegates to [AcousticClosedLoopEvaluator.evaluate].
//
// Score is computed by [ProResponseError.analyze] against a flat (0 dB)
// reference target — the result reflects absolute response flatness, making
// the before/after delta meaningful regardless of the original tuning target.
//
// Null afterArtifact = "pending" state (after measurement not yet available).
// No fake score or artificial PASS is generated.

import '../acoustic/closed_loop_evaluator.dart';
import '../acoustic/measurement_confidence.dart';
import '../pro_response_error.dart';
import 'tools/pro_tool_artifact_store.dart';

abstract final class ProClosedLoopMeasurementBridge {
  /// Converts a [MeasurementArtifact] to a [LoopMeasurementSnapshot] for
  /// before/after comparison.
  ///
  /// Score is the flatness of the response curve relative to 0 dB (flat
  /// reference). [confidenceStatus] is read from [artifact.confidence]; when
  /// no confidence was evaluated, [ConfidenceStatus.insufficientEvidence] is
  /// used — which causes [AcousticClosedLoopEvaluator] to return
  /// [ImprovementVerdict.inconclusive].
  static LoopMeasurementSnapshot snapshotFrom(
    MeasurementArtifact artifact,
    String measurementRef,
  ) {
    final data = artifact.parse.data;
    final points =
        data?.points.where((p) => p.magnitudeDb != null).toList() ?? [];

    final ResponseErrorResult scoreResult;
    if (points.isEmpty) {
      scoreResult = const ResponseErrorResult(
        rmsDb: 0.0,
        maxDeviationDb: 0.0,
        maxDeviationHz: 0.0,
        weightedRmsDb: 0.0,
        score: 0.0,
      );
    } else {
      scoreResult = ProResponseError.analyze(
        freqs: [for (final p in points) p.frequencyHz],
        responseDb: [for (final p in points) p.magnitudeDb!],
        targetDb: List.filled(points.length, 0.0),
      );
    }

    // No magnitude → confidence is insufficient regardless of artifact field.
    final confidenceStatus = points.isEmpty
        ? ConfidenceStatus.insufficientEvidence
        : (artifact.confidence?.status ?? ConfidenceStatus.insufficientEvidence);

    return LoopMeasurementSnapshot(
      measurementRef: measurementRef,
      scoreResult: scoreResult,
      confidenceStatus: confidenceStatus,
    );
  }

  /// Evaluates before/after measurement artifacts.
  ///
  /// Returns `null` (pending) when [afterArtifact] is `null` — the after
  /// measurement has not yet arrived. The caller should remain in
  /// `awaitingMeasurement` until the after data is available.
  ///
  /// Never generates a fake improvement score. The [AcousticClosedLoopEvaluator]
  /// applies the confidence gate: insufficient after-confidence → inconclusive.
  static ClosedLoopResult? evaluate({
    required MeasurementArtifact beforeArtifact,
    required String beforeRef,
    required MeasurementArtifact? afterArtifact,
    required String afterRef,
  }) {
    if (afterArtifact == null) return null;

    final before = snapshotFrom(beforeArtifact, beforeRef);
    final after = snapshotFrom(afterArtifact, afterRef);

    return AcousticClosedLoopEvaluator.evaluate(
      before,
      after,
      ClosedLoopPolicy.proProvisional(),
      evidenceRefs: [beforeRef, afterRef],
    );
  }
}
