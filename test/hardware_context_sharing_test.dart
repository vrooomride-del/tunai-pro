import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

// Mutable fake ICP5 transport whose connection state can be toggled to simulate
// the Hardware tab connecting / disconnecting.
class _MutableFakeTransport implements Adau1701TuningTransport {
  bool connected = false;
  final List<(int, double)> gainWrites = [];

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
  Future<Adau1701WriteAck> writePeqGain(int c, double g, {int band = 0}) async {
    gainWrites.add((c, g));
    return const Adau1701WriteAck(success: true, message: 'ok');
  }

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int c, int f,
          {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writePeqQ(int c, double q, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
}

const _band1Gain = HardwareWriteOp(
  channelId: 'wf',
  parameterKind: HardwareParamKind.peqGain,
  bandIndex: 0,
  targetValue: -3.0,
  verification: HardwareParamVerification.captureProven,
  writable: true,
  reason: 'test',
);

void main() {
  test('Hardware tab and Deploy read the same shared context instance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Two independent reads (one representing the Hardware tab, one Deploy).
    final fromHardwareTab = container.read(adau1701Icp5UsbContextProvider);
    final fromDeploy = container.read(adau1701Icp5UsbContextProvider);

    expect(fromHardwareTab, same(fromDeploy));
    expect(fromHardwareTab.transport, same(fromDeploy.transport));
    expect(fromHardwareTab.gate, same(fromDeploy.gate));
    expect(fromHardwareTab.readService, same(fromDeploy.readService));
    expect(fromHardwareTab.writePort, same(fromDeploy.writePort));
  });

  group('shared connection state', () {
    late _MutableFakeTransport transport;
    late ProviderContainer container;

    setUp(() {
      transport = _MutableFakeTransport();
      container = ProviderContainer(overrides: [
        adau1701Icp5UsbContextProvider.overrideWithValue(
            Adau1701HardwareContext.fromTransport(transport)),
      ]);
      addTearDown(container.dispose);
    });

    test('connecting in the Hardware tab makes the Deploy context ready', () {
      final deploy = container.read(adau1701Icp5UsbContextProvider);
      expect(deploy.isReady, isFalse);

      // Hardware tab connects the shared transport.
      transport.connected = true;

      // Deploy immediately observes connected + handshake + identity.
      expect(deploy.transport.isConnected, isTrue);
      expect(deploy.transport.handshakeComplete, isTrue);
      expect(deploy.transport.detectedProfile, isNotNull);
      expect(deploy.isReady, isTrue);
    });

    test('disconnecting makes the shared context not ready (Apply fails closed)',
        () async {
      final deploy = container.read(adau1701Icp5UsbContextProvider);
      transport.connected = true;
      expect(deploy.isReady, isTrue);

      transport.connected = false;
      expect(deploy.isReady, isFalse);

      // The write port fails closed: preflight blocks, no write occurs.
      final report = await deploy.writePort.preflightAndWrite(_band1Gain);
      expect(report.deploymentAllowed, isFalse);
      expect(transport.gainWrites, isEmpty);
    });
  });
}
