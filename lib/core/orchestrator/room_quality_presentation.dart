// ── TUNAI PRO Phase 3-D3B — Room quality gate presentation strings ──────────
//
// ONE pure mapping from the individual and pair quality blocker codes to the
// exact Korean copy this phase specifies. No UI widget composes this text
// itself, and no string comparison is ever used to decide remediation.
library;

import 'room_before_pair_quality_gate.dart';
import 'room_measurement_quality_gate.dart';

String roomMeasurementQualityBlockerText(
    RoomMeasurementQualityBlockerCode code) {
  switch (code) {
    case RoomMeasurementQualityBlockerCode.missingMeasurement:
      return '측정이 없습니다.';
    case RoomMeasurementQualityBlockerCode.missingQualitySnapshot:
      return '측정의 품질 정보가 없습니다.';
    case RoomMeasurementQualityBlockerCode.projectMismatch:
      return '다른 프로젝트에서 캡처된 측정입니다.';
    case RoomMeasurementQualityBlockerCode.missingMicrophoneProfile:
      return '측정 마이크 정보가 없습니다.';
    case RoomMeasurementQualityBlockerCode.missingInputDevice:
      return '입력 장치 정보가 없습니다.';
    case RoomMeasurementQualityBlockerCode.unsupportedPolicyVersion:
      return '측정 품질 기준 버전이 다릅니다.';
    case RoomMeasurementQualityBlockerCode.actualSampleRateMismatch:
      return '실제 녹음 샘플레이트가 예상과 다릅니다.';
    case RoomMeasurementQualityBlockerCode.actualChannelCountMismatch:
      return '실제 녹음 채널 수가 예상과 다릅니다.';
    case RoomMeasurementQualityBlockerCode.clipping:
      return '측정 준비 확인에서 클리핑이 감지되었습니다.';
    case RoomMeasurementQualityBlockerCode.calibrationCoverageInsufficient:
      return '마이크 보정이 20–300 Hz를 포함하지 않습니다.';
  }
}

String _sideBlockerText(
    String sideLabel, RoomMeasurementQualityBlockerCode? code) {
  if (code == null) return '$sideLabel 측정의 품질 확인에 실패했습니다.';
  switch (code) {
    case RoomMeasurementQualityBlockerCode.missingMeasurement:
      return '$sideLabel 측정이 없습니다.';
    case RoomMeasurementQualityBlockerCode.missingQualitySnapshot:
      return '$sideLabel 측정의 품질 정보가 없습니다.';
    case RoomMeasurementQualityBlockerCode.calibrationCoverageInsufficient:
      // Matches the spec's exact example copy verbatim (no side prefix).
      return '마이크 보정이 20–300 Hz를 포함하지 않습니다.';
    default:
      return '$sideLabel ${roomMeasurementQualityBlockerText(code)}';
  }
}

String roomBeforePairQualityBlockerText(
    RoomBeforePairQualityGateResult result) {
  final blocker = result.primaryBlocker;
  if (blocker == null) return '';
  switch (blocker.code) {
    case RoomBeforePairQualityBlockerCode.leftQualityFailed:
      return _sideBlockerText('왼쪽', result.leftResult.primaryBlocker?.code);
    case RoomBeforePairQualityBlockerCode.rightQualityFailed:
      return _sideBlockerText('오른쪽', result.rightResult.primaryBlocker?.code);
    case RoomBeforePairQualityBlockerCode.differentProject:
      return '좌우 측정의 프로젝트가 다릅니다.';
    case RoomBeforePairQualityBlockerCode.differentMicrophoneProfile:
      return '좌우 측정에 서로 다른 마이크가 사용되었습니다.';
    case RoomBeforePairQualityBlockerCode.differentCalibrationCurve:
    case RoomBeforePairQualityBlockerCode.differentCalibrationOrientation:
      return '좌우 측정의 마이크 보정 설정이 다릅니다.';
    case RoomBeforePairQualityBlockerCode.differentInputDevice:
      return '좌우 측정의 입력 장치가 다릅니다.';
    case RoomBeforePairQualityBlockerCode.differentPolicyVersion:
      return '좌우 측정의 품질 기준 버전이 다릅니다.';
  }
}

/// What the UI should do about the pair gate's primary blocker — typed, no
/// string matching. `null` means no remediation action makes sense (e.g. a
/// left/right mismatch is resolved by re-measuring, not by any single CTA).
enum RoomBeforePairQualityRemediationKind {
  /// Missing measurement/quality entirely — go capture it (existing Measure
  /// tab).
  goToMeasureTab,

  /// Calibration coverage problem — go fix the microphone's calibration.
  manageMicrophone,
}

RoomBeforePairQualityRemediationKind? roomBeforePairQualityRemediation(
    RoomBeforePairQualityGateResult result) {
  final blocker = result.primaryBlocker;
  if (blocker == null) return null;
  switch (blocker.code) {
    case RoomBeforePairQualityBlockerCode.leftQualityFailed:
    case RoomBeforePairQualityBlockerCode.rightQualityFailed:
      final subCode =
          blocker.code == RoomBeforePairQualityBlockerCode.leftQualityFailed
              ? result.leftResult.primaryBlocker?.code
              : result.rightResult.primaryBlocker?.code;
      if (subCode == null) {
        return RoomBeforePairQualityRemediationKind.goToMeasureTab;
      }
      switch (subCode) {
        case RoomMeasurementQualityBlockerCode.missingMeasurement:
        case RoomMeasurementQualityBlockerCode.missingQualitySnapshot:
          return RoomBeforePairQualityRemediationKind.goToMeasureTab;
        case RoomMeasurementQualityBlockerCode.calibrationCoverageInsufficient:
          return RoomBeforePairQualityRemediationKind.manageMicrophone;
        default:
          return RoomBeforePairQualityRemediationKind.goToMeasureTab;
      }
    case RoomBeforePairQualityBlockerCode.differentProject:
    case RoomBeforePairQualityBlockerCode.differentMicrophoneProfile:
    case RoomBeforePairQualityBlockerCode.differentCalibrationCurve:
    case RoomBeforePairQualityBlockerCode.differentCalibrationOrientation:
    case RoomBeforePairQualityBlockerCode.differentInputDevice:
    case RoomBeforePairQualityBlockerCode.differentPolicyVersion:
      // No single-CTA fix — resolved only by re-measuring Before consistently.
      return null;
  }
}

const String kRoomBeforePairQualityReadyText =
    'Room Before 측정 2/2 · 측정 품질 확인 완료';
