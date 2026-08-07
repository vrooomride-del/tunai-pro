// ── TUNAI PRO Phase 3-D3C-2 §12 — Room Before/After provenance UI copy ──────
//
// ONE pure mapping from the typed comparison blocker/warning codes to the
// exact Korean copy the Room Closed Loop UI shows. Widgets never compare
// enum names or match on strings — they render what this returns.
//
// Room-only: the Factory measurement UI has its own separate copy and must
// not use these strings.

library;

import 'measurement_before_after_comparison.dart';

/// What the user should do next when a Before/After comparison is blocked.
/// Both actions already exist in the app — no new navigation is introduced.
enum RoomBeforeAfterRemediation {
  /// Re-run the After measurement (the usual fix once the chain is right).
  measureAgain,

  /// The measurement chain itself needs attention first.
  checkMeasurementSetup,
}

String roomBeforeAfterBlockerText(MeasurementBeforeAfterMismatchCode code) {
  switch (code) {
    case MeasurementBeforeAfterMismatchCode.differentMicrophoneProfile:
      return 'Before와 After가 서로 다른 측정 마이크로 측정되었습니다.';
    case MeasurementBeforeAfterMismatchCode.differentCalibrationCurve:
      return 'Before와 After의 마이크 보정 설정이 다릅니다.';
    case MeasurementBeforeAfterMismatchCode.differentCalibrationOrientation:
      return 'Before와 After의 마이크 방향 설정이 다릅니다.';
    case MeasurementBeforeAfterMismatchCode.differentInputDevice:
      return 'Before와 After의 입력 장치가 다릅니다.';
    case MeasurementBeforeAfterMismatchCode.differentProject:
      return 'Before와 After가 서로 다른 프로젝트에서 측정되었습니다.';
    case MeasurementBeforeAfterMismatchCode.missingBeforeProvenance:
    case MeasurementBeforeAfterMismatchCode.missingAfterProvenance:
    case MeasurementBeforeAfterMismatchCode.missingBeforeQuality:
    case MeasurementBeforeAfterMismatchCode.missingAfterQuality:
    case MeasurementBeforeAfterMismatchCode.nonLiveBefore:
    case MeasurementBeforeAfterMismatchCode.nonLiveAfter:
      return 'Before/After 측정의 품질 정보를 확인할 수 없습니다. 다시 측정해 주세요.';
    case MeasurementBeforeAfterMismatchCode.invalidBeforeFormat:
    case MeasurementBeforeAfterMismatchCode.invalidAfterFormat:
      return 'Before와 After의 녹음 형식이 일치하지 않습니다.';
  }
}

String roomBeforeAfterWarningText(MeasurementBeforeAfterWarningCode code) {
  switch (code) {
    case MeasurementBeforeAfterWarningCode.qualityPolicyVersionMismatch:
      return 'Before와 After가 서로 다른 측정 품질 기준으로 확인되었습니다.';
    case MeasurementBeforeAfterWarningCode.bothExplicitlyUncalibrated:
      return '보정되지 않은 마이크로 측정된 결과입니다.';
  }
}

/// A chain-identity mismatch is fixed by measuring again (the setup itself is
/// fine — the user simply used a different mic/device between the two
/// measurements); missing or non-live provenance means the measurement chain
/// needs checking first.
RoomBeforeAfterRemediation roomBeforeAfterRemediation(
    MeasurementBeforeAfterMismatchCode code) {
  switch (code) {
    case MeasurementBeforeAfterMismatchCode.missingBeforeProvenance:
    case MeasurementBeforeAfterMismatchCode.missingAfterProvenance:
    case MeasurementBeforeAfterMismatchCode.missingBeforeQuality:
    case MeasurementBeforeAfterMismatchCode.missingAfterQuality:
    case MeasurementBeforeAfterMismatchCode.nonLiveBefore:
    case MeasurementBeforeAfterMismatchCode.nonLiveAfter:
    case MeasurementBeforeAfterMismatchCode.invalidBeforeFormat:
    case MeasurementBeforeAfterMismatchCode.invalidAfterFormat:
      return RoomBeforeAfterRemediation.checkMeasurementSetup;
    case MeasurementBeforeAfterMismatchCode.differentProject:
    case MeasurementBeforeAfterMismatchCode.differentMicrophoneProfile:
    case MeasurementBeforeAfterMismatchCode.differentCalibrationCurve:
    case MeasurementBeforeAfterMismatchCode.differentCalibrationOrientation:
    case MeasurementBeforeAfterMismatchCode.differentInputDevice:
      return RoomBeforeAfterRemediation.measureAgain;
  }
}

String roomBeforeAfterRemediationLabel(RoomBeforeAfterRemediation r) =>
    switch (r) {
      RoomBeforeAfterRemediation.measureAgain => '다시 측정하기',
      RoomBeforeAfterRemediation.checkMeasurementSetup => '측정 준비 확인',
    };
