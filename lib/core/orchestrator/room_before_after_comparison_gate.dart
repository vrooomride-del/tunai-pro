// ── TUNAI PRO Phase 3-D3C-2 §4 — Room Before/After pair provenance gate ─────
//
// The OUTERMOST gate of the Room Closed Loop. Both sides (Left and Right)
// must be provenance-comparable before RoomClosedLoopEvaluator — and
// therefore CorrectionCycleEvaluator — is allowed to run at all. A
// comparison between captures made with a different microphone, calibration,
// orientation or input device is not a worse/better result; it is not a
// result. Blocking here is what stops such a delta from ever being rendered
// as "improved" or "worsened", or from producing a rollback recommendation.
//
// Pure: no I/O, no provider reads, no acoustic math. It only combines two
// MeasurementBeforeAfterComparison verdicts.

library;

import '../measurement/measurement_before_after_comparison.dart';
import '../pro_acoustic_data.dart';
import '../room_measurement_data.dart';

class RoomBeforeAfterComparisonGateResult {
  /// True only when BOTH sides are comparable. Warnings never block.
  final bool canEvaluate;

  final MeasurementBeforeAfterComparisonResult leftResult;
  final MeasurementBeforeAfterComparisonResult rightResult;

  /// Every blocker across both sides, de-duplicated by code and ordered
  /// cause-first (see [_blockerOrder]) rather than Left-then-Right, so the
  /// user is told the underlying thing to fix regardless of which side
  /// surfaced it.
  final List<MeasurementBeforeAfterMismatch> blockers;

  final List<MeasurementBeforeAfterWarning> warnings;

  const RoomBeforeAfterComparisonGateResult({
    required this.canEvaluate,
    required this.leftResult,
    required this.rightResult,
    required this.blockers,
    required this.warnings,
  });

  MeasurementBeforeAfterMismatch? get primaryBlocker =>
      blockers.isEmpty ? null : blockers.first;

  bool hasBlocker(MeasurementBeforeAfterMismatchCode code) =>
      blockers.any((b) => b.code == code);

  bool hasWarning(MeasurementBeforeAfterWarningCode code) =>
      warnings.any((w) => w.code == code);
}

abstract final class RoomBeforeAfterComparisonGate {
  /// Cause-first ordering: the earliest entry a result carries becomes its
  /// primary blocker. Ordered by what the user must actually do — first
  /// "we have no usable measurement at all", then "the chain changed",
  /// then "the recording format is wrong".
  static const List<MeasurementBeforeAfterMismatchCode> _blockerOrder = [
    MeasurementBeforeAfterMismatchCode.missingBeforeProvenance,
    MeasurementBeforeAfterMismatchCode.missingAfterProvenance,
    MeasurementBeforeAfterMismatchCode.nonLiveBefore,
    MeasurementBeforeAfterMismatchCode.nonLiveAfter,
    MeasurementBeforeAfterMismatchCode.missingBeforeQuality,
    MeasurementBeforeAfterMismatchCode.missingAfterQuality,
    MeasurementBeforeAfterMismatchCode.differentProject,
    MeasurementBeforeAfterMismatchCode.differentMicrophoneProfile,
    MeasurementBeforeAfterMismatchCode.differentCalibrationCurve,
    MeasurementBeforeAfterMismatchCode.differentCalibrationOrientation,
    MeasurementBeforeAfterMismatchCode.differentInputDevice,
    MeasurementBeforeAfterMismatchCode.invalidBeforeFormat,
    MeasurementBeforeAfterMismatchCode.invalidAfterFormat,
  ];

  static RoomBeforeAfterComparisonGateResult evaluate({
    required ParsedMeasurementData? beforeLeft,
    required ParsedMeasurementData? afterLeft,
    required ParsedMeasurementData? beforeRight,
    required ParsedMeasurementData? afterRight,
  }) {
    final left = MeasurementBeforeAfterComparison.evaluateMeasurements(
        before: beforeLeft, after: afterLeft);
    final right = MeasurementBeforeAfterComparison.evaluateMeasurements(
        before: beforeRight, after: afterRight);

    final byCode =
        <MeasurementBeforeAfterMismatchCode, MeasurementBeforeAfterMismatch>{};
    for (final m in [...left.mismatches, ...right.mismatches]) {
      byCode.putIfAbsent(m.code, () => m);
    }
    final ordered = [
      for (final code in _blockerOrder)
        if (byCode.containsKey(code)) byCode[code]!,
    ];
    // Any code not in the ordering list still surfaces, after the known ones.
    for (final entry in byCode.entries) {
      if (!_blockerOrder.contains(entry.key)) ordered.add(entry.value);
    }

    final warningsByCode =
        <MeasurementBeforeAfterWarningCode, MeasurementBeforeAfterWarning>{};
    for (final w in [...left.warnings, ...right.warnings]) {
      warningsByCode.putIfAbsent(w.code, () => w);
    }

    return RoomBeforeAfterComparisonGateResult(
      canEvaluate: ordered.isEmpty,
      leftResult: left,
      rightResult: right,
      blockers: List.unmodifiable(ordered),
      warnings: List.unmodifiable(warningsByCode.values.toList()),
    );
  }

  /// Convenience overload for the Room snapshots the controller holds.
  static RoomBeforeAfterComparisonGateResult evaluateSnapshots({
    required RoomMeasurementSnapshot before,
    required RoomMeasurementSnapshot after,
  }) =>
      evaluate(
        beforeLeft: before.leftSystemFrd?.frd,
        afterLeft: after.leftSystemFrd?.frd,
        beforeRight: before.rightSystemFrd?.frd,
        afterRight: after.rightSystemFrd?.frd,
      );
}
