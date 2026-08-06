// ADAU1701 PEQ Graph — Full 10-Band Calculation Tests.
//
// Verifies that the linear-product combinedMagnitudeDb formula includes ALL
// 10 bands, not just the first or a filtered subset.
//
// MiUMAX Output1 (Tweeter L) test fixture:
//   Band1  1800 Hz  0.0 dB  Q1.20  (passthrough — contributes ×1.0)
//   Band2  2500 Hz  0.0 dB  Q0.70
//   ...
//   Band7 11000 Hz -0.8 dB  Q0.80  ← only non-passthrough bands
//   Band8 14500 Hz -0.3 dB  Q0.80  ←
//   Band9 18000 Hz  0.0 dB  Q0.70
//   Band10 20000 Hz 0.0 dB  Q0.70
//
// Core assertion: combinedCurve(allTenBands) != combinedCurve([Band7 only])
//   because Band8 contributes a visible dip at 14.5 kHz in the 10-band curve.
//
// Groups:
//   1. all 10 bands curve != single band curve
//   2. Band7/8 negative gain dip maintained
//   3. Band1 frequency marker — passthrough at centre freq
//   4. linear product identity — 0-dB bands multiply by 1
//   5. pipeline: peqBandsToResponseBands preserves all 10 bands
//   6. enabled/disabled toggle: disabled band leaves response unchanged

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_state_decoder.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_dsp_state_read_card.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

PeqResponseBand _band(double freqHz, double gainDb, double q,
    {bool enabled = true}) =>
    PeqResponseBand(frequencyHz: freqHz, gainDb: gainDb, q: q, enabled: enabled);

// MiUMAX Output1 (Tweeter L) 10-band fixture.
// Band7 and Band8 are the only non-passthrough bands.
List<PeqResponseBand> _tweeterL10Bands() => [
  _band(1800, 0.0, 1.2),   // Band1
  _band(2500, 0.0, 0.7),   // Band2
  _band(3150, 0.0, 0.7),   // Band3
  _band(4000, 0.0, 0.7),   // Band4
  _band(6300, 0.0, 0.7),   // Band5
  _band(8000, 0.0, 0.7),   // Band6
  _band(11000, -0.8, 0.8), // Band7 — cut
  _band(14500, -0.3, 0.8), // Band8 — cut
  _band(18000, 0.0, 0.7),  // Band9
  _band(20000, 0.0, 0.7),  // Band10
];

// Single-band fixture: Band7 only.
List<PeqResponseBand> _band7Only() => [_band(11000, -0.8, 0.8)];

