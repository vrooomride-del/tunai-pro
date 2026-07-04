import 'dart:math';
import 'dart:typed_data';
import 'dsp_adapter.dart';
import '../dsp_engine.dart';

/// ADAU1466 + CS42448 어댑터 (tunai_pro)
///
/// 채널 인덱스 (DspState.outputs 순서와 일치):
///   0: TWE L  1: TWE R  2: MID L  3: MID R  4: WOO L  5: WOO R
///
/// SigmaStudio PRAM 주소 (1466_cs42448_18out_eng 실제 export 대조 확정, 2026-07-04):
///   Volume : 545, 548, 551, 554, 557, 560 (slew_mode = target+1) — 8.24 fixed, BE.
///            SPI 쓰기 검증 완료 — 변경 없음
///   Delay  : 562, 567, 563, 566, 564, 565 (ch0~5) — 정수 샘플(ms×48000/1000).
///            채널 순서는 Volume과 동일 CH0~5로 가정 — 실기기에서 채널별로 값을
///            넣어 소리로 확인 필요
///   PEQ    : base=410, 밴드n(0~14) = 410+n×5, 15밴드, addr 410~484.
///            계수 순서 B2,B1,B0,A2,A1 (ADAU1701 신 펌웨어의 B0,B1,B2,A0,A1과
///            다르니 주의). 채널별 스트라이드는 이번 export에 없음 — 현재는
///            모든 채널이 410 기준 단일 15밴드를 공유하는 것으로 처리(확인된
///            정보 그대로). 채널별 개별 PEQ가 필요하면 추가 확인 필요
///   HPF/LPF: 신규 발견 — PEQ/Delay와 구조가 전혀 다름, SafeLoad 방식 필요
///            HPF target=24873~24877(5워드), slewMode=401
///            LPF target=24878~24882(5워드), slewMode=407
///            SafeLoad 레지스터 영역 24576~24583과 인접 — 일반 write가 아니라
///            SigmaStudio SafeLoad 프로토콜(데이터→SAFELOAD_DATA0~4, 주소→
///            SAFELOAD_ADDRESS, 개수→SAFELOAD_NUM 순으로 써서 트리거)이 필요할
///            가능성이 높다. **불확실 — 실기기 테스트로 검증 전까지
///            [experimentalXoWriteEnabled]는 항상 false로 유지할 것.**
///   Mute   : 16채널, addr 1081~1096 (참고용, 미구현)
///   Compressor: addr 489~542 (범위만 확인, 세부 미매핑, 참고용)
///
/// 고정소수점: ADAU1466 = 5.27 (ADAU1701의 5.23과 다름)
class Adau1466Adapter implements DspAdapter {
  final RawWriteFn _send;

  /// HPF/LPF는 SafeLoad 프로토콜이 실기기 검증되지 않았다 — 항상 false로 유지할 것.
  /// true로 바꾸면 미검증 SafeLoad 시퀀스가 그대로 전송된다.
  static bool experimentalXoWriteEnabled = false;

  static const int _peqBands = 15;
  static const int _peqBase  = 410; // 확정 — 채널별 스트라이드 미확인

  // ── Volume 셀 PRAM 주소 (ch0~ch5) ─────────────────────────────
  // SigmaStudio SPI 쓰기 검증 완료 — 변경 없음
  static const List<int> _gainAddresses = [545, 548, 551, 554, 557, 560];

  // ── Delay 셀 PRAM 주소 (ch0~ch5, 확정) ─────────────────────────
  // Volume과 동일 CH0~5 순서로 가정 — 실기기에서 채널별 소리 확인 필요
  static const List<int> _delayAddresses = [562, 567, 563, 566, 564, 565];

  // ── HPF/LPF SafeLoad 대상 주소 (신규 발견, 미검증) ─────────────
  static const int _hpfTargetAddr = 24873; // 5워드, slewMode=401
  static const int _lpfTargetAddr = 24878; // 5워드, slewMode=407

  // SafeLoad 레지스터 배치 — 표준 ADI SafeLoad 규약(DATA0~4/ADDRESS/NUM)을
  // 가정한 것일 뿐, 이 프로젝트의 실제 24576~24583 배치와 일치하는지는
  // 실기기로 확인되지 않았다.
  static const int _safeloadData0   = 24576; // SAFELOAD_DATA0~4 (24576~24580, 가정)
  static const int _safeloadAddress = 24581; // 목표 주소 레지스터 (가정)
  static const int _safeloadNum     = 24582; // 개수 레지스터 — 쓰면 트리거 (가정)

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

  // ── PEQ 밴드 (확정 주소, 채널 스트라이드 미확인) ────────────────
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    assert(bandIndex < _peqBands);
    // TODO: 채널별 PEQ 오프셋 미확인 — 현재 모든 채널이 410 기준 단일 15밴드를 공유
    final addr = _peqBase + bandIndex * 5;
    await _send(DspEngine.buildBleFrame1466(
      BiquadCoefficients(b0: coeffs.b2, b1: coeffs.b1, b2: coeffs.b0,
                         a1: coeffs.a2, a2: coeffs.a1),
      addr,
    ));
  }

  // ── 크로스오버 (SafeLoad 스텁 — 기본 잠금) ──────────────────────
  // SafeLoad 프로토콜이 실기기 검증되지 않아 experimentalXoWriteEnabled가
  // false인 동안은 계산만 하고 아무 것도 전송하지 않는다.
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    if (!experimentalXoWriteEnabled) return; // TODO: SafeLoad 실기기 검증 전까지 잠금

    final xoType = _mapXoType(config.slope);
    if (xoType == null) return;

    final isHpf = config.side == FilterSide.hpf;
    final biquads = DspEngine.calculateCrossoverBiquads(config.freqHz, isHpf, xoType);
    if (biquads.length != 1) return; // target당 5워드(1스테이지)뿐 — 이상 슬로프 미지원

    final targetAddr = isHpf ? _hpfTargetAddr : _lpfTargetAddr;
    final c = biquads[0];
    // PEQ와 동일한 계수 순서(B2,B1,B0,A2,A1)를 가정 — XO 자체는 별도 확인 안 됨
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

  // 정수 1워드를 그대로 싣는 프레임(고정소수점 변환 없음) — SafeLoad의
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
