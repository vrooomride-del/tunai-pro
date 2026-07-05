import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dsp_state.dart';
import '../../core/dsp_engine.dart' as engine;
import '../../core/dsp/dsp_adapter.dart';
import '../../core/profiles/system_profile.dart';
import '../../core/factory_preset.dart';
import '../../core/dsp_safety_notice.dart';
import '../connect/connect_controller.dart';
import '../../core/channel_link_provider.dart';


final dspProvider = StateNotifierProvider<DspController, DspState>(
  (ref) => DspController(ref),
);

class DspController extends StateNotifier<DspState> {
  final Ref _ref;
  DspController(this._ref)
      : super(kFactoryPresetFlat.build(_ref.read(systemProfileProvider).maxPeqBands)) {
    // 과거(Factory/User 레이어 분리 이전)에 "Factory"라는 이름으로 저장된 유저
    // 프리셋이 있으면 1회 마이그레이션 — 데이터는 보존하고 이름만 바꾼다.
    _migrateLegacyFactoryNamedPresets();
  }

  // ── 탭 전환 ──────────────────────────────────────
  void selectOutput(int i) => state = state.copyWith(selectedOutput: i, showInput: false, selectedBand: 0);
  void selectInput(int i)  => state = state.copyWith(selectedInput: i, showInput: true, selectedBand: 0);
  void selectBand(int i)   => state = state.copyWith(selectedBand: i);

  // ── OUTPUT 편집 ──────────────────────────────────
  void _updateOutput(int idx, OutputChannel Function(OutputChannel) fn,
      {bool propagate = true}) {
    final outputs = List<OutputChannel>.from(state.outputs);
    outputs[idx] = fn(outputs[idx]);

    // L/R 링크 시 페어 채널에도 동일하게 적용
    if (propagate) {
      final links = _ref.read(channelLinkProvider);
      if (isChannelLinked(links, idx)) {
        final pair = channelPairOf(idx);
        if (pair >= 0 && pair < outputs.length) {
          outputs[pair] = fn(outputs[pair]);
        }
      }
    }

    state = state.copyWith(outputs: outputs, isDirty: true);
  }

  void updateOutputGain(int idx, double v) =>
      _updateOutput(idx, (o) => o.copyWith(gainDb: v.clamp(-40, 12)));

  void updateOutputDelay(int idx, double v) =>
      _updateOutput(idx, (o) => o.copyWith(delayMs: v.clamp(0, 100)));

  void toggleMute(int idx) =>
      _updateOutput(idx, (o) => o.copyWith(muted: !o.muted));

  Future<void> setMute(int idx, bool muted) async {
    _updateOutput(idx, (o) => o.copyWith(muted: muted));
    await sendToDsp(); // 즉시 실기기에 반영
  }

  void togglePolarity(int idx) =>
      _updateOutput(idx, (o) => o.copyWith(polarity: !o.polarity));

  void updateHpFilter(int idx, CrossoverFilter f) =>
      _updateOutput(idx, (o) => o.copyWith(hpFilter: f));

  void updateLpFilter(int idx, CrossoverFilter f) =>
      _updateOutput(idx, (o) => o.copyWith(lpFilter: f));

  void updateOutputBand(int outIdx, int bandIdx, PeqBand band) {
    final outputs = List<OutputChannel>.from(state.outputs);

    void applyBand(int chIdx) {
      final bands = List<PeqBand>.from(outputs[chIdx].bands);
      bands[bandIdx] = band;
      outputs[chIdx] = outputs[chIdx].copyWith(bands: bands);
    }

    applyBand(outIdx);

    final links = _ref.read(channelLinkProvider);
    if (isChannelLinked(links, outIdx)) {
      final pair = channelPairOf(outIdx);
      if (pair >= 0 && pair < outputs.length) applyBand(pair);
    }

    state = state.copyWith(outputs: outputs, isDirty: true);
  }

  void toggleOutputBand(int outIdx, int bandIdx) {
    final band = state.outputs[outIdx].bands[bandIdx];
    updateOutputBand(outIdx, bandIdx, band.copyWith(enabled: !band.enabled));
  }

  // ── INPUT 편집 ───────────────────────────────────
  void _updateInput(int idx, InputChannel Function(InputChannel) fn) {
    final inputs = List<InputChannel>.from(state.inputs);
    inputs[idx] = fn(inputs[idx]);
    state = state.copyWith(inputs: inputs, isDirty: true);
  }

