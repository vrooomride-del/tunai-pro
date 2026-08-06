// ADAU1701 MiUMAX Full Readback Recovery — Task 3 tests.
//
// Verifies that the tuning panel's _read() path correctly decodes all 10
// Output1 bands (not just Band1) from a 513-byte hardware snapshot.
//
// MiUMAX Output1 (Tweeter L) confirmed values:
//   Band1  1800 Hz  0.0 dB  Q1.20
//   Band2  2500 Hz  0.0 dB  Q0.70
//   Band7 11000 Hz -0.8 dB  Q0.80
//   Band8 14500 Hz -0.3 dB  Q0.80
//   Band10 20000 Hz 0.0 dB  Q0.70
//
// Groups:
//   1. Output1 bands.length == 10
//   2. Band1-10 frequency decode from stride-6 offsets
//   3. Gain decode (negative gain bands)
//   4. Q decode
//   5. Graph input: all 10 bands enabled for graph converter
//   6. _peqModel binding: all 10 slots populated enabled=true

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_state_decoder.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_dsp_state_read_card.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';

// Encodes a single band at base offset (6-byte stride format).
void _writeBand(List<int> p, int base,
    {required int freqHz, required double gainDb, required double q}) {
  p[base] = freqHz & 0xFF;
  p[base + 1] = (freqHz >> 8) & 0xFF;
  final gainRaw = (gainDb * 10).round();
  p[base + 2] = gainRaw < 0 ? gainRaw + 256 : gainRaw;
  p[base + 4] = (q * 10).round();
}

