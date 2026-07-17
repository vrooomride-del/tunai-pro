import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';
const _kBlockId = 0x2202;

// State A payload: 1800 Hz, -1.0 dB, Q 2.0, property08State 1.
// Pages 1 and 2 carry unique marker bytes so frames are not identical.
List<int> _stateAPayload() {
  final p = List<int>.filled(513, 0x00);
  p[19] = 0x08;
  p[20] = 0x07;
  p[21] = 0xF6; // -1.0 dB
  p[23] = 0x14; // Q 2.0
  p[24] = 0x01; // property08State 1
  p[154] = 0x01; // unique page-1 marker
  p[308] = 0x02; // unique page-2 marker
  return p;
}

RawDspStateSnapshot _snapshot({
  String deviceId = _kDeviceId,
  List<int>? payload,
}) =>
    RawDspStateSnapshot(
      deviceId: deviceId,
      timestamp: DateTime.utc(2025, 6, 1, 12),
      blockId: _kBlockId,
      payload: payload ?? _stateAPayload(),
    );

// ── Fake transport ────────────────────────────────────────────────────────────

class _FakeTransport implements Adau1701RawReadTransport {
  @override
  final bool isConnected;
  @override
  final bool handshakeComplete;
  @override
  final String? detectedProfile;

  final Object? _error;
  final RawDspStateSnapshot? _snapshot;

