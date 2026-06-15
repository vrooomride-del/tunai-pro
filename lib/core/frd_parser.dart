import 'dart:math';

/// FRD 포인트 (주파수 + SPL dB + 위상 도)
class FrdPoint {
  final double frequency;
  final double spl;
  final double phase; // 도(degree)

  const FrdPoint({required this.frequency, required this.spl, this.phase = 0.0});
}

/// ZMA 포인트 (주파수 + 임피던스 Ω + 위상 도)
class ZmaPoint {
  final double frequency;
  final double impedance;
  final double phase;

  const ZmaPoint({required this.frequency, required this.impedance, this.phase = 0.0});
}

/// T/S 파라미터 (ZMA에서 역산)
class TsParameters {
  final double fs;          // 공진 주파수 (Hz)
  final double re;          // DC 저항 (Ω)
  final double qes;         // 전기적 Q
  final double qms;         // 기계적 Q
  final double qts;         // 총 Q
  final double vas;         // 등가 체적 (L) - 별도 입력 필요
  final double zmax;        // 최대 임피던스 (Ω)

  const TsParameters({
    required this.fs, required this.re, required this.qes,
    required this.qms, required this.qts, required this.zmax,
    this.vas = 0.0,
  });

  @override
  String toString() =>
      'Fs=${fs.toStringAsFixed(1)}Hz Re=${re.toStringAsFixed(2)}Ω '
      'Qts=${qts.toStringAsFixed(3)} Qes=${qes.toStringAsFixed(3)} Qms=${qms.toStringAsFixed(2)}';
}

