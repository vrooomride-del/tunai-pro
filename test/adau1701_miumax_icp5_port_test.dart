// Parity tests: PRO port dispatch matches Consumer production write paths.
//
// Consumer (tunai_codex) uses:
//   - peqGain:      writePeqGain(channel, gainDb, band: N)     — param 0x18 property 0x01
//   - peqFrequency: writePeqFrequency(channel, freqHz, band: N) — param 0x18 property 0x02
//   - peqQ:         writePeqQ(channel, q, band: N)              — param 0x18 property 0x00
//   - XO cutoff:    writeFilterFrequency(channel, freqHz)       — param 0x15
//
// These tests verify PRO dispatches identically — same method, same args.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/deploy/pro_icp5_peq_write_port.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/adau1701_peq_deployment_gate.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

const _kDeviceId = 'DSP1701.100.00.01';

// ── Fake transport ────────────────────────────────────────────────────────────

class _FakeTransport implements Adau1701TuningTransport {
  final bool connected;
  _FakeTransport({this.connected = true});

  // Recorded calls — each entry is (channel, value, band) where applicable.
  final List<(int, double, int)> gainWrites = [];     // writePeqGain
  final List<(int, int, int)> peqFreqWrites = [];     // writePeqFrequency (param 0x18)
  final List<(int, double, int)> qWrites = [];        // writePeqQ
  final List<(int, int)> filterFreqWrites = [];       // writeFilterFrequency (param 0x15)
  final List<(int, double)> outputGainWrites = [];    // writeOutputGain

  bool ackSuccess = true;

  @override
  bool get isConnected => connected;
  @override
  bool get handshakeComplete => connected;
  @override
  String? get detectedProfile => connected ? _kDeviceId : null;

  @override
  Future<RawDspStateSnapshot> readRawDspState() async =>
      RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026),
        blockId: 0x2202,
        payload: _validPayload(),
      );

  @override
  Future<Adau1701WriteAck> writePeqGain(int channel, double gainDb,
      {int band = 0}) async {
    gainWrites.add((channel, gainDb, band));
    return Adau1701WriteAck(success: ackSuccess, message: 'gain');
  }

  @override
  Future<Adau1701WriteAck> writePeqFrequency(int channel, int frequencyHz,
      {int band = 0}) async {
    peqFreqWrites.add((channel, frequencyHz, band));
    return Adau1701WriteAck(success: ackSuccess, message: 'peqFreq');
  }

  @override
  Future<Adau1701WriteAck> writePeqQ(int channel, double q,
      {int band = 0}) async {
    qWrites.add((channel, q, band));
    return Adau1701WriteAck(success: ackSuccess, message: 'q');
  }

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz,
      {int band = 0}) async {
    filterFreqWrites.add((channel, frequencyHz));
    return Adau1701WriteAck(success: ackSuccess, message: 'filterFreq');
  }

  @override
  Future<Adau1701WriteAck> writeOutputGain(int channel, double gainDb) async {
    outputGainWrites.add((channel, gainDb));
    return Adau1701WriteAck(success: ackSuccess, message: 'outputGain');
  }

  @override
  Future<Adau1701WriteAck> writeMasterMute(bool muted) async =>
      Adau1701WriteAck(success: ackSuccess, message: 'masterMute');
}

// ── Fake read service ─────────────────────────────────────────────────────────

class _FakeReadService extends Adau1701Ch0Band0ReadService {
  final Adau1701Ch0Band0ReadResult result;
  _FakeReadService(Adau1701RawReadTransport t, this.result)
      : super(transport: t);
  @override
  Future<Adau1701Ch0Band0ReadResult> readOriginalState() async => result;
}

// A valid DSP payload: decodes to a ch0/band0 state that the preflight accepts.
List<int> _validPayload() {
  final p = List<int>.filled(513, 0x00);
  p[19] = 0x08;
  p[20] = 0x07;
  p[21] = 0xF6;
  p[23] = 0x14;
  p[24] = 0x01;
  p[154] = 0x01;
  p[308] = 0x02;
  return p;
}

