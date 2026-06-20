import 'dart:math';
import 'dsp_adapter.dart';
import '../dsp_engine.dart';

/// ADAU1701 어댑터 (tunai_pro UART 버전)
///
/// 프레임: [0xAA][Addr 2B][Data 20B = 5×4B][XOR][0x55] = 27바이트
///
/// ▼ PRAM 주소 — SigmaStudio IC Memory Map (WONDOM 기본 데모, 2025-06-20 확인)
///   GAIN : ExtSWGainDB 셀, 5.23 선형값 1워드
///     ch0 Woofer  = 7  (ExtSWGainDB2step_20, "Vol")
///     ch1 Tweeter = 6  (ExtSWGainDB3step_19, "Vol_2")
///   DELAY: 현 펌웨어에 Delay 블록 없음 — 추가+재컴파일 필요, 현재 미지원
///   PEQ  : 채널별 20밴드 × 5 워드 (주소 미확정, 별도 확인 필요)
///   XO   : PEQ 직후 HP/LP 각 최대 4 슬롯
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _send;

  // ── PRAM 레이아웃 ──────────────────────────────────────────────
  static const int _peqBase         = 0x0010; // PEQ 밴드 시작 (미확정)
  static const int _peqBands        = 20;
  static const int _peqChStride     = _peqBands * 5; // ch당 100 워드

  // XO: PEQ(6ch × 100워드) 뒤에 채널당 [HP×4슬롯][LP×4슬롯] = 8슬롯 × 5워드
  static const int _xoBase          = _peqBase + 6 * _peqChStride;
  static const int _xoSlotsPerSide  = 4; // LR48 최대 4 biquad
  static const int _xoChStride      = _xoSlotsPerSide * 2 * 5; // (HP+LP) × 5워드

  // Gain 셀 PRAM 주소 — ch0/ch1 순서가 비연속이므로 배열로 관리
  // SigmaStudio 프로젝트(.dspproj)가 변경되면 재확인 필요
  static const List<int> _gainAddresses = [7, 6]; // [ch0 Woofer=Vol, ch1 Tweeter=Vol_2]

  // Delay: 현 펌웨어에 블록 없음 → 미지원
  static const int _delayBase       = 0x0000; // Delay 블록 추가+재컴파일 전까지 미사용

  Adau1701Adapter({required RawWriteFn send}) : _send = send;

  // ── PEQ 밴드 ─────────────────────────────────────────────────
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    final addr = _peqBase + channelIndex * _peqChStride + bandIndex * 5;
    final frame = DspEngine.buildBleFrame(
      BiquadCoefficients(b0: coeffs.b0, b1: coeffs.b1, b2: coeffs.b2,
                         a1: coeffs.a1, a2: coeffs.a2),
      addr,
    );
    await _send(frame);
  }

  // ── 크로스오버 ───────────────────────────────────────────────
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    final xoType = _mapXoType(config.slope);
    if (xoType == null) return; // bypass

    final isHpf = config.side == FilterSide.hpf;
    final biquads = DspEngine.calculateCrossoverBiquads(config.freqHz, isHpf, xoType);

    // HP = 슬롯 0..3, LP = 슬롯 4..7 (채널 내)
    final slotBase = isHpf ? 0 : _xoSlotsPerSide;
    final chBase   = _xoBase + channelIndex * _xoChStride;

    for (var i = 0; i < biquads.length; i++) {
      await _send(DspEngine.buildBleFrame(biquads[i], chBase + (slotBase + i) * 5));
    }
    // 사용하지 않는 나머지 슬롯 → passthrough
    for (var i = biquads.length; i < _xoSlotsPerSide; i++) {
      await _send(DspEngine.buildBleFrame(
          BiquadCoefficients.passthrough, chBase + (slotBase + i) * 5));
    }
  }

  // ── Gain ─────────────────────────────────────────────────────
  @override
  Future<void> writeGain(int channelIndex, double gainDb) async {
    if (channelIndex >= _gainAddresses.length) return;
    final linear = pow(10.0, gainDb / 20.0).toDouble();
    await _send(DspEngine.buildGainFrame(linear, _gainAddresses[channelIndex]));
  }

  // ── Delay ────────────────────────────────────────────────────
  // 현 펌웨어에 Delay 블록 없음 — SigmaStudio에서 블록 추가+재컴파일 필요
  @override
  Future<void> writeDelay(int channelIndex, double delayMs) async {
    if (_delayBase == 0x0000) return; // Delay 블록 미존재
    await _send(DspEngine.buildDelayFrame(delayMs, _delayBase + channelIndex));
  }

  // ── 서브소닉 HPF ─────────────────────────────────────────────
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {
    final biquads = DspEngine.calculateCrossoverBiquads(freqHz, true, XoType.bw2);
    // XO HP 슬롯의 마지막 슬롯(슬롯 3)을 서브소닉 전용으로 사용
    final addr = _xoBase + channelIndex * _xoChStride + (_xoSlotsPerSide - 1) * 5;
    await _send(DspEngine.buildBleFrame(biquads[0], addr));
  }

  // ── 내부 매핑 ─────────────────────────────────────────────────
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
