// ── TUNAI PRO Phase 3-D3C-3 §13 — Workspace Home copy ──────────────────────
//
// Typed, exhaustive mapping so Phase 3-E's Home renders without a single
// conditional of its own:
//
//   Text(measurementWorkflowActionTitle(r.nextRecommendedAction))
//   Text(measurementWorkflowActionDescription(r.nextRecommendedAction))
//
// Beginner-facing copy only. Internal terminology — PEQ register, biquad,
// FFT bin, DSP address, checksum, provenance — must never appear here; it
// belongs in the Workbench tabs and Expert Details, not on Home.

library;

import '../hardware/hardware_connection_readiness.dart';
import '../pro_correction_cycle.dart';
import 'measurement_workflow_readiness.dart';

/// The CTA title. Short, imperative, and describing the user's action rather
/// than the system's internal step.
String measurementWorkflowActionTitle(MeasurementWorkflowAction a) =>
    switch (a) {
      MeasurementWorkflowAction.createOrOpenProject => '프로젝트 만들기',
      MeasurementWorkflowAction.selectMicrophone => '측정 마이크 선택',
      MeasurementWorkflowAction.fixCalibration => '마이크 보정 확인',
      MeasurementWorkflowAction.selectInputDevice => '입력 장치 선택',
      MeasurementWorkflowAction.checkMeasurementSetup => '측정 준비 확인',
      MeasurementWorkflowAction.measureFactoryDrivers => '스피커 유닛 측정',
      MeasurementWorkflowAction.runFactoryGuidedTuning => '기본 튜닝 진행',
      MeasurementWorkflowAction.measureRoomBefore => '보정 전 측정',
      MeasurementWorkflowAction.resolveRoomMeasurementQuality => '측정 다시 하기',
      MeasurementWorkflowAction.generateRoomAutoPeq => '자동 보정 만들기',
      MeasurementWorkflowAction.deployRoomCorrection => '보정 적용하기',
      MeasurementWorkflowAction.measureRoomAfter => '보정 후 측정',
      MeasurementWorkflowAction.resolveBeforeAfterMismatch => '다시 측정하기',
      MeasurementWorkflowAction.reviewClosedLoop => '결과 확인',
      MeasurementWorkflowAction.complete => '튜닝 완료',
    };

/// One sentence explaining why this is next, in plain language.
String measurementWorkflowActionDescription(MeasurementWorkflowAction a) =>
    switch (a) {
      MeasurementWorkflowAction.createOrOpenProject =>
        '스피커를 튜닝하려면 먼저 프로젝트를 만들거나 열어 주세요.',
      MeasurementWorkflowAction.selectMicrophone => '측정에 사용할 마이크를 선택해 주세요.',
      MeasurementWorkflowAction.fixCalibration =>
        '선택한 마이크의 보정 정보를 확인할 수 없습니다. 보정 파일을 다시 불러와 주세요.',
      MeasurementWorkflowAction.selectInputDevice => '마이크가 연결된 입력 장치를 선택해 주세요.',
      MeasurementWorkflowAction.checkMeasurementSetup =>
        '측정을 시작하기 전에 소리 크기와 주변 소음을 한 번 확인합니다.',
      MeasurementWorkflowAction.measureFactoryDrivers =>
        '스피커의 각 유닛을 측정해 기준 데이터를 만듭니다.',
      MeasurementWorkflowAction.runFactoryGuidedTuning =>
        '측정 결과를 바탕으로 스피커 자체의 기본 튜닝을 진행합니다.',
      MeasurementWorkflowAction.measureRoomBefore =>
        '보정 전 상태를 확인하기 위해 좌우 스피커를 각각 측정합니다.',
      MeasurementWorkflowAction.resolveRoomMeasurementQuality =>
        '좌우 측정 조건이 서로 달라 사용할 수 없습니다. 같은 조건으로 다시 측정해 주세요.',
      MeasurementWorkflowAction.generateRoomAutoPeq =>
        '측정 결과에 맞춘 보정안을 만들고 확인합니다.',
      MeasurementWorkflowAction.deployRoomCorrection =>
        '만든 보정을 스피커에 실제로 적용합니다.',
      MeasurementWorkflowAction.measureRoomAfter =>
        '보정이 얼마나 효과가 있었는지 좌우를 다시 측정합니다.',
      MeasurementWorkflowAction.resolveBeforeAfterMismatch =>
        '보정 전과 후의 측정 조건이 달라 비교할 수 없습니다. 같은 조건으로 다시 측정해 주세요.',
      MeasurementWorkflowAction.reviewClosedLoop => '보정 전후 비교 결과를 확인해 주세요.',
      MeasurementWorkflowAction.complete => '모든 단계가 끝났습니다. 소리를 즐겨 주세요.',
    };

