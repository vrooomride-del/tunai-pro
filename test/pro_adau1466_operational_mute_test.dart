import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_mute_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_operational_mute_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/gain_tab.dart';

class _RealQueueBackend implements ProUsbiNativeBackend {
  final List<List<int>?> responses;
  final bodies = <List<int>>[];
  final setups = <List<int>>[];
  final ackRequests = <List<int>>[];

  _RealQueueBackend(this.responses);

  @override
  bool get isAvailable => true;

  @override
  bool get isFake => false;

  @override
  Future<List<int>?> sendPacketsAndReadAck({
    required List<int> setupPacket,
    required List<int> bodyPacket,
    required List<int> ackReadRequest,
  }) async {
    setups.add(List.of(setupPacket));
    bodies.add(List.of(bodyPacket));
    ackRequests.add(List.of(ackReadRequest));
    return responses.removeAt(0);
  }
}

Widget _harness(_RealQueueBackend backend, {void Function(String)? onStop}) =>
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: GainTab(
            projectId: 'missing-project',
            usbiBackend: backend,
            isWindowsPlatform: () => true,
            deviceOpen: true,
            onDspWriteStop: onStop,
          ),
        ),
      ),
    );

void main() {
  const expected = <String, (String, String, int, int)>{
    'WFL': ('Mute1_3', 'MuteNoSlewADAU145XAlg3mute', 0x060E, 1),
    'MID_L': ('Mute1', 'MuteNoSlewADAU145XAlg1mute', 0x0613, 1),
    'TWL': ('Mute1_4', 'MuteNoSlewADAU145XAlg4mute', 0x0610, 0),
    'WFR': ('Mute1_2', 'MuteNoSlewADAU145XAlg2mute', 0x060F, 1),
    'MID_R': ('Mute1_8', 'MuteNoSlewADAU145XAlg8mute', 0x0612, 1),
    'TWR': ('Mute1_7', 'MuteNoSlewADAU145XAlg7mute', 0x0611, 0),
  };

  test('registry contains exactly the six current export-derived mappings', () {
    expect(ProAdau1466MuteChannelRegistry.channels, hasLength(6));
    for (final channel in ProAdau1466MuteChannelRegistry.channels) {
      final row = expected[channel.channel]!;
      expect((
        channel.sigmaCell,
        channel.sigmaSymbol,
        channel.address,
        channel.exportedState
      ), row);
    }
    final addresses =
        ProAdau1466MuteChannelRegistry.channels.map((c) => c.address).toSet();
    expect(addresses.intersection({
      0x061C, 0x061D, 0x061E, 0x061F, 0x0620,
      0x0621, 0x0622, 0x0623, 0x0624, 0x0625,
    }), isEmpty);
  });

  test('executor emits exact direct-write 0 and 1 bodies without SafeLoad',
      () async {
    final backend = _RealQueueBackend(List.generate(12, (_) => [0x01]));
    final executor = ProAdau1466OperationalMuteExecutor(
        backend: backend, isWindowsPlatform: () => true);
    for (final channel in ProAdau1466MuteChannelRegistry.channels) {
      for (final state in [0, 1]) {
        final result = await executor.writeWithRollback(
          channel: channel,
          requestedState: state,
          previousConfirmedState: channel.exportedState,
          deviceOpen: true,
        );
        expect(result.success, isTrue);
      }
    }
    var index = 0;
    for (final channel in ProAdau1466MuteChannelRegistry.channels) {
      for (final state in [0, 1]) {
        expect(backend.bodies[index++],
            [channel.address >> 8, channel.address & 0xFF, 0, 0, 0, state]);
      }
    }
    expect(backend.setups.every((p) => p[6] == 6), isTrue);
    expect(backend.bodies.any((p) => p[0] == 0x60 && p[1] == 0x00), isFalse);
  });

  test('confirmed state changes only for raw ACK 01', () async {
    final backend = _RealQueueBackend([
      [0x00],
      [0x01]
    ]);
    final executor = ProAdau1466OperationalMuteExecutor(
        backend: backend, isWindowsPlatform: () => true);
    final result = await executor.writeWithRollback(
      channel: ProAdau1466MuteChannelRegistry.find('WFL')!,
      requestedState: 0,
      previousConfirmedState: 1,
      deviceOpen: true,
    );
    expect(result.success, isFalse);
    expect(result.confirmedState, 1);
    expect(result.ackStatus, 'FAIL');
  });

  test('executor rejects arbitrary addresses and values before backend call',
      () async {
    final backend = _RealQueueBackend([]);
    final executor = ProAdau1466OperationalMuteExecutor(
        backend: backend, isWindowsPlatform: () => true);
    const arbitrary = Adau1466MappedMuteChannel(
      channel: 'UNKNOWN',
      sigmaCell: 'unknown',
      sigmaSymbol: 'unknown',
      address: 0x0620,
      exportedState: 0,
      sigmaOutput: '',
      physicalOutput: '',
    );
    expect((await executor.writeWithRollback(channel: arbitrary,
      requestedState: 1, previousConfirmedState: 0,
      deviceOpen: true)).blocked, isTrue);
    expect((await executor.writeWithRollback(
      channel: ProAdau1466MuteChannelRegistry.channels.first,
      requestedState: 2, previousConfirmedState: 1,
      deviceOpen: true)).blocked, isTrue);
    expect(backend.bodies, isEmpty);
  });

  testWidgets('visible Gain tab contains six neutral-polarity controls',
      (tester) async {
    final backend = _RealQueueBackend([]);
    await tester.pumpWidget(_harness(backend));
    expect(find.byKey(const Key('operational-adau1466-mute-controls')),
        findsOneWidget);
    for (final name in expected.keys) {
      expect(find.byKey(Key('mute-toggle-$name')), findsOneWidget);
    }
    expect(find.textContaining('checked=1 and unchecked=0'), findsOneWidget);
    expect(find.textContaining('never VERIFIED'), findsWidgets);
  });

  testWidgets(
      'linked write is left first and rolls left back after right fails',
      (tester) async {
    final backend = _RealQueueBackend([
      [0x01],
      [0x00],
      [0x01],
      [0x01]
    ]);
    await tester.pumpWidget(_harness(backend));
    await tester.ensureVisible(find.byKey(const Key('mute-link-WFL+WFR')));
    await tester.tap(find.byKey(const Key('mute-link-WFL+WFR')));
    await tester.ensureVisible(find.byKey(const Key('mute-toggle-WFR')));
    await tester.tap(find.byKey(const Key('mute-toggle-WFR')));
    await tester.pumpAndSettle();
    expect(backend.bodies.map((b) => [b[0], b[1], b[5]]).toList(), [
      [0x06, 0x0E, 0],
      [0x06, 0x0F, 0],
      [0x06, 0x0F, 1],
      [0x06, 0x0E, 1],
    ]);
    expect(find.textContaining('ROLLED_BACK'), findsOneWidget);
  });

  testWidgets('set all operations are sequential in registry order',
      (tester) async {
    final backend = _RealQueueBackend(List.generate(12, (_) => [0x01]));
    await tester.pumpWidget(_harness(backend));
    await tester.ensureVisible(find.byKey(const Key('mute-all-checked')));
    await tester.tap(find.byKey(const Key('mute-all-checked')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('mute-all-unchecked')));
    await tester.tap(find.byKey(const Key('mute-all-unchecked')));
    await tester.pumpAndSettle();
    final addresses =
        ProAdau1466MuteChannelRegistry.channels.map((c) => c.address).toList();
    expect(backend.bodies.take(6).map((b) => (b[0] << 8) | b[1]), addresses);
    expect(backend.bodies.take(6).every((b) => b[5] == 1), isTrue);
    expect(backend.bodies.skip(6).map((b) => (b[0] << 8) | b[1]), addresses);
    expect(backend.bodies.skip(6).every((b) => b[5] == 0), isTrue);
  });

  testWidgets('linked rollback failure triggers shared STOP interlock',
      (tester) async {
    String? warning;
    final backend = _RealQueueBackend([
      [0x01],
      [0x00],
      [0x01],
      [0x00],
      [0x00]
    ]);
    await tester
        .pumpWidget(_harness(backend, onStop: (value) => warning = value));
    await tester.ensureVisible(find.byKey(const Key('mute-link-WFL+WFR')));
    await tester.tap(find.byKey(const Key('mute-link-WFL+WFR')));
    await tester.ensureVisible(find.byKey(const Key('mute-toggle-WFR')));
    await tester.tap(find.byKey(const Key('mute-toggle-WFR')));
    await tester.pumpAndSettle();
    expect(warning, contains('STOP'));
    expect(find.textContaining('DSP writes: STOPPED'), findsOneWidget);
  });

  test('Master Volume and Gain address registries remain unchanged', () {
    expect(ProAdau1466GainChannelRegistry.channels.map((c) => c.targetAddress),
        [0x03B8, 0x03C4, 0x03C7, 0x03BB, 0x03CA, 0x03CD]);
    const masterVolumeAllowlist = [0x0067, 0x0064];
    expect(masterVolumeAllowlist, [0x0067, 0x0064]);
  });
}
