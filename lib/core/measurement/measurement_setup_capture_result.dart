// ── TUNAI PRO Phase 3-D1 — setup-check capture result types ────────────────
//
// Shared result shape for MicMeasurementController's new
// measureNoiseFloor()/runInputLevelCheck() setup-check methods. Neither
// method touches MicMeasurementState — a setup check is not a live/FFT
// measurement, so it does not go through that state machine at all.
library;

import 'measurement_quality_model.dart';

/// Which channel(s) a level-check test signal carries. Foundation-only:
/// which of these Guided Setup (Phase 3-D2) actually offers, and what each
/// means for Room's L/R workflow, is decided there — this phase only makes
/// the underlying capture parameterized rather than hardcoded to mono.
enum MeasurementLevelCheckSignal { mono, leftOnly, rightOnly }

class MeasurementSetupCaptureResult {
  final bool isSuccess;
  final MeasurementQualityEvaluation? evaluation;

  /// Set on failure — device unavailable, permission denied, malformed
  /// capture, etc. Always null when [isSuccess] is true.
  final String? error;

  const MeasurementSetupCaptureResult({
    required this.isSuccess,
    this.evaluation,
    this.error,
  });

  factory MeasurementSetupCaptureResult.failure(String error) =>
      MeasurementSetupCaptureResult(isSuccess: false, error: error);

  factory MeasurementSetupCaptureResult.success(
          MeasurementQualityEvaluation evaluation) =>
      MeasurementSetupCaptureResult(isSuccess: true, evaluation: evaluation);
}
