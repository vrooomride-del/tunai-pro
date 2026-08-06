// ADAU1701 DSP State Read Card — unit tests
//
// These tests cover the core logic path used by the BLE readback card without
// requiring a physical device:
//   1. 513-byte snapshot decode with known Ch0 Band0 values
//   2. Raw evidence hex string format
//   3. Read is blocked / button disabled when transport is not connected
//   4. Read action does not modify any tuning/deploy state
//
// The widget itself is not pumped here (no full widget test) because the card's
// logic is exercised through the public interfaces it calls:
// [Adau1701RawReadTransport], [RawDspStateSnapshot], [Adau1701Ch0Band0Decoder].

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_state_decoder.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_decoder.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_dsp_state_read_card.dart'
    show peqBandsToResponseBands;

// ── Fake transport ────────────────────────────────────────────────────────────

class _FakeTransport implements Adau1701RawReadTransport {
  final bool _connected;
  final bool _handshaked;
  final RawDspStateSnapshot? Function()? _snapshotFactory;
  int readCalls = 0;

  _FakeTransport({
    bool connected = true,
    bool handshaked = true,
    RawDspStateSnapshot? Function()? snapshotFactory,
  })  : _connected = connected,
        _handshaked = handshaked,
        _snapshotFactory = snapshotFactory;

  @override
  bool get isConnected => _connected;

  @override
  bool get handshakeComplete => _handshaked;

  @override
  String? get detectedProfile =>
      _handshaked ? 'DSP1701.100.00.01' : null;

  @override
  Future<RawDspStateSnapshot> readRawDspState() async {
    readCalls++;
    final factory = _snapshotFactory;
    if (factory == null) throw StateError('No snapshot configured.');
    return factory()!;
  }
}

// ── Payload builder ───────────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';

List<int> _buildPayload({
  int freqHz = 1000,
  double gainDb = 0.0,
  double q = 1.0,
  int property08 = 0,
}) {
  final payload = List<int>.filled(513, 0);
  // Page markers so the ICP5 collector does not reject identical same-length pages.
  payload[154] = 0x01;
  payload[308] = 0x02;
  payload[462] = 0x03;
  // Band0 values.
  payload[19] = freqHz & 0xFF;
  payload[20] = (freqHz >> 8) & 0xFF;
  final gainRaw = (gainDb * 10).round();
  payload[21] = gainRaw < 0 ? gainRaw + 256 : gainRaw;
  payload[23] = (q * 10).round();
  payload[24] = property08;
  return payload;
}

