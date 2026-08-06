// ADAU1701 Full DSP State Readback Mapping — Phase 1 Tests
//
// Tests for the full state decoder infrastructure (Adau1701StateDecoder),
// the rawHexDump helper, and the per-band provenance model.
//
// Groups:
//   1. Band0 decode regression  — output matches the verified single-band decoder
//   2. 513-byte payload decode  — structure and field counts
//   3. Band 1-10 decoder output — all bands decode; provenance flags correct
//   4. Unknown mapping never marked verified — bands 1-9 stay mappingCandidate
//   5. Read-only state          — no mutations across multiple decodes
//   6. UI / rendering helpers   — status labels, hex dump format

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_decoder.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_state_decoder.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';

List<int> _buildPayload({
  int freqHz = 1800,
  double gainDb = 0.0,
  double q = 1.2,
  int property08 = 0,
}) {
  final payload = List<int>.filled(513, 0);
  // Distinct page markers so Icp5RawStateCollector accepts all 4 pages.
  payload[154] = 0x01;
  payload[308] = 0x02;
  payload[462] = 0x03;
  // Band 0 (Band 1) — capture-proven offsets 19-24.
  payload[19] = freqHz & 0xFF;
  payload[20] = (freqHz >> 8) & 0xFF;
  final gainRaw = (gainDb * 10).round();
  payload[21] = gainRaw < 0 ? gainRaw + 256 : gainRaw;
  payload[23] = (q * 10).round();
  payload[24] = property08;
  return payload;
}

RawDspStateSnapshot _buildSnapshot({
  int freqHz = 1800,
  double gainDb = 0.0,
  double q = 1.2,
  int property08 = 0,
}) =>
    RawDspStateSnapshot(
      deviceId: _kDeviceId,
      timestamp: DateTime.utc(2026, 8, 5, 12, 0, 0),
      blockId: 0x2202,
      payload: _buildPayload(
          freqHz: freqHz, gainDb: gainDb, q: q, property08: property08),
    );

// ── MiUMAX preset definition ──────────────────────────────────────────────────
//
// Representative EQ state for a MiUMAX device with 10 PEQ bands on Ch0.
// Band 0 (Band 1) values are HARDWARE-CONFIRMED via physical capture:
//   MiUMAX EQ Band1 → Freq 1800 Hz, Gain 0.0 dB, Q 1.20.
// Bands 1-9 (Band 2-10) are placed at stride-6 candidate offsets to verify
// the decoder round-trip at each position.

typedef _BandPreset = ({
  int index,
  int freqHz,
  double gainDb,
  double q,
  int property08
});

const List<_BandPreset> _miuMaxPresets = [
  (index: 0, freqHz: 1800, gainDb: 0.0, q: 1.2, property08: 0), // Band 1 — hw-confirmed
  (index: 1, freqHz: 3200, gainDb: 0.5, q: 1.0, property08: 0), // Band 2
  (index: 2, freqHz: 630, gainDb: -1.0, q: 2.0, property08: 0), // Band 3
  (index: 3, freqHz: 1250, gainDb: 1.5, q: 1.0, property08: 0), // Band 4
  (index: 4, freqHz: 2500, gainDb: 0.0, q: 0.7, property08: 0), // Band 5
  (index: 5, freqHz: 5000, gainDb: -2.0, q: 1.5, property08: 0), // Band 6
  (index: 6, freqHz: 8000, gainDb: 0.5, q: 1.0, property08: 0), // Band 7
  (index: 7, freqHz: 12500, gainDb: 0.0, q: 1.0, property08: 0), // Band 8
  (index: 8, freqHz: 315, gainDb: -0.5, q: 2.0, property08: 0), // Band 9
  (index: 9, freqHz: 16000, gainDb: 1.0, q: 0.8, property08: 0), // Band 10
];

