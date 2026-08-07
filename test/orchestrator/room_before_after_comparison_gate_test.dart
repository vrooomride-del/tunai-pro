// Phase 3-D3C-2 §2/§3/§4/§7/§8/§9 — Room Before/After provenance gate.
//
// This gate is the outermost guard of the Room Closed Loop: a Before/After
// pair that does not describe the same measurement chain must never reach
// RoomClosedLoopEvaluator, so no improved/worsened verdict — and no rollback
// recommendation — can be produced from a meaningless comparison.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_before_after_comparison.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/measurement/room_before_after_presentation.dart';
import 'package:tunai_pro/core/orchestrator/room_before_after_comparison_gate.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';

final _at = DateTime.utc(2026, 8, 7, 12);

MeasurementCaptureProvenance _prov({
  String projectId = 'proj-1',
  String profile = 'profile-a',
  String? curve = 'curve-a',
  String? angle = 'zeroDegree',
  String device = 'device:dev-1',
  String generation = 'gen-1',
  String policyVersion = 'pro-provisional-1',
  int sampleRate = 48000,
  int channels = 1,
}) =>
    MeasurementCaptureProvenance(
      projectId: projectId,
      microphoneProfileChecksum: profile,
      calibrationCurveChecksum: curve,
      calibrationAngle: angle,
      inputDeviceSelectionIdentity: device,
      setupReadinessGenerationId: generation,
      qualityPolicyVersion: policyVersion,
      actualSampleRate: sampleRate,
      actualChannelCount: channels,
      capturedAt: _at,
    );

ParsedMeasurementData _m({
  MeasurementCaptureProvenance? provenance,
  MeasurementDataSource source = MeasurementDataSource.liveCapture,
  bool noQuality = false,
  CalibrationStatus calibration = CalibrationStatus.calibrated,
}) =>
    ParsedMeasurementData(
      id: 'm-${provenance.hashCode}-${source.name}',
      sourceFileName: 'room.frd',
      fileType: AcousticFileType.frd,
      importedAt: _at,
      points: const [
        MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -3),
        MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: -2),
      ],
      calibrationStatus: calibration,
      calibrationCurveChecksum: 'curve-a',
      source: source,
      qualitySnapshot: noQuality
          ? null
          : MeasurementQualitySnapshot(
              provenance: provenance ?? _prov(),
              setupCalibrationStatus: calibration,
              setupNoiseFloorDbFs: -70,
              setupPeakDbFs: -6,
              setupRmsDbFs: -18,
              setupSignalToNoiseDb: 52,
              setupClippedSampleCount: 0,
              setupClippedSampleRatio: 0,
              setupCheckedAt: _at,
            ),
    );

/// Pair gate over one perturbed side; the other side is always valid, so a
/// total FAIL proves "one side is enough to block".
RoomBeforeAfterComparisonGateResult _pair({
  ParsedMeasurementData? beforeLeft,
  ParsedMeasurementData? afterLeft,
  ParsedMeasurementData? beforeRight,
  ParsedMeasurementData? afterRight,
}) =>
    RoomBeforeAfterComparisonGate.evaluate(
      beforeLeft: beforeLeft ?? _m(),
      afterLeft: afterLeft ?? _m(),
      beforeRight: beforeRight ?? _m(),
      afterRight: afterRight ?? _m(),
    );