String measurementWorkflowBlockerText(MeasurementWorkflowBlockerCode c) =>
    switch (c) {
      MeasurementWorkflowBlockerCode.noProject => '열려 있는 프로젝트가 없습니다.',
      MeasurementWorkflowBlockerCode.noMicrophone => '측정 마이크가 선택되지 않았습니다.',
      MeasurementWorkflowBlockerCode.calibrationInvalid =>
        '마이크 보정 정보를 사용할 수 없습니다.',
      MeasurementWorkflowBlockerCode.noInputDevice => '입력 장치가 선택되지 않았습니다.',
      MeasurementWorkflowBlockerCode.setupRequired => '측정 준비 확인이 필요합니다.',
      MeasurementWorkflowBlockerCode.factoryDriversMissing =>
        '아직 측정되지 않은 스피커 유닛이 있습니다.',
      MeasurementWorkflowBlockerCode.factoryTuningIncomplete =>
        '스피커 기본 튜닝이 끝나지 않았습니다.',
      MeasurementWorkflowBlockerCode.roomBeforeIncomplete =>
        '보정 전 측정이 좌우 모두 필요합니다.',
      MeasurementWorkflowBlockerCode.roomBeforeQualityFailed =>
        '좌우 측정 조건이 서로 다릅니다.',
      MeasurementWorkflowBlockerCode.roomAutoPeqNotApproved =>
        '적용할 보정이 아직 준비되지 않았습니다.',
      MeasurementWorkflowBlockerCode.roomCorrectionNotDeployed =>
        '보정이 아직 스피커에 적용되지 않았습니다.',
      MeasurementWorkflowBlockerCode.roomAfterIncomplete =>
        '보정 후 측정이 좌우 모두 필요합니다.',
      MeasurementWorkflowBlockerCode.beforeAfterMismatch =>
        '보정 전과 후를 같은 조건에서 측정하지 않았습니다.',
    };

String measurementWorkflowWarningText(MeasurementWorkflowWarningCode c) =>
    switch (c) {
      MeasurementWorkflowWarningCode.calibrationPartial =>
        '마이크 보정이 일부 구간에만 적용됩니다.',
      MeasurementWorkflowWarningCode.calibrationUncalibrated =>
        '보정되지 않은 마이크로 측정합니다.',
      MeasurementWorkflowWarningCode.setupWarning => '측정 환경에 주의할 점이 있습니다.',
      MeasurementWorkflowWarningCode.legacyMeasurementData =>
        '이전 버전에서 저장된 측정 데이터가 있습니다. 방 보정에는 새로 측정한 값이 필요합니다.',
      MeasurementWorkflowWarningCode.closedLoopPolicyVersionMismatch =>
        '보정 전후가 서로 다른 기준으로 확인되었습니다.',
      MeasurementWorkflowWarningCode.closedLoopUncalibrated =>
        '보정되지 않은 마이크로 측정된 결과입니다.',
    };

/// §9 — the Deploy step is where hardware readiness first actually matters.
/// It is surfaced as an extra line on that step, never by promoting
/// "connect hardware" ahead of measurement in the ladder.
String? measurementWorkflowHardwareBlockerText(MeasurementWorkflowReadiness r) {
  if (r.nextRecommendedAction !=
      MeasurementWorkflowAction.deployRoomCorrection) {
    return null;
  }
  if (r.hardwareReadyForDeploy) return null;
  return switch (r.hardwareConnectionState) {
    HardwareConnectionState.incompatible => '프로젝트와 연결된 DSP가 일치하지 않습니다.',
    _ => '먼저 하드웨어를 연결하고 준비 상태를 확인하세요.',
  };
}

String measurementWorkflowStageTitle(MeasurementWorkflowStage s) => switch (s) {
      MeasurementWorkflowStage.project => '프로젝트',
      MeasurementWorkflowStage.measurementSetup => '측정 준비',
      MeasurementWorkflowStage.factoryTuning => '스피커 튜닝',
      MeasurementWorkflowStage.roomTuning => '방 보정',
      MeasurementWorkflowStage.verification => '결과 확인',
    };

/// Honest, integer progress. Never a derived percentage — see §14.
({int completed, int total}) measurementWorkflowProgress(
        MeasurementWorkflowReadiness r) =>
    (completed: r.completedStages, total: r.totalStages);

/// How the input device state may be described. A system-default selection
/// is never worded as confirmed, and a specific device is only ever
/// "last checked", never "connected now" — this model runs no device scan.
String measurementWorkflowInputStatusText(MeasurementWorkflowReadiness r) =>
    switch (r.runtimeAvailability) {
      MeasurementWorkflowInputAvailability.lastKnownValid =>
        '마지막 확인 시점에 정상이었습니다.',
      MeasurementWorkflowInputAvailability.systemDefaultUnverified =>
        '시스템 기본 입력을 사용합니다 — 실제 장치는 측정 시작 시 확인됩니다.',
      MeasurementWorkflowInputAvailability.unknown =>
        '입력 장치 상태를 아직 확인하지 않았습니다.',
    };

