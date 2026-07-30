import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_approval.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// ── Fakes / helpers ───────────────────────────────────────────────────────────

class _FakePort implements Icp5PeqWritePort {
  final Adau1701DeploymentReport Function(HardwareWriteOp) responder;
  int calls = 0;
  final List<HardwareWriteOp> received = [];
  _FakePort(this.responder);

  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op) async {
    calls++;
    received.add(op);
    return responder(op);
  }
}

Adau1701DeploymentReport _written() => Adau1701DeploymentReport(
      attemptedAt: DateTime(2026, 7, 19),
      originalStateAvailable: true,
      preflightStatus: Adau1701PreflightStatus.passed,
      deploymentAllowed: true,
      deploymentResult: const Icp5PhaseCResult(
          success: true,
          wasActualWrite: true,
          writeMayHaveReachedDevice: true,
          message: 'ok'),
    );

Adau1701DeploymentReport _blocked() => Adau1701DeploymentReport(
      attemptedAt: DateTime(2026, 7, 19),
      originalStateAvailable: false,
      preflightStatus: Adau1701PreflightStatus.transportNotReady,
      preflightFailureReason: 'transport not ready',
      deploymentAllowed: false,
    );

Adau1701DeploymentReport _failed() => Adau1701DeploymentReport(
      attemptedAt: DateTime(2026, 7, 19),
      originalStateAvailable: true,
      preflightStatus: Adau1701PreflightStatus.passed,
      deploymentAllowed: true,
      deploymentResult: const Icp5PhaseCResult(
          success: false,
          wasActualWrite: false,
          writeMayHaveReachedDevice: false,
          message: 'nack'),
    );

DspExportPackage _pkg(List<ExportParameterBlock> blocks) =>
    DspExportPackage(id: 'exp1', parameterBlocks: blocks);

ExportParameterBlock _peq(String ch, Map<String, dynamic> bands) =>
    ExportParameterBlock(
      id: 'blk_$ch',
      type: ExportBlockType.peq,
      channelId: ch,
      title: 'PEQ',
      summary: '',
      parameters: {'bands': bands},
    );

Map<String, dynamic> _band(double f, double g, double q) =>
    {'freq_hz': f, 'gain_db': g, 'q': q, 'type': 'peak'};

// Band 0 on ADAU1701 → gain + frequency + Q are all captureProven (3 ops).
HardwareWriteApproval _approvedBand1() {
  final plan = buildHardwareWritePlan(
    _pkg([
      _peq('wf', {'band_0': _band(1000, -3, 1.2)})
    ]),
    HardwareDeviceProfiles.adau1701Icp5,
  );
  return HardwareWriteApproval.approve(plan, approver: 'expert');
}