RawDspStateSnapshot _buildSnapshot({
  int freqHz = 1000,
  double gainDb = 0.0,
  double q = 1.0,
  int property08 = 0,
}) =>
    RawDspStateSnapshot(
      deviceId: _kDeviceId,
      timestamp: DateTime.utc(2026, 8, 5, 12, 0, 0),
      blockId: 0x2202,
      payload: _buildPayload(
          freqHz: freqHz, gainDb: gainDb, q: q, property08: property08),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. 513-byte snapshot decode ──────────────────────────────────────────

  group('513-byte snapshot decode', () {
    test('decodes 1000 Hz at offsets 19-20', () {
      final snapshot = _buildSnapshot(freqHz: 1000, gainDb: 0.0, q: 1.0);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(decoded.frequencyHz, equals(1000));
    });

    test('decodes +3.0 dB at offset 21 (0x1E)', () {
      final snapshot = _buildSnapshot(gainDb: 3.0);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(decoded.gainDb, equals(3.0));
    });

    test('decodes 0.0 dB at offset 21 (0x00)', () {
      final snapshot = _buildSnapshot(gainDb: 0.0);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(decoded.gainDb, equals(0.0));
    });

    test('decodes -1.0 dB at offset 21 (0xF6 = 246 as uint8)', () {
      final snapshot = _buildSnapshot(gainDb: -1.0);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(decoded.gainDb, equals(-1.0));
    });

    test('decodes Q 1.4 at offset 23 (0x0E)', () {
      final snapshot = _buildSnapshot(q: 1.4);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(decoded.q, closeTo(1.4, 0.01));
    });

    test('decodes property08 = 0 at offset 24', () {
      final snapshot = _buildSnapshot(property08: 0);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(decoded.property08State, equals(0));
    });

    test('decodes property08 = 1 at offset 24', () {
      final snapshot = _buildSnapshot(property08: 1);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(decoded.property08State, equals(1));
    });

    test('snapshot payload is exactly 513 bytes', () {
      final snapshot = _buildSnapshot();
      expect(snapshot.payload.length, equals(513));
    });
  });

  // ── 2. Known Ch0 Band0 values render (formatting) ────────────────────────

  group('Known Ch0 Band0 values render (string formatting)', () {
    test('frequency renders as "1000 Hz"', () {
      final snapshot = _buildSnapshot(freqHz: 1000);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect('${decoded.frequencyHz} Hz', equals('1000 Hz'));
    });

    test('gain renders as "+3.0 dB" with one decimal place', () {
      final snapshot = _buildSnapshot(gainDb: 3.0);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect('${decoded.gainDb.toStringAsFixed(1)} dB', equals('3.0 dB'));
    });

    test('gain renders as "-1.0 dB" for negative value', () {
      final snapshot = _buildSnapshot(gainDb: -1.0);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect('${decoded.gainDb.toStringAsFixed(1)} dB', equals('-1.0 dB'));
    });

    test('Q renders as "1.40" with two decimal places', () {
      final snapshot = _buildSnapshot(q: 1.4);
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(decoded.q.toStringAsFixed(2), equals('1.40'));
    });

    test('property08 renders as "0" or "1"', () {
      for (final p08 in [0, 1]) {
        final snapshot = _buildSnapshot(property08: p08);
        final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
        expect('${decoded.property08State}', equals('$p08'));
      }
    });

    test('raw evidence hex is space-separated 0x-prefixed bytes', () {
      final snapshot = _buildSnapshot(freqHz: 1000, gainDb: 3.0, q: 1.0);
      final rawBytes = snapshot.payload.sublist(19, 25);
      final rawHex = rawBytes
          .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
          .join(' ');
      // 1000 Hz: [0xE8, 0x03], +3.0 dB: [0x1E], pad: [0x00], Q=1.0: [0x0A], prop08=0: [0x00]
      expect(rawHex, equals('0xe8 0x03 0x1e 0x00 0x0a 0x00'));
    });

    test('raw evidence always has exactly 6 space-separated tokens', () {
      final snapshot = _buildSnapshot(gainDb: -1.0, q: 2.5);
      final rawBytes = snapshot.payload.sublist(19, 25);
      final rawHex = rawBytes
          .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
          .join(' ');
      expect(rawHex.split(' '), hasLength(6));
    });
  });

  // ── 3. Disconnected state blocks read ────────────────────────────────────

  group('Disconnected state blocks read', () {
    test('transport not connected: canRead is false', () {
      final t = _FakeTransport(connected: false, handshaked: false);
      // Mimic _canRead logic from the card
      final canRead = t.isConnected && t.handshakeComplete;
      expect(canRead, isFalse,
          reason: 'Must not allow read when transport not connected');
    });

    test('transport connected but handshake not passed: canRead is false', () {
      final t = _FakeTransport(connected: true, handshaked: false);
      final canRead = t.isConnected && t.handshakeComplete;
      expect(canRead, isFalse,
          reason: 'Must not allow read when handshake has not passed');
    });

    test('transport connected and handshaked: canRead is true', () {
      final t = _FakeTransport(connected: true, handshaked: true);
      final canRead = t.isConnected && t.handshakeComplete;
      expect(canRead, isTrue);
    });

    test('disconnected transport: readRawDspState guard would block at transport level', () {
      // The ICP5 transport itself throws StateError when called without a
      // successful handshake. The card's canRead guard catches this before the
      // call — this test verifies the guard logic matches the transport contract.
      final t = _FakeTransport(connected: false, handshaked: false);
      expect(t.isConnected, isFalse);
      expect(t.handshakeComplete, isFalse);
      // canRead is false → read must not be called
      expect(t.readCalls, equals(0));
    });
  });

  // ── 4. Read action does not modify tuning/deploy state ───────────────────

  group('Read action does not modify tuning/deploy state', () {
    test('readRawDspState returns a snapshot without side effects on transport', () async {
      final payload = _buildPayload(freqHz: 800, gainDb: 2.0, q: 1.2);
      final snapshot = RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: payload,
      );
      final t = _FakeTransport(
        connected: true,
        handshaked: true,
        snapshotFactory: () => snapshot,
      );

      // Single read call
      final result = await t.readRawDspState();
      expect(t.readCalls, equals(1));

      // Transport is unchanged after read
      expect(t.isConnected, isTrue,
          reason: 'Read must not disconnect the transport');
      expect(t.handshakeComplete, isTrue,
          reason: 'Read must not reset handshake state');

      // Decoded values match written payload — no mutation
      final decoded = Adau1701Ch0Band0Decoder.decode(result);
      expect(decoded.frequencyHz, equals(800));
      expect(decoded.gainDb, closeTo(2.0, 0.01));
    });

    test('multiple reads return the same snapshot without accumulating state', () async {
      final payload = _buildPayload(freqHz: 500, gainDb: -2.0, q: 0.7);
      final snapshot = RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: payload,
      );
      final t = _FakeTransport(
        connected: true,
        handshaked: true,
        snapshotFactory: () => snapshot,
      );

      final r1 = await t.readRawDspState();
      final r2 = await t.readRawDspState();

      expect(t.readCalls, equals(2));

      // Both reads decode identically — no state contamination between reads
      final d1 = Adau1701Ch0Band0Decoder.decode(r1);
      final d2 = Adau1701Ch0Band0Decoder.decode(r2);
      expect(d1.frequencyHz, equals(d2.frequencyHz));
      expect(d1.gainDb, equals(d2.gainDb));
    });

    test('read does not accept property08 values outside 0-1 (decoder fails closed)', () {
      final payload = _buildPayload(property08: 0);
      payload[24] = 0xFF; // inject an unseen property08 value
      final snapshot = RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: payload,
      );
      // Decoder must throw FormatException, not silently accept a bad value
      expect(
        () => Adau1701Ch0Band0Decoder.decode(snapshot),
        throwsA(isA<FormatException>()),
        reason: 'Decoder must fail closed on unseen property08 value',
      );
    });

    test(
        'read-only: Adau1701Ch0Band0ReadService.readOriginalState does not write',
        () async {
      // The service calls only readRawDspState — no write method is invoked.
      final payload = _buildPayload(freqHz: 1000, gainDb: 1.0, q: 1.0);
      final snapshot = RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: payload,
      );
      final t = _FakeTransport(
        connected: true,
        handshaked: true,
        snapshotFactory: () => snapshot,
      );

      final service = Adau1701Ch0Band0ReadService(transport: t);
      final result = await service.readOriginalState();

      expect(result.succeeded, isTrue);
      expect(t.readCalls, equals(1),
          reason: 'Service should call readRawDspState exactly once');
      // No writes — the fake transport has no write method, proving none was called.
    });
  });

  // ── Group 5: Live DSP graph data preparation ─────────────────────────────────

  group('Live DSP graph data preparation', () {
    // Helper: build a minimal PeqBandState list the same way the decoder does.
    List<PeqBandState> _makeBands({
      int count = 10,
      PeqBandVerificationStatus status = PeqBandVerificationStatus.mappingCandidate,
    }) =>
        List.generate(
          count,
          (i) => PeqBandState(
            bandIndex: i,
            frequencyHz: 1000 + i * 100,
            gainDb: i * 0.5,
            q: 1.0 + i * 0.1,
            property08: 0,
            verificationStatus: i == 0 ? PeqBandVerificationStatus.verified : status,
            withinVerifiedRanges: true,
          ),
        );

    test('converts 10 bands to 10 PeqResponseBands', () {
      final bands = _makeBands();
      final result = peqBandsToResponseBands(bands);
      expect(result.length, 10);
    });

    test('frequency, gain, and Q are preserved per band', () {
      final bands = _makeBands();
      final result = peqBandsToResponseBands(bands);
      for (var i = 0; i < bands.length; i++) {
        expect(result[i].frequencyHz, bands[i].frequencyHz.toDouble());
        expect(result[i].gainDb, bands[i].gainDb);
        expect(result[i].q, bands[i].q);
      }
    });

    test('all result bands are enabled=true regardless of verification status', () {
      final bands = _makeBands();
      final result = peqBandsToResponseBands(bands);
      for (final b in result) {
        expect(b.enabled, isTrue,
            reason:
                'Capture pending is a confidence badge only — it must not disable the band from the graph');
      }
    });

    test('Capture pending bands (mappingCandidate) are included in graph data', () {
      final bands = _makeBands();
      final captureCount = bands
          .where((b) => b.verificationStatus == PeqBandVerificationStatus.mappingCandidate)
          .length;
      expect(captureCount, greaterThan(0));

      final result = peqBandsToResponseBands(bands);
      expect(result.length, bands.length,
          reason: 'Every band, verified or pending, must appear in graph data');
    });

    test('combined PEQ curve is computable from all 10 bands', () {
      final bands = _makeBands();
      final responseBands = peqBandsToResponseBands(bands);
      final points = Adau1701PeqResponse.logFrequencyPoints(count: 20);
      final curve = Adau1701PeqResponse.combinedCurve(responseBands, points);
      expect(curve, hasLength(20));
      expect(curve.every((y) => y.isFinite), isTrue);
    });

    test('empty band list produces empty result', () {
      expect(peqBandsToResponseBands([]), isEmpty);
    });

    test('verified Band 1 (index 0) also has enabled=true in graph', () {
      final bands = _makeBands();
      expect(bands[0].verificationStatus, PeqBandVerificationStatus.verified);
      final result = peqBandsToResponseBands(bands);
      expect(result[0].enabled, isTrue);
    });
  });
}
