import 'dart:math';
import 'dart:typed_data';

enum FilterType { peaking, lowShelf, highShelf, lowPass, highPass, notch }

class BiquadFilter {
  final double frequency;
  final double gainDb;
  final double q;
  final FilterType type;

  const BiquadFilter({
    required this.frequency,
    required this.gainDb,
    required this.q,
    this.type = FilterType.peaking,
  });

  BiquadFilter copyWith({double? frequency, double? gainDb, double? q, FilterType? type}) =>
      BiquadFilter(
        frequency: frequency ?? this.frequency,
        gainDb: gainDb ?? this.gainDb,
        q: q ?? this.q,
        type: type ?? this.type,
      );
}

class BiquadCoefficients {
  final double b0, b1, b2, a1, a2;
  const BiquadCoefficients({
    required this.b0, required this.b1, required this.b2,
    required this.a1, required this.a2,
  });

  static const BiquadCoefficients passthrough =
      BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0);
}

class DspEngine {
  static const int sampleRate = 48000;

  // ── PEQ biquad 계산 ──────────────────────────────────────────
  static BiquadCoefficients calculate(BiquadFilter filter) {
    final w0 = 2 * pi * filter.frequency / sampleRate;
    final A = pow(10, filter.gainDb / 40).toDouble();
    final alpha = sin(w0) / (2 * filter.q);

    double b0, b1, b2, a0, a1, a2;

    switch (filter.type) {
      case FilterType.peaking:
        b0 = 1 + alpha * A;
        b1 = -2 * cos(w0);
        b2 = 1 - alpha * A;
        a0 = 1 + alpha / A;
        a1 = -2 * cos(w0);
        a2 = 1 - alpha / A;
        break;
      case FilterType.lowShelf:
        b0 = A * ((A + 1) - (A - 1) * cos(w0) + 2 * sqrt(A) * alpha);
        b1 = 2 * A * ((A - 1) - (A + 1) * cos(w0));
        b2 = A * ((A + 1) - (A - 1) * cos(w0) - 2 * sqrt(A) * alpha);
        a0 = (A + 1) + (A - 1) * cos(w0) + 2 * sqrt(A) * alpha;
        a1 = -2 * ((A - 1) + (A + 1) * cos(w0));
        a2 = (A + 1) + (A - 1) * cos(w0) - 2 * sqrt(A) * alpha;
        break;
      case FilterType.highShelf:
        b0 = A * ((A + 1) + (A - 1) * cos(w0) + 2 * sqrt(A) * alpha);
        b1 = -2 * A * ((A - 1) + (A + 1) * cos(w0));
        b2 = A * ((A + 1) + (A - 1) * cos(w0) - 2 * sqrt(A) * alpha);
        a0 = (A + 1) - (A - 1) * cos(w0) + 2 * sqrt(A) * alpha;
        a1 = 2 * ((A - 1) - (A + 1) * cos(w0));
        a2 = (A + 1) - (A - 1) * cos(w0) - 2 * sqrt(A) * alpha;
        break;
      case FilterType.lowPass:
        b0 = (1 - cos(w0)) / 2;
        b1 = 1 - cos(w0);
        b2 = (1 - cos(w0)) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cos(w0);
        a2 = 1 - alpha;
        break;
      case FilterType.highPass:
        b0 = (1 + cos(w0)) / 2;
        b1 = -(1 + cos(w0));
        b2 = (1 + cos(w0)) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cos(w0);
        a2 = 1 - alpha;
        break;
      case FilterType.notch:
        b0 = 1;
        b1 = -2 * cos(w0);
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cos(w0);
        a2 = 1 - alpha;
        break;
    }

    return BiquadCoefficients(
      b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
      a1: -(a1 / a0), a2: -(a2 / a0),
    );
  }

