// ADAU1701 DSP Comparison — unit tests (4-output).
//
// Groups:
//   1. Output role mapping       — 4 outputs, correct speaker roles, tab labels
//   2. PEQ reference model       — 40 bands (4ch × 10), confidence tiers
//   3. Comparison logic (Ch0)    — match, diff, score for Tweeter L
//   4. 4-output comparison       — all 4 outputs comparable/not, per-output score
//   5. Unknown confidence (Woofer) — excluded from match score, freq still shown
//   6. Tweeter/Woofer role enum  — enum values and short labels
//   7. Graph curve builder       — peqReferenceToBands for all 4 channels

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_state_decoder.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_output_role.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_peq_reference.dart';
import 'package:tunai_pro/core/dsp/adau1701/readback/adau1701_dsp_comparison.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_dsp_state_read_card.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';

// Builds a 513-byte payload encoding Ch0 reference values at stride-6 offsets
// (offset 19 + 6*bandIndex). Ch1-3 left as zeros.
List<int> _buildCh0RefPayload() {
  final p = List<int>.filled(513, 0);
  p[154] = 0x01;
  p[308] = 0x02;
  p[462] = 0x03;
  final refs = Adau1701MiuMaxPeqReference.ch0Bands;
  for (var i = 0; i < refs.length; i++) {
    final base = 19 + 6 * i;
    final ref = refs[i];
    p[base] = ref.frequencyHz & 0xFF;
    p[base + 1] = (ref.frequencyHz >> 8) & 0xFF;
    final gainRaw = (ref.gainDb * 10).round();
    p[base + 2] = gainRaw < 0 ? gainRaw + 256 : gainRaw;
    p[base + 4] = (ref.q * 10).round();
  }
  return p;
}

// Builds a payload encoding both Tweeter L (Ch0) and Tweeter R (Ch1) reference
// values so that overall match score can reach 100% for Tweeter outputs.
List<int> _buildTweeterRefPayload() {
  final p = _buildCh0RefPayload();
  // Ch1 at stride-60 offset: base = 19 + 60 = 79
  final refs = Adau1701MiuMaxPeqReference.ch1Bands;
  for (var i = 0; i < refs.length; i++) {
    final base = 79 + 6 * i;
    final ref = refs[i];
    p[base] = ref.frequencyHz & 0xFF;
    p[base + 1] = (ref.frequencyHz >> 8) & 0xFF;
    final gainRaw = (ref.gainDb * 10).round();
    p[base + 2] = gainRaw < 0 ? gainRaw + 256 : gainRaw;
    p[base + 4] = (ref.q * 10).round();
  }
  return p;
}

RawDspStateSnapshot _snap(List<int> payload) => RawDspStateSnapshot(
      deviceId: _kDeviceId,
      timestamp: DateTime.utc(2026, 8, 5, 12, 0, 0),
      blockId: 0x2202,
      payload: payload,
    );

