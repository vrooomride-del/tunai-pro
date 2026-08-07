// Phase 3-D3A-1B — pure presentation-string contract tests.
//
// Locks in the exact Korean UI copy for every MeasurementCaptureBlockerCode /
// MeasurementCaptureWarningCode / MeasurementCaptureRemediation, and the
// systemDefaultUnverified label's forbidden-word guarantee. This is the
// single source the Capture UI draws strings from (measurement_capture_ui.dart
// widgets never hardcode these) — this file is what actually pins the copy.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_gate_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_presentation.dart';

void main() {
  group('measurementCaptureBlockerText — exact Phase 3-D3A-1B copy', () {
    const expected = {
      MeasurementCaptureBlockerCode.noProject: '프로젝트를 먼저 열어주세요.',
      MeasurementCaptureBlockerCode.noMicrophoneProfile: '측정 마이크를 선택하세요.',
      MeasurementCaptureBlockerCode.noInputDeviceSelected: '입력 장치를 선택하세요.',
      MeasurementCaptureBlockerCode.inputDeviceUnavailable:
          '선택한 입력 장치를 찾을 수 없습니다.',
      MeasurementCaptureBlockerCode.microphonePermissionDenied:
          '마이크 접근 권한이 필요합니다.',
      MeasurementCaptureBlockerCode.invalidCalibration: '마이크 보정 정보를 확인하세요.',
      MeasurementCaptureBlockerCode.legacyUnknownCalibration:
          '마이크 보정 상태를 다시 확인하세요.',
      MeasurementCaptureBlockerCode.setupNotChecked: '측정 준비 확인을 먼저 실행하세요.',
      MeasurementCaptureBlockerCode.setupExpired: '측정 준비 확인이 만료되었습니다.',
      MeasurementCaptureBlockerCode.setupProfileMismatch:
          '마이크 설정이 변경되었습니다. 준비 확인을 다시 실행하세요.',
      MeasurementCaptureBlockerCode.setupCalibrationCurveMismatch:
          '마이크 설정이 변경되었습니다. 준비 확인을 다시 실행하세요.',
      MeasurementCaptureBlockerCode.setupOrientationMismatch:
          '마이크 설정이 변경되었습니다. 준비 확인을 다시 실행하세요.',
      MeasurementCaptureBlockerCode.setupInputDeviceMismatch:
          '입력 장치가 변경되었습니다. 준비 확인을 다시 실행하세요.',
      MeasurementCaptureBlockerCode.setupPolicyVersionMismatch:
          '측정 준비 기준이 변경되었습니다. 다시 확인하세요.',
      MeasurementCaptureBlockerCode.setupSampleRateMismatch: '녹음 형식이 예상과 다릅니다.',
      MeasurementCaptureBlockerCode.setupChannelMismatch: '녹음 채널 구성이 예상과 다릅니다.',
      MeasurementCaptureBlockerCode.setupQuality: '측정 환경 품질을 다시 확인하세요.',
    };

    for (final entry in expected.entries) {
      test(entry.key.name, () {
        expect(measurementCaptureBlockerText(entry.key), entry.value);
      });
    }

    // Codes not explicitly enumerated in the Phase 3-D3A-1B spec (they were
    // added to the gate after the spec was written) still resolve to
    // non-empty, distinct-enough copy rather than throwing.
    test('setupNotReady resolves to non-empty copy', () {
      expect(
        measurementCaptureBlockerText(
            MeasurementCaptureBlockerCode.setupNotReady),
        isNotEmpty,
      );
    });
    test('setupProjectMismatch resolves to non-empty copy', () {
      expect(
        measurementCaptureBlockerText(
            MeasurementCaptureBlockerCode.setupProjectMismatch),
        isNotEmpty,
      );
    });

    test('every MeasurementCaptureBlockerCode has mapped text', () {
      for (final code in MeasurementCaptureBlockerCode.values) {
        expect(measurementCaptureBlockerText(code), isNotEmpty,
            reason: code.name);
      }
    });
  });

  group('measurementCaptureWarningText — exact Phase 3-D3A-1B copy', () {
    test('explicitlyUncalibrated', () {
      expect(
        measurementCaptureWarningText(
            MeasurementCaptureWarningCode.explicitlyUncalibrated),
        '마이크 보정 없이 측정할 수 있지만 결과 정확도가 낮아질 수 있습니다.',
      );
    });
    test('partialCalibration', () {
      expect(
        measurementCaptureWarningText(
            MeasurementCaptureWarningCode.partialCalibration),
        '보정 파일이 측정 대역 전체를 포함하지 않습니다.',
      );
    });
    test('setupQuality', () {
      expect(
        measurementCaptureWarningText(
            MeasurementCaptureWarningCode.setupQuality),
        '측정 환경이 권장 범위에 가깝습니다. 결과 정확도가 낮아질 수 있습니다.',
      );
    });
  });

  test('warning confirm label is exactly "경고를 확인하고 측정"', () {
    expect(kMeasurementCaptureWarningConfirmLabel, '경고를 확인하고 측정');
  });

  group('measurementCaptureRemediationLabel — every remediation has a CTA', () {
    test('every MeasurementCaptureRemediation has non-empty label', () {
      for (final r in MeasurementCaptureRemediation.values) {
        expect(measurementCaptureRemediationLabel(r), isNotEmpty,
            reason: r.name);
      }
    });
  });

  group('systemDefaultUnverified display — forbidden-word guarantee', () {
    const forbidden = ['Verified', 'Connected', 'Available', 'Confirmed'];

    test('label is exactly "System Default Input"', () {
      expect(kMeasurementCaptureSystemDefaultLabel, 'System Default Input');
    });

    test('subtext contains none of the forbidden words', () {
      for (final word in forbidden) {
        expect(kMeasurementCaptureSystemDefaultSubtext.contains(word), isFalse,
            reason: 'subtext must never contain "$word"');
      }
    });

    test('label contains none of the forbidden words beyond "Default"', () {
      for (final word in forbidden) {
        expect(kMeasurementCaptureSystemDefaultLabel.contains(word), isFalse,
            reason: 'label must never contain "$word"');
      }
    });
  });

  group('remediation<->blocker mapping stays consistent with the gate', () {
    test('blocker code remediation resolves to a labeled CTA for every code',
        () {
      for (final code in MeasurementCaptureBlockerCode.values) {
        final remediation = code.remediation;
        expect(measurementCaptureRemediationLabel(remediation), isNotEmpty,
            reason: code.name);
      }
    });
  });
}
