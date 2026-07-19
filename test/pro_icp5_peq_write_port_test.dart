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
  final List<(int, int)> freqWrites = [];
  final List<(int, double)> qWrites = [];
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
    return Adau1701WriteAck(success: ackSuccess, message: 'freq');
  }

  @override
  Future<Adau1701WriteAck> writePeqQ(int channel, double q,
      {int band = 0}) async {
    qWrites.add((channel, q));
    return Adau1701WriteAck(success: ackSuccess, message: 'q');
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

    expect(t.freqWrites, [(0, 2500)]);
    expect(t.gainWrites, isEmpty);
    expect(report.deploymentAllowed, isTrue);
    expect(report.deploymentSucceeded, isTrue);
  });

  test('unsupported Q is blocked — throws, no write', () async {
    final t = _FakeTuningTransport();
    await expectLater(
      _port(t).preflightAndWrite(_op(HardwareParamKind.peqQ, 2.0)),
      throwsA(isA<UnsupportedIcp5WriteOperation>()),
    );
    expect(t.gainWrites, isEmpty);
    expect(t.freqWrites, isEmpty);
    expect(t.qWrites, isEmpty);
  });

  test('Band 2 (index 1) is blocked — throws, no write', () async {
    final t = _FakeTuningTransport();
    await expectLater(
      _port(t)
          .preflightAndWrite(_op(HardwareParamKind.peqGain, -3.0, band: 1)),
      throwsA(isA<UnsupportedIcp5WriteOperation>()),
    );
    expect(t.gainWrites, isEmpty);
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
}
