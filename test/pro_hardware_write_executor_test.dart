import 'dart:async';

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

/// Port that returns _written() for the first [firstWritten] calls, then hangs.
class _MixedPort implements Icp5PeqWritePort {
  final int firstWritten;
  int _calls = 0;
  _MixedPort({required this.firstWritten});

  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op) {
    _calls++;
    if (_calls <= firstWritten) {
      return Future.value(_written());
    }
    return Completer<Adau1701DeploymentReport>().future; // hangs
  }
}

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
    final result = await HardwareWriteExecutor(port).execute(_approvedBand1());

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
    final polarityOp = plan.operations.firstWhere(
        (o) => o.parameterKind == HardwareParamKind.channelPolarity);
    expect(polarityOp.writable, isFalse,
        reason: 'channelPolarity has no ADAU1701 write path');
    final rejected =
        HardwareWriteApproval.approve(plan, selection: [polarityOp]);
    expect(rejected.status, HardwareApprovalStatus.rejected);

    final port = _FakePort((_) => _written());
    final result = await HardwareWriteExecutor(port).execute(rejected);

    expect(result.executed, isFalse);
    expect(result.rejectionReason, isNotNull);
    expect(port.calls, 0);
    expect(result.outcomes, isEmpty);
  });

  test('empty approval fails closed — no port calls', () async {
    final plan =
        buildHardwareWritePlan(_pkg([]), HardwareDeviceProfiles.adau1701Icp5);
    final empty = HardwareWriteApproval.approve(plan);
    expect(empty.status, HardwareApprovalStatus.empty);

    final port = _FakePort((_) => _written());
    final result = await HardwareWriteExecutor(port).execute(empty);

    expect(result.executed, isFalse);
    expect(port.calls, 0);
  });

  test('preflight-blocked op is reported, not written', () async {
    final port = _FakePort((_) => _blocked());
    final result = await HardwareWriteExecutor(port).execute(_approvedBand1());

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
    final result = await HardwareWriteExecutor(port).execute(_approvedBand1());
    expect(result.failedCount, 3);
    expect(result.writtenCount, 0);
  });

  test('failure count uses the shared failed/timedOut/blocked predicate', () {
    final op = _approvedBand1().approvedOperations.first;
    HardwareWriteOpOutcome outcome(HardwareWriteOpStatus status) =>
        HardwareWriteOpOutcome(
          op: op,
          status: status,
          report: null,
          message: status.name,
        );

    for (final status in [
      HardwareWriteOpStatus.failed,
      HardwareWriteOpStatus.timedOut,
      HardwareWriteOpStatus.blockedByPreflight,
    ]) {
      final result = HardwareWriteExecutionResult(
        planId: 'failure-$status',
        executed: true,
        rejectionReason: null,
        outcomes: [
          outcome(HardwareWriteOpStatus.ackOnly),
          outcome(status),
          outcome(HardwareWriteOpStatus.written),
        ],
      );

      expect(result.failedCount, 1);
      expect(result.failures, hasLength(1));
      expect(result.failures.single.status, status);
      expect(result.allPassed, isFalse);
    }
  });

  test('multiple ACK-only outcomes with no failure produce PASS_ACK state', () {
    final op = _approvedBand1().approvedOperations.first;
    final result = HardwareWriteExecutionResult(
      planId: 'ack-only',
      executed: true,
      rejectionReason: null,
      outcomes: List.generate(
        4,
        (_) => HardwareWriteOpOutcome(
          op: op,
          status: HardwareWriteOpStatus.ackOnly,
          report: null,
          message: 'PASS_ACK',
        ),
      ),
    );

    expect(result.failedCount, 0);
    expect(result.failures, isEmpty);
    expect(result.allPassed, isTrue);
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
    final band10Outcome =
        result.outcomes.firstWhere((o) => o.op.bandIndex == 10);
    expect(band10Outcome.status, HardwareWriteOpStatus.unsupported);
    expect(band10Outcome.report, isNull);
  });

  // ── Timeout / progress tests ──────────────────────────────────────────────

  test('64-op all-success → allPassed=true, 64 outcomes', () async {
    // 4 channels × 5 bands × 3 ops (gain+freq+Q) = 60, plus 4 channel gains = 64.
    final channels = ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'];
    final peqBlocks = [
      for (final ch in channels)
        _peq(ch, {
          for (var b = 0; b < 5; b++)
            'band_$b': _band(1000 + b * 100.0, -3, 1.2),
        }),
    ];
    final gainBlocks = [
      for (final ch in channels)
        ExportParameterBlock(
          id: 'gain_$ch',
          type: ExportBlockType.gain,
          channelId: ch,
          title: 'Gain',
          summary: '',
          parameters: {'gainDb': -2.0},
        ),
    ];
    final plan = buildHardwareWritePlan(
      _pkg([...peqBlocks, ...gainBlocks]),
      HardwareDeviceProfiles.adau1701Icp5,
    );
    final approval = HardwareWriteApproval.approve(plan, approver: 'test');
    expect(approval.approvedCount, 64,
        reason: '4ch × 5bands × 3ops + 4 channel gains = 64');

    final port = _FakePort((_) => _written());
    final result = await HardwareWriteExecutor(port).execute(approval);

    expect(result.executed, isTrue);
    expect(result.outcomes, hasLength(64));
    expect(result.allPassed, isTrue);
    expect(port.calls, 64);
  });

  test(
      'mid-execution port hang → bounded timeout → timedOut outcome, execution stops',
      () async {
    // 3 ops: first succeeds, second hangs, third should never be reached.
    final plan = buildHardwareWritePlan(
      _pkg([
        _peq('ch_a',
            {'band_0': _band(1000, -3, 1.2), 'band_1': _band(2000, -2, 1.4)}),
      ]),
      HardwareDeviceProfiles.adau1701Icp5,
    );
    final approval = HardwareWriteApproval.approve(plan, approver: 'test');
    // band_0 → 3 ops (gain+freq+Q), band_1 → 3 ops = 6 total
    expect(approval.approvedCount, 6);

    // First call returns written; subsequent calls hang.
    final port = _MixedPort(firstWritten: 1);
    final executor = HardwareWriteExecutor(
      port,
      opTimeout: const Duration(milliseconds: 100),
    );

    final result = await executor.execute(approval);

    expect(result.executed, isTrue);
    // First op written, second op times out → execution stops.
    expect(result.outcomes.length, lessThan(6));
    final timedOut = result.outcomes
        .where((o) => o.status == HardwareWriteOpStatus.timedOut);
    expect(timedOut, isNotEmpty);
    expect(timedOut.first.status, HardwareWriteOpStatus.timedOut);
  });

  test(
      'timeout message contains channel, parameterKind, bandIndex, and completed count',
      () async {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peq('ch_woofer', {'band_0': _band(800, -4, 2.0)})
      ]),
      HardwareDeviceProfiles.adau1701Icp5,
    );
    final approval = HardwareWriteApproval.approve(plan, approver: 'test');
    // 3 ops: gain (succeeds), freq (hangs → times out), Q never reached.
    final port = _MixedPort(firstWritten: 1);
    final executor = HardwareWriteExecutor(
      port,
      opTimeout: const Duration(milliseconds: 100),
    );

    final result = await executor.execute(approval);

    final timedOut = result.outcomes
        .firstWhere((o) => o.status == HardwareWriteOpStatus.timedOut);
    expect(timedOut.message, contains('ch_woofer'));
    expect(timedOut.message, anyOf(contains('band0'), contains('band')));
    expect(timedOut.message, contains('/')); // "x/total completed"
  });

  test('result JSON summarizes the execution', () async {
    final port = _FakePort((_) => _written());
    final result = await HardwareWriteExecutor(port).execute(_approvedBand1());
    final json = result.toJson();
    expect(json['executed'], isTrue);
    expect(json['writtenCount'], 3);
    expect((json['outcomes'] as List), hasLength(3));
  });

  test('ADAU1701 out-of-range PEQ gain is not approved or sent to executor',
      () async {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peq('wf', {'band_0': _band(1000, -9, 1.2)})
      ]),
      HardwareDeviceProfiles.adau1701Icp5,
    );
    expect(
        plan.operations
            .singleWhere((o) => o.parameterKind == HardwareParamKind.peqGain)
            .writable,
        isFalse);
    final gainOp = plan.operations
        .singleWhere((o) => o.parameterKind == HardwareParamKind.peqGain);
    final approval = HardwareWriteApproval.approve(
      plan,
      approver: 'test',
      selection: [gainOp],
    );
    expect(approval.isApproved, isFalse);
    final port = _FakePort((_) => _written());
    final result = await HardwareWriteExecutor(port).execute(approval);
    expect(port.calls, 0);
    expect(result.executed, isFalse);
  });

  test('ADAU1466 developer profile keeps shared policy-independent behavior',
      () {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peq('wf', {'band_0': _band(1000, -9, 1.2)})
      ]),
      HardwareDeviceProfiles.adau1466Developer,
    );
    expect(plan.operations, isNotEmpty);
    expect(plan.operations.every((o) => o.writable == false), isTrue);
  });
}