void main() {
  test('supported writable ops execute through the port and are written',
      () async {
    final port = _FakePort((_) => _written());
    final result =
        await HardwareWriteExecutor(port).execute(_approvedBand1());

    expect(result.executed, isTrue);
    expect(port.calls, 3); // band0 gain + frequency + Q; all captureProven
    expect(result.writtenCount, 3);
    expect(result.allWritten, isTrue);
    expect(result.allPassed, isTrue);
    expect(result.unsupportedCount, 0);
    for (final o in result.outcomes) {
      expect(o.status, HardwareWriteOpStatus.written);
    }
  });

  test('rejected approval is refused — no port calls', () async {
    // channelPolarity is unavailable on ADAU1701 → selecting it is rejected.
    final plan = buildHardwareWritePlan(
      _pkg([
        _peq('wf', {'band_0': _band(1000, -3, 1.2)}),
        ExportParameterBlock(
          id: 'blk_xo',
          type: ExportBlockType.crossover,
          channelId: 'wf',
          title: 'XO',
          summary: '',
          parameters: {'polarityInverted': true},
        ),
      ]),
      HardwareDeviceProfiles.adau1701Icp5,
    );
    final polarityOp = plan.operations
        .firstWhere((o) => o.parameterKind == HardwareParamKind.channelPolarity);
    expect(polarityOp.writable, isFalse,
        reason: 'channelPolarity has no ADAU1701 write path');
    final rejected = HardwareWriteApproval.approve(plan, selection: [polarityOp]);
    expect(rejected.status, HardwareApprovalStatus.rejected);

    final port = _FakePort((_) => _written());
    final result = await HardwareWriteExecutor(port).execute(rejected);

    expect(result.executed, isFalse);
    expect(result.rejectionReason, isNotNull);
    expect(port.calls, 0);
    expect(result.outcomes, isEmpty);
  });

  test('empty approval fails closed — no port calls', () async {
    final plan = buildHardwareWritePlan(
        _pkg([]), HardwareDeviceProfiles.adau1701Icp5);
    final empty = HardwareWriteApproval.approve(plan);
    expect(empty.status, HardwareApprovalStatus.empty);

    final port = _FakePort((_) => _written());
    final result = await HardwareWriteExecutor(port).execute(empty);

    expect(result.executed, isFalse);
    expect(port.calls, 0);
  });

  test('preflight-blocked op is reported, not written', () async {
    final port = _FakePort((_) => _blocked());
    final result =
        await HardwareWriteExecutor(port).execute(_approvedBand1());

    expect(result.executed, isTrue);
    expect(port.calls, 3); // gain + frequency + Q; all blocked
    expect(result.writtenCount, 0);
    expect(result.blockedCount, 3);
    expect(result.allWritten, isFalse);
    expect(result.allPassed, isFalse);
    expect(result.outcomes.first.message, contains('transport not ready'));
  });

  test('preflight passes but write fails → failed outcome', () async {
    final port = _FakePort((_) => _failed());
    final result =
        await HardwareWriteExecutor(port).execute(_approvedBand1());
    expect(result.failedCount, 3);
    expect(result.writtenCount, 0);
  });

  test('approved-but-unsupported op fails closed without a port call',
      () async {
    // Custom profile proves peqGain for all bands (including band 10, which
    // is outside the executor's 0–9 range). The band-10 gain op is approved
    // but the executor has no writer for it → fails closed as unsupported.
    const provesHighBand = HardwareDeviceProfile(
      deviceId: 'adau1701-icp5',
      deviceName: 'ADAU1701 (ICP5)',
      transport: HardwareTransportType.icp5,
      capabilities: [
        HardwareCapabilityEntry(
            kind: HardwareParamKind.peqGain,
            bandIndex: 0,
            verification: HardwareParamVerification.captureProven),
        // Band-agnostic entry makes band 10 captureProven too.
        HardwareCapabilityEntry(
            kind: HardwareParamKind.peqGain,
            verification: HardwareParamVerification.captureProven),
      ],
    );
    // plan has band_0 gain (supported, bandIndex 0) + band_10 gain (unsupported, > 9)
    // freq/Q are NOT in provesHighBand → unavailable → not in approval.
    final plan = buildHardwareWritePlan(
      _pkg([
        _peq('wf', {
          'band_0': _band(1000, -3, 1.2),
          'band_10': _band(800, 0, 1.0),
        })
      ]),
      provesHighBand,
    );
    final approval = HardwareWriteApproval.approve(plan);
    // gain band 0 (supported) + gain band 10 (unsupported, > 9) both approved.
    expect(approval.status, HardwareApprovalStatus.approved);
    expect(approval.approvedCount, 2);

    final port = _FakePort((_) => _written());
    final result = await HardwareWriteExecutor(port).execute(approval);

    expect(result.executed, isTrue);
    // Only band-0 gain reaches the port; band-10 is failed-closed.
    expect(port.calls, 1);
    expect(result.writtenCount, 1);
    expect(result.unsupportedCount, 1);
    final band10Outcome = result.outcomes.firstWhere(
        (o) => o.op.bandIndex == 10);
    expect(band10Outcome.status, HardwareWriteOpStatus.unsupported);
    expect(band10Outcome.report, isNull);
  });

  test('result JSON summarizes the execution', () async {
    final port = _FakePort((_) => _written());
    final result =
        await HardwareWriteExecutor(port).execute(_approvedBand1());
    final json = result.toJson();
    expect(json['executed'], isTrue);
    expect(json['writtenCount'], 3);
    expect((json['outcomes'] as List), hasLength(3));
  });
}
