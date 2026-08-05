// ADAU1701 payload diff helpers — Task 5 tests.
//
// Covers computePayloadDiff and dspOffsetAnnotation from
// adau1701_dsp_state_read_card.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_dsp_state_read_card.dart';

void main() {
  // ── computePayloadDiff ────────────────────────────────────────────────────

  group('computePayloadDiff', () {
    test('identical payloads produce empty diff', () {
      final a = List<int>.filled(513, 0x00);
      final b = List<int>.filled(513, 0x00);
      expect(computePayloadDiff(a, b), isEmpty);
    });

    test('single byte change detected at correct offset', () {
      final a = List<int>.filled(513, 0x00);
      final b = List<int>.filled(513, 0x00);
      b[19] = 0xD0;
      final diff = computePayloadDiff(a, b);
      expect(diff.length, 1);
      expect(diff[0].offset, 19);
      expect(diff[0].before, 0x00);
      expect(diff[0].after, 0xD0);
    });

    test('multiple byte changes all reported', () {
      final a = List<int>.filled(513, 0x00);
      final b = List<int>.filled(513, 0x00);
      b[19] = 0xD0; // Ch0 Band1 freq-lo
      b[20] = 0x07; // Ch0 Band1 freq-hi
      b[21] = 0xF6; // Ch0 Band1 gain
      final diff = computePayloadDiff(a, b);
      expect(diff.length, 3);
      expect(diff.map((e) => e.offset), containsAll([19, 20, 21]));
    });

    test('before and after values are correct', () {
      final a = List<int>.filled(513, 0xFF);
      final b = List<int>.filled(513, 0xFF);
      b[100] = 0x3C;
      final diff = computePayloadDiff(a, b);
      expect(diff[0].before, 0xFF);
      expect(diff[0].after, 0x3C);
    });

    test('handles payloads of unequal length — compares up to shorter length', () {
      final a = List<int>.filled(513, 0x00);
      final b = List<int>.filled(300, 0x00);
      b[50] = 0xAB;
      final diff = computePayloadDiff(a, b);
      expect(diff.length, 1);
      expect(diff[0].offset, 50);
    });

    test('last byte offset 512 change detected', () {
      final a = List<int>.filled(513, 0x00);
      final b = List<int>.filled(513, 0x00);
      b[512] = 0x01;
      final diff = computePayloadDiff(a, b);
      expect(diff[0].offset, 512);
    });
  });

  // ── dspOffsetAnnotation ───────────────────────────────────────────────────

  group('dspOffsetAnnotation', () {
    // Ch0 Band1 — confirmed offsets.
    test('offset 19 → Ch1 Band1 freq-lo [confirmed]', () {
      expect(dspOffsetAnnotation(19), 'Ch1 Band1 freq-lo [confirmed]');
    });

    test('offset 20 → Ch1 Band1 freq-hi [confirmed]', () {
      expect(dspOffsetAnnotation(20), 'Ch1 Band1 freq-hi [confirmed]');
    });

    test('offset 21 → Ch1 Band1 gain [confirmed]', () {
      expect(dspOffsetAnnotation(21), 'Ch1 Band1 gain [confirmed]');
    });

    test('offset 23 → Ch1 Band1 Q [confirmed]', () {
      expect(dspOffsetAnnotation(23), 'Ch1 Band1 Q [confirmed]');
    });

    // Ch0 Band2 — band candidate.
    test('offset 25 → Ch1 Band2 freq-lo [band-cand]', () {
      expect(dspOffsetAnnotation(25), 'Ch1 Band2 freq-lo [band-cand]');
    });

    test('offset 27 → Ch1 Band2 gain [band-cand]', () {
      expect(dspOffsetAnnotation(27), 'Ch1 Band2 gain [band-cand]');
    });

    // Ch0 Band10 (last band in Ch0: 19 + 9*6 = 73).
    test('offset 73 → Ch1 Band10 freq-lo [band-cand]', () {
      expect(dspOffsetAnnotation(73), 'Ch1 Band10 freq-lo [band-cand]');
    });

    // Ch0 range end is 19 + 10*6 = 79; offset 78 is last in Ch0.
    test('offset 78 → Ch1 Band10 prop08 [band-cand]', () {
      expect(dspOffsetAnnotation(78), 'Ch1 Band10 prop08 [band-cand]');
    });

    // Ch1 base 79 — channel layout candidate.
    test('offset 79 → Ch2 Band1 freq-lo [ch-cand]', () {
      expect(dspOffsetAnnotation(79), 'Ch2 Band1 freq-lo [ch-cand]');
    });

    test('offset 81 → Ch2 Band1 gain [ch-cand]', () {
      expect(dspOffsetAnnotation(81), 'Ch2 Band1 gain [ch-cand]');
    });

    // Ch2 base 139.
    test('offset 139 → Ch3 Band1 freq-lo [ch-cand]', () {
      expect(dspOffsetAnnotation(139), 'Ch3 Band1 freq-lo [ch-cand]');
    });

    // Ch3 base 199.
    test('offset 199 → Ch4 Band1 freq-lo [ch-cand]', () {
      expect(dspOffsetAnnotation(199), 'Ch4 Band1 freq-lo [ch-cand]');
    });

    // Offset 154 is inside Ch3 candidate range [139..199), so it is annotated
    // as a band byte — the page-marker check in the source is unreachable here.
    test('offset 154 → Ch3 Band3 pad (inside ch-cand range, page marker unreachable)', () {
      expect(dspOffsetAnnotation(154), 'Ch3 Band3 pad [ch-cand]');
    });

    test('offset 308 → page-3 marker', () {
      expect(dspOffsetAnnotation(308), 'page-3 marker');
    });

    test('offset 462 → page-4 marker', () {
      expect(dspOffsetAnnotation(462), 'page-4 marker');
    });

    // Unknown offsets.
    test('offset 0 → unknown', () {
      expect(dspOffsetAnnotation(0), '— (unknown)');
    });

    test('offset 18 (just before Ch0 base) → unknown', () {
      expect(dspOffsetAnnotation(18), '— (unknown)');
    });

    test('offset 512 (last byte) → unknown', () {
      expect(dspOffsetAnnotation(512), '— (unknown)');
    });
  });
}
