import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 인클로저 스펙 기반 고유 해시 생성 (SonicCore 특허 청구항8)
///
/// 허용오차 버킷 적용 후 SHA-256:
///   체적  ±0.25L   → 0.5L 버킷
///   포트  ±2.5mm   → 5mm  버킷
///   Fs    ±5Hz     → 10Hz 버킷
///   Vas   ±0.25L   → 0.5L 버킷
///
/// 결과 해시 앞 12자(48bit) 사용 — 실용적으로 충돌 확률 무시 가능.
class EnclosureHash {
  static const double _volBucket  = 0.5;   // 리터
  static const double _portBucket = 5.0;   // mm
  static const double _fsBucket   = 10.0;  // Hz
  static const double _vasBucket  = 0.5;   // 리터

  static double _bucket(double value, double step) =>
      (value / step).round() * step;

  /// 해시 생성
  ///
  /// [volumeL]      내부 체적 (L), 필수
  /// [portLengthMm] 포트 길이 (mm) — null = sealed
  /// [portDiamMm]   포트 직경 (mm) — null = sealed
  /// [fsHz]         우퍼 Fs (Hz) — optional
  /// [vasL]         우퍼 Vas (L) — optional
  static String generate({
    required double volumeL,
    double? portLengthMm,
    double? portDiamMm,
    double? fsHz,
    double? vasL,
  }) {
    final vol = _bucket(volumeL,  _volBucket).toStringAsFixed(1);
    final pl  = portLengthMm != null
        ? _bucket(portLengthMm, _portBucket).toStringAsFixed(0) : 'S';
    final pd  = portDiamMm  != null
        ? _bucket(portDiamMm,  _portBucket).toStringAsFixed(0) : 'S';
    final fs  = fsHz != null
        ? _bucket(fsHz,  _fsBucket).toStringAsFixed(0) : '';
    final vas = vasL != null
        ? _bucket(vasL,  _vasBucket).toStringAsFixed(1) : '';

    final canonical = 'v=$vol|pl=$pl|pd=$pd|fs=$fs|vas=$vas';
    final digest = sha256.convert(utf8.encode(canonical));
    return digest.toString().substring(0, 12);
  }

  /// volumeL이 null이면 null 반환
  static String? fromEnclosure({
    required double? volumeL,
    double? portLengthMm,
    double? portDiamMm,
    double? fsHz,
    double? vasL,
  }) {
    if (volumeL == null) return null;
    return generate(
      volumeL: volumeL,
      portLengthMm: portLengthMm,
      portDiamMm: portDiamMm,
      fsHz: fsHz,
      vasL: vasL,
    );
  }
}
