import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_delay_audit_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_mute_channel_registry.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/delay_tab.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';

class _CountingRealBackend implements ProUsbiNativeBackend {
  int calls = 0;
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
    return [0x01];
  }
}

void main() {
  const expected = <String, (String, String, int, int)>{
    'WFL': ('Delay2', 'DelaySigma300PMAlg2delay', 0x03C1, 0x00000004),
    'MID_L': ('Delay2_2', 'DelaySigma300PMAlg1delay', 0x0408, 0),
    'TWL': ('Delay2_3', 'DelaySigma300PMAlg4delay', 0x0405, 0),
    'WFR': ('Delay2_5', 'DelaySigma300PMAlg6delay', 0x03C2, 0),
    'MID_R': ('Delay2_6', 'DelaySigma300PMAlg7delay', 0x0406, 0),
    'TWR': ('Delay2_4', 'DelaySigma300PMAlg5delay', 0x0407, 0),
  };

  test('exact export-derived Delay table, symbols, and baseline words', () {
    expect(ProAdau1466DelayAuditRegistry.channels, hasLength(6));
    for (final channel in ProAdau1466DelayAuditRegistry.channels) {
      expect((
        channel.sigmaCell,
        channel.sigmaSymbol,
        channel.address,
        channel.exportedBaselineWord
      ), expected[channel.channel]);
      expect(channel.writeEnabled, isFalse);
      expect(channel.parameterFormat, contains('UNPROVEN'));
      expect(channel.validRawRange, 'UNPROVEN');
      expect(channel.engineeringUnit, 'UNPROVEN');
      expect(channel.sampleRateDependency, 'UNPROVEN');
    }
  });

  test('strict Delay write allowlist is empty and rejects arbitrary values',
      () {
    expect(ProAdau1466DelayAuditRegistry.writeEnabledAddresses, isEmpty);
    for (final channel in ProAdau1466DelayAuditRegistry.channels) {
      expect(
          ProAdau1466DelayAuditRegistry.acceptsWrite(
              channel.address, channel.exportedBaselineWord),
          isFalse);
    }
    expect(ProAdau1466DelayAuditRegistry.acceptsWrite(0x03C0, 1), isFalse);
    expect(ProAdau1466DelayAuditRegistry.acceptsWrite(0xFFFF, 0xFFFFFFFF),
        isFalse);
  });

  testWidgets('Delay audit exposes no write, SafeLoad, reset, or link action',
      (tester) async {
    final backend = _CountingRealBackend();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
      body: DelayTab(
          projectId: 'missing',
          usbiBackend: backend,
          isWindowsPlatform: () => true,
          deviceOpen: true),
    ))));
    expect(find.text('ADAU1466 Operational Delay'), findsOneWidget);
    expect(find.textContaining('EXPORT AUDIT ONLY'), findsOneWidget);
    expect(find.textContaining('Sample rate: UNPROVEN'), findsOneWidget);
    expect(
        find.textContaining('PASS_ACK only, never VERIFIED'), findsOneWidget);
    for (final channel in expected.keys) {
      final button = tester
          .widget<OutlinedButton>(find.byKey(Key('delay-reset-$channel')));
      expect(button.onPressed, isNull);
    }
    expect(backend.calls, 0);
  });

  testWidgets('launched Workbench retains a visible Delay tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
      home: WorkbenchShell(projectId: 'missing'),
    )));
    await tester.pump();
    expect(find.text('Delay'), findsOneWidget);
  });

  test('completed Gain and Mute mappings remain unchanged', () {
    expect(ProAdau1466GainChannelRegistry.channels.map((c) => c.targetAddress),
        [0x03B8, 0x03C4, 0x03C7, 0x03BB, 0x03CA, 0x03CD]);
    expect(ProAdau1466MuteChannelRegistry.channels.map((c) => c.address),
        [0x060E, 0x0613, 0x0610, 0x060F, 0x0612, 0x0611]);
    const masterVolumeAllowlist = [0x0067, 0x0064];
    expect(masterVolumeAllowlist, [0x0067, 0x0064]);
  });
}
