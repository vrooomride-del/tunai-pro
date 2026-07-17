import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/adau1701_peq_deployment_gate.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';

// State A payload: 1800 Hz, -1.0 dB, Q 2.0, property08State 1.
// Unique markers at bytes 154 / 308 so collector does not reject as duplicates.
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

RawDspStateSnapshot _snapshot({String deviceId = _kDeviceId}) =>
    RawDspStateSnapshot(
      deviceId: deviceId,
      timestamp: DateTime.utc(2025, 6, 1, 12),
      blockId: 0x2202,
      payload: _stateAPayload(),
    );

// ── Fake transport ────────────────────────────────────────────────────────────

class _FakeTransport implements Adau1701RawReadTransport {
  @override
  final bool isConnected;
  @override
  bool get handshakeComplete => true;
  @override
  String? get detectedProfile => _kDeviceId;
  final Object? _error;
  final RawDspStateSnapshot? _snapshot;

  const _FakeTransport({
    this.isConnected = true,
    RawDspStateSnapshot? snapshot,
    Object? error,
  })  : _snapshot = snapshot,
        _error = error;

  @override
  Future<RawDspStateSnapshot> readRawDspState() async {
    if (_error != null) throw _error!;
    return _snapshot!;
  }
}

_FakeTransport _ready({RawDspStateSnapshot? snapshot, Object? error}) =>
    _FakeTransport(snapshot: snapshot ?? _snapshot(), error: error);

Adau1701PeqDeploymentGate _gate({_FakeTransport? transport}) =>
    Adau1701PeqDeploymentGate(transport: transport ?? _ready());

// ── Write plans ───────────────────────────────────────────────────────────────

const _gainPlan = Adau1701PeqWriteFields(gain: true);
const _freqGainQPlan = Adau1701PeqWriteFields(
  frequency: true,
  gain: true,
  q: true,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Adau1701PeqDeploymentGate', () {
    test('initial state: no result, deployment not allowed', () {
      final gate = _gate();
      expect(gate.lastResult, isNull);
      expect(gate.isDeploymentAllowed, isFalse);
    });

    test('preflight pass → isDeploymentAllowed true, result populated',
        () async {
      final gate = _gate();
      final result = await gate.runPreflight(_gainPlan);

      expect(result.passed, isTrue);
      expect(gate.isDeploymentAllowed, isTrue);
      expect(gate.lastResult, same(result));
    });

    test('preflight pass allows existing deployment flow', () async {
      // Simulate the deployment flow: gate must pass before write is called.
      final gate = _gate();
      bool writeExecuted = false;

      await gate.runPreflight(_gainPlan);

      if (gate.isDeploymentAllowed) {
        // In production this triggers the actual PEQ write.
        writeExecuted = true;
      }

      expect(writeExecuted, isTrue,
          reason: 'write must execute after a passing preflight');
    });

    test('failed preflight blocks write', () async {
      final gate = _gate(
        transport: const _FakeTransport(isConnected: false),
      );
      bool writeExecuted = false;

      await gate.runPreflight(_gainPlan);

      if (gate.isDeploymentAllowed) {
        writeExecuted = true;
      }

      expect(writeExecuted, isFalse,
          reason: 'write must be blocked after a failing preflight');
      expect(gate.lastResult!.status,
          Adau1701PreflightStatus.transportNotReady);
    });

    test('transport error → preflight fails, write blocked', () async {
      final gate = _gate(
        transport: _ready(error: StateError('port lost')),
      );
      final result = await gate.runPreflight(_gainPlan);

      expect(result.passed, isFalse);
      expect(gate.isDeploymentAllowed, isFalse);
    });

    test('wrong device identity → preflight fails', () async {
      final gate = _gate(
        transport: _ready(
          snapshot: _snapshot(deviceId: 'DSP9999.000.00.00'),
        ),
      );
      final result = await gate.runPreflight(_gainPlan);

      expect(result.passed, isFalse);
      expect(result.status, Adau1701PreflightStatus.deviceIdentityMismatch);
      expect(gate.isDeploymentAllowed, isFalse);
    });

    test('invalidate clears result and blocks deployment', () async {
      final gate = _gate();
      await gate.runPreflight(_gainPlan);
      expect(gate.isDeploymentAllowed, isTrue);

      gate.invalidate();

      expect(gate.lastResult, isNull);
      expect(gate.isDeploymentAllowed, isFalse);
    });

    test('re-running preflight after invalidate restores allowed state',
        () async {
      final gate = _gate();
      await gate.runPreflight(_gainPlan);
      gate.invalidate();
      final result = await gate.runPreflight(_gainPlan);

      expect(result.passed, isTrue);
      expect(gate.isDeploymentAllowed, isTrue);
    });
  });

  group('Adau1701PreflightDiagnostics', () {
    test('passed result → all fields populated in diagnostics', () async {
      final gate = _gate();
      final result = await gate.runPreflight(_freqGainQPlan);
      final diag = Adau1701PreflightDiagnostics.fromResult(result);

      expect(diag.passed, isTrue);
      expect(diag.status, Adau1701PreflightStatus.passed);
      expect(diag.dspIdentity, _kDeviceId);
      expect(diag.snapshotCapturedAt, isNotNull);
      expect(diag.frequencyHz, 1800);
      expect(diag.gainDb, closeTo(-1.0, 0.001));
      expect(diag.q, closeTo(2.0, 0.001));
      expect(diag.property08State, 1);
      expect(diag.coverageIsCovered, isTrue);
      expect(diag.missingFields, isEmpty);
    });

    test('failure result → relevant fields populated, state fields null',
        () async {
      final gate = _gate(
        transport: const _FakeTransport(isConnected: false),
      );
      final result = await gate.runPreflight(_gainPlan);
      final diag = Adau1701PreflightDiagnostics.fromResult(result);

      expect(diag.passed, isFalse);
      expect(diag.dspIdentity, isNull);
      expect(diag.frequencyHz, isNull);
      expect(diag.gainDb, isNull);
      expect(diag.missingFields, isEmpty);
    });

    test('diagnostics message is non-empty for all outcomes', () async {
      for (final transport in [
        _ready(),
        const _FakeTransport(isConnected: false),
        _ready(error: StateError('x')),
      ]) {
        final gate = _gate(transport: transport);
        final result = await gate.runPreflight(_gainPlan);
        final diag = Adau1701PreflightDiagnostics.fromResult(result);
        expect(diag.message, isNotEmpty,
            reason: 'message must be set for status ${diag.status}');
      }
    });
  });
}
