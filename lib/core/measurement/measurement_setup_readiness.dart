// ── TUNAI PRO Phase 3-D2 — Guided Measurement Setup readiness typed model ──
//
// Pure types + pure identity/staleness logic. No I/O, no Riverpod. Built on
// top of Phase 3-D1's MeasurementQualityEvaluation/MeasurementInputDevice*
// types — this module composes them into one persistable "is this project
// ready to measure" record, but does not itself run any capture.
library;

import 'measurement_input_device.dart';
import 'measurement_quality_model.dart';

/// Every field that, if it changes, must invalidate a previously-computed
/// readiness. Two identities are compared by value equality — see
/// [MeasurementSetupReadinessSnapshot.isStaleFor].
class MeasurementSetupReadinessIdentity {
  final String projectId;

  /// [MeasurementMicrophoneProfile.checksum] — already folds in
  /// manufacturer/model/serial/connection/calibrationSource/curve checksum
  /// /orientation (angle)/sensitivity/SPL reference. Kept alongside the two
  /// fields below (which ARE already part of this checksum) because the
  /// brief calls them out as separate identity dimensions explicitly, and
  /// redundant-but-explicit is safer for a caller inspecting stale reasons
  /// than a single opaque hash.
  final String? profileChecksum;

  final String? calibrationCurveChecksum;
  final String? calibrationAngle;

  /// `'system-default'` or `'device:<id>'` — a single string discriminator
  /// so BOTH "which device" and "system-default vs specific mode" changes
  /// are caught by one equality check.
  final String inputDeviceIdentity;

  final int expectedSampleRate;
  final int expectedChannelCount;

  /// Free-form version tag for the MeasurementQualityPolicy that produced
  /// this readiness — bumping policy thresholds must invalidate old
  /// readiness snapshots computed under different rules.
  final String qualityPolicyVersion;

  const MeasurementSetupReadinessIdentity({
    required this.projectId,
    required this.profileChecksum,
    required this.calibrationCurveChecksum,
    required this.calibrationAngle,
    required this.inputDeviceIdentity,
    required this.expectedSampleRate,
    required this.expectedChannelCount,
    required this.qualityPolicyVersion,
  });

