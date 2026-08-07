// ── TUNAI PRO Phase 3-D3B — Room Before Left/Right pair quality gate ────────
//
// Room Auto PEQ needs BOTH sides to describe the same measurement chain —
// same microphone, same calibration, same input device, same policy — or a
// "correction" derived from mismatched captures would be meaningless. This
// is layered ON TOP of (never a replacement for) the existing Left/Right
// 2/2 completeness check (RoomAutoPeq.isReady/RoomMeasurementSnapshot
// .isComplete) and each side's own [RoomMeasurementQualityGate].
//
// Deliberately NOT required to match: setupReadinessGenerationId. The user
// may legitimately re-run Setup Check between capturing Left and Right — as
// long as each capture's OWN generation was valid at ITS OWN capture time
// (already guaranteed by the Phase 3-D3A-2 Accept gate), a differing
// generationId between the two sides is not itself a problem.
library;

import '../room_measurement_data.dart';
import 'room_measurement_quality_gate.dart';

enum RoomBeforePairQualityBlockerCode {
  leftQualityFailed,
  rightQualityFailed,
  differentProject,
  differentMicrophoneProfile,
  differentCalibrationCurve,
  differentCalibrationOrientation,
  differentInputDevice,
  differentPolicyVersion,
}

class RoomBeforePairQualityBlocker {
  final RoomBeforePairQualityBlockerCode code;
  final String message;

  const RoomBeforePairQualityBlocker(this.code, this.message);

  @override
  String toString() => '${code.name}: $message';
}

class RoomBeforePairQualityGateResult {
  final bool canGenerate;
  final RoomMeasurementQualityResult leftResult;
  final RoomMeasurementQualityResult rightResult;
  final List<RoomBeforePairQualityBlocker> blockers;

  const RoomBeforePairQualityGateResult({
    required this.canGenerate,
    required this.leftResult,
    required this.rightResult,
    required this.blockers,
  });

  RoomBeforePairQualityBlocker? get primaryBlocker =>
      blockers.isEmpty ? null : blockers.first;

  bool hasBlocker(RoomBeforePairQualityBlockerCode code) =>
      blockers.any((b) => b.code == code);
}

abstract final class RoomBeforePairQualityGate {
  static RoomBeforePairQualityGateResult evaluate({
    required String projectId,
    required RoomSystemMeasurement? left,
    required RoomSystemMeasurement? right,
  }) {
    final leftResult = RoomMeasurementQualityGate.evaluate(
      measurement: left,
      expectedProjectId: projectId,
    );
    final rightResult = RoomMeasurementQualityGate.evaluate(
      measurement: right,
      expectedProjectId: projectId,
    );

    final blockers = <RoomBeforePairQualityBlocker>[];
    if (!leftResult.isValid) {
      blockers.add(RoomBeforePairQualityBlocker(
        RoomBeforePairQualityBlockerCode.leftQualityFailed,
        '왼쪽 측정의 품질 확인에 실패했습니다: '
        '${leftResult.primaryBlocker?.message ?? ""}',
      ));
    }
    if (!rightResult.isValid) {
      blockers.add(RoomBeforePairQualityBlocker(
        RoomBeforePairQualityBlockerCode.rightQualityFailed,
        '오른쪽 측정의 품질 확인에 실패했습니다: '
        '${rightResult.primaryBlocker?.message ?? ""}',
      ));
    }

    if (leftResult.isValid && rightResult.isValid) {
      final lp = left!.frd.qualitySnapshot!.provenance;
      final rp = right!.frd.qualitySnapshot!.provenance;

      if (lp.projectId != rp.projectId) {
        blockers.add(const RoomBeforePairQualityBlocker(
          RoomBeforePairQualityBlockerCode.differentProject,
          '좌우 측정의 프로젝트가 다릅니다.',
        ));
      }
      if (lp.microphoneProfileChecksum != rp.microphoneProfileChecksum) {
        blockers.add(const RoomBeforePairQualityBlocker(
          RoomBeforePairQualityBlockerCode.differentMicrophoneProfile,
          '좌우 측정에 서로 다른 마이크가 사용되었습니다.',
        ));
      }
      if (lp.calibrationCurveChecksum != rp.calibrationCurveChecksum) {
        blockers.add(const RoomBeforePairQualityBlocker(
          RoomBeforePairQualityBlockerCode.differentCalibrationCurve,
          '좌우 측정의 보정 커브가 다릅니다.',
        ));
      }
      if (lp.calibrationAngle != rp.calibrationAngle) {
        blockers.add(const RoomBeforePairQualityBlocker(
          RoomBeforePairQualityBlockerCode.differentCalibrationOrientation,
          '좌우 측정의 마이크 방향이 다릅니다.',
        ));
      }
      if (lp.inputDeviceSelectionIdentity != rp.inputDeviceSelectionIdentity) {
        blockers.add(const RoomBeforePairQualityBlocker(
          RoomBeforePairQualityBlockerCode.differentInputDevice,
          '좌우 측정의 입력 장치가 다릅니다.',
        ));
      }
      if (lp.qualityPolicyVersion != rp.qualityPolicyVersion) {
        blockers.add(const RoomBeforePairQualityBlocker(
          RoomBeforePairQualityBlockerCode.differentPolicyVersion,
          '좌우 측정의 품질 기준 버전이 다릅니다.',
        ));
      }
    }

    return RoomBeforePairQualityGateResult(
      canGenerate: blockers.isEmpty,
      leftResult: leftResult,
      rightResult: rightResult,
      blockers: List.unmodifiable(blockers),
    );
  }
}
