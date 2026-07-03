import 'dart:math';
import 'dsp_adapter.dart';
import '../dsp_engine.dart';

/// ADAU1701 어댑터 (tunai_pro UART 버전)
///
/// 프레임: [0xAA][Addr 2B][Data 20B = 5×4B][XOR][0x55] = 27바이트
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
///   PEQ  : 이 펌웨어에는 별도의 PEQ 모듈이 없다 — writeBiquad는 no-op.
///          이전에 peqBase=14로 가정했던 것은 오판이었다. 실제로는 addr 14~799가
///          전부 아래 XO 캐스케이드 영역이라 잘못 쓰면 크로스오버가 깨진다.
///   XO   : addr 14~799 = 2차 필터 캐스케이드 8개(스테레오 페어 4쌍) + 210~211 믹서:
///     Filter1_4  14~111    Filter1_9  112~209   (98워드씩)
///     2XMixer1_3 210~211 (XO 믹스 포인트)
///     Filter1_10 212~309   Filter1_11 310~407
///     Filter1_5  408~505   Filter1_8  506~603
///     Filter1_6  604~701   Filter1_7  702~799
///     블록 → (채널, HPF/LPF) 매핑과 블록 내부 스테이지 오프셋은 아직 미확정 —
///     SigmaStudio .dspproj를 열어 블록 라벨을 육안 확인해야 한다(Boot Camp
///     Windows). 확인 전까지 writeCrossover/writeSubsonicFilter는 no-op.
///
///   참고용(미사용): SW vol1=800, Gain3/Gain1=801~804, Inv1_10/Inv1_9(극성)=810/811
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _send;

  // ── XO 필터 블록 (확정 주소, 채널/필터타입 매핑 미확정) ────────────
  // Filter1_4, 1_9, 1_10, 1_11, 1_5, 1_8, 1_6, 1_7 순서, 각 98워드 연속 배치
  static const List<int> _xoFilterBlockBase = [
    14, 112, 212, 310, 408, 506, 604, 702,
  ];
  static const int _xoMixerBase = 210; // 2XMixer1_3

  // 채널 → XO 필터 블록 인덱스 — TODO: SigmaStudio .dspproj 육안 확인 후 채우기
  static int? _xoBlockIndex(int channelIndex, FilterSide side) {
    assert(_xoFilterBlockBase.length == 8 && _xoMixerBase == 210);
    return null; // 매핑 미확정
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
  // 이 펌웨어에는 PEQ 모듈이 없음(addr 14~799는 전부 XO 캐스케이드) — no-op.
  // 향후 PEQ가 필요하면 SigmaStudio에서 PEQ 블록을 추가해 펌웨어를 재컴파일해야 한다.
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {}

  // ── 크로스오버 ───────────────────────────────────────────────
  // 블록→(채널,HPF/LPF) 매핑과 블록 내부 스테이지 오프셋 미확정 — SigmaStudio
  // .dspproj 육안 확인 전까지 no-op.
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    final blockIndex = _xoBlockIndex(channelIndex, config.side);
    if (blockIndex == null) return; // TODO: 블록 매핑 미확정
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
  // XO 블록 매핑 미확정 — writeCrossover와 동일 사유로 no-op.
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {
    final blockIndex = _xoBlockIndex(channelIndex, FilterSide.hpf);
    if (blockIndex == null) return; // TODO: 블록 매핑 미확정
  }
}