  static const String kSystemDefaultInputDeviceIdentity = 'system-default';
  static String specificInputDeviceIdentity(String deviceId) =>
      'device:$deviceId';

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        if (profileChecksum != null) 'profileChecksum': profileChecksum,
        if (calibrationCurveChecksum != null)
          'calibrationCurveChecksum': calibrationCurveChecksum,
        if (calibrationAngle != null) 'calibrationAngle': calibrationAngle,
        'inputDeviceIdentity': inputDeviceIdentity,
        'expectedSampleRate': expectedSampleRate,
        'expectedChannelCount': expectedChannelCount,
        'qualityPolicyVersion': qualityPolicyVersion,
      };

  factory MeasurementSetupReadinessIdentity.fromJson(Map<String, dynamic> j) =>
      MeasurementSetupReadinessIdentity(
        projectId: j['projectId'] as String? ?? '',
        profileChecksum: j['profileChecksum'] as String?,
        calibrationCurveChecksum: j['calibrationCurveChecksum'] as String?,
        calibrationAngle: j['calibrationAngle'] as String?,
        inputDeviceIdentity: j['inputDeviceIdentity'] as String? ??
            kSystemDefaultInputDeviceIdentity,
        expectedSampleRate: j['expectedSampleRate'] as int? ?? 0,
        expectedChannelCount: j['expectedChannelCount'] as int? ?? 0,
        qualityPolicyVersion: j['qualityPolicyVersion'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is MeasurementSetupReadinessIdentity &&
      other.projectId == projectId &&
      other.profileChecksum == profileChecksum &&
      other.calibrationCurveChecksum == calibrationCurveChecksum &&
      other.calibrationAngle == calibrationAngle &&
      other.inputDeviceIdentity == inputDeviceIdentity &&
      other.expectedSampleRate == expectedSampleRate &&
      other.expectedChannelCount == expectedChannelCount &&
      other.qualityPolicyVersion == qualityPolicyVersion;

  @override
  int get hashCode => Object.hash(
        projectId,
        profileChecksum,
        calibrationCurveChecksum,
        calibrationAngle,
        inputDeviceIdentity,
        expectedSampleRate,
        expectedChannelCount,
        qualityPolicyVersion,
      );
}

/// Which output side the Guided Setup's input-level-check signal played —
/// see MeasurementLevelCheckSignal (Phase 3-D1). Recorded here for display
/// ("Expert Details") and for Room's future ability to re-check either
/// side; never used as an Auto PEQ input.
enum MeasurementSetupSignalSide { mono, left, right }

/// A snapshot of one Guided Measurement Setup check. Immutable; persisted
/// on ProProject. A NEW instance (new [generationId]) is produced by every
/// successful check — never mutated in place.
class MeasurementSetupReadinessSnapshot {
  final MeasurementSetupReadinessIdentity identity;

  /// Unique per successful check — see [MeasurementSetupReadinessSnapshot
  /// .newGenerationId].
  final String generationId;

  final MeasurementQualityEvaluation? noiseFloorEvaluation;
  final MeasurementQualityEvaluation? levelCheckEvaluation;

  /// The actual device the level-check (or, if level-check hasn't run yet,
  /// the noise-floor capture) used — display/Expert-Details only.
  final MeasurementInputDeviceSnapshot? deviceSnapshot;

  /// Reasons capture should NOT proceed (empty when ready).
  final List<String> blockers;

  /// Reasons the user should be warned about but that don't block (empty
  /// when nothing to warn about).
  final List<String> warnings;

  final DateTime checkedAt;
  final DateTime expiresAt;

  /// True only when [blockers] is empty. Always computed by
  /// MeasurementSetupReadinessBuilder.build — never re-derived ad hoc by a
  /// caller.
  final bool isReady;

  /// True when the user explicitly acknowledged a warning-level condition
  /// (e.g. "continue without calibration") for THIS generation. Never
  /// implied — always set by an explicit user action.
  final bool explicitWarningAcknowledgement;

  final MeasurementSetupSignalSide selectedSetupSignalSide;

  const MeasurementSetupReadinessSnapshot({
    required this.identity,
    required this.generationId,
    this.noiseFloorEvaluation,
    this.levelCheckEvaluation,
    this.deviceSnapshot,
    required this.blockers,
    required this.warnings,
    required this.checkedAt,
    required this.expiresAt,
    required this.isReady,
    this.explicitWarningAcknowledgement = false,
    this.selectedSetupSignalSide = MeasurementSetupSignalSide.mono,
  });

  static String newGenerationId() =>
      'setup_${DateTime.now().microsecondsSinceEpoch}';

  /// True when [now] (defaults to [DateTime.now]) is at/after [expiresAt],
  /// OR when [checkedAt] is implausibly in the future relative to [now] —
  /// a system-clock anomaly must never be interpreted as "still valid",
  /// so it fails safe to expired rather than trusting a clearly-wrong
  /// timestamp.
  bool isExpired({DateTime? now}) {
    final n = now ?? DateTime.now();
    if (checkedAt.isAfter(n.add(const Duration(minutes: 1)))) return true;
    return !n.isBefore(expiresAt);
  }

  /// True when [current] identity differs from the identity this snapshot
  /// was computed under — a previously-Ready snapshot must be treated as
  /// stale (never silently trusted) once anything identity-relevant
  /// changes.
  bool isStaleFor(MeasurementSetupReadinessIdentity current) =>
      current != identity;

  /// Combined "can this actually be used right now" check — expired OR
  /// stale OR never was ready.
  bool isUsableNow(MeasurementSetupReadinessIdentity current,
          {DateTime? now}) =>
      isReady && !isExpired(now: now) && !isStaleFor(current);

  Map<String, dynamic> toJson() => {
        'identity': identity.toJson(),
        'generationId': generationId,
        if (noiseFloorEvaluation != null)
          'noiseFloorMetrics': noiseFloorEvaluation!.metrics.toJson(),
        if (noiseFloorEvaluation != null)
          'noiseFloorStatuses':
              noiseFloorEvaluation!.statuses.map((s) => s.toJson()).toList(),
        if (levelCheckEvaluation != null)
          'levelCheckMetrics': levelCheckEvaluation!.metrics.toJson(),
        if (levelCheckEvaluation != null)
          'levelCheckStatuses':
              levelCheckEvaluation!.statuses.map((s) => s.toJson()).toList(),
        if (deviceSnapshot != null) 'deviceSnapshot': deviceSnapshot!.toJson(),
        'blockers': blockers,
        'warnings': warnings,
        'checkedAt': checkedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'isReady': isReady,
        'explicitWarningAcknowledgement': explicitWarningAcknowledgement,
        'selectedSetupSignalSide': selectedSetupSignalSide.name,
      };

  factory MeasurementSetupReadinessSnapshot.fromJson(Map<String, dynamic> j) {
    MeasurementQualityEvaluation? decodeEval(
        String metricsKey, String statusesKey) {
      final metricsJson = j[metricsKey];
      if (metricsJson == null) return null;
      try {
        final metrics = MeasurementQualityMetrics.fromJson(
            Map<String, dynamic>.from(metricsJson as Map));
        final statuses = ((j[statusesKey] as List?) ?? const [])
            .map((e) => MeasurementQualityStatus.fromJson(e as String))
            .toSet();
        return MeasurementQualityEvaluation(
          statuses:
              statuses.isEmpty ? {MeasurementQualityStatus.ready} : statuses,
          metrics: metrics,
        );
      } catch (_) {
        return null;
      }
    }

    return MeasurementSetupReadinessSnapshot(
      identity: MeasurementSetupReadinessIdentity.fromJson(
          Map<String, dynamic>.from(j['identity'] as Map? ?? {})),
      generationId: j['generationId'] as String? ?? newGenerationId(),
      noiseFloorEvaluation:
          decodeEval('noiseFloorMetrics', 'noiseFloorStatuses'),
      deviceSnapshot: () {
        final raw = j['deviceSnapshot'];
        if (raw == null) return null;
        try {
          return MeasurementInputDeviceSnapshot.fromJson(
              Map<String, dynamic>.from(raw as Map));
        } catch (_) {
          return null;
        }
      }(),
      levelCheckEvaluation:
          decodeEval('levelCheckMetrics', 'levelCheckStatuses'),
      blockers: ((j['blockers'] as List?) ?? const []).cast<String>(),
      warnings: ((j['warnings'] as List?) ?? const []).cast<String>(),
      checkedAt:
          DateTime.tryParse(j['checkedAt'] as String? ?? '') ?? DateTime.now(),
      expiresAt:
          DateTime.tryParse(j['expiresAt'] as String? ?? '') ?? DateTime.now(),
      isReady: j['isReady'] as bool? ?? false,
      explicitWarningAcknowledgement:
          j['explicitWarningAcknowledgement'] as bool? ?? false,
      selectedSetupSignalSide: MeasurementSetupSignalSide.values.firstWhere(
          (s) => s.name == j['selectedSetupSignalSide'],
          orElse: () => MeasurementSetupSignalSide.mono),
    );
  }
}