RawDspStateSnapshot _ch0RefSnap() => _snap(_buildCh0RefPayload());
RawDspStateSnapshot _tweeterRefSnap() => _snap(_buildTweeterRefPayload());

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. Output role mapping ────────────────────────────────────────────────

  group('Output role mapping', () {
    test('miuMaxOutputRoles has exactly 4 entries', () {
      expect(miuMaxOutputRoles.length, equals(4));
    });

    test('Output 0 is Tweeter L (DAC0)', () {
      expect(miuMaxOutputRoles[0], equals(Adau1701OutputRole.tweeterLeft));
    });

    test('Output 1 is Tweeter R (DAC1)', () {
      expect(miuMaxOutputRoles[1], equals(Adau1701OutputRole.tweeterRight));
    });

    test('Output 2 is Woofer L (DAC2)', () {
      expect(miuMaxOutputRoles[2], equals(Adau1701OutputRole.wooferLeft));
    });

    test('Output 3 is Woofer R (DAC3)', () {
      expect(miuMaxOutputRoles[3], equals(Adau1701OutputRole.wooferRight));
    });

    test('miuMaxOutputTabLabel(0) produces "Output 1 · Tweeter L"', () {
      expect(miuMaxOutputTabLabel(0), equals('Output 1 · Tweeter L'));
    });

    test('miuMaxOutputTabLabel(1) produces "Output 2 · Tweeter R"', () {
      expect(miuMaxOutputTabLabel(1), equals('Output 2 · Tweeter R'));
    });

    test('miuMaxOutputTabLabel(2) produces "Output 3 · Woofer L"', () {
      expect(miuMaxOutputTabLabel(2), equals('Output 3 · Woofer L'));
    });

    test('miuMaxOutputTabLabel(3) produces "Output 4 · Woofer R"', () {
      expect(miuMaxOutputTabLabel(3), equals('Output 4 · Woofer R'));
    });

    test('all 4 tab labels contain the output number', () {
      for (var i = 0; i < 4; i++) {
        expect(miuMaxOutputTabLabel(i), contains('Output ${i + 1}'));
      }
    });
  });

  // ── 2. PEQ reference model — 4 channels ──────────────────────────────────

  group('PEQ reference model', () {
    test('forChannel returns non-null for all 4 channels', () {
      for (var ch = 0; ch < 4; ch++) {
        expect(Adau1701MiuMaxPeqReference.forChannel(ch), isNotNull,
            reason: 'Ch$ch must have reference data');
      }
    });

    test('forChannel returns null for channel index >= 4', () {
      expect(Adau1701MiuMaxPeqReference.forChannel(4), isNull);
    });

    test('each channel has exactly 10 reference bands', () {
      for (var ch = 0; ch < 4; ch++) {
        expect(Adau1701MiuMaxPeqReference.forChannel(ch)!.length, equals(10),
            reason: 'Ch$ch must have 10 bands');
      }
    });

    test('total reference bands across 4 channels is 40', () {
      final total =
          List.generate(4, (i) => Adau1701MiuMaxPeqReference.forChannel(i)!.length)
              .fold(0, (a, b) => a + b);
      expect(total, equals(40));
    });

    test('Ch0 Band 0 is hardwareConfirmed (1800 Hz / 0.0 dB / Q1.2)', () {
      final b = Adau1701MiuMaxPeqReference.ch0Bands[0];
      expect(b.confidence, equals(DataConfidence.hardwareConfirmed));
      expect(b.frequencyHz, equals(1800));
      expect(b.gainDb, closeTo(0.0, 0.001));
      expect(b.q, closeTo(1.2, 0.001));
    });

    test('Ch0 Bands 1-9 are candidateMapping', () {
      for (var i = 1; i < 10; i++) {
        expect(Adau1701MiuMaxPeqReference.ch0Bands[i].confidence,
            equals(DataConfidence.candidateMapping),
            reason: 'Ch0 Band $i must be candidateMapping');
      }
    });

    test('Ch0 has correct Tweeter frequencies (from MiUMAX screen)', () {
      const expectedFreqs = [1800, 2500, 3300, 4500, 6500, 8500, 11000, 14500, 18000, 20000];
      for (var i = 0; i < 10; i++) {
        expect(Adau1701MiuMaxPeqReference.ch0Bands[i].frequencyHz, equals(expectedFreqs[i]),
            reason: 'Ch0 Band $i freq mismatch');
      }
    });

    test('Ch0 Band 6 gain is -0.8 dB', () {
      expect(Adau1701MiuMaxPeqReference.ch0Bands[6].gainDb, closeTo(-0.8, 0.001));
    });

    test('Ch0 Band 7 gain is -0.3 dB', () {
      expect(Adau1701MiuMaxPeqReference.ch0Bands[7].gainDb, closeTo(-0.3, 0.001));
    });

    test('Ch1 (Tweeter R) has same frequencies as Ch0', () {
      for (var i = 0; i < 10; i++) {
        expect(
          Adau1701MiuMaxPeqReference.ch1Bands[i].frequencyHz,
          equals(Adau1701MiuMaxPeqReference.ch0Bands[i].frequencyHz),
          reason: 'Ch1 Band $i must match Ch0 freq',
        );
      }
    });

    test('Ch1 all bands are candidateMapping (channel layout unconfirmed)', () {
      for (var i = 0; i < 10; i++) {
        expect(Adau1701MiuMaxPeqReference.ch1Bands[i].confidence,
            equals(DataConfidence.candidateMapping),
            reason: 'Ch1 Band $i must be candidateMapping');
      }
    });

    test('Ch2 (Woofer L) has correct frequencies (from MiUMAX screen)', () {
      const expectedFreqs = [60, 120, 220, 350, 550, 750, 1200, 1800, 2400, 3500];
      for (var i = 0; i < 10; i++) {
        expect(Adau1701MiuMaxPeqReference.ch2Bands[i].frequencyHz, equals(expectedFreqs[i]),
            reason: 'Ch2 Band $i freq mismatch');
      }
    });

    test('Ch2 all bands are unknown (Gain/Q not yet captured)', () {
      for (var i = 0; i < 10; i++) {
        expect(Adau1701MiuMaxPeqReference.ch2Bands[i].confidence,
            equals(DataConfidence.unknown),
            reason: 'Ch2 Band $i must be unknown');
      }
    });

    test('Ch3 (Woofer R) is identical to Ch2 (Woofer L)', () {
      expect(Adau1701MiuMaxPeqReference.ch3Bands,
          same(Adau1701MiuMaxPeqReference.ch2Bands));
    });

    test('DataConfidence labels are correct', () {
      expect(DataConfidence.hardwareConfirmed.label, equals('Hardware Confirmed'));
      expect(DataConfidence.candidateMapping.label, equals('Candidate Mapping'));
      expect(DataConfidence.unknown.label, equals('Unknown'));
    });
  });

  // ── 3. Comparison logic — Ch0 (Tweeter L) ────────────────────────────────

  group('Comparison logic — Ch0 Tweeter L', () {
    late DspComparisonSummary comp;

    setUp(() {
      final decoded = Adau1701StateDecoder.decode(_ch0RefSnap());
      comp = Adau1701DspComparison.compare(decoded);
    });

    test('compare() returns exactly 4 output results', () {
      expect(comp.outputs.length, equals(4));
    });

    test('Ch0 has comparable reference (candidateMapping/hardwareConfirmed)', () {
      expect(comp.outputs[0].hasComparableReference, isTrue);
    });

    test('Ch0 comparison has exactly 10 band results', () {
      expect(comp.outputs[0].bandComparisons!.length, equals(10));
    });

    test('Ch0 all 10 bands are isComparable = true', () {
      for (final b in comp.outputs[0].bandComparisons!) {
        expect(b.isComparable, isTrue,
            reason: 'Ch0 Band ${b.bandIndex} must be comparable');
      }
    });

    test('Ch0 ref payload → all 10 bands match', () {
      expect(comp.outputs[0].matchCount, equals(10));
    });

    test('Ch0 match score is 100% when payload matches reference', () {
      expect(comp.outputs[0].matchScorePercent, closeTo(100.0, 0.01));
    });

    test('Ch0 freqDiff = 0 for Band 0 (1800 Hz match)', () {
      expect(comp.outputs[0].bandComparisons![0].freqDiffHz, equals(0));
    });

    test('Ch0 gainDiff ≈ 0 for Band 0 (0.0 dB match)', () {
      expect(comp.outputs[0].bandComparisons![0].gainDiffDb, closeTo(0.0, 0.001));
    });

    test('Band 0 isMatch=false when freq differs from reference', () {
      final payload = _buildCh0RefPayload();
      payload[19] = 0x00;
      payload[20] = 0x01; // 256 Hz (≠ 1800 Hz reference)
      final decoded = Adau1701StateDecoder.decode(_snap(payload));
      final c2 = Adau1701DspComparison.compare(decoded);
      expect(c2.outputs[0].bandComparisons![0].isMatch, isFalse);
      expect(c2.outputs[0].bandComparisons![0].freqDiffHz, equals(256 - 1800));
    });

    test('role assigned to each output result matches miuMaxOutputRoles', () {
      for (var i = 0; i < 4; i++) {
        expect(comp.outputs[i].role, equals(miuMaxOutputRoles[i]));
      }
    });
  });

  // ── 4. 4-output comparison ────────────────────────────────────────────────

  group('4-output comparison', () {
    late DspComparisonSummary comp;

    setUp(() {
      final decoded = Adau1701StateDecoder.decode(_tweeterRefSnap());
      comp = Adau1701DspComparison.compare(decoded);
    });

    test('Ch1 (Tweeter R) has comparable reference', () {
      expect(comp.outputs[1].hasComparableReference, isTrue);
    });

    test('Ch1 has 10 comparable bands (candidateMapping)', () {
      expect(comp.outputs[1].totalComparable, equals(10));
    });

    test('Ch1 match score is 100% when payload encodes Tweeter R reference values', () {
      expect(comp.outputs[1].matchScorePercent, closeTo(100.0, 0.01));
    });

    test('Ch2 (Woofer L) has no comparable reference (all unknown)', () {
      expect(comp.outputs[2].hasComparableReference, isFalse);
    });

    test('Ch2 totalComparable is 0 (Woofer Gain/Q excluded)', () {
      expect(comp.outputs[2].totalComparable, equals(0));
    });

    test('Ch2 matchCount is 0', () {
      expect(comp.outputs[2].matchCount, equals(0));
    });

    test('Ch3 (Woofer R) has no comparable reference', () {
      expect(comp.outputs[3].hasComparableReference, isFalse);
    });

    test('totalComparableBands across 4 outputs is 20 (Ch0+Ch1 only)', () {
      expect(comp.totalComparableBands, equals(20));
    });

    test('matchedBands is 20 when both Tweeter payloads match reference', () {
      expect(comp.matchedBands, equals(20));
    });

    test('overall matchScorePercent is 100% when both Tweeters match', () {
      expect(comp.matchScorePercent, closeTo(100.0, 0.01));
    });
  });

  // ── 5. Unknown confidence — Woofer ───────────────────────────────────────

  group('Unknown confidence band handling', () {
    late DspComparisonSummary comp;

    setUp(() {
      final decoded = Adau1701StateDecoder.decode(_ch0RefSnap());
      comp = Adau1701DspComparison.compare(decoded);
    });

    test('Ch2 bandComparisons is non-null (reference data exists for freq)', () {
      expect(comp.outputs[2].bandComparisons, isNotNull);
    });

    test('Ch2 bandComparisons has 10 entries', () {
      expect(comp.outputs[2].bandComparisons!.length, equals(10));
    });

    test('all Ch2 band comparisons have isComparable = false', () {
      for (final b in comp.outputs[2].bandComparisons!) {
        expect(b.isComparable, isFalse,
            reason: 'Ch2 Band ${b.bandIndex} must not be comparable');
      }
    });

    test('all Ch2 band comparisons have isMatch = false', () {
      for (final b in comp.outputs[2].bandComparisons!) {
        expect(b.isMatch, isFalse,
            reason: 'Unknown band must never be isMatch=true');
      }
    });

    test('Ch2 reference frequency is still accessible for display', () {
      const expectedFreqs = [60, 120, 220, 350, 550, 750, 1200, 1800, 2400, 3500];
      for (var i = 0; i < 10; i++) {
        expect(comp.outputs[2].bandComparisons![i].reference.frequencyHz,
            equals(expectedFreqs[i]),
            reason: 'Ch2 Band $i reference freq must match Woofer L values');
      }
    });

    test('Ch2 confidence for all bands is unknown', () {
      for (final b in comp.outputs[2].bandComparisons!) {
        expect(b.reference.confidence, equals(DataConfidence.unknown));
      }
    });

    test('Woofer totalComparable is excluded from DspComparisonSummary total', () {
      // Only Ch0 (10) + Ch1 (10) = 20 comparable, not 40.
      final decoded = Adau1701StateDecoder.decode(_ch0RefSnap());
      final c2 = Adau1701DspComparison.compare(decoded);
      expect(c2.totalComparableBands, lessThanOrEqualTo(20));
    });
  });

  // ── 6. Tweeter/Woofer role enum ───────────────────────────────────────────

  group('Tweeter/Woofer role enum', () {
    test('Adau1701OutputRole has exactly 4 values', () {
      expect(Adau1701OutputRole.values.length, equals(4));
    });

    test('tweeterLeft shortLabel is "Tweeter L"', () {
      expect(Adau1701OutputRole.tweeterLeft.shortLabel, equals('Tweeter L'));
    });

    test('tweeterRight shortLabel is "Tweeter R"', () {
      expect(Adau1701OutputRole.tweeterRight.shortLabel, equals('Tweeter R'));
    });

    test('wooferLeft shortLabel is "Woofer L"', () {
      expect(Adau1701OutputRole.wooferLeft.shortLabel, equals('Woofer L'));
    });

    test('wooferRight shortLabel is "Woofer R"', () {
      expect(Adau1701OutputRole.wooferRight.shortLabel, equals('Woofer R'));
    });
  });

  // ── 7. Graph curve builder — all 4 channels ───────────────────────────────

  group('Graph curve builder — peqReferenceToBands', () {
    test('Ch0 Tweeter L reference → 10 bands', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch0Bands);
      expect(bands.length, equals(10));
    });

    test('Ch0 Band 0 frequency preserved (1800 Hz)', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch0Bands);
      expect(bands[0].frequencyHz, closeTo(1800.0, 0.01));
    });

    test('Ch0 Band 6 gain preserved (-0.8 dB)', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch0Bands);
      expect(bands[6].gainDb, closeTo(-0.8, 0.01));
    });

    test('Ch1 Tweeter R reference → 10 bands', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch1Bands);
      expect(bands.length, equals(10));
    });

    test('Ch2 Woofer L reference → 10 bands (freq known, gain placeholder)', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch2Bands);
      expect(bands.length, equals(10));
    });

    test('Ch2 Band 0 frequency is 60 Hz', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch2Bands);
      expect(bands[0].frequencyHz, closeTo(60.0, 0.01));
    });

    test('Ch3 Woofer R reference → 10 bands (same as Ch2)', () {
      final bands = peqReferenceToBands(Adau1701MiuMaxPeqReference.ch3Bands);
      expect(bands.length, equals(10));
    });

    test('all 4 channel reference lists convert to non-empty band lists', () {
      for (var ch = 0; ch < 4; ch++) {
        final refs = Adau1701MiuMaxPeqReference.forChannel(ch)!;
        final bands = peqReferenceToBands(refs);
        expect(bands, isNotEmpty, reason: 'Ch$ch must produce non-empty band list');
      }
    });

    test('all bands set enabled=true in reference conversion', () {
      for (var ch = 0; ch < 4; ch++) {
        final refs = Adau1701MiuMaxPeqReference.forChannel(ch)!;
        final bands = peqReferenceToBands(refs);
        expect(bands.every((b) => b.enabled), isTrue,
            reason: 'Ch$ch all bands must be enabled');
      }
    });

    test('empty list produces empty band list', () {
      expect(peqReferenceToBands([]), isEmpty);
    });
  });
}
