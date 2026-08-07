// ── TUNAI PRO Phase 3-D3C — live-capture evidence builder ───────────────────
//
// ONE place that turns an accepted live-capture [ParsedMeasurementData] into
// a [MeasurementCaptureEvidence]. Every adapter that needs capture evidence
// calls this instead of re-deriving the calibration/quality mapping, so the
// rules below exist exactly once.
//
// Hard rules (Phase 3-D3C §3/§4):
//  - Only real, measured values are ever claimed. No placeholder noise floor
//    (-90/-78), no invented SNR, no synthesised repeatability score.
//  - A metric is `available` only when the underlying numbers actually exist
//    and are finite; otherwise it is explicitly `unavailable`. Unknown is
//    never rendered as "fine".
//  - Repeatability is always unavailable: this app performs a single capture
//    per channel and has no repeat/split-half measurement, so there is
//    nothing honest to claim. (MeasurementCaptureEvidence would reject a
//    claim anyway — it requires split-half refs or >=2 repeat spectra.)
//  - Calibration follows the capture's recorded CalibrationStatus, not the
//    profile's current state: `calibrated` may claim the metric (with a ref),
//    `partiallyCalibrated` keeps the ref for traceability but must NOT claim
//    full calibration, and uncalibrated/legacyUnknown/invalid claim nothing.

library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../calibration/calibration_types.dart';
import '../pro_acoustic_data.dart';
import 'measurement_evidence.dart';

class MeasurementCaptureEvidenceBuildResult {
  final MeasurementCaptureEvidence evidence;

  /// Human-readable provenance notes for the UI/report layer — e.g. that
  /// calibration only partially covered the measured band, or that the
  /// capture predates quality provenance.
  final List<String> provenanceWarnings;

  const MeasurementCaptureEvidenceBuildResult({
    required this.evidence,
    this.provenanceWarnings = const [],
  });
}

abstract final class MeasurementCaptureEvidenceBuilder {
  static const String producer = 'MeasurementCaptureEvidenceBuilder';
  static const String producerVersion = '1';
  static const String _hashPrefix = 'live_capture_v1';

