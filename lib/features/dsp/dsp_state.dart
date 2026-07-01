import 'dart:convert';
import 'dart:math';

enum FilterType { peaking, lowShelf, highShelf, lowPass, highPass, notch, allPass }
enum CrossoverType { bypass, butterworth12, butterworth24, lr12, lr24, lr48 }

extension FilterTypeLabel on FilterType {
  String get label {
    switch (this) {
      case FilterType.peaking:   return 'PEQ';
      case FilterType.lowShelf:  return 'LSH';
      case FilterType.highShelf: return 'HSH';
      case FilterType.lowPass:   return 'LPF';
      case FilterType.highPass:  return 'HPF';
      case FilterType.notch:     return 'NCH';
      case FilterType.allPass:   return 'APF';
    }
  }
}

extension CrossoverLabel on CrossoverType {
  String get label {
    switch (this) {
      case CrossoverType.bypass:         return 'BYPASS';
      case CrossoverType.butterworth12:  return 'BW12';
      case CrossoverType.butterworth24:  return 'BW24';
      case CrossoverType.lr12:           return 'LR12';
      case CrossoverType.lr24:           return 'LR24';
      case CrossoverType.lr48:           return 'LR48';
    }
  }
}

/// 20Hz ~ 20kHz를 count 구간으로 로그 균등 분할, i번째 주파수 반환
double _logEqualFreq(int i, int count) {
  const logMin = 1.30103;   // log10(20)
  const logMax = 4.30103;   // log10(20000)
  if (count <= 1) return 1000;
  final logF = logMin + i * (logMax - logMin) / (count - 1);
  // 소수점 불필요한 잡음 제거: 반올림 후 1 자리 유효숫자
  final raw = pow(10, logF).toDouble();
  return (raw / pow(10, (log(raw) / ln10).floor() - 1)).round() *
      pow(10, (log(raw) / ln10).floor() - 1).toDouble();
}

/// 단일 PEQ 밴드
class PeqBand {
  final bool enabled;
  final double frequency;  // 20 ~ 20000 Hz
  final double gainDb;     // -24 ~ +24 dB
  final double q;          // 0.1 ~ 16
  final FilterType type;

  const PeqBand({
    this.enabled = true,
    this.frequency = 1000,
    this.gainDb = 0,
    this.q = 2.0,
    this.type = FilterType.peaking,
  });

  PeqBand copyWith({
    bool? enabled, double? frequency, double? gainDb, double? q, FilterType? type,
  }) => PeqBand(
    enabled: enabled ?? this.enabled,
    frequency: frequency ?? this.frequency,
    gainDb: gainDb ?? this.gainDb,
    q: q ?? this.q,
    type: type ?? this.type,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled, 'frequency': frequency,
    'gainDb': gainDb, 'q': q, 'type': type.index,
  };

  factory PeqBand.fromJson(Map<String, dynamic> j) => PeqBand(
    enabled: j['enabled'] ?? true,
    frequency: (j['frequency'] ?? 1000).toDouble(),
    gainDb: (j['gainDb'] ?? 0).toDouble(),
    q: (j['q'] ?? 2.0).toDouble(),
    type: FilterType.values[j['type'] ?? 0],
  );
}

/// 크로스오버 필터 (HP 또는 LP)
class CrossoverFilter {
  final CrossoverType type;
  final double frequency;

  const CrossoverFilter({
    this.type = CrossoverType.bypass,
    this.frequency = 80,
  });

  CrossoverFilter copyWith({CrossoverType? type, double? frequency}) =>
      CrossoverFilter(type: type ?? this.type, frequency: frequency ?? this.frequency);

  Map<String, dynamic> toJson() => {'type': type.index, 'frequency': frequency};
  factory CrossoverFilter.fromJson(Map<String, dynamic> j) => CrossoverFilter(
    type: CrossoverType.values[j['type'] ?? 0],
    frequency: (j['frequency'] ?? 80).toDouble(),
  );
}

/// 출력 채널 (6개: OUT1~6)
class OutputChannel {
  final String name;        // 'WOOFER L', 'WOOFER R', 'MID L' ...
  final bool muted;
  final bool polarity;      // false=정상, true=반전
  final double gainDb;      // -40 ~ +12
  final double delayMs;     // 0 ~ 100ms
  final CrossoverFilter hpFilter;
  final CrossoverFilter lpFilter;
  final List<PeqBand> bands; // 20밴드

  const OutputChannel({
    required this.name,
    this.muted = false,
    this.polarity = false,
    this.gainDb = 0,
    this.delayMs = 0,
    this.hpFilter = const CrossoverFilter(type: CrossoverType.bypass),
    this.lpFilter = const CrossoverFilter(type: CrossoverType.bypass),
    this.bands = const [],
  });

  OutputChannel copyWith({
    String? name, bool? muted, bool? polarity, double? gainDb, double? delayMs,
    CrossoverFilter? hpFilter, CrossoverFilter? lpFilter, List<PeqBand>? bands,
  }) => OutputChannel(
    name: name ?? this.name,
    muted: muted ?? this.muted,
    polarity: polarity ?? this.polarity,
    gainDb: gainDb ?? this.gainDb,
    delayMs: delayMs ?? this.delayMs,
    hpFilter: hpFilter ?? this.hpFilter,
    lpFilter: lpFilter ?? this.lpFilter,
    bands: bands ?? this.bands,
  );

  Map<String, dynamic> toJson() => {
    'name': name, 'muted': muted, 'polarity': polarity,
    'gainDb': gainDb, 'delayMs': delayMs,
    'hpFilter': hpFilter.toJson(), 'lpFilter': lpFilter.toJson(),
    'bands': bands.map((b) => b.toJson()).toList(),
  };

