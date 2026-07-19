import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_export_data.dart';

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

HardwareWriteOp _op(HardwareWritePlan plan, HardwareParamKind kind,
        {int? bandIndex}) =>
    plan.operations.firstWhere(
        (o) => o.parameterKind == kind && o.bandIndex == bandIndex);

void main() {
  const adau1701 = HardwareDeviceProfiles.adau1701Icp5;
  const adau1466 = HardwareDeviceProfiles.adau1466Developer;

  test('reads only from parameterBlocks and stamps source id', () {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peqBlock('wf', {'band_0': _band(1000, -3, 1.0)})
      ]),
      adau1701,
      generatedAt: DateTime(2026, 7, 19),
    );
    expect(plan.sourceExportPackageId, 'exp1');
    expect(plan.deviceProfile.deviceId, 'adau1701-icp5');
    expect(plan.generatedAt, DateTime(2026, 7, 19));
  });

  test('ADAU1701 Band 1 gain + frequency create writable ops; Q does not', () {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peqBlock('wf', {'band_0': _band(1000, -3, 1.2)})
      ]),
      adau1701,
    );

    final gain = _op(plan, HardwareParamKind.peqGain, bandIndex: 0);
    final freq = _op(plan, HardwareParamKind.peqFrequency, bandIndex: 0);
    final q = _op(plan, HardwareParamKind.peqQ, bandIndex: 0);

    expect(gain.writable, isTrue);
    expect(gain.verification, HardwareParamVerification.captureProven);
    expect(gain.targetValue, -3);
    expect(freq.writable, isTrue);
    expect(freq.verification, HardwareParamVerification.captureProven);
    expect(freq.targetValue, 1000);

    // Q on band 0 exists but is unverified → not writable.
    expect(q.writable, isFalse);
    expect(q.verification, HardwareParamVerification.unverified);
  });

  test('ADAU1701 Band 2 (index 1) creates blocked (unverified) ops', () {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peqBlock('wf', {'band_1': _band(2500, 2, 1.0)})
      ]),
      adau1701,
    );
    final gain = _op(plan, HardwareParamKind.peqGain, bandIndex: 1);
    final freq = _op(plan, HardwareParamKind.peqFrequency, bandIndex: 1);
    expect(gain.writable, isFalse);
    expect(gain.verification, HardwareParamVerification.unverified);
    expect(freq.writable, isFalse);
    expect(freq.verification, HardwareParamVerification.unverified);
    expect(plan.writableOperations, isEmpty);
  });

  test('XO parameters are unavailable and not writable', () {
    final plan = buildHardwareWritePlan(
      _pkg([
        const ExportParameterBlock(
          id: 'blk_xo',
          type: ExportBlockType.crossover,
          channelId: 'wf',
          title: 'Crossover — wf',
          summary: '',
          parameters: {
            'highPass': {'freq_hz': 80.0, 'type': 'linkwitzRiley', 'slope': 'db24', 'enabled': true},
            'lowPass': {'freq_hz': 2500.0, 'type': 'linkwitzRiley', 'slope': 'db24', 'enabled': true},
            'polarityInverted': true,
          },
        )
      ]),
      adau1701,
    );
    final hp = _op(plan, HardwareParamKind.crossoverHighPass);
    final lp = _op(plan, HardwareParamKind.crossoverLowPass);
    final pol = _op(plan, HardwareParamKind.channelPolarity);
    for (final o in [hp, lp, pol]) {
      expect(o.writable, isFalse);
      expect(o.verification, HardwareParamVerification.unavailable);
    }
  });

  test('channel gain/delay/mute are unavailable on ADAU1701', () {
    final plan = buildHardwareWritePlan(
      _pkg([
        const ExportParameterBlock(
          id: 'blk_ctrl',
          type: ExportBlockType.delay,
          channelId: 'wf',
          title: 'Delay — wf',
          summary: '',
          parameters: {'gainDb': 2.0, 'delayMs': 0.5, 'muted': true},
        )
      ]),
      adau1701,
    );
    expect(_op(plan, HardwareParamKind.channelGain).writable, isFalse);
    expect(_op(plan, HardwareParamKind.channelDelay).writable, isFalse);
    expect(_op(plan, HardwareParamKind.channelMute).writable, isFalse);
  });

  test('ADAU1466 developer: every op is unavailable / not writable', () {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peqBlock('l', {'band_0': _band(1000, -3, 1.0), 'band_1': _band(2500, 2, 1.0)})
      ]),
      adau1466,
    );
    expect(plan.operations, isNotEmpty);
    for (final o in plan.operations) {
      expect(o.writable, isFalse);
      expect(o.verification, HardwareParamVerification.unavailable);
    }
    expect(plan.writableOperations, isEmpty);
  });

  test('protection block yields no ops', () {
    final plan = buildHardwareWritePlan(
      _pkg([
        const ExportParameterBlock(
          id: 'blk_prot',
          type: ExportBlockType.protection,
          channelId: 'system',
          title: 'Protection Summary',
          summary: '',
          parameters: {'verificationStatus': 'passed'},
        )
      ]),
      adau1701,
    );
    expect(plan.operations, isEmpty);
  });

  test('summary counts partition the operations correctly', () {
    // Band 0: gain(proven), freq(proven), q(unverified).
    // Band 1: gain(unverified), freq(unverified), q(unverified).
    // XO high-pass: unavailable.
    final plan = buildHardwareWritePlan(
      _pkg([
        _peqBlock('wf', {
          'band_0': _band(1000, -3, 1.0),
          'band_1': _band(2500, 2, 1.0),
        }),
        const ExportParameterBlock(
          id: 'blk_xo',
          type: ExportBlockType.crossover,
          channelId: 'wf',
          title: 'Crossover — wf',
          summary: '',
          parameters: {
            'highPass': {'freq_hz': 80.0, 'type': 'lr', 'slope': 'db24'},
          },
        ),
      ]),
      adau1701,
    );

    final s = plan.summary;
    expect(s.totalOps, 7); // 3 + 3 + 1
    expect(s.captureProvenCount, 2); // band0 gain + freq
    expect(s.unverifiedCount, 4); // band0 q + band1 gain/freq/q
    expect(s.unavailableCount, 1); // XO high-pass
    expect(s.writableOps, 2);
    expect(s.writableOps, plan.writableOperations.length);
    expect(s.hasWritableOps, isTrue);
    expect(
        s.captureProvenCount + s.unverifiedCount + s.unavailableCount,
        s.totalOps);
  });
}
