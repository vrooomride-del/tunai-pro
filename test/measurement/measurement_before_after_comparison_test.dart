// Phase 3-D3B §10 — MeasurementBeforeAfterComparison foundation contract.
// Pure helper + type, unit-tested only — NOT wired into Closed Loop yet.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_before_after_comparison.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';

MeasurementCaptureProvenance _provenance({
  String projectId = 'proj-1',
  String microphoneProfileChecksum = 'chk-1',
  String? calibrationCurveChecksum = 'curve-1',
  String? calibrationAngle = 'zeroDegree',
  String inputDeviceSelectionIdentity = 'device:usb-1',
  String qualityPolicyVersion = 'provisional-1',
}) =>
    MeasurementCaptureProvenance(
      projectId: projectId,
      microphoneProfileChecksum: microphoneProfileChecksum,
      calibrationCurveChecksum: calibrationCurveChecksum,
      calibrationAngle: calibrationAngle,
      inputDeviceSelectionIdentity: inputDeviceSelectionIdentity,
      setupReadinessGenerationId: 'gen-1',
      qualityPolicyVersion: qualityPolicyVersion,
      actualSampleRate: 48000,
      actualChannelCount: 1,
      capturedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('comparable', () {
    test('identical identity -> comparable true', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: _provenance(),
        after: _provenance(),
      );
      expect(result.comparable, isTrue);
      expect(result.mismatches, isEmpty);
    });

    test('different policy version alone is still comparable', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: _provenance(qualityPolicyVersion: 'provisional-1'),
        after: _provenance(qualityPolicyVersion: 'provisional-2'),
      );
      expect(result.comparable, isTrue);
    });
  });

  group('missing provenance', () {
    test('null before -> missingBeforeProvenance', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: null,
        after: _provenance(),
      );
      expect(result.comparable, isFalse);
      expect(result.primaryMismatch!.code,
          MeasurementBeforeAfterMismatchCode.missingBeforeProvenance);
    });

    test('null after -> missingAfterProvenance', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: _provenance(),
        after: null,
      );
      expect(result.comparable, isFalse);
      expect(result.primaryMismatch!.code,
          MeasurementBeforeAfterMismatchCode.missingAfterProvenance);
    });
  });

  group('identity mismatches', () {
    test('different project -> differentProject', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: _provenance(projectId: 'proj-1'),
        after: _provenance(projectId: 'proj-2'),
      );
      expect(result.comparable, isFalse);
      expect(
          result
              .hasMismatch(MeasurementBeforeAfterMismatchCode.differentProject),
          isTrue);
    });

    test('different microphone profile -> differentMicrophoneProfile', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: _provenance(microphoneProfileChecksum: 'chk-A'),
        after: _provenance(microphoneProfileChecksum: 'chk-B'),
      );
      expect(result.comparable, isFalse);
      expect(
          result.hasMismatch(
              MeasurementBeforeAfterMismatchCode.differentMicrophoneProfile),
          isTrue);
    });

    test('different calibration curve -> differentCalibrationCurve', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: _provenance(calibrationCurveChecksum: 'curve-A'),
        after: _provenance(calibrationCurveChecksum: 'curve-B'),
      );
      expect(result.comparable, isFalse);
      expect(
          result.hasMismatch(
              MeasurementBeforeAfterMismatchCode.differentCalibrationCurve),
          isTrue);
    });

    test('different orientation -> differentCalibrationOrientation', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: _provenance(calibrationAngle: 'zeroDegree'),
        after: _provenance(calibrationAngle: 'ninetyDegree'),
      );
      expect(result.comparable, isFalse);
      expect(
          result.hasMismatch(MeasurementBeforeAfterMismatchCode
              .differentCalibrationOrientation),
          isTrue);
    });

    test('different input device -> differentInputDevice', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: _provenance(inputDeviceSelectionIdentity: 'device:usb-1'),
        after: _provenance(inputDeviceSelectionIdentity: 'device:usb-2'),
      );
      expect(result.comparable, isFalse);
      expect(
          result.hasMismatch(
              MeasurementBeforeAfterMismatchCode.differentInputDevice),
          isTrue);
    });

    test('multiple mismatches all collected, not just the first', () {
      final result = MeasurementBeforeAfterComparison.evaluate(
        before: _provenance(
            microphoneProfileChecksum: 'chk-A',
            inputDeviceSelectionIdentity: 'device:usb-1'),
        after: _provenance(
            microphoneProfileChecksum: 'chk-B',
            inputDeviceSelectionIdentity: 'device:usb-2'),
      );
      expect(result.comparable, isFalse);
      expect(result.mismatches.length, 2);
    });
  });
}
