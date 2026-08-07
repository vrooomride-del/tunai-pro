// Phase 3-B — calibration_readiness.dart pure gate-input tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_readiness.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';

void main() {
  group('CalibrationReadiness.fromCalibrationStatus', () {
    test('calibrated + checksum -> calibrated level with a claimable ref', () {
      final r = CalibrationReadiness.fromCalibrationStatus(
        status: CalibrationStatus.calibrated,
        calibrationCurveChecksum: 'abc123',
      );
      expect(r.level, CalibrationReadinessLevel.calibrated);
      expect(r.calibrationRef, 'abc123');
      expect(r.canClaimCalibrationMetric, isTrue);
    });

    test('calibrated without a checksum demotes to unknown, never claims', () {
      final r = CalibrationReadiness.fromCalibrationStatus(
        status: CalibrationStatus.calibrated,
      );
      expect(r.level, CalibrationReadinessLevel.unknown);
      expect(r.calibrationRef, isNull);
      expect(r.canClaimCalibrationMetric, isFalse);
      expect(r.reasons, isNotEmpty);
    });

    test(
        'partiallyCalibrated + checksum -> partiallyCalibrated level, '
        'still claimable', () {
      final r = CalibrationReadiness.fromCalibrationStatus(
        status: CalibrationStatus.partiallyCalibrated,
        calibrationCurveChecksum: 'abc123',
      );
      expect(r.level, CalibrationReadinessLevel.partiallyCalibrated);
      expect(r.canClaimCalibrationMetric, isTrue);
    });

    test('partiallyCalibrated without a checksum demotes to unknown', () {
      final r = CalibrationReadiness.fromCalibrationStatus(
        status: CalibrationStatus.partiallyCalibrated,
      );
      expect(r.level, CalibrationReadinessLevel.unknown);
      expect(r.canClaimCalibrationMetric, isFalse);
    });

    test(
        'explicitlyUncalibrated -> uncalibrated level, never claimable '
        'even with a stray checksum', () {
      final r = CalibrationReadiness.fromCalibrationStatus(
        status: CalibrationStatus.explicitlyUncalibrated,
        calibrationCurveChecksum: 'should-be-ignored',
      );
      expect(r.level, CalibrationReadinessLevel.uncalibrated);
      expect(r.canClaimCalibrationMetric, isFalse);
    });

    test('legacyUnknown -> unknown level, never claimable', () {
      final r = CalibrationReadiness.fromCalibrationStatus(
        status: CalibrationStatus.legacyUnknown,
      );
      expect(r.level, CalibrationReadinessLevel.unknown);
      expect(r.canClaimCalibrationMetric, isFalse);
    });

    test('invalid -> unknown level, never claimable', () {
      final r = CalibrationReadiness.fromCalibrationStatus(
        status: CalibrationStatus.invalid,
        calibrationCurveChecksum: 'should-be-ignored',
      );
      expect(r.level, CalibrationReadinessLevel.unknown);
      expect(r.canClaimCalibrationMetric, isFalse);
    });
  });

  group('CalibrationReadiness.evidenceCalibrationFields', () {
    test('returns available:true with the ref only when claimable', () {
      final r = CalibrationReadiness.fromCalibrationStatus(
        status: CalibrationStatus.calibrated,
        calibrationCurveChecksum: 'abc123',
      );
      final fields = CalibrationReadiness.evidenceCalibrationFields(r);
      expect(fields.available, isTrue);
      expect(fields.ref, 'abc123');
    });

    test(
        'never returns available:true with a null ref — satisfies '
        'MeasurementCaptureEvidence\'s own invariant by construction', () {
      for (final status in CalibrationStatus.values) {
        final r = CalibrationReadiness.fromCalibrationStatus(status: status);
        final fields = CalibrationReadiness.evidenceCalibrationFields(r);
        if (fields.available) {
          expect(fields.ref, isNotNull,
              reason: 'status=$status produced available=true with a null '
                  'ref');
        }
      }
    });

    test('returns available:false, ref:null for uncalibrated/unknown', () {
      final r = CalibrationReadiness.fromCalibrationStatus(
        status: CalibrationStatus.explicitlyUncalibrated,
      );
      final fields = CalibrationReadiness.evidenceCalibrationFields(r);
      expect(fields.available, isFalse);
      expect(fields.ref, isNull);
    });
  });
}
