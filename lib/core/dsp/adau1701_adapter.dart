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
///   GAIN : ExtSWGainDB 셀, 5.23 선형값 1워드 — 변경 없음
///     ch0 Woofer  = 7  (ExtSWGainDB2step_20, "Vol")
///     ch1 Tweeter = 6  (ExtSWGainDB3step_19, "Vol_2")
///   DELAY: 이 펌웨어에 Delay 블록 없음 — 미지원 (변경 없음)
///   MUTE : 채널(밴드) 뮤트 — Woofer on/off=11,step=12 (변경 없음)
///          출력 뮤트 — Mute1=805~806, Mute0=807~808 (변경 없음)
///
///   PEQ  : 이 신 펌웨어에도 PEQ 모듈이 없음 — writeBiquad는 no-op. 단, Miumax 공식
///          PC UI 화면에는 채널별 10-Band EQ가 표시돼 있어 다른 펌웨어 버전이
///          존재할 가능성이 있음 — 미해결로 남김(HANDOFF.md 참고)
///
/// XO 필터 구조 — 신 펌웨어(2026-07-04 재컴파일, 실제 export .h 기준 확정):
/// 기존 "General 2nd Order w var Param/Lookup/Slew"(96워드 lookup) 필터를 표준
/// "General (2nd order)"(5워드 biquad) 필터로 교체. 2웨이 크로스오버, 물리 DAC
/// 4채널 각각 HPF 블록 → LPF 블록(각 5워드, B0/B1/B2/A0/A1):
///
///   DAC0 (Tweeter A): GenFilter1   (41~45, HPF) → GenFilter1_5 (46~50, LPF)
///   DAC1 (Tweeter B): GenFilter1_2 (16~20, HPF) → GenFilter1_6 (26~30, LPF)
///   DAC2 (Woofer A):  GenFilter1_3 (21~25, HPF) → GenFilter1_7 (31~35, LPF)
///   DAC3 (Woofer B):  GenFilter1_4 (36~40, HPF) → GenFilter1_8 (51~55, LPF)
///
/// 트위터 체인은 HPF가, 우퍼 체인은 LPF가 실질적 크로스오버 지점이다. Pro는
/// 채널당 L/R 두 DAC 모두에 동일 설정을 write한다(_xoBlockBase 참고).
///
/// **각 필터 블록은 정확히 5워드(2차 biquad 1스테이지)뿐이다** — 이전 펌웨어의
/// 98워드 cascade와 달리 스테이지가 하나뿐이라, 다단 cascade가 필요한 슬로프
/// (bw4/lr4/lr8, 24dB/oct 이상)는 이 하드웨어로 구현 불가하다. 지원 가능한
/// 최대 슬로프는 bw2/lr2(12dB/oct, 1스테이지)뿐 — writeCrossover는 슬로프가
/// 2스테이지 이상을 요구하면 잘못된(더 얕은) 응답을 보내는 대신 아무 것도
/// 쓰지 않는다.
///
/// 계수 순서는 B0,B1,B2,A0,A1(SigmaStudio "General 2nd order filter" 표준
/// 파라미터명 — A0/A1은 DspEngine의 a1/a2와 동일한 자리, 0-index 명명 차이일
/// 뿐) — BiquadCoefficients(b0,b1,b2,a1,a2) 그대로 write하면 된다(재배열 불필요).
/// Fixed-point는 ADAU1701 표준 5.23 가정 유지 — 이번 세션에서 실측 재확인은
/// 안 됐으니 실기기 테스트 시 저볼륨으로 시작할 것.
///
/// [experimentalXoWriteEnabled] 기본 true로 전환(신 펌웨어 주소/포맷이 실측
/// export .h 기준으로 확정됐다고 판단) — 단 **이 신 펌웨어가 아직 실기기에
/// 플래시되지 않았을 수 있다.** 실기기 테스트 전 반드시 SigmaStudio로 신
/// 펌웨어를 보드에 플래시할 것(HANDOFF.md 참고).
///
///   참고용(미사용): I2C 주소=0x34, Inv1_10/Inv1_9(극성)=810/811
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _send;

  /// 신 펌웨어(GenFilter, 5워드 표준 biquad) 주소맵이 실제 export .h 기준으로
  /// 확정돼 기본 true로 전환. 신 펌웨어가 보드에 아직 플래시되지 않았다면
  /// writeCrossover가 잘못된 주소에 값을 쓰게 되므로, 실기기 테스트 전 반드시
  /// SigmaStudio로 신 펌웨어를 플래시할 것.
  static bool experimentalXoWriteEnabled = true;

  // 채널(0=Woofer, 1=Tweeter, 스테레오 링크) → (HPF 블록들, LPF 블록들) 주소.
  // 각 채널은 L/R 두 DAC를 갖고 있어 동일 설정을 두 주소 모두에 write한다.
  static const List<({List<int> hpf, List<int> lpf})> _xoBlockBase = [
    (hpf: [21, 36], lpf: [31, 51]), // ch0 Woofer  = DAC2+DAC3: GenFilter1_3/1_4 → GenFilter1_7/1_8
    (hpf: [41, 16], lpf: [46, 26]), // ch1 Tweeter = DAC0+DAC1: GenFilter1/1_2   → GenFilter1_5/1_6
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
  // 이 신 펌웨어에도 PEQ 모듈이 없음 — no-op. (Miumax UI의 10-Band EQ 표시는
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
    // 블록당 1스테이지(5워드)뿐 — 2스테이지 이상 필요한 슬로프(bw4/lr4/lr8)는
    // 얕은(잘못된) 응답을 보내는 대신 아무 것도 쓰지 않는다.
    if (biquads.length != 1) return;

    final c = biquads[0];
    final addrs = _xoBlockAddrs(channelIndex, config.side);

    for (final addr in addrs) {
      // SigmaStudio "General 2nd order filter" 표준 파라미터 순서: B0,B1,B2,A0,A1
      // (A0/A1은 DspEngine의 a1/a2와 동일 자리 — 재배열 불필요)
      await _send(DspEngine.buildBleFrame(
        BiquadCoefficients(b0: c.b0, b1: c.b1, b2: c.b2, a1: c.a1, a2: c.a2),
        addr,
      ));
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
  // 이 구조엔 별도 subsonic 개념이 없음 — no-op 유지
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
