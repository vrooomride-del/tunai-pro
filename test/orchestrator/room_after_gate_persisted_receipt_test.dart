// Phase 3-F3 §4/§6 — RoomAfterGate's restart-safe persistedReceipt fallback.
//
// Extends (never replaces) the existing session-only lastResult contract:
// a live session result, when present and matching, always wins; the
// persisted receipt is consulted ONLY when the session has nothing to say
// about the current approved package — which is exactly the state of the
// world immediately after an app restart (activeAdau1701ContextProvider is
// necessarily null then, but that must never gate this decision).

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/orchestrator/room_after_gate.dart';
import 'package:tunai_pro/core/room_workflow_persistence.dart';

HardwareWriteExecutionResult _result({
  required String planId,
  bool executed = true,
  HardwareWriteOpStatus status = HardwareWriteOpStatus.written,
}) =>
    HardwareWriteExecutionResult(
      planId: planId,
      executed: executed,
      rejectionReason: null,
      outcomes: [
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
          message: 'ok',
        ),
      ],
    );

VerifiedDeploymentReceipt _receipt({
  String packageId = 'pkg-1',
  String? planId,
}) =>
    VerifiedDeploymentReceipt(
      projectId: 'proj-1',
      packageId: packageId,
      planId: planId ?? '$packageId@2026-01-01T00:00:00.000Z',
      dspTarget: 'ADAU1701',
      executed: true,
      allReadbackVerified: true,
      verifiedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('no approval at all', () {
    test('approvedPackageId null -> blocked regardless of receipt', () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: null,
        lastResult: null,
        persistedReceipt: _receipt(),
      );
      expect(result.available, isFalse);
      expect(result.blockedCode, RoomAfterBlockerCode.correctionNotApproved);
    });
  });

  group('restart-safe fallback (no session result)', () {
    test('no session result, matching persisted receipt -> available', () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: null,
        persistedReceipt: _receipt(packageId: 'pkg-1'),
      );
      expect(result.available, isTrue);
    });

    test('no session result, receipt for a DIFFERENT package -> blocked', () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: null,
        persistedReceipt: _receipt(packageId: 'pkg-2'),
      );
      expect(result.available, isFalse);
      expect(result.blockedCode, RoomAfterBlockerCode.correctionNotDeployed);
    });

    test(
        'no session result, no receipt at all -> blocked, correctionNotDeployed',
        () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: null,
        persistedReceipt: null,
      );
      expect(result.available, isFalse);
      expect(result.blockedCode, RoomAfterBlockerCode.correctionNotDeployed);
    });
  });

  group('live session result always takes precedence', () {
    test(
        'matching, verified session result -> available (unchanged '
        'pre-3-F3 behavior, receipt present or not)', () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(planId: 'pkg-1@2026-06-01T00:00:00.000Z'),
        persistedReceipt: _receipt(packageId: 'pkg-1'),
      );
      expect(result.available, isTrue);
    });

    test(
        'session result present but for a stale/different plan, even '
        'with a matching persisted receipt for the SAME package -> the '
        'live session still wins the identity check and blocks, since the '
        'session result itself does not match', () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(planId: 'pkg-OLD@2026-01-01T00:00:00.000Z'),
        persistedReceipt: _receipt(packageId: 'pkg-1'),
      );
      // The session result doesn't match pkg-1, so sessionMatches is false
      // — falls back to the receipt, which DOES match pkg-1.
      expect(result.available, isTrue);
    });

    test(
        'a fresh FAILED retry for the SAME approved package must not be '
        'masked by an older, still-persisted successful receipt', () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@2026-06-01T00:00:00.000Z',
          status: HardwareWriteOpStatus.failed,
        ),
        persistedReceipt: _receipt(packageId: 'pkg-1'),
      );
      expect(result.available, isFalse,
          reason: 'the live session matches by identity, so it must be trusted '
              'over the stale receipt');
      expect(result.blockedCode, RoomAfterBlockerCode.hardwareWriteNotVerified);
    });

    test(
        'a fresh ack-only retry for the SAME approved package must not be '
        'masked by an older, still-persisted successful receipt', () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@2026-06-01T00:00:00.000Z',
          status: HardwareWriteOpStatus.ackOnly,
        ),
        persistedReceipt: _receipt(packageId: 'pkg-1'),
      );
      expect(result.available, isFalse);
      expect(result.blockedCode, RoomAfterBlockerCode.hardwareWriteNotVerified);
    });
  });

  group('backward compatibility — no persistedReceipt argument at all', () {
    test('behaves exactly as before 3-F3 when omitted', () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(planId: 'pkg-1@2026-06-01T00:00:00.000Z'),
      );
      expect(result.available, isTrue);
    });

    test('omitted + no session -> blocked, not a crash', () {
      final result = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: null,
      );
      expect(result.available, isFalse);
    });
  });
}
