// Phase 3-F3 — RoomAutoPeqApproval / VerifiedDeploymentReceipt /
// PersistedRoomClosedLoopResult pure contract + JSON round-trip/corruption
// isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/core/room_workflow_persistence.dart';

HardwareWriteExecutionResult _writtenResult({
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

RoomSystemMeasurement _measurement({
  required RoomSystemSide side,
  required RoomMeasurementPhase phase,
  String id = 'm1',
  DateTime? capturedAt,
}) =>
    RoomSystemMeasurement(
      side: side,
      phase: phase,
      frd: _fakeFrd(id),
      capturedAt: capturedAt ?? DateTime.utc(2026, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: 'proj-1',
    );

ParsedMeasurementData _fakeFrd(String id) => ParsedMeasurementData(
      id: id,
      sourceFileName: '$id.frd',
      fileType: AcousticFileType.frd,
      importedAt: DateTime.utc(2026, 1, 1),
      points: const [MeasurementDataPoint(frequencyHz: 100, magnitudeDb: 0)],
    );

void main() {
  group('RoomAutoPeqApproval', () {
    test('JSON round-trip', () {
      final a = RoomAutoPeqApproval(
        projectId: 'proj-1',
        approvedPackageId: 'pkg-1',
        approvedAt: DateTime.utc(2026, 1, 1, 12),
      );
      final decoded = RoomAutoPeqApproval.fromJson(a.toJson())!;
      expect(decoded.projectId, 'proj-1');
      expect(decoded.approvedPackageId, 'pkg-1');
      expect(decoded.approvedAt, DateTime.utc(2026, 1, 1, 12));
    });

    test('missing approvedPackageId -> null, never a synthetic approval', () {
      expect(RoomAutoPeqApproval.fromJson({'projectId': 'proj-1'}), isNull);
    });

    test('missing projectId -> null', () {
      expect(
          RoomAutoPeqApproval.fromJson({'approvedPackageId': 'pkg-1'}), isNull);
    });

    test('corrupt map does not throw', () {
      expect(() => RoomAutoPeqApproval.fromJson({'approvedAt': 12345}),
          returnsNormally);
    });
  });

  group('VerifiedDeploymentReceipt.fromExecutionResult', () {
    test('matches the approved correction package -> receipt built', () {
      final r = VerifiedDeploymentReceipt.fromExecutionResult(
        result: _writtenResult(planId: 'pkg-1@2026-01-01T00:00:00.000Z'),
        projectId: 'proj-1',
        dspTarget: 'ADAU1701',
        approvedPackageId: 'pkg-1',
        rollbackApprovedPackageId: null,
        verifiedAt: DateTime.utc(2026, 1, 1),
      );
      expect(r, isNotNull);
      expect(r!.packageId, 'pkg-1');
      expect(r.executed, isTrue);
      expect(r.allReadbackVerified, isTrue);
    });

    test('matches the rollback package -> receipt built', () {
      final r = VerifiedDeploymentReceipt.fromExecutionResult(
        result:
            _writtenResult(planId: 'room-rollback-1@2026-01-01T00:00:00.000Z'),
        projectId: 'proj-1',
        dspTarget: 'ADAU1701',
        approvedPackageId: 'pkg-1',
        rollbackApprovedPackageId: 'room-rollback-1',
        verifiedAt: DateTime.utc(2026, 1, 1),
      );
      expect(r, isNotNull);
      expect(r!.packageId, 'room-rollback-1');
    });

    test('matches neither approved package -> null (Factory package etc.)', () {
      final r = VerifiedDeploymentReceipt.fromExecutionResult(
        result:
            _writtenResult(planId: 'guided-ai-xyz@2026-01-01T00:00:00.000Z'),
        projectId: 'proj-1',
        dspTarget: 'ADAU1701',
        approvedPackageId: 'pkg-1',
        rollbackApprovedPackageId: null,
        verifiedAt: DateTime.utc(2026, 1, 1),
      );
      expect(r, isNull);
    });

    test('ack-only result -> null, never creates a receipt', () {
      final r = VerifiedDeploymentReceipt.fromExecutionResult(
        result: _writtenResult(
          planId: 'pkg-1@2026-01-01T00:00:00.000Z',
          status: HardwareWriteOpStatus.ackOnly,
        ),
        projectId: 'proj-1',
        dspTarget: 'ADAU1701',
        approvedPackageId: 'pkg-1',
        rollbackApprovedPackageId: null,
        verifiedAt: DateTime.utc(2026, 1, 1),
      );
      expect(r, isNull);
    });

    test('failed result -> null', () {
      final r = VerifiedDeploymentReceipt.fromExecutionResult(
        result: _writtenResult(
          planId: 'pkg-1@2026-01-01T00:00:00.000Z',
          status: HardwareWriteOpStatus.failed,
        ),
        projectId: 'proj-1',
        dspTarget: 'ADAU1701',
        approvedPackageId: 'pkg-1',
        rollbackApprovedPackageId: null,
        verifiedAt: DateTime.utc(2026, 1, 1),
      );
      expect(r, isNull);
    });

    test('executed: false -> null', () {
      final r = VerifiedDeploymentReceipt.fromExecutionResult(
        result: _writtenResult(
            planId: 'pkg-1@2026-01-01T00:00:00.000Z', executed: false),
        projectId: 'proj-1',
        dspTarget: 'ADAU1701',
        approvedPackageId: 'pkg-1',
        rollbackApprovedPackageId: null,
        verifiedAt: DateTime.utc(2026, 1, 1),
      );
      expect(r, isNull);
    });

    test('no approval at all (both null) -> null', () {
      final r = VerifiedDeploymentReceipt.fromExecutionResult(
        result: _writtenResult(planId: 'pkg-1@2026-01-01T00:00:00.000Z'),
        projectId: 'proj-1',
        dspTarget: 'ADAU1701',
        approvedPackageId: null,
        rollbackApprovedPackageId: null,
        verifiedAt: DateTime.utc(2026, 1, 1),
      );
      expect(r, isNull);
    });
  });

  group('VerifiedDeploymentReceipt round-trip / matching / corruption', () {
    final receipt = VerifiedDeploymentReceipt(
      projectId: 'proj-1',
      packageId: 'pkg-1',
      planId: 'pkg-1@2026-01-01T00:00:00.000Z',
      dspTarget: 'ADAU1701',
      executed: true,
      allReadbackVerified: true,
      verifiedAt: DateTime.utc(2026, 1, 1),
    );

    test('JSON round-trip', () {
      final decoded = VerifiedDeploymentReceipt.fromJson(receipt.toJson())!;
      expect(decoded.projectId, 'proj-1');
      expect(decoded.packageId, 'pkg-1');
      expect(decoded.planId, receipt.planId);
      expect(decoded.executed, isTrue);
      expect(decoded.allReadbackVerified, isTrue);
    });

    test('matchesApprovedPackage true for the exact prefix', () {
      expect(receipt.matchesApprovedPackage('pkg-1'), isTrue);
    });

    test('matchesApprovedPackage false for a different package', () {
      expect(receipt.matchesApprovedPackage('pkg-2'), isFalse);
    });

    test('matchesApprovedPackage false for null', () {
      expect(receipt.matchesApprovedPackage(null), isFalse);
    });

    test(
        'a legacy/corrupt receipt claiming executed:false never decodes '
        'into a verified one', () {
      final j = receipt.toJson();
      j['executed'] = false;
      expect(VerifiedDeploymentReceipt.fromJson(j), isNull);
    });

    test('missing packageId -> null', () {
      final j = receipt.toJson();
      j.remove('packageId');
      expect(VerifiedDeploymentReceipt.fromJson(j), isNull);
    });

    test('malformed map does not throw', () {
      expect(() => VerifiedDeploymentReceipt.fromJson({'executed': 'nope'}),
          returnsNormally);
    });
  });

  group('PersistedRoomClosedLoopResult', () {
    test('JSON round-trip', () {
      final before = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(
            side: RoomSystemSide.left, phase: RoomMeasurementPhase.before),
        rightSystemFrd: _measurement(
            side: RoomSystemSide.right, phase: RoomMeasurementPhase.before),
      );
      final after = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(
            side: RoomSystemSide.left,
            phase: RoomMeasurementPhase.after,
            id: 'a1'),
        rightSystemFrd: _measurement(
            side: RoomSystemSide.right,
            phase: RoomMeasurementPhase.after,
            id: 'a2'),
      );
      final r = PersistedRoomClosedLoopResult.fromResult(
        projectId: 'proj-1',
        before: before,
        after: after,
        decision: CorrectionCycleDecision.improvedAndComplete,
        evaluatedAt: DateTime.utc(2026, 1, 1),
      );
      final decoded = PersistedRoomClosedLoopResult.fromJson(r.toJson())!;
      expect(decoded.projectId, 'proj-1');
      expect(decoded.decision, CorrectionCycleDecision.improvedAndComplete);
      expect(decoded.matchesCurrent(before, after), isTrue);
    });

    test('matchesCurrent false once After changes', () {
      final before = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(
            side: RoomSystemSide.left, phase: RoomMeasurementPhase.before),
        rightSystemFrd: _measurement(
            side: RoomSystemSide.right, phase: RoomMeasurementPhase.before),
      );
      final after = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(
            side: RoomSystemSide.left,
            phase: RoomMeasurementPhase.after,
            id: 'a1'),
        rightSystemFrd: _measurement(
            side: RoomSystemSide.right,
            phase: RoomMeasurementPhase.after,
            id: 'a2'),
      );
      final r = PersistedRoomClosedLoopResult.fromResult(
        projectId: 'proj-1',
        before: before,
        after: after,
        decision: CorrectionCycleDecision.improvedAndComplete,
        evaluatedAt: DateTime.utc(2026, 1, 1),
      );
      final newAfter = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(
            side: RoomSystemSide.left,
            phase: RoomMeasurementPhase.after,
            id: 'a1-new'),
        rightSystemFrd: _measurement(
            side: RoomSystemSide.right,
            phase: RoomMeasurementPhase.after,
            id: 'a2'),
      );
      expect(r.matchesCurrent(before, newAfter), isFalse);
    });

    test('unknown decision name -> null (never a fabricated decision)', () {
      expect(
          PersistedRoomClosedLoopResult.fromJson({
            'projectId': 'proj-1',
            'decision': 'not-a-real-decision',
            'evaluatedAt': DateTime.utc(2026).toIso8601String(),
            'beforeIdentity': '',
            'afterIdentity': '',
          }),
          isNull);
    });

    test('missing projectId -> null', () {
      expect(
          PersistedRoomClosedLoopResult.fromJson({
            'decision': 'improvedAndComplete',
          }),
          isNull);
    });

    test('malformed map does not throw', () {
      expect(() => PersistedRoomClosedLoopResult.fromJson({'decision': 12345}),
          returnsNormally);
    });
  });
}
