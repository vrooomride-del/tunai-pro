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

enum CrossoverType { lpf, hpf }
enum CrossoverSlope { lr2, lr4, bw2, bw4 }

class CrossoverConfig {
  final CrossoverType type;
  final double freqHz;
  final CrossoverSlope slope;
  const CrossoverConfig({required this.type, required this.freqHz, this.slope = CrossoverSlope.lr4});
}

/// DSP 칩별 통신 추상화 — 채널/밴드 단위 고수준 API
abstract class DspAdapter {
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs);
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config);
  Future<void> writeDelay(int channelIndex, double delayMs);
  Future<void> writeGain(int channelIndex, double gainDb);
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz);
}