List<double> _freqs(int count) =>
    Adau1701PeqResponse.logFrequencyPoints(count: count);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Group 1: all 10 bands curve != single band curve ─────────────────────

  group('all 10 bands curve != single band curve', () {
    final freqs = _freqs(200);

    test('combinedCurve differs between 10-band and Band7-only at 14.5 kHz', () {
      // The 10-band curve includes Band8 (-0.3 dB at 14.5 kHz).
      // The Band7-only curve has no contribution at 14.5 kHz.
      final curve10 = Adau1701PeqResponse.combinedCurve(_tweeterL10Bands(), freqs);
      final curve1 = Adau1701PeqResponse.combinedCurve(_band7Only(), freqs);

      final idx14k = freqs.indexWhere((f) => f >= 14000 && f <= 15000);
      expect(idx14k, isNot(-1), reason: 'no freq point near 14.5 kHz');

      // 10-band curve has Band8 dip at 14.5 kHz; Band7-only does not.
      expect(curve10[idx14k], lessThan(curve1[idx14k]),
          reason: 'Band8 should make 10-band curve more negative at 14.5 kHz');
    });

    test('curves differ at 14.5 kHz by at least 0.1 dB', () {
      final freqs200 = _freqs(200);
      final curve10 = Adau1701PeqResponse.combinedCurve(_tweeterL10Bands(), freqs200);
      final curve1 = Adau1701PeqResponse.combinedCurve(_band7Only(), freqs200);

      final idx14k = freqs200.indexWhere((f) => f >= 14000 && f <= 15000);
      expect(curve1[idx14k] - curve10[idx14k], greaterThan(0.1),
          reason: 'Band8 should add at least 0.1 dB cut relative to Band7-only');
    });

    test('curves are identical at 11 kHz (Band7 present in both; Band8 tail is small)', () {
      // At 11 kHz both curves include Band7. Band8 (centred at 14.5 kHz, Q0.8)
      // has some tail at 11 kHz, so the 10-band curve is slightly MORE negative.
      final curve10 = Adau1701PeqResponse.combinedCurve(_tweeterL10Bands(), freqs);
      final curve1 = Adau1701PeqResponse.combinedCurve(_band7Only(), freqs);

      final idx11k = freqs.indexWhere((f) => f >= 10500 && f <= 11500);
      expect(idx11k, isNot(-1));
      // Both should be negative (Band7 present).
      expect(curve10[idx11k], lessThan(0));
      expect(curve1[idx11k], lessThan(0));
      // 10-band may be slightly more negative (Band8 tail), but by < 0.5 dB.
      expect((curve10[idx11k] - curve1[idx11k]).abs(), lessThan(0.5));
    });

    test('length of both curves matches the frequency grid', () {
      final freqs256 = _freqs(256);
      final curve10 = Adau1701PeqResponse.combinedCurve(_tweeterL10Bands(), freqs256);
      final curve1 = Adau1701PeqResponse.combinedCurve(_band7Only(), freqs256);
      expect(curve10.length, 256);
      expect(curve1.length, 256);
    });
  });

  // ── Group 2: Band7/8 negative gain dip maintained ────────────────────────

  group('Band7/8 negative gain dip maintained', () {
    final freqs = _freqs(200);

    test('combined 10-band curve is negative at 11 kHz (Band7 dip)', () {
      final db = Adau1701PeqResponse.combinedMagnitudeDb(
          _tweeterL10Bands(), 11000);
      expect(db, lessThan(-0.5));
    });

    test('combined 10-band curve is negative at 14.5 kHz (Band8 dip)', () {
      final db = Adau1701PeqResponse.combinedMagnitudeDb(
          _tweeterL10Bands(), 14500);
      expect(db, lessThan(-0.2));
    });

    test('minimum of the 10-band curve is negative', () {
      final curve = Adau1701PeqResponse.combinedCurve(_tweeterL10Bands(), freqs);
      expect(curve.reduce((a, b) => a < b ? a : b), lessThan(-0.5));
    });

    test('peakingMagnitudeDb single-band Band7 ≈ -0.8 dB at 11000 Hz', () {
      final band7 = _band(11000, -0.8, 0.8);
      expect(Adau1701PeqResponse.peakingMagnitudeDb(band7, 11000),
          closeTo(-0.8, 0.05));
    });

    test('peakingMagnitudeDb single-band Band8 ≈ -0.3 dB at 14500 Hz', () {
      final band8 = _band(14500, -0.3, 0.8);
      expect(Adau1701PeqResponse.peakingMagnitudeDb(band8, 14500),
          closeTo(-0.3, 0.05));
    });
  });

  // ── Group 3: Band1 frequency marker — passthrough at centre freq ─────────

  group('Band1 frequency marker — passthrough at centre freq', () {
    test('Band1 (1800 Hz, 0 dB) contributes 0 dB at its centre frequency', () {
      final band1 = _band(1800, 0.0, 1.2);
      expect(Adau1701PeqResponse.peakingMagnitudeDb(band1, 1800), 0.0);
    });

    test('10-band curve at 1800 Hz is near 0 dB (Band1 is passthrough)', () {
      final db = Adau1701PeqResponse.combinedMagnitudeDb(
          _tweeterL10Bands(), 1800);
      expect(db.abs(), lessThan(0.2));
    });

    test('combinedMagnitudeDb at 1000 Hz is near 0 dB (no active band nearby)', () {
      final db = Adau1701PeqResponse.combinedMagnitudeDb(
          _tweeterL10Bands(), 1000);
      expect(db.abs(), lessThan(0.3));
    });
  });

  // ── Group 4: linear product identity — 0-dB bands multiply by 1 ─────────

  group('linear product identity — 0-dB bands multiply by 1', () {
    test('adding a 0-dB band does not change the combined curve', () {
      final bands7 = [_band(11000, -0.8, 0.8)];
      final bandsWithFlat = [
        _band(1800, 0.0, 1.2),   // passthrough
        _band(11000, -0.8, 0.8),
        _band(14500, 0.0, 0.8),  // passthrough
      ];
      // At 11 kHz: adding 0-dB bands should not change Band7's contribution.
      final db7 = Adau1701PeqResponse.combinedMagnitudeDb(bands7, 11000);
      final dbWith = Adau1701PeqResponse.combinedMagnitudeDb(bandsWithFlat, 11000);
      expect(dbWith, closeTo(db7, 0.01));
    });

    test('10 passthrough bands produce 0 dB everywhere', () {
      final flat = [for (var i = 0; i < 10; i++) _band(1000, 0.0, 1.0)];
      final freqs200 = _freqs(200);
      for (final f in [20.0, 1000.0, 10000.0, 20000.0]) {
        expect(Adau1701PeqResponse.combinedMagnitudeDb(flat, f), 0.0);
      }
      final curve = Adau1701PeqResponse.combinedCurve(flat, freqs200);
      expect(curve.every((db) => db == 0.0), isTrue);
    });

    test('empty band list produces 0 dB', () {
      expect(Adau1701PeqResponse.combinedMagnitudeDb([], 11000), 0.0);
    });
  });

  // ── Group 5: pipeline peqBandsToResponseBands preserves all 10 bands ─────

  group('pipeline: peqBandsToResponseBands preserves all 10 bands', () {
    // Build a decoded snapshot with all 10 Output1 bands.
    late List<PeqResponseBand> pipeline;

    setUpAll(() {
      final payload = List<int>.filled(513, 0);
      // Page-boundary markers.
      payload[154] = 0x01;
      payload[308] = 0x02;
      payload[462] = 0x03;
      // Band1-10 at stride-6 from Ch0 base 19.
      final bands = [
        (freqHz: 1800, gainDb: 0.0, q: 1.2),
        (freqHz: 2500, gainDb: 0.0, q: 0.7),
        (freqHz: 3150, gainDb: 0.0, q: 0.7),
        (freqHz: 4000, gainDb: 0.0, q: 0.7),
        (freqHz: 6300, gainDb: 0.0, q: 0.7),
        (freqHz: 8000, gainDb: 0.0, q: 0.7),
        (freqHz: 11000, gainDb: -0.8, q: 0.8),
        (freqHz: 14500, gainDb: -0.3, q: 0.8),
        (freqHz: 18000, gainDb: 0.0, q: 0.7),
        (freqHz: 20000, gainDb: 0.0, q: 0.7),
      ];
      for (var i = 0; i < bands.length; i++) {
        final base = 19 + i * 6;
        final b = bands[i];
        payload[base] = b.freqHz & 0xFF;
        payload[base + 1] = (b.freqHz >> 8) & 0xFF;
        final gainRaw = (b.gainDb * 10).round();
        payload[base + 2] = gainRaw < 0 ? gainRaw + 256 : gainRaw;
        payload[base + 4] = (b.q * 10).round();
      }
      final snap = RawDspStateSnapshot(
        deviceId: 'DSP1701.100.00.01',
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: payload,
      );
      final state = Adau1701StateDecoder.decode(snap);
      pipeline = peqBandsToResponseBands(state.outputs[0].peqBands);
    });

    test('peqBandsToResponseBands output has 10 items', () {
      expect(pipeline.length, 10);
    });

    test('all pipeline bands are enabled=true', () {
      expect(pipeline.every((b) => b.enabled), isTrue);
    });

    test('pipeline Band7 (index 6) has frequency 11000 Hz', () {
      expect(pipeline[6].frequencyHz, closeTo(11000.0, 0.1));
    });

    test('pipeline Band7 (index 6) has gainDb -0.8 dB', () {
      expect(pipeline[6].gainDb, closeTo(-0.8, 0.01));
    });

    test('pipeline Band8 (index 7) has frequency 14500 Hz', () {
      expect(pipeline[7].frequencyHz, closeTo(14500.0, 0.1));
    });

    test('combinedCurve from pipeline has dip at 11 kHz', () {
      expect(
          Adau1701PeqResponse.combinedMagnitudeDb(pipeline, 11000),
          lessThan(-0.5));
    });

    test('combinedCurve from pipeline differs from Band7-only at 14.5 kHz', () {
      final db10 = Adau1701PeqResponse.combinedMagnitudeDb(pipeline, 14500);
      final db1 = Adau1701PeqResponse.combinedMagnitudeDb(_band7Only(), 14500);
      // 10-band includes Band8 cut → more negative.
      expect(db10, lessThan(db1));
    });
  });

  // ── Group 6: enabled/disabled toggle ─────────────────────────────────────

  group('enabled/disabled toggle: disabled band leaves response unchanged', () {
    test('disabling Band7 removes the 11 kHz dip', () {
      final bands = _tweeterL10Bands();
      final band7disabled = _band(11000, -0.8, 0.8, enabled: false);
      final bandsNoB7 = [
        ...bands.sublist(0, 6),
        band7disabled,
        ...bands.sublist(7),
      ];
      // With Band7 disabled, the 11 kHz response should be near 0 (only Band8 tail).
      final db = Adau1701PeqResponse.combinedMagnitudeDb(bandsNoB7, 11000);
      final dbWith = Adau1701PeqResponse.combinedMagnitudeDb(bands, 11000);
      expect(db, greaterThan(dbWith)); // less cut without Band7
      expect(db.abs(), lessThan(0.5)); // near flat
    });

    test('disabling all bands produces 0 dB curve', () {
      final disabled = _tweeterL10Bands()
          .map((b) => b.copyWith(enabled: false))
          .toList();
      final db = Adau1701PeqResponse.combinedMagnitudeDb(disabled, 11000);
      expect(db, 0.0);
    });

    test('re-enabling a disabled Band7 restores the dip', () {
      final bands = _tweeterL10Bands();
      final dbAll = Adau1701PeqResponse.combinedMagnitudeDb(bands, 11000);
      final bandsNoB7 = [
        ...bands.sublist(0, 6),
        _band(11000, -0.8, 0.8, enabled: false),
        ...bands.sublist(7),
      ];
      final dbNoB7 = Adau1701PeqResponse.combinedMagnitudeDb(bandsNoB7, 11000);
      expect(dbAll, lessThan(dbNoB7)); // original has more cut
    });
  });
}
