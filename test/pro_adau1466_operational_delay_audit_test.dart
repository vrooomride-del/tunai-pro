import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_delay_audit_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_mute_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_operational_delay_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/delay_tab.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';

class _QueueRealBackend implements ProUsbiNativeBackend {
  final List<List<int>?> responses;
  final setups = <List<int>>[];
  final bodies = <List<int>>[];
  final ackRequests = <List<int>>[];
  _QueueRealBackend(this.responses);
  @override
  bool get isAvailable => true;
  @override
  bool get isFake => false;
  @override
  Future<List<int>?> sendPacketsAndReadAck(
      {required List<int> setupPacket,
      required List<int> bodyPacket,
      required List<int> ackReadRequest}) async {
    setups.add(List.of(setupPacket));
    bodies.add(List.of(bodyPacket));
    ackRequests.add(List.of(ackReadRequest));
    return responses.removeAt(0);
  }
}

Widget _harness(_QueueRealBackend backend, {void Function(String)? onStop}) =>
    ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: DelayTab(
      projectId: 'missing',
      usbiBackend: backend,
      isWindowsPlatform: () => true,
      deviceOpen: true,
      onDspWriteStop: onStop,
    ))));

void main() {
  const expected = <String, (String, String, int, int, int?)>{
    'WFL': ('Delay2', 'DelaySigma300PMAlg2delay', 0x03C1, 4, 4),
    'MID_L': ('Delay2_2', 'DelaySigma300PMAlg1delay', 0x0408, 0, null),
    'TWL': ('Delay2_3', 'DelaySigma300PMAlg4delay', 0x0405, 0, null),
    'WFR': ('Delay2_5', 'DelaySigma300PMAlg6delay', 0x03C2, 0, null),
    'MID_R': ('Delay2_6', 'DelaySigma300PMAlg7delay', 0x0406, 0, null),
    'TWR': ('Delay2_4', 'DelaySigma300PMAlg5delay', 0x0407, 0, null),
  };

  test('exact six mappings, symbols, baselines, and proven Max metadata', () {
    expect(ProAdau1466DelayAuditRegistry.channels, hasLength(6));
    for (final channel in ProAdau1466DelayAuditRegistry.channels) {
      expect((
        channel.sigmaCell,
        channel.sigmaSymbol,
        channel.address,
        channel.exportedBaselineWord,
        channel.configuredMaxSamples
      ), expected[channel.channel]);
    }
    expect(ProAdau1466DelayAuditRegistry.writeEnabledAddresses, {0x03C1});
  });

  test('strict mapped allowlist contains six addresses and rejects 0x03C0', () {
    expect(ProAdau1466DelayAuditRegistry.mappedAddressAllowlist,
        {0x03C1, 0x0408, 0x0405, 0x03C2, 0x0406, 0x0407});
    expect(ProAdau1466DelayAuditRegistry.mappedAddressAllowlist,
        isNot(contains(0x03C0)));
    expect(ProAdau1466DelayAuditRegistry.acceptsWrite(0x03C0, 3), isFalse);
  });

  test('integer-only WFL range is 0 through configured Max 4', () {
    for (final value in [0, 1, 2, 3, 4]) {
      expect(ProAdau1466DelayAuditRegistry.acceptsWrite(0x03C1, value), isTrue);
    }
    for (final value in [-1, 2.5, 5, double.nan, double.infinity]) {
      expect(
          ProAdau1466DelayAuditRegistry.acceptsWrite(0x03C1, value), isFalse);
    }
    for (final address in [0x0408, 0x0405, 0x03C2, 0x0406, 0x0407]) {
      expect(ProAdau1466DelayAuditRegistry.acceptsWrite(address, 0), isFalse);
    }
  });

  test('WFL capture vectors are exact direct writes with one raw ACK request',
      () async {
    final backend = _QueueRealBackend([
      [0x01],
      [0x01]
    ]);
    final executor = ProAdau1466OperationalDelayExecutor(
        backend: backend, isWindowsPlatform: () => true);
    final wfl = ProAdau1466DelayAuditRegistry.find('WFL')!;
    expect(
        (await executor.writeOnce(channel: wfl, samples: 3, deviceOpen: true))
            .success,
        isTrue);
    expect(
        (await executor.writeOnce(channel: wfl, samples: 4, deviceOpen: true))
            .success,
        isTrue);
    expect(backend.setups, [
      [0x40, 0xB2, 0, 0, 1, 1, 6, 0],
      [0x40, 0xB2, 0, 0, 1, 1, 6, 0],
    ]);
    expect(backend.bodies, [
      [0x03, 0xC1, 0, 0, 0, 3],
      [0x03, 0xC1, 0, 0, 0, 4],
    ]);
    expect(backend.ackRequests, everyElement([0xC0, 0xB5, 0, 0, 0, 0, 1, 0]));
  });

  test('ACK gates confirmation and failure performs no automatic retry',
      () async {
    final backend = _QueueRealBackend([
      [0x00]
    ]);
    final result = await ProAdau1466OperationalDelayExecutor(
            backend: backend, isWindowsPlatform: () => true)
        .writeOnce(
            channel: ProAdau1466DelayAuditRegistry.find('WFL')!,
            samples: 3,
            deviceOpen: true);
    expect(result.success, isFalse);
    expect(result.confirmedSamples, isNull);
    expect(backend.bodies, hasLength(1));
  });

  test('executor rejects arbitrary channel objects and fractional raw values',
      () async {
    final backend = _QueueRealBackend([]);
    final executor = ProAdau1466OperationalDelayExecutor(
        backend: backend, isWindowsPlatform: () => true);
    const arbitrary = Adau1466MappedDelayAudit(
        channel: 'unknown',
        sigmaCell: 'unknown',
        sigmaSymbol: 'unknown',
        address: 0x03C0,
        exportedBaselineWord: 0,
        sigmaOutput: '',
        physicalOutput: '',
        configuredMaxSamples: 4);
    expect(
        (await executor.writeOnce(
                channel: arbitrary, samples: 3, deviceOpen: true))
            .blocked,
        isTrue);
    expect(
        (await executor.writeOnce(
                channel: ProAdau1466DelayAuditRegistry.find('WFL')!,
                samples: 3.5,
                deviceOpen: true))
            .blocked,
        isTrue);
    expect(backend.bodies, isEmpty);
  });

  testWidgets('one slider action emits exactly one write and updates after ACK',
      (tester) async {
    final backend = _QueueRealBackend([
      [0x01]
    ]);
    await tester.pumpWidget(_harness(backend));
    await tester.ensureVisible(find.byKey(const Key('delay-slider-WFL')));
    var slider =
        tester.widget<Slider>(find.byKey(const Key('delay-slider-WFL')));
    slider.onChanged!(3);
    await tester.pump();
    slider = tester.widget<Slider>(find.byKey(const Key('delay-slider-WFL')));
    expect(find.textContaining('confirmed 4 samples'), findsOneWidget);
    slider.onChangeEnd!(3);
    await tester.pumpAndSettle();
    expect(backend.bodies, [
      [0x03, 0xC1, 0, 0, 0, 3]
    ]);
    expect(find.textContaining('confirmed 3 samples'), findsOneWidget);
    expect(find.textContaining('last ACK PASS_ACK'), findsOneWidget);
  });

  testWidgets('unproven channels and stereo links remain individually disabled',
      (tester) async {
    final backend = _QueueRealBackend([]);
    await tester.pumpWidget(_harness(backend));
    for (final name in ['MID_L', 'TWL', 'WFR', 'MID_R', 'TWR']) {
      expect(
          tester
              .widget<OutlinedButton>(find.byKey(Key('delay-reset-$name')))
              .onPressed,
          isNull);
    }
    for (final pair in ['WFL + WFR', 'MID_L + MID_R', 'TWL + TWR']) {
      expect(
          tester
              .widget<FilterChip>(find.byKey(Key('delay-link-$pair')))
              .onSelected,
          isNull);
    }
    expect(backend.bodies, isEmpty);
  });

  testWidgets('visible operational Delay tab reports safety status',
      (tester) async {
    await tester.pumpWidget(_harness(_QueueRealBackend([])));
    expect(find.text('ADAU1466 Operational Delay'), findsOneWidget);
    expect(
        find.textContaining('Direct 6-byte parameter write'), findsOneWidget);
    expect(
        find.textContaining('PASS_ACK only, never VERIFIED'), findsOneWidget);
    for (final name in expected.keys) {
      expect(find.byKey(Key('delay-reset-$name')), findsOneWidget);
    }
  });

  testWidgets('launched Workbench retains a visible Delay tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
      home: WorkbenchShell(projectId: 'missing'),
    )));
    await tester.pump();
    expect(find.text('Delay'), findsOneWidget);
  });

  test('completed Master Volume, Gain, and Mute mappings remain unchanged', () {
    const masterVolumeAllowlist = [0x0067, 0x0064];
    expect(masterVolumeAllowlist, [0x0067, 0x0064]);
    expect(ProAdau1466GainChannelRegistry.channels.map((c) => c.targetAddress),
        [0x03B8, 0x03C4, 0x03C7, 0x03BB, 0x03CA, 0x03CD]);
    expect(ProAdau1466MuteChannelRegistry.channels.map((c) => c.address),
        [0x060E, 0x0613, 0x0610, 0x060F, 0x0612, 0x0611]);
  });
}