void main() {
  group('1. individual comparison', () {
    MeasurementBeforeAfterComparisonResult one({
      ParsedMeasurementData? before,
      ParsedMeasurementData? after,
    }) =>
        MeasurementBeforeAfterComparison.evaluateMeasurements(
            before: before ?? _m(), after: after ?? _m());

    test('identical provenance is comparable', () {
      final r = one();
      expect(r.comparable, isTrue);
      expect(r.mismatches, isEmpty);
      expect(r.warnings, isEmpty);
    });

    test('missing quality on either side blocks', () {
      expect(
          one(before: _m(noQuality: true)).hasMismatch(
              MeasurementBeforeAfterMismatchCode.missingBeforeQuality),
          isTrue);
      expect(
          one(after: _m(noQuality: true)).hasMismatch(
              MeasurementBeforeAfterMismatchCode.missingAfterQuality),
          isTrue);
    });

    test('imported or legacy source blocks (Room compares live captures only)',
        () {
      for (final s in [
        MeasurementDataSource.imported,
        MeasurementDataSource.legacyUnknown,
      ]) {
        expect(one(before: _m(source: s)).comparable, isFalse, reason: s.name);
        expect(
            one(before: _m(source: s))
                .hasMismatch(MeasurementBeforeAfterMismatchCode.nonLiveBefore),
            isTrue);
        expect(
            one(after: _m(source: s))
                .hasMismatch(MeasurementBeforeAfterMismatchCode.nonLiveAfter),
            isTrue);
      }
    });

    test('each chain-identity component mismatch is reported specifically', () {
      final cases = {
        MeasurementBeforeAfterMismatchCode.differentProject:
            _prov(projectId: 'other'),
        MeasurementBeforeAfterMismatchCode.differentMicrophoneProfile:
            _prov(profile: 'profile-b'),
        MeasurementBeforeAfterMismatchCode.differentCalibrationCurve:
            _prov(curve: 'curve-b'),
        MeasurementBeforeAfterMismatchCode.differentCalibrationOrientation:
            _prov(angle: 'ninetyDegree'),
        MeasurementBeforeAfterMismatchCode.differentInputDevice:
            _prov(device: 'device:other'),
      };
      cases.forEach((code, prov) {
        final r = one(after: _m(provenance: prov));
        expect(r.comparable, isFalse, reason: code.name);
        expect(r.hasMismatch(code), isTrue, reason: code.name);
      });
    });

    test('invalid actual format blocks', () {
      expect(
          one(before: _m(provenance: _prov(sampleRate: 0))).hasMismatch(
              MeasurementBeforeAfterMismatchCode.invalidBeforeFormat),
          isTrue);
      expect(
          one(after: _m(provenance: _prov(channels: 0))).hasMismatch(
              MeasurementBeforeAfterMismatchCode.invalidAfterFormat),
          isTrue);
    });

    test('differing actual format between the two sides blocks', () {
      final r = one(after: _m(provenance: _prov(sampleRate: 44100)));
      expect(r.comparable, isFalse);
    });

    test(
        'a different setup generation is allowed (each capture was valid '
        'under its own)', () {
      final r = one(after: _m(provenance: _prov(generation: 'gen-99')));
      expect(r.comparable, isTrue);
      expect(r.mismatches, isEmpty);
    });

    test('policy-version mismatch is a WARNING, never a blocker', () {
      final r = one(after: _m(provenance: _prov(policyVersion: 'v2')));
      expect(r.comparable, isTrue);
      expect(r.mismatches, isEmpty);
      expect(
          r.hasWarning(
              MeasurementBeforeAfterWarningCode.qualityPolicyVersionMismatch),
          isTrue);
    });

    test('both sides explicitly uncalibrated: comparable, with a warning', () {
      final r = one(
        before: _m(calibration: CalibrationStatus.explicitlyUncalibrated),
        after: _m(calibration: CalibrationStatus.explicitlyUncalibrated),
      );
      expect(r.comparable, isTrue,
          reason: 'same chain twice is still a like-for-like delta');
      expect(
          r.hasWarning(
              MeasurementBeforeAfterWarningCode.bothExplicitlyUncalibrated),
          isTrue,
          reason: 'must never be presented as a calibrated result');
    });
  });

  group('2. pair gate', () {
    test('both sides valid -> canEvaluate', () {
      final r = _pair();
      expect(r.canEvaluate, isTrue);
      expect(r.blockers, isEmpty);
      expect(r.leftResult.comparable, isTrue);
      expect(r.rightResult.comparable, isTrue);
    });

    test('Left alone failing blocks the whole pair', () {
      final r = _pair(afterLeft: _m(provenance: _prov(profile: 'other')));
      expect(r.canEvaluate, isFalse);
      expect(r.rightResult.comparable, isTrue,
          reason: 'the healthy side is still reported as healthy');
    });

    test('Right alone failing blocks the whole pair', () {
      final r = _pair(afterRight: _m(provenance: _prov(device: 'device:x')));
      expect(r.canEvaluate, isFalse);
      expect(r.leftResult.comparable, isTrue);
    });

    test('both failing reports each distinct cause once', () {
      final r = _pair(
        afterLeft: _m(provenance: _prov(profile: 'other')),
        afterRight: _m(provenance: _prov(profile: 'other')),
      );
      expect(r.canEvaluate, isFalse);
      expect(
          r.blockers
              .where((b) =>
                  b.code ==
                  MeasurementBeforeAfterMismatchCode.differentMicrophoneProfile)
              .length,
          1,
          reason: 'de-duplicated by cause, not listed per side');
    });

    test('warnings only -> canEvaluate stays true and warnings survive', () {
      final r = _pair(
        afterLeft: _m(provenance: _prov(policyVersion: 'v2')),
        afterRight: _m(provenance: _prov(policyVersion: 'v2')),
      );
      expect(r.canEvaluate, isTrue);
      expect(
          r.hasWarning(
              MeasurementBeforeAfterWarningCode.qualityPolicyVersionMismatch),
          isTrue);
    });

    test('blocker ordering is cause-first, not Left-then-Right', () {
      // Right side has the "earlier cause" (no quality at all); Left has a
      // later one (device changed). The primary blocker must be the earlier
      // cause even though it came from the Right side.
      final r = _pair(
        afterLeft: _m(provenance: _prov(device: 'device:x')),
        afterRight: _m(noQuality: true),
      );
      expect(r.primaryBlocker?.code,
          MeasurementBeforeAfterMismatchCode.missingAfterQuality);
    });
  });

  group('3. presentation mapping (§6/§12)', () {
    test('each blocker code maps to distinct user-facing copy and a CTA', () {
      for (final code in MeasurementBeforeAfterMismatchCode.values) {
        final text = roomBeforeAfterBlockerText(code);
        expect(text, isNotEmpty, reason: code.name);
        expect(text, isNot(contains(code.name)),
            reason: 'must not leak the enum name into the UI');
        // Every blocker offers a real, existing next action.
        expect(
            roomBeforeAfterRemediationLabel(roomBeforeAfterRemediation(code)),
            isNotEmpty);
      }
    });

    test('mic / calibration / orientation / device have their specified copy',
        () {
      expect(
          roomBeforeAfterBlockerText(
              MeasurementBeforeAfterMismatchCode.differentMicrophoneProfile),
          'Before와 After가 서로 다른 측정 마이크로 측정되었습니다.');
      expect(
          roomBeforeAfterBlockerText(
              MeasurementBeforeAfterMismatchCode.differentCalibrationCurve),
          'Before와 After의 마이크 보정 설정이 다릅니다.');
      expect(
          roomBeforeAfterBlockerText(MeasurementBeforeAfterMismatchCode
              .differentCalibrationOrientation),
          'Before와 After의 마이크 방향 설정이 다릅니다.');
      expect(
          roomBeforeAfterBlockerText(
              MeasurementBeforeAfterMismatchCode.differentInputDevice),
          'Before와 After의 입력 장치가 다릅니다.');
      expect(
          roomBeforeAfterBlockerText(
              MeasurementBeforeAfterMismatchCode.missingAfterQuality),
          contains('다시 측정'));
    });

    test('every warning code maps to copy', () {
      for (final code in MeasurementBeforeAfterWarningCode.values) {
        expect(roomBeforeAfterWarningText(code), isNotEmpty, reason: code.name);
      }
    });
  });
}
