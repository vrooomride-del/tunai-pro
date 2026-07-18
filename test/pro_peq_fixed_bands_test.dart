// Unit tests for the fixed 10-band PEQ slot model (ADAU1701/MIUMAX style).

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

void main() {
  group('PeqBand.slot', () {
    test('is a disabled/bypassed peak slot with a deterministic id', () {
      final s = PeqBand.slot(3);
      expect(s.id, 'band_3');
      expect(s.enabled, isFalse);
      expect(s.status, PeqBandStatus.bypassed);
      expect(s.type, PeqBandType.peak);
    });
  });

  group('PeqChannelState.fixed', () {
    test('always has exactly 10 disabled slots', () {
      final ch = PeqChannelState.fixed('ch0');
      expect(ch.bands, hasLength(PeqChannelState.bandCount));
      expect(PeqChannelState.bandCount, 10);
      expect(ch.bands.every((b) => !b.enabled), isTrue);
      expect(ch.enabledBandCount, 0);
    });
  });

  group('normalized()', () {
    test('pads a short channel to 10, preserving existing bands by position', () {
      final ch = PeqChannelState(channelId: 'ch0', bands: [
        const PeqBand(id: 'a', enabled: true, frequencyHz: 100, gainDb: -1, q: 2),
        const PeqBand(id: 'b', enabled: true, frequencyHz: 200, gainDb: 1, q: 3),
      ]);
      final n = ch.normalized();
      expect(n.bands, hasLength(10));
      // Band 1 (index 0) verified values are preserved unchanged.
      expect(n.bands[0].frequencyHz, 100);
      expect(n.bands[0].gainDb, -1);
      expect(n.bands[0].enabled, isTrue);
      expect(n.bands[1].frequencyHz, 200);
      // Padded slots are disabled.
      expect(n.bands.skip(2).every((b) => !b.enabled), isTrue);
      expect(n.enabledBandCount, 2);
    });

    test('is idempotent for an already-fixed channel', () {
      final ch = PeqChannelState.fixed('ch0');
      expect(identical(ch.normalized(), ch), isTrue);
    });

    test('truncates a channel with more than 10 bands', () {
      final ch = PeqChannelState(
        channelId: 'ch0',
        bands: List.generate(
            13, (i) => PeqBand(id: 'b$i', frequencyHz: 100.0 + i)),
      );
      expect(ch.normalized().bands, hasLength(10));
      expect(ch.normalized().bands.last.frequencyHz, 109);
    });
  });

  group('fillNextFreeSlot', () {
    test('enables the first disabled slot with the given values', () {
      final ch = PeqChannelState.fixed('ch0');
      final filled = ch.fillNextFreeSlot(
        type: PeqBandType.peak,
        frequencyHz: 1200,
        gainDb: -3,
        q: 4,
      );
      expect(filled.bands, hasLength(10));
      expect(filled.enabledBandCount, 1);
      expect(filled.bands[0].enabled, isTrue);
      expect(filled.bands[0].status, PeqBandStatus.active);
      expect(filled.bands[0].frequencyHz, 1200);
      // Next call fills slot 1, not slot 0.
      final filled2 = filled.fillNextFreeSlot(
          type: PeqBandType.peak, frequencyHz: 2400, gainDb: 0, q: 1);
      expect(filled2.enabledBandCount, 2);
      expect(filled2.bands[1].frequencyHz, 2400);
    });

    test('is a no-op (stays 10 slots) when every slot is in use', () {
      var ch = PeqChannelState.fixed('ch0');
      for (var i = 0; i < 10; i++) {
        ch = ch.fillNextFreeSlot(
            type: PeqBandType.peak, frequencyHz: 100.0 * (i + 1), gainDb: 0, q: 1);
      }
      expect(ch.enabledBandCount, 10);
      final overflow = ch.fillNextFreeSlot(
          type: PeqBandType.peak, frequencyHz: 9999, gainDb: 0, q: 1);
      expect(overflow.bands, hasLength(10));
      expect(overflow.enabledBandCount, 10);
      expect(overflow.bands.any((b) => b.frequencyHz == 9999), isFalse);
    });
  });

  test('JSON round-trip preserves the 10 fixed slots', () {
    final ch = PeqChannelState.fixed('ch0').fillNextFreeSlot(
        type: PeqBandType.peak, frequencyHz: 800, gainDb: 2, q: 1.5);
    final restored = PeqChannelState.fromJson(ch.toJson());
    expect(restored.bands, hasLength(10));
    expect(restored.enabledBandCount, 1);
    expect(restored.bands[0].frequencyHz, 800);
  });
}
