import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// AKG(Acoustic Knowledge Graph)-ready 노드 — 측정 1회의 메타데이터.
///
/// 지금은 그래프 DB가 없어 로컬(SharedPreferences)에 append-only 리스트로
/// 쌓아두기만 한다. [userId]는 다른 노드(User)를 ID로 참조하는 필드일 뿐 —
/// 나중에 실제 그래프 DB로 옮길 때 그대로 엣지(관계)가 된다. [deviceId]는 Pro에
/// 기기 등록/식별 인프라(mobile의 device_service.dart 같은 것)가 아직 없어서
/// 항상 null이다 — 생기면 그대로 채우면 됨(구조는 이미 준비돼 있음).
class MeasurementSession {
  final String id;
  final DateTime timestamp;
  final String? deviceId; // Pro엔 기기 식별 인프라가 없어 현재 항상 null
  final int? userId;      // AuthState.userId 참조
  final String? systemProfileId; // SystemProfile.id.name 참조(보드/스피커 구성)
  final int channelCount;

  const MeasurementSession({
    required this.id,
    required this.timestamp,
    this.deviceId,
    this.userId,
    this.systemProfileId,
    required this.channelCount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'deviceId': deviceId,
        'userId': userId,
        'systemProfileId': systemProfileId,
        'channelCount': channelCount,
      };

  factory MeasurementSession.fromJson(Map<String, dynamic> j) => MeasurementSession(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        deviceId: j['deviceId'] as String?,
        userId: j['userId'] as int?,
        systemProfileId: j['systemProfileId'] as String?,
        channelCount: j['channelCount'] as int? ?? 0,
      );
}

/// 로컬 측정 이력 저장소 — 최근 [_maxEntries]개까지만 보관(무한 성장 방지).
class MeasurementSessionStore {
  static const _key = 'akg_measurement_sessions_v1';
  static const _maxEntries = 200;

  static Future<void> append(MeasurementSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    raw.add(jsonEncode(session.toJson()));
    final trimmed =
        raw.length > _maxEntries ? raw.sublist(raw.length - _maxEntries) : raw;
    await prefs.setStringList(_key, trimmed);
  }

  static Future<List<MeasurementSession>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    final out = <MeasurementSession>[];
    for (final s in raw) {
      try {
        out.add(MeasurementSession.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // 손상된 항목은 건너뜀
      }
    }
    return out;
  }
}
