import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../acoustic/measurement_confidence.dart';
import '../../../acoustic/measurement_evidence.dart';
import '../../../pro_acoustic_data.dart'
    show AcousticFileType, FrdSweepEntry, MeasurementParseResult, MeasurementParseStatus;
import 'frd_grid_aligner.dart';
import '../../../pro_measurement_parser.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_execution.dart';
import '../pro_tool_registry.dart';

/// `measurementAnalyze` → [ProMeasurementParser] (+ evidence + FRD confidence).
///
/// One resolve, ONE parse, then locally: build [ImportedMeasurementEvidence],
/// and — for FRD (acoustic) only — compute a [MeasurementConfidenceResult].
/// ZMA (impedance) is recorded as `unsupportedDomain` (the acoustic confidence
/// engine is never run on it, no placeholder score). Everything (parse,
/// evidence, confidence, evaluation) is stored in one [MeasurementArtifact] at
/// the step's outputRef; the Cloud-facing result carries only references.
class MeasurementAnalyzeAdapter implements ProToolAdapter {
  /// Number of synthetic sweep copies placed in [spectraDb].
  ///
  /// Production default is 1 (a single imported FRD). Set to ≥2 only in
  /// tests that need to satisfy the [proProvisional] repeatability requirement
  /// without a real multi-sweep measurement session.
  @visibleForTesting
  final int sweepCount;

  const MeasurementAnalyzeAdapter({this.sweepCount = 1});

  /// Version prefix for the import content hash. Deliberately distinct from the
  /// enclosure hash prefix — this identifies an original measurement FILE by its
  /// content, nothing else.
  static const String contentHashPrefix = 'measurement_import_content_v1';

  static const String _producer = 'ProMeasurementParser';
  static const String _parserSchemaVersion = '1';

  @override
  ProOrchestratorToolId get toolId => ProOrchestratorToolId.measurementAnalyze;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final ref = singleInputRef(step);
    final source = ctx.resolver.resolveMeasurementSource(ctx.projectId, ref);

    // ── One parse of the original content ────────────────────────────────────
    final parsed = switch (source.format) {
      AcousticFileType.frd => ProMeasurementParser.parseFrd(
          fileName: source.fileName, content: source.content),
      AcousticFileType.zma => ProMeasurementParser.parseZma(
          fileName: source.fileName, content: source.content),
      _ => throw ProToolException(
          ProToolFailureCode.unknownFormat,
          'measurementAnalyze supports FRD/ZMA only, got '
          '${source.format.name}.'),
    };
    if (parsed.status == MeasurementParseStatus.failed) {
      throw ProToolException(ProToolFailureCode.parseFailure,
          'parse failed: ${parsed.errors.join('; ')}');
    }

    // Content-only hash (never the filename/path).
    final contentHash = sha256
        .convert(utf8.encode('$contentHashPrefix|${source.content}'))
        .toString();
    final evidenceId = 'ev:${ctx.projectId}|$ref|$contentHash';

    final points = parsed.data?.points ?? const [];
    final magnitudePresent =
        points.any((p) => (p.magnitudeDb?.isFinite ?? false));
    final phasePresent = points.any((p) => (p.phaseDeg?.isFinite ?? false));
    final impedancePresent =
        points.any((p) => (p.impedanceOhm?.isFinite ?? false));

    final provenance = MeasurementProvenance(
      producer: _producer,
      producerVersion: _parserSchemaVersion,
      sourceIdentity: source.fileName,
      contentHash: contentHash,
      label: source.fileName,
    );

    final MeasurementArtifact artifact;
    if (source.format == AcousticFileType.frd) {
      artifact = _frd(step, ref, parsed, provenance, evidenceId, ctx.projectId,
          magnitudePresent: magnitudePresent,
          phasePresent: phasePresent,
          impedancePresent: impedancePresent,
          points: points,
          primaryContentHash: contentHash,
          additionalSweeps: source.additionalSweeps);
    } else {
      artifact = _zma(step, ref, parsed, provenance, evidenceId, ctx.projectId,
          impedancePresent: impedancePresent);
    }

