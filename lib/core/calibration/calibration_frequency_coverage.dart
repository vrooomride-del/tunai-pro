// ── TUNAI PRO Phase 3-D3B — calibration frequency coverage evaluator ────────
//
// Pure PASS/FAIL over whether a microphone's calibration actually covers a
// required frequency range (Room Auto PEQ v1: 20–300 Hz). Reuses the
// existing [CalibrationCurve]/[CalibrationStatus] types — no new calibration
// model.
//
// Endpoint-inclusive, no extrapolation: a curve's [validMinFrequencyHz,
// validMaxFrequencyHz] must contain BOTH endpoints of the required range.
// Coverage outside the required range is irrelevant to this gate.
//
// [CalibrationStatus.partiallyCalibrated] is NOT an automatic FAIL — a curve
// can leave parts of a MEASUREMENT's full range uncovered while still fully
// covering the required 20–300 Hz band. Only the explicit failure statuses
// (uncalibrated/legacyUnknown/invalid) or a missing/structurally-invalid
// curve fail outright.
library;

import 'calibration_types.dart';

abstract final class CalibrationFrequencyCoverage {
  static bool evaluate({
    required CalibrationStatus calibrationStatus,
    required CalibrationCurve? calibrationCurve,
    required double minFrequencyHz,
    required double maxFrequencyHz,
  }) {
    switch (calibrationStatus) {
      case CalibrationStatus.explicitlyUncalibrated:
      case CalibrationStatus.legacyUnknown:
      case CalibrationStatus.invalid:
        return false;
      case CalibrationStatus.calibrated:
      case CalibrationStatus.partiallyCalibrated:
        break;
    }

    final curve = calibrationCurve;
    if (curve == null) return false;
    if (!curve.isStructurallyValid) return false;

    return curve.validMinFrequencyHz <= minFrequencyHz &&
        curve.validMaxFrequencyHz >= maxFrequencyHz;
  }
}
