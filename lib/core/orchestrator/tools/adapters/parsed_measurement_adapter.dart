import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../acoustic/measurement_confidence.dart';
import '../../../acoustic/measurement_evidence.dart';
import '../../../pro_acoustic_data.dart'
    show
        FrdSweepEntry,
        MeasurementParseResult,
        MeasurementParseStatus;
import '../../../pro_measurement_parser.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_execution.dart';
import '../pro_tool_registry.dart';
import 'frd_grid_aligner.dart';

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
/// When [DriverChannel.additionalFrdSweeps] is non-empty, those raw FRD entries
/// are parsed, numerically deduplicated, and grid-aligned via [FrdGridAligner].
/// If at least two distinct sweeps survive, the evidence includes
/// [EvidenceMetric.repeatability] as available and the confidence engine sees
/// real multi-sweep spectra — yielding [ConfidenceStatus.good] or better and
/// enabling candidate generation.
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

    // Build primary sweep arrays.
    final points = frdData.points;
    final freqs = [for (final p in points) p.frequencyHz];
    final mags = [for (final p in points) p.magnitudeDb ?? double.nan];

    // Try multi-sweep alignment when additional sweeps are stored.
    // Evidence always marks repeatability unavailable (ImportedMeasurementEvidence
    // invariant). The aligned spectraDb is passed to the confidence engine
    // independently — it computes repeatability from the data, not from evidence.
    final aligned = driver.additionalFrdSweeps.isNotEmpty
        ? _buildAlignedSpectra(freqs, mags, driver.additionalFrdSweeps)
        : null;

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

    MeasurementConfidenceResult confidence;
    try {
      final List<double> confFreqs;
      final List<List<double>> confSpectra;
      if (aligned != null) {
        confFreqs = aligned.frequencies;
        confSpectra = aligned.spectraDb;
      } else {
        confFreqs = freqs;
        confSpectra = [mags];
      }
      confidence = MeasurementConfidenceEngine.evaluate(
        MeasurementConfidenceMetrics(
          frequencies: confFreqs,
          spectraDb: confSpectra,
          minBandHz: confFreqs.isEmpty ? 1 : confFreqs.first,
          maxBandHz: confFreqs.isEmpty ? 2 : confFreqs.last,
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

  /// Parses and aligns [additionalSweeps] with the primary sweep.
  ///
  /// Uses the same numeric fingerprint deduplication as
  /// [MeasurementAnalyzeAdapter]: sweeps are considered identical when their
  /// (freq, mag) pairs round to the same integer Hz / 0.001 dB values.
  ///
  /// Returns null when fewer than 2 distinct valid sweeps survive alignment.
  static ({List<double> frequencies, List<List<double>> spectraDb})?
      _buildAlignedSpectra(
    List<double> primaryFreqs,
    List<double> primaryMags,
    List<FrdSweepEntry> additionalSweeps,
  ) {
    final seenNumeric = <String>{_numericFingerprint(primaryFreqs, primaryMags)};
    final sweepList = <({List<double> freqs, List<double> mags})>[
      (freqs: primaryFreqs, mags: primaryMags),
    ];

    for (final entry in additionalSweeps) {
      final parsed = ProMeasurementParser.parseFrd(
        fileName: entry.fileName,
        content: entry.content,
      );
      if (parsed.status == MeasurementParseStatus.failed) continue;
      final pts = parsed.data?.points ?? const [];
      final aFreqs = [for (final p in pts) p.frequencyHz];
      final aMags = [for (final p in pts) p.magnitudeDb ?? double.nan];
      if (aFreqs.isEmpty) continue;

      final fp = _numericFingerprint(aFreqs, aMags);
      if (seenNumeric.contains(fp)) continue;
      seenNumeric.add(fp);
      sweepList.add((freqs: aFreqs, mags: aMags));
    }

    if (sweepList.length < 2) return null;
    return FrdGridAligner.align(sweepList);
  }

  /// Canonical numeric fingerprint: sorted (freq_int:mag_int) SHA-256.
  /// Tolerance: ±0.5 Hz, ±0.0005 dB.
  static String _numericFingerprint(List<double> freqs, List<double> mags) {
    final n = freqs.length < mags.length ? freqs.length : mags.length;
    final idx = List.generate(n, (i) => i)
      ..sort((a, b) => freqs[a].compareTo(freqs[b]));
    final parts = [
      for (final i in idx) '${freqs[i].round()}:${(mags[i] * 1000).round()}',
    ];
    return sha256.convert(utf8.encode(parts.join('|'))).toString();
  }
}
