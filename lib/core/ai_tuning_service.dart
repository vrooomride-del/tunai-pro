import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../features/dsp/dsp_state.dart';
import 'speaker_profile.dart';

class AiTuningService {
  static const _apiKey = 'AQ.Ab8RN6Je2ple9H4TTYY30b5qKIx7N-xyaLV-7zr5wzWOT_7pJQ'; // 환경변수로 교체 예정
  
  static final _model = GenerativeModel(
    model: 'gemini-2.5-flash-lite',
    apiKey: _apiKey,
    generationConfig: GenerationConfig(
      temperature: 0.2, // 낮을수록 일관된 수치 출력
      responseMimeType: 'application/json',
    ),
  );

  /// 현재 DSP 상태 + 사용자 요청 → Gemini → PEQ 파라미터 추천
  static Future<AiTuningResult> suggest({
    required DspState dspState,
    required String userRequest,
    List<Map<String, double>>? frequencyResponse,
    SpeakerProfile? speakerProfile,
  }) async {
    final prompt = _buildPrompt(dspState, userRequest, frequencyResponse, speakerProfile);
    
    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';
      final json = jsonDecode(text);
      return AiTuningResult.fromJson(json);
    } catch (e) {
      return AiTuningResult.error('AI 응답 오류: $e');
    }
  }

  static String _buildPrompt(
    DspState state,
    String userRequest,
    List<Map<String, double>>? freqResponse,
    SpeakerProfile? speakerProfile,
  ) {
    final outIdx = state.selectedOutput;
    final out = state.outputs[outIdx];

    // 현재 PEQ 상태
    final currentBands = out.bands.asMap().entries.map((e) {
      final b = e.value;
      return '  Band${e.key + 1}: ${b.frequency.toStringAsFixed(0)}Hz, '
          '${b.gainDb.toStringAsFixed(1)}dB, Q${b.q.toStringAsFixed(2)}, '
          '${b.type.label}, enabled=${b.enabled}';
    }).join('\n');

    // 크로스오버 정보
    final hp = out.hpFilter.type != CrossoverType.bypass
        ? 'HP: ${out.hpFilter.type.label} ${out.hpFilter.frequency.toStringAsFixed(0)}Hz'
        : 'HP: BYPASS';
    final lp = out.lpFilter.type != CrossoverType.bypass
        ? 'LP: ${out.lpFilter.type.label} ${out.lpFilter.frequency.toStringAsFixed(0)}Hz'
        : 'LP: BYPASS';

    // 주파수 응답 데이터 (있으면 포함)
    String freqSection = '';
    if (freqResponse != null && freqResponse.isNotEmpty) {
      final points = freqResponse.where((r) {
        final f = r['frequency'] ?? r['f'] ?? 0;
        return f >= 20 && f <= 20000;
      }).map((r) {
        final f = r['frequency'] ?? r['f'] ?? 0;
        final db = r['db'] ?? 0;
        return '${f.toStringAsFixed(0)}Hz: ${db.toStringAsFixed(1)}dB';
      }).take(31).join(', ');
      freqSection = '\n\nMEASURED FREQUENCY RESPONSE:\n$points';
    }
    String tsSection = '';
    if (speakerProfile != null) {
      tsSection = '''

SPEAKER T/S PARAMETERS (PHYSICAL CONSTRAINTS - MUST RESPECT):
  Name: ${speakerProfile.name}
  Fs: ${speakerProfile.fs.toStringAsFixed(1)} Hz  → Do NOT boost below ${speakerProfile.recommendedHpfFreq.toStringAsFixed(0)} Hz
  Qts: ${speakerProfile.qts.toStringAsFixed(3)}
  Vas: ${speakerProfile.vas.toStringAsFixed(1)} L
  Xmax: ${speakerProfile.xmax.toStringAsFixed(1)} mm  → Max bass boost: ${speakerProfile.maxBassBoostDb.toStringAsFixed(1)} dB
  Sensitivity: ${speakerProfile.sensitivity.toStringAsFixed(1)} dB  → Gain offset ref: ${speakerProfile.gainReferenceOffset >= 0 ? '+' : ''}${speakerProfile.gainReferenceOffset.toStringAsFixed(1)} dB
CONSTRAINTS: Never recommend HPF below ${speakerProfile.recommendedHpfFreq.toStringAsFixed(0)} Hz. Bass boost must not exceed ${speakerProfile.maxBassBoostDb.toStringAsFixed(1)} dB.''';
    }

    return '''
You are an expert audio DSP engineer specializing in active speaker systems.
Analyze the current DSP settings and provide PEQ adjustment recommendations.

CHANNEL: ${out.name}
CROSSOVER: $hp | $lp
GAIN: ${out.gainDb.toStringAsFixed(1)}dB
DELAY: ${out.delayMs.toStringAsFixed(2)}ms

CURRENT PEQ BANDS (20 bands):
$currentBands
$freqSection
$tsSection

USER REQUEST: "$userRequest"

Respond ONLY with valid JSON in this exact format:
{
  "analysis": "Brief analysis of the current situation in Korean (2-3 sentences)",
  "bands": [
    {
      "index": 0,
      "frequency": 80.0,
      "gainDb": -3.0,
      "q": 2.0,
      "type": 0,
      "enabled": true,
      "reason": "reason in Korean"
    }
  ],
  "summary": "Summary of changes in Korean"
}

Rules:
- type: 0=peaking, 1=lowShelf, 2=highShelf, 3=lowPass, 4=highPass, 5=notch, 6=allPass
- Only include bands that need changes (index 0-19)
- frequency: 20-20000 Hz
- gainDb: -24 to +24 dB
- q: 0.1 to 16
- Be conservative with adjustments (max ±6dB per band unless clearly necessary)
- Consider the crossover frequencies when making recommendations
''';
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
        .map((b) => AiBandSuggestion.fromJson(b))
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
