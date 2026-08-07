// ── TUNAI PRO Phase 3-B — Calibration interpolation / application ──────────
//
// Pure module: no FFT, no file I/O, no platform channel. Deliberately
// independent of the pink-noise capture pipeline (mic_measurement_controller
// .dart) so a future Log Sweep / impulse-response path can call the exact
// same [CalibrationApplicator.apply] without this module knowing anything
// about how its input points were produced.

import 'dart:math' as math;

import '../pro_acoustic_data.dart' show MeasurementDataPoint;
import 'calibration_types.dart';

/// Result of applying (or attempting to apply) a [CalibrationCurve] to a set
/// of raw measurement points. [rawPoints] is always the caller's input,
/// untouched. [calibratedPoints] is always a NEW list — even when nothing
/// changed (flat curve, or no curve at all), it is never the same list
/// instance as [rawPoints].
class CalibrationApplicationResult {
  final List<MeasurementDataPoint> rawPoints;
  final List<MeasurementDataPoint> calibratedPoints;
  final CalibrationStatus status;
  final double? coveredMinFrequencyHz;
  final double? coveredMaxFrequencyHz;
  final int uncoveredCount;
  final String? curveChecksum;
  final List<String> warnings;

  const CalibrationApplicationResult({
    required this.rawPoints,
    required this.calibratedPoints,
    required this.status,
    this.coveredMinFrequencyHz,
    this.coveredMaxFrequencyHz,
    this.uncoveredCount = 0,
    this.curveChecksum,
    this.warnings = const [],
  });
}

