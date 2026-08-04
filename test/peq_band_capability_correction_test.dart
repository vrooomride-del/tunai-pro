// PEQ Band Capability Correction — real-hardware deploy evidence:
//   Band index 0-7 (PEQ Band 1-8): deploy succeeds on real hardware.
//   Band index 8-9 (PEQ Band 9-10): deploy fails on real hardware.
// frame builder, ACK parser, and channel mapping apply zero band-8/9-
// specific handling (audited separately) — this is not a protocol bug, the
// currently-compiled ADAU1701 DSP profile does not support bands 9-10.
//
// pro_hardware_capability.dart's PEQ bandIndex:null captureProven fallback
// was removed and replaced with explicit per-band entries (0-7 captureProven,
// 8-9 unavailable). These tests confirm that correction end to end through
// the existing capability lookup structure (HardwareCapabilityEntry.bandIndex,
// verificationFor(), isWriteEligible()) — no new gating logic.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_approval.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

const _adau1701 = HardwareDeviceProfiles.adau1701Icp5;

ExportParameterBlock _peqBlock(String channelId, Map<String, dynamic> bands) =>
    ExportParameterBlock(
      id: 'blk_peq_$channelId',
      type: ExportBlockType.peq,
      channelId: channelId,
      title: 'PEQ — $channelId',
      summary: '',
      parameters: {'bands': bands, 'bandCount': bands.length},
    );

Map<String, dynamic> _band(double f, double g, double q) =>
    {'freq_hz': f, 'gain_db': g, 'q': q, 'type': 'peak'};

DspExportPackage _pkg(List<ExportParameterBlock> blocks) =>
    DspExportPackage(id: 'exp1', parameterBlocks: blocks);

/// Full 10-band map (band_0 .. band_9), so a single plan build exercises
/// every band index at once.
Map<String, dynamic> _allTenBands() => {
      for (var i = 0; i < 10; i++) 'band_$i': _band(1000.0 + i, 1.0, 1.0),
    };

/// Records every op actually handed to preflightAndWrite — proves a blocked
/// op never reaches the executor/port.
class _RecordingPort implements Icp5PeqWritePort {
  final List<HardwareWriteOp> received = [];

  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op) async {
    received.add(op);
    return Adau1701DeploymentReport(
      attemptedAt: DateTime(2026, 8, 4),
      originalStateAvailable: false,
      preflightStatus: Adau1701PreflightStatus.passed,
      deploymentAllowed: true,
      deploymentResult: const Icp5PhaseCResult(
        success: true,
        wasActualWrite: true,
        writeMayHaveReachedDevice: true,
        message: 'PASS_ACK',
      ),
    );
  }
}

void main() {
  group('Capability blocking — bands 8-9 unavailable', () {
    final plan = buildHardwareWritePlan(_pkg([_peqBlock('wf', _allTenBands())]), _adau1701);

    for (final band in [8, 9]) {
      test('band $band peqFrequency/peqGain/peqQ: writable=false, blocked reason exists', () {
        for (final kind in [
          HardwareParamKind.peqFrequency,
          HardwareParamKind.peqGain,
          HardwareParamKind.peqQ,
        ]) {
          final op = plan.operations.firstWhere(
              (o) => o.parameterKind == kind && o.bandIndex == band);
          expect(op.writable, isFalse,
              reason: 'band $band ${kind.name} must not be writable');
          expect(op.verification, HardwareParamVerification.unavailable);
          expect(op.reason, isNotEmpty,
              reason: 'a blocked op must always carry a reason');
          expect(op.reason, contains('Band 9-10'),
              reason: 'blocked reason must name the actual unsupported range');
        }
      });
    }

    test('bands 8-9 are excluded from writableOperations entirely', () {
      final band89Ops = plan.writableOperations
          .where((o) => o.bandIndex == 8 || o.bandIndex == 9)
          .toList();
      expect(band89Ops, isEmpty);
    });

    test('bands 8-9 never reach the executor/write port', () async {
      final port = _RecordingPort();
      final approval = HardwareWriteApproval.approve(plan, approver: 'test');
      // Approval itself must already exclude bands 8-9.
      expect(
          approval.approvedOperations
              .where((o) => o.bandIndex == 8 || o.bandIndex == 9),
          isEmpty);

      await HardwareWriteExecutor(port).execute(approval);

      expect(port.received.where((o) => o.bandIndex == 8 || o.bandIndex == 9),
          isEmpty,
          reason: 'band 8/9 ops must never be sent to preflightAndWrite');
    });
  });

  group('Regression — bands 0-7 remain writable (unchanged)', () {
    final plan = buildHardwareWritePlan(_pkg([_peqBlock('wf', _allTenBands())]), _adau1701);

    for (var band = 0; band <= 7; band++) {
      test('band $band peqFrequency/peqGain/peqQ: writable=true, captureProven', () {
        for (final kind in [
          HardwareParamKind.peqFrequency,
          HardwareParamKind.peqGain,
          HardwareParamKind.peqQ,
        ]) {
          final op = plan.operations.firstWhere(
              (o) => o.parameterKind == kind && o.bandIndex == band);
          expect(op.writable, isTrue,
              reason: 'band $band ${kind.name} must remain writable');
          expect(op.verification, HardwareParamVerification.captureProven);
        }
      });
    }

    test('bands 0-7 all reach the executor/write port and succeed', () async {
      final port = _RecordingPort();
      final approval = HardwareWriteApproval.approve(plan, approver: 'test');
      final band07Approved =
          approval.approvedOperations.where((o) => (o.bandIndex ?? -1) <= 7).toList();
      // 8 bands x 3 kinds (frequency, gain, Q).
      expect(band07Approved.length, 24);

      final result = await HardwareWriteExecutor(port).execute(approval);

      expect(port.received.where((o) => (o.bandIndex ?? -1) <= 7).length, 24);
      expect(result.outcomes.every((o) => o.succeeded), isTrue);
    });
  });
}
