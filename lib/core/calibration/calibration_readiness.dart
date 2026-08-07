/// Pure calibration-readiness evaluation — no I/O, no UI, no gating.
///
/// This module answers one question: "given what a capture actually knows
/// about its calibration, what can be claimed about it?" It does not decide
/// whether Auto PEQ may run, and it does not change any existing behavior —
/// it exists so a future gate (not built this round) has a single, tested
/// source of truth to consult instead of re-deriving this logic ad hoc.
///
/// It also gives [MeasurementCaptureEvidence] callers a small, pure helper
/// for filling in `EvidenceMetric.calibration` / `calibrationRef` correctly,
/// since that model's own invariant ("calibration available requires a
/// calibrationRef") is easy to violate by hand.
library;

import 'calibration_types.dart';

/// How trustworthy a capture's calibration information is, from a future
/// gate's point of view. This is a superset-refinement of [CalibrationStatus]
/// that also accounts for whether a usable reference (checksum) exists —
/// a status can claim "calibrated" while still lacking a ref to point to,
/// which must never be treated as claimable.
enum CalibrationReadinessLevel {
  /// A calibration curve was applied and a stable ref to it exists.
  calibrated,

  /// A calibration curve was applied, but coverage was partial (some points
  /// fell outside the curve's valid range) and/or a stable ref exists.
  partiallyCalibrated,

  /// The capture explicitly recorded that no calibration was applied.
  uncalibrated,

  /// Older data whose calibration status was never recorded — must not be
  /// treated as either calibrated or explicitly uncalibrated.
  unknown,
}

/// Pure readiness verdict for a single measurement's calibration state.
class CalibrationReadiness {
  final CalibrationReadinessLevel level;
  final CalibrationStatus status;

  /// A stable identity for the calibration curve that was applied (its
  /// checksum), or null if none exists / none is safely claimable.
  final String? calibrationRef;

  /// Human-readable reasons a caller may want to surface, e.g. why a
  /// "calibrated" status still could not produce a claimable ref.
  final List<String> reasons;

  const CalibrationReadiness({
    required this.level,
    required this.status,
    this.calibrationRef,
    this.reasons = const [],
  });

  /// True only when a future gate (or `MeasurementCaptureEvidence`) may
  /// safely claim `EvidenceMetric.calibration` as available. Requires both
  /// a positive readiness level AND a non-null ref — mirrors
  /// `MeasurementCaptureEvidence`'s own invariant.
  bool get canClaimCalibrationMetric =>
      calibrationRef != null &&
      (level == CalibrationReadinessLevel.calibrated ||
          level == CalibrationReadinessLevel.partiallyCalibrated);

  /// Derives readiness from a capture's recorded [CalibrationStatus] and
  /// (if any) the checksum of the curve that was applied. Pure — no lookups,
  /// no defaults invented beyond what the inputs already state.
  static CalibrationReadiness fromCalibrationStatus({
    required CalibrationStatus status,
    String? calibrationCurveChecksum,
  }) {
    switch (status) {
      case CalibrationStatus.calibrated:
        if (calibrationCurveChecksum == null) {
          return CalibrationReadiness(
            level: CalibrationReadinessLevel.unknown,
            status: status,
            reasons: const [
              'status is calibrated but no curve checksum was recorded; '
                  'cannot produce a claimable ref.',
            ],
          );
        }
        return CalibrationReadiness(
          level: CalibrationReadinessLevel.calibrated,
          status: status,
          calibrationRef: calibrationCurveChecksum,
        );
      case CalibrationStatus.partiallyCalibrated:
        if (calibrationCurveChecksum == null) {
          return CalibrationReadiness(
            level: CalibrationReadinessLevel.unknown,
            status: status,
            reasons: const [
              'status is partiallyCalibrated but no curve checksum was '
                  'recorded; cannot produce a claimable ref.',
            ],
          );
        }
        return CalibrationReadiness(
          level: CalibrationReadinessLevel.partiallyCalibrated,
          status: status,
          calibrationRef: calibrationCurveChecksum,
          reasons: const [
            'coverage was partial — some points fell outside the '
                'calibration curve\'s valid frequency range.',
          ],
        );
      case CalibrationStatus.explicitlyUncalibrated:
        return const CalibrationReadiness(
          level: CalibrationReadinessLevel.uncalibrated,
          status: CalibrationStatus.explicitlyUncalibrated,
        );
      case CalibrationStatus.legacyUnknown:
        return const CalibrationReadiness(
          level: CalibrationReadinessLevel.unknown,
          status: CalibrationStatus.legacyUnknown,
          reasons: [
            'legacy data recorded before calibration tracking existed.',
          ],
        );
      case CalibrationStatus.invalid:
        return const CalibrationReadiness(
          level: CalibrationReadinessLevel.unknown,
          status: CalibrationStatus.invalid,
          reasons: ['calibration data was present but structurally invalid.'],
        );
    }
  }

  /// The `(available, ref)` pair a caller should pass into
  /// `MeasurementCaptureEvidence`'s `availableMetrics` /
  /// `calibrationRef` fields for `EvidenceMetric.calibration`. Never returns
  /// `available: true` with a null `ref` — satisfies that model's invariant
  /// by construction.
  static ({bool available, String? ref}) evidenceCalibrationFields(
    CalibrationReadiness readiness,
  ) {
    if (readiness.canClaimCalibrationMetric) {
      return (available: true, ref: readiness.calibrationRef);
    }
    return (available: false, ref: null);
  }
}
