import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/deploy/pro_icp5_peq_write_port.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// Minimal fake tuning transport (records writes; connection controllable).
class _FakeTuningTransport implements Adau1701TuningTransport {
  final bool connected;
  _FakeTuningTransport({this.connected = true});
  final List<(int, double)> gainWrites = [];
  final List<(int, int)> freqWrites = [];

  @override
  bool get isConnected => connected;
  @override
  bool get handshakeComplete => connected;
  @override
  String? get detectedProfile => connected ? 'DSP1701.100.00.01' : null;
  @override
  Future<RawDspStateSnapshot> readRawDspState() async =>
      throw StateError('not connected');

  @override
  Future<Adau1701WriteAck> writePeqGain(int channel, double gainDb,
      {int band = 0}) async {
    gainWrites.add((channel, gainDb));
    return const Adau1701WriteAck(success: true, message: 'ok');
  }

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz,
      {int band = 0}) async {
    freqWrites.add((channel, frequencyHz));
    return const Adau1701WriteAck(success: true, message: 'ok');
  }

  @override
  Future<Adau1701WriteAck> writePeqQ(int channel, double q,
      {int band = 0}) async =>
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
  group('construction', () {
    test('fromTransport wires all four dependencies', () {
      final t = _FakeTuningTransport();
      final ctx = Adau1701HardwareContext.fromTransport(t);

      expect(ctx.transport, same(t));
      expect(ctx.gate, isNotNull);
      expect(ctx.readService, isA<Adau1701Ch0Band0ReadService>());
      expect(ctx.writePort, isA<Adau1701Icp5PeqWritePort>());
      expect(ctx.transportType, HardwareTransportType.icp5);
    });

    test('icp5Usb builds an Icp5UsbTransport context', () {
      final ctx = Adau1701HardwareContext.icp5Usb();
      expect(ctx.transport, isA<Icp5UsbTransport>());
      expect(ctx.transportType, HardwareTransportType.icp5);
      expect(ctx.writePort, isA<Adau1701Icp5PeqWritePort>());
    });

    test('bleIcp5Placeholder builds an Icp5UsbTransport (BLE driver) context',
        () {
      final ctx = Adau1701HardwareContext.bleIcp5Placeholder();
      expect(ctx.transport, isA<Icp5UsbTransport>());
      expect(ctx.transportType, HardwareTransportType.icp5);
      expect(ctx.writePort, isA<Adau1701Icp5PeqWritePort>());
    });
  });

  group('dependency wiring', () {
    test('gate, read service, and write port share the same transport', () {
      final t = _FakeTuningTransport();
      final ctx = Adau1701HardwareContext.fromTransport(t);
      // The write port's transport is the same instance.
      expect(ctx.writePort.transport, same(t));
      expect(ctx.readService.transport, same(t));
      // Same write-port type is produced across both transport factories.
      expect(Adau1701HardwareContext.icp5Usb().writePort.runtimeType,
          Adau1701HardwareContext.bleIcp5Placeholder().writePort.runtimeType);
    });

    test('custom channel resolver is used by the write port', () async {
      final t = _FakeTuningTransport(connected: false);
      var resolverCalls = 0;
      final ctx = Adau1701HardwareContext.fromTransport(
        t,
        channelResolver: (id) {
          resolverCalls++;
          return 0;
        },
      );
      // Executing a supported op exercises the resolver (then fails closed at
      // preflight because the transport is not connected).
      await ctx.writePort.preflightAndWrite(_band1Gain);
      expect(resolverCalls, greaterThan(0));
    });
  });

  group('fail closed when transport unavailable', () {
    test('isReady is false for a disconnected transport', () {
      final ctx = Adau1701HardwareContext.fromTransport(
          _FakeTuningTransport(connected: false));
      expect(ctx.isReady, isFalse);
    });

    test('write port blocks (no write) when transport is unavailable',
        () async {
      final t = _FakeTuningTransport(connected: false);
      final ctx = Adau1701HardwareContext.fromTransport(t);
      final report = await ctx.writePort.preflightAndWrite(_band1Gain);

      expect(report.deploymentAllowed, isFalse);
      expect(report.deploymentResult, isNull);
      expect(t.gainWrites, isEmpty);
      expect(t.freqWrites, isEmpty);
    });

    test('isReady is true for a connected transport', () {
      final ctx = Adau1701HardwareContext.fromTransport(_FakeTuningTransport());
      expect(ctx.isReady, isTrue);
    });
  });
}
