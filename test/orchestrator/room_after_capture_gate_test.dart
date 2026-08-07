// Phase 3-D3A-3 — RoomAfterCaptureGate pure composite contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_gate.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_gate_types.dart';
import 'package:tunai_pro/core/orchestrator/room_after_capture_gate.dart';
import 'package:tunai_pro/core/orchestrator/room_after_gate.dart';

HardwareWriteOpOutcome _outcome(HardwareWriteOpStatus status) =>
    HardwareWriteOpOutcome(
      op: const HardwareWriteOp(
        channelId: 'ch_wf_l',
        parameterKind: HardwareParamKind.peqGain,
        bandIndex: 0,
        targetValue: -1.0,
        verification: HardwareParamVerification.captureProven,
        writable: true,
        reason: 'test',
      ),
      status: status,
      report: null,
      message: 'test',
    );

RoomAfterGateResult _hardwarePass() => RoomAfterGate.evaluate(
      approvedPackageId: 'pkg-1',
      lastResult: HardwareWriteExecutionResult(
        planId: 'pkg-1@t1',
        executed: true,
        rejectionReason: null,
        outcomes: [_outcome(HardwareWriteOpStatus.written)],
      ),
    );

RoomAfterGateResult _hardwareNotApproved() =>
    RoomAfterGate.evaluate(approvedPackageId: null, lastResult: null);

RoomAfterGateResult _hardwareNotVerified() => RoomAfterGate.evaluate(
      approvedPackageId: 'pkg-1',
      lastResult: HardwareWriteExecutionResult(
        planId: 'pkg-1@t1',
        executed: true,
        rejectionReason: null,
        outcomes: [_outcome(HardwareWriteOpStatus.ackOnly)],
      ),
    );

const _measurementPass = MeasurementCaptureGateResult(
  canCapture: true,
  blockers: [],
  warnings: [],
  requiresExplicitWarningAcknowledgement: false,
  activeGenerationId: 'gen-1',
  profileIdentity: 'chk-1',
  deviceIdentity: 'device:usb-1',
);

const _measurementBlocked = MeasurementCaptureGateResult(
  canCapture: false,
  blockers: [
    MeasurementCaptureBlocker(
        MeasurementCaptureBlockerCode.setupNotChecked, '측정 준비 확인을 먼저 실행하세요.'),
  ],
  warnings: [],
  requiresExplicitWarningAcknowledgement: false,
  activeGenerationId: null,
  profileIdentity: null,
  deviceIdentity: null,
);

const _measurementWarningPending = MeasurementCaptureGateResult(
  canCapture: false,
  blockers: [],
  warnings: [
    MeasurementCaptureWarning(
        MeasurementCaptureWarningCode.explicitlyUncalibrated,
        '보정되지 않은 마이크로 측정합니다.'),
  ],
  requiresExplicitWarningAcknowledgement: true,
  activeGenerationId: 'gen-1',
  profileIdentity: 'chk-1',
  deviceIdentity: 'device:usb-1',
);

void main() {
  group('composite AND semantics', () {
    test('hardware PASS + measurement PASS -> canCapture true', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwarePass(),
        measurementGate: _measurementPass,
      );
      expect(r.canCapture, isTrue);
      expect(r.blockers, isEmpty);
      expect(r.primaryBlocker, isNull);
    });

    test('hardware FAIL + measurement PASS -> canCapture false', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwareNotApproved(),
        measurementGate: _measurementPass,
      );
      expect(r.canCapture, isFalse);
      expect(r.primaryBlocker!.code,
          RoomAfterCaptureBlockerCode.correctionNotApproved);
    });

    test('hardware PASS + measurement FAIL -> canCapture false', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwarePass(),
        measurementGate: _measurementBlocked,
      );
      expect(r.canCapture, isFalse);
      expect(r.primaryBlocker!.code,
          RoomAfterCaptureBlockerCode.measurementSetupBlocked);
    });

    test('both FAIL -> canCapture false', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwareNotApproved(),
        measurementGate: _measurementBlocked,
      );
      expect(r.canCapture, isFalse);
    });
  });

  group('blocker ordering (Phase 3-D3A-3 §4)', () {
    test('hardware blocker is reported first when both fail', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwareNotApproved(),
        measurementGate: _measurementBlocked,
      );
      expect(r.primaryBlocker!.code,
          RoomAfterCaptureBlockerCode.correctionNotApproved);
      expect(r.blockers.length, 2);
      expect(r.blockers[1].code,
          RoomAfterCaptureBlockerCode.measurementSetupBlocked);
    });

    test('hardware PASS -> measurement blocker surfaces as primary', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwarePass(),
        measurementGate: _measurementBlocked,
      );
      expect(r.primaryBlocker!.code,
          RoomAfterCaptureBlockerCode.measurementSetupBlocked);
      expect(r.blockers.length, 1);
    });

    test(
        'hardware PASS + measurement warning pending -> warning blocker, '
        'not a plain measurementSetupBlocked', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwarePass(),
        measurementGate: _measurementWarningPending,
      );
      expect(r.canCapture, isFalse);
      expect(r.primaryBlocker!.code,
          RoomAfterCaptureBlockerCode.measurementSetupWarningNotAcknowledged);
    });

    test('hardware not verified takes priority over measurement warning', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwareNotVerified(),
        measurementGate: _measurementWarningPending,
      );
      expect(r.primaryBlocker!.code,
          RoomAfterCaptureBlockerCode.hardwareWriteNotVerified);
    });
  });

  group('measurement blocker detail preservation', () {
    test('measurementSetupBlocked keeps the full measurementGate attached', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwarePass(),
        measurementGate: _measurementBlocked,
      );
      expect(r.measurementGate.primaryBlocker!.code,
          MeasurementCaptureBlockerCode.setupNotChecked);
    });
  });

  group('primaryRemediation typing', () {
    test('hardware blocker -> deployCorrection remediation', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwareNotApproved(),
        measurementGate: _measurementPass,
      );
      expect(r.primaryRemediation!.kind,
          RoomAfterCaptureRemediationKind.deployCorrection);
    });

    test('measurement blocker -> typed measurement remediation preserved', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwarePass(),
        measurementGate: _measurementBlocked,
      );
      expect(r.primaryRemediation!.kind,
          RoomAfterCaptureRemediationKind.measurement);
      expect(r.primaryRemediation!.measurementRemediation,
          MeasurementCaptureRemediation.runSetupCheck);
    });

    test('warning blocker -> acknowledgeMeasurementWarning remediation', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwarePass(),
        measurementGate: _measurementWarningPending,
      );
      expect(r.primaryRemediation!.kind,
          RoomAfterCaptureRemediationKind.acknowledgeMeasurementWarning);
    });

    test('canCapture true -> no primaryRemediation', () {
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: _hardwarePass(),
        measurementGate: _measurementPass,
      );
      expect(r.primaryRemediation, isNull);
    });
  });

  group('stale hardware result / staleness code', () {
    test('mismatched plan id -> staleHardwareResult blocker', () {
      final staleGate = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-current',
        lastResult: HardwareWriteExecutionResult(
          planId: 'pkg-OLD@t1',
          executed: true,
          rejectionReason: null,
          outcomes: [_outcome(HardwareWriteOpStatus.written)],
        ),
      );
      final r = RoomAfterCaptureGate.evaluate(
        hardwareGate: staleGate,
        measurementGate: _measurementPass,
      );
      expect(r.canCapture, isFalse);
      expect(r.primaryBlocker!.code,
          RoomAfterCaptureBlockerCode.staleHardwareResult);
    });
  });
}
