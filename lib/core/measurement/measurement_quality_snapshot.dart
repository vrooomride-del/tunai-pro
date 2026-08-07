// ── TUNAI PRO Phase 3-D2 — MeasurementQualitySnapshot ───────────────────────
//
// The immutable record a future Factory/Room Accept (Phase 3-D3) will embed
// into ParsedMeasurementData — "what quality was true about the setup this
// specific capture was taken under." Distinct from
// MeasurementSetupReadinessSnapshot (the SETUP CHECK's own record, which can
// span multiple captures) — this type is per-capture and, once wired in
// 3-D3, never mutated after creation.
//
// This phase only defines the type + JSON + the setup->snapshot builder.
// No Accept wiring yet — see the Phase 3-D2 completion report.
library;

import '../calibration/calibration_types.dart' show CalibrationStatus;
import 'measurement_input_device.dart';
import 'measurement_setup_readiness.dart';

class MeasurementQualitySnapshot {
  final String setupGenerationId;
  final MeasurementInputDeviceSnapshot? inputDeviceSnapshot;

  /// [MeasurementMicrophoneProfile.checksum] at capture time.
  final String? profileChecksum;

  final CalibrationStatus? calibrationStatus;
  final double? noiseFloorDbFs;
  final double peakDbFs;
  final double rmsDbFs;
  final double? signalToNoiseDb;
  final int clippedSampleCount;
  final double clippedSampleRatio;
  final int actualSampleRate;
  final int actualChannelCount;
  final DateTime setupCheckedAt;
  final DateTime capturedAt;
  final String qualityPolicyVersion;

  const MeasurementQualitySnapshot({
    required this.setupGenerationId,
    this.inputDeviceSnapshot,
    this.profileChecksum,
    this.calibrationStatus,
    this.noiseFloorDbFs,
    required this.peakDbFs,
    required this.rmsDbFs,
    this.signalToNoiseDb,
    required this.clippedSampleCount,
    required this.clippedSampleRatio,
    required this.actualSampleRate,
    required this.actualChannelCount,
    required this.setupCheckedAt,
    required this.capturedAt,
    required this.qualityPolicyVersion,
  });

  /// Builds a capture-time snapshot from a Guided Setup readiness record —
  /// the setup's own level-check metrics ARE what this capture's quality
  /// was taken under, as long as the identity/generation still matches at
  /// Accept time (that matching is Phase 3-D3's stale-preview-style guard,
  /// not this constructor's job — this is a pure data copy).
  factory MeasurementQualitySnapshot.fromSetupReadiness(
    MeasurementSetupReadinessSnapshot readiness, {
    required String qualityPolicyVersion,
    DateTime? capturedAt,
  }) {
    final level = readiness.levelCheckEvaluation;
    final metrics = level?.metrics;
    return MeasurementQualitySnapshot(
      setupGenerationId: readiness.generationId,
      inputDeviceSnapshot: readiness.deviceSnapshot,
      profileChecksum: readiness.identity.profileChecksum,
      calibrationStatus: metrics?.calibrationStatus,
      noiseFloorDbFs: metrics?.noiseFloorDbFs ??
          readiness.noiseFloorEvaluation?.metrics.noiseFloorDbFs,
      peakDbFs: metrics?.peakDbFs ?? 0.0,
      rmsDbFs: metrics?.rmsDbFs ?? 0.0,
      signalToNoiseDb: metrics?.signalToNoiseDb,
      clippedSampleCount: metrics?.clippedSampleCount ?? 0,
      clippedSampleRatio: metrics?.clippedSampleRatio ?? 0.0,
      actualSampleRate:
          metrics?.actualSampleRate ?? readiness.identity.expectedSampleRate,
      actualChannelCount: metrics?.actualChannelCount ??
          readiness.identity.expectedChannelCount,
      setupCheckedAt: readiness.checkedAt,
      capturedAt: capturedAt ?? DateTime.now(),
      qualityPolicyVersion: qualityPolicyVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'setupGenerationId': setupGenerationId,
        if (inputDeviceSnapshot != null)
          'inputDeviceSnapshot': inputDeviceSnapshot!.toJson(),
        if (profileChecksum != null) 'profileChecksum': profileChecksum,
        if (calibrationStatus != null)
          'calibrationStatus': calibrationStatus!.toJson(),
        if (noiseFloorDbFs != null) 'noiseFloorDbFs': noiseFloorDbFs,
        'peakDbFs': peakDbFs,
        'rmsDbFs': rmsDbFs,
        if (signalToNoiseDb != null) 'signalToNoiseDb': signalToNoiseDb,
        'clippedSampleCount': clippedSampleCount,
        'clippedSampleRatio': clippedSampleRatio,
        'actualSampleRate': actualSampleRate,
        'actualChannelCount': actualChannelCount,
        'setupCheckedAt': setupCheckedAt.toIso8601String(),
        'capturedAt': capturedAt.toIso8601String(),
        'qualityPolicyVersion': qualityPolicyVersion,
      };

  /// Item-resilient by field: a corrupt/missing nested value falls back to
  /// null/a safe default rather than throwing — matches the established
  /// pattern for every other snapshot type in this codebase (never fails
  /// the whole enclosing measurement's decode).
  factory MeasurementQualitySnapshot.fromJson(Map<String, dynamic> j) {
    MeasurementInputDeviceSnapshot? device;
    try {
      final raw = j['inputDeviceSnapshot'];
      if (raw != null) {
        device = MeasurementInputDeviceSnapshot.fromJson(
            Map<String, dynamic>.from(raw as Map));
      }
    } catch (_) {
      device = null;
    }

    CalibrationStatus? calStatus;
    try {
      final raw = j['calibrationStatus'];
      if (raw is String) calStatus = CalibrationStatus.fromJson(raw);
    } catch (_) {
      calStatus = null;
    }

    return MeasurementQualitySnapshot(
      setupGenerationId: j['setupGenerationId'] as String? ?? '',
      inputDeviceSnapshot: device,
      profileChecksum: j['profileChecksum'] as String?,
      calibrationStatus: calStatus,
      noiseFloorDbFs: (j['noiseFloorDbFs'] as num?)?.toDouble(),
      peakDbFs: (j['peakDbFs'] as num?)?.toDouble() ?? 0.0,
      rmsDbFs: (j['rmsDbFs'] as num?)?.toDouble() ?? 0.0,
      signalToNoiseDb: (j['signalToNoiseDb'] as num?)?.toDouble(),
      clippedSampleCount: j['clippedSampleCount'] as int? ?? 0,
      clippedSampleRatio: (j['clippedSampleRatio'] as num?)?.toDouble() ?? 0.0,
      actualSampleRate: j['actualSampleRate'] as int? ?? 0,
      actualChannelCount: j['actualChannelCount'] as int? ?? 0,
      setupCheckedAt: DateTime.tryParse(j['setupCheckedAt'] as String? ?? '') ??
          DateTime.now(),
      capturedAt:
          DateTime.tryParse(j['capturedAt'] as String? ?? '') ?? DateTime.now(),
      qualityPolicyVersion: j['qualityPolicyVersion'] as String? ?? '',
    );
  }
}
