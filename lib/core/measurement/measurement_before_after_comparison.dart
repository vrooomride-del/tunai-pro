// ── TUNAI PRO Phase 3-D3B §10 — Before/After provenance comparison ──────────
//
// Phase 3-D3C-2 wired this into the Room Closed Loop as its outermost
// provenance gate (see RoomBeforeAfterComparisonGate): a comparison that is
// not provenance-comparable never reaches CorrectionCycleEvaluator, so a
// meaningless Before/After delta can never be presented as "improved" or
// "worsened".
//
// This helper judges IDENTITY AND PROVENANCE ONLY — it computes no acoustic
// delta and is not a comparison engine.
//
// A Before and an After capture are only a meaningful performance
// comparison if they describe the SAME measurement chain: same project,
// same microphone profile, same calibration curve/orientation, same input
// device. A different quality policy version is compatible as long as both
// are present (the policy governs capture validity, not comparability) —
// only project/profile/calibration/device identity must match exactly.
library;

import '../calibration/calibration_types.dart';
import '../pro_acoustic_data.dart';
import 'measurement_capture_provenance.dart';

enum MeasurementBeforeAfterMismatchCode {
  missingBeforeProvenance,
  missingAfterProvenance,
  differentProject,
  differentMicrophoneProfile,
  differentCalibrationCurve,
  differentCalibrationOrientation,
  differentInputDevice,

  // ── Phase 3-D3C-2 additions ─────────────────────────────────────────────
  /// The capture carries no quality record at all (pre-3-D3B, or imported).
  missingBeforeQuality,
  missingAfterQuality,

  /// Room Closed Loop compares live Room captures only. An imported or
  /// legacy-provenance measurement is a legitimate Factory input but is not
  /// an automatic Before/After comparison basis.
  nonLiveBefore,
  nonLiveAfter,

  /// The recorded WAV format is missing or implausible, so the numbers can't
  /// be trusted to describe the same kind of recording.
  invalidBeforeFormat,
  invalidAfterFormat,
}

/// Conditions that are worth telling the user about but do NOT invalidate
/// the comparison.
enum MeasurementBeforeAfterWarningCode {
  /// Both captures are valid, but were checked under different
  /// MeasurementQualityPolicy versions. The policy governs capture validity,
  /// not acoustic comparability, so this never blocks — it is surfaced so a
  /// future policy change that DOES affect semantics can be turned into a
  /// blocker by giving this code a compatibility rule instead of re-deriving
  /// the concept.
  qualityPolicyVersionMismatch,

  /// Both sides were captured with an explicitly uncalibrated microphone.
  /// The acoustic delta is still meaningful (same chain both times), but the
  /// result must never be presented as a calibrated measurement.
  bothExplicitlyUncalibrated,
}

class MeasurementBeforeAfterWarning {
  final MeasurementBeforeAfterWarningCode code;
  final String message;

  const MeasurementBeforeAfterWarning(this.code, this.message);

  @override
  String toString() => '${code.name}: $message';
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
  final List<MeasurementBeforeAfterWarning> warnings;

  const MeasurementBeforeAfterComparisonResult({
    required this.comparable,
    required this.mismatches,
    this.warnings = const [],
  });

  MeasurementBeforeAfterMismatch? get primaryMismatch =>
      mismatches.isEmpty ? null : mismatches.first;

  bool hasMismatch(MeasurementBeforeAfterMismatchCode code) =>
      mismatches.any((m) => m.code == code);

  bool hasWarning(MeasurementBeforeAfterWarningCode code) =>
      warnings.any((w) => w.code == code);
}

