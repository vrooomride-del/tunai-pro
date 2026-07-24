import '../../../acoustic/acoustic_classification_policy.dart';
import '../../../acoustic/acoustic_problem_classifier.dart';
import '../../../acoustic/measurement_evidence.dart' show MeasurementDomain;
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_execution.dart';
import '../pro_tool_registry.dart';

/// `acousticClassify` → [AcousticProblemClassifier.classify].
///
/// Resolves a [MeasurementArtifact] (produced by a prior `measurementAnalyze`
/// step) from the step's single inputRef. Converts its parsed FRD points to
/// an [AcousticClassificationInput] with a flat-zero target (deviation from
/// flat response), and calls the pure classifier with the proProvisional
/// policy. Stores the result as a [ClassificationArtifact]; the Cloud-facing
/// result carries only the outputRef.
///
/// Read-only: no DSP value, biquad, gain/Q/address, or hardware command is
/// generated. [AcousticApplyEngine] is deliberately not called from here.
class AcousticClassifyAdapter implements ProToolAdapter {
  const AcousticClassifyAdapter();

  @override
  ProOrchestratorToolId get toolId => ProOrchestratorToolId.acousticClassify;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final ref = singleInputRef(step);
    final artifact =
        ctx.store.getTyped<MeasurementArtifact>(ctx.projectId, ref);

    // Gate 1: domain — classifier is acoustic-response only.
    if (artifact.evidence.domain != MeasurementDomain.acousticResponse) {
      throw ProToolException(
        ProToolFailureCode.typeMismatch,
        'acousticClassify requires an acousticResponse measurement, '
        'got ${artifact.evidence.domain.name}. '
        'Run measurementAnalyze on an FRD file.',
      );
    }

    // Gate 2: confidence must have been evaluated (FRD path always evaluates).
    final confidence = artifact.confidence;
    if (confidence == null) {
      throw ProToolException(
        ProToolFailureCode.confidenceCalculationFailure,
        'MeasurementArtifact has no confidence result '
        '(evaluation: ${artifact.evaluation.name}) — '
        'acousticClassify requires a FRD measurement with evaluated confidence.',
      );
    }

    // Build frequency / magnitude arrays from the parsed FRD points.
    final points = artifact.parse.data?.points ?? const [];
    final freqs = [for (final p in points) p.frequencyHz];
    final magnitudes = [
      for (final p in points) p.magnitudeDb ?? double.nan
    ];

    // Flat-zero target: classifier computes deviation from flat response.
    final target = List<double>.filled(freqs.length, 0.0);

    final input = AcousticClassificationInput(
      frequenciesHz: freqs,
      measuredMagnitudeDb: magnitudes,
      targetMagnitudeDb: target,
      measurementConfidence: confidence,
      measurementSource: artifact.evidence.source,
      measurementDomain: artifact.evidence.domain,
      evidenceRefs: [artifact.evidence.evidenceId],
    );

    final result = AcousticProblemClassifier.classify(
      input,
      AcousticClassificationPolicy.proProvisional(),
    );

    ctx.store
        .put(ctx.projectId, step.outputRef, ClassificationArtifact(result));

    return referenceResult(
      step,
      confidence: _toolConfidence(result),
      summary: '${result.observedFeatures.length} feature(s); '
          'status=${result.status.name}.',
    );
  }

  ProConfidence _toolConfidence(AcousticClassificationResult r) =>
      switch (r.status) {
        AcousticClassificationStatus.ok => ProConfidence.high,
        AcousticClassificationStatus.insufficientEvidence => ProConfidence.low,
        AcousticClassificationStatus.invalidMeasurement => ProConfidence.low,
      };
}
