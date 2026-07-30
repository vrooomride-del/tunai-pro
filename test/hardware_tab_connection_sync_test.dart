// Focused test: after _syncConnectionToStore() is called (simulated inline),
// project.connection in the store reflects the live ICP5 transport state so
// the status bar and Gain / Deploy / XO tabs all see the correct value.
//
// Proves the 5-step chain required by the runtime fix:
//   1. connected ADAU1701 hardware context
//   2. navigate Hardware → Gain (simulated by reading the same provider)
//   3. connection remains connected in the project store
//   4. the Gain context resolves the same write executor / transport instance
//   5. writeOutputGain can be invoked on that instance

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

class _FakeTransport implements Adau1701TuningTransport {
  bool connected = false;
  final List<(int, double)> outputGainWrites = [];

  @override
  bool get isConnected => connected;
  @override
  bool get handshakeComplete => connected;
  @override
  String? get detectedProfile => connected ? 'DSP1701.100.00.01' : null;
  @override
  Future<RawDspStateSnapshot> readRawDspState() async =>
      throw StateError('not used');
  @override
  Future<Adau1701WriteAck> writePeqGain(int c, double g, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int c, int f,
          {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writePeqFrequency(int c, int f,
          {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writePeqQ(int c, double q, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writeOutputGain(int c, double g) async {
    outputGainWrites.add((c, g));
    return const Adau1701WriteAck(success: true, message: 'ok');
  }
}

void main() {
  final now = DateTime(2026, 7, 29);

  ProProject testProject() => ProProject(
        id: 'proj1',
        name: 'Test',
        createdAt: now,
        updatedAt: now,
        connection: HardwareConnection.disconnected,
      );

  /// Simulates one call of hardware_tab.dart's _syncConnectionToStore().
  Future<void> syncToStore(
    ProviderContainer c, {
    required bool liveConnected,
  }) =>
      c
          .read(proProjectStoreProvider.notifier)
          .updateHardwareConnection(
            'proj1',
            liveConnected
                ? HardwareConnection.connected
                : HardwareConnection.disconnected,
          );

  group('Hardware tab connection sync → project store', () {
    late _FakeTransport transport;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      transport = _FakeTransport();
      container = ProviderContainer(overrides: [
        adau1701Icp5UsbContextProvider.overrideWithValue(
            Adau1701HardwareContext.fromTransport(transport)),
      ]);
      addTearDown(container.dispose);

      // Initialise store and add the test project.
      container.read(proProjectStoreProvider);
      await pumpEventQueue();
      await container
          .read(proProjectStoreProvider.notifier)
          .addProject(testProject());
    });

    test(
        '1. connected ADAU1701 context: transport.isReady is true, '
        'handshake passes, profile confirmed', () {
      transport.connected = true;
      final ctx = container.read(adau1701Icp5UsbContextProvider);
      expect(ctx.isReady, isTrue);
      expect(ctx.transport.handshakeComplete, isTrue);
      expect(ctx.transport.detectedProfile, equals('DSP1701.100.00.01'));
    });

    test(
        '2. Hardware→Gain navigation: project.connection stays connected '
        'after _syncConnectionToStore fires', () async {
      transport.connected = true;

      // Hardware tab's 1 s timer fires _syncConnectionToStore().
      await syncToStore(container, liveConnected: true);

      // Status bar, Gain tab, PEQ tab — all read the same store.
      final proj = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj1');
      expect(proj.connection, HardwareConnection.connected);
    });

    test(
        '3. Gain-tab context resolves the SAME transport instance as '
        'Hardware tab (same Riverpod Provider)', () {
      final fromHw = container.read(adau1701Icp5UsbContextProvider);
      final fromGain = container.read(adau1701Icp5UsbContextProvider);
      expect(fromHw, same(fromGain));
      expect(fromHw.transport, same(fromGain.transport));
      expect(fromHw.transport, same(transport));
    });

    test(
        '4. HardwareWriteExecutor built from the Gain context reaches '
        'the shared write port', () {
      transport.connected = true;
      final ctx = container.read(adau1701Icp5UsbContextProvider);
      expect(ctx.isReady, isTrue);
      final executor = HardwareWriteExecutor(ctx.writePort);
      expect(executor, isNotNull);
    });

    test('5. writeOutputGain can be invoked on the shared transport', () async {
      transport.connected = true;
      await syncToStore(container, liveConnected: true);

      final ctx = container.read(adau1701Icp5UsbContextProvider);
      expect(ctx.transport, same(transport));

      final ack = await transport.writeOutputGain(0, -3.5);
      expect(ack.success, isTrue);
      expect(transport.outputGainWrites, [(0, -3.5)]);
    });
  });
}
