import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_phase_response.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

CrossoverFilter _hp(double fc,
        {CrossoverFilterType type = CrossoverFilterType.butterworth,
        CrossoverSlope slope = CrossoverSlope.db12}) =>
    CrossoverFilter(
        side: FilterSide.highPass, type: type, slope: slope, frequencyHz: fc);
CrossoverFilter _lp(double fc,
        {CrossoverFilterType type = CrossoverFilterType.butterworth,
        CrossoverSlope slope = CrossoverSlope.db12}) =>
    CrossoverFilter(
        side: FilterSide.lowPass, type: type, slope: slope, frequencyHz: fc);

CrossoverChannelState _ch(String id,
        {CrossoverFilter? hp,
        CrossoverFilter? lp,
        bool polarity = false,
        bool bypass = false}) =>
    CrossoverChannelState(
        channelId: id,
        highPass: hp,
        lowPass: lp,
        polarityInverted: polarity,
        bypassed: bypass);

void main() {
  group('distance ↔ delay (343 m/s)', () {
    test('1 ms ↔ 343 mm', () {
      expect(CrossoverPhase.distanceMmFromDelayMs(1.0), closeTo(343, 1e-6));
      expect(CrossoverPhase.delayMsFromDistanceMm(343.0), closeTo(1.0, 1e-6));
    });
    test('round trip', () {
      expect(
          CrossoverPhase.delayMsFromDistanceMm(
              CrossoverPhase.distanceMmFromDelayMs(2.5)),
          closeTo(2.5, 1e-9));
    });
  });

  group('delay phase', () {
    test('pure delay is linear: −360·f·τ deg', () {
      // 1 ms at 1000 Hz = one full period → −360°.
      expect(CrossoverPhase.delayPhaseDeg(1000, 1.0), closeTo(-360, 1e-6));
      expect(CrossoverPhase.delayPhaseDeg(500, 1.0), closeTo(-180, 1e-6));
    });
  });

  group('wrapDeg', () {
    test('wraps to (−180, 180]', () {
      expect(CrossoverPhase.wrapDeg(190), closeTo(-170, 1e-9));
      expect(CrossoverPhase.wrapDeg(-190), closeTo(170, 1e-9));
      expect(CrossoverPhase.wrapDeg(540), closeTo(180, 1e-9));
    });
  });

  group('filter phase', () {
    test('1st-order (12 dB/oct BW → order 2) sanity at cutoff', () {
      // Butterworth db12 = 2nd order: LPF phase −90° at fc, HPF +90°.
      final lp = _ch('w', lp: _lp(1000, slope: CrossoverSlope.db12));
      final hp = _ch('t', hp: _hp(1000, slope: CrossoverSlope.db12));
      expect(
          CrossoverPhase.driverPhaseDeg(
              channel: lp, delayMs: 0, phaseOffsetDeg: 0, f: 1000),
          closeTo(-90, 0.5));
      expect(
          CrossoverPhase.driverPhaseDeg(
              channel: hp, delayMs: 0, phaseOffsetDeg: 0, f: 1000),
          closeTo(90, 0.5));
    });

    test('polarity invert adds 180° (wrapped)', () {
      final normal = _ch('a', lp: _lp(2000));
      final inverted = _ch('a', lp: _lp(2000), polarity: true);
      final pn = CrossoverPhase.driverPhaseDeg(
          channel: normal, delayMs: 0, phaseOffsetDeg: 0, f: 500);
      final pi = CrossoverPhase.driverPhaseDeg(
          channel: inverted, delayMs: 0, phaseOffsetDeg: 0, f: 500);
      expect(CrossoverPhase.wrapDeg(pi - pn).abs(), closeTo(180, 0.5));
    });
  });

  group('LR crossover phase alignment', () {
    test('LR24 woofer LPF and tweeter HPF are in phase at fc', () {
      const fc = 2500.0;
      final wf = _ch('wf',
          lp: _lp(fc,
              type: CrossoverFilterType.linkwitzRiley,
              slope: CrossoverSlope.db24));
      final tw = _ch('tw',
          hp: _hp(fc,
              type: CrossoverFilterType.linkwitzRiley,
              slope: CrossoverSlope.db24));
      final pw = CrossoverPhase.driverPhaseDeg(
          channel: wf, delayMs: 0, phaseOffsetDeg: 0, f: fc);
      final pt = CrossoverPhase.driverPhaseDeg(
          channel: tw, delayMs: 0, phaseOffsetDeg: 0, f: fc);
      // Both −180°/+180° → same wrapped point → in phase (LR sums flat).
      expect(CrossoverPhase.wrapDeg(pw - pt).abs(), lessThan(1.0));
    });
  });

  group('summed phase', () {
    test('two identical drivers sum to the same phase', () {
      final d = XoPhaseDriver(channel: _ch('x', lp: _lp(1500)));
      final freqs = [200.0, 1500.0, 8000.0];
      final summed =
          CrossoverPhase.summedPhaseCurve(drivers: [d, d], freqs: freqs);
      for (var i = 0; i < freqs.length; i++) {
        final single = CrossoverPhase.driverPhaseDeg(
            channel: d.channel, delayMs: 0, phaseOffsetDeg: 0, f: freqs[i]);
        expect(CrossoverPhase.wrapDeg(summed[i] - single).abs(),
            lessThan(0.5));
      }
    });
  });
}