  /// Builds capture evidence for [data], which MUST be a live capture
  /// ([MeasurementDataSource.liveCapture]). Imported/legacy data has no
  /// capture provenance and must keep using ImportedMeasurementEvidence.
  static MeasurementCaptureEvidenceBuildResult build({
    required String projectId,
    required String measurementRef,
    required ParsedMeasurementData data,
  }) {
    assert(data.source == MeasurementDataSource.liveCapture,
        'capture evidence is only valid for a live capture');

    final warnings = <String>[];
    final quality = data.qualitySnapshot;
    final available = <EvidenceMetric>{};
    final unavailable = <EvidenceMetric>{};

    // ── Band coverage / phase: properties of the parsed data itself ────────
    available.add(EvidenceMetric.validBandCoverage);
    if (data.hasPhase) {
      available.add(EvidenceMetric.phase);
    } else {
      unavailable.add(EvidenceMetric.phase);
    }

    // ── Repeatability: never claimable today (see file header) ────────────
    unavailable.add(EvidenceMetric.repeatability);

    // ── SNR: derived from the REAL measured rms and noise floor ───────────
    // Powers (not dB) are what MeasurementCaptureEvidence stores; converting
    // the measured dBFS values is a unit change, not an invented number.
    double? signalPower;
    double? noisePower;
    final rmsDb = quality?.setupRmsDbFs;
    final noiseDb = quality?.setupNoiseFloorDbFs;
    if (rmsDb != null &&
        noiseDb != null &&
        rmsDb.isFinite &&
        noiseDb.isFinite) {
      signalPower = math.pow(10, rmsDb / 10).toDouble();
      noisePower = math.pow(10, noiseDb / 10).toDouble();
    }
    if (signalPower != null && noisePower != null) {
      available.add(EvidenceMetric.snr);
    } else {
      unavailable.add(EvidenceMetric.snr);
    }

    // ── Clipping: needs BOTH counts. The snapshot stores the clipped count
    // and its ratio; the total is recoverable only when the ratio is > 0.
    // When it isn't, the total is genuinely unknown and clipping is reported
    // unavailable rather than backed by a guessed denominator.
    int? clipped;
    int? total;
    if (quality != null) {
      final ratio = quality.setupClippedSampleRatio;
      if (ratio.isFinite && ratio > 0) {
        clipped = quality.setupClippedSampleCount;
        total = (quality.setupClippedSampleCount / ratio).round();
        if (total < clipped) total = clipped;
      }
    }
    if (clipped != null && total != null) {
      available.add(EvidenceMetric.clipping);
    } else {
      unavailable.add(EvidenceMetric.clipping);
    }

    // ── Calibration: from the capture's own recorded status ───────────────
    final calibrationRef = data.calibrationCurveChecksum;
    switch (data.calibrationStatus) {
      case CalibrationStatus.calibrated:
        if (calibrationRef != null) {
          available.add(EvidenceMetric.calibration);
        } else {
          // "calibrated" with no curve identity is unrecoverable provenance.
          unavailable.add(EvidenceMetric.calibration);
          warnings.add('보정 상태는 calibrated이지만 보정 커브 식별자가 없습니다.');
        }
      case CalibrationStatus.partiallyCalibrated:
        // Ref kept for traceability, but a partial correction must never be
        // presented as full calibration.
        unavailable.add(EvidenceMetric.calibration);
        warnings.add('보정 커브가 측정 대역 전체를 덮지 않았습니다(부분 보정).');
      case CalibrationStatus.explicitlyUncalibrated:
        unavailable.add(EvidenceMetric.calibration);
        warnings.add('보정 없이 측정되었습니다.');
      case CalibrationStatus.legacyUnknown:
        unavailable.add(EvidenceMetric.calibration);
        warnings.add('이 측정의 보정 이력이 기록되어 있지 않습니다.');
      case CalibrationStatus.invalid:
        unavailable.add(EvidenceMetric.calibration);
        warnings.add('보정 정보가 올바르지 않아 사용되지 않았습니다.');
    }

    if (quality == null) {
      warnings.add('이 측정에는 품질 기록(quality snapshot)이 없습니다.');
    }

    final contentHash =
        sha256.convert(utf8.encode('$_hashPrefix|${data.id}')).toString();

    return MeasurementCaptureEvidenceBuildResult(
      evidence: MeasurementCaptureEvidence(
        evidenceId: 'ev:$projectId|$measurementRef|$contentHash',
        projectId: projectId,
        measurementRef: measurementRef,
        provenance: MeasurementProvenance(
          producer: producer,
          producerVersion: producerVersion,
          sourceIdentity: data.sourceFileName,
          contentHash: contentHash,
          label: data.sourceFileName,
          capturedAtIso: (quality?.provenance.capturedAt ?? data.importedAt)
              .toIso8601String(),
        ),
        availableMetrics: available,
        unavailableMetrics: unavailable,
        // Actual recorded format, re-verified from the capture WAV at accept
        // time (Phase 3-D3A-2) — never the policy's expected values.
        sampleRate: quality?.provenance.actualSampleRate,
        channelCount: quality?.provenance.actualChannelCount,
        signalPower: signalPower,
        noisePower: noisePower,
        clippedSamples: clipped,
        totalSamples: total,
        microphoneProfileRef: quality?.provenance.microphoneProfileChecksum ??
            data.microphoneSnapshot?.profileChecksum,
        // Kept even for partial coverage: it identifies WHICH curve was
        // applied. The metric claim above is what controls whether callers
        // may treat this as fully calibrated.
        calibrationRef: data.calibrationStatus ==
                    CalibrationStatus.calibrated ||
                data.calibrationStatus == CalibrationStatus.partiallyCalibrated
            ? calibrationRef
            : null,
        captureConfigurationRef: quality?.provenance.setupReadinessGenerationId,
      ),
      provenanceWarnings: warnings,
    );
  }
}
