import 'dart:math';
import 'dsp_adapter.dart';
import '../dsp_engine.dart';

/// ADAU1701 어댑터 (tunai_pro UART 버전)
///
/// 프레임 포맷: [0xAA][Addr 2B][Data 20B][XOR Checksum][0x55] = 27바이트
/// PRAM 레이아웃 (출력 채널 기준):
///   채널 ch, 밴드 band → 0x0010 + ch * (bandsPerChannel * 5) + band * 5
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _send;

  static const int _basePram          = 0x0010;
  static const int _bandsPerChannel   = 20; // tunai_pro: 20밴드
  static const int _channelStride     = _bandsPerChannel * 5;

  Adau1701Adapter({required RawWriteFn send}) : _send = send;

  int _pramAddr(int channelIndex, int bandIndex) =>
      _basePram + channelIndex * _channelStride + bandIndex * 5;

  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    final addr = _pramAddr(channelIndex, bandIndex);
    final frame = DspEngine.buildBleFrame(
      BiquadCoefficients(
        b0: coeffs.b0, b1: coeffs.b1, b2: coeffs.b2,
        a1: coeffs.a1, a2: coeffs.a2,
      ),
      addr,
    );
    await _send(frame);
  }

  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    final coeffs = config.type == CrossoverType.hpf
        ? _hpf(config.freqHz)
        : _lpf(config.freqHz);
    // 크로스오버는 마지막 밴드 슬롯 사용
    await writeBiquad(channelIndex, _bandsPerChannel - 1, coeffs);
  }

  @override
  Future<void> writeDelay(int channelIndex, double delayMs) async {
    // TODO: ADAU1701 딜레이 레지스터 주소 확인 후 구현
  }

  @override
  Future<void> writeGain(int channelIndex, double gainDb) async {
    // TODO: ADAU1701 게인 셀 주소 확인 후 구현
  }

  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {
    final coeffs = _hpf(freqHz);
    await writeBiquad(channelIndex, _bandsPerChannel - 2, coeffs);
  }

  // ── 내부 유틸 ──────────────────────────────────────────

  static BiquadCoeffs _hpf(double freq) {
    const sr = DspEngine.sampleRate;
    const q = 0.7071;
    final w0 = 2 * pi * freq / sr;
    final alpha = sin(w0) / (2 * q);
    final cosW = cos(w0);
    final b0 = (1 + cosW) / 2;
    final b1 = -(1 + cosW);
    final b2 = (1 + cosW) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * cosW;
    final a2 = 1 - alpha;
    return BiquadCoeffs(
      b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
      a1: -(a1 / a0), a2: -(a2 / a0),
    );
  }

  static BiquadCoeffs _lpf(double freq) {
    const sr = DspEngine.sampleRate;
    const q = 0.7071;
    final w0 = 2 * pi * freq / sr;
    final alpha = sin(w0) / (2 * q);
    final cosW = cos(w0);
    final b0 = (1 - cosW) / 2;
    final b1 = 1 - cosW;
    final b2 = (1 - cosW) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * cosW;
    final a2 = 1 - alpha;
    return BiquadCoeffs(
      b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
      a1: -(a1 / a0), a2: -(a2 / a0),
    );
  }
}