  // ── 크로스오버 biquad 계산 ────────────────────────────────────
  //
  // 반환값: 직렬 연결할 BiquadCoefficients 목록
  //   butterworth12 → 1개 (Q=0.7071)
  //   butterworth24 → 2개 (BW4: Q=0.5412, Q=1.3066)
  //   lr12          → 1개 (LR2: Q=0.5)
  //   lr24          → 2개 (LR4: Q=0.7071 × 2)
  //   lr48          → 4개 (LR8: Q=0.5412, Q=1.3066 × 2)
  static List<BiquadCoefficients> calculateCrossoverBiquads(
      double freqHz, bool isHpf, XoType type) {
    switch (type) {
      case XoType.bw2:
        return [_xoBiquad(freqHz, isHpf, 0.7071)];
      case XoType.bw4:
        // 4th-order Butterworth pole Q values
        return [
          _xoBiquad(freqHz, isHpf, 0.5412),
          _xoBiquad(freqHz, isHpf, 1.3066),
        ];
      case XoType.lr2:
        // LR2 = Q=0.5 biquad (approximation of cascaded 1st-order BW)
        return [_xoBiquad(freqHz, isHpf, 0.5)];
      case XoType.lr4:
        // LR4 = 2× BW2 (Q=0.7071) at same fc
        return [
          _xoBiquad(freqHz, isHpf, 0.7071),
          _xoBiquad(freqHz, isHpf, 0.7071),
        ];
      case XoType.lr8:
        // LR8 = 4× BW2 (2 sets of BW4 poles)
        return [
          _xoBiquad(freqHz, isHpf, 0.5412),
          _xoBiquad(freqHz, isHpf, 1.3066),
          _xoBiquad(freqHz, isHpf, 0.5412),
          _xoBiquad(freqHz, isHpf, 1.3066),
        ];
    }
  }

  static BiquadCoefficients _xoBiquad(double freqHz, bool isHpf, double q) {
    final w0 = 2 * pi * freqHz / sampleRate;
    final alpha = sin(w0) / (2 * q);
    final cosW = cos(w0);
    double b0, b1, b2;
    if (isHpf) {
      b0 = (1 + cosW) / 2;
      b1 = -(1 + cosW);
      b2 = (1 + cosW) / 2;
    } else {
      b0 = (1 - cosW) / 2;
      b1 = 1 - cosW;
      b2 = (1 - cosW) / 2;
    }
    final a0 = 1 + alpha;
    final a1 = -2 * cosW;
    final a2 = 1 - alpha;
    return BiquadCoefficients(
      b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
      a1: -(a1 / a0), a2: -(a2 / a0),
    );
  }

  // ── 주파수 응답 (Bode plot용) ─────────────────────────────────
  static List<Map<String, double>> frequencyResponse(
      List<BiquadFilter> filters, {
      int points = 200,
      List<BiquadCoefficients>? extraCoeffs, // 크로스오버 등 추가 계수
  }) {
    final result = <Map<String, double>>[];
    for (int i = 0; i < points; i++) {
      final freq = 20 * pow(1000, i / (points - 1)).toDouble();
      double totalDb = 0;

      for (final filter in filters) {
        totalDb += _evalBiquad(calculate(filter), freq);
      }
      for (final coeff in (extraCoeffs ?? [])) {
        totalDb += _evalBiquad(coeff, freq);
      }

      result.add({'frequency': freq, 'db': totalDb});
    }
    return result;
  }

  static double _evalBiquad(BiquadCoefficients c, double freq) {
    final w = 2 * pi * freq / sampleRate;
    final cosW  = cos(w);  final sinW  = sin(w);
    final cos2W = cos(2 * w); final sin2W = sin(2 * w);
    final numRe = c.b0 + c.b1 * cosW + c.b2 * cos2W;
    final numIm = c.b1 * sinW + c.b2 * sin2W;
    final denRe = 1 - c.a1 * cosW - c.a2 * cos2W;
    final denIm = c.a1 * sinW + c.a2 * sin2W;
    final num = sqrt(numRe * numRe + numIm * numIm);
    final den = sqrt(denRe * denRe + denIm * denIm);
    if (den == 0) return 0;
    return 20 * log(num / den) / ln10;
  }

