import 'dart:math';
import 'dart:typed_data';
import 'dsp_adapter.dart';
import '../dsp_engine.dart';

/// ADAU1466 + CS42448 어댑터 (tunai_pro)
///
/// 채널 인덱스 (DspState.outputs 순서와 일치):
///   0: TWE L  1: TWE R  2: MID L  3: MID R  4: WOO L  5: WOO R
///
/// SigmaStudio PRAM 주소 (TUNAI_ADAU1466_v0_9_Final export 확정, 2026-08-06):
///
///   Master Vol: TUNAI_MASTER_VOL_R=100, TUNAI_MASTER_VOL_L=103 (슬루=TARGET+1).
///               5.27 fixed-point (선형값). 이전 펌웨어의 545/548과 완전히 다름.
///
///   Gain(ch trim): SINGLE1 블록, ch0~5 = 952,955,964,967,970,973 (slew=+1).
///                  5.27 fixed-point. 채널 순서는 PARAM.h 블록 배치 기준 가정
///                  — 실기기에서 채널별 값 입력 후 소리로 검증 필요.
///
///   Delay: ch0~5 가정 주소 = 960,961,962,1029,1030,1031 (PARAM.h 순).
///          7번째 블록(DELAY2_2=1032)은 sub/mono 전용 추정 — 미사용.
///          채널 순서 실기기 검증 필요.
///
///   PEQ (v0.9부터 채널별 독립 블록, 10밴드 × 5워드 각):
///     ch0 TWE_L: base=588  (L_TWEETER_PEQ20_BAND, 588~637)
///     ch1 TWE_R: base=688  (R_TWEETER_PEQ20_BAND, 688~737)
///     ch2 MID_L: base=806  (L_MID_PEQ_20B,        806~855)
///     ch3 MID_R: base=756  (R_MID_PEQ_20B,         756~805)
///     ch4 WOO_L: base=538  (L_WOOFER_PEQ20_BAND,  538~587)
///     ch5 WOO_R: base=638  (R_WOOFER_PEQ20_BAND,  638~687)
///     밴드n 주소 = base + n×5. 계수 순서 B2,B1,B0,A2,A1.
///
///   XO (SafeLoad 방식 — experimentalXoWriteEnabled=false로 잠금):
///     LPF_2 target=24973  HPF_2 target=24978  HPF_3 target=24983
///     LPF_4 target=24988  HPF_4 target=24993  HPF_5 target=24998
///     LPF_3 target=25208  LPF_5 target=25213
///     채널별 XO 블록 대응은 SigmaStudio 라우팅 도면 확인 후 매핑 예정.
///
///   SafeLoad 레지스터 (PARAM.h 확정):
///     DATA0~4=24576~24580, ADDRESS=24581, NUM_LOWER=24582, NUM_UPPER=24583.
///
/// 고정소수점: ADAU1466 = 5.27 (ADAU1701의 5.23과 다름)
class Adau1466Adapter implements DspAdapter {
  final RawWriteFn _send;

  /// XO SafeLoad 프로토콜이 실기기 검증되지 않았다 — 항상 false로 유지할 것.
  /// true로 바꾸면 미검증 SafeLoad 시퀀스가 전송된다.
  static bool experimentalXoWriteEnabled = false;

  static const int _peqBands = 10; // v0.9: 채널별 10밴드 (이전 15에서 변경)

  // 채널별 PEQ 블록 기본 주소 (ch0~ch5: TWE_L,TWE_R,MID_L,MID_R,WOO_L,WOO_R)
  // PARAM.h에서 블록 이름으로 확정. 밴드n = base + n×5.
  static const List<int> _peqBases = [588, 688, 806, 756, 538, 638];

  // ── Gain (SINGLE1 ch trim, ch0~ch5) ──────────────────────────
  // PARAM.h SINGLE1 블록 주소 순서 기반 — 채널 대응 실기기 검증 필요
  static const List<int> _gainAddresses = [952, 955, 964, 967, 970, 973];

  // ── Delay (ch0~ch5 가정, ch 대응 실기기 검증 필요) ──────────────
  static const List<int> _delayAddresses = [960, 961, 962, 1029, 1030, 1031];

  // ── SafeLoad 레지스터 (PARAM.h 확정) ─────────────────────────
  static const int _safeloadData0   = 24576; // DATA0~4: 24576~24580
  static const int _safeloadAddress = 24581; // 목표 주소 레지스터
  static const int _safeloadNum     = 24582; // 개수 레지스터 — 쓰면 트리거

  // ── XO SafeLoad 대상 주소 (PARAM.h 확정, 채널 매핑 미확인) ──────
  // 순서: LPF_2, HPF_2, HPF_3, LPF_4, HPF_4, HPF_5, LPF_3, LPF_5
  // 채널별 HPF/LPF 대응은 SigmaStudio 라우팅 확인 후 2D 배열로 교체 예정
  static const List<int> _xoTargets = [
    24973, 24978, 24983, 24988, 24993, 24998, 25208, 25213,
  ];

