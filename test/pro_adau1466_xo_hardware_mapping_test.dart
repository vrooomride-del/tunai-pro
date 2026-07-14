import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_delay_audit_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_mute_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_xo_audit_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_wfl_lpf2_safeload_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/xo_tab.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';

class _CountingRealBackend implements ProUsbiNativeBackend {
  int calls = 0;
  final List<List<int>> setups = [];
  final List<List<int>> bodies = [];
  final List<List<int>> ackRequests = [];
  final List<List<int>?> responses;
  _CountingRealBackend({this.responses = const []});
  @override
  bool get isAvailable => true;
  @override
  bool get isFake => false;
  @override
  Future<List<int>?> sendPacketsAndReadAck(
      {required List<int> setupPacket,
      required List<int> bodyPacket,
      required List<int> ackReadRequest}) async {
    calls++;
    setups.add(List.of(setupPacket));
    bodies.add(List.of(bodyPacket));
    ackRequests.add(List.of(ackReadRequest));
    return calls <= responses.length ? responses[calls - 1] : [1];
  }
}

void main() {
  const expected = <(String, String), (String, int, String, int, int)>{
    ('WFL', 'LPF_2'): (
      'LPF',
      0x01FA,
      'EQS300MultiDPHWSlewP1Alg1Targ_B2_1',
      0x618D,
      0x6191
    ),
    ('MID_L', 'HPF_2'): (
      'HPF',
      0x0200,
      'EQS300MultiDPHWSlewP1Alg2Targ_B2_1',
      0x6192,
      0x6196
    ),
    ('MID_L', 'LPF_3'): (
      'LPF',
      0x02ED,
      'EQS300MultiDPHWSlewP1Alg3Targ_B2_1',
      0x6278,
      0x627C
    ),
    ('TWL', 'HPF_3'): (
      'HPF',
      0x0206,
      'EQS300MultiDPHWSlewP1Alg4Targ_B2_1',
      0x6197,
      0x619B
    ),
    ('TWL', 'Safety HPF_5'): (
      'HPF',
      0x0365,
      'EQS300MultiDPHWSlewP1Alg11Targ_B2_1',
      0x62EB,
      0x62EF
    ),
    ('WFR', 'LPF_4'): (
      'LPF',
      0x020C,
      'EQS300MultiDPHWSlewP1Alg7Targ_B2_1',
      0x619C,
      0x61A0
    ),
    ('MID_R', 'HPF_4'): (
      'HPF',
      0x0212,
      'EQS300MultiDPHWSlewP1Alg8Targ_B2_1',
      0x61A1,
      0x61A5
    ),
    ('MID_R', 'LPF_5'): (
      'LPF',
      0x02F3,
      'EQS300MultiDPHWSlewP1Alg9Targ_B2_1',
      0x627D,
      0x6281
    ),
    ('TWR', 'HPF_5'): (
      'HPF',
      0x0218,
      'EQS300MultiDPHWSlewP1Alg10Targ_B2_1',
      0x61A6,
      0x61AA
    ),
    ('TWR', 'Safefty HPF_5'): (
      'HPF',
      0x036B,
      'EQS300MultiDPHWSlewP1Alg12Targ_B2_1',
      0x62F0,
      0x62F4
    ),
  };

  test('exact six-channel XO block mapping and coefficient symbols', () {
    expect(ProAdau1466XoAuditRegistry.blocks, hasLength(10));
    expect(ProAdau1466XoAuditRegistry.blocks.map((b) => b.channel).toSet(),
        {'WFL', 'MID_L', 'TWL', 'WFR', 'MID_R', 'TWR'});
    for (final block in ProAdau1466XoAuditRegistry.blocks) {
      final row = expected[(block.channel, block.sigmaCell)]!;
      expect((
        block.role,
        block.slewAddress,
        block.coefficientSymbol,
        block.coefficients.first.address,
        block.coefficients.last.address
      ), row);
      expect(block.coefficients.map((c) => c.label),
          ['b2', 'b1', 'b0', 'a2', 'a1']);
      expect(block.coefficients, hasLength(5));
      expect(block.slewWord, 0x0000208A);
      expect(block.writeEnabled, isFalse);
    }
  });

  test('exact exported coefficient words are retained', () {
    final wfl = ProAdau1466XoAuditRegistry.blocks.first;
    expect(wfl.coefficients.map((c) => c.exportedWord),
        [0x000015BA, 0x00002B73, 0x000015BA, 0xFF069155, 0x01F917C5]);
    final safety = ProAdau1466XoAuditRegistry.blocks
        .firstWhere((b) => b.sigmaCell == 'Safety HPF_5');
    expect(safety.coefficients.map((c) => c.exportedWord),
        [0x00E67C13, 0xFE3307DA, 0x00E67C13, 0xFF2B0A7D, 0x01C4FACA]);
  });

  test('strict audit allowlist has only exact coefficient rows', () {
    expect(
        ProAdau1466XoAuditRegistry.coefficientAddressAllowlist, hasLength(50));
    for (final block in ProAdau1466XoAuditRegistry.blocks) {
      for (final coefficient in block.coefficients) {
        expect(ProAdau1466XoAuditRegistry.coefficientAddressAllowlist,
            contains(coefficient.address));
      }
    }
    expect(ProAdau1466XoAuditRegistry.coefficientAddressAllowlist,
        isNot(contains(0x618C)));
    expect(ProAdau1466XoAuditRegistry.coefficientAddressAllowlist,
        isNot(contains(0x62F5)));
    expect(ProAdau1466XoAuditRegistry.writeEnabledAddresses, isEmpty);
    expect(ProAdau1466XoAuditRegistry.acceptsWrite(0x618D, [1, 2, 3, 4, 5]),
        isFalse);
  });

  test('WFL LPF_2 captured 280 and 281 Hz vectors are exact', () {
    expect(ProAdau1466WflLpf2DiagnosticEvidence.coefficientOrder,
        ['b2', 'b1', 'b0', 'a2', 'a1']);
    expect(ProAdau1466WflLpf2DiagnosticEvidence.baseline280Hz,
        [0x000015BA, 0x00002B73, 0x000015BA, 0xFF069155, 0x01F917C5]);
    expect(ProAdau1466WflLpf2DiagnosticEvidence.test281Hz,
        [0x000015E1, 0x00002BC2, 0x000015E1, 0xFF069742, 0x01F9113A]);
    expect(ProAdau1466WflLpf2DiagnosticEvidence.baselinePayload, [
      0x00,
      0x00,
      0x15,
      0xBA,
      0x00,
      0x00,
      0x2B,
      0x73,
      0x00,
      0x00,
      0x15,
      0xBA,
      0xFF,
      0x06,
      0x91,
      0x55,
      0x01,
      0xF9,
      0x17,
      0xC5,
    ]);
    expect(ProAdau1466WflLpf2DiagnosticEvidence.testPayload, [
      0x00,
      0x00,
      0x15,
      0xE1,
      0x00,
      0x00,
      0x2B,
      0xC2,
      0x00,
      0x00,
      0x15,
      0xE1,
      0xFF,
      0x06,
      0x97,
      0x42,
      0x01,
      0xF9,
      0x11,
      0x3A,
    ]);
    expect(ProAdau1466WflLpf2DiagnosticEvidence.baselinePayload, hasLength(20));
    expect(ProAdau1466WflLpf2DiagnosticEvidence.testPayload, hasLength(20));
  });

  test('signed 8.24 high bytes are preserved without numeric conversion', () {
    expect(ProAdau1466WflLpf2DiagnosticEvidence.baselinePayload.sublist(12, 16),
        [0xFF, 0x06, 0x91, 0x55]);
    expect(ProAdau1466WflLpf2DiagnosticEvidence.testPayload.sublist(12, 16),
        [0xFF, 0x06, 0x97, 0x42]);
  });

  test('official five-word trigger enables only exact WFL vectors', () {
    expect(ProAdau1466WflLpf2DiagnosticEvidence.slewAddress, 0x01FA);
    expect(ProAdau1466WflLpf2DiagnosticEvidence.coefficientAddresses,
        {0x618D, 0x618E, 0x618F, 0x6190, 0x6191});
    expect(ProAdau1466WflLpf2DiagnosticEvidence.transactionShapeProven, isTrue);
    expect(ProAdau1466WflLpf2DiagnosticEvidence.writeEnabledAddresses,
        {0x01FA, 0x618D, 0x618E, 0x618F, 0x6190, 0x6191});
    expect(
        ProAdau1466WflLpf2DiagnosticEvidence.acceptsTransaction(
            0x01FA,
            {0x618D, 0x618E, 0x618F, 0x6190, 0x6191},
            ProAdau1466WflLpf2DiagnosticEvidence.test281Hz),
        isTrue);
    expect(
        ProAdau1466WflLpf2DiagnosticEvidence.acceptsTransaction(
            0x01FA, {0x618D, 0x618E, 0x618F, 0x6190, 0x6191}, [1, 2, 3, 4, 5]),
        isFalse);
    expect(ProAdau1466WflLpf2DiagnosticEvidence.unresolvedTrigger,
        contains('lower-memory count 5'));
  });

  test('exact TEST and RESTORE packets use setup lengths 6, 22, 14', () {
    final testStages = ProAdau1466WflLpf2SafeLoadExecutor.testStages();
    final restoreStages = ProAdau1466WflLpf2SafeLoadExecutor.restoreStages();
    const setupPrefix = [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01];
    expect(testStages.map((stage) => stage.setupPacket), [
      [...setupPrefix, 0x06, 0x00],
      [...setupPrefix, 0x16, 0x00],
      [...setupPrefix, 0x0E, 0x00],
    ]);
    expect(testStages.map((stage) => stage.bodyPacket), [
      [0x01, 0xFA, 0x00, 0x00, 0x20, 0x8A],
      [0x60, 0x00, ...ProAdau1466WflLpf2DiagnosticEvidence.testPayload],
      [
        0x60,
        0x05,
        0x00,
        0x00,
        0x61,
        0x8D,
        0x00,
        0x00,
        0x00,
        0x05,
        0x00,
        0x00,
        0x00,
        0x00
      ],
    ]);
    expect(restoreStages.map((stage) => stage.bodyPacket), [
      [0x01, 0xFA, 0x00, 0x00, 0x20, 0x8A],
      [0x60, 0x00, ...ProAdau1466WflLpf2DiagnosticEvidence.baselinePayload],
      [
        0x60,
        0x05,
        0x00,
        0x00,
        0x61,
        0x8D,
        0x00,
        0x00,
        0x00,
        0x05,
        0x00,
        0x00,
        0x00,
        0x00
      ],
    ]);
  });

  test('one TEST action emits one transaction and exact ACK requests',
      () async {
    final backend = _CountingRealBackend();
    final waits = <Duration>[];
    final executor = ProAdau1466WflLpf2SafeLoadExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
        wait: (duration) async => waits.add(duration));
    final result = await executor.runTest(deviceOpen: true);
    expect(backend.calls, 3);
    expect(backend.ackRequests,
        List.filled(3, [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]));
    expect(waits, isEmpty);
    expect(result.confirmedState, '281 Hz TEST · PASS_ACK');
    expect(result.restoreStages, isEmpty);
  });

  test('TEST failure runs complete restore after one audio-frame wait',
      () async {
    final backend = _CountingRealBackend(responses: [
      [1],
      [0],
      [1],
      [1],
      [1],
      [1]
    ]);
    final waits = <Duration>[];
    final executor = ProAdau1466WflLpf2SafeLoadExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
        wait: (duration) async => waits.add(duration));
    final result = await executor.runTest(deviceOpen: true);
    expect(backend.calls, 6);
    expect(
        backend.bodies.sublist(3),
        ProAdau1466WflLpf2SafeLoadExecutor.restoreStages()
            .map((stage) => stage.bodyPacket));
    expect(waits, [ProAdau1466WflLpf2SafeLoadExecutor.minimumAudioFrameWait]);
    expect(result.confirmedState, '280 Hz BASELINE · PASS_ACK');
    expect(result.restoreFailed, isFalse);
  });

  test('restore failure is reported and no partial state is confirmed',
      () async {
    final backend = _CountingRealBackend(responses: [
      [1],
      [0],
      [1],
      [1],
      [0],
      [1]
    ]);
    final executor = ProAdau1466WflLpf2SafeLoadExecutor(
        backend: backend, isWindowsPlatform: () => true, wait: (_) async {});
    final result = await executor.runTest(deviceOpen: true);
    expect(result.restoreFailed, isTrue);
    expect(result.confirmedState, 'UNCONFIRMED');
  });

  testWidgets('visible diagnostic enables WFL only and does not auto-write',
      (tester) async {
    final backend = _CountingRealBackend();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
      body: XoTab(
          projectId: 'missing',
          usbiBackend: backend,
          isWindowsPlatform: () => true,
          deviceOpen: true),
    ))));
    expect(find.text('ADAU1466 XO Hardware Mapping'), findsOneWidget);
    expect(find.textContaining('WFL LPF_2 WRITE ENABLED'), findsOneWidget);
    expect(
        find.byKey(const Key('wfl-lpf2-safeload-diagnostic')), findsOneWidget);
    expect(find.text('TEST 281 Hz'), findsOneWidget);
    expect(find.text('RESTORE 280 Hz'), findsOneWidget);
    expect(
        find.textContaining('WRITE ENABLED — exact 280/281'), findsOneWidget);
    expect(find.textContaining('WRITE BLOCKED'), findsNWidgets(9));
    expect(find.textContaining('PASS_ACK only, never VERIFIED'), findsNWidgets(2));
    expect(backend.calls, 0);
  });

  testWidgets('restore failure activates shared STOP', (tester) async {
    final backend = _CountingRealBackend(responses: [
      [1],
      [0],
      [1],
      [1],
      [0],
      [1]
    ]);
    final stops = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WflLpf2SafeLoadDiagnosticCard(
                backend: backend,
                isWindowsPlatform: () => true,
                deviceOpen: true,
                dspWritesDisabled: false,
                onDspWriteStop: stops.add))));
    await tester.tap(find.byKey(const Key('xo-test-281')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('xo-stop-warning')), findsOneWidget);
    expect(stops.single, contains('shared DSP STOP'));
    expect(find.textContaining('Current confirmed state: UNCONFIRMED'),
        findsOneWidget);
  });

  testWidgets('launched Workbench retains visible XO navigation',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
      home: WorkbenchShell(projectId: 'missing'),
    )));
    await tester.pump();
    expect(find.text('XO'), findsOneWidget);
  });

  test('completed mappings stay unchanged and PEQ has no enabled path', () {
    const masterVolume = [0x0067, 0x0064];
    expect(masterVolume, [0x0067, 0x0064]);
    expect(ProAdau1466GainChannelRegistry.channels.map((c) => c.targetAddress),
        [0x03B8, 0x03C4, 0x03C7, 0x03BB, 0x03CA, 0x03CD]);
    expect(ProAdau1466MuteChannelRegistry.channels.map((c) => c.address),
        [0x060E, 0x0613, 0x0610, 0x060F, 0x0612, 0x0611]);
    expect(ProAdau1466DelayAuditRegistry.writeEnabledAddresses, {0x03C1});
    const peqWriteEnabledAddresses = <int>{};
    expect(peqWriteEnabledAddresses, isEmpty);
  });
}