  void updateInputGain(int idx, double v) =>
      _updateInput(idx, (i) => i.copyWith(gainDb: v.clamp(-40, 12)));

  void updateInputBand(int inIdx, int bandIdx, PeqBand band) {
    _updateInput(inIdx, (i) {
      final bands = List<PeqBand>.from(i.bands);
      bands[bandIdx] = band;
      return i.copyWith(bands: bands);
    });
  }

  // ── RESET ────────────────────────────────────────
  // Factory 레이어(kFactoryPresetFlat)를 직접 가리킨다 — "초기화"와 "Factory 로드"가
  // 서로 다른 값으로 드리프트하지 않도록 단일 소스로 유지(AOS 항목 C).
  void resetAll() {
    state = kFactoryPresetFlat.build(_ref.read(systemProfileProvider).maxPeqBands);
  }

  void resetOutputBands(int idx, {int bandCount = 20}) {
    _updateOutput(idx, (o) => o.copyWith(bands: OutputChannel.defaultBands(count: bandCount)));
  }

  void resetBandsForProfile(int maxPeqBands) {
    state = state.copyWith(
      outputs: state.outputs.map((o) =>
          o.copyWith(bands: OutputChannel.defaultBands(count: maxPeqBands))).toList(),
    );
  }

  // ── Factory 프리셋 (읽기전용, 별도 계층) ────────────
  /// Factory는 SharedPreferences에 저장되지 않는다 — 코드에 내장된 불변 값을
  /// 그대로 state에 반영할 뿐이라 덮어쓰기/삭제 대상이 아니다.
  void loadFactoryPreset(FactoryPreset preset) {
    final maxPeqBands = _ref.read(systemProfileProvider).maxPeqBands;
    state = preset.build(maxPeqBands).copyWith(isDirty: false);
  }

  // ── User 프리셋 저장/불러오기 (SharedPreferences, Factory와 별도 네임스페이스) ──
  /// "Factory"(대소문자 무관)로는 저장할 수 없다 — 성공 시 true, 예약된 이름이라
  /// 거부되면 false를 반환한다(호출부가 사용자에게 안내).
  Future<bool> savePreset(String name) async {
    final trimmed = name.trim();
    if (isReservedPresetName(trimmed)) return false;
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('dsp_presets') ?? [];
    if (!keys.contains(trimmed)) keys.add(trimmed);
    await prefs.setStringList('dsp_presets', keys);
    await prefs.setString('dsp_preset_$trimmed', state.toJson());
    state = state.copyWith(isDirty: false);
    return true;
  }

