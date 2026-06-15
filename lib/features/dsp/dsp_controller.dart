import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dsp_state.dart';
import '../../core/dsp_engine.dart' as engine;
import '../../core/dsp/dsp_adapter.dart';
import '../../core/dsp/adau1701_adapter.dart';
import '../../core/profiles/system_profile.dart';
import '../connect/connect_controller.dart';

/// 선택된 시스템 프로파일 (JAB4 / 파란보드)
final systemProfileProvider = StateProvider<SystemProfile>(
  (ref) => kTunaiOneSystemProfile,
);

final dspProvider = StateNotifierProvider<DspController, DspState>(
  (ref) => DspController(ref),
);

class DspController extends StateNotifier<DspState> {
  final Ref _ref;
  DspController(this._ref) : super(DspState.initial());

  // ── 탭 전환 ──────────────────────────────────────
  void selectOutput(int i) => state = state.copyWith(selectedOutput: i, showInput: false, selectedBand: 0);
  void selectInput(int i)  => state = state.copyWith(selectedInput: i, showInput: true, selectedBand: 0);
  void selectBand(int i)   => state = state.copyWith(selectedBand: i);

  // ── OUTPUT 편집 ──────────────────────────────────
  void _updateOutput(int idx, OutputChannel Function(OutputChannel) fn) {
    final outputs = List<OutputChannel>.from(state.outputs);
    outputs[idx] = fn(outputs[idx]);
    state = state.copyWith(outputs: outputs, isDirty: true);
  }

  void updateOutputGain(int idx, double v) =>
      _updateOutput(idx, (o) => o.copyWith(gainDb: v.clamp(-40, 12)));

  void updateOutputDelay(int idx, double v) =>
      _updateOutput(idx, (o) => o.copyWith(delayMs: v.clamp(0, 100)));

  void toggleMute(int idx) =>
      _updateOutput(idx, (o) => o.copyWith(muted: !o.muted));

  void togglePolarity(int idx) =>
      _updateOutput(idx, (o) => o.copyWith(polarity: !o.polarity));

  void updateHpFilter(int idx, CrossoverFilter f) =>
      _updateOutput(idx, (o) => o.copyWith(hpFilter: f));

  void updateLpFilter(int idx, CrossoverFilter f) =>
      _updateOutput(idx, (o) => o.copyWith(lpFilter: f));

  void updateOutputBand(int outIdx, int bandIdx, PeqBand band) {
    _updateOutput(outIdx, (o) {
      final bands = List<PeqBand>.from(o.bands);
      bands[bandIdx] = band;
      return o.copyWith(bands: bands);
    });
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
  void resetAll() {
    state = DspState.initial();
  }

  void resetOutputBands(int idx) {
    _updateOutput(idx, (o) => o.copyWith(bands: OutputChannel.defaultBands()));
  }

  // ── 프리셋 저장/불러오기 ──────────────────────────
  Future<void> savePreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('dsp_presets') ?? [];
    if (!keys.contains(name)) keys.add(name);
    await prefs.setStringList('dsp_presets', keys);
    await prefs.setString('dsp_preset_$name', state.toJson());
    state = state.copyWith(isDirty: false);
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

  // ── SEND TO DSP ───────────────────────────────────
  Future<bool> sendToDsp() async {
    final conn = _ref.read(connectProvider);
    if (conn.connection != UartConnectionState.connected) return false;

    final profile = _ref.read(systemProfileProvider);
    if (profile.isAdau1466) return false; // 주소맵 미확정

    final notifier = _ref.read(connectProvider.notifier);
    Future<bool> rawWrite(List<int> bytes) => notifier.sendBytes(bytes);
    final adapter = Adau1701Adapter(send: rawWrite);

    for (var chIdx = 0; chIdx < state.outputs.length; chIdx++) {
      final out = state.outputs[chIdx];

      if (out.muted) continue;

      // Gain
      await adapter.writeGain(chIdx, out.gainDb);

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

      // PEQ 밴드
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
