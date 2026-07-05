import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// AKG-ready 노드 — 사용자가 어떤 프리셋을 선택/롤백/저장/삭제했는지 남기는 신호.
///
/// 지금 당장 이 데이터를 분석하지 않는다 — 나중에 AIE(지능엔진)가 "이 사용자가
/// 어떤 튜닝을 선호하는지" 참조할 수 있도록 쌓아만 둔다(로컬, SharedPreferences).
enum PreferenceAction { select, rollback, save, delete }

class UserPreferenceSignal {
  final String id;
  final DateTime timestamp;
  final String? deviceId; // Pro엔 기기 식별 인프라가 없어 현재 항상 null
  final int? userId;      // AuthState.userId 참조
  final PreferenceAction action;
  final String presetLabel;

  const UserPreferenceSignal({
    required this.id,
    required this.timestamp,
    this.deviceId,
    this.userId,
    required this.action,
    required this.presetLabel,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'deviceId': deviceId,
        'userId': userId,
        'action': action.name,
        'presetLabel': presetLabel,
      };

  factory UserPreferenceSignal.fromJson(Map<String, dynamic> j) => UserPreferenceSignal(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        deviceId: j['deviceId'] as String?,
        userId: j['userId'] as int?,
        action: PreferenceAction.values.firstWhere(
          (a) => a.name == j['action'],
          orElse: () => PreferenceAction.select,
        ),
        presetLabel: j['presetLabel'] as String? ?? '',
      );
}

/// 로컬 선호 신호 로그 — 최근 [_maxEntries]개까지만 보관(무한 성장 방지).
class UserPreferenceSignalStore {
  static const _key = 'akg_preference_signals_v1';
  static const _maxEntries = 200;

  static Future<void> append(UserPreferenceSignal signal) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    raw.add(jsonEncode(signal.toJson()));
    final trimmed =
        raw.length > _maxEntries ? raw.sublist(raw.length - _maxEntries) : raw;
    await prefs.setStringList(_key, trimmed);
  }

  static Future<List<UserPreferenceSignal>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    final out = <UserPreferenceSignal>[];
    for (final s in raw) {
      try {
        out.add(UserPreferenceSignal.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // 손상된 항목은 건너뜀
      }
    }
    return out;
  }
}
