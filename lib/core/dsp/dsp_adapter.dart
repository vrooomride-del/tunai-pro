import '../dsp_engine.dart';

/// 직렬(UART) 또는 BLE로 raw 바이트를 전송하는 콜백 타입
typedef RawWriteFn = Future<bool> Function(List<int> bytes);

class BiquadCoeffs {
  final double b0, b1, b2, a1, a2;
  const BiquadCoeffs({
    required this.b0, required this.b1, required this.b2,
    required this.a1, required this.a2,
  });

  factory BiquadCoeffs.fromEngine(BiquadCoefficients c) =>
      BiquadCoeffs(b0: c.b0, b1: c.b1, b2: c.b2, a1: c.a1, a2: c.a2);
}

/// HP(고역통과) / LP(저역통과) 방향
enum FilterSide { lpf, hpf }

/// 크로스오버 필터 특성 (기울기)
/// bypass : 비활성
/// bw2/bw4: 2차/4차 Butterworth  (12/24 dB/oct)
/// lr2/lr4 : 2차/4차 Linkwitz-Riley (12/24 dB/oct)
/// lr8     : 8차 Linkwitz-Riley  (48 dB/oct)
enum CrossoverSlope { bypass, bw2, bw4, lr2, lr4, lr8 }

class CrossoverConfig {
  final FilterSide side;
  final double freqHz;
  final CrossoverSlope slope;
  const CrossoverConfig({
    required this.side,
    required this.freqHz,
    this.slope = CrossoverSlope.lr4,
  });
}

/// DSP 칩별 통신 추상화 — 채널/밴드 단위 고수준 API
abstract class DspAdapter {
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs);
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config);
  Future<void> writeDelay(int channelIndex, double delayMs);
  Future<void> writeGain(int channelIndex, double gainDb);
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz);
}