    ctx.store.put(ctx.projectId, step.outputRef, artifact);
    return referenceResult(step, confidence: _confidence(parsed));
  }

  MeasurementArtifact _frd(
    ProOrchestratorStep step,
    String ref,
    MeasurementParseResult parsed,
    MeasurementProvenance provenance,
    String evidenceId,
    String projectId, {
    required bool magnitudePresent,
    required bool phasePresent,
    required bool impedancePresent,
    required List points,
    required String primaryContentHash,
    List<FrdSweepEntry> additionalSweeps = const [],
  }) {
    if (!magnitudePresent) {
      throw ProToolException(ProToolFailureCode.missingMagnitude,
          'FRD parse produced no finite magnitude data.');
    }
    final ImportedMeasurementEvidence evidence;
    try {
      evidence = ImportedMeasurementEvidence(
        evidenceId: evidenceId,
        projectId: projectId,
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
          EvidenceMetric.calibration,
          if (!phasePresent) EvidenceMetric.phase,
        },
        displayName: provenance.sourceIdentity,
        originalFormat: 'FRD',
        parserSchemaVersion: _parserSchemaVersion,
        magnitudePresent: true,
        phasePresent: phasePresent,
        impedancePresent: impedancePresent,
      );
    } on MeasurementEvidenceException catch (e) {
      throw ProToolException(
          ProToolFailureCode.evidenceConstructionFailure, e.message);
    }

    // FRD confidence. Single sweep → only coverage is computable; repeatability
    // is legitimately unavailable → proProvisional yields insufficientEvidence
    // (honest metadata, not a failure). Multi-sweep path uses aligned spectra
    // so repeatability can be computed from real independent measurements.
    MeasurementConfidenceResult confidence;
    try {
      final freqs = [for (final p in points) p.frequencyHz as double];
      final mags = [
        for (final p in points) (p.magnitudeDb as double?) ?? double.nan
      ];

      final List<double> confFreqs;
      final List<List<double>> spectraDb;
      if (additionalSweeps.isNotEmpty) {
        final aligned = _buildAlignedSpectra(
            freqs, mags, primaryContentHash, additionalSweeps);
        if (aligned != null) {
          confFreqs = aligned.frequencies;
          spectraDb = aligned.spectraDb;
        } else {
          // All additional sweeps were duplicates or invalid; fall back to single.
          confFreqs = freqs;
          spectraDb = [mags];
        }
      } else {
        confFreqs = freqs;
        spectraDb = List.filled(sweepCount, mags);
      }

      confidence = MeasurementConfidenceEngine.evaluate(
        MeasurementConfidenceMetrics(
          frequencies: confFreqs,
          spectraDb: spectraDb,
          minBandHz: confFreqs.isEmpty ? 1 : confFreqs.first,
          maxBandHz: confFreqs.isEmpty ? 2 : confFreqs.last,
        ),
        MeasurementConfidencePolicy.proProvisional(),
      );
    } catch (e) {
      throw ProToolException(
          ProToolFailureCode.confidenceCalculationFailure, e.toString());
    }

    return MeasurementArtifact(
      parse: parsed,
      evidence: evidence,
      evaluation: MeasurementConfidenceEvaluation.evaluated,
      evaluationReason: '',
      confidence: confidence,
    );
  }

  MeasurementArtifact _zma(
    ProOrchestratorStep step,
    String ref,
    MeasurementParseResult parsed,
    MeasurementProvenance provenance,
    String evidenceId,
    String projectId, {
    required bool impedancePresent,
  }) {
    if (!impedancePresent) {
      throw ProToolException(ProToolFailureCode.missingImpedance,
          'ZMA parse produced no finite impedance data.');
    }
    final ImportedMeasurementEvidence evidence;
    try {
      evidence = ImportedMeasurementEvidence(
        evidenceId: evidenceId,
        projectId: projectId,
        measurementRef: ref,
        domain: MeasurementDomain.impedance,
        source: MeasurementSource.importedZma,
        provenance: provenance,
        availableMetrics: const {EvidenceMetric.validBandCoverage},
        unavailableMetrics: const {
          EvidenceMetric.repeatability,
          EvidenceMetric.snr,
          EvidenceMetric.clipping,
          EvidenceMetric.phase,
          EvidenceMetric.calibration,
        },
        displayName: provenance.sourceIdentity,
        originalFormat: 'ZMA',
        parserSchemaVersion: _parserSchemaVersion,
        magnitudePresent: false,
        phasePresent: false,
        impedancePresent: true,
      );
    } on MeasurementEvidenceException catch (e) {
      throw ProToolException(
          ProToolFailureCode.evidenceConstructionFailure, e.message);
    }

    // The confidence engine is acoustic-magnitude only; impedance is not run
    // through it and gets no invented score.
    return MeasurementArtifact(
      parse: parsed,
      evidence: evidence,
      evaluation: MeasurementConfidenceEvaluation.unsupportedDomain,
      evaluationReason:
          'acoustic confidence engine does not apply to impedance (ZMA).',
      confidence: null,
    );
  }

  /// Coarse confidence from the parse outcome — errors low, warnings medium,
  /// clean high. This is the tool-result confidence enum, unrelated to the
  /// numeric measurement confidence stored in the artifact.
  ProConfidence _confidence(MeasurementParseResult r) {
    if (r.errors.isNotEmpty) return ProConfidence.low;
    if (r.warnings.isNotEmpty) return ProConfidence.medium;
    return ProConfidence.high;
  }

  /// Builds aligned (frequencies, spectraDb) from the primary sweep and any
  /// non-duplicate additional sweeps.
  ///
  /// Duplicate detection uses a canonical NUMERIC fingerprint computed from the
  /// parsed (frequencyHz, magnitudeDb) pairs — not from the raw file content.
  /// Two sweeps with the same measured values but different whitespace, decimal
  /// formatting, or comment lines are treated as one sweep, not two.
  ///
  /// Fingerprint tolerance (documented):
  ///   frequency : rounded to nearest integer Hz  (±0.5 Hz)
  ///   magnitude : rounded to nearest 0.001 dB   (±0.0005 dB)
  ///
  /// The raw [FrdSweepEntry.contentHash] is preserved as an identity/integrity
  /// field but is NOT used for repeatability-evidence deduplication.
  ///
  /// Returns null when fewer than 2 distinct valid sweeps survive.
  ({List<double> frequencies, List<List<double>> spectraDb})? _buildAlignedSpectra(
    List<double> primaryFreqs,
    List<double> primaryMags,
    String primaryHash,
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
      final aMags = [
        for (final p in pts) p.magnitudeDb ?? double.nan
      ];
      if (aFreqs.isEmpty) continue;

      final fp = _numericFingerprint(aFreqs, aMags);
      if (seenNumeric.contains(fp)) continue; // numerically identical — not independent
      seenNumeric.add(fp);
      sweepList.add((freqs: aFreqs, mags: aMags));
    }

    if (sweepList.length < 2) return null;
    return FrdGridAligner.align(sweepList);
  }

  /// Canonical numeric fingerprint of an FRD sweep.
  ///
  /// Sorted by frequency; each point encoded as 'fRounded:mRounded' where
  /// fRounded = frequencyHz.round() and mRounded = (magnitudeDb × 1000).round().
  /// Tolerance: ±0.5 Hz in frequency, ±0.0005 dB in magnitude.
  static String _numericFingerprint(List<double> freqs, List<double> mags) {
    final n = freqs.length < mags.length ? freqs.length : mags.length;
    final idx = List.generate(n, (i) => i)
      ..sort((a, b) => freqs[a].compareTo(freqs[b]));
    final parts = [
      for (final i in idx)
        '${freqs[i].round()}:${(mags[i] * 1000).round()}',
    ];
    return sha256.convert(utf8.encode(parts.join('|'))).toString();
  }
}
