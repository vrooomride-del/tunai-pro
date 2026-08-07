// ── TUNAI PRO Phase 3-D3B §10 — Before/After provenance comparison ──────────
//
// FOUNDATION ONLY this phase: a pure helper + type, unit-tested, NOT wired
// into Closed Loop (Factory or Room) yet — that wiring is D3C/a later phase's
// job, once the scope of touching Closed Loop itself is assessed on its own.
//
// A Before and an After capture are only a meaningful performance
// comparison if they describe the SAME measurement chain: same project,
// same microphone profile, same calibration curve/orientation, same input
// device. A different quality policy version is compatible as long as both
// are present (the policy governs capture validity, not comparability) —
// only project/profile/calibration/device identity must match exactly.
library;

import 'measurement_capture_provenance.dart';

enum MeasurementBeforeAfterMismatchCode {
  missingBeforeProvenance,
  missingAfterProvenance,
  differentProject,
  differentMicrophoneProfile,
  differentCalibrationCurve,
  differentCalibrationOrientation,
  differentInputDevice,
}

class MeasurementBeforeAfterMismatch {
  final MeasurementBeforeAfterMismatchCode code;
  final String message;

  const MeasurementBeforeAfterMismatch(this.code, this.message);

  @override
  String toString() => '${code.name}: $message';
}

class MeasurementBeforeAfterComparisonResult {
  final bool comparable;
  final List<MeasurementBeforeAfterMismatch> mismatches;

  const MeasurementBeforeAfterComparisonResult({
    required this.comparable,
    required this.mismatches,
  });

  MeasurementBeforeAfterMismatch? get primaryMismatch =>
      mismatches.isEmpty ? null : mismatches.first;

  bool hasMismatch(MeasurementBeforeAfterMismatchCode code) =>
      mismatches.any((m) => m.code == code);
}

abstract final class MeasurementBeforeAfterComparison {
  static MeasurementBeforeAfterComparisonResult evaluate({
    required MeasurementCaptureProvenance? before,
    required MeasurementCaptureProvenance? after,
  }) {
    if (before == null) {
      return const MeasurementBeforeAfterComparisonResult(
        comparable: false,
        mismatches: [
          MeasurementBeforeAfterMismatch(
            MeasurementBeforeAfterMismatchCode.missingBeforeProvenance,
            'Before 측정의 캡처 정보가 없습니다.',
          ),
        ],
      );
    }
    if (after == null) {
      return const MeasurementBeforeAfterComparisonResult(
        comparable: false,
        mismatches: [
          MeasurementBeforeAfterMismatch(
            MeasurementBeforeAfterMismatchCode.missingAfterProvenance,
            'After 측정의 캡처 정보가 없습니다.',
          ),
        ],
      );
    }

    final mismatches = <MeasurementBeforeAfterMismatch>[];
    if (before.projectId != after.projectId) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.differentProject,
        'Before/After 측정의 프로젝트가 다릅니다.',
      ));
    }
    if (before.microphoneProfileChecksum != after.microphoneProfileChecksum) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.differentMicrophoneProfile,
        'Before/After 측정에 서로 다른 마이크가 사용되었습니다.',
      ));
    }
    if (before.calibrationCurveChecksum != after.calibrationCurveChecksum) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.differentCalibrationCurve,
        'Before/After 측정의 보정 커브가 다릅니다.',
      ));
    }
    if (before.calibrationAngle != after.calibrationAngle) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.differentCalibrationOrientation,
        'Before/After 측정의 마이크 방향이 다릅니다.',
      ));
    }
    if (before.inputDeviceSelectionIdentity !=
        after.inputDeviceSelectionIdentity) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.differentInputDevice,
        'Before/After 측정의 입력 장치가 다릅니다.',
      ));
    }

    return MeasurementBeforeAfterComparisonResult(
      comparable: mismatches.isEmpty,
      mismatches: List.unmodifiable(mismatches),
    );
  }
}
