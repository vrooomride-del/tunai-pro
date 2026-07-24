import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../acoustic/measurement_confidence.dart';
import '../../../acoustic/measurement_evidence.dart';
import '../../../pro_acoustic_data.dart'
    show MeasurementParseResult, MeasurementParseStatus;
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_execution.dart';
import '../pro_tool_registry.dart';

/// `measurementAnalyze` adapter for projects where raw FRD text is unavailable.
///
/// [MeasurementAnalyzeAdapter] requires raw text content via
/// [ProToolReferenceResolver.resolveMeasurementSource], which
/// [ProProjectResolver] throws on. This adapter skips the parse step entirely:
/// it calls [resolveMeasurementProjectState] and reads the already-parsed
/// [ParsedMeasurementData] from the [DriverChannel] whose id matches the step's
/// inputRef. The produced [MeasurementArtifact] is identical in shape, so
/// [AcousticClassifyAdapter] consumes it without modification.
///
/// The inputRef in the orchestrator step must be a [DriverChannel.id] that
/// exists in the project and carries a non-null [frdData].
class ParsedMeasurementAdapter implements ProToolAdapter {
  const ParsedMeasurementAdapter();

  static const String _hashPrefix = 'parsed_frd_v1';
  static const String _producer = 'ParsedMeasurementAdapter';
  static const String _parserSchemaVersion = '1';

  @override
  ProOrchestratorToolId get toolId => ProOrchestratorToolId.measurementAnalyze;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final ref = singleInputRef(step);
    final state =
        ctx.resolver.resolveMeasurementProjectState(ctx.projectId, ref);

    final driver =
        state.driverChannels.where((d) => d.id == ref).firstOrNull;
    if (driver == null) {
      throw ProToolException(
        ProToolFailureCode.missingReference,
        'no driver channel "$ref" in project ${ctx.projectId}.',
      );
    }

    final frdData = driver.frdData;
    if (frdData == null) {
      throw ProToolException(
        ProToolFailureCode.missingReference,
        'driver "$ref" has no parsed FRD data in project ${ctx.projectId}.',
      );
    }

    if (!frdData.hasMagnitude) {
      throw ProToolException(
        ProToolFailureCode.missingMagnitude,
        'driver "$ref" FRD data contains no finite magnitude values.',
      );
    }

    final contentHash = sha256
        .convert(utf8.encode('$_hashPrefix|${frdData.id}'))
        .toString();
    final evidenceId = 'ev:${ctx.projectId}|$ref|$contentHash';
    final phasePresent = frdData.hasPhase;

    final provenance = MeasurementProvenance(
      producer: _producer,
      producerVersion: _parserSchemaVersion,
      sourceIdentity: frdData.sourceFileName,
      contentHash: contentHash,
      label: frdData.sourceFileName,
    );

    final ImportedMeasurementEvidence evidence;
    try {
      evidence = ImportedMeasurementEvidence(
        evidenceId: evidenceId,
        projectId: ctx.projectId,
        measurementRef: ref,
        domain: MeasurementDomain.acousticResponse,
        source: MeasurementSource.importedFrd,
        provenance: provenance,
        availableMetrics: {
          EvidenceMetric.validBandCoverage,
          if (phasePresent) EvidenceMetric.phase,
        },
        unavailableMetrics: {
          EvidenceMetric.repeatability,
          EvidenceMetric.snr,
          EvidenceMetric.clipping,
          if (!phasePresent) EvidenceMetric.phase,
        },
        displayName: frdData.sourceFileName,
        originalFormat: 'FRD',
        parserSchemaVersion: _parserSchemaVersion,
        magnitudePresent: true,
        phasePresent: phasePresent,
        impedancePresent: frdData.hasImpedance,
      );
    } on MeasurementEvidenceException catch (e) {
      throw ProToolException(
          ProToolFailureCode.evidenceConstructionFailure, e.message);
    }

    final points = frdData.points;
    MeasurementConfidenceResult confidence;
    try {
      final freqs = [for (final p in points) p.frequencyHz];
      final mags = [for (final p in points) p.magnitudeDb ?? double.nan];
      confidence = MeasurementConfidenceEngine.evaluate(
        MeasurementConfidenceMetrics(
          frequencies: freqs,
          spectraDb: [mags],
          minBandHz: freqs.isEmpty ? 1 : freqs.first,
          maxBandHz: freqs.isEmpty ? 2 : freqs.last,
        ),
        MeasurementConfidencePolicy.proProvisional(),
      );
    } catch (e) {
      throw ProToolException(
          ProToolFailureCode.confidenceCalculationFailure, e.toString());
    }

    final parsed = MeasurementParseResult(
      status: frdData.warning != null
          ? MeasurementParseStatus.parsedWithWarnings
          : MeasurementParseStatus.parsed,
      data: frdData,
      warnings: frdData.warning != null ? [frdData.warning!] : const [],
      errors: const [],
      summary:
          '${frdData.pointCount} points from "${frdData.sourceFileName}" '
          '(pre-parsed, no re-read).',
    );

    ctx.store.put(
      ctx.projectId,
      step.outputRef,
      MeasurementArtifact(
        parse: parsed,
        evidence: evidence,
        evaluation: MeasurementConfidenceEvaluation.evaluated,
        evaluationReason: '',
        confidence: confidence,
      ),
    );

    return referenceResult(
      step,
      confidence:
          frdData.warning != null ? ProConfidence.medium : ProConfidence.high,
      summary: parsed.summary,
    );
  }
}
