import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_decoder.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

// ── Fixture helpers ──────────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';
const _kBlockId = 0x2202;

/// Build a 513-byte payload with only the validated offsets set.
List<int> _payload({
  required int freqLow, // offset 19
  required int freqHigh, // offset 20
  required int gainRaw, // offset 21, int8 as uint8
  // offset 22 stays 0x00 — uninterpreted
  required int qRaw, // offset 23
  required int prop08, // offset 24
}) {
  final p = List<int>.filled(513, 0x00);
  p[19] = freqLow;
  p[20] = freqHigh;
  p[21] = gainRaw;
  p[23] = qRaw;
  p[24] = prop08;
  return p;
}

RawDspStateSnapshot _snapshot(List<int> payload) => RawDspStateSnapshot(
      deviceId: _kDeviceId,
      timestamp: DateTime.utc(2025, 1, 1),
      blockId: _kBlockId,
      payload: payload,
    );

// ── Validated state fixtures ─────────────────────────────────────────────────
//
// State A (physically captured):
//   offset 19 = 0x08, offset 20 = 0x07 → 1800 Hz
//   offset 21 = 0xF6                   → -10 raw → -1.0 dB
//   offset 22 = 0x00                   (uninterpreted, not decoded)
//   offset 23 = 0x14                   → 20 raw → Q 2.0
//   offset 24 = 0x01                   → property08State 1
//
// State B (physically captured):
//   offset 19 = 0x09, offset 20 = 0x07 → 1801 Hz
//   offset 21 = 0x00                   → 0 raw → 0.0 dB
//   offset 22 = 0x00                   (uninterpreted, not decoded)
//   offset 23 = 0x1E                   → 30 raw → Q 3.0
//   offset 24 = 0x00                   → property08State 0

final _stateA = _payload(
  freqLow: 0x08,
  freqHigh: 0x07,
  gainRaw: 0xF6, // signed -10, i.e. -1.0 dB
  qRaw: 0x14, // 20 → Q 2.0
  prop08: 0x01,
);

final _stateB = _payload(
  freqLow: 0x09,
  freqHigh: 0x07,
  gainRaw: 0x00, // 0 → 0.0 dB
  qRaw: 0x1E, // 30 → Q 3.0
  prop08: 0x00,
);

void main() {
  group('Adau1701Ch0Band0Decoder — validated state fixtures', () {
    test('State A: 1800 Hz, -1.0 dB, Q 2.0, property08State 1', () {
      final result = Adau1701Ch0Band0Decoder.decode(_snapshot(_stateA));

      expect(result.frequencyHz, 1800);
      expect(result.gainDb, closeTo(-1.0, 0.001));
      expect(result.q, closeTo(2.0, 0.001));
      expect(result.property08State, 1);
    });

    test('State B: 1801 Hz, 0.0 dB, Q 3.0, property08State 0', () {
      final result = Adau1701Ch0Band0Decoder.decode(_snapshot(_stateB));

      expect(result.frequencyHz, 1801);
      expect(result.gainDb, closeTo(0.0, 0.001));
      expect(result.q, closeTo(3.0, 0.001));
      expect(result.property08State, 0);
    });
  });

  group('Adau1701Ch0Band0Decoder — fail-closed guards', () {
    test('rejects wrong device identity', () {
      final badSnapshot = RawDspStateSnapshot(
        deviceId: 'DSP9999.000.00.00',
        timestamp: DateTime.utc(2025, 1, 1),
        blockId: _kBlockId,
        payload: _stateA,
      );
      expect(
        () => Adau1701Ch0Band0Decoder.decode(badSnapshot),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects frequency below 20 Hz', () {
      final p = _payload(
        freqLow: 0x01,
        freqHigh: 0x00, // 1 Hz
        gainRaw: 0x00,
        qRaw: 0x14,
        prop08: 0x00,
      );
      expect(
        () => Adau1701Ch0Band0Decoder.decode(_snapshot(p)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects frequency above 20000 Hz', () {
      final p = _payload(
        freqLow: 0x41,
        freqHigh: 0x4E, // 0x4E41 = 20033 Hz
        gainRaw: 0x00,
        qRaw: 0x14,
        prop08: 0x00,
      );
      expect(
        () => Adau1701Ch0Band0Decoder.decode(_snapshot(p)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects gain below -6.0 dB', () {
      // -61 raw = 0xC3 (two's complement: -61)
      final p = _payload(
        freqLow: 0x08,
        freqHigh: 0x07,
        gainRaw: 0xC3, // -61 → -6.1 dB
        qRaw: 0x14,
        prop08: 0x00,
      );
      expect(
        () => Adau1701Ch0Band0Decoder.decode(_snapshot(p)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects gain above +3.0 dB', () {
      // +31 raw = 0x1F
      final p = _payload(
        freqLow: 0x08,
        freqHigh: 0x07,
        gainRaw: 0x1F, // 31 → 3.1 dB
        qRaw: 0x14,
        prop08: 0x00,
      );
      expect(
        () => Adau1701Ch0Band0Decoder.decode(_snapshot(p)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects Q below 0.3', () {
      // 2 raw = 0x02 → Q 0.2
      final p = _payload(
        freqLow: 0x08,
        freqHigh: 0x07,
        gainRaw: 0x00,
        qRaw: 0x02,
        prop08: 0x00,
      );
      expect(
        () => Adau1701Ch0Band0Decoder.decode(_snapshot(p)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects Q above 10.0', () {
      // 101 raw = 0x65 → Q 10.1
      final p = _payload(
        freqLow: 0x08,
        freqHigh: 0x07,
        gainRaw: 0x00,
        qRaw: 0x65,
        prop08: 0x00,
      );
      expect(
        () => Adau1701Ch0Band0Decoder.decode(_snapshot(p)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects property08State not equal to 0 or 1', () {
      final p = _payload(
        freqLow: 0x08,
        freqHigh: 0x07,
        gainRaw: 0x00,
        qRaw: 0x14,
        prop08: 0x02, // unseen value
      );
      expect(
        () => Adau1701Ch0Band0Decoder.decode(_snapshot(p)),
        throwsA(isA<FormatException>()),
      );
    });

    test('RawDspStateSnapshot rejects wrong payload length', () {
      expect(
        () => RawDspStateSnapshot(
          deviceId: _kDeviceId,
          timestamp: DateTime.utc(2025, 1, 1),
          blockId: _kBlockId,
          payload: List.filled(512, 0),
        ),
        throwsArgumentError,
      );
    });

    test('RawDspStateSnapshot rejects wrong block ID', () {
      expect(
        () => RawDspStateSnapshot(
          deviceId: _kDeviceId,
          timestamp: DateTime.utc(2025, 1, 1),
          blockId: 0x2201,
          payload: List.filled(513, 0),
        ),
        throwsArgumentError,
      );
    });
  });
}
