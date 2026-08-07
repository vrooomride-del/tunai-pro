// ── TUNAI PRO Phase 3-D3B — MeasurementQualitySnapshot ──────────────────────
//
// The immutable record embedded into ParsedMeasurementData at Accept time —
// "what was true about this specific capture and the setup it was taken
// under." Two deliberately SEPARATE provenance sources, never conflated:
//
//   - [provenance]: this capture's own identity + actual WAV format
//     (project/profile/curve/angle/device/generation/policy, actual
//     sampleRate/channelCount, capturedAt) — the SAME
//     MeasurementCaptureProvenance object Phase 3-D3A-2's Accept gate
//     already pins at capture time. Reused here, not duplicated.
//
//   - the `setup*` fields: the Guided Setup CHECK's own level-check/
//     noise-floor metrics (peak/RMS/SNR/clipping/noise-floor, the device it
//     ran on, when it ran). A setup check can precede many captures and its
//     own actual-format numbers are NOT this capture's WAV — mixing the two
//     was the exact mistake this phase's spec calls out, hence the `setup`
//     prefix on every field sourced from the check rather than the capture.
//
// Built exactly once, at capture time, by [MeasurementQualitySnapshotBuilder]
// — never reconstructed from current project state at Accept.
library;

import '../calibration/calibration_types.dart' show CalibrationStatus;
import 'measurement_capture_provenance.dart';
import 'measurement_input_device.dart';
import 'measurement_setup_readiness.dart';

class MeasurementQualitySnapshot {
  /// This capture's own identity + actual WAV format — never the setup
  /// check's numbers. See [MeasurementCaptureProvenance] for field detail.
  final MeasurementCaptureProvenance provenance;

  /// Below: the SETUP CHECK's own metrics — what the check measured, not
  /// what this capture measured. Distinguishable from [provenance] both by
  /// the `setup` prefix and by nested structure.
  final CalibrationStatus? setupCalibrationStatus;
  final double? setupNoiseFloorDbFs;
  final double setupPeakDbFs;
  final double setupRmsDbFs;
  final double? setupSignalToNoiseDb;
  final int setupClippedSampleCount;
  final double setupClippedSampleRatio;
  final MeasurementInputDeviceSnapshot? setupInputDeviceSnapshot;
  final DateTime setupCheckedAt;

  const MeasurementQualitySnapshot({
    required this.provenance,
    this.setupCalibrationStatus,
    this.setupNoiseFloorDbFs,
    required this.setupPeakDbFs,
    required this.setupRmsDbFs,
    this.setupSignalToNoiseDb,
    required this.setupClippedSampleCount,
    required this.setupClippedSampleRatio,
    this.setupInputDeviceSnapshot,
    required this.setupCheckedAt,
  });

  Map<String, dynamic> toJson() => {
        'provenance': provenance.toJson(),
        if (setupCalibrationStatus != null)
          'setupCalibrationStatus': setupCalibrationStatus!.toJson(),
        if (setupNoiseFloorDbFs != null)
          'setupNoiseFloorDbFs': setupNoiseFloorDbFs,
        'setupPeakDbFs': setupPeakDbFs,
        'setupRmsDbFs': setupRmsDbFs,
        if (setupSignalToNoiseDb != null)
          'setupSignalToNoiseDb': setupSignalToNoiseDb,
        'setupClippedSampleCount': setupClippedSampleCount,
        'setupClippedSampleRatio': setupClippedSampleRatio,
        if (setupInputDeviceSnapshot != null)
          'setupInputDeviceSnapshot': setupInputDeviceSnapshot!.toJson(),
        'setupCheckedAt': setupCheckedAt.toIso8601String(),
      };

  /// Item-resilient: a corrupt/missing nested value falls back to null/a
  /// safe default rather than throwing — never fails the whole enclosing
  /// measurement's decode. A missing/unparseable `provenance` is the one
  /// exception: without it this snapshot carries no usable identity at all,
  /// so [fromJson] returns null in that case (see call site) rather than a
  /// snapshot with an empty synthetic provenance.
  static MeasurementQualitySnapshot? fromJson(Map<String, dynamic> j) {
    MeasurementCaptureProvenance provenance;
    try {
      final raw = j['provenance'];
      if (raw == null) return null;
      provenance = MeasurementCaptureProvenance.fromJson(
          Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      return null;
    }

    MeasurementInputDeviceSnapshot? device;
    try {
      final raw = j['setupInputDeviceSnapshot'];
      if (raw != null) {
        device = MeasurementInputDeviceSnapshot.fromJson(
            Map<String, dynamic>.from(raw as Map));
      }
    } catch (_) {
      device = null;
    }

    CalibrationStatus? calStatus;
    try {
      final raw = j['setupCalibrationStatus'];
      if (raw is String) calStatus = CalibrationStatus.fromJson(raw);
    } catch (_) {
      calStatus = null;
    }

    return MeasurementQualitySnapshot(
      provenance: provenance,
      setupCalibrationStatus: calStatus,
      setupNoiseFloorDbFs: (j['setupNoiseFloorDbFs'] as num?)?.toDouble(),
      setupPeakDbFs: (j['setupPeakDbFs'] as num?)?.toDouble() ?? 0.0,
      setupRmsDbFs: (j['setupRmsDbFs'] as num?)?.toDouble() ?? 0.0,
      setupSignalToNoiseDb: (j['setupSignalToNoiseDb'] as num?)?.toDouble(),
      setupClippedSampleCount: j['setupClippedSampleCount'] as int? ?? 0,
      setupClippedSampleRatio:
          (j['setupClippedSampleRatio'] as num?)?.toDouble() ?? 0.0,
      setupInputDeviceSnapshot: device,
      setupCheckedAt: DateTime.tryParse(j['setupCheckedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// The ONE builder — Factory and Room capture() both call this, so a quality
/// snapshot's shape/derivation can never drift between the two paths, and it
/// is always built from the SAME [MeasurementCaptureProvenance] instance
/// already pinned for the Accept gate (never a second, separately-derived
/// provenance).
abstract final class MeasurementQualitySnapshotBuilder {
  static MeasurementQualitySnapshot build({
    required MeasurementCaptureProvenance provenance,
    required MeasurementSetupReadinessSnapshot readiness,
  }) {
    final metrics = readiness.levelCheckEvaluation?.metrics;
    return MeasurementQualitySnapshot(
      provenance: provenance,
      setupCalibrationStatus: metrics?.calibrationStatus,
      setupNoiseFloorDbFs: metrics?.noiseFloorDbFs ??
          readiness.noiseFloorEvaluation?.metrics.noiseFloorDbFs,
      setupPeakDbFs: metrics?.peakDbFs ?? 0.0,
      setupRmsDbFs: metrics?.rmsDbFs ?? 0.0,
      setupSignalToNoiseDb: metrics?.signalToNoiseDb,
      setupClippedSampleCount: metrics?.clippedSampleCount ?? 0,
      setupClippedSampleRatio: metrics?.clippedSampleRatio ?? 0.0,
      setupInputDeviceSnapshot: readiness.deviceSnapshot,
      setupCheckedAt: readiness.checkedAt,
    );
  }
}