// ── Phase 3-E §9/§10/§11 — Workspace Home status copy ──────────────────────

String measurementWorkflowCalibrationText(
        MeasurementWorkflowCalibrationState c) =>
    switch (c) {
      MeasurementWorkflowCalibrationState.none => '마이크 미선택',
      MeasurementWorkflowCalibrationState.calibrated => '보정 완료',
      MeasurementWorkflowCalibrationState.partiallyCalibrated => '부분 보정',
      MeasurementWorkflowCalibrationState.explicitlyUncalibrated => '보정 없이 사용',
      MeasurementWorkflowCalibrationState.legacyUnknown => '보정 상태 확인 필요',
      MeasurementWorkflowCalibrationState.invalid => '보정 파일 확인 필요',
    };

String measurementWorkflowSetupStateText(MeasurementWorkflowSetupState s) =>
    switch (s) {
      MeasurementWorkflowSetupState.notChecked => '확인 필요',
      MeasurementWorkflowSetupState.ready => '준비 완료',
      MeasurementWorkflowSetupState.warning => '주의 사항 있음',
      MeasurementWorkflowSetupState.blocked => '다시 확인 필요',
      MeasurementWorkflowSetupState.stale => '설정이 바뀌었습니다',
      MeasurementWorkflowSetupState.expired => '유효 기간 지남',
    };

/// Phase 3-F1 §8 — how the live DSP session reads on Home.
///
/// "준비 완료"/"검증" wording is reserved for [HardwareConnectionState
/// .readyForDeploy] alone; every other state says plainly what is missing. A
/// state nobody has checked is neutral, never a failure.
({String title, String detail}) measurementWorkflowHardwareText(
        HardwareConnectionState state) =>
    switch (state) {
      HardwareConnectionState.unknown => (
          title: '하드웨어 상태 확인 필요',
          detail: 'DSP 연결 상태는 Hardware에서 확인할 수 있습니다.',
        ),
      HardwareConnectionState.disconnected => (
          title: '하드웨어가 연결되지 않았습니다.',
          detail: 'Hardware에서 연결을 시작할 수 있습니다.',
        ),
      HardwareConnectionState.connecting => (
          title: '하드웨어 연결 중',
          detail: '기기 확인이 끝나면 준비 상태가 표시됩니다.',
        ),
      HardwareConnectionState.connected => (
          title: '하드웨어 연결됨',
          detail: 'DSP 준비 상태를 확인하고 있습니다.',
        ),
      HardwareConnectionState.readyForDeploy => (
          title: '하드웨어 준비 완료',
          detail: '보정을 적용할 수 있습니다.',
        ),
      HardwareConnectionState.incompatible => (
          title: '프로젝트와 연결된 DSP가 일치하지 않습니다.',
          detail: '프로젝트 설정과 같은 기기를 연결해 주세요.',
        ),
      HardwareConnectionState.error => (
          title: '하드웨어 연결을 확인해 주세요.',
          detail: 'Hardware에서 연결 상태를 다시 확인할 수 있습니다.',
        ),
    };

/// §11 — how the Factory stage reads. Only `improvedAndComplete` is a
/// completion; every other verdict is an explicit "there is more to do",
/// and a manual approval is never inferred as finished.
String measurementWorkflowFactoryText(MeasurementWorkflowReadiness r) {
  if (r.factoryTuningCompleted) return 'Factory Tuning 완료';
  return switch (r.factoryLastCycleDecision) {
    CorrectionCycleDecision.improvedNeedsAnotherCycle => '추가 보정 권장',
    CorrectionCycleDecision.worsened => '재검토 필요',
    CorrectionCycleDecision.noMeaningfulImprovement => '변화 없음 — 재검토 필요',
    CorrectionCycleDecision.insufficientEvidence ||
    CorrectionCycleDecision.wrongProjectOrChannel =>
      '재측정 필요',
    CorrectionCycleDecision.improvedAndComplete => 'Factory Tuning 완료',
    null => r.driverMeasurementReady ? '튜닝 시작 가능' : '측정 진행 중',
  };
}

/// The label under each Journey dot. Users read these as their own steps,
/// so they are the beginner-facing stage names, not the enum names.
String measurementWorkflowStageStateText(MeasurementWorkflowStageState s) =>
    switch (s) {
      MeasurementWorkflowStageState.notStarted => '시작 전',
      MeasurementWorkflowStageState.inProgress => '진행 중',
      MeasurementWorkflowStageState.complete => '완료',
      MeasurementWorkflowStageState.blocked => '해결 필요',
      MeasurementWorkflowStageState.warning => '주의',
    };
