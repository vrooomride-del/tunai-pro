// ── TUNAI PRO Phase 3-D3A-3 — Room After dual-gate presentation strings ─────
//
// ONE pure mapping from [RoomAfterCaptureBlockerCode] to the exact Korean
// copy this phase specifies. Reuses the existing Phase 3-D3A-1B measurement
// presentation helper for measurement-side blockers instead of inventing
// parallel copy — `measurementSetupBlocked` never loses which specific
// [MeasurementCaptureBlockerCode] it was.
library;

import '../measurement/measurement_capture_presentation.dart';
import 'room_after_capture_gate.dart';

String roomAfterCaptureBlockerText(RoomAfterCaptureGateResult result) {
  final blocker = result.primaryBlocker;
  if (blocker == null) return '';
  switch (blocker.code) {
    case RoomAfterCaptureBlockerCode.correctionNotApproved:
    case RoomAfterCaptureBlockerCode.correctionNotDeployed:
      return 'Room 보정을 먼저 스피커에 적용하고 확인해 주세요.';
    case RoomAfterCaptureBlockerCode.hardwareWriteNotVerified:
      return 'DSP 적용 확인이 완료되지 않았습니다.';
    case RoomAfterCaptureBlockerCode.staleHardwareResult:
      return '현재 보정과 적용 결과가 일치하지 않습니다. 다시 적용해 주세요.';
    case RoomAfterCaptureBlockerCode.measurementSetupBlocked:
      return measurementCaptureBlockerText(
          result.measurementGate.primaryBlocker!.code);
    case RoomAfterCaptureBlockerCode.measurementSetupWarningNotAcknowledged:
      return '측정 전 경고 확인이 필요합니다.';
  }
}

/// CTA label for [RoomAfterCaptureRemediationKind.deployCorrection] —
/// [RoomAfterCaptureRemediationKind.measurement] reuses
/// [measurementCaptureRemediationLabel] instead of a parallel label here.
const String kRoomAfterCaptureDeployRemediationLabel = 'Deploy로 이동';