abstract final class CalibrationApplicator {
  /// Interpolates [curve]'s correction (dB) at [frequencyHz] on a
  /// log10(frequency)-linear-dB axis. Returns null — never a clamped/
  /// extrapolated value — when [frequencyHz] falls outside
  /// [CalibrationCurve.validMinFrequencyHz]..[CalibrationCurve.validMaxFrequencyHz]
  /// or the curve is not [CalibrationCurve.isStructurallyValid].
  static double? interpolate(CalibrationCurve curve, double frequencyHz) {
    if (!curve.isStructurallyValid) return null;
    if (!frequencyHz.isFinite || frequencyHz <= 0) return null;
    if (frequencyHz < curve.validMinFrequencyHz ||
        frequencyHz > curve.validMaxFrequencyHz) {
      return null;
    }

    // Defensive: interpolate never trusts caller-supplied ordering, even
    // though CalibrationCurve.isStructurallyValid already requires
    // ascending order for a curve built through normal construction paths.
    final sorted = [...curve.points]
      ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));

    for (final p in sorted) {
      if (p.frequencyHz == frequencyHz) return p.correctionDb;
    }

    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (frequencyHz > a.frequencyHz && frequencyHz < b.frequencyHz) {
        final logF = _log10(frequencyHz);
        final logA = _log10(a.frequencyHz);
        final logB = _log10(b.frequencyHz);
        final t = (logF - logA) / (logB - logA);
        return a.correctionDb + t * (b.correctionDb - a.correctionDb);
      }
    }
    // Within [min,max] but not bracketed (shouldn't happen given the range
    // check above) — fail closed rather than guess.
    return null;
  }

  /// Applies [curve] to [rawPoints]. [rawPoints] is never mutated.
  ///
  /// A point whose frequency falls outside the curve's valid range is kept
  /// in [CalibrationApplicationResult.calibratedPoints] at its ORIGINAL
  /// (uncorrected) magnitude — coverage is recorded, but the point is never
  /// dropped and never extrapolated.
  static CalibrationApplicationResult apply({
    required List<MeasurementDataPoint> rawPoints,
    required CalibrationCurve curve,
  }) {
    if (!curve.isStructurallyValid) {
      return CalibrationApplicationResult(
        rawPoints: List.unmodifiable(rawPoints),
        calibratedPoints: List.unmodifiable(rawPoints.map(_copyPoint)),
        status: CalibrationStatus.invalid,
        curveChecksum: curve.checksum,
        warnings: const ['Calibration curve failed structural validation.'],
      );
    }
    if (rawPoints.isEmpty) {
      return CalibrationApplicationResult(
        rawPoints: const [],
        calibratedPoints: const [],
        status: CalibrationStatus.invalid,
        curveChecksum: curve.checksum,
        warnings: const ['No raw points to calibrate.'],
      );
    }

    final calibrated = <MeasurementDataPoint>[];
    var coveredCount = 0;
    double? coveredMin;
    double? coveredMax;

    for (final p in rawPoints) {
      final correction = interpolate(curve, p.frequencyHz);
      if (correction == null) {
        calibrated.add(_copyPoint(p));
        continue;
      }
      coveredCount++;
      coveredMin = (coveredMin == null || p.frequencyHz < coveredMin)
          ? p.frequencyHz
          : coveredMin;
      coveredMax = (coveredMax == null || p.frequencyHz > coveredMax)
          ? p.frequencyHz
          : coveredMax;
      calibrated.add(MeasurementDataPoint(
        frequencyHz: p.frequencyHz,
        magnitudeDb: p.magnitudeDb != null ? p.magnitudeDb! + correction : null,
        phaseDeg: p.phaseDeg,
        impedanceOhm: p.impedanceOhm,
        impedancePhaseDeg: p.impedancePhaseDeg,
      ));
    }

    final uncovered = rawPoints.length - coveredCount;
    final warnings = <String>[];
    final CalibrationStatus status;
    if (coveredCount == rawPoints.length) {
      status = CalibrationStatus.calibrated;
    } else if (coveredCount > 0) {
      status = CalibrationStatus.partiallyCalibrated;
      warnings.add('$uncovered of ${rawPoints.length} point(s) fell outside '
          'the calibration curve\'s valid range '
          '(${curve.validMinFrequencyHz.toStringAsFixed(0)}-'
          '${curve.validMaxFrequencyHz.toStringAsFixed(0)} Hz) and were left '
          'uncorrected.');
    } else {
      status = CalibrationStatus.partiallyCalibrated;
      warnings.add('No measurement point fell inside the calibration '
          'curve\'s valid range — 0 of ${rawPoints.length} corrected.');
    }

    return CalibrationApplicationResult(
      rawPoints: List.unmodifiable(rawPoints),
      calibratedPoints: List.unmodifiable(calibrated),
      status: status,
      coveredMinFrequencyHz: coveredMin,
      coveredMaxFrequencyHz: coveredMax,
      uncoveredCount: uncovered,
      curveChecksum: curve.checksum,
      warnings: List.unmodifiable(warnings),
    );
  }

  /// The no-calibration path: wraps [rawPoints] into a result whose
  /// calibratedPoints are numerically identical to rawPoints (a new list,
  /// never the same instance) under an explicit [status] the caller
  /// supplies — this function never decides between explicitlyUncalibrated
  /// and legacyUnknown itself, since that distinction depends on WHY there
  /// is no curve (a deliberate user choice vs. an old/decoded project),
  /// which only the caller knows.
  static CalibrationApplicationResult passthrough({
    required List<MeasurementDataPoint> rawPoints,
    required CalibrationStatus status,
  }) {
    assert(status == CalibrationStatus.explicitlyUncalibrated ||
        status == CalibrationStatus.legacyUnknown);
    return CalibrationApplicationResult(
      rawPoints: List.unmodifiable(rawPoints),
      calibratedPoints: List.unmodifiable(rawPoints.map(_copyPoint)),
      status: status,
      curveChecksum: null,
      warnings: const [],
    );
  }

  static MeasurementDataPoint _copyPoint(MeasurementDataPoint p) =>
      MeasurementDataPoint(
        frequencyHz: p.frequencyHz,
        magnitudeDb: p.magnitudeDb,
        phaseDeg: p.phaseDeg,
        impedanceOhm: p.impedanceOhm,
        impedancePhaseDeg: p.impedancePhaseDeg,
      );

  static double _log10(double v) => math.log(v) / math.ln10;
}