  factory OutputChannel.fromJson(Map<String, dynamic> j) => OutputChannel(
    name: j['name'] ?? '',
    muted: j['muted'] ?? false,
    polarity: j['polarity'] ?? false,
    gainDb: (j['gainDb'] ?? 0).toDouble(),
    delayMs: (j['delayMs'] ?? 0).toDouble(),
    hpFilter: CrossoverFilter.fromJson(j['hpFilter'] ?? {}),
    lpFilter: CrossoverFilter.fromJson(j['lpFilter'] ?? {}),
    bands: (j['bands'] as List? ?? []).map((b) => PeqBand.fromJson(b)).toList(),
  );

  static List<PeqBand> defaultBands({int count = 20}) =>
      List.generate(20, (i) => PeqBand(frequency: _logEqualFreq(i, count)));
}

/// 입력 채널 (2개: L/R)
class InputChannel {
  final String name;
  final double gainDb;
  final CrossoverFilter hpFilter;
  final CrossoverFilter lpFilter;
  final List<PeqBand> bands; // 10밴드

  const InputChannel({
    required this.name,
    this.gainDb = 0,
    this.hpFilter = const CrossoverFilter(type: CrossoverType.bypass),
    this.lpFilter = const CrossoverFilter(type: CrossoverType.bypass),
    this.bands = const [],
  });

  InputChannel copyWith({
    String? name, double? gainDb,
    CrossoverFilter? hpFilter, CrossoverFilter? lpFilter, List<PeqBand>? bands,
  }) => InputChannel(
    name: name ?? this.name,
    gainDb: gainDb ?? this.gainDb,
    hpFilter: hpFilter ?? this.hpFilter,
    lpFilter: lpFilter ?? this.lpFilter,
    bands: bands ?? this.bands,
  );

  Map<String, dynamic> toJson() => {
    'name': name, 'gainDb': gainDb,
    'hpFilter': hpFilter.toJson(), 'lpFilter': lpFilter.toJson(),
    'bands': bands.map((b) => b.toJson()).toList(),
  };

  factory InputChannel.fromJson(Map<String, dynamic> j) => InputChannel(
    name: j['name'] ?? '',
    gainDb: (j['gainDb'] ?? 0).toDouble(),
    hpFilter: CrossoverFilter.fromJson(j['hpFilter'] ?? {}),
    lpFilter: CrossoverFilter.fromJson(j['lpFilter'] ?? {}),
    bands: (j['bands'] as List? ?? []).map((b) => PeqBand.fromJson(b)).toList(),
  );

  static List<PeqBand> defaultBands({int count = 10}) =>
      List.generate(10, (i) => PeqBand(frequency: _logEqualFreq(i, count)));
}

/// 전체 DSP 상태
class DspState {
  final List<InputChannel> inputs;   // 2ch: L, R
  final List<OutputChannel> outputs; // 6ch: W-L, W-R, M-L, M-R, T-L, T-R
  final int selectedOutput;          // 0~5
  final int selectedInput;           // 0~1
  final bool showInput;              // true=INPUT탭, false=OUTPUT탭
  final int selectedBand;            // 선택된 PEQ 밴드
  final bool isDirty;

  const DspState({
    required this.inputs,
    required this.outputs,
    this.selectedOutput = 0,
    this.selectedInput = 0,
    this.showInput = false,
    this.selectedBand = 0,
    this.isDirty = false,
  });

  DspState copyWith({
    List<InputChannel>? inputs,
    List<OutputChannel>? outputs,
    int? selectedOutput,
    int? selectedInput,
    bool? showInput,
    int? selectedBand,
    bool? isDirty,
  }) => DspState(
    inputs: inputs ?? this.inputs,
    outputs: outputs ?? this.outputs,
    selectedOutput: selectedOutput ?? this.selectedOutput,
    selectedInput: selectedInput ?? this.selectedInput,
    showInput: showInput ?? this.showInput,
    selectedBand: selectedBand ?? this.selectedBand,
    isDirty: isDirty ?? this.isDirty,
  );

  String toJson() => jsonEncode({
    'inputs': inputs.map((i) => i.toJson()).toList(),
    'outputs': outputs.map((o) => o.toJson()).toList(),
  });

  static DspState initial() => DspState(
    inputs: [
      InputChannel(name: 'IN L', bands: InputChannel.defaultBands()),
      InputChannel(name: 'IN R', bands: InputChannel.defaultBands()),
    ],
    outputs: [
      OutputChannel(name: 'TWE L', bands: OutputChannel.defaultBands(),
        hpFilter: const CrossoverFilter(type: CrossoverType.lr24, frequency: 2500)),
      OutputChannel(name: 'TWE R', bands: OutputChannel.defaultBands(),
        hpFilter: const CrossoverFilter(type: CrossoverType.lr24, frequency: 2500)),
      OutputChannel(name: 'MID L', bands: OutputChannel.defaultBands(),
        hpFilter: const CrossoverFilter(type: CrossoverType.lr24, frequency: 200),
        lpFilter: const CrossoverFilter(type: CrossoverType.lr24, frequency: 2500)),
      OutputChannel(name: 'MID R', bands: OutputChannel.defaultBands(),
        hpFilter: const CrossoverFilter(type: CrossoverType.lr24, frequency: 200),
        lpFilter: const CrossoverFilter(type: CrossoverType.lr24, frequency: 2500)),
      OutputChannel(name: 'WOO L', bands: OutputChannel.defaultBands(),
        lpFilter: const CrossoverFilter(type: CrossoverType.lr24, frequency: 200)),
      OutputChannel(name: 'WOO R', bands: OutputChannel.defaultBands(),
        lpFilter: const CrossoverFilter(type: CrossoverType.lr24, frequency: 200)),
    ],
  );
}
