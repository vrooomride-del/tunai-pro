import 'package:dio/dio.dart';
import '../features/dsp/dsp_state.dart';
import 'speaker_profile.dart';
import 'profiles/system_profile.dart';

const _functionUrl =
    'https://asia-northeast3-tunai-54b7f.cloudfunctions.net/aiTunePro';

class AiTuningService {
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
  ));

  static Future<AiTuningResult> suggest({
    required DspState dspState,
    required String userRequest,
    List<Map<String, double>>? frequencyResponse,
    SpeakerProfile? speakerProfile,
    SystemProfile? systemProfile,
  }) async {
    try {
      final outIdx = dspState.selectedOutput;

      final body = {
        'dspState': {
          'selectedOutput': outIdx,
          'outputs': dspState.outputs.map((o) => {
            'name': o.name,
            'gainDb': o.gainDb,
            'delayMs': o.delayMs,
            'hpFilter': {'type': o.hpFilter.type.name, 'frequency': o.hpFilter.frequency},
            'lpFilter': {'type': o.lpFilter.type.name, 'frequency': o.lpFilter.frequency},
            'bands': o.bands.map((b) => {
              'frequency': b.frequency,
              'gainDb': b.gainDb,
              'q': b.q,
              'type': b.type.index,
              'enabled': b.enabled,
            }).toList(),
          }).toList(),
        },
        'userRequest': userRequest,
        if (frequencyResponse != null) 'frequencyResponse': frequencyResponse,
        if (speakerProfile != null) 'speakerProfile': {
          'name': speakerProfile.name,
          'fs': speakerProfile.fs,
          'xmax': speakerProfile.xmax,
          'sensitivity': speakerProfile.sensitivity,
        },
        if (systemProfile != null) 'systemProfile': {
          'displayName': systemProfile.displayName,
          'chipLabel': systemProfile.chipLabel,
          'channels': systemProfile.channels.map((c) => {'name': c.name}).toList(),
        },
      };

      final response = await _dio.post(_functionUrl, data: body);
      final result = response.data['result'] as Map<String, dynamic>;
      return AiTuningResult.fromJson(result);
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] ?? e.message ?? '네트워크 오류';
      return AiTuningResult.error(msg.toString());
    } catch (e) {
      return AiTuningResult.error('AI 응답 오류: $e');
    }
  }
}

class AiTuningResult {
  final bool success;
  final String analysis;
  final List<AiBandSuggestion> bands;
  final String summary;
  final String? error;

  const AiTuningResult({
    required this.success,
    required this.analysis,
    required this.bands,
    required this.summary,
    this.error,
  });

  factory AiTuningResult.fromJson(Map<String, dynamic> j) => AiTuningResult(
        success: true,
        analysis: j['analysis'] ?? '',
        bands: (j['bands'] as List? ?? [])
            .map((b) => AiBandSuggestion.fromJson(Map<String, dynamic>.from(b as Map)))
            .toList(),
        summary: j['summary'] ?? '',
      );

  factory AiTuningResult.error(String msg) => AiTuningResult(
        success: false,
        analysis: '',
        bands: [],
        summary: '',
        error: msg,
      );
}

class AiBandSuggestion {
  final int index;
  final double frequency;
  final double gainDb;
  final double q;
  final int type;
  final bool enabled;
  final String reason;

  const AiBandSuggestion({
    required this.index,
    required this.frequency,
    required this.gainDb,
    required this.q,
    required this.type,
    required this.enabled,
    required this.reason,
  });

  factory AiBandSuggestion.fromJson(Map<String, dynamic> j) => AiBandSuggestion(
        index: j['index'] ?? 0,
        frequency: (j['frequency'] ?? 1000).toDouble(),
        gainDb: (j['gainDb'] ?? 0).toDouble(),
        q: (j['q'] ?? 2.0).toDouble(),
        type: j['type'] ?? 0,
        enabled: j['enabled'] ?? true,
        reason: j['reason'] ?? '',
      );

  PeqBand toPeqBand() => PeqBand(
        frequency: frequency,
        gainDb: gainDb,
        q: q,
        type: FilterType.values[type.clamp(0, FilterType.values.length - 1)],
        enabled: enabled,
      );
}
