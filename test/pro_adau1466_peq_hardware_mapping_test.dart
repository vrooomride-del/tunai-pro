import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_3way_address_map_embedded.dart';
import 'package:tunai_pro/core/pro_adau1466_delay_audit_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_mute_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_peq_audit_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_xo_audit_registry.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/peq_tab.dart';

class _CountingBackend implements ProUsbiNativeBackend {
  int calls = 0;
  @override bool get isAvailable => true;
  @override bool get isFake => false;
  @override
  Future<List<int>?> sendPacketsAndReadAck({required List<int> setupPacket,
    required List<int> bodyPacket, required List<int> ackReadRequest}) async {
    calls++;
    return [1];
  }
}

void main() {
  test('embedded PEQ evidence reports count but contains no individual rows', () {
    expect(ProAdau1466PeqAuditRegistry.fullOriginalExportFound, isFalse);
    expect(ProAdau1466PeqAuditRegistry.requiredExportArtifact,
        'TUNAI_ADAU1466_v0_8B_GLOBAL_DRIVER_160BAND_PEQ.params');
    expect(ProAdau1466PeqAuditRegistry.requiredSigmaStudioOperation,
        contains('Export System Files'));
    expect(ProAdau1466PeqAuditRegistry.requiredSigmaStudioOperation,
        contains('without filtering PEQ rows'));
    expect(kTunaiAdau1466ThreeWayPeqRowCount, 875);
    expect(ProAdau1466PeqAuditRegistry.sourcePeqRowCount, 875);
    expect(ProAdau1466PeqAuditRegistry.embeddedPeqRowCount, 0);
    final registry = createTunaiAdau1466ThreeWayRegistry();
    expect(registry.peqRowCount, 875);
    expect(registry.addresses.where((entry) => entry.parameterKind.name == 'peq'),
        isEmpty);
  });

  test('exact six physical output mappings are retained without invented PEQ rows', () {
    expect(ProAdau1466PeqAuditRegistry.outputs.map((output) =>
      (output.channel, output.sigmaOutput, output.physicalOutput)), [
      ('WFL', 'Output1', 'OUT3'),
      ('MID_L', 'Output2', 'OUT2'),
      ('TWL', 'Output3', 'OUT1'),
      ('WFR', 'Output4', 'OUT8'),
      ('MID_R', 'Output5', 'OUT7'),
      ('TWR', 'Output6', 'OUT4'),
    ]);
  });

  test('representative band fails closed without baseline metadata', () {
    expect(ProAdau1466PeqAuditRegistry.selectedRepresentative,
        'WFL · L_WOOFER_PEQ_20 · Band 1');
    expect(ProAdau1466PeqAuditRegistry.baselineMetadataProven, isFalse);
    expect(ProAdau1466PeqAuditRegistry.coefficientOrder,
        ['b2', 'b1', 'b0', 'a2', 'a1']);
    expect(ProAdau1466PeqAuditRegistry.writeEnabledAddresses, isEmpty);
    expect(ProAdau1466PeqAuditRegistry.acceptsTransaction(
      slewAddress: 0x01FA,
      coefficientAddresses: [0x618D, 0x618E, 0x618F, 0x6190, 0x6191],
      coefficientWords: [1, 2, 3, 4, 5]), isFalse);
  });

  testWidgets('visible PEQ panel exposes audit and no hardware action',
      (tester) async {
    final backend = _CountingBackend();
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(
      body: PeqTab(projectId: 'missing', usbiBackend: backend,
        isWindowsPlatform: () => true, deviceOpen: true),
    ))));
    expect(find.text('ADAU1466 PEQ Hardware Mapping'), findsOneWidget);
    expect(find.byKey(const Key('peq-representative-blocked')), findsOneWidget);
    expect(find.byKey(const Key('peq-required-export-file')), findsOneWidget);
    expect(find.byKey(const Key('peq-required-export-operation')), findsOneWidget);
    expect(find.textContaining('USBPcap is not requested'), findsOneWidget);
    expect(find.textContaining('PEQ WRITE BLOCKED'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'TEST'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'RESTORE'), findsNothing);
    for (final channel in ['WFL', 'MID_L', 'TWL', 'WFR', 'MID_R', 'TWR']) {
      expect(find.byKey(Key('peq-map-$channel')), findsOneWidget);
    }
    expect(backend.calls, 0);
  });

  test('completed hardware allowlists remain unchanged', () {
    expect(ProAdau1466GainChannelRegistry.channels.map((c) => c.targetAddress),
        [0x03B8, 0x03C4, 0x03C7, 0x03BB, 0x03CA, 0x03CD]);
    expect(ProAdau1466MuteChannelRegistry.channels.map((c) => c.address),
        [0x060E, 0x0613, 0x0610, 0x060F, 0x0612, 0x0611]);
    expect(ProAdau1466DelayAuditRegistry.writeEnabledAddresses, {0x03C1});
    expect(ProAdau1466WflLpf2DiagnosticEvidence.writeEnabledAddresses,
        {0x01FA, 0x618D, 0x618E, 0x618F, 0x6190, 0x6191});
    expect(ProAdau1466PeqAuditRegistry.writeEnabledAddresses, isEmpty);
  });
}
