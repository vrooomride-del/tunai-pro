import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_phase_alignment.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

CrossoverFilter _lr(FilterSide side, double fc,
        {CrossoverSlope slope = CrossoverSlope.db24}) =>
    CrossoverFilter(
        side: side,
        type: CrossoverFilterType.linkwitzRiley,
        slope: slope,
        frequencyHz: fc);

XoAlignmentInput _woofer(
        {double fc = 2500,
        double delayMs = 0,
        bool polarity = false}) =>
    XoAlignmentInput(
      label: 'Woofer',
      delayMs: delayMs,
      channel: CrossoverChannelState(
          channelId: 'wf',
          lowPass: _lr(FilterSide.lowPass, fc),
          polarityInverted: polarity),
    );

XoAlignmentInput _tweeter(
        {double fc = 2500,
        double delayMs = 0,
        bool polarity = false}) =>
    XoAlignmentInput(
      label: 'Tweeter',
      delayMs: delayMs,
      channel: CrossoverChannelState(
          channelId: 'tw',
          highPass: _lr(FilterSide.highPass, fc),
          polarityInverted: polarity),
    );

void main() {
  group('statusForPhaseDiff thresholds', () {
    test('GOOD < 30, CHECK 30–60, MISALIGN > 60', () {
      expect(XoPhaseAlignment.statusForPhaseDiff(0), XoAlignmentStatus.good);
      expect(XoPhaseAlignment.statusForPhaseDiff(29.9), XoAlignmentStatus.good);
      expect(XoPhaseAlignment.statusForPhaseDiff(30), XoAlignmentStatus.check);
      expect(XoPhaseAlignment.statusForPhaseDiff(60), XoAlignmentStatus.check);
      expect(
          XoPhaseAlignment.statusForPhaseDiff(60.1), XoAlignmentStatus.misalign);
      expect(
          XoPhaseAlignment.statusForPhaseDiff(180), XoAlignmentStatus.misalign);
    });
  });

  group('analyze', () {
    test('aligned LR24 2-way → one GOOD pair at the crossover', () {
      final pairs = XoPhaseAlignment.analyze([_woofer(), _tweeter()]);
      expect(pairs, hasLength(1));
      final p = pairs.single;
      expect(p.lowLabel, 'Woofer');
      expect(p.highLabel, 'Tweeter');
      expect(p.crossoverHz, closeTo(2500, 60));
      expect(p.phaseDiffDeg, lessThan(5));
      expect(p.status, XoAlignmentStatus.good);
    });

    test('inverting one driver → ~180° → MISALIGN', () {
      final pairs = XoPhaseAlignment
          .analyze([_woofer(), _tweeter(polarity: true)]);
      expect(pairs, hasLength(1));
      expect(pairs.single.phaseDiffDeg, greaterThan(120));
      expect(pairs.single.status, XoAlignmentStatus.misalign);
      expect(pairs.single.highPolarityInverted, isTrue);
    });

    test('a small delay pushes it into CHECK (30–60°)', () {
      // ~0.05 ms at 2500 Hz ≈ 45° of added phase.
      final pairs =
          XoPhaseAlignment.analyze([_woofer(), _tweeter(delayMs: 0.05)]);
      expect(pairs, hasLength(1));
      expect(pairs.single.phaseDiffDeg, inInclusiveRange(30.0, 60.0));
      expect(pairs.single.status, XoAlignmentStatus.check);
      expect(pairs.single.highDelayMs, closeTo(0.05, 1e-9));
    });

    test('no HPF driver → no crossover pair', () {
      final pairs = XoPhaseAlignment.analyze([_woofer()]);
      expect(pairs, isEmpty);
    });

    test('cutoffs more than an octave apart → no pair', () {
      // Woofer LPF 500, tweeter HPF 4000 → ratio 0.125 (out of ±1 octave).
      final pairs = XoPhaseAlignment
          .analyze([_woofer(fc: 500), _tweeter(fc: 4000)]);
      expect(pairs, isEmpty);
    });

    test('a bypassed driver is excluded', () {
      final bypassedTweeter = XoAlignmentInput(
        label: 'Tweeter',
        channel: CrossoverChannelState(
            channelId: 'tw',
            highPass: _lr(FilterSide.highPass, 2500),
            bypassed: true),
      );
      expect(XoPhaseAlignment.analyze([_woofer(), bypassedTweeter]), isEmpty);
    });
  });
}
