// Phase 3-B — calibration_applicator.dart pure interpolation/application
// tests.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_applicator.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart'
    show MeasurementDataPoint;

CalibrationCurve _curve() {
  const points = [
    CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
    CalibrationPoint(frequencyHz: 100, correctionDb: -1.0),
    CalibrationPoint(frequencyHz: 20000, correctionDb: 2.0),
  ];
  return CalibrationCurve(
    points: points,
    validMinFrequencyHz: 20,
    validMaxFrequencyHz: 20000,
    sourceIdentity: 'test',
    checksum: CalibrationCurve.checksumFor(points),
  );
}

void main() {
  group('CalibrationApplicator.interpolate', () {
    test('returns the exact point value at a declared frequency', () {
      expect(CalibrationApplicator.interpolate(_curve(), 100), -1.0);
    });

    test(
        'log-frequency-linear-dB interpolation matches hand-calculated '
        'value between two points', () {
      // Between 20Hz(0.5dB) and 100Hz(-1.0dB), at 50Hz:
      // t = (log10(50)-log10(20)) / (log10(100)-log10(20))
      final t = (math.log(50 / 20)) / (math.log(100 / 20));
      final expected = 0.5 + t * (-1.0 - 0.5);
      final actual = CalibrationApplicator.interpolate(_curve(), 50);
      expect(actual, closeTo(expected, 1e-9));
    });

    test('returns null below the valid range (never extrapolates)', () {
      expect(CalibrationApplicator.interpolate(_curve(), 10), isNull);
    });

    test('returns null above the valid range (never extrapolates)', () {
      expect(CalibrationApplicator.interpolate(_curve(), 30000), isNull);
    });

    test('returns null for a structurally invalid curve', () {
      const invalid = CalibrationCurve(
        points: [CalibrationPoint(frequencyHz: 100, correctionDb: 0)],
        validMinFrequencyHz: 100,
        validMaxFrequencyHz: 100,
        sourceIdentity: 'x',
        checksum: 'x',
      );
      expect(CalibrationApplicator.interpolate(invalid, 100), isNull);
    });

    test('returns null for non-finite or non-positive frequency', () {
      expect(CalibrationApplicator.interpolate(_curve(), double.nan), isNull);
      expect(CalibrationApplicator.interpolate(_curve(), 0), isNull);
      expect(CalibrationApplicator.interpolate(_curve(), -50), isNull);
    });
  });

  group('CalibrationApplicator.apply — full coverage', () {
    test('every point in range is corrected, status is calibrated', () {
      final raw = [
        const MeasurementDataPoint(frequencyHz: 20, magnitudeDb: 70.0),
        const MeasurementDataPoint(frequencyHz: 100, magnitudeDb: 68.0),
        const MeasurementDataPoint(frequencyHz: 20000, magnitudeDb: 60.0),
      ];
      final result =
          CalibrationApplicator.apply(rawPoints: raw, curve: _curve());
      expect(result.status, CalibrationStatus.calibrated);
      expect(result.calibratedPoints[0].magnitudeDb, closeTo(70.5, 1e-9));
      expect(result.calibratedPoints[1].magnitudeDb, closeTo(67.0, 1e-9));
      expect(result.calibratedPoints[2].magnitudeDb, closeTo(62.0, 1e-9));
      expect(result.uncoveredCount, 0);
      expect(result.curveChecksum, _curve().checksum);
    });

    test('rawPoints in the result is the original input, unmutated', () {
      final raw = [
        const MeasurementDataPoint(frequencyHz: 100, magnitudeDb: 68.0),
      ];
      final result =
          CalibrationApplicator.apply(rawPoints: raw, curve: _curve());
      expect(result.rawPoints[0].magnitudeDb, 68.0);
      expect(result.rawPoints, isNot(same(result.calibratedPoints)));
    });
  });

  group('CalibrationApplicator.apply — partial coverage', () {
    test(
        'out-of-range points are kept uncorrected, status is '
        'partiallyCalibrated', () {
      final raw = [
        const MeasurementDataPoint(
            frequencyHz: 5, magnitudeDb: 70.0), // below range
        const MeasurementDataPoint(
            frequencyHz: 100, magnitudeDb: 68.0), // in range
      ];
      final result =
          CalibrationApplicator.apply(rawPoints: raw, curve: _curve());
      expect(result.status, CalibrationStatus.partiallyCalibrated);
      expect(result.calibratedPoints[0].magnitudeDb, 70.0); // unchanged
      expect(result.calibratedPoints[1].magnitudeDb, closeTo(67.0, 1e-9));
      expect(result.uncoveredCount, 1);
      expect(result.warnings, isNotEmpty);
    });

    test(
        'zero coverage still returns partiallyCalibrated (never '
        '"calibrated" with 0 corrected points)', () {
      final raw = [
        const MeasurementDataPoint(frequencyHz: 5, magnitudeDb: 70.0),
      ];
      final result =
          CalibrationApplicator.apply(rawPoints: raw, curve: _curve());
      expect(result.status, CalibrationStatus.partiallyCalibrated);
      expect(result.uncoveredCount, 1);
    });
  });

  group('CalibrationApplicator.apply — invalid inputs', () {
    test(
        'a structurally invalid curve produces status=invalid and passes '
        'points through unchanged', () {
      const invalidCurve = CalibrationCurve(
        points: [CalibrationPoint(frequencyHz: 100, correctionDb: 0)],
        validMinFrequencyHz: 100,
        validMaxFrequencyHz: 100,
        sourceIdentity: 'x',
        checksum: 'x',
      );
      final raw = [
        const MeasurementDataPoint(frequencyHz: 100, magnitudeDb: 68.0)
      ];
      final result =
          CalibrationApplicator.apply(rawPoints: raw, curve: invalidCurve);
      expect(result.status, CalibrationStatus.invalid);
      expect(result.calibratedPoints[0].magnitudeDb, 68.0);
    });

    test('empty rawPoints produces status=invalid with no points', () {
      final result =
          CalibrationApplicator.apply(rawPoints: const [], curve: _curve());
      expect(result.status, CalibrationStatus.invalid);
      expect(result.calibratedPoints, isEmpty);
    });
  });

  group('CalibrationApplicator.passthrough', () {
    test(
        'produces numerically identical points under '
        'explicitlyUncalibrated, with no checksum', () {
      final raw = [
        const MeasurementDataPoint(frequencyHz: 100, magnitudeDb: 68.0)
      ];
      final result = CalibrationApplicator.passthrough(
        rawPoints: raw,
        status: CalibrationStatus.explicitlyUncalibrated,
      );
      expect(result.status, CalibrationStatus.explicitlyUncalibrated);
      expect(result.calibratedPoints[0].magnitudeDb, 68.0);
      expect(result.calibratedPoints, isNot(same(result.rawPoints)));
      expect(result.curveChecksum, isNull);
    });

    test('also accepts legacyUnknown', () {
      final result = CalibrationApplicator.passthrough(
        rawPoints: const [],
        status: CalibrationStatus.legacyUnknown,
      );
      expect(result.status, CalibrationStatus.legacyUnknown);
    });
  });
}