  // ── ADAU1701 고정소수점 ────────────────────────────────────────

  // 5.23 — PEQ 계수, gain 선형값
  static int toFixed523(double value) {
    final clamped = value.clamp(-16.0, 15.9999999);
    int fixedVal = (clamped * 8388608).round();
    if (fixedVal < 0) fixedVal = (0x10000000 + fixedVal) & 0x0FFFFFFF;
    return fixedVal;
  }

  // 28.0 — delay 샘플 카운트 (정수)
  static int toSampleCount(double delayMs) =>
      (delayMs / 1000.0 * sampleRate).round().clamp(0, 0xFFFF);

  static List<int> toBytes4(int value) => [
    (value >> 24) & 0xFF, (value >> 16) & 0xFF,
    (value >> 8) & 0xFF, value & 0xFF,
  ];

  // ── BLE/UART 프레임 빌더 ──────────────────────────────────────
  //
  // [0xAA][addr_hi][addr_lo][data 20B = 5×4B][XOR][0x55] = 27바이트
  // ADAU1701 Safeload: 5개 PRAM 워드 원자 기록

  // biquad 5계수 프레임
  static Uint8List buildBleFrame(BiquadCoefficients coeff, int pramAddr) {
    final vals = [coeff.b0, coeff.b1, coeff.b2, coeff.a1, coeff.a2];
    return _buildFrame(pramAddr, vals.map(toFixed523).toList());
  }

  // gain 단일 계수 프레임 (선형 비율, 5.23)
  // addr = SigmaStudio gain 셀 주소 (TODO: .dspproj 확인)
  static Uint8List buildGainFrame(double gainLinear, int pramAddr) {
    return _buildFrame(pramAddr, [
      toFixed523(gainLinear), 0, 0, 0, 0,
    ]);
  }

  // delay 프레임 (샘플 카운트, 28.0 정수)
  // addr = SigmaStudio delay 셀 주소 (TODO: .dspproj 확인)
  static Uint8List buildDelayFrame(double delayMs, int pramAddr) {
    return _buildFrame(pramAddr, [
      toSampleCount(delayMs), 0, 0, 0, 0,
    ]);
  }

  static Uint8List _buildFrame(int pramAddr, List<int> words5) {
    final frame = Uint8List(27);
    int idx = 0;
    frame[idx++] = 0xAA;
    frame[idx++] = (pramAddr >> 8) & 0xFF;
    frame[idx++] = pramAddr & 0xFF;
    for (final w in words5) {
      for (final b in toBytes4(w)) { frame[idx++] = b; }
    }
    int checksum = 0;
    for (int i = 0; i < 23; i++) { checksum ^= frame[i]; }
    frame[idx++] = checksum;
    frame[idx++] = 0x55;
    return frame;
  }
}

// ── 크로스오버 필터 타입 ─────────────────────────────────────────
// dsp_state.dart의 CrossoverType과 분리해 DspEngine을 독립적으로 유지
enum XoType { bw2, bw4, lr2, lr4, lr8 }

// ── T/S 기반 안전범위 ─────────────────────────────────────────
class SafetyProfile {
  final double hpfFreq;
  final double maxBassBoost;
  final double gainOffset;

  const SafetyProfile({
    required this.hpfFreq,
    required this.maxBassBoost,
    required this.gainOffset,
  });

  static SafetyProfile fromTs({
    required double fs,
    required double xmax,
    required double sensitivity,
  }) {
    return SafetyProfile(
      hpfFreq: fs * 0.85,
      maxBassBoost: xmax >= 10 ? 6.0 : xmax >= 6 ? 4.0 : xmax >= 3 ? 2.0 : 0.0,
      gainOffset: sensitivity - 85.0,
    );
  }

  double clampBassBoost(double gainDb, double freq) {
    if (freq < 200 && gainDb > maxBassBoost) return maxBassBoost;
    return gainDb;
  }
}
