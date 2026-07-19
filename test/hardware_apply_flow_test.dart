import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/widgets/hardware_apply_flow.dart';

const _kDeviceId = 'DSP1701.100.00.01';

List<int> _stateAPayload() {
  final p = List<int>.filled(513, 0x00);
  p[19] = 0x08;
  p[20] = 0x07;
  p[21] = 0xF6;
  p[23] = 0x14;
  p[24] = 0x01;
  p[154] = 0x01;
  p[308] = 0x02;
  return p;
}

// Fake transport that decodes to ch0/band0 = 1800 Hz, -1.0 dB (matches the
// export package below so writes verify).
class _FakeTransport implements Adau1701TuningTransport {
  final bool connected;
  _FakeTransport({this.connected = true});
  final List<(int, double)> gainWrites = [];
  final List<(int, int)> freqWrites = [];

  @override
  bool get isConnected => connected;
  @override
  bool get handshakeComplete => connected;
  @override
  String? get detectedProfile => connected ? _kDeviceId : null;
  @override
  Future<RawDspStateSnapshot> readRawDspState() async => RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2025, 6, 1, 12),
        blockId: 0x2202,
        payload: _stateAPayload(),
      );
  @override
  Future<Adau1701WriteAck> writePeqGain(int c, double g, {int band = 0}) async {
    gainWrites.add((c, g));
    return const Adau1701WriteAck(success: true, message: 'ok');
  }

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int c, int f,
      {int band = 0}) async {
    freqWrites.add((c, f));
    return const Adau1701WriteAck(success: true, message: 'ok');
  }

  @override
  Future<Adau1701WriteAck> writePeqQ(int c, double q, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
}

DspExportPackage _pkg() => DspExportPackage(id: 'exp1', parameterBlocks: [
      const ExportParameterBlock(
        id: 'blk',
        type: ExportBlockType.peq,
        channelId: 'wf',
        title: 'PEQ',
        summary: '',
        parameters: {
          'bands': {
            'band_0': {'freq_hz': 1800.0, 'gain_db': -1.0, 'q': 2.0, 'type': 'peak'},
          }
        },
      ),
    ]);

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Finder _btn(String label) => find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<OutlinedButton>(),
    );

void main() {
  testWidgets('renders preview + both gate buttons; apply disabled initially',
      (tester) async {
    await tester.pumpWidget(_wrap(HardwareApplyFlow(
      exportPackage: _pkg(),
      profile: HardwareDeviceProfiles.adau1701Icp5,
      contextFactory: () =>
          Adau1701HardwareContext.fromTransport(_FakeTransport(connected: false)),
    )));

    expect(find.text('HARDWARE APPLY PREVIEW'), findsOneWidget);
    expect(_btn('APPROVE VERIFIED WRITE'), findsOneWidget);
    expect(_btn('APPLY VERIFIED SETTINGS'), findsOneWidget);
    // Apply disabled before approval.
    expect(tester.widget<OutlinedButton>(_btn('APPLY VERIFIED SETTINGS')).onPressed,
        isNull);
  });

  testWidgets('approve then not-ready → apply stays disabled with a note',
      (tester) async {
    await tester.pumpWidget(_wrap(HardwareApplyFlow(
      exportPackage: _pkg(),
      profile: HardwareDeviceProfiles.adau1701Icp5,
      contextFactory: () =>
          Adau1701HardwareContext.fromTransport(_FakeTransport(connected: false)),
    )));

    await tester.tap(_btn('APPROVE VERIFIED WRITE'));
    await tester.pump();

    expect(find.textContaining('Approved 2 operation'), findsOneWidget);
    expect(find.textContaining('Hardware not ready'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_btn('APPLY VERIFIED SETTINGS')).onPressed,
        isNull);
  });

  testWidgets('approve + apply on a ready context writes and shows results',
      (tester) async {
    final transport = _FakeTransport();
    await tester.pumpWidget(_wrap(HardwareApplyFlow(
      exportPackage: _pkg(),
      profile: HardwareDeviceProfiles.adau1701Icp5,
      contextFactory: () => Adau1701HardwareContext.fromTransport(transport),
    )));

    await tester.tap(_btn('APPROVE VERIFIED WRITE'));
    await tester.pump();
    // Apply now enabled.
    expect(tester.widget<OutlinedButton>(_btn('APPLY VERIFIED SETTINGS')).onPressed,
        isNotNull);

    await tester.tap(_btn('APPLY VERIFIED SETTINGS'));
    await tester.pumpAndSettle();

    // Both proven ops were written through the transport.
    expect(transport.gainWrites, [(0, -1.0)]);
    expect(transport.freqWrites, [(0, 1800)]);
    expect(find.text('APPLY RESULTS'), findsOneWidget);
    expect(find.text('WRITTEN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
