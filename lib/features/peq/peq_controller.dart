import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/dsp_engine.dart';

class PeqState {
  final List<BiquadFilter> filters;
  final int selectedIndex;
  final List<Map<String, double>> frequencyResponse;
  final bool isDirty; // 미저장 변경사항

  const PeqState({
    this.filters = const [],
    this.selectedIndex = 0,
    this.frequencyResponse = const [],
    this.isDirty = false,
  });

  PeqState copyWith({
    List<BiquadFilter>? filters,
    int? selectedIndex,
    List<Map<String, double>>? frequencyResponse,
    bool? isDirty,
  }) => PeqState(
    filters: filters ?? this.filters,
    selectedIndex: selectedIndex ?? this.selectedIndex,
    frequencyResponse: frequencyResponse ?? this.frequencyResponse,
    isDirty: isDirty ?? this.isDirty,
  );
}

final peqProvider = StateNotifierProvider<PeqController, PeqState>(
  (ref) => PeqController(),
);

class PeqController extends StateNotifier<PeqState> {
  PeqController() : super(const PeqState()) {
    // 기본 4밴드 PEQ 초기화
    final defaultFilters = [
      const BiquadFilter(frequency: 80, gainDb: 0, q: 1.4, type: FilterType.lowShelf),
      const BiquadFilter(frequency: 200, gainDb: 0, q: 2.0, type: FilterType.peaking),
      const BiquadFilter(frequency: 1000, gainDb: 0, q: 2.0, type: FilterType.peaking),
      const BiquadFilter(frequency: 8000, gainDb: 0, q: 1.4, type: FilterType.highShelf),
    ];
    state = state.copyWith(filters: defaultFilters);
    _updateResponse();
  }

  void selectFilter(int index) {
    state = state.copyWith(selectedIndex: index);
  }

  void updateFrequency(int index, double freq) {
    final filters = List<BiquadFilter>.from(state.filters);
    filters[index] = filters[index].copyWith(frequency: freq.clamp(20, 20000));
    state = state.copyWith(filters: filters, isDirty: true);
    _updateResponse();
  }

  void updateGain(int index, double gain) {
    final filters = List<BiquadFilter>.from(state.filters);
    filters[index] = filters[index].copyWith(gainDb: gain.clamp(-24, 24));
    state = state.copyWith(filters: filters, isDirty: true);
    _updateResponse();
  }

  void updateQ(int index, double q) {
    final filters = List<BiquadFilter>.from(state.filters);
    filters[index] = filters[index].copyWith(q: q.clamp(0.1, 16));
    state = state.copyWith(filters: filters, isDirty: true);
    _updateResponse();
  }

  void updateType(int index, FilterType type) {
    final filters = List<BiquadFilter>.from(state.filters);
    filters[index] = filters[index].copyWith(type: type);
    state = state.copyWith(filters: filters, isDirty: true);
    _updateResponse();
  }

  void addFilter() {
    if (state.filters.length >= 8) return;
    final filters = List<BiquadFilter>.from(state.filters);
    filters.add(const BiquadFilter(frequency: 1000, gainDb: 0, q: 2.0));
    state = state.copyWith(filters: filters, selectedIndex: filters.length - 1, isDirty: true);
    _updateResponse();
  }

  void removeFilter(int index) {
    if (state.filters.length <= 1) return;
    final filters = List<BiquadFilter>.from(state.filters);
    filters.removeAt(index);
    state = state.copyWith(
      filters: filters,
      selectedIndex: (state.selectedIndex >= filters.length ? filters.length - 1 : state.selectedIndex),
      isDirty: true,
    );
    _updateResponse();
  }

  void resetAll() {
    final filters = state.filters.map((f) => f.copyWith(gainDb: 0)).toList();
    state = state.copyWith(filters: filters, isDirty: true);
    _updateResponse();
  }

  void _updateResponse() {
    final response = DspEngine.frequencyResponse(state.filters);
    state = state.copyWith(frequencyResponse: response);
  }

  // 프리셋 저장
  Future<void> savePreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final data = state.filters.map((f) => {
      'frequency': f.frequency,
      'gainDb': f.gainDb,
      'q': f.q,
      'type': f.type.index,
    }).toList();
    final presets = prefs.getStringList('presets_keys') ?? [];
    if (!presets.contains(name)) presets.add(name);
    await prefs.setStringList('presets_keys', presets);
    await prefs.setString('preset_\$name', jsonEncode(data));
    state = state.copyWith(isDirty: false);
  }

  // 프리셋 불러오기
  Future<void> loadPreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('preset_\$name');
    if (json == null) return;
    final data = jsonDecode(json) as List;
    final filters = data.map((d) => BiquadFilter(
      frequency: d['frequency'].toDouble(),
      gainDb: d['gainDb'].toDouble(),
      q: d['q'].toDouble(),
      type: FilterType.values[d['type']],
    )).toList();
    state = state.copyWith(filters: filters, isDirty: false);
    _updateResponse();
  }

  // 저장된 프리셋 목록
  Future<List<String>> getSavedPresets() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('presets_keys') ?? [];
  }

  // 외부 필터 직접 로드
  void loadFilters(List<BiquadFilter> filters) {
    state = state.copyWith(filters: filters, isDirty: false);
    _updateResponse();
  }

  // 프리셋 삭제
  Future<void> deletePreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final presets = prefs.getStringList('presets_keys') ?? [];
    presets.remove(name);
    await prefs.setStringList('presets_keys', presets);
    await prefs.remove('preset_\$name');
  }

  // BLE 전송용 프레임 생성
  List<Map<String, dynamic>> buildFrames() {
    final frames = <Map<String, dynamic>>[];
    int pramAddr = 0x0010;
    for (final filter in state.filters) {
      final coeff = DspEngine.calculate(filter);
      final frame = DspEngine.buildBleFrame(coeff, pramAddr);
      frames.add({'addr': pramAddr, 'frame': frame});
      pramAddr += 5;
    }
    return frames;
  }
}
