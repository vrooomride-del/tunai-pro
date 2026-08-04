import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/deploy/pro_icp5_peq_write_port.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/adau1701_peq_deployment_gate.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

const _kDeviceId = 'DSP1701.100.00.01';

// State A payload used by the existing gate/preflight tests: decodes to a valid
// ch0/band0 state so the REAL preflight passes.
List<int> _stateAPayload() {
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

RawDspStateSnapshot _snapshot() => RawDspStateSnapshot(
      deviceId: _kDeviceId,
      timestamp: DateTime.utc(2025, 6, 1, 12),
      blockId: 0x2202,
      payload: _stateAPayload(),
    );

// ── Fake tuning transport (write + raw read surface) ──────────────────────────

class _FakeTuningTransport implements Adau1701TuningTransport {
  final bool connected;
  _FakeTuningTransport({this.connected = true});

  final List<(int, double)> gainWrites = [];
  final List<(int, int, double)> gainBandWrites = [];
  final List<(int, int)> freqWrites = [];        // XO: writeFilterFrequency (param 0x15)
  final List<(int, int)> peqFreqWrites = [];     // PEQ: writePeqFrequency (param 0x18)
  final List<(int, int, int)> peqFreqBandWrites = [];
  final List<(int, double)> qWrites = [];
  final List<(int, double)> outputGainWrites = [];
  bool ackSuccess = true;

  @override
  bool get isConnected => connected;
  @override
  bool get handshakeComplete => connected;
  @override
  String? get detectedProfile => connected ? _kDeviceId : null;

  @override
  Future<RawDspStateSnapshot> readRawDspState() async => _snapshot();

  @override
  Future<Adau1701WriteAck> writePeqGain(int channel, double gainDb,
      {int band = 0}) async {
    gainWrites.add((channel, gainDb));
    gainBandWrites.add((channel, band, gainDb));
    return Adau1701WriteAck(success: ackSuccess, message: 'gain');
  }

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz,
      {int band = 0, bool isHighPass = false}) async {
    freqWrites.add((channel, frequencyHz));
    return Adau1701WriteAck(success: ackSuccess, message: 'filterFreq');
  }

  @override
  Future<Adau1701WriteAck> writePeqFrequency(int channel, int frequencyHz,
      {int band = 0}) async {
    peqFreqWrites.add((channel, frequencyHz));
    peqFreqBandWrites.add((channel, band, frequencyHz));
    return Adau1701WriteAck(success: ackSuccess, message: 'peqFreq');
  }

  @override
  Future<Adau1701WriteAck> writePeqQ(int channel, double q,
      {int band = 0}) async {
    qWrites.add((channel, q));
    return Adau1701WriteAck(success: ackSuccess, message: 'q');
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

// Injectable read service returning a canned readback.
class _FakeReadService extends Adau1701Ch0Band0ReadService {

  final Adau1701Ch0Band0ReadResult result;
  _FakeReadService(Adau1701RawReadTransport t, this.result)
      : super(transport: t);
  @override
  Future<Adau1701Ch0Band0ReadResult> readOriginalState() async => result;
}

Adau1701Ch0Band0ReadResult _readOk({double gainDb = -1.0, int freq = 1800}) =>
    Adau1701Ch0Band0ReadResult.success(Adau1701Ch0Band0OriginalState(
      deviceId: _kDeviceId,
      capturedAt: DateTime.utc(2025),
      frequencyHz: freq,
      gainDb: gainDb,
      q: 2.0,
      property08State: 1,
    ));

const _readFail = Adau1701Ch0Band0ReadResult.failure(
    Adau1701Ch0Band0ReadStatus.rawReadFailed, 'read failed');

// Stateful read service: returns responses from [responses] in order;
// the last entry is repeated once exhausted.
class _SequentialReadService extends Adau1701Ch0Band0ReadService {
  final List<Adau1701Ch0Band0ReadResult> responses;
  int _call = 0;
  _SequentialReadService(Adau1701RawReadTransport t, this.responses)
      : super(transport: t);

  @override
  Future<Adau1701Ch0Band0ReadResult> readOriginalState() async {
    final i = _call < responses.length ? _call : responses.length - 1;
    _call++;
    return responses[i];
  }
}

// Counts readOriginalState() calls while returning a fixed result.
class _CountingReadService extends Adau1701Ch0Band0ReadService {
  final Adau1701Ch0Band0ReadResult result;
  int callCount = 0;
  _CountingReadService(Adau1701RawReadTransport t, this.result)
      : super(transport: t);

  @override
  Future<Adau1701Ch0Band0ReadResult> readOriginalState() async {
    callCount++;
    return result;
  }
}

Adau1701Icp5PeqWritePort _retryPort(
  _FakeTuningTransport t,
  List<Adau1701Ch0Band0ReadResult> readbacks, {
  int maxAttempts = 3,
}) =>
    Adau1701Icp5PeqWritePort(
      transport: t,
      gate: Adau1701PeqDeploymentGate(transport: t),
      readService: _SequentialReadService(t, readbacks),
      channelResolver: (id) => id == 'wf' ? 0 : -1,
      clock: () => DateTime.utc(2026, 7, 19),
      maxReadbackAttempts: maxAttempts,
      readbackRetryDelay: Duration.zero,
    );

// Build a port with the real gate + a fake transport/read service.
Adau1701Icp5PeqWritePort _port(
  _FakeTuningTransport t, {
  Adau1701Ch0Band0ReadResult? readback,
}) =>
    Adau1701Icp5PeqWritePort(
      transport: t,
      gate: Adau1701PeqDeploymentGate(transport: t),
      readService: _FakeReadService(t, readback ?? _readOk()),
      channelResolver: (id) => id == 'wf' ? 0 : -1,
      clock: () => DateTime.utc(2026, 7, 19),
    );

// A capture-proven op, as it would arrive from an approved plan.
HardwareWriteOp _op(HardwareParamKind kind, num value,
        {int? band = 0, String channelId = 'wf'}) =>
    HardwareWriteOp(
      channelId: channelId,
      parameterKind: kind,
      bandIndex: band,
      targetValue: value,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );

void main() {
  test('Band 1 gain writes through the transport and verifies', () async {
    final t = _FakeTuningTransport();
    final report = await _port(t, readback: _readOk(gainDb: -3.0))
        .preflightAndWrite(
            _op(HardwareParamKind.peqGain, -3.0));

    expect(t.gainWrites, [(0, -3.0)]);
    expect(t.freqWrites, isEmpty);
    expect(report.deploymentAllowed, isTrue);
    expect(report.deploymentSucceeded, isTrue);
  });

  test('Band 1 frequency writes through the transport and verifies', () async {
    final t = _FakeTuningTransport();
    final report = await _port(t, readback: _readOk(freq: 2500))
        .preflightAndWrite(
            _op(HardwareParamKind.peqFrequency, 2500));

    // Must use writePeqFrequency (param 0x18 property 0x02), NOT writeFilterFrequency.
    expect(t.peqFreqWrites, [(0, 2500)]);
    expect(t.freqWrites, isEmpty); // writeFilterFrequency (param 0x15) not called
    expect(t.gainWrites, isEmpty);
    expect(report.deploymentAllowed, isTrue);
    expect(report.deploymentSucceeded, isTrue);
  });

  test('Q (band 0) dispatches ACK-only — Consumer-production-proven', () async {
    final t = _FakeTuningTransport();
    final report = await _port(t).preflightAndWrite(
        _op(HardwareParamKind.peqQ, 2.0));

    expect(t.qWrites, [(0, 2.0)]);
    expect(t.gainWrites, isEmpty);
    expect(t.freqWrites, isEmpty);
    expect(t.peqFreqWrites, isEmpty);
    expect(report.deploymentAllowed, isTrue);
    expect(report.deploymentSucceeded, isTrue);
    expect(report.isAckOnly, isTrue);
  });

  test('Band 1 (index 1) gain dispatches ACK-only — Consumer-production-proven',
      () async {
    final t = _FakeTuningTransport();
    final report = await _port(t)
        .preflightAndWrite(_op(HardwareParamKind.peqGain, -3.0, band: 1));

    expect(t.gainWrites, [(0, -3.0)]);
    expect(report.deploymentAllowed, isTrue);
    expect(report.deploymentSucceeded, isTrue);
    expect(report.isAckOnly, isTrue);
  });

  test('preflight failure blocks the write', () async {
    final t = _FakeTuningTransport(connected: false); // transport not ready
    final report = await _port(t)
        .preflightAndWrite(_op(HardwareParamKind.peqGain, -3.0));

    expect(report.deploymentAllowed, isFalse);
    expect(report.deploymentResult, isNull);
    expect(t.gainWrites, isEmpty); // never written
    expect(report.preflightFailureReason, isNotNull);
  });

  test('readback failure is reported (write attempted, not confirmed)',
      () async {
    final t = _FakeTuningTransport();
    final report = await _port(t, readback: _readFail)
        .preflightAndWrite(_op(HardwareParamKind.peqGain, -3.0));

    expect(report.deploymentAllowed, isTrue);
    expect(t.gainWrites, [(0, -3.0)]); // write happened
    expect(report.deploymentSucceeded, isFalse); // but not confirmed
    expect(report.deploymentResult!.message, contains('readback'));
  });

  test('readback value mismatch is not confirmed', () async {
    final t = _FakeTuningTransport();
    // Wrote -3.0 but device reads -1.0 → mismatch.
    final report = await _port(t, readback: _readOk(gainDb: -1.0))
        .preflightAndWrite(_op(HardwareParamKind.peqGain, -3.0));
    expect(report.deploymentSucceeded, isFalse);
  });

  test('unresolved channel throws before any I/O', () async {
    final t = _FakeTuningTransport();
    const op = HardwareWriteOp(
      channelId: 'unknown',
      parameterKind: HardwareParamKind.peqGain,
      bandIndex: 0,
      targetValue: -3.0,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );
    await expectLater(
      _port(t).preflightAndWrite(op),
      throwsA(isA<UnsupportedIcp5WriteOperation>()),
    );
    expect(t.gainWrites, isEmpty);
  });

  test('crossoverHighPass writes through transport, ACK-only (param 0x15)',
      () async {
    final t = _FakeTuningTransport();
    const op = HardwareWriteOp(
      channelId: 'wf',
      parameterKind: HardwareParamKind.crossoverHighPass,
      bandIndex: null,
      targetValue: 2000,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );
    final report = await _port(t).preflightAndWrite(op);

    expect(t.freqWrites, [(0, 2000)]);
    expect(t.gainWrites, isEmpty);
    expect(report.deploymentAllowed, isTrue);
    expect(report.deploymentSucceeded, isTrue);
    // XO uses param 0x15; PEQ readback (param 0x18) cannot verify it → ACK-only.
    expect(report.isAckOnly, isTrue);
    expect(report.deploymentResult!.message, contains('crossover'));
  });

  test('crossoverLowPass writes through transport, ACK-only (param 0x15)',
      () async {
    final t = _FakeTuningTransport();
    const op = HardwareWriteOp(
      channelId: 'wf',
      parameterKind: HardwareParamKind.crossoverLowPass,
      bandIndex: null,
      targetValue: 2000,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );
    final report = await _port(t).preflightAndWrite(op);

    expect(t.freqWrites, [(0, 2000)]);
    expect(report.deploymentAllowed, isTrue);
    expect(report.deploymentSucceeded, isTrue);
    expect(report.isAckOnly, isTrue);
  });

  test('channelGain writes through transport, ACK-only, no readback required',
      () async {
    final t = _FakeTuningTransport();
    const op = HardwareWriteOp(
      channelId: 'wf',
      parameterKind: HardwareParamKind.channelGain,
      bandIndex: null,
      targetValue: -3.5,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );
    final report = await _port(t).preflightAndWrite(op);

    expect(t.outputGainWrites, [(0, -3.5)]);
    expect(t.gainWrites, isEmpty);
    expect(t.freqWrites, isEmpty);
    expect(report.deploymentAllowed, isTrue);
    expect(report.deploymentSucceeded, isTrue);
    expect(report.deploymentResult!.message, contains('ACKed'));
  });

  test('channelGain preflight failure blocks write', () async {
    final t = _FakeTuningTransport(connected: false);
    const op = HardwareWriteOp(
      channelId: 'wf',
      parameterKind: HardwareParamKind.channelGain,
      bandIndex: null,
      targetValue: -3.5,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );
    final report = await _port(t).preflightAndWrite(op);

    expect(report.deploymentAllowed, isFalse);
    expect(t.outputGainWrites, isEmpty);
  });

  // ── Bounded readback retry tests ────────────────────────────────────────────

  group('Bounded frequency readback retry', () {
    test(
        'first readback returns old value, second returns target → Written',
        () async {
      final t = _FakeTuningTransport();
      final port = _retryPort(t, [
        _readOk(freq: 1800), // attempt 1: old value
        _readOk(freq: 1000), // attempt 2: target
      ]);

      final report = await port.preflightAndWrite(
          _op(HardwareParamKind.peqFrequency, 1000));

      expect(report.deploymentAllowed, isTrue);
      expect(report.deploymentSucceeded, isTrue,
          reason: 'second readback matches target');
      expect(report.deploymentResult!.message, contains('attempt 2'));
    });

    test(
        'all readbacks return old value → Failed with target/readback/attempts in message',
        () async {
      final t = _FakeTuningTransport();
      final port = _retryPort(
        t,
        [_readOk(freq: 1800)], // always returns old value
        maxAttempts: 3,
      );

      final report = await port.preflightAndWrite(
          _op(HardwareParamKind.peqFrequency, 1000));

      expect(report.deploymentAllowed, isTrue);
      expect(report.deploymentSucceeded, isFalse);
      final msg = report.deploymentResult!.message;
      expect(msg, contains('3 attempt(s)'));
      expect(msg, contains('1000 Hz'));
      expect(msg, contains('1800 Hz'));
    });

    test('NACK → no readback attempted, immediate failure', () async {
      final t = _FakeTuningTransport()..ackSuccess = false;
      final counting = _CountingReadService(t, _readOk(freq: 1800));
      final port = Adau1701Icp5PeqWritePort(
        transport: t,
        gate: Adau1701PeqDeploymentGate(transport: t),
        readService: counting,
        channelResolver: (id) => 0,
        clock: () => DateTime.utc(2026),
        maxReadbackAttempts: 3,
        readbackRetryDelay: Duration.zero,
      );

      final report = await port.preflightAndWrite(
          _op(HardwareParamKind.peqFrequency, 1000));

      expect(report.deploymentSucceeded, isFalse);
      expect(counting.callCount, 0, reason: 'NACK must skip all readbacks');
      expect(report.deploymentResult!.message, contains('NACK'));
    });

    test('readback read error stops retrying immediately', () async {
      final t = _FakeTuningTransport();
      final port = _retryPort(t, [
        _readFail,            // read error on first attempt
        _readOk(freq: 1000), // would succeed but must not be reached
      ]);

      final report = await port.preflightAndWrite(
          _op(HardwareParamKind.peqFrequency, 1000));

      expect(report.deploymentSucceeded, isFalse);
      expect(report.deploymentResult!.message, contains('readback failed'));
    });

    test('gain path unchanged — single read, no retry', () async {
      final t = _FakeTuningTransport();
      final port = _retryPort(t, [
        _readOk(gainDb: -3.0), // first read matches
        _readOk(gainDb: -9.0), // second read would not match — must not be called
      ], maxAttempts: 3);

      final report = await port.preflightAndWrite(
          _op(HardwareParamKind.peqGain, -3.0));

      expect(report.deploymentSucceeded, isTrue,
          reason: 'gain verifies on single read');
    });
  });

  // ── ACK-only dispatch: Q + bands 1–9 ────────────────────────────────────────

  group('UI band to protocol band readback boundary', () {
    Adau1701Icp5PeqWritePort countingPort(
      _FakeTuningTransport transport,
      _CountingReadService reads,
    ) =>
        Adau1701Icp5PeqWritePort(
          transport: transport,
          gate: Adau1701PeqDeploymentGate(transport: transport),
          readService: reads,
          channelResolver: (id) => switch (id) {
            'ch_tw_l' => 0,
            'ch_wf_l' => 1,
            'ch_tw_r' => 2,
            'ch_wf_r' => 3,
            _ => -1,
          },
          readbackRetryDelay: Duration.zero,
        );

    test('UI B1/ch0 maps protocol0 and invokes readback', () async {
      final transport = _FakeTuningTransport();
      final reads = _CountingReadService(transport, _readOk(gainDb: -1));
      final report = await countingPort(transport, reads).preflightAndWrite(
        _op(HardwareParamKind.peqGain, -1,
            band: 0, channelId: 'ch_tw_l'),
      );

      expect(transport.gainBandWrites, [(0, 0, -1.0)]);
      expect(reads.callCount, 1);
      expect(report.isAckOnly, isFalse);
    });

    test('UI B2/ch0 maps protocol1 with zero readback and ACK-only', () async {
      final transport = _FakeTuningTransport();
      final reads = _CountingReadService(transport, _readFail);
      final report = await countingPort(transport, reads).preflightAndWrite(
        _op(HardwareParamKind.peqGain, -2,
            band: 1, channelId: 'ch_tw_l'),
      );

      expect(transport.gainBandWrites, [(0, 1, -2.0)]);
      expect(reads.callCount, 0);
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isTrue);
    });

    test('UI B10/ch0 maps protocol9 with zero readback and ACK-only', () async {
      final transport = _FakeTuningTransport();
      final reads = _CountingReadService(transport, _readFail);
      final report = await countingPort(transport, reads).preflightAndWrite(
        _op(HardwareParamKind.peqGain, -2,
            band: 9, channelId: 'ch_tw_l'),
      );

      expect(transport.gainBandWrites, [(0, 9, -2.0)]);
      expect(reads.callCount, 0);
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isTrue);
    });

    test('60 PEQ operations complete without ACK-only readback misrouting',
        () async {
      final transport = _FakeTuningTransport();
      final reads = _CountingReadService(
          transport, _readOk(gainDb: -1, freq: 1800));
      final port = countingPort(transport, reads);
      final reports = <Adau1701DeploymentReport>[];
      for (final channelId in ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r']) {
        for (var band = 0; band < 5; band++) {
          reports.add(await port.preflightAndWrite(HardwareWriteOp(
            channelId: channelId,
            parameterKind: HardwareParamKind.peqGain,
            bandIndex: band,
            targetValue: -1,
            verification: HardwareParamVerification.captureProven,
            writable: true,
            reason: '60-op regression',
          )));
          reports.add(await port.preflightAndWrite(HardwareWriteOp(
            channelId: channelId,
            parameterKind: HardwareParamKind.peqFrequency,
            bandIndex: band,
            targetValue: 1800,
            verification: HardwareParamVerification.captureProven,
            writable: true,
            reason: '60-op regression',
          )));
          reports.add(await port.preflightAndWrite(HardwareWriteOp(
            channelId: channelId,
            parameterKind: HardwareParamKind.peqQ,
            bandIndex: band,
            targetValue: 2,
            verification: HardwareParamVerification.captureProven,
            writable: true,
            reason: '60-op regression',
          )));
        }
      }

      expect(reports, hasLength(60));
      expect(reports.every((report) => report.deploymentSucceeded), isTrue);
      expect(reads.callCount, 2,
          reason: 'only ch0 protocol band0 gain/frequency use readback');
      expect(reports.where((report) => report.isAckOnly), hasLength(58));
    });
  });

  test('Q on band 9 (boundary) dispatches ACK-only', () async {
    final t = _FakeTuningTransport();
    final report = await _port(t)
        .preflightAndWrite(_op(HardwareParamKind.peqQ, 0.7, band: 9));

    expect(t.qWrites, [(0, 0.7)]);
    expect(report.deploymentSucceeded, isTrue);
    expect(report.isAckOnly, isTrue);
  });

  test('Band 9 (boundary) frequency dispatches ACK-only', () async {
    final t = _FakeTuningTransport();
    final report = await _port(t)
        .preflightAndWrite(_op(HardwareParamKind.peqFrequency, 4000, band: 9));

    expect(t.peqFreqWrites, [(0, 4000)]);
    expect(t.freqWrites, isEmpty);
    expect(report.deploymentSucceeded, isTrue);
    expect(report.isAckOnly, isTrue);
  });

  test('ACK-only NACK (transport error) reports failed, not ackOnly', () async {
    final t = _FakeTuningTransport()..ackSuccess = false;
    // Band 1 gain → ACK-only path; transport returns NACK.
    final report = await _port(t)
        .preflightAndWrite(_op(HardwareParamKind.peqGain, -3.0, band: 1));

    expect(t.gainWrites, [(0, -3.0)]);
    expect(report.deploymentSucceeded, isFalse);
    expect(report.isAckOnly, isFalse,
        reason: 'isAckOnly is only true when the ACK actually succeeded');
  });

  // ── Protocol channel 1 / band 0 regression (실기: ch_wf_l = protocol ch 1) ───
  //
  // 실기 재현: ch_wf_l → protocol channel 1 / band 0 write ACKs successfully
  // but the old code ran the ch0/band0 readback path and compared the ch0 DSP
  // slot against the ch1 target → guaranteed frequency/gain mismatch.
  // Fix: channel != 0 at band 0 → ACK-only, same as bands 1–9.

  group('Protocol ch1 / band 0 — ACK-only, no ch0 readback mismatch', () {
    Adau1701Icp5PeqWritePort _portCh(
      _FakeTuningTransport t,
      int protocolChannel, {
      Adau1701Ch0Band0ReadResult? readback,
    }) =>
        Adau1701Icp5PeqWritePort(
          transport: t,
          gate: Adau1701PeqDeploymentGate(transport: t),
          readService: _FakeReadService(t, readback ?? _readOk()),
          channelResolver: (_) => protocolChannel,
          clock: () => DateTime.utc(2026, 7, 19),
        );

    HardwareWriteOp _ch1Op(HardwareParamKind kind, num value) =>
        HardwareWriteOp(
          channelId: 'ch_wf_l',
          parameterKind: kind,
          bandIndex: 0,
          targetValue: value,
          verification: HardwareParamVerification.captureProven,
          writable: true,
          reason: 'ch1 regression',
        );

    test('gain ch1/band0 → ACK-only success, NOT a readback mismatch', () async {
      final t = _FakeTuningTransport();
      // ch0 readback returns -1.0 dB; target is -3.0 dB — mismatch if compared.
      final report = await _portCh(t, 1, readback: _readOk(gainDb: -1.0))
          .preflightAndWrite(_ch1Op(HardwareParamKind.peqGain, -3.0));

      expect(t.gainWrites, [(1, -3.0)], reason: 'write must use protocol channel 1');
      expect(report.deploymentAllowed, isTrue);
      expect(report.deploymentSucceeded, isTrue,
          reason: 'ch1/band0 gain: ACK-only, ch0 readback must not be compared');
      expect(report.isAckOnly, isTrue);
      expect(report.capturedOriginalState, isNull,
          reason: 'ch0 baseline must not be captured for ch1 writes');
    });

    test('frequency ch1/band0 → ACK-only success, NOT a readback mismatch',
        () async {
      final t = _FakeTuningTransport();
      // ch0 readback returns 1800 Hz; target is 2500 Hz — mismatch if compared.
      final report = await _portCh(t, 1, readback: _readOk(freq: 1800))
          .preflightAndWrite(_ch1Op(HardwareParamKind.peqFrequency, 2500));

      expect(t.peqFreqWrites, [(1, 2500)],
          reason: 'write must use protocol channel 1');
      expect(report.deploymentAllowed, isTrue);
      expect(report.deploymentSucceeded, isTrue,
          reason: 'ch1/band0 freq: ACK-only, ch0 readback must not be compared');
      expect(report.isAckOnly, isTrue);
      expect(report.capturedOriginalState, isNull);
    });

    test('NACK on ch1/band0 gain → failed, not ackOnly', () async {
      final t = _FakeTuningTransport()..ackSuccess = false;
      final report = await _portCh(t, 1)
          .preflightAndWrite(_ch1Op(HardwareParamKind.peqGain, -3.0));

      expect(report.deploymentSucceeded, isFalse);
      expect(report.isAckOnly, isFalse,
          reason: 'isAckOnly is only true when ACK actually succeeded');
    });

    test('channels 2 and 3 at band 0 also ACK-only (boundary)', () async {
      for (final ch in [2, 3]) {
        final t = _FakeTuningTransport();
        // ch0 readback mismatch would fire if not guarded.
        final report = await _portCh(t, ch, readback: _readOk(gainDb: -1.0))
            .preflightAndWrite(_ch1Op(HardwareParamKind.peqGain, -3.0));
        expect(report.deploymentSucceeded, isTrue,
            reason: 'ch$ch/band0 must not compare ch0 readback');
        expect(report.isAckOnly, isTrue,
            reason: 'ch$ch/band0 must be ACK-only');
        expect(report.capturedOriginalState, isNull);
      }
    });

    test('ch0/band0 gain still readback-verified — regression guard', () async {
      final t = _FakeTuningTransport();
      final report = await _port(t, readback: _readOk(gainDb: -3.0))
          .preflightAndWrite(_op(HardwareParamKind.peqGain, -3.0));

      expect(t.gainWrites, [(0, -3.0)]);
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isFalse,
          reason: 'ch0/band0 gain must remain readback-verified');
      expect(report.capturedOriginalState, isNotNull,
          reason: 'ch0 baseline captured only for ch0/band0');
    });

    test('ch0/band0 frequency still readback-verified — regression guard',
        () async {
      final t = _FakeTuningTransport();
      final report = await _port(t, readback: _readOk(freq: 2500))
          .preflightAndWrite(_op(HardwareParamKind.peqFrequency, 2500));

      expect(t.peqFreqWrites, [(0, 2500)]);
      expect(report.deploymentSucceeded, isTrue);
      expect(report.isAckOnly, isFalse,
          reason: 'ch0/band0 freq must remain readback-verified');
    });
  });

  // ── Channel mapping ──────────────────────────────────────────────────────────

  test('unknown channel fails closed before any I/O', () async {
    final t = _FakeTuningTransport();
    // '_port' factory maps only 'wf' → 0; anything else returns -1.
    const op = HardwareWriteOp(
      channelId: 'unknown_ch',
      parameterKind: HardwareParamKind.peqGain,
      bandIndex: 0,
      targetValue: -3.0,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );
    await expectLater(
      _port(t).preflightAndWrite(op),
      throwsA(isA<UnsupportedIcp5WriteOperation>()),
    );
    expect(t.gainWrites, isEmpty);
    expect(t.freqWrites, isEmpty);
  });
}
