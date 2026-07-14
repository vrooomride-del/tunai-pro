import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_master_volume_executor.dart';
import 'package:tunai_pro/core/pro_adau1466_mute_validation_executor.dart';
import 'package:tunai_pro/core/pro_adau1466_operational_gain_executor.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/gain_tab.dart';

class _Backend implements ProUsbiNativeBackend {
  final List<List<int>> outcomes;
  final List<List<int>> bodies = [];
  int calls = 0;
  _Backend({List<List<int>>? outcomes})
      : outcomes = outcomes ?? List.generate(100, (_) => [0x01]);
  @override
  bool get isAvailable => true;
  @override
  bool get isFake => false;
  @override
  Future<List<int>?> sendPacketsAndReadAck(
      {required List<int> setupPacket,
      required List<int> bodyPacket,
      required List<int> ackReadRequest}) async {
    bodies.add(List.of(bodyPacket));
    return outcomes[calls++];
  }
}

void main() {
  test('operational write uses three stages and confirms only all raw ACK 01',
      () async {
    final backend = _Backend();
    final channel = ProAdau1466GainChannelRegistry.findByChannel('MID_L')!;
    final result = await ProAdau1466OperationalGainExecutor(
      backend: backend,
      isWindowsPlatform: () => true,
    ).writeWithRollback(
        channel: channel,
        requestedWord: 0x00002000,
        previousConfirmedWord: channel.exportedRestoreWord,
        deviceOpen: true);
    expect(result.success, isTrue);
    expect(result.confirmedWord, 0x00002000);
    expect(backend.calls, 3);
    expect(backend.bodies[0], [0x03, 0xC5, 0, 0, 0x20, 0x8A]);
    expect(backend.bodies[1], [0x60, 0, 0, 0, 0x20, 0]);
    expect(backend.bodies[2], [0x60, 5, 0, 0, 3, 0xC4, 0, 0, 0, 1, 0, 0, 0, 0]);
  });

  test('failed write runs full previous-confirmed restore', () async {
    final backend = _Backend(outcomes: const [
      [0],
      [1],
      [1],
      [1],
      [1],
      [1],
    ]);
    final channel = ProAdau1466GainChannelRegistry.channels.first;
    final result = await ProAdau1466OperationalGainExecutor(
      backend: backend,
      isWindowsPlatform: () => true,
    ).writeWithRollback(
        channel: channel,
        requestedWord: 0x840,
        previousConfirmedWord: 0x68E,
        deviceOpen: true);
    expect(result.success, isFalse);
    expect(result.restoreFailed, isFalse);
    expect(result.confirmedWord, 0x68E);
    expect(backend.calls, 6);
    expect(backend.bodies[4], [0x60, 0, 0, 0, 0x06, 0x8E]);
  });

  testWidgets('visible operational panel previews drag and writes only on end',
      (tester) async {
    final backend = _Backend();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: OperationalAdau1466GainControls(
                    backend: backend,
                    isWindowsPlatform: () => true,
                    deviceOpen: true)))));
    final sliderFinder = find.byKey(const Key('gain-slider-WFL'));
    final slider = tester.widget<Slider>(sliderFinder);
    slider.onChanged!(-75);
    await tester.pump();
    expect(backend.calls, 0);
    slider.onChangeEnd!(-75);
    await tester.pumpAndSettle();
    expect(backend.calls, 3);
    expect(find.textContaining('ACK PASS_ACK'), findsOneWidget);
    expect(find.text('Operational ADAU1466 Gain Controls'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(6));
  });

  testWidgets('actual GainTab contains all six operational sliders',
      (tester) async {
    final backend = _Backend();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
      body: GainTab(
          projectId: 'gain-visible-test',
          usbiBackend: backend,
          isWindowsPlatform: () => true,
          deviceOpen: true),
    ))));
    expect(find.byKey(const Key('operational-adau1466-gain-controls')),
        findsOneWidget);
    for (final channel in ['WFL', 'MID_L', 'TWL', 'WFR', 'MID_R', 'TWR']) {
      expect(find.byKey(Key('gain-slider-$channel')), findsOneWidget);
    }
    expect(find.text('Reset All to Exported Baselines'), findsOneWidget);
  });

  testWidgets(
      'linked pair writes left then right and rolls left back on failure',
      (tester) async {
    final backend = _Backend(outcomes: const [
      [1], [1], [1], // left succeeds
      [0], [1], [1], // right fails
      [1], [1], [1], // right internal restore
      [1], [1], [1], // left rollback
    ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: OperationalAdau1466GainControls(
                    backend: backend,
                    isWindowsPlatform: () => true,
                    deviceOpen: true)))));
    await tester.tap(find.widgetWithText(FilterChip, 'Link WFL+WFR'));
    await tester.pump();
    final slider =
        tester.widget<Slider>(find.byKey(const Key('gain-slider-WFR')));
    slider.onChangeEnd!(-75);
    await tester.pumpAndSettle();
    expect(backend.calls, 12);
    expect(backend.bodies[0].take(2), [0x03, 0xB9]);
    expect(backend.bodies[3].take(2), [0x03, 0xBC]);
    expect(backend.bodies[10], [0x60, 0, 0, 0, 0x06, 0x8E]);
    expect(find.textContaining('ROLLED_BACK'), findsOneWidget);
  });

  testWidgets('restore failure raises the session-wide DSP STOP callback',
      (tester) async {
    final backend = _Backend(outcomes: const [
      [0],
      [1],
      [1],
      [0],
      [1],
      [1],
    ]);
    String? stopWarning;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: OperationalAdau1466GainControls(
      backend: backend,
      isWindowsPlatform: () => true,
      deviceOpen: true,
      onDspWriteStop: (warning) => stopWarning = warning,
    )))));
    final slider =
        tester.widget<Slider>(find.byKey(const Key('gain-slider-MID_L')));
    slider.onChangeEnd!(-70);
    await tester.pumpAndSettle();
    expect(backend.calls, 6);
    expect(stopWarning, contains('STOP'));
  });

  test('Master Volume and Mute paths remain unchanged', () {
    expect(ProUsbiSigmaVerificationExecutor.writeEnabledAddresses,
        {0x0067, 0x0064});
    expect(kOperationalMasterVolumeL, 0x0067);
    expect(kOperationalMasterVolumeR, 0x0064);
    expect(ProAdau1466MuteValidationExecutor.writeEnabledAddresses, {0x060E});
  });
}