class FrdParser {
  /// FRD 파일 파싱
  /// 형식: "주파수 SPL [위상]" (공백/탭 구분, # 주석)
  static List<FrdPoint> parseFrd(String content) {
    final points = <FrdPoint>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('*')) continue;
      final parts = trimmed.split(RegExp(r'[\s,\t]+'));
      if (parts.length < 2) continue;
      final freq = double.tryParse(parts[0]);
      final spl = double.tryParse(parts[1]);
      if (freq == null || spl == null) continue;
      final phase = parts.length >= 3 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0;
      points.add(FrdPoint(frequency: freq, spl: spl, phase: phase));
    }
    points.sort((a, b) => a.frequency.compareTo(b.frequency));
    return points;
  }

  /// ZMA 파일 파싱
  static List<ZmaPoint> parseZma(String content) {
    final points = <ZmaPoint>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('*')) continue;
      final parts = trimmed.split(RegExp(r'[\s,\t]+'));
      if (parts.length < 2) continue;
      final freq = double.tryParse(parts[0]);
      final imp = double.tryParse(parts[1]);
      if (freq == null || imp == null) continue;
      final phase = parts.length >= 3 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0;
      points.add(ZmaPoint(frequency: freq, impedance: imp, phase: phase));
    }
    points.sort((a, b) => a.frequency.compareTo(b.frequency));
    return points;
  }

  /// ZMA → T/S 파라미터 역산
  /// 표준 방법: Fs = 최대 임피던스 주파수, Re = 최소 임피던스
  static TsParameters extractTs(List<ZmaPoint> zma) {
    if (zma.isEmpty) throw Exception('ZMA 데이터 없음');

    // Re: 고주파 영역 최소 임피던스 (100Hz 이하 평균)
    final lowFreq = zma.where((p) => p.frequency > 200 && p.frequency < 1000).toList();
    final re = lowFreq.isEmpty ? zma.map((p) => p.impedance).reduce(min)
        : lowFreq.map((p) => p.impedance).reduce(min);

    // Zmax: 전체 최대 임피던스
    final zmaxPoint = zma.reduce((a, b) => a.impedance > b.impedance ? a : b);
    final zmax = zmaxPoint.impedance;
    final fs = zmaxPoint.frequency;

    // Ro = Zmax / Re
    final ro = zmax / re;

    // f1, f2: Zmax/√2 교차점 (Fs 양쪽)
    final targetZ = zmax / sqrt(2);
    double? f1, f2;
    for (int i = 0; i < zma.length - 1; i++) {
      final p = zma[i];
      final n = zma[i + 1];
      if (p.frequency < fs && p.impedance < targetZ && n.impedance >= targetZ) {
        f1 = p.frequency + (n.frequency - p.frequency) * (targetZ - p.impedance) / (n.impedance - p.impedance);
      }
      if (p.frequency > fs && p.impedance >= targetZ && n.impedance < targetZ) {
        f2 = p.frequency + (n.frequency - p.frequency) * (p.impedance - targetZ) / (p.impedance - n.impedance);
      }
    }

    double qms, qes, qts;
    if (f1 != null && f2 != null && f2 > f1) {
      qms = fs * sqrt(ro) / (f2 - f1);
      qes = qms / (ro - 1);
      qts = (qms * qes) / (qms + qes);
    } else {
      // 근사값
      qts = 0.4;
      qes = 0.5;
      qms = (qts * qes) / (qes - qts).abs().clamp(0.01, 10);
    }

    return TsParameters(fs: fs, re: re, qes: qes, qms: qms, qts: qts, zmax: zmax);
  }

  /// FRD에서 특정 주파수의 SPL 보간
  static double interpolateSpl(List<FrdPoint> frd, double frequency) {
    if (frd.isEmpty) return 0.0;
    if (frequency <= frd.first.frequency) return frd.first.spl;
    if (frequency >= frd.last.frequency) return frd.last.spl;
    for (int i = 0; i < frd.length - 1; i++) {
      if (frd[i].frequency <= frequency && frd[i+1].frequency >= frequency) {
        final t = (frequency - frd[i].frequency) / (frd[i+1].frequency - frd[i].frequency);
        return frd[i].spl + t * (frd[i+1].spl - frd[i].spl);
      }
    }
    return 0.0;
  }

  /// FRD에서 위상 보간
  static double interpolatePhase(List<FrdPoint> frd, double frequency) {
    if (frd.isEmpty) return 0.0;
    if (frequency <= frd.first.frequency) return frd.first.phase;
    if (frequency >= frd.last.frequency) return frd.last.phase;
    for (int i = 0; i < frd.length - 1; i++) {
      if (frd[i].frequency <= frequency && frd[i+1].frequency >= frequency) {
        final t = (frequency - frd[i].frequency) / (frd[i+1].frequency - frd[i].frequency);
        return frd[i].phase + t * (frd[i+1].phase - frd[i].phase);
      }
    }
    return 0.0;
  }

  /// 감도 계산 (300Hz~3kHz 평균 SPL)
  static double calculateSensitivity(List<FrdPoint> frd) {
    final band = frd.where((p) => p.frequency >= 300 && p.frequency <= 3000).toList();
    if (band.isEmpty) return 85.0;
    return band.map((p) => p.spl).reduce((a, b) => a + b) / band.length;
  }

  /// 크로스오버 주파수 추천 (우퍼 -3dB 포인트)
  static double recommendCrossover(List<FrdPoint> wooferFrd, List<FrdPoint> tweeterFrd) {
    final wooferSens = calculateSensitivity(wooferFrd);
    final tweeterSens = calculateSensitivity(tweeterFrd);

    // 우퍼 고역 롤오프 -6dB 포인트
    double? wooferRolloff;
    for (int i = wooferFrd.length - 1; i >= 0; i--) {
      if (wooferFrd[i].spl >= wooferSens - 6) {
        wooferRolloff = wooferFrd[i].frequency;
        break;
      }
    }

    // 트위터 저역 한계 (-6dB)
    double? tweeterLow;
    for (final p in tweeterFrd) {
      if (p.spl >= tweeterSens - 6) {
        tweeterLow = p.frequency;
        break;
      }
    }

    if (wooferRolloff != null && tweeterLow != null) {
      return sqrt(wooferRolloff * tweeterLow);
    }
    return 2500.0; // 기본값
  }
}
