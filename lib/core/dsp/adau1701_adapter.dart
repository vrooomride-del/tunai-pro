import 'dart:math';
import 'dsp_adapter.dart';
import '../dsp_engine.dart';

/// ADAU1701 어댑터 (tunai_pro UART 버전)
///
/// 프레임: [0xAA][Addr 2B][Data 20B = 5×4B][XOR][0x55] = 27바이트
///
/// ▼ PRAM 주소 — SigmaStudio export 주소 확정 (2026-07)
///   GAIN : ExtSWGainDB 셀, 5.23 선형값 1워드
///     ch0 Woofer  = 7  (ExtSWGainDB2step_20, "Vol")
///     ch1 Tweeter = 6  (ExtSWGainDB3step_19, "Vol_2")
///   DELAY: 현 펌웨어에 Delay 블록 없음 — 추가+재컴파일 필요, 현재 미지원
///   PEQ  : peqBase=14, 채널당 10밴드×5계수=50워드 연속 배치 (20밴드 총합, 14~113)
///     ch0 Woofer  PEQ: 14~63,  ch1 Tweeter PEQ: 64~113
///   XO   : 주소 미확정 (SigmaStudio Filter 블록 주소 확인 전까지 no-op)
///   MUTE : 채널(밴드) 뮤트 — Woofer=11, Tweeter=12
///          출력 뮤트 — 물리 출력 채널별 개별: out0=805, out1=806, out2=807, out3=808
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _send;

  // ── PRAM 레이아웃 ──────────────────────────────────────────────
  static const int _peqBase         = 14; // PEQ 밴드 시작 (확정)
  static const int _peqBands        = 10; // 채널당 PEQ 슬롯 수 (maxPeqBands 기준)
  static const int _peqChStride     = _peqBands * 5; // ch당 50 워드

  // XO: 주소 미확정 — SigmaStudio Filter 블록 주소 확인 전까지 no-op
  static const int? _xoBase         = null; // TODO: 주소 미확정
  static const int _xoSlotsPerSide  = 4; // LR48 최대 4 biquad
  static const int _xoChStride      = _xoSlotsPerSide * 2 * 5; // (HP+LP) × 5워드

  // Gain 셀 PRAM 주소 — ch0/ch1 순서가 비연속이므로 배열로 관리
  // SigmaStudio 프로젝트(.dspproj)가 변경되면 재확인 필요
  static const List<int> _gainAddresses = [7, 6]; // [ch0 Woofer=Vol, ch1 Tweeter=Vol_2]

  // Delay: 현 펌웨어에 블록 없음 → 미지원
  static const int _delayBase       = 0x0000; // Delay 블록 추가+재컴파일 전까지 미사용

  // 채널(밴드) 뮤트 주소 — Woofer=11, Tweeter=12 (확정)
  static const List<int> _channelMuteAddresses = [11, 12];

  // 출력 뮤트 주소 — 물리 출력 채널별 개별 (확정)
  static const List<int> _outputMuteAddresses = [805, 806, 807, 808];

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
    const xoBase = _xoBase;
    if (xoBase == null) return; // TODO: XO 주소 미확정

    final xoType = _mapXoType(config.slope);
    if (xoType == null) return; // bypass

    final isHpf = config.side == FilterSide.hpf;
    final biquads = DspEngine.calculateCrossoverBiquads(config.freqHz, isHpf, xoType);

    // HP = 슬롯 0..3, LP = 슬롯 4..7 (채널 내)
    final slotBase = isHpf ? 0 : _xoSlotsPerSide;
    final chBase   = xoBase + channelIndex * _xoChStride;

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

  // ── Mute (확정 주소, DspAdapter 인터페이스 밖 — Adau1701 전용 부가 기능) ──
  /// 채널(밴드) 단위 뮤트 — Woofer=11, Tweeter=12
  Future<void> writeChannelMute(int channelIndex, bool muted) async {
    if (channelIndex >= _channelMuteAddresses.length) return;
    await _send(DspEngine.buildGainFrame(
        muted ? 0.0 : 1.0, _channelMuteAddresses[channelIndex]));
  }

  /// 출력 단위 뮤트 — 물리 출력 채널 개별 (0~3)
  Future<void> writeOutputMute(int outputIndex, bool muted) async {
    if (outputIndex >= _outputMuteAddresses.length) return;
    await _send(DspEngine.buildGainFrame(
        muted ? 0.0 : 1.0, _outputMuteAddresses[outputIndex]));
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
    const xoBase = _xoBase;
    if (xoBase == null) return; // TODO: XO 주소 미확정
    final biquads = DspEngine.calculateCrossoverBiquads(freqHz, true, XoType.bw2);
    // XO HP 슬롯의 마지막 슬롯(슬롯 3)을 서브소닉 전용으로 사용
    final addr = xoBase + channelIndex * _xoChStride + (_xoSlotsPerSide - 1) * 5;
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