abstract final class MeasurementBeforeAfterComparison {
  /// Measurement-level entry point used by the Room Closed Loop gate.
  ///
  /// Adds, on top of the provenance identity comparison below: an explicit
  /// live-capture source requirement, a quality-record requirement, actual
  /// WAV format sanity, and the non-blocking policy-version /
  /// both-uncalibrated warnings. Blockers are appended in a fixed
  /// cause-first order (what the user must fix), NOT Before-then-After
  /// order, so the primary blocker is stable regardless of which side
  /// happens to be wrong.
  static MeasurementBeforeAfterComparisonResult evaluateMeasurements({
    required ParsedMeasurementData? before,
    required ParsedMeasurementData? after,
  }) {
    final mismatches = <MeasurementBeforeAfterMismatch>[];
    final warnings = <MeasurementBeforeAfterWarning>[];

    // ── Step 1: both measurements must exist and be live captures ─────────
    if (before == null) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.missingBeforeProvenance,
        'Before 측정의 캡처 정보가 없습니다.',
      ));
    } else if (before.source != MeasurementDataSource.liveCapture) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.nonLiveBefore,
        'Before 측정이 이 앱에서 직접 측정한 결과가 아닙니다.',
      ));
    }
    if (after == null) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.missingAfterProvenance,
        'After 측정의 캡처 정보가 없습니다.',
      ));
    } else if (after.source != MeasurementDataSource.liveCapture) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.nonLiveAfter,
        'After 측정이 이 앱에서 직접 측정한 결과가 아닙니다.',
      ));
    }
    if (mismatches.isNotEmpty) {
      return MeasurementBeforeAfterComparisonResult(
          comparable: false, mismatches: List.unmodifiable(mismatches));
    }

    // ── Step 2: both need a quality record to compare provenance at all ───
    final beforeQuality = before!.qualitySnapshot;
    final afterQuality = after!.qualitySnapshot;
    if (beforeQuality == null) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.missingBeforeQuality,
        'Before 측정의 품질 정보를 확인할 수 없습니다.',
      ));
    }
    if (afterQuality == null) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.missingAfterQuality,
        'After 측정의 품질 정보를 확인할 수 없습니다.',
      ));
    }
    if (mismatches.isNotEmpty) {
      return MeasurementBeforeAfterComparisonResult(
          comparable: false, mismatches: List.unmodifiable(mismatches));
    }

    // ── Step 3: chain identity (project/mic/curve/orientation/device) ─────
    final identity = evaluate(
      before: beforeQuality!.provenance,
      after: afterQuality!.provenance,
    );
    mismatches.addAll(identity.mismatches);

    // ── Step 4: actual recorded format must be plausible on both sides ────
    if (!_formatValid(beforeQuality.provenance)) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.invalidBeforeFormat,
        'Before 측정의 녹음 형식이 올바르지 않습니다.',
      ));
    }
    if (!_formatValid(afterQuality.provenance)) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.invalidAfterFormat,
        'After 측정의 녹음 형식이 올바르지 않습니다.',
      ));
    }
    if (beforeQuality.provenance.actualSampleRate !=
            afterQuality.provenance.actualSampleRate ||
        beforeQuality.provenance.actualChannelCount !=
            afterQuality.provenance.actualChannelCount) {
      mismatches.add(const MeasurementBeforeAfterMismatch(
        MeasurementBeforeAfterMismatchCode.invalidAfterFormat,
        'Before와 After의 녹음 형식이 일치하지 않습니다.',
      ));
    }

    // ── Step 5: non-blocking warnings ─────────────────────────────────────
    if (beforeQuality.provenance.qualityPolicyVersion !=
        afterQuality.provenance.qualityPolicyVersion) {
      warnings.add(const MeasurementBeforeAfterWarning(
        MeasurementBeforeAfterWarningCode.qualityPolicyVersionMismatch,
        'Before와 After가 서로 다른 측정 품질 기준으로 확인되었습니다.',
      ));
    }
    // Both sides uncalibrated is still a like-for-like acoustic comparison
    // (same chain twice), so it is allowed — but the result must never be
    // shown as a calibrated measurement. Room Auto PEQ separately blocks
    // uncalibrated data (D3B), so this should be rare in the normal flow.
    if (before.calibrationStatus == CalibrationStatus.explicitlyUncalibrated &&
        after.calibrationStatus == CalibrationStatus.explicitlyUncalibrated) {
      warnings.add(const MeasurementBeforeAfterWarning(
        MeasurementBeforeAfterWarningCode.bothExplicitlyUncalibrated,
        '보정되지 않은 마이크로 측정된 결과입니다.',
      ));
    }

    return MeasurementBeforeAfterComparisonResult(
      comparable: mismatches.isEmpty,
      mismatches: List.unmodifiable(mismatches),
      warnings: List.unmodifiable(warnings),
    );
  }

  static bool _formatValid(MeasurementCaptureProvenance p) =>
      p.actualSampleRate > 0 && p.actualChannelCount > 0;

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
