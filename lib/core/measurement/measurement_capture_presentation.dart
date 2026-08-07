// ── TUNAI PRO Phase 3-D3A-1B — Capture UI presentation strings ──────────────
//
// ONE pure mapping from [MeasurementCaptureBlockerCode] /
// [MeasurementCaptureWarningCode] / [MeasurementCaptureRemediation] to the
// exact Korean UI copy this phase specifies. The gate's own
// [MeasurementCaptureBlocker.message] carries chain-evaluation text (used by
// controllers/tests); this file is the single place the Capture UI itself
// draws user-facing strings from, so no widget ever hardcodes or duplicates
// a blocker/warning/remediation string.

library;

import 'measurement_capture_gate_types.dart';
import 'measurement_preview_acceptance_gate.dart';

/// Exact Phase 3-D3A-1B blocker copy, keyed by [MeasurementCaptureBlockerCode].
String measurementCaptureBlockerText(MeasurementCaptureBlockerCode code) {
  switch (code) {
    case MeasurementCaptureBlockerCode.noProject:
      return '프로젝트를 먼저 열어주세요.';
    case MeasurementCaptureBlockerCode.noMicrophoneProfile:
      return '측정 마이크를 선택하세요.';
    case MeasurementCaptureBlockerCode.noInputDeviceSelected:
      return '입력 장치를 선택하세요.';
    case MeasurementCaptureBlockerCode.inputDeviceUnavailable:
      return '선택한 입력 장치를 찾을 수 없습니다.';
    case MeasurementCaptureBlockerCode.microphonePermissionDenied:
      return '마이크 접근 권한이 필요합니다.';
    case MeasurementCaptureBlockerCode.invalidCalibration:
      return '마이크 보정 정보를 확인하세요.';
    case MeasurementCaptureBlockerCode.legacyUnknownCalibration:
      return '마이크 보정 상태를 다시 확인하세요.';
    case MeasurementCaptureBlockerCode.setupNotChecked:
      return '측정 준비 확인을 먼저 실행하세요.';
    case MeasurementCaptureBlockerCode.setupNotReady:
      return '측정 준비 확인이 실패했습니다. 다시 확인하세요.';
    case MeasurementCaptureBlockerCode.setupExpired:
      return '측정 준비 확인이 만료되었습니다.';
    case MeasurementCaptureBlockerCode.setupProjectMismatch:
    case MeasurementCaptureBlockerCode.setupProfileMismatch:
    case MeasurementCaptureBlockerCode.setupCalibrationCurveMismatch:
    case MeasurementCaptureBlockerCode.setupOrientationMismatch:
      return '마이크 설정이 변경되었습니다. 준비 확인을 다시 실행하세요.';
    case MeasurementCaptureBlockerCode.setupInputDeviceMismatch:
      return '입력 장치가 변경되었습니다. 준비 확인을 다시 실행하세요.';
    case MeasurementCaptureBlockerCode.setupPolicyVersionMismatch:
      return '측정 준비 기준이 변경되었습니다. 다시 확인하세요.';
    case MeasurementCaptureBlockerCode.setupSampleRateMismatch:
      return '녹음 형식이 예상과 다릅니다.';
    case MeasurementCaptureBlockerCode.setupChannelMismatch:
      return '녹음 채널 구성이 예상과 다릅니다.';
    case MeasurementCaptureBlockerCode.setupQuality:
      return '측정 환경 품질을 다시 확인하세요.';
  }
}

/// Exact Phase 3-D3A-1B warning copy, keyed by [MeasurementCaptureWarningCode].
String measurementCaptureWarningText(MeasurementCaptureWarningCode code) {
  switch (code) {
    case MeasurementCaptureWarningCode.explicitlyUncalibrated:
      return '마이크 보정 없이 측정할 수 있지만 결과 정확도가 낮아질 수 있습니다.';
    case MeasurementCaptureWarningCode.partialCalibration:
      return '보정 파일이 측정 대역 전체를 포함하지 않습니다.';
    case MeasurementCaptureWarningCode.setupQuality:
      return '측정 환경이 권장 범위에 가깝습니다. 결과 정확도가 낮아질 수 있습니다.';
  }
}

/// CTA label for the button that triggers a given [MeasurementCaptureRemediation].
String measurementCaptureRemediationLabel(
    MeasurementCaptureRemediation remediation) {
  switch (remediation) {
    case MeasurementCaptureRemediation.createOrOpenProject:
      return '프로젝트 열기';
    case MeasurementCaptureRemediation.manageMicrophone:
      return '마이크 관리';
    case MeasurementCaptureRemediation.selectInputDevice:
      return '입력 장치 선택';
    case MeasurementCaptureRemediation.checkInputDeviceAgain:
      return '입력 장치 다시 확인';
    case MeasurementCaptureRemediation.grantMicrophonePermission:
      return '권한 허용';
    case MeasurementCaptureRemediation.runSetupCheck:
      return '준비 확인 실행';
  }
}

/// Phase 3-D3A-2 — the single Accept-time provenance-gate presentation
/// helper: every actual-format blocker gets the "format mismatch" copy,
/// every other blocker (missing/stale identity) gets the general "settings
/// changed, re-measure" copy. No UI widget composes this text itself.
String measurementPreviewAcceptanceBlockerText(
    MeasurementPreviewAcceptanceBlockerCode code) {
  switch (code) {
    case MeasurementPreviewAcceptanceBlockerCode.actualSampleRateMismatch:
    case MeasurementPreviewAcceptanceBlockerCode.actualChannelCountMismatch:
      return '실제 녹음 형식이 예상과 다릅니다. 측정 준비를 다시 확인해 주세요.';
    case MeasurementPreviewAcceptanceBlockerCode.missingProvenance:
    case MeasurementPreviewAcceptanceBlockerCode.projectChanged:
    case MeasurementPreviewAcceptanceBlockerCode.microphoneProfileChanged:
    case MeasurementPreviewAcceptanceBlockerCode.calibrationCurveChanged:
    case MeasurementPreviewAcceptanceBlockerCode.calibrationOrientationChanged:
    case MeasurementPreviewAcceptanceBlockerCode.inputDeviceChanged:
    case MeasurementPreviewAcceptanceBlockerCode.setupGenerationChanged:
    case MeasurementPreviewAcceptanceBlockerCode.qualityPolicyChanged:
      return '측정 설정이 변경되었습니다. 다시 측정해 주세요.';
  }
}

/// Confirm-button label for the warning acknowledgement dialog.
const String kMeasurementCaptureWarningConfirmLabel = '경고를 확인하고 측정';

/// The exact system-default input label + explanatory subtext (Phase
/// 3-D3A-1B §7). Deliberately contains none of the forbidden words
/// ("Verified", "Connected", "Available", "Confirmed") — a system-default
/// selection is never preflighted past "unverified" (see
/// [measurement_capture_gate.dart]'s doc comment on why).
const String kMeasurementCaptureSystemDefaultLabel = 'System Default Input';
const String kMeasurementCaptureSystemDefaultSubtext =
    '실제 입력 장치는 녹음 시작 시 최종 확인됩니다.';
