import 'dart:math';
import 'dsp_adapter.dart';
import '../dsp_engine.dart';

/// ADAU1466 + CS42448 어댑터 (tunai_pro)
///
/// 채널 인덱스 (DspState.outputs 순서와 일치):
///   0: TWE L  1: TWE R  2: MID L  3: MID R  4: WOO L  5: WOO R
///
/// SigmaStudio PRAM 주소 (2026-07-01):
///   Volume : 545, 548, 551, 554, 557, 560  — SPI 쓰기 검증 완료 ✓
///   Delay  : 562, 563, 564, 565, 566, 567  — 채널 묶음 패턴 추정, 실기기 미확인
///   PEQ/XO : 미확정 — SigmaStudio .dspproj export 후 ParameterRAM.dat 확인 필요
///
/// 고정소수점: ADAU1466 = 5.27 (ADAU1701의 5.23과 다름)
class Adau1466Adapter implements DspAdapter {
  final RawWriteFn _send;

  // ── Volume 셀 PRAM 주소 (ch0~ch5) ─────────────────────────────
  // SigmaStudio SPI 쓰기 검증 완료 (2026-07-01) ✓
  static const List<int> _gainAddresses = [545, 548, 551, 554, 557, 560];

  // ── Delay 셀 PRAM 주소 (ch0~ch5) ──────────────────────────────
  // 채널 묶음의 연속 배치 패턴으로 추정 — 실기기 확인 필요 (2026-07-01)
  static const List<int> _delayAddresses = [562, 563, 564, 565, 566, 567];

  // ── PEQ / XO 주소 ─────────────────────────────────────────────
  // TODO: SigmaStudio .dspproj export → ParameterRAM.dat 확인 후 교체
  // 현재값은 ADAU1701 패턴 기반 추정치 — 실기기 미확인
  static const int _peqBase        = 0x0100; // 추정 — 미확정
  static const int _peqBands       = 20;
  static const int _peqChStride    = _peqBands * 5; // ch당 100 워드
  static const int _xoBase         = _peqBase + 6 * _peqChStride; // 추정
  static const int _xoSlotsPerSide = 4; // LR48 최대 4 biquad
  static const int _xoChStride     = _xoSlotsPerSide * 2 * 5; // (HP+LP) × 5워드

  Adau1466Adapter({required RawWriteFn send}) : _send = send;

  // ── Gain ─────────────────────────────────────────────────────
  // Volume 셀: 5.27 선형값 1워드 — 검증됨 ✓
  @override
  Future<void> writeGain(int channelIndex, double gainDb) async {
    if (channelIndex >= _gainAddresses.length) return;
    final linear = pow(10.0, gainDb / 20.0).toDouble();
    await _send(DspEngine.buildGainFrame1466(linear, _gainAddresses[channelIndex]));
  }

  // ── Delay ────────────────────────────────────────────────────
  // 28.0 샘플 카운트 — 주소 추정값, 실기기 확인 필요
  @override
  Future<void> writeDelay(int channelIndex, double delayMs) async {
    if (channelIndex >= _delayAddresses.length) return;
    await _send(DspEngine.buildDelayFrame(delayMs, _delayAddresses[channelIndex]));
  }

  // ── PEQ 밴드 ─────────────────────────────────────────────────
  // 5.27 biquad — PEQ 주소 미확정, SigmaStudio export 후 갱신 필요
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    final addr = _peqBase + channelIndex * _peqChStride + bandIndex * 5;
    await _send(DspEngine.buildBleFrame1466(
      BiquadCoefficients(b0: coeffs.b0, b1: coeffs.b1, b2: coeffs.b2,
                         a1: coeffs.a1, a2: coeffs.a2),
      addr,
    ));
  }

  // ── 크로스오버 ───────────────────────────────────────────────
  // XO 주소 미확정, SigmaStudio export 후 갱신 필요
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    final xoType = _mapXoType(config.slope);
    if (xoType == null) return;

    final isHpf = config.side == FilterSide.hpf;
    final biquads = DspEngine.calculateCrossoverBiquads(config.freqHz, isHpf, xoType);

    final slotBase = isHpf ? 0 : _xoSlotsPerSide;
    final chBase   = _xoBase + channelIndex * _xoChStride;

    for (var i = 0; i < biquads.length; i++) {
      await _send(DspEngine.buildBleFrame1466(biquads[i], chBase + (slotBase + i) * 5));
    }
    for (var i = biquads.length; i < _xoSlotsPerSide; i++) {
      await _send(DspEngine.buildBleFrame1466(
          BiquadCoefficients.passthrough, chBase + (slotBase + i) * 5));
    }
  }

  // ── 서브소닉 HPF ─────────────────────────────────────────────
  // XO HP 슬롯 마지막(슬롯 3)을 서브소닉 전용 사용 — 주소 미확정
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {
    final biquads = DspEngine.calculateCrossoverBiquads(freqHz, true, XoType.bw2);
    final addr = _xoBase + channelIndex * _xoChStride + (_xoSlotsPerSide - 1) * 5;
    await _send(DspEngine.buildBleFrame1466(biquads[0], addr));
  }

  static XoType? _mapXoType(CrossoverSlope slope) {
    switch (slope) {
      case CrossoverSlope.bypass: return null;
      case CrossoverSlope.bw2:   return XoType.bw2;
      case CrossoverSlope.bw4:   return XoType.bw4;
      case CrossoverSlope.lr2:   return XoType.lr2;
      case CrossoverSlope.lr4:   return XoType.lr4;
      case CrossoverSlope.lr8:   return XoType.lr8;
    }
  }
}