Adau1701Ch0Band0ReadResult _readOk({double gainDb = -1.0, int freq = 1000}) =>
    Adau1701Ch0Band0ReadResult.success(Adau1701Ch0Band0OriginalState(
      deviceId: _kDeviceId,
      capturedAt: DateTime.utc(2026),
      frequencyHz: freq,
      gainDb: gainDb,
      q: 1.0,
      property08State: 1,
    ));

// ── Port factory ──────────────────────────────────────────────────────────────

Adau1701Icp5PeqWritePort _port(
  _FakeTransport t, {
  Adau1701Ch0Band0ReadResult? readback,
  Icp5ChannelResolver? resolver,
}) =>
    Adau1701Icp5PeqWritePort(
      transport: t,
      gate: Adau1701PeqDeploymentGate(transport: t),
      readService: _FakeReadService(t, readback ?? _readOk()),
      channelResolver:
          resolver ?? Adau1701HardwareContext.defaultChannelResolver,
      clock: () => DateTime.utc(2026, 7, 30),
    );

// A capture-proven op using the default channel resolver.
HardwareWriteOp _op(
  String channelId,
  HardwareParamKind kind,
  num value, {
  int? band = 0,
}) =>
    HardwareWriteOp(
      channelId: channelId,
      parameterKind: kind,
      bandIndex: band,
      targetValue: value,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Channel mapping ──────────────────────────────────────────────────────────

  group('defaultChannelResolver', () {
    test('ch_tw_l → 0', () {
      expect(Adau1701HardwareContext.defaultChannelResolver('ch_tw_l'), 0);
    });
    test('ch_wf_l → 1', () {
      expect(Adau1701HardwareContext.defaultChannelResolver('ch_wf_l'), 1);
    });
    test('ch_tw_r → 2', () {
      expect(Adau1701HardwareContext.defaultChannelResolver('ch_tw_r'), 2);
    });
    test('ch_wf_r → 3', () {
      expect(Adau1701HardwareContext.defaultChannelResolver('ch_wf_r'), 3);
    });
    test('unknown channel → -1 (fail-closed)', () {
      expect(Adau1701HardwareContext.defaultChannelResolver('ch_sub'), -1);
      expect(Adau1701HardwareContext.defaultChannelResolver(''), -1);
    });
  });

  group('channel resolver is propagated to transport calls', () {
    test('ch_tw_l uses transport channel 0', () async {
      final t = _FakeTransport();
      final report = await _port(t, readback: _readOk(gainDb: -3.0))
          .preflightAndWrite(_op('ch_tw_l', HardwareParamKind.peqGain, -3.0));
      expect(report.deploymentSucceeded, isTrue);
      expect(t.gainWrites, [(0, -3.0, 0)]);
    });

    test('ch_wf_r uses transport channel 3', () async {
      final t = _FakeTransport();
      await _port(t)
          .preflightAndWrite(_op('ch_wf_r', HardwareParamKind.peqQ, 1.5));
      expect(t.qWrites, [(3, 1.5, 0)]);
    });

    test('unknown channel throws before any I/O', () async {
      final t = _FakeTransport();
      await expectLater(
        _port(t).preflightAndWrite(
            _op('ch_sub', HardwareParamKind.peqGain, -3.0)),
        throwsA(isA<UnsupportedIcp5WriteOperation>()),
      );
      expect(t.gainWrites, isEmpty);
    });
  });

  // ── Band index mapping: UI band 1 → protocol band 0, UI band 10 → band 9 ──

  group('band index mapping (plan → port → transport)', () {
    // Band keys in the export package: 'band_0' .. 'band_9'
    // (band_0 = UI "Band 1"; band_9 = UI "Band 10")

    test('band_0 key → bandIndex 0 → transport band 0 (UI Band 1)', () {
      final plan = buildHardwareWritePlan(
        DspExportPackage(id: 'e', parameterBlocks: [
          ExportParameterBlock(
            id: 'b', type: ExportBlockType.peq, channelId: 'ch_tw_l',
            title: 'PEQ', summary: '',
            parameters: {'bands': {'band_0': {'freq_hz': 1000.0, 'gain_db': -3.0, 'q': 1.0, 'type': 'peak'}}},
          ),
        ]),
        HardwareDeviceProfiles.adau1701Icp5,
      );
      final gainOp = plan.operations
          .firstWhere((o) => o.parameterKind == HardwareParamKind.peqGain);
      expect(gainOp.bandIndex, 0);
    });

    test('band_9 key → bandIndex 9 → transport band 9 (UI Band 10)', () async {
      final t = _FakeTransport();
      final report = await _port(t)
          .preflightAndWrite(_op('ch_tw_l', HardwareParamKind.peqGain, -2.0, band: 9));
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isTrue);
      expect(t.gainWrites, [(0, -2.0, 9)]);
    });
  });

  // ── Transport method dispatch parity ────────────────────────────────────────

  group('PEQ gain dispatch — param 0x18 property 0x01', () {
    test('band 0 gain: writePeqGain called, readback-verified', () async {
      final t = _FakeTransport();
      final report = await _port(t, readback: _readOk(gainDb: -3.0))
          .preflightAndWrite(_op('ch_tw_l', HardwareParamKind.peqGain, -3.0));

      expect(t.gainWrites, [(0, -3.0, 0)]);
      expect(t.peqFreqWrites, isEmpty);
      expect(t.filterFreqWrites, isEmpty);
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isFalse); // readback-verified path
    });

    test('band 5 gain: writePeqGain called with band 5, ACK-only', () async {
      final t = _FakeTransport();
      final report = await _port(t)
          .preflightAndWrite(_op('ch_wf_l', HardwareParamKind.peqGain, 2.0, band: 5));

      expect(t.gainWrites, [(1, 2.0, 5)]);
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isTrue);
    });
  });

  group('PEQ frequency dispatch — param 0x18 property 0x02', () {
    test('band 0 frequency: writePeqFrequency called (NOT writeFilterFrequency)', () async {
      final t = _FakeTransport();
      final report = await _port(t, readback: _readOk(freq: 2500))
          .preflightAndWrite(_op('ch_tw_l', HardwareParamKind.peqFrequency, 2500));

      expect(t.peqFreqWrites, [(0, 2500, 0)]);
      expect(t.filterFreqWrites, isEmpty, // XO method must NOT be called for PEQ
          reason: 'PEQ frequency uses param 0x18, not param 0x15');
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isFalse);
    });

    test('band 3 frequency: writePeqFrequency with band 3, ACK-only', () async {
      final t = _FakeTransport();
      final report = await _port(t)
          .preflightAndWrite(_op('ch_wf_r', HardwareParamKind.peqFrequency, 1500, band: 3));

      expect(t.peqFreqWrites, [(3, 1500, 3)]);
      expect(t.filterFreqWrites, isEmpty);
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isTrue);
    });
  });

  group('PEQ Q dispatch — param 0x18 property 0x00', () {
    test('band 0 Q: writePeqQ called, ACK-only (no Q readback)', () async {
      final t = _FakeTransport();
      final report = await _port(t)
          .preflightAndWrite(_op('ch_tw_r', HardwareParamKind.peqQ, 0.7));

      expect(t.qWrites, [(2, 0.7, 0)]);
      expect(t.gainWrites, isEmpty);
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isTrue);
    });

    test('band 9 Q: writePeqQ with band 9, ACK-only (boundary)', () async {
      final t = _FakeTransport();
      final report = await _port(t)
          .preflightAndWrite(_op('ch_wf_l', HardwareParamKind.peqQ, 2.5, band: 9));

      expect(t.qWrites, [(1, 2.5, 9)]);
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isTrue);
    });
  });

  group('XO dispatch — param 0x15 (writeFilterFrequency)', () {
    test('crossoverHighPass: writeFilterFrequency called (NOT writePeqFrequency), ACK-only', () async {
      final t = _FakeTransport();
      final report = await _port(t).preflightAndWrite(HardwareWriteOp(
        channelId: 'ch_wf_l',
        parameterKind: HardwareParamKind.crossoverHighPass,
        bandIndex: null,
        targetValue: 3000,
        verification: HardwareParamVerification.captureProven,
        writable: true,
        reason: 'test',
      ));

      expect(t.filterFreqWrites, [(1, 3000)]);
      expect(t.peqFreqWrites, isEmpty, // PEQ method must NOT be called for XO
          reason: 'XO uses param 0x15, not param 0x18');
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isTrue,
          reason: 'PEQ readback cannot verify param 0x15 writes');
      expect(report.deploymentResult!.message, contains('crossover'));
    });

    test('crossoverLowPass: writeFilterFrequency called, ACK-only', () async {
      final t = _FakeTransport();
      final report = await _port(t).preflightAndWrite(HardwareWriteOp(
        channelId: 'ch_tw_r',
        parameterKind: HardwareParamKind.crossoverLowPass,
        bandIndex: null,
        targetValue: 1500,
        verification: HardwareParamVerification.captureProven,
        writable: true,
        reason: 'test',
      ));

      expect(t.filterFreqWrites, [(2, 1500)]);
      expect(t.peqFreqWrites, isEmpty);
      expect(report.isAckOnly, isTrue);
    });

    test('XO NACK → deploymentSucceeded=false, isAckOnly=false', () async {
      final t = _FakeTransport()..ackSuccess = false;
      final report = await _port(t).preflightAndWrite(HardwareWriteOp(
        channelId: 'ch_wf_l',
        parameterKind: HardwareParamKind.crossoverHighPass,
        bandIndex: null,
        targetValue: 2000,
        verification: HardwareParamVerification.captureProven,
        writable: true,
        reason: 'test',
      ));

      expect(t.filterFreqWrites, isNotEmpty);
      expect(report.deploymentSucceeded, isFalse);
      expect(report.isAckOnly, isFalse);
    });
  });

  // ── Band 0 readback captures originalState for restore ────────────────────

  test('band 0 gain sets capturedOriginalState on report', () async {
    final t = _FakeTransport();
    final report = await _port(t, readback: _readOk(gainDb: -3.0))
        .preflightAndWrite(_op('ch_tw_l', HardwareParamKind.peqGain, -3.0));

    expect(report.capturedOriginalState, isNotNull,
        reason: 'band 0 readback-verified path must store pre-write state for restore');
    expect(report.capturedOriginalState!.gainDb, closeTo(-1.0, 0.01),
        reason: 'originalState is the PRE-write preflight read, not the write target');
  });

  test('band 1+ gain does NOT set capturedOriginalState (ACK-only, no pre-write read)', () async {
    final t = _FakeTransport();
    final report = await _port(t)
        .preflightAndWrite(_op('ch_tw_l', HardwareParamKind.peqGain, -3.0, band: 1));

    expect(report.capturedOriginalState, isNull);
    expect(report.isAckOnly, isTrue);
  });

  // ── ACK-only does not count as failure ────────────────────────────────────

  test('ACK-only band-1 gain: deploymentSucceeded=true, isAckOnly=true', () async {
    final t = _FakeTransport();
    final report = await _port(t)
        .preflightAndWrite(_op('ch_tw_l', HardwareParamKind.peqGain, -2.0, band: 1));

    expect(report.deploymentSucceeded, isTrue);
    expect(report.isAckOnly, isTrue);
    expect(report.deploymentResult!.success, isTrue);
  });
}