  Adau1466Adapter({required RawWriteFn send}) : _send = send;

  // ── Gain ─────────────────────────────────────────────────────
  // Volume 셀: 5.27 선형값 1워드 — 검증됨, 변경 없음
  @override
  Future<void> writeGain(int channelIndex, double gainDb) async {
    if (channelIndex >= _gainAddresses.length) return;
    final linear = pow(10.0, gainDb / 20.0).toDouble();
    await _send(DspEngine.buildGainFrame1466(linear, _gainAddresses[channelIndex]));
  }

  // ── Delay ────────────────────────────────────────────────────
  // 28.0 샘플 카운트 — 주소 확정, 채널 순서는 Volume과 동일 가정(실기기 확인 필요)
  @override
  Future<void> writeDelay(int channelIndex, double delayMs) async {
    if (channelIndex >= _delayAddresses.length) return;
    await _send(DspEngine.buildDelayFrame(delayMs, _delayAddresses[channelIndex]));
  }

  // ── PEQ 밴드 (채널별 독립 블록, 10밴드) ─────────────────────────
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    if (channelIndex >= _peqBases.length) return;
    assert(bandIndex < _peqBands);
    final addr = _peqBases[channelIndex] + bandIndex * 5;
    await _send(DspEngine.buildBleFrame1466(
      BiquadCoefficients(b0: coeffs.b2, b1: coeffs.b1, b2: coeffs.b0,
                         a1: coeffs.a2, a2: coeffs.a1),
      addr,
    ));
  }

  // ── 크로스오버 (SafeLoad 스텁 — 기본 잠금) ──────────────────────
  // XO 블록↔채널 매핑이 확인되지 않았다. experimentalXoWriteEnabled=false 유지.
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    if (!experimentalXoWriteEnabled) return;

    final xoType = _mapXoType(config.slope);
    if (xoType == null) return;

    final isHpf = config.side == FilterSide.hpf;
    final biquads = DspEngine.calculateCrossoverBiquads(config.freqHz, isHpf, xoType);
    if (biquads.length != 1) return;

    // TODO: 채널별 XO 블록 매핑 확인 후 2D 배열 인덱스로 교체
    // 임시: HPF → _xoTargets[1](HPF_2), LPF → _xoTargets[0](LPF_2) (ch 무관)
    final targetAddr = isHpf ? _xoTargets[1] : _xoTargets[0];
    final c = biquads[0];
    await _writeSafeload(targetAddr, BiquadCoefficients(
      b0: c.b2, b1: c.b1, b2: c.b0, a1: c.a2, a2: c.a1,
    ));
  }

  // ── 서브소닉 HPF ─────────────────────────────────────────────
  // 신 XO 구조엔 채널당 여분 슬롯이 없음(HPF target 하나뿐, 그마저 SafeLoad
  // 미검증) — 별도 subsonic 슬롯 없이 no-op 유지
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {}

  // ── SafeLoad 쓰기 (표준 ADI SafeLoad 레지스터 배치 가정 — 미검증) ──
  // SAFELOAD_DATA0~4에 계수 5워드, SAFELOAD_ADDRESS에 목표 주소, SAFELOAD_NUM에
  // 개수(5)를 쓰면 하드웨어가 원자적으로 타겟에 반영한다는 것이 일반적인 ADI
  // SafeLoad 동작이나, 이 프로젝트의 실제 레지스터 배치와 정확히 일치하는지는
  // 실기기로 확인되지 않았다.
  Future<void> _writeSafeload(int targetAddr, BiquadCoefficients coeff) async {
    final words = [coeff.b0, coeff.b1, coeff.b2, coeff.a1, coeff.a2];
    for (var i = 0; i < words.length; i++) {
      await _send(DspEngine.buildGainFrame1466(words[i], _safeloadData0 + i));
    }
    await _send(_buildRawIntFrame(_safeloadAddress, targetAddr));
    await _send(_buildRawIntFrame(_safeloadNum, words.length));
  }

  // ADDRESS/NUM 레지스터처럼 계수가 아닌 정수 값을 쓸 때 사용
  Uint8List _buildRawIntFrame(int pramAddr, int value) {
    final frame = Uint8List(27);
    var idx = 0;
    frame[idx++] = 0xAA;
    frame[idx++] = (pramAddr >> 8) & 0xFF;
    frame[idx++] = pramAddr & 0xFF;
    for (final w in [value, 0, 0, 0, 0]) {
      for (final b in DspEngine.toBytes4(w)) { frame[idx++] = b; }
    }
    var checksum = 0;
    for (var i = 0; i < 23; i++) { checksum ^= frame[i]; }
    frame[idx++] = checksum;
    frame[idx++] = 0x55;
    return frame;
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
