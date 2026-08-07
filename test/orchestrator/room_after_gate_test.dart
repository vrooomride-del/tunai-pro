// Phase 2 safety audit — RoomAfterGate tests.
//
// Pure logic, no widget/provider needed. Covers the exact block list from
// the audit: null/unexecuted, blockedByPreflight/failed/timedOut/unsupported
// /ackOnly, stale/mismatched plan identity, and the only-path-to-available
// case (allReadbackVerified with a matching planId prefix).

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/orchestrator/room_after_gate.dart';

HardwareWriteOpOutcome _outcome(HardwareWriteOpStatus status,
        {String channelId = 'ch_wf_l'}) =>
    HardwareWriteOpOutcome(
      op: HardwareWriteOp(
        channelId: channelId,
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

HardwareWriteExecutionResult _result({
  required String planId,
  bool executed = true,
  String? rejectionReason,
  List<HardwareWriteOpOutcome> outcomes = const [],
}) =>
    HardwareWriteExecutionResult(
      planId: planId,
      executed: executed,
      rejectionReason: rejectionReason,
      outcomes: outcomes,
    );

void main() {
  group('candidate generation / approval alone must not unlock After', () {
    test('no approvedPackageId at all -> blocked', () {
      final r =
          RoomAfterGate.evaluate(approvedPackageId: null, lastResult: null);
      expect(r.available, isFalse);
    });

    test('approvedPackageId set but no Deploy result yet -> blocked', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: null,
      );
      expect(r.available, isFalse);
      expect(r.blockedReason, contains('Deploy'));
    });
  });

  group('block on every non-verified execution result', () {
    test('executed=false (rejected up front) -> blocked', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@t1',
          executed: false,
          rejectionReason: 'no writable ops',
        ),
      );
      expect(r.available, isFalse);
    });

    test('blockedByPreflight -> blocked', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@t1',
          outcomes: [_outcome(HardwareWriteOpStatus.blockedByPreflight)],
        ),
      );
      expect(r.available, isFalse);
    });

    test('failed -> blocked', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@t1',
          outcomes: [_outcome(HardwareWriteOpStatus.failed)],
        ),
      );
      expect(r.available, isFalse);
    });

    test('timedOut -> blocked', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@t1',
          outcomes: [_outcome(HardwareWriteOpStatus.timedOut)],
        ),
      );
      expect(r.available, isFalse);
    });

    test('unsupported -> blocked', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@t1',
          outcomes: [_outcome(HardwareWriteOpStatus.unsupported)],
        ),
      );
      expect(r.available, isFalse);
    });

    test(
        'ackOnly -> blocked (Room requires readback verification, '
        'stricter than Factory allWritten)', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@t1',
          outcomes: [_outcome(HardwareWriteOpStatus.ackOnly)],
        ),
      );
      expect(r.available, isFalse);
      expect(r.blockedReason, contains('판독'));
    });

    test('mixed written + ackOnly -> still blocked (not ALL readback-verified)',
        () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@t1',
          outcomes: [
            _outcome(HardwareWriteOpStatus.written),
            _outcome(HardwareWriteOpStatus.ackOnly, channelId: 'ch_wf_r'),
          ],
        ),
      );
      expect(r.available, isFalse);
    });
  });

  group('stale / mismatched plan identity', () {
    test(
        'a different project/plan\'s successful result does not satisfy '
        'THIS approvedPackageId', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-current',
        lastResult: _result(
          planId: 'pkg-OLD-or-other-project@t1',
          outcomes: [_outcome(HardwareWriteOpStatus.written)],
        ),
      );
      expect(r.available, isFalse);
      expect(r.blockedReason, contains('일치하는'));
    });

    test(
        'an EARLIER Room generation\'s successful result does not satisfy '
        'a NEWER approvedPackageId after regenerating candidates', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'room-auto-peq-proj-2',
        lastResult: _result(
          planId: 'room-auto-peq-proj-1@t1', // superseded generation
          outcomes: [_outcome(HardwareWriteOpStatus.written)],
        ),
      );
      expect(r.available, isFalse);
    });
  });

  group('the only path to available', () {
    test(
        'matching planId prefix + every op written (readback-verified) '
        '-> available', () {
      final r = RoomAfterGate.evaluate(
        approvedPackageId: 'pkg-1',
        lastResult: _result(
          planId: 'pkg-1@2025-01-01T00:00:00.000Z',
          outcomes: [
            _outcome(HardwareWriteOpStatus.written),
            _outcome(HardwareWriteOpStatus.written, channelId: 'ch_wf_r'),
          ],
        ),
      );
      expect(r.available, isTrue);
      expect(r.blockedReason, isNull);
    });
  });
}
