import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_delay_audit_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_mute_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_peq_audit_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_xo_audit_registry.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/peq_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/pro_adau1466_peq_hardware_panel.dart';

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
  late List<Adau1466PeqCoefficientRow> rows;
  late List<Adau1466PeqBandAudit> bands;

  setUpAll(() {
    rows = ProAdau1466PeqAuditRegistry.parse(
        File(ProAdau1466PeqAuditRegistry.sourceAsset).readAsStringSync());
    bands = ProAdau1466PeqAuditRegistry.bands(rows);
  });

  test('complete v0.9 export retains all 800 requested PEQ rows', () {
    expect(ProAdau1466PeqAuditRegistry.fullOriginalExportFound, isTrue);
    expect(rows, hasLength(800));
    expect(bands, hasLength(160));
    expect(rows.map((row) => row.cellName).toSet(),
        ProAdau1466PeqAuditRegistry.outputs.map((output) => output.cellName).toSet());
    expect(rows.every((row) => row.sourceFile ==
        ProAdau1466PeqAuditRegistry.sourceAsset && row.sourceLine > 0), isTrue);
  });

  test('exact output/cell mappings remain separate', () {
    expect(ProAdau1466PeqAuditRegistry.outputs.map((output) =>
      (output.channel, output.cellName, output.physicalOutput)), [
      ('WFL', 'L_WOOFER_PEQ 20-band', 'OUT3'),
      ('MID_L', 'L_MID_PEQ_20B', 'OUT2'),
      ('TWL', 'L_TWEETER_PEQ 20-band', 'OUT1'),
      ('WFR', 'R_WOOFER_PEQ 20-band', 'OUT8'),
      ('MID_R', 'R_MID_PEQ_20B', 'OUT7'),
      ('TWR', 'R_TWEETER_PEQ 20-band', 'OUT4'),
      ('GLOBAL_L', 'TUNAI_GLOBAL_PEQ_L', 'L bus'),
      ('GLOBAL_R', 'TUNAI_GLOBAL_PEQ_R', 'R bus'),
    ]);
    for (final output in ProAdau1466PeqAuditRegistry.outputs) {
      expect(bands.where((band) => band.output.cellName == output.cellName),
          hasLength(20));
    }
  });

  test('WFL first band exact addresses, vector, order, and provenance', () {
    final band = bands.firstWhere((band) =>
        band.output.channel == 'WFL' && band.bandNumber == 1);
    expect(band.slewAddress, isNull);
    expect(band.targetStartAddress, 538);
    expect(band.addresses, [538, 539, 540, 541, 542]);
    expect(band.words, [0, 0, 0x01000000, 0, 0]);
    expect(band.coefficients.map((row) => row.coefficient),
        ['b2', 'b1', 'b0', 'a2', 'a1']);
    expect(band.coefficients.map((row) => row.parameterName).toSet(),
        {'IdxSelIndpBandsAlgMDP_S3003B2_10'});
    expect(band.coefficients.map((row) => row.sourceLine),
        [4527, 4528, 4529, 4530, 4531]);
    expect(ProAdau1466PeqAuditRegistry.baselineFrequencyGainQExplicit, isFalse);
  });

  test('all bands are exact contiguous five-word groups with fixed order', () {
    expect(ProAdau1466PeqAuditRegistry.coefficientOrder,
        ['b2', 'b1', 'b0', 'a2', 'a1']);
    for (final band in bands) {
      expect(band.coefficients, hasLength(5));
      expect(band.addresses,
          List.generate(5, (index) => band.targetStartAddress + index));
      expect(band.coefficients.map((row) => row.coefficient),
          ProAdau1466PeqAuditRegistry.coefficientOrder);
    }
  });

  test('deduplication is deterministic and never merges cells or bands', () {
    final duplicateInput = [...rows.reversed, ...rows];
    final dedupedA = ProAdau1466PeqAuditRegistry.deduplicate(duplicateInput);
    final dedupedB = ProAdau1466PeqAuditRegistry.deduplicate(rows);
    expect(dedupedA.map((row) => '${row.cellName}|${row.address}'),
        dedupedB.map((row) => '${row.cellName}|${row.address}'));
    expect(dedupedA, hasLength(800));
  });

  test('PARAM header and XML corroborate representative WFL evidence', () {
    final header = File(ProAdau1466PeqAuditRegistry.corroboratingParamHeader)
        .readAsStringSync();
    final xml = File(ProAdau1466PeqAuditRegistry.corroboratingXml)
        .readAsStringSync();
    expect(header, contains('MOD_L_WOOFER_PEQ20_BAND_COUNT'));
    expect(header, contains('IDXSELINDPBANDSALGMDPS3003B2100_ADDR 538'));
    expect(header, contains('IDXSELINDPBANDSALGMDPS3003B2104_ADDR 542'));
    expect(header, contains('SIGMASTUDIOTYPE_8_24'));
    expect(xml, contains('cell="L_WOOFER_PEQ 20-band "'));
  });

  test('all PEQ writes remain blocked without explicit Frequency/Gain/Q', () {
    expect(ProAdau1466PeqAuditRegistry.writeEnabledAddresses, isEmpty);
    expect(ProAdau1466PeqAuditRegistry.acceptsTransaction(
      slewAddress: 0x01FA,
      coefficientAddresses: [0x618D, 0x618E, 0x618F, 0x6190, 0x6191],
      coefficientWords: [1, 2, 3, 4, 5]), isFalse);
  });

  testWidgets('visible PEQ panel exposes audit and no hardware action',
      (tester) async {
    final backend = _CountingBackend();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: Adau1466PeqHardwareMappingPanel(
        backend: backend, isWindowsPlatform: () => true, deviceOpen: true,
        dspWritesDisabled: false,
        sourceOverride: File(ProAdau1466PeqAuditRegistry.sourceAsset)
            .readAsStringSync())),
    )));
    await tester.pumpAndSettle();
    expect(find.text('ADAU1466 PEQ Hardware Mapping'), findsOneWidget);
    expect(find.byKey(const Key('peq-representative-blocked')), findsOneWidget);
    expect(find.byKey(const Key('peq-missing-design-metadata')), findsOneWidget);
    expect(find.textContaining('800 individual coefficient rows'), findsOneWidget);
    expect(find.textContaining('Target 0x021A'), findsOneWidget);
    expect(find.textContaining('PEQ TEST WRITE BLOCKED'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'TEST'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'RESTORE'), findsNothing);
    for (final channel in ['WFL', 'MID_L', 'TWL', 'WFR', 'MID_R', 'TWR']) {
      expect(find.byKey(Key('peq-map-$channel')), findsOneWidget);
    }
    expect(backend.calls, 0);
  });

  testWidgets('actual PEQ tab contains visible hardware mapping panel',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home:
      Scaffold(body: PeqTab(projectId: 'missing')))));
    expect(find.byKey(const Key('adau1466-peq-hardware-mapping')),
        findsOneWidget);
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
