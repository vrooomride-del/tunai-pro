// Tests for the ADAU1701 ICP5 arbitrary-value write codec methods.
// These use the confirmed parameter-ID encoding (0x18 for PEQ gain,
// 0x15 for filter frequency) but allow any value within the hardware-
// validated range instead of restricting to capture-proven pairs.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';

void main() {
  // ── Frame envelope helper ────────────────────────────────────────────────
  bool validEnvelope(List<int> frame) =>
      Icp5FrameCodec.hasValidEnvelope(frame);

  // ── PEQ gain write ───────────────────────────────────────────────────────

  group('buildPeqGainWriteArbitrary', () {
    test('builds valid frame for gain -1.0 dB on channel 0', () {
      final frame = Icp5FrameCodec.buildPeqGainWriteArbitrary(0, -1.0);
      expect(validEnvelope(frame), isTrue);
      // Parameter ID 0x00000018 at bytes 3-6
      expect(frame[3], 0x00);
      expect(frame[4], 0x00);
      expect(frame[5], 0x00);
      expect(frame[6], 0x18);
      // Payload: [channel=0, 0x01, 0x00, tenths=(-10 & 0xFF)=246]
      expect(frame[7], 0x00); // channel
      expect(frame[8], 0x01);
      expect(frame[9], 0x00);
      expect(frame[10], 246); // (-1.0 * 10).round() & 0xFF = -10 & 0xFF = 246
    });

    test('builds valid frame for gain +3.0 dB on channel 1', () {
      final frame = Icp5FrameCodec.buildPeqGainWriteArbitrary(1, 3.0);
      expect(validEnvelope(frame), isTrue);
      expect(frame[7], 0x01); // channel 1
      expect(frame[10], 30);  // 3.0 * 10 = 30
    });

    test('builds valid frame for gain -6.0 dB (lower bound)', () {
      final frame = Icp5FrameCodec.buildPeqGainWriteArbitrary(0, -6.0);
      expect(validEnvelope(frame), isTrue);
      expect(frame[10], 196); // (-6.0 * 10).round() & 0xFF = -60 & 0xFF = 196
    });

    test('builds valid frame for gain 0.0 dB', () {
      final frame = Icp5FrameCodec.buildPeqGainWriteArbitrary(2, 0.0);
      expect(validEnvelope(frame), isTrue);
      expect(frame[10], 0);
    });

    test('ACK parser accepts parameter ID 0x18', () {
      // Synthesise a valid ACK frame for parameter 0x18
      final ack = [
        0x55, 0x07, 0xE1,
        0x00, 0x00, 0x00, 0x18,
        0x00, // status = success
      ];
      // Append checksum
      final cs =
          Icp5FrameCodec.checksum(ack.take(ack.length));
      final full = [...ack, cs];
      expect(Icp5FrameCodec.parsePeqGainAck(full), isTrue);
    });

    test('rejects gain above +3.0 dB', () {
      expect(
        () => Icp5FrameCodec.buildPeqGainWriteArbitrary(0, 3.1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects gain below -6.0 dB', () {
      expect(
        () => Icp5FrameCodec.buildPeqGainWriteArbitrary(0, -6.1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects invalid channel', () {
      expect(
        () => Icp5FrameCodec.buildPeqGainWriteArbitrary(4, 0.0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── Filter frequency write ───────────────────────────────────────────────

  group('buildFilterFrequencyWriteArbitrary', () {
    test('builds valid frame for 2000 Hz on channel 0', () {
      final frame =
          Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(0, 2000);
      expect(validEnvelope(frame), isTrue);
      // Parameter ID 0x00000015 at bytes 3-6
      expect(frame[3], 0x00);
      expect(frame[4], 0x00);
      expect(frame[5], 0x00);
      expect(frame[6], 0x15);
      // Payload: [channel=0, 0x02, 0x00, 2000 & 0xFF, (2000 >> 8) & 0xFF]
      expect(frame[7], 0x00); // channel
      expect(frame[8], 0x02);
      expect(frame[9], 0x00);
      expect(frame[10], 2000 & 0xFF);       // 0xD0
      expect(frame[11], (2000 >> 8) & 0xFF); // 0x07
    });

    test('builds valid frame for 20 Hz (lower bound)', () {
      final frame =
          Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(0, 20);
      expect(validEnvelope(frame), isTrue);
      expect(frame[10], 20 & 0xFF);
      expect(frame[11], (20 >> 8) & 0xFF);
    });

    test('builds valid frame for 20000 Hz (upper bound)', () {
      final frame =
          Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(0, 20000);
      expect(validEnvelope(frame), isTrue);
      expect(frame[10], 20000 & 0xFF);      // 0x20
      expect(frame[11], (20000 >> 8) & 0xFF); // 0x4E
    });

    test('builds valid frame for 100 Hz on channel 2', () {
      final frame =
          Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(2, 100);
      expect(validEnvelope(frame), isTrue);
      expect(frame[7], 0x02); // channel 2
      expect(frame[10], 100);
      expect(frame[11], 0);
    });

    test('ACK parser accepts parameter ID 0x15', () {
      final ack = [
        0x55, 0x07, 0xE1,
        0x00, 0x00, 0x00, 0x15,
        0x00,
      ];
      final cs = Icp5FrameCodec.checksum(ack.take(ack.length));
      final full = [...ack, cs];
      expect(Icp5FrameCodec.parseFilterFrequencyAck(full), isTrue);
    });

    test('rejects frequency below 20 Hz', () {
      expect(
        () => Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(0, 19),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects frequency above 20000 Hz', () {
      expect(
        () => Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(0, 20001),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects invalid channel', () {
      expect(
        () => Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(-1, 1000),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── Q write (adopted-from-Consumer, NOT capture-proven) ──────────────────

  group('buildPeqQWriteArbitrary (adopted-from-Consumer, unverified)', () {
    test('builds frame: param 0x18, property 0x00, Q 2.0 on channel 0', () {
      final frame = Icp5FrameCodec.buildPeqQWriteArbitrary(0, 2.0);
      expect(validEnvelope(frame), isTrue);
      // Parameter ID 0x00000018 at bytes 3-6 (same 0x18 as gain).
      expect(frame.sublist(3, 7), [0x00, 0x00, 0x00, 0x18]);
      // Payload: [channel=0, property=0x00 (Q), 0x00, tenths=(2.0*10)=20].
      expect(frame[7], 0x00); // channel
      expect(frame[8], 0x00); // Q property (gain uses 0x01, freq(consumer) 0x02)
      expect(frame[9], 0x00);
      expect(frame[10], 20);
      // Full expected packet incl. checksum.
      const base = [0x55, 0x0A, 0x1C, 0x00, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00,
        20];
      expect(frame, [...base, Icp5FrameCodec.checksum(base)]);
    });

    test('differs from gain only in the property byte', () {
      final q = Icp5FrameCodec.buildPeqQWriteArbitrary(0, 2.0);
      final gain = Icp5FrameCodec.buildPeqGainWriteArbitrary(0, 2.0);
      expect(q[8], 0x00); // Q property
      expect(gain[8], 0x01); // gain property
      // Same parameter id, same channel/band/value bytes.
      expect(q.sublist(3, 7), gain.sublist(3, 7));
      expect(q[7], gain[7]); // channel
      expect(q[10], gain[10]); // tenths
    });

    test('encodes lower and upper Q bounds', () {
      expect(Icp5FrameCodec.buildPeqQWriteArbitrary(0, 0.3)[10], 3);
      expect(Icp5FrameCodec.buildPeqQWriteArbitrary(0, 10.0)[10], 100);
    });

    test('ACK parser accepts parameter ID 0x18', () {
      const ack = [0x55, 0x07, 0xE1, 0x00, 0x00, 0x00, 0x18, 0x00];
      final full = [...ack, Icp5FrameCodec.checksum(ack)];
      expect(Icp5FrameCodec.parsePeqQAck(full), isTrue);
    });

    test('rejects Q below 0.3 and above 10.0', () {
      expect(() => Icp5FrameCodec.buildPeqQWriteArbitrary(0, 0.29),
          throwsA(isA<ArgumentError>()));
      expect(() => Icp5FrameCodec.buildPeqQWriteArbitrary(0, 10.1),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects invalid channel', () {
      expect(() => Icp5FrameCodec.buildPeqQWriteArbitrary(4, 2.0),
          throwsA(isA<ArgumentError>()));
    });
  });

  // ── Multi-band (Band 1..10) generalization ───────────────────────────────
  // Band index occupies payload byte 2 = frame index 9. Band 0 (Band 1) output
  // must be byte-identical to the pre-multiband build; bands 1..9 set index 9.

  group('multi-band band index encoding', () {
    test('gain band 0 is unchanged and matches default (no band arg)', () {
      final def = Icp5FrameCodec.buildPeqGainWriteArbitrary(0, -1.0);
      final band0 = Icp5FrameCodec.buildPeqGainWriteArbitrary(0, -1.0, band: 0);
      expect(band0, def);
      expect(band0[9], 0x00); // band byte
    });

    test('gain band N sets frame index 9 to N, everything else identical', () {
      final band0 = Icp5FrameCodec.buildPeqGainWriteArbitrary(0, -1.0);
      for (var band = 1; band < Icp5FrameCodec.peqBandCount; band++) {
        final f = Icp5FrameCodec.buildPeqGainWriteArbitrary(0, -1.0, band: band);
        expect(validEnvelope(f), isTrue);
        expect(f[9], band);
        // Only the band byte and checksum differ from band 0.
        expect(f.sublist(0, 9), band0.sublist(0, 9));
        expect(f[10], band0[10]); // gain value unchanged
      }
    });

    test('frequency band N sets frame index 9 to N', () {
      final band0 = Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(0, 2000);
      final f =
          Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(0, 2000, band: 7);
      expect(validEnvelope(f), isTrue);
      expect(f[9], 7);
      expect(f.sublist(0, 9), band0.sublist(0, 9));
      expect(f.sublist(10, 12), band0.sublist(10, 12)); // freq LE bytes unchanged
    });

    test('Q band N sets frame index 9 to N', () {
      final f = Icp5FrameCodec.buildPeqQWriteArbitrary(0, 2.0, band: 9);
      expect(validEnvelope(f), isTrue);
      expect(f[9], 9);
      expect(f[10], 20); // Q value unchanged
    });

    test('rejects out-of-range band for all three builders', () {
      expect(() => Icp5FrameCodec.buildPeqGainWriteArbitrary(0, 0.0, band: 10),
          throwsA(isA<ArgumentError>()));
      expect(() => Icp5FrameCodec.buildPeqGainWriteArbitrary(0, 0.0, band: -1),
          throwsA(isA<ArgumentError>()));
      expect(
          () => Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(0, 1000,
              band: 10),
          throwsA(isA<ArgumentError>()));
      expect(() => Icp5FrameCodec.buildPeqQWriteArbitrary(0, 2.0, band: 10),
          throwsA(isA<ArgumentError>()));
    });

    test('peqBandCount is 10 (Band 1 .. Band 10)', () {
      expect(Icp5FrameCodec.peqBandCount, 10);
    });
  });

  // ── Envelope consistency across both methods ─────────────────────────────

  group('frame envelope consistency', () {
    test('PEQ gain frame passes hasValidEnvelope for all channels', () {
      for (final ch in [0, 1, 2, 3]) {
        final frame = Icp5FrameCodec.buildPeqGainWriteArbitrary(ch, 0.0);
        expect(validEnvelope(frame), isTrue,
            reason: 'channel $ch should produce valid envelope');
      }
    });

    test('filter frequency frame passes hasValidEnvelope for all channels', () {
      for (final ch in [0, 1, 2, 3]) {
        final frame =
            Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(ch, 1000);
        expect(validEnvelope(frame), isTrue,
            reason: 'channel $ch should produce valid envelope');
      }
    });

    test('PEQ gain and capture-proven gain use same parameter ID', () {
      final arbitrary =
          Icp5FrameCodec.buildPeqGainWriteArbitrary(0, -1.0);
      // The existing capture-proven pair for ch 0 is [-0.9, -1.0]
      final proven =
          Icp5FrameCodec.buildPeqBand1GainWrite(0, -1.0);
      // Both must use parameter ID 0x18 at bytes 3-6
      expect(arbitrary.sublist(3, 7), equals(proven.sublist(3, 7)));
      // Both must produce the same payload for the same value
      expect(arbitrary, equals(proven));
    });

    test('filter frequency and capture-proven cutoff use same parameter ID', () {
      final arbitrary =
          Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(0, 2000);
      final proven = Icp5FrameCodec.buildFilterCutoffWrite(0, 2000);
      expect(arbitrary.sublist(3, 7), equals(proven.sublist(3, 7)));
      expect(arbitrary, equals(proven));
    });
  });
}
