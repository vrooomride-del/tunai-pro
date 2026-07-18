import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_crossover_response.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

CrossoverFilter _hp(
        {double fc = 2000,
        CrossoverFilterType type = CrossoverFilterType.butterworth,
        CrossoverSlope slope = CrossoverSlope.db24,
        bool enabled = true}) =>
    CrossoverFilter(
        side: FilterSide.highPass,
        type: type,
        slope: slope,
        frequencyHz: fc,
        enabled: enabled);

CrossoverFilter _lp(
        {double fc = 2000,
        CrossoverFilterType type = CrossoverFilterType.butterworth,
        CrossoverSlope slope = CrossoverSlope.db24,
        bool enabled = true}) =>
    CrossoverFilter(
        side: FilterSide.lowPass,
        type: type,
        slope: slope,
        frequencyHz: fc,
        enabled: enabled);

void main() {
  group('logFrequencyPoints', () {
    test('spans 20..20k, monotonic', () {
      final pts = CrossoverResponse.logFrequencyPoints(count: 64);
      expect(pts.first, closeTo(20, 1e-6));
      expect(pts.last, closeTo(20000, 1e-6));
      for (var i = 1; i < pts.length; i++) {
        expect(pts[i], greaterThan(pts[i - 1]));
      }
    });
  });

  group('orderFor', () {
    test('6 dB/oct per order', () {
      expect(CrossoverResponse.orderFor(CrossoverSlope.db12), 2);
      expect(CrossoverResponse.orderFor(CrossoverSlope.db24), 4);
      expect(CrossoverResponse.orderFor(CrossoverSlope.db36), 6);
      expect(CrossoverResponse.orderFor(CrossoverSlope.db48), 8);
    });
  });

  group('filterMagnitudeDb', () {
    test('Butterworth is −3 dB at the cutoff', () {
      final lp = _lp(fc: 1000, type: CrossoverFilterType.butterworth);
      expect(CrossoverResponse.filterMagnitudeDb(lp, 1000), closeTo(-3.0, 0.05));
      final hp = _hp(fc: 1000, type: CrossoverFilterType.butterworth);
      expect(CrossoverResponse.filterMagnitudeDb(hp, 1000), closeTo(-3.0, 0.05));
    });

    test('Linkwitz-Riley is −6 dB at the cutoff (sums flat)', () {
      final lp = _lp(fc: 1000, type: CrossoverFilterType.linkwitzRiley);
      expect(CrossoverResponse.filterMagnitudeDb(lp, 1000), closeTo(-6.0, 0.05));
    });

    test('LR24 low-pass asymptotic slope is ~24 dB/oct in the stopband', () {
      final lp = _lp(
          fc: 1000,
          type: CrossoverFilterType.linkwitzRiley,
          slope: CrossoverSlope.db24);
      // Well past fc the slope approaches the nominal 24 dB/oct.
      final at4k = CrossoverResponse.filterMagnitudeDb(lp, 4000);
      final at8k = CrossoverResponse.filterMagnitudeDb(lp, 8000);
      expect(at4k - at8k, closeTo(24, 1.5));
    });

    test('high-pass passes above and rolls off below fc', () {
      final hp = _hp(fc: 1000);
      expect(CrossoverResponse.filterMagnitudeDb(hp, 8000).abs(),
          lessThan(0.5)); // passes
      expect(CrossoverResponse.filterMagnitudeDb(hp, 125),
          lessThan(-12)); // rolled off
    });

    test('a disabled filter passes (0 dB)', () {
      expect(CrossoverResponse.filterMagnitudeDb(_lp(enabled: false), 1000), 0);
    });
  });

  group('channelMagnitudeDb', () {
    test('band-pass driver: HPF + LPF cascade', () {
      const ch = CrossoverChannelState(channelId: 'mid');
      final band = ch.copyWith(
        highPass: _hp(fc: 300, type: CrossoverFilterType.linkwitzRiley),
        lowPass: _lp(fc: 3000, type: CrossoverFilterType.linkwitzRiley),
      );
      // In-band (near 1 kHz) is close to 0 dB.
      expect(CrossoverResponse.channelMagnitudeDb(band, 1000).abs(),
          lessThan(1.5));
      // Below HPF and above LPF is attenuated.
      expect(CrossoverResponse.channelMagnitudeDb(band, 60), lessThan(-12));
      expect(CrossoverResponse.channelMagnitudeDb(band, 15000), lessThan(-12));
    });

    test('bypassed channel is flat (0 dB)', () {
      final ch = const CrossoverChannelState(channelId: 'x')
          .copyWith(bypassed: true, lowPass: _lp(fc: 500));
      expect(CrossoverResponse.channelMagnitudeDb(ch, 5000), 0);
    });
  });

  group('summed (power sum)', () {
    test('LR24 woofer LPF + tweeter HPF at the same fc sums near 0 dB', () {
      final freqs = CrossoverResponse.logFrequencyPoints(count: 200);
      final woofer = const CrossoverChannelState(channelId: 'wf').copyWith(
          lowPass:
              _lp(fc: 2500, type: CrossoverFilterType.linkwitzRiley));
      final tweeter = const CrossoverChannelState(channelId: 'tw').copyWith(
          highPass:
              _hp(fc: 2500, type: CrossoverFilterType.linkwitzRiley));
      final summed = CrossoverResponse.summedCurve([
        CrossoverResponse.channelCurve(woofer, freqs),
        CrossoverResponse.channelCurve(tweeter, freqs),
      ]);
      // At the crossover each is −6 dB; power sum ≈ −3 dB.
      final idxFc = freqs.indexWhere((f) => f >= 2500);
      expect(summed[idxFc], closeTo(-3.0, 0.4));
      // Well inside each passband the sum is ≈ 0 dB.
      final idxLow = freqs.indexWhere((f) => f >= 100);
      final idxHigh = freqs.indexWhere((f) => f >= 12000);
      expect(summed[idxLow], closeTo(0.0, 0.5));
      expect(summed[idxHigh], closeTo(0.0, 0.5));
    });

    test('powerSumDb of two equal levels is +3 dB', () {
      expect(CrossoverResponse.powerSumDb(const [0, 0]), closeTo(3.01, 0.05));
    });
  });
}
