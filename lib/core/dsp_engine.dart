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
}

class DspEngine {
  static const int sampleRate = 48000;

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
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: -(a1 / a0),
      a2: -(a2 / a0),
    );
  }

  // 주파수 응답 계산 (Bode plot용)
  static List<Map<String, double>> frequencyResponse(
      List<BiquadFilter> filters, {int points = 200}) {
    final result = <Map<String, double>>[];
    for (int i = 0; i < points; i++) {
      final freq = 20 * pow(1000, i / (points - 1)).toDouble();
      double totalDb = 0;
      for (final filter in filters) {
        final coeff = calculate(filter);
        final w = 2 * pi * freq / sampleRate;
        final cosW = cos(w);
        final sinW = sin(w);
        final cos2W = cos(2 * w);
        final sin2W = sin(2 * w);
        final numRe = coeff.b0 + coeff.b1 * cosW + coeff.b2 * cos2W;
        final numIm = coeff.b1 * sinW + coeff.b2 * sin2W;
        final denRe = 1 - coeff.a1 * cosW - coeff.a2 * cos2W;
        final denIm = -(-coeff.a1 * sinW - coeff.a2 * sin2W);
        final num = sqrt(numRe * numRe + numIm * numIm);
        final den = sqrt(denRe * denRe + denIm * denIm);
        if (den > 0) totalDb += 20 * log(num / den) / ln10;
      }
      result.add({'frequency': freq, 'db': totalDb});
    }
    return result;
  }

  // ADAU1701 5.23 고정소수점
  static int toFixed523(double value) {
    final clamped = value.clamp(-16.0, 15.9999999);
    int fixedVal = (clamped * 8388608).round();
    if (fixedVal < 0) fixedVal = (0x10000000 + fixedVal) & 0x0FFFFFFF;
    return fixedVal;
  }

  static List<int> toBytes4(int value) => [
    (value >> 24) & 0xFF, (value >> 16) & 0xFF,
    (value >> 8) & 0xFF, value & 0xFF,
  ];

  // BLE 27바이트 프레임
  static Uint8List buildBleFrame(BiquadCoefficients coeff, int pramAddr) {
    final frame = Uint8List(27);
    int idx = 0;
    frame[idx++] = 0xAA;
    frame[idx++] = (pramAddr >> 8) & 0xFF;
    frame[idx++] = pramAddr & 0xFF;
    for (final c in [coeff.b0, coeff.b1, coeff.b2, coeff.a1, coeff.a2]) {
      for (final b in toBytes4(toFixed523(c))) frame[idx++] = b;
    }
    int checksum = 0;
    for (int i = 0; i < 23; i++) checksum ^= frame[i];
    frame[idx++] = checksum;
    frame[idx++] = 0x55;
    return frame;
  }
}

// ── T/S 기반 안전범위 ─────────────────────────────────────

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

  /// PEQ gainDb를 Xmax 기반으로 클램핑
  double clampBassBoost(double gainDb, double freq) {
    if (freq < 200 && gainDb > maxBassBoost) return maxBassBoost;
    return gainDb;
  }
}