// Builds a 513-byte payload with MiUMAX Tweeter L values across all 10 bands
// at stride-6 from Ch0 base offset 19.
//
// MiUMAX Output1 values (capture-confirmed Band1, stride-hypothesis Bands 2-10):
//   Band1 1800/0.0/1.2   Band2 2500/0.0/0.7   Band3 3150/0.0/0.7
//   Band4 4000/0.0/0.7   Band5 6300/0.0/0.7   Band6 8000/0.0/0.7
//   Band7 11000/-0.8/0.8 Band8 14500/-0.3/0.8 Band9 18000/0.0/0.7
//   Band10 20000/0.0/0.7
const _kMiuMaxTweeterLBands = [
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

List<int> _buildTweeterLPayload() {
  final p = List<int>.filled(513, 0);
  // Page-boundary markers required by the decoder.
  p[154] = 0x01;
  p[308] = 0x02;
  p[462] = 0x03;
  // Ch0 base offset 19; stride 6 per band.
  for (var i = 0; i < _kMiuMaxTweeterLBands.length; i++) {
    final b = _kMiuMaxTweeterLBands[i];
    _writeBand(p, 19 + i * 6,
        freqHz: b.freqHz, gainDb: b.gainDb, q: b.q);
  }
  return p;
}

RawDspStateSnapshot _buildSnapshot(List<int> payload) => RawDspStateSnapshot(
      deviceId: _kDeviceId,
      timestamp: DateTime.utc(2026, 8, 5),
      blockId: 0x2202,
      payload: payload,
    );

// Simulate the _peqModel population that _read() now performs.
// Returns a 10-element list of PeqResponseBand (enabled=true).
List<PeqResponseBand> _simulatePeqModelBinding(
    Adau1701StateSnapshot stateSnapshot) {
  final output1Bands = stateSnapshot.outputs[0].peqBands;
  return [
    for (final b in output1Bands)
      PeqResponseBand(
        frequencyHz: b.frequencyHz.toDouble(),
        gainDb: b.gainDb,
        q: b.q,
        enabled: true,
      ),
  ];
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late Adau1701StateSnapshot snap;

  setUp(() {
    snap = Adau1701StateDecoder.decode(_buildSnapshot(_buildTweeterLPayload()));
  });

  // ── Group 1: Output1 bands.length == 10 ──────────────────────────────────

  group('Output1 bands.length == 10', () {
    test('outputs[0].peqBands has exactly 10 entries', () {
      expect(snap.outputs[0].peqBands.length, 10);
    });

    test('all 10 bands have sequential bandIndex 0..9', () {
      final bands = snap.outputs[0].peqBands;
      for (var i = 0; i < bands.length; i++) {
        expect(bands[i].bandIndex, i,
            reason: 'Band${i + 1} wrong bandIndex');
      }
    });

    test('peqBandsToResponseBands from Output1 produces 10 items', () {
      final responseBands =
          peqBandsToResponseBands(snap.outputs[0].peqBands);
      expect(responseBands.length, 10);
    });
  });

  // ── Group 2: Band1-10 frequency decode ───────────────────────────────────

  group('Band1-10 frequency decode from stride-6 offsets', () {
    test('Band1 (offset 19) decodes to 1800 Hz', () {
      expect(snap.outputs[0].peqBands[0].frequencyHz, 1800);
    });

    test('Band2 (offset 25) decodes to 2500 Hz', () {
      expect(snap.outputs[0].peqBands[1].frequencyHz, 2500);
    });

    test('Band3 (offset 31) decodes to 3150 Hz', () {
      expect(snap.outputs[0].peqBands[2].frequencyHz, 3150);
    });

    test('Band4 (offset 37) decodes to 4000 Hz', () {
      expect(snap.outputs[0].peqBands[3].frequencyHz, 4000);
    });

    test('Band5 (offset 43) decodes to 6300 Hz', () {
      expect(snap.outputs[0].peqBands[4].frequencyHz, 6300);
    });

    test('Band6 (offset 49) decodes to 8000 Hz', () {
      expect(snap.outputs[0].peqBands[5].frequencyHz, 8000);
    });

    test('Band7 (offset 55) decodes to 11000 Hz', () {
      expect(snap.outputs[0].peqBands[6].frequencyHz, 11000);
    });

    test('Band8 (offset 61) decodes to 14500 Hz', () {
      expect(snap.outputs[0].peqBands[7].frequencyHz, 14500);
    });

    test('Band9 (offset 67) decodes to 18000 Hz', () {
      expect(snap.outputs[0].peqBands[8].frequencyHz, 18000);
    });

    test('Band10 (offset 73) decodes to 20000 Hz', () {
      expect(snap.outputs[0].peqBands[9].frequencyHz, 20000);
    });

    test('all 10 frequencies match the MiUMAX Tweeter L reference table', () {
      final bands = snap.outputs[0].peqBands;
      for (var i = 0; i < _kMiuMaxTweeterLBands.length; i++) {
        expect(bands[i].frequencyHz, _kMiuMaxTweeterLBands[i].freqHz,
            reason: 'Band${i + 1} frequency mismatch');
      }
    });
  });

  // ── Group 3: Gain decode ─────────────────────────────────────────────────

  group('Gain decode (negative gain bands)', () {
    test('Band7 gain decodes to -0.8 dB', () {
      expect(snap.outputs[0].peqBands[6].gainDb, closeTo(-0.8, 0.01));
    });

    test('Band8 gain decodes to -0.3 dB', () {
      expect(snap.outputs[0].peqBands[7].gainDb, closeTo(-0.3, 0.01));
    });

    test('Bands 1-6 have 0.0 dB gain (flat)', () {
      for (var i = 0; i < 6; i++) {
        expect(snap.outputs[0].peqBands[i].gainDb, closeTo(0.0, 0.01),
            reason: 'Band${i + 1} should be flat');
      }
    });

    test('Bands 9-10 have 0.0 dB gain (flat)', () {
      expect(snap.outputs[0].peqBands[8].gainDb, closeTo(0.0, 0.01));
      expect(snap.outputs[0].peqBands[9].gainDb, closeTo(0.0, 0.01));
    });
  });

  // ── Group 4: Q decode ────────────────────────────────────────────────────

  group('Q decode', () {
    test('Band1 Q decodes to 1.20', () {
      expect(snap.outputs[0].peqBands[0].q, closeTo(1.2, 0.01));
    });

    test('Band2 Q decodes to 0.70', () {
      expect(snap.outputs[0].peqBands[1].q, closeTo(0.7, 0.01));
    });

    test('Band7 Q decodes to 0.80', () {
      expect(snap.outputs[0].peqBands[6].q, closeTo(0.8, 0.01));
    });

    test('Band8 Q decodes to 0.80', () {
      expect(snap.outputs[0].peqBands[7].q, closeTo(0.8, 0.01));
    });
  });

  // ── Group 5: Graph input — all 10 bands enabled ──────────────────────────

  group('Graph input: all 10 bands enabled for graph converter', () {
    test('peqBandsToResponseBands produces all enabled=true bands', () {
      final responseBands =
          peqBandsToResponseBands(snap.outputs[0].peqBands);
      expect(responseBands.every((b) => b.enabled), isTrue);
    });

    test('graph input band count is 10', () {
      final graphBands =
          peqBandsToResponseBands(snap.outputs[0].peqBands);
      expect(graphBands.length, 10);
    });

    test('graph combined curve has a dip at 11 kHz (Band7 -0.8 dB)', () {
      final graphBands =
          peqBandsToResponseBands(snap.outputs[0].peqBands);
      final db = graphBands
          .map((b) => PeqResponseBand(
              frequencyHz: b.frequencyHz,
              gainDb: b.gainDb,
              q: b.q,
              enabled: b.enabled))
          .fold<double>(0.0,
              (sum, b) => sum + Adau1701PeqResponse.peakingMagnitudeDb(b, 11000));
      expect(db, lessThan(-0.5));
    });

    test('graph combined curve is near 0 dB at 1000 Hz (no active band near there)',
        () {
      final graphBands =
          peqBandsToResponseBands(snap.outputs[0].peqBands);
      final db = graphBands
          .map((b) => PeqResponseBand(
              frequencyHz: b.frequencyHz,
              gainDb: b.gainDb,
              q: b.q,
              enabled: b.enabled))
          .fold<double>(0.0,
              (sum, b) => sum + Adau1701PeqResponse.peakingMagnitudeDb(b, 1000));
      expect(db.abs(), lessThan(0.3));
    });
  });

  // ── Group 6: _peqModel binding ───────────────────────────────────────────

  group('_peqModel binding: all 10 slots populated enabled=true', () {
    late List<PeqResponseBand> model;

    setUp(() {
      model = _simulatePeqModelBinding(snap);
    });

    test('_peqModel[0] has exactly 10 entries', () {
      expect(model.length, 10);
    });

    test('all 10 _peqModel slots are enabled=true', () {
      expect(model.every((b) => b.enabled), isTrue);
    });

    test('_peqModel[0][0] has frequency 1800 Hz', () {
      expect(model[0].frequencyHz, closeTo(1800.0, 0.1));
    });

    test('_peqModel[0][6] has frequency 11000 Hz (Band7)', () {
      expect(model[6].frequencyHz, closeTo(11000.0, 0.1));
    });

    test('_peqModel[0][6] has gain -0.8 dB', () {
      expect(model[6].gainDb, closeTo(-0.8, 0.01));
    });

    test('_peqModel[0][9] has frequency 20000 Hz (Band10)', () {
      expect(model[9].frequencyHz, closeTo(20000.0, 0.1));
    });
  });
}