// Builds a 513-byte payload with the MiUMAX preset values at each band's
// stride-6 position: base = 19 + 6 * bandIndex.
List<int> _buildMiUMaxPresetPayload() {
  final payload = List<int>.filled(513, 0);
  payload[154] = 0x01; // page 1 marker — distinct for duplicate detection
  payload[308] = 0x02; // page 2 marker
  payload[462] = 0x03; // page 3 marker
  for (final band in _miuMaxPresets) {
    final base = 19 + 6 * band.index;
    payload[base] = band.freqHz & 0xFF;
    payload[base + 1] = (band.freqHz >> 8) & 0xFF;
    final gainRaw = (band.gainDb * 10).round();
    payload[base + 2] = gainRaw < 0 ? gainRaw + 256 : gainRaw;
    // base+3 is the padding byte (left as 0)
    payload[base + 4] = (band.q * 10).round();
    payload[base + 5] = band.property08;
  }
  return payload;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. Band0 decode regression ───────────────────────────────────────────

  group('Band0 decode regression', () {
    test('frequencyHz matches verified single-band decoder', () {
      final snap = _buildSnapshot(freqHz: 1800);
      final legacy = Adau1701Ch0Band0Decoder.decode(snap);
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.outputs[0].peqBands[0].frequencyHz, equals(legacy.frequencyHz));
    });

    test('gainDb matches verified single-band decoder', () {
      final snap = _buildSnapshot(gainDb: 0.0);
      final legacy = Adau1701Ch0Band0Decoder.decode(snap);
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.outputs[0].peqBands[0].gainDb, equals(legacy.gainDb));
    });

    test('Q matches verified single-band decoder', () {
      final snap = _buildSnapshot(q: 1.2);
      final legacy = Adau1701Ch0Band0Decoder.decode(snap);
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.outputs[0].peqBands[0].q,
          closeTo(legacy.q, 0.001));
    });

    test('property08 matches verified single-band decoder', () {
      final snap = _buildSnapshot(property08: 1);
      final legacy = Adau1701Ch0Band0Decoder.decode(snap);
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.outputs[0].peqBands[0].property08,
          equals(legacy.property08State));
    });

    test('Band0 verificationStatus is verified', () {
      final snap = _buildSnapshot();
      final full = Adau1701StateDecoder.decode(snap);
      expect(
        full.outputs[0].peqBands[0].verificationStatus,
        equals(PeqBandVerificationStatus.verified),
      );
    });

    test('Band0 withinVerifiedRanges is true for valid values', () {
      final snap = _buildSnapshot(freqHz: 1800, gainDb: 0.0, q: 1.2);
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.outputs[0].peqBands[0].withinVerifiedRanges, isTrue);
    });
  });

  // ── 2. 513-byte payload decode ───────────────────────────────────────────

  group('513-byte payload decode', () {
    test('outputs list has exactly 4 entries (Outputs 1-4)', () {
      final snap = _buildSnapshot();
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.outputs.length, equals(4));
    });

    test('Output 1 has outputIndex 0', () {
      final snap = _buildSnapshot();
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.outputs[0].outputIndex, equals(0));
    });

    test('peqBands list has exactly 10 entries (Bands 1-10)', () {
      final snap = _buildSnapshot();
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.outputs[0].peqBands.length, equals(10));
    });

    test('rawSnapshot is preserved without mutation', () {
      final snap = _buildSnapshot(freqHz: 1800);
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.rawSnapshot.payload.length, equals(513));
      expect(full.rawSnapshot.deviceId, equals(_kDeviceId));
    });

    test('decodedAt is populated', () {
      final snap = _buildSnapshot();
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final full = Adau1701StateDecoder.decode(snap);
      expect(full.decodedAt.isAfter(before), isTrue);
    });

    test('bandIndex values run 0..9 in order', () {
      final snap = _buildSnapshot();
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      for (var i = 0; i < 10; i++) {
        expect(bands[i].bandIndex, equals(i));
      }
    });
  });

  // ── 3. Band 1-10 decoder output ─────────────────────────────────────────

  group('Band 1-10 decoder output', () {
    test('all 10 bands decode without throwing', () {
      final snap = _buildSnapshot();
      expect(() => Adau1701StateDecoder.decode(snap), returnsNormally);
    });

    test('Band 1 (index 0) is capture-proven / verified', () {
      final snap = _buildSnapshot(freqHz: 1800, gainDb: 0.0, q: 1.2);
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      expect(
        bands[0].verificationStatus,
        equals(PeqBandVerificationStatus.verified),
      );
    });

    test('Bands 2-10 (index 1-9) are mappingCandidate', () {
      final snap = _buildSnapshot();
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      for (var i = 1; i < 10; i++) {
        expect(
          bands[i].verificationStatus,
          equals(PeqBandVerificationStatus.mappingCandidate),
          reason: 'Band ${i + 1} (index $i) must be mappingCandidate',
        );
      }
    });

    test('Band 1 withinVerifiedRanges is true for valid payload', () {
      final snap = _buildSnapshot(freqHz: 1800, gainDb: 0.0, q: 1.2);
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      expect(bands[0].withinVerifiedRanges, isTrue);
    });

    test('Bands 2-10 with zero payload have withinVerifiedRanges = false', () {
      // Zero frequencyHz (0) is < 20 Hz, outside the verified range.
      final snap = _buildSnapshot();
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      for (var i = 1; i < 10; i++) {
        // The default zero payload makes freq=0, which is out of range.
        // withinVerifiedRanges must be false — confirms out-of-range is
        // reported as a flag, not thrown.
        expect(
          bands[i].withinVerifiedRanges,
          isFalse,
          reason: 'Band ${i + 1} zero-payload should be withinVerifiedRanges=false',
        );
      }
    });
  });

  // ── 4. Unknown mapping never marked verified ─────────────────────────────

  group('Unknown mapping never marked verified', () {
    test('only Band 1 (index 0) may be verified', () {
      final snap = _buildSnapshot();
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      final verifiedBands = bands
          .where((b) => b.verificationStatus == PeqBandVerificationStatus.verified)
          .map((b) => b.bandIndex)
          .toList();
      expect(verifiedBands, equals([0]),
          reason: 'Only bandIndex 0 (Band 1) should be verified');
    });

    test('PeqBandVerificationStatus enum has exactly three values', () {
      expect(PeqBandVerificationStatus.values.length, equals(3));
      expect(PeqBandVerificationStatus.values,
          containsAll([
            PeqBandVerificationStatus.verified,
            PeqBandVerificationStatus.mappingCandidate,
            PeqBandVerificationStatus.channelLayoutCandidate,
          ]));
    });

    test('mappingCandidate is never equal to verified', () {
      expect(
        PeqBandVerificationStatus.mappingCandidate,
        isNot(equals(PeqBandVerificationStatus.verified)),
      );
    });

    test('no band 1-9 has its provenance upgraded by decode', () {
      // Even after a "reasonable-looking" payload for band 1+ offsets,
      // the verificationStatus for bands 1-9 must remain mappingCandidate.
      final payload = _buildPayload(freqHz: 1800, gainDb: 0.0, q: 1.2);
      // Inject Band 2 values at stride-6 offset (25-30) so they're in-range.
      payload[25] = 0xE8; // 1000 Hz lo
      payload[26] = 0x03; // 1000 Hz hi
      payload[27] = 0x1E; // +3.0 dB
      payload[29] = 0x0A; // Q = 1.0
      payload[30] = 0x00; // property08 = 0
      final snap = RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: payload,
      );
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      expect(
        bands[1].verificationStatus,
        equals(PeqBandVerificationStatus.mappingCandidate),
        reason: 'In-range values must not upgrade mappingCandidate to verified',
      );
    });
  });

  // ── 5. Read-only state ───────────────────────────────────────────────────

  group('Read-only state', () {
    test('two decodes of the same snapshot return identical band values', () {
      final snap = _buildSnapshot(freqHz: 1800, gainDb: 0.0, q: 1.2);
      final r1 = Adau1701StateDecoder.decode(snap);
      final r2 = Adau1701StateDecoder.decode(snap);
      expect(r1.outputs[0].peqBands[0].frequencyHz,
          equals(r2.outputs[0].peqBands[0].frequencyHz));
      expect(r1.outputs[0].peqBands[0].gainDb,
          equals(r2.outputs[0].peqBands[0].gainDb));
    });

    test('decode does not mutate original snapshot payload', () {
      final snap = _buildSnapshot(freqHz: 1800);
      final originalByte19 = snap.payload[19];
      Adau1701StateDecoder.decode(snap);
      expect(snap.payload[19], equals(originalByte19),
          reason: 'Decode must not mutate the snapshot payload');
    });

    test('peqBands list is unmodifiable', () {
      final snap = _buildSnapshot();
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      expect(
        () => (bands as dynamic).add(null),
        throwsA(anything),
        reason: 'peqBands must be unmodifiable',
      );
    });

    test('outputs list is unmodifiable', () {
      final snap = _buildSnapshot();
      final outputs = Adau1701StateDecoder.decode(snap).outputs;
      expect(
        () => (outputs as dynamic).add(null),
        throwsA(anything),
        reason: 'outputs must be unmodifiable',
      );
    });
  });

  // ── 6. UI / rendering helpers ────────────────────────────────────────────

  group('UI and rendering helpers', () {
    test('rawHexDump produces lines starting with 0x offset prefix', () {
      final snap = _buildSnapshot();
      final dump = snap.rawHexDump();
      final lines = dump.split('\n');
      expect(lines.first, startsWith('0x000:'),
          reason: 'First line must start with 0x000:');
      expect(lines.last, startsWith('0x'),
          reason: 'Last line must start with hex offset');
    });

    test('rawHexDump covers all 513 bytes (33 rows of 16, last row 1 byte)', () {
      // 513 bytes: 32 full rows of 16 + 1 byte in the last row = 33 rows.
      final snap = _buildSnapshot();
      final dump = snap.rawHexDump();
      final lines = dump.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.length, equals(33));
    });

    test('rawHexDump last row offset is 0x200 (byte 512)', () {
      final snap = _buildSnapshot();
      final dump = snap.rawHexDump();
      final lines = dump.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.last, startsWith('0x200:'));
    });

    test('rawHexDump encodes payload[19] (freqLo of Band1) correctly', () {
      // 1800 Hz lo byte = 0x08 (1800 = 0x0708, lo = 0x08)
      final snap = _buildSnapshot(freqHz: 1800);
      final dump = snap.rawHexDump();
      // Offset 19 is in the second row (0x010: bytes 16-31), at position 4.
      final row = dump.split('\n').firstWhere((l) => l.startsWith('0x010:'));
      // freqLo at offset 19: row position = 19 - 16 = 3 (0-indexed byte 3)
      // Row format: "0x010: b0 b1 b2 b3 b4 b5 ..."
      // byte 19 is the 4th byte in the row (index 3 → 0-based)
      expect(row, contains('08'),
          reason: 'Offset 19 (1800 Hz lo = 0x08) should appear in 0x010: row');
    });

    test('only Band 1 (index 0) renders the Verified badge', () {
      // The UI shows a "Verified" badge only for capture-proven bands.
      // Bands 2-10 show no label badge — live read values are displayed directly.
      final snap = _buildSnapshot();
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      final showsVerifiedBadge = (PeqBandState b) =>
          b.verificationStatus == PeqBandVerificationStatus.verified;
      expect(showsVerifiedBadge(bands[0]), isTrue,
          reason: 'Band 1 (index 0) must show the Verified badge');
      for (var i = 1; i < 10; i++) {
        expect(showsVerifiedBadge(bands[i]), isFalse,
            reason: 'Band ${i + 1} (index $i) must not show the Verified badge');
      }
    });

    test('band display index is bandIndex + 1 (1-based)', () {
      final snap = _buildSnapshot();
      final bands = Adau1701StateDecoder.decode(snap).outputs[0].peqBands;
      for (var i = 0; i < 10; i++) {
        expect(bands[i].bandIndex + 1, equals(i + 1));
      }
    });
  });

  // ── 7. MiUMAX preset vs decoder round-trip ──────────────────────────────

  group('MiUMAX preset vs decoder round-trip', () {
    late Adau1701StateSnapshot decoded;

    setUp(() {
      final snap = RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5, 12, 0, 0),
        blockId: 0x2202,
        payload: _buildMiUMaxPresetPayload(),
      );
      decoded = Adau1701StateDecoder.decode(snap);
    });

    test('Band 1 frequency matches hardware-confirmed MiUMAX value (1800 Hz)',
        () {
      expect(decoded.outputs[0].peqBands[0].frequencyHz, equals(1800));
    });

    test('Band 1 gain matches hardware-confirmed MiUMAX value (0.0 dB)', () {
      expect(decoded.outputs[0].peqBands[0].gainDb, equals(0.0));
    });

    test('Band 1 Q matches hardware-confirmed MiUMAX value (1.20)', () {
      expect(decoded.outputs[0].peqBands[0].q, closeTo(1.2, 0.01));
    });

    test('all 10 preset frequencies decode round-trip correctly', () {
      final bands = decoded.outputs[0].peqBands;
      for (final preset in _miuMaxPresets) {
        expect(
          bands[preset.index].frequencyHz,
          equals(preset.freqHz),
          reason:
              'Band ${preset.index + 1} freq: expected ${preset.freqHz} Hz',
        );
      }
    });

    test('all 10 preset gains decode round-trip correctly', () {
      final bands = decoded.outputs[0].peqBands;
      for (final preset in _miuMaxPresets) {
        expect(
          bands[preset.index].gainDb,
          closeTo(preset.gainDb, 0.05),
          reason:
              'Band ${preset.index + 1} gain: expected ${preset.gainDb} dB',
        );
      }
    });

    test('all 10 preset Q values decode round-trip correctly', () {
      final bands = decoded.outputs[0].peqBands;
      for (final preset in _miuMaxPresets) {
        expect(
          bands[preset.index].q,
          closeTo(preset.q, 0.05),
          reason: 'Band ${preset.index + 1} Q: expected ${preset.q}',
        );
      }
    });

    test('stride-6 offsets do not overlap — each band decodes independently',
        () {
      // Modifying Band N's bytes must not affect Band N+1.
      final payload = _buildMiUMaxPresetPayload();
      // Corrupt Band 2 (index 1) freqLo byte at offset 25 → should not affect Band 3 (index 2, offset 31).
      payload[25] = 0xFF;
      final snap2 = RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: payload,
      );
      final d2 = Adau1701StateDecoder.decode(snap2);
      // Band 3 (index 2) must still decode to its preset freq (630 Hz).
      expect(d2.outputs[0].peqBands[2].frequencyHz, equals(630),
          reason: 'Corrupting band 2 offset must not affect band 3');
    });

    test('Band 1 withinVerifiedRanges is true for MiUMAX preset payload', () {
      expect(decoded.outputs[0].peqBands[0].withinVerifiedRanges, isTrue);
    });

    test('all 10 bands withinVerifiedRanges with valid preset values', () {
      final bands = decoded.outputs[0].peqBands;
      for (final band in bands) {
        expect(
          band.withinVerifiedRanges,
          isTrue,
          reason:
              'Band ${band.bandIndex + 1} preset values must be within verified ranges',
        );
      }
    });
  });
}
