import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/deploy/pro_icp5_peq_write_port.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/adau1701_peq_deployment_gate.dart';
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
  final List<(int, int)> freqWrites = [];        // XO: writeFilterFrequency (param 0x15)
  final List<(int, int)> peqFreqWrites = [];     // PEQ: writePeqFrequency (param 0x18)
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
    return Adau1701WriteAck(success: ackSuccess, message: 'gain');
  }

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz,
      {int band = 0}) async {
    freqWrites.add((channel, frequencyHz));
    return Adau1701WriteAck(success: ackSuccess, message: 'filterFreq');
  }

  @override
  Future<Adau1701WriteAck> writePeqFrequency(int channel, int frequencyHz,
      {int band = 0}) async {
    peqFreqWrites.add((channel, frequencyHz));
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
HardwareWriteOp _op(HardwareParamKind kind, num value, {int? band = 0}) =>
    HardwareWriteOp(
      channelId: 'wf',
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