  const _FakeTransport({
    this.isConnected = true,
    this.handshakeComplete = true,
    this.detectedProfile = _kDeviceId,
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
    _FakeTransport(
      snapshot: snapshot ?? _snapshot(),
      error: error,
    );

// ── Write plans ───────────────────────────────────────────────────────────────

const _freqGainQ = Adau1701PeqWriteFields(
  frequency: true,
  gain: true,
  q: true,
);

const _gainOnly = Adau1701PeqWriteFields(gain: true);

const _withProperty08 = Adau1701PeqWriteFields(
  frequency: true,
  gain: true,
  q: true,
  property08: true,
);

const _property08Only = Adau1701PeqWriteFields(property08: true);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Adau1701DeploymentPreflight', () {
    test('successful preflight: all fields covered, report populated', () async {
      final preflight =
          Adau1701DeploymentPreflight(transport: _ready());
      final result = await preflight.run(writePlan: _freqGainQ);

      expect(result.passed, isTrue);
      expect(result.status, Adau1701PreflightStatus.passed);
      expect(result.confirmedDeviceId, _kDeviceId);
      expect(result.snapshotCapturedAt, isNotNull);
      expect(result.originalState, isNotNull);
      expect(result.originalState!.frequencyHz, 1800);
      expect(result.originalState!.gainDb, closeTo(-1.0, 0.001));
      expect(result.originalState!.q, closeTo(2.0, 0.001));
      expect(result.originalState!.property08State, 1);
      expect(result.coverage, isNotNull);
      expect(result.coverage!.isCovered, isTrue);
      expect(result.coverage!.missingFields, isEmpty);
    });

    test('not connected → transportNotReady, deployment blocked', () async {
      const preflight = Adau1701DeploymentPreflight(
        transport: _FakeTransport(isConnected: false),
      );
      final result = await preflight.run(writePlan: _freqGainQ);

      expect(result.passed, isFalse);
      expect(result.status, Adau1701PreflightStatus.transportNotReady);
      expect(result.confirmedDeviceId, isNull);
      expect(result.originalState, isNull);
    });

    test('handshake not complete → transportNotReady', () async {
      const preflight = Adau1701DeploymentPreflight(
        transport: _FakeTransport(handshakeComplete: false),
      );
      final result = await preflight.run(writePlan: _freqGainQ);
      expect(result.status, Adau1701PreflightStatus.transportNotReady);
    });

    test('wrong firmware profile → transportNotReady', () async {
      const preflight = Adau1701DeploymentPreflight(
        transport: _FakeTransport(detectedProfile: 'DSP9999.000.00.00'),
      );
      final result = await preflight.run(writePlan: _freqGainQ);
      expect(result.status, Adau1701PreflightStatus.transportNotReady);
    });

    test('snapshot carries wrong device identity → deviceIdentityMismatch',
        () async {
      final preflight = Adau1701DeploymentPreflight(
        transport: _ready(snapshot: _snapshot(deviceId: 'DSP9999.000.00.00')),
      );
      final result = await preflight.run(writePlan: _freqGainQ);

      expect(result.passed, isFalse);
      expect(result.status, Adau1701PreflightStatus.deviceIdentityMismatch);
      expect(result.confirmedDeviceId, _kDeviceId);
      expect(result.originalState, isNull);
    });

    test('raw read throws → rawReadFailed, deployment blocked', () async {
      final preflight = Adau1701DeploymentPreflight(
        transport: _ready(error: StateError('port disconnected')),
      );
      final result = await preflight.run(writePlan: _freqGainQ);

      expect(result.passed, isFalse);
      expect(result.status, Adau1701PreflightStatus.rawReadFailed);
      expect(result.message, contains('port disconnected'));
      expect(result.originalState, isNull);
    });

    test('malformed payload → decodeFailed, deployment blocked', () async {
      // All-zero payload: frequencyHz = 0, out of valid range
      final preflight = Adau1701DeploymentPreflight(
        transport: _ready(snapshot: _snapshot(payload: List.filled(513, 0))),
      );
      final result = await preflight.run(writePlan: _freqGainQ);

      expect(result.passed, isFalse);
      expect(result.status, Adau1701PreflightStatus.decodeFailed);
    });

    test(
        'write plan modifies Freq/Gain/Q; original state present → coverage passed',
        () async {
      final preflight = Adau1701DeploymentPreflight(transport: _ready());
      final result = await preflight.run(writePlan: _gainOnly);

      expect(result.passed, isTrue);
      expect(result.coverage!.isCovered, isTrue);
    });

    test(
        'write plan modifies property08; original state present → coverage passed',
        () async {
      final preflight = Adau1701DeploymentPreflight(transport: _ready());
      final result = await preflight.run(writePlan: _withProperty08);

      expect(result.passed, isTrue);
      expect(result.coverage!.isCovered, isTrue);
    });

    test(
        'property08 is NOT required when write plan does not modify it',
        () async {
      final preflight = Adau1701DeploymentPreflight(transport: _ready());
      final result = await preflight.run(writePlan: _freqGainQ);

      // Coverage passes even though property08State is present in original state:
      // the plan doesn't write property 0x08, so it is not a required field.
      expect(result.passed, isTrue);
      expect(result.coverage!.missingFields,
          isNot(contains('property08State')));
    });

    test('property08 IS required when write plan explicitly modifies it',
        () async {
      // A transport with no snapshot → original state will be null on decode
      // path, so coverage will list property08State as missing.
      // Simulate by providing no snapshot to force rawReadFailed path;
      // instead test coverage behavior directly via evaluateOriginalStateCoverage.
      //
      // The preflight result won't reach coverage if the read fails, so we
      // verify the coverage logic separately here.
      final coverage = evaluateOriginalStateCoverage(
        plan: _property08Only,
        originalState: null,
      );
      expect(coverage.status,
          Adau1701OriginalStateCoverageStatus.missingOriginalValues);
      expect(coverage.missingFields, contains('property08State'));
    });

    test(
        'preflight report includes snapshot timestamp and DSP identity on success',
        () async {
      final preflight = Adau1701DeploymentPreflight(transport: _ready());
      final result = await preflight.run(writePlan: _freqGainQ);

      expect(result.passed, isTrue);
      expect(result.snapshotCapturedAt, DateTime.utc(2025, 6, 1, 12));
      expect(result.confirmedDeviceId, _kDeviceId);
      expect(result.message, contains('2025-06-01'));
    });
  });
}
