import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

// ── Fixture helpers ──────────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';
const _kBlockId = 0x2202;

/// State A payload bytes: 1800 Hz, -1.0 dB, Q 2.0, property08State 1.
List<int> _stateAPayload() {
  final p = List<int>.filled(513, 0x00);
  p[19] = 0x08;
  p[20] = 0x07;
  p[21] = 0xF6; // -10 → -1.0 dB
  p[23] = 0x14; // 20 → Q 2.0
  p[24] = 0x01;
  return p;
}

RawDspStateSnapshot _snapshot({
  String deviceId = _kDeviceId,
  int blockId = _kBlockId,
  List<int>? payload,
}) =>
    RawDspStateSnapshot(
      deviceId: deviceId,
      timestamp: DateTime.utc(2025, 1, 1),
      blockId: blockId,
      payload: payload ?? _stateAPayload(),
    );

// ── Fake transport ───────────────────────────────────────────────────────────

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
    return _snapshot ?? _snapshot!; // always provided in passing tests
  }
}

_FakeTransport _ready({
  RawDspStateSnapshot? snapshot,
  Object? error,
}) =>
    _FakeTransport(
      snapshot: snapshot ?? _snapshot(),
      error: error,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Adau1701Ch0Band0ReadService', () {
    test('successful raw read → decoded original state', () async {
      final service = Adau1701Ch0Band0ReadService(transport: _ready());
      final result = await service.readOriginalState();

      expect(result.succeeded, isTrue);
      expect(result.status, Adau1701Ch0Band0ReadStatus.success);
      final state = result.originalState!;
      expect(state.deviceId, _kDeviceId);
      expect(state.frequencyHz, 1800);
      expect(state.gainDb, closeTo(-1.0, 0.001));
      expect(state.q, closeTo(2.0, 0.001));
      expect(state.property08State, 1);
    });

    test('transport not connected → transportNotReady', () async {
      const service = Adau1701Ch0Band0ReadService(
        transport: _FakeTransport(isConnected: false),
      );
      final result = await service.readOriginalState();
      expect(result.status, Adau1701Ch0Band0ReadStatus.transportNotReady);
      expect(result.succeeded, isFalse);
    });

    test('handshake not complete → transportNotReady', () async {
      const service = Adau1701Ch0Band0ReadService(
        transport: _FakeTransport(handshakeComplete: false),
      );
      final result = await service.readOriginalState();
      expect(result.status, Adau1701Ch0Band0ReadStatus.transportNotReady);
    });

    test('wrong detected profile → transportNotReady', () async {
      const service = Adau1701Ch0Band0ReadService(
        transport: _FakeTransport(detectedProfile: 'DSP9999.000.00.00'),
      );
      final result = await service.readOriginalState();
      expect(result.status, Adau1701Ch0Band0ReadStatus.transportNotReady);
    });

    test('snapshot device identity mismatch → deviceIdentityMismatch',
        () async {
      final service = Adau1701Ch0Band0ReadService(
        transport: _ready(
          snapshot: _snapshot(deviceId: 'DSP9999.000.00.00'),
        ),
      );
      final result = await service.readOriginalState();
      expect(result.status, Adau1701Ch0Band0ReadStatus.deviceIdentityMismatch);
    });

    test('transport throws → rawReadFailed', () async {
      final service = Adau1701Ch0Band0ReadService(
        transport: _ready(error: StateError('serial port lost')),
      );
      final result = await service.readOriginalState();
      expect(result.status, Adau1701Ch0Band0ReadStatus.rawReadFailed);
      expect(result.message, contains('serial port lost'));
    });

    test('decoder rejects malformed payload → decodeFailed', () async {
      // Frequency 0x00 0x00 = 0 Hz, out of valid range 20..20000
      final badPayload = List<int>.filled(513, 0x00);
      final service = Adau1701Ch0Band0ReadService(
        transport: _ready(snapshot: _snapshot(payload: badPayload)),
      );
      final result = await service.readOriginalState();
      expect(result.status, Adau1701Ch0Band0ReadStatus.decodeFailed);
    });
  });

  group('evaluateOriginalStateCoverage', () {
    Adau1701Ch0Band0OriginalState state() => Adau1701Ch0Band0OriginalState(
          deviceId: _kDeviceId,
          capturedAt: DateTime.utc(2025, 1, 1),
          frequencyHz: 1800,
          gainDb: -1.0,
          q: 2.0,
          property08State: 1,
        );

    test('Frequency + Gain + Q plan with complete original state → covered',
        () {
      final coverage = evaluateOriginalStateCoverage(
        plan: const Adau1701PeqWriteFields(
          frequency: true,
          gain: true,
          q: true,
        ),
        originalState: state(),
      );
      expect(coverage.isCovered, isTrue);
      expect(coverage.missingFields, isEmpty);
    });

    test('missing one modified field (originalState null) → missingOriginalValues',
        () {
      final coverage = evaluateOriginalStateCoverage(
        plan: const Adau1701PeqWriteFields(gain: true),
        originalState: null,
      );
      expect(coverage.status,
          Adau1701OriginalStateCoverageStatus.missingOriginalValues);
      expect(coverage.missingFields, contains('gainDb'));
    });

    test(
        'unmodified property08State is not required when plan does not touch it',
        () {
      final coverage = evaluateOriginalStateCoverage(
        plan: const Adau1701PeqWriteFields(
          frequency: true,
          gain: true,
          q: true,
          // property08: false — not modified
        ),
        originalState: state(),
      );
      expect(coverage.isCovered, isTrue);
      expect(coverage.missingFields, isNot(contains('property08State')));
    });

    test(
        'property08State becomes required when plan explicitly sets property08',
        () {
      final coverage = evaluateOriginalStateCoverage(
        plan: const Adau1701PeqWriteFields(property08: true),
        originalState: null, // no read performed
      );
      expect(coverage.status,
          Adau1701OriginalStateCoverageStatus.missingOriginalValues);
      expect(coverage.missingFields, contains('property08State'));
    });

    test('property08State is covered when original state is present', () {
      final coverage = evaluateOriginalStateCoverage(
        plan: const Adau1701PeqWriteFields(property08: true),
        originalState: state(),
      );
      expect(coverage.isCovered, isTrue);
    });

    test('no fields modified → noFieldsModified', () {
      final coverage = evaluateOriginalStateCoverage(
        plan: const Adau1701PeqWriteFields(),
        originalState: null,
      );
      expect(coverage.status,
          Adau1701OriginalStateCoverageStatus.noFieldsModified);
      expect(coverage.isCovered, isFalse);
    });

    test('all fields required but no original state → all four listed missing',
        () {
      final coverage = evaluateOriginalStateCoverage(
        plan: const Adau1701PeqWriteFields(
          frequency: true,
          gain: true,
          q: true,
          property08: true,
        ),
        originalState: null,
      );
      expect(coverage.status,
          Adau1701OriginalStateCoverageStatus.missingOriginalValues);
      expect(coverage.missingFields,
          containsAll(['frequencyHz', 'gainDb', 'q', 'property08State']));
    });
  });
}
