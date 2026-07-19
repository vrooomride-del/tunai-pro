import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/features/workbench/widgets/hardware_apply_preview.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
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

void main() {
  testWidgets('renders device, counts, and the safety notice', (tester) async {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peq('wf', {
          'band_0': {'freq_hz': 1000.0, 'gain_db': -3.0, 'q': 1.0, 'type': 'peak'},
          'band_1': {'freq_hz': 2500.0, 'gain_db': 2.0, 'q': 1.0, 'type': 'peak'},
        })
      ]),
      HardwareDeviceProfiles.adau1701Icp5,
    );

    await tester.pumpWidget(_wrap(HardwareApplyPreview(plan: plan)));

    expect(find.text('HARDWARE APPLY PREVIEW'), findsOneWidget);
    expect(find.text('ADAU1701 (ICP5)'), findsOneWidget);
    // Counts present.
    expect(find.text('TOTAL OPS'), findsOneWidget);
    expect(find.text('WRITABLE'), findsOneWidget);
    expect(find.text('BLOCKED'), findsOneWidget);
    expect(find.text('CAPTURE PROVEN'), findsOneWidget);
    expect(find.text('UNVERIFIED'), findsOneWidget);
    expect(find.text('UNAVAILABLE'), findsOneWidget);
    // Writable section shows the 2 proven ops (band0 gain + freq).
    expect(find.text('WRITABLE OPERATIONS (2)'), findsOneWidget);
    // Explicit approval notice.
    expect(
        find.textContaining('Hardware write is not implemented / requires approval'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ADAU1466 developer plan shows zero writable operations',
      (tester) async {
    final plan = buildHardwareWritePlan(
      _pkg([
        _peq('l', {
          'band_0': {'freq_hz': 1000.0, 'gain_db': -3.0, 'q': 1.0, 'type': 'peak'},
        })
      ]),
      HardwareDeviceProfiles.adau1466Developer,
    );

    await tester.pumpWidget(_wrap(HardwareApplyPreview(plan: plan)));

    expect(find.text('WRITABLE OPERATIONS (0)'), findsOneWidget);
    expect(find.text('No capture-proven operations in this plan.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty plan renders without throwing', (tester) async {
    final plan =
        buildHardwareWritePlan(_pkg([]), HardwareDeviceProfiles.adau1701Icp5);
    await tester.pumpWidget(_wrap(HardwareApplyPreview(plan: plan)));
    expect(find.text('BLOCKED OPERATIONS (0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('label helpers format parameter, band, and value', () {
    expect(HardwareApplyPreview.paramLabel(HardwareParamKind.peqGain), 'PEQ Gain');
    expect(HardwareApplyPreview.bandLabel(0), 'Band 1');
    expect(HardwareApplyPreview.bandLabel(null), '—');
    const gainOp = HardwareWriteOp(
      channelId: 'wf',
      parameterKind: HardwareParamKind.peqGain,
      bandIndex: 0,
      targetValue: -3,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'x',
    );
    expect(HardwareApplyPreview.valueLabel(gainOp), '-3 dB');
  });
}
