// Phase 3-D3A-3 §11 — rollback identity must never be mistaken for a fresh
// correction's After-eligibility.
//
// Walks the exact hostile/accidental sequence the phase spec calls out:
// correction approved + deployed (After becomes available) -> a rollback is
// separately requested and deployed, overwriting the shared
// lastHardwareWriteResultProvider with the ROLLBACK's own
// HardwareWriteExecutionResult -> RoomAfterGate (and therefore the composite
// dual gate) must go back to blocked for the ORIGINAL correction's
// approvedPackageId, never silently reading the rollback's result as
// evidence the correction is still deployed.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/orchestrator/room_after_gate.dart';

HardwareWriteExecutionResult _verifiedResult(String planId) =>
    HardwareWriteExecutionResult(
      planId: planId,
      executed: true,
      rejectionReason: null,
      outcomes: [
        const HardwareWriteOpOutcome(
          op: HardwareWriteOp(
            channelId: 'ch_wf_l',
            parameterKind: HardwareParamKind.peqGain,
            bandIndex: 0,
            targetValue: -1.0,
            verification: HardwareParamVerification.captureProven,
            writable: true,
            reason: 'test',
          ),
          status: HardwareWriteOpStatus.written,
          report: null,
          message: 'ok',
        ),
      ],
    );

void main() {
  group('correction vs rollback identity separation (production id shapes)',
      () {
    const correctionPackageId = 'room-auto-peq-proj-1-1000';
    const rollbackPackageId = 'room-rollback-proj-1-2000';

    test('correction deployed -> After available for the correction id', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: correctionPackageId,
        lastResult: _verifiedResult('$correctionPackageId@t1'),
      );
      expect(r.available, isTrue);
    });

    test(
        'rollback subsequently deployed (overwrites the shared hardware '
        'result) -> the ORIGINAL correction id is now blocked, not '
        'silently still available', () {
      // Simulates lastHardwareWriteResultProvider being overwritten by the
      // rollback's own deploy — the correction's approvedPackageId field on
      // RoomAutoPeqState is untouched by a rollback request (a separate
      // rollbackApprovedPackageId field), so the caller still passes the
      // SAME correction id here.
      final r = RoomAfterGate.evaluate(
        approvedPackageId: correctionPackageId,
        lastResult: _verifiedResult('$rollbackPackageId@t2'),
      );
      expect(r.available, isFalse);
      expect(r.blockedCode, RoomAfterBlockerCode.staleHardwareResult);
    });

    test(
        'the rollback\'s OWN id against the rollback\'s OWN deployed result '
        'still correctly resolves available (legitimate reuse — '
        'auto_peq_tab\'s rollback-status indicator calls this the same way)',
        () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: rollbackPackageId,
        lastResult: _verifiedResult('$rollbackPackageId@t2'),
      );
      expect(r.available, isTrue);
    });
  });
}