  Future<List<String>> getPresets() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('dsp_presets') ?? [];
  }

  Future<void> loadPreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('dsp_preset_$name');
    if (json == null) return;
    try {
      final data = jsonDecode(json);
      final inputs = (data['inputs'] as List).map((i) => InputChannel.fromJson(i)).toList();
      final outputs = (data['outputs'] as List).map((o) => OutputChannel.fromJson(o)).toList();
      state = state.copyWith(inputs: inputs, outputs: outputs, isDirty: false);
    } catch (_) {}
  }

  Future<void> deletePreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('dsp_presets') ?? [];
    keys.remove(name);
    await prefs.setStringList('dsp_presets', keys);
    await prefs.remove('dsp_preset_$name');
  }

  /// 1회성 마이그레이션: Factory/User 분리 이전에 "Factory"라는 이름으로 저장됐던
  /// 유저 프리셋을 찾아 데이터는 보존한 채 이름만 바꾼다(삭제하지 않음 — 사용자
  /// 데이터 손실 방지). 여러 개 있어도 이름이 겹치지 않게 번호를 붙인다.
  Future<void> _migrateLegacyFactoryNamedPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('dsp_presets') ?? [];
    final collisions = keys.where(isReservedPresetName).toList();
    if (collisions.isEmpty) return;

    for (final old in collisions) {
      final json = prefs.getString('dsp_preset_$old');
      keys.remove(old);
      await prefs.remove('dsp_preset_$old');
      if (json == null) continue;

      var newName = '$old (사용자 저장본)';
      var suffix = 2;
      while (keys.contains(newName)) {
        newName = '$old (사용자 저장본 $suffix)';
        suffix++;
      }
      keys.add(newName);
      await prefs.setString('dsp_preset_$newName', json);
    }
    await prefs.setStringList('dsp_presets', keys);
    DspSafetyNotice.show(
        '기존 "Factory"라는 이름으로 저장된 프리셋을 "(사용자 저장본)"으로 이름을 바꿨습니다 — 데이터는 그대로 보존됩니다.');
  }

  // ── SEND TO DSP ───────────────────────────────────
  Future<bool> sendToDsp() async {
    final conn = _ref.read(connectProvider);
    if (conn.connection != ConnectionStatus.connected) return false;

    final profile = _ref.read(systemProfileProvider);
    if (profile.isAdau1466) return false; // 주소맵 미확정

    final notifier = _ref.read(connectProvider.notifier);
    Future<bool> rawWrite(List<int> bytes) => notifier.sendBytes(bytes);
    // profile.adapterFactory를 반드시 경유해야 ValidatingDspAdapter(Safety
    // Validation Layer)가 적용된다 — 이전에는 Adau1701Adapter를 직접 생성해서
    // 이 경로를 우회하고 있었음(Living Speaker gap analysis에서 발견).
    final adapter = profile.adapterFactory(rawWrite);

    for (var chIdx = 0; chIdx < state.outputs.length; chIdx++) {
      final out = state.outputs[chIdx];

      // 뮤트 = 게인 -96dB로 전송 (채널별 측정 시 실제 DSP 소음 차단)
      await adapter.writeGain(chIdx, out.muted ? -96.0 : out.gainDb);
      if (out.muted) continue;

      // Delay
      await adapter.writeDelay(chIdx, out.delayMs);

      // HP 크로스오버
      if (out.hpFilter.type != CrossoverType.bypass) {
        await adapter.writeCrossover(
          chIdx,
          CrossoverConfig(
            side: FilterSide.hpf,
            freqHz: out.hpFilter.frequency,
            slope: _mapCrossoverSlope(out.hpFilter.type),
          ),
        );
      }

      // LP 크로스오버
      if (out.lpFilter.type != CrossoverType.bypass) {
        await adapter.writeCrossover(
          chIdx,
          CrossoverConfig(
            side: FilterSide.lpf,
            freqHz: out.lpFilter.frequency,
            slope: _mapCrossoverSlope(out.lpFilter.type),
          ),
        );
      }

      // PEQ 밴드 — ADAU1701에는 PEQ 모듈이 없어 writeBiquad가 no-op으로 처리함
      // (SystemProfile.maxPeqBands 주석 참고). ADAU1466에서만 실제로 적용됨.
      for (var bandIdx = 0; bandIdx < out.bands.length; bandIdx++) {
        final band = out.bands[bandIdx];
        if (!band.enabled) continue;
        final filter = engine.BiquadFilter(
          frequency: band.frequency,
          gainDb: band.gainDb,
          q: band.q,
          type: _mapFilterType(band.type),
        );
        final coeff = engine.DspEngine.calculate(filter);
        await adapter.writeBiquad(chIdx, bandIdx, BiquadCoeffs.fromEngine(coeff));
      }
    }

    return true;
  }

  engine.FilterType _mapFilterType(FilterType t) {
    switch (t) {
      case FilterType.peaking:   return engine.FilterType.peaking;
      case FilterType.lowShelf:  return engine.FilterType.lowShelf;
      case FilterType.highShelf: return engine.FilterType.highShelf;
      case FilterType.lowPass:   return engine.FilterType.lowPass;
      case FilterType.highPass:  return engine.FilterType.highPass;
      case FilterType.notch:     return engine.FilterType.notch;
      case FilterType.allPass:   return engine.FilterType.peaking;
    }
  }

  CrossoverSlope _mapCrossoverSlope(CrossoverType t) {
    switch (t) {
      case CrossoverType.bypass:        return CrossoverSlope.bypass;
      case CrossoverType.butterworth12: return CrossoverSlope.bw2;
      case CrossoverType.butterworth24: return CrossoverSlope.bw4;
      case CrossoverType.lr12:          return CrossoverSlope.lr2;
      case CrossoverType.lr24:          return CrossoverSlope.lr4;
      case CrossoverType.lr48:          return CrossoverSlope.lr8;
    }
  }
}
