import 'dart:math';
import 'dsp_adapter.dart';
import '../dsp_engine.dart';

/// ADAU1701 어댑터 (tunai_pro UART 버전)
///
/// 프레임: [0xAA][Addr 2B][Data 20B = 5×4B][XOR][0x55] = 27바이트
///
/// 채널 인덱스: 0=Woofer(스테레오 링크, L/R 동시 write), 1=Tweeter(스테레오 링크)
/// — Gain/Mute와 동일한 2채널 모델(모바일은 L/R 분리 4채널, Pro는 링크된 2채널)
///
/// ▼ PRAM 주소맵 — JAB4_DSP_Firmware_Hardware_SouceCode_V112_2021_01_12_IC_1_PARAM.h
/// (SigmaStudio export 원본 대조 확정, 2026-07)
///   GAIN : ExtSWGainDB 셀, 5.23 선형값 1워드 — 변경 없음
///     ch0 Woofer  = 7  (ExtSWGainDB2step_20, "Vol")
///     ch1 Tweeter = 6  (ExtSWGainDB3step_19, "Vol_2")
///   DELAY: 현 펌웨어에 Delay 블록 없음 — 추가+재컴파일 필요, 현재 미지원 (변경 없음)
///   MUTE : 채널(밴드) 뮤트 — Woofer=11, Tweeter=12 (변경 없음)
///          출력 뮤트 — 물리 출력 채널별 개별: out0=805, out1=806, out2=807, out3=808 (변경 없음)
///
///   PEQ  : 이 스키매틱엔 PEQ 모듈이 없음 — writeBiquad는 no-op. 단, Miumax 공식
///          PC UI 화면에는 채널별 10-Band EQ가 표시돼 있어 다른 펌웨어 버전이
///          존재할 가능성이 있음 — 미해결로 남김(HANDOFF.md 참고)
///
/// XO 필터 구조 (SigmaStudio 스키매틱 직접 확인, 2026-07-04):
/// 2웨이 크로스오버, 물리 DAC 4채널 각각 HPF 블록 → LPF 블록 순으로 캐스케이드:
///
///   DAC0 (Tweeter A): Filter1_4  (14~111,  HPF) → Filter1_11 (310~407, LPF@20kHz≈통과)
///   DAC1 (Tweeter B): Filter1_9  (112~209, HPF) → Filter1_10 (212~309, LPF@20kHz≈통과)
///   DAC2 (Woofer A):  Filter1_5  (408~505, HPF@150Hz≈무시) → Filter1_6 (604~701, LPF)
///   DAC3 (Woofer B):  Filter1_8  (506~603, HPF@150Hz≈무시) → Filter1_7 (702~799, LPF)
///
/// 즉 트위터 체인은 HPF가, 우퍼 체인은 LPF가 실질적 크로스오버 지점이다(반대쪽은
/// 스키매틱 기본값이 사실상 통과/무시로 설정돼 있을 뿐, 실제로 쓸 수 있는 필터임).
/// Pro는 채널당 L/R 두 DAC 모두에 동일 설정을 write한다(_xoBlockBase 참고).
/// 2XMixer1_3(210~211)은 참고용(미사용) — 현재 writeCrossover 대상 아님.
///
/// **각 98워드 블록 내부의 정확한 스테이지 오프셋(주파수/Q가 몇 번째 워드인지)과
/// 계수 fixed-point 포맷은 실측 write 캡처로 검증되지 않았다.** 아래 구현은
/// "블록 시작 = 1번째 스테이지(B2,B1,B0,A2,A1 5워드)"라는 가장 보수적인 가정을
/// 사용하며, 실기기 검증 전까지 [Adau1701Adapter.experimentalXoWriteEnabled]가
/// 기본 false라 실제로는 아무 것도 전송되지 않는다. 상위 레이어에서 "실험적 기능"
/// 동의를 받은 뒤에만 명시적으로 true로 설정할 것.
///
///   DELAY: 이 스키매틱엔 Delay 블록이 안 보임(Miumax UI엔 있었음 — 별도 확인
///          필요, HANDOFF.md 참고)
///
///   참고용(미사용): SW vol1=800, Gain3/Gain1=801~804, Inv1_10/Inv1_9(극성)=810/811
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _send;

  /// 실기기 write 캡처로 위 오프셋/포맷을 검증하기 전까지 안전장치로 기본 false.
  /// true가 되기 전엔 writeCrossover가 계산만 하고 아무 것도 전송하지 않는다.
  /// UI 쪽 "실험적 기능" 동의 토글은 이번 세션 스코프 밖 — 상위 레이어에서 옵트인할 것.
  static bool experimentalXoWriteEnabled = false;

  // 채널(0=Woofer, 1=Tweeter, 스테레오 링크) → (HPF 블록들, LPF 블록들) 주소.
  // 각 채널은 L/R 두 DAC를 갖고 있어 동일 설정을 두 주소 모두에 write한다.
  static const List<({List<int> hpf, List<int> lpf})> _xoBlockBase = [
    (hpf: [408, 506], lpf: [604, 702]), // ch0 Woofer  = DAC2+DAC3: Filter1_5/1_8 → Filter1_6/1_7
    (hpf: [14, 112],  lpf: [310, 212]), // ch1 Tweeter = DAC0+DAC1: Filter1_4/1_9 → Filter1_11/1_10
  ];

  static List<int> _xoBlockAddrs(int channelIndex, FilterSide side) {
    final entry = _xoBlockBase[channelIndex];
    return side == FilterSide.hpf ? entry.hpf : entry.lpf;
  }

  // Gain 셀 PRAM 주소 — ch0/ch1 순서가 비연속이므로 배열로 관리 (변경 없음)
  // SigmaStudio 프로젝트(.dspproj)가 변경되면 재확인 필요
  static const List<int> _gainAddresses = [7, 6]; // [ch0 Woofer=Vol, ch1 Tweeter=Vol_2]

  // Delay: 현 펌웨어에 블록 없음 → 미지원 (변경 없음)
  static const int _delayBase = 0x0000; // Delay 블록 추가+재컴파일 전까지 미사용

  // 채널(밴드) 뮤트 주소 — Woofer=11, Tweeter=12 (변경 없음)
  static const List<int> _channelMuteAddresses = [11, 12];

  // 출력 뮤트 주소 — 물리 출력 채널별 개별 (변경 없음)
  static const List<int> _outputMuteAddresses = [805, 806, 807, 808];

  Adau1701Adapter({required RawWriteFn send}) : _send = send;

  // ── PEQ ──────────────────────────────────────────────────────
  // 이 스키매틱엔 PEQ 모듈이 없음 — no-op. (Miumax UI의 10-Band EQ 표시는
  // 별도 펌웨어 버전 가능성이 있어 미해결로 남김 — HANDOFF.md 참고)
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {}

  // ── 크로스오버 ───────────────────────────────────────────────
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    if (!experimentalXoWriteEnabled) return; // TODO: 실기기 검증 후 기본값 재검토

    final xoType = _mapXoType(config.slope);
    if (xoType == null) return; // bypass

    final isHpf = config.side == FilterSide.hpf;
    final biquads = DspEngine.calculateCrossoverBiquads(config.freqHz, isHpf, xoType);
    final addrs = _xoBlockAddrs(channelIndex, config.side);

    for (final base in addrs) {
      for (var i = 0; i < biquads.length; i++) {
        final c = biquads[i];
        // SigmaStudio 2nd-order filter 표준 계수 순서: B2,B1,B0,A2,A1 (fixed-point
        // 포맷은 기존 5.23 가정 유지 — 재확인 필요)
        await _send(DspEngine.buildBleFrame(
          BiquadCoefficients(b0: c.b2, b1: c.b1, b2: c.b0, a1: c.a2, a2: c.a1),
          base + i * 5,
        ));
      }
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
  // 이 구조엔 별도 subsonic 개념이 없음(Woofer 채널의 HPF 블록이 150Hz 부근
  // 사실상 무시 상태로 확인됐지만, 정확한 오프셋/기본값이 실측 검증되지 않아
  // 이번 세션에선 그대로 no-op 유지)
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {}

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
