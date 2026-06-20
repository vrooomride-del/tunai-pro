import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 인클로저 스펙 기반 고유 해시 (SonicCore 특허 청구항8, enclosure_hash_v1)
///
/// 입력: 체적 + 포트길이 + 포트직경 (3개)
/// 버킷: 체적 1.0L / 포트 5mm — 측정 오차 흡수
/// sealed 인클로저: portLength=null, portDiameter=null → 'S' 인코딩
/// volumeL=null이면 해시 생성 불가 (null 반환)
///
/// 버전 태그 'v1'을 canonical string에 포함 — 배플 등 필드 추가 시 v2로 분리
class EnclosureHash {
  static const double _volBucket  = 1.0;  // 리터
  static const double _portBucket = 5.0;  // mm

  static double _bucket(double value, double step) =>
      (value / step).round() * step;

  static String generate({
    required double volumeL,
    double? portLengthMm,
    double? portDiamMm,
  }) {
    final vol = _bucket(volumeL, _volBucket).toStringAsFixed(1);
    final pl  = portLengthMm != null
        ? _bucket(portLengthMm, _portBucket).toStringAsFixed(0) : 'S';
    final pd  = portDiamMm != null
        ? _bucket(portDiamMm,  _portBucket).toStringAsFixed(0) : 'S';

    final canonical = 'enclosure_hash_v1|v=$vol|pl=$pl|pd=$pd';
    final digest = sha256.convert(utf8.encode(canonical));
    return digest.toString().substring(0, 12);
  }

  /// volumeL이 null이면 null 반환 (업로드/검색 비활성화)
  static String? fromEnclosure({
    required double? volumeL,
    double? portLengthMm,
    double? portDiamMm,
  }) {
    if (volumeL == null) return null;
    return generate(
      volumeL: volumeL,
      portLengthMm: portLengthMm,
      portDiamMm: portDiamMm,
    );
  }
}
