// Phase 3-D3B — CalibrationFrequencyCoverage pure contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_frequency_coverage.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';

const _points = [
  CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
  CalibrationPoint(frequencyHz: 300, correctionDb: -0.5),
  CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
];

CalibrationCurve _curve({
  double minHz = 10,
  double maxHz = 22000,
}) =>
    CalibrationCurve(
      points: _points,
      angle: CalibrationAngle.zeroDegree,
      validMinFrequencyHz: minHz,
      validMaxFrequencyHz: maxHz,
      sourceIdentity: 'test',
      checksum: CalibrationCurve.checksumFor(_points),
    );

void main() {
  group('fully calibrated', () {
    test('curve fully covers 20-300 -> PASS', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.calibrated,
          calibrationCurve: _curve(minHz: 10, maxHz: 22000),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isTrue,
      );
    });

    test('exact endpoints (curve range == required range) -> PASS', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.calibrated,
          calibrationCurve: _curve(minHz: 20, maxHz: 300),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isTrue,
      );
    });

    test('curve min just above 20 -> FAIL', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.calibrated,
          calibrationCurve: _curve(minHz: 20.01, maxHz: 22000),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isFalse,
      );
    });

    test('curve max just below 300 -> FAIL', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.calibrated,
          calibrationCurve: _curve(minHz: 10, maxHz: 299.99),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isFalse,
      );
    });
  });

  group('partially calibrated', () {
    test('partial status but curve covers 20-300 -> PASS', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.partiallyCalibrated,
          calibrationCurve: _curve(minHz: 15, maxHz: 500),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isTrue,
      );
    });

    test('partial status AND curve does not cover 20-300 -> FAIL', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.partiallyCalibrated,
          calibrationCurve: _curve(minHz: 100, maxHz: 20000),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isFalse,
      );
    });
  });

  group('always FAIL statuses', () {
    test('explicitlyUncalibrated -> FAIL even with a wide curve', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.explicitlyUncalibrated,
          calibrationCurve: _curve(minHz: 1, maxHz: 40000),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isFalse,
      );
    });

    test('legacyUnknown -> FAIL', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.legacyUnknown,
          calibrationCurve: _curve(minHz: 1, maxHz: 40000),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isFalse,
      );
    });

    test('invalid -> FAIL', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.invalid,
          calibrationCurve: _curve(minHz: 1, maxHz: 40000),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isFalse,
      );
    });

    test('curve missing -> FAIL even with calibrated status', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.calibrated,
          calibrationCurve: null,
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isFalse,
      );
    });

    test('structurally invalid curve -> FAIL', () {
      const invalidCurve = CalibrationCurve(
        points: [CalibrationPoint(frequencyHz: 20, correctionDb: 0)],
        angle: CalibrationAngle.zeroDegree,
        validMinFrequencyHz: 10,
        validMaxFrequencyHz: 22000,
        sourceIdentity: 'test',
        checksum: 'x',
      );
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.calibrated,
          calibrationCurve: invalidCurve,
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isFalse,
      );
    });
  });

  group('no extrapolation outside the required range', () {
    test('coverage far outside 20-300 does not matter to this gate', () {
      // A curve covering ONLY 20-300 exactly (nothing beyond) still PASSes
      // — the gate never asks about frequencies outside its own range.
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.calibrated,
          calibrationCurve: _curve(minHz: 20, maxHz: 300),
          minFrequencyHz: 20,
          maxFrequencyHz: 300,
        ),
        isTrue,
      );
    });
  });
}
