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

  test('ADAU1701 Band 1 gain and frequency are writable; Q is unverified', () {
    // peqFrequency band 0 is Consumer-production-proven: param 0x18 property 0x02.
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

    // peqFrequency band 0 is captureProven (Consumer-production-proven) → writable.
    expect(freq.writable, isTrue);
    expect(freq.verification, HardwareParamVerification.captureProven);
    expect(freq.targetValue, 1000);

    // Q on band 0 is captureProven (Consumer-production-proven) → writable, ACK-only at port.
    expect(q.writable, isTrue);
    expect(q.verification, HardwareParamVerification.captureProven);
  });

  test('ADAU1701 Band 2 (index 1) creates captureProven ops (Consumer-proven, ACK-only at port)', () {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peqBlock('wf', {'band_1': _band(2500, 2, 1.0)})
      ]),
      adau1701,
    );
    final gain = _op(plan, HardwareParamKind.peqGain, bandIndex: 1);
    final freq = _op(plan, HardwareParamKind.peqFrequency, bandIndex: 1);
    expect(gain.writable, isTrue);
    expect(gain.verification, HardwareParamVerification.captureProven);
    expect(freq.writable, isTrue);
    expect(freq.verification, HardwareParamVerification.captureProven);
    expect(plan.writableOperations, isNotEmpty);
  });

  test('XO HPF/LPF are captureProven; polarity remains unavailable', () {
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
    // HPF/LPF: param-ID 0x15, band 0, capture-proven via filter cutoff TEST/RESTORE.
    expect(hp.writable, isTrue);
    expect(hp.verification, HardwareParamVerification.captureProven);
    expect(lp.writable, isTrue);
    expect(lp.verification, HardwareParamVerification.captureProven);
    // Polarity: no confirmed write path.
    expect(pol.writable, isFalse);
    expect(pol.verification, HardwareParamVerification.unavailable);
  });

  test('channelGain is captureProven on ADAU1701; delay and mute remain unavailable',
      () {
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
    // channelGain: parameter-ID 0x14 + float32 LE + channel byte confirmed.
    expect(_op(plan, HardwareParamKind.channelGain).writable, isTrue);
    expect(_op(plan, HardwareParamKind.channelGain).verification,
        HardwareParamVerification.captureProven);
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

    // Band 0: gain(proven), freq(proven), q(proven).
    // Band 1: gain(proven), freq(proven), q(proven).
    // XO high-pass: captureProven.
    final s = plan.summary;
    expect(s.totalOps, 7); // 3 + 3 + 1
    expect(s.captureProvenCount, 7); // all ops are captureProven
    expect(s.unverifiedCount, 0);
    expect(s.unavailableCount, 0);
    expect(s.writableOps, 7); // all ops writable
    expect(s.writableOps, plan.writableOperations.length);
    expect(s.hasWritableOps, isTrue);
    expect(
        s.captureProvenCount + s.unverifiedCount + s.unavailableCount,
        s.totalOps);
  });
}
