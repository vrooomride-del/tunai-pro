import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_approval.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_export_data.dart';

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

// A plan with band 0 (3 writable ops: peqFrequency + peqGain + peqQ, all captureProven) on ADAU1701.
HardwareWritePlan _provenPlan() => buildHardwareWritePlan(
      _pkg([
        _peq('wf', {'band_0': _band(1000, -3, 1.2)})
      ]),
      HardwareDeviceProfiles.adau1701Icp5,
      generatedAt: DateTime(2026, 7, 19),
    );

// A plan that contains a channelPolarity op (unavailable → not writable)
// alongside writable PEQ ops. Used to test rejection of blocked ops.
HardwareWritePlan _planWithPolarityOp() => buildHardwareWritePlan(
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

void main() {
  test('approving writable ops succeeds', () {
    final plan = _provenPlan();
    final approval = HardwareWriteApproval.approve(plan,
        approver: 'expert', approvedAt: DateTime(2026, 7, 19, 12));

    expect(approval.status, HardwareApprovalStatus.approved);
    expect(approval.isApproved, isTrue);
    expect(approval.approvedCount, 3); // band0 gain + frequency + Q; all captureProven
    expect(approval.approver, 'expert');
    expect(approval.rejectionReason, isNull);
    // Every approved op is capture-proven.
    for (final o in approval.approvedOperations) {
      expect(o.writable, isTrue);
      expect(o.verification, HardwareParamVerification.captureProven);
    }
    expect(approval.planId, HardwareWriteApproval.planIdFor(plan));
  });

  test('approved operations list is immutable', () {
    final approval = HardwareWriteApproval.approve(_provenPlan());
    expect(() => approval.approvedOperations.clear(), throwsUnsupportedError);
  });

  test('selecting a blocked (unavailable) op is rejected — nothing approved', () {
    // channelPolarity is unavailable (no entry in ADAU1701 profile) → not writable.
    final plan = _planWithPolarityOp();
    final polarityOp = plan.operations
        .firstWhere((o) => o.parameterKind == HardwareParamKind.channelPolarity);
    expect(polarityOp.writable, isFalse,
        reason: 'channelPolarity has no ADAU1701 write path');

    final approval =
        HardwareWriteApproval.approve(plan, selection: [polarityOp]);
    expect(approval.status, HardwareApprovalStatus.rejected);
    expect(approval.isApproved, isFalse);
    expect(approval.approvedOperations, isEmpty);
    expect(approval.rejectionReason, isNotNull);
  });

  test('a selection mixing writable + blocked is rejected wholesale', () {
    final plan = _planWithPolarityOp();
    final gain = plan.operations.firstWhere(
        (o) => o.parameterKind == HardwareParamKind.peqGain && o.writable);
    final polarityOp = plan.operations
        .firstWhere((o) => o.parameterKind == HardwareParamKind.channelPolarity);

    final approval =
        HardwareWriteApproval.approve(plan, selection: [gain, polarityOp]);
    expect(approval.status, HardwareApprovalStatus.rejected);
    expect(approval.approvedOperations, isEmpty);
  });

  test('empty plan fails closed', () {
    final plan = buildHardwareWritePlan(
        _pkg([]), HardwareDeviceProfiles.adau1701Icp5);
    final approval = HardwareWriteApproval.approve(plan);
    expect(approval.status, HardwareApprovalStatus.empty);
    expect(approval.isApproved, isFalse);
    expect(approval.approvedOperations, isEmpty);
    expect(approval.rejectionReason, isNotNull);
  });

  test('plan with no writable ops (ADAU1466) fails closed', () {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peq('l', {'band_0': _band(1000, -3, 1.0)})
      ]),
      HardwareDeviceProfiles.adau1466Developer,
    );
    expect(plan.operations, isNotEmpty);
    final approval = HardwareWriteApproval.approve(plan);
    expect(approval.status, HardwareApprovalStatus.empty);
    expect(approval.approvedOperations, isEmpty);
  });

  test('foreign writable-looking op (not in plan) is rejected', () {
    final plan = _provenPlan();
    const foreign = HardwareWriteOp(
      channelId: 'x',
      parameterKind: HardwareParamKind.peqGain,
      bandIndex: 0,
      targetValue: 1,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'fabricated',
    );
    final approval = HardwareWriteApproval.approve(plan, selection: [foreign]);
    expect(approval.status, HardwareApprovalStatus.rejected);
  });

  test('JSON captures the decision', () {
    final approval = HardwareWriteApproval.approve(_provenPlan(),
        approver: 'expert', approvedAt: DateTime(2026, 7, 19, 12));
    final json = approval.toJson();
    expect(json['status'], 'approved');
    expect(json['approver'], 'expert');
    expect(json['deviceId'], 'adau1701-icp5');
    expect((json['approvedOperations'] as List), hasLength(3));
  });
}
