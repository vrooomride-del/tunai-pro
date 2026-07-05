import 'dart:math';
import 'dsp/dsp_adapter.dart';

/// 값 검증 결과 — 통과 여부와 무관하게 항상 (최종적으로 써야 할) [value]를 담는다.
/// [wasClamped]가 true면 [reason]에 사용자에게 보여줄 문구가 들어있다.
class SafetyResult<T> {
  final T value;
  final bool wasClamped;
  final String? reason;
  const SafetyResult(this.value, {this.wasClamped = false, this.reason});
}

/// DSP Safety Validation Layer (AOS 항목 D) — mobile(tunai)의 동일 클래스와
/// 로직/임계값을 맞춤. 두 repo가 공유 패키지로 묶여 있지 않아 파일을 복제
/// 구현했다(ACM 계층의 기존 중복 패턴과 동일 — HANDOFF.md gap analysis 참고).
class DspSafety {
  static const double tweeterMinHpfHz = 1500;
  static const double tweeterBandThresholdHz = 2000;
  static const double tweeterMaxBoostDb = 6.0;
  static const double bassBandThresholdHz = 200;
  static const double bassMaxBoostDbDefault = 6.0;

  /// 채널 broadband 게인(주파수 정보 없음) 검증 — [DspAdapter.writeGain] 전용.
  static SafetyResult<double> validateChannelGain(double gainDb, {required bool isTweeter}) {
    if (isTweeter && gainDb > tweeterMaxBoostDb) {
      return SafetyResult(
        tweeterMaxBoostDb,
        wasClamped: true,
        reason: '트위터 채널 게인이 보호를 위해 +${tweeterMaxBoostDb.toStringAsFixed(0)}dB로 제한되었습니다',
      );
    }
    return SafetyResult(gainDb);
  }

  /// 크로스오버 HPF 최소 주파수 검증 — [DspAdapter.writeCrossover] 전용.
  static SafetyResult<double> validateCrossoverFreq(
    double freqHz,
    FilterSide side, {
    required bool isTweeter,
  }) {
    if (isTweeter && side == FilterSide.hpf && freqHz < tweeterMinHpfHz) {
      return SafetyResult(
        tweeterMinHpfHz,
        wasClamped: true,
        reason: '트위터 보호를 위해 크로스오버 주파수가 ${tweeterMinHpfHz.toStringAsFixed(0)}Hz로 조정되었습니다',
      );
    }
    return SafetyResult(freqHz);
  }

  /// 주파수+게인 기반 밴드 검증 — PEQ 밴드/피크에 공용으로 사용.
  static SafetyResult<double> validateBandGain(
    double freqHz,
    double gainDb, {
    double? maxBassBoostDb,
  }) {
    if (freqHz >= tweeterBandThresholdHz && gainDb > tweeterMaxBoostDb) {
      return SafetyResult(
        tweeterMaxBoostDb,
        wasClamped: true,
        reason: '고역(트위터 대역) 부스트가 보호를 위해 +${tweeterMaxBoostDb.toStringAsFixed(0)}dB로 제한되었습니다',
      );
    }
    final bassCap = maxBassBoostDb ?? bassMaxBoostDbDefault;
    if (freqHz < bassBandThresholdHz && gainDb > bassCap) {
      return SafetyResult(
        bassCap,
        wasClamped: true,
        reason: '저역 부스트가 드라이버 보호를 위해 +${bassCap.toStringAsFixed(1)}dB로 제한되었습니다',
      );
    }
    return SafetyResult(gainDb);
  }

  /// biquad 계수에서 피크 게인/주파수를 역산해 검증 — [DspAdapter.writeBiquad] 전용.
  /// 위반 시엔 부분 재조정 대신 안전한 passthrough(무효화)로 대체(1차 구현, 보수적).
  static SafetyResult<BiquadCoeffs> validateBiquad(BiquadCoeffs c, {double? maxBassBoostDb}) {
    final peak = _analyzePeak(c);
    final r = validateBandGain(peak.freqHz, peak.gainDb, maxBassBoostDb: maxBassBoostDb);
    if (!r.wasClamped) return SafetyResult(c);
    return SafetyResult(
      const BiquadCoeffs(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0), // passthrough
      wasClamped: true,
      reason: r.reason,
    );
  }

  /// 20Hz~20kHz 로그 스윕으로 biquad의 피크 이득(dB)과 그 주파수를 근사 계산.
  /// 이 코드베이스의 계수 저장 규약(SigmaStudio용으로 a1,a2 부호 반전, DspEngine.calculate
  /// 참고)에 맞춰 전달함수 분모를 `1 - a1·z⁻¹ - a2·z⁻²`로 계산한다.
  static ({double freqHz, double gainDb}) _analyzePeak(BiquadCoeffs c) {
    const sampleRate = 48000;
    var bestFreq = 20.0;
    var bestMag = 0.0;
    for (var f = 20.0; f <= 20000; f *= 1.03) {
      final w = 2 * pi * f / sampleRate;
      final cosW = cos(w), sinW = sin(w);
      final cos2W = cos(2 * w), sin2W = sin(2 * w);

      final numRe = c.b0 + c.b1 * cosW + c.b2 * cos2W;
      final numIm = -(c.b1 * sinW + c.b2 * sin2W);
      final denRe = 1 - c.a1 * cosW - c.a2 * cos2W;
      final denIm = c.a1 * sinW + c.a2 * sin2W;

      final numMag = sqrt(numRe * numRe + numIm * numIm);
      final denMag = sqrt(denRe * denRe + denIm * denIm);
      if (denMag < 1e-9) continue;
      final mag = numMag / denMag;
      if (mag > bestMag) {
        bestMag = mag;
        bestFreq = f;
      }
    }
    final gainDb = bestMag > 0 ? 20 * (log(bestMag) / ln10) : -100.0;
    return (freqHz: bestFreq, gainDb: gainDb);
  }
}
