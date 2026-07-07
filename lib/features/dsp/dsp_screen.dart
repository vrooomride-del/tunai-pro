import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dsp_state.dart';
import 'dsp_controller.dart';
import 'widgets/bode_plot.dart';
import 'widgets/peq_band.dart';
import 'widgets/crossover.dart';
import 'widgets/channel_strip.dart';
import '../connect/connect_controller.dart';
import 'widgets/ai_panel.dart';
import '../../core/factory_preset.dart';
import '../../core/profiles/system_profile.dart';
import '../mic/mic_measurement_controller.dart';
import '../../core/channel_link_provider.dart';
import 'master_volume_controller.dart';

class DspScreen extends ConsumerWidget {
  const DspScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dspProvider);
    final ctrl = ref.read(dspProvider.notifier);
    final conn = ref.watch(connectProvider);
    final connected = conn.connected;
    final profile = ref.watch(systemProfileProvider);
    final micState = ref.watch(micMeasurementProvider);
    final freqResponse = micState.frequencyResponse.isEmpty ? null : micState.frequencyResponse;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      bottomSheet: AiTuningPanel(frequencyResponse: freqResponse),
      body: Column(
        children: [
          // ── 상단 툴바 ────────────────────────────────
          _TopBar(
            isDirty: state.isDirty,
            connected: connected,
            onSave: () => _showSaveDialog(context, ctrl),
            onLoad: () => _showLoadDialog(context, ctrl),
            onReset: ctrl.resetAll,
            onSend: () async {
              if (!connected) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('CONNECT 탭에서 DSP 연결 먼저')));
                return;
              }
              final messenger = ScaffoldMessenger.of(context);
              final ok = await ctrl.sendToDsp();
              messenger.showSnackBar(SnackBar(
                content: Text(ok ? '✓ DSP 적용 완료' : '전송 실패'),
              ));
            },
          ),

          // ── 보드 선택 배너 ───────────────────────────
          _BoardSelector(profile: profile, onSelect: (p) {
            ref.read(systemProfileProvider.notifier).state = p;
            ctrl.resetBandsForProfile(p.maxPeqBands);
          }),

          // ── Master Volume ─────────────────────────────
          if (connected) const _MasterVolumeSection(),

          // ── INPUT / OUTPUT 탭 선택 ───────────────────
          _SectionTabs(showInput: state.showInput, ctrl: ctrl, state: state),

          Expanded(
            child: state.showInput
                ? _InputView(state: state, ctrl: ctrl)
                : _OutputView(state: state, ctrl: ctrl),
          ),
        ],
      ),
    );
  }

  void _showSaveDialog(BuildContext context, DspController ctrl) {
    final nameCtrl = TextEditingController(
        text: 'Preset ${DateTime.now().millisecondsSinceEpoch}');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('프리셋 저장',
            style: TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'NAME',
            labelStyle: TextStyle(color: Colors.white38, fontSize: 10),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final ok = await ctrl.savePreset(name);
              if (!ok) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('"Factory"는 예약된 이름이라 사용할 수 없습니다. 다른 이름을 입력하세요.')));
                return; // 다이얼로그 유지 — 사용자가 이름을 다시 입력
              }
              nav.pop();
              messenger.showSnackBar(SnackBar(content: Text('$name 저장됐습니다.')));
            },
            child: const Text('저장', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLoadDialog(BuildContext context, DspController ctrl) async {
    // Factory는 항상 최소 1개 존재하므로(kFactoryPresets) 유저 프리셋이 비어 있어도
    // 다이얼로그를 열 수 있다 — "불러올 게 없다"는 상황 자체가 없어짐.
    final presets = await ctrl.getPresets();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('프리셋 불러오기',
            style: TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2)),
        content: SizedBox(
          width: 300,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('FACTORY (읽기전용)',
                    style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
              ),
              ...kFactoryPresets.map((p) => ListTile(
                title: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                subtitle: Text(p.description,
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
                onTap: () {
                  final nav = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  ctrl.loadFactoryPreset(p);
                  nav.pop();
                  messenger.showSnackBar(SnackBar(content: Text('${p.name} 불러왔습니다.')));
                },
              )),
              if (presets.isNotEmpty) ...[
                const Divider(color: Colors.white12),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('MY PRESETS',
                      style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
                ),
                ...presets.map((name) => ListTile(
                  title: Text(name,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.white24, size: 16),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      await ctrl.deletePreset(name);
                      nav.pop();
                    },
                  ),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    final snackbar = ScaffoldMessenger.of(context);
                    await ctrl.loadPreset(name);
                    nav.pop();
                    snackbar.showSnackBar(
                        SnackBar(content: Text('$name 불러왔습니다.')));
                  },
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── 상단 툴바 ─────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final bool isDirty;
  final bool connected;
  final VoidCallback onSave;
  final VoidCallback onLoad;
  final VoidCallback onReset;
  final VoidCallback onSend;

  const _TopBar({
    required this.isDirty, required this.connected,
    required this.onSave, required this.onLoad,
    required this.onReset, required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          const Text('TUNAI PRO',
              style: TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w200, letterSpacing: 6)),
          if (isDirty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('UNSAVED',
                  style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
            ),
          ],
          const Spacer(),
          // 연결 상태
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(
                  color: connected ? Colors.white38 : Colors.white12, width: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(connected ? '● DSP' : '○ NO DSP',
                style: TextStyle(
                  color: connected ? Colors.white70 : Colors.white38,
                  fontSize: 11, letterSpacing: 1,
                )),
          ),
          _Btn('LOAD', onLoad, dim: true),
          const SizedBox(width: 8),
          _Btn('SAVE', onSave, dim: true),
          const SizedBox(width: 8),
          _Btn('RESET', onReset, dim: true),
          const SizedBox(width: 12),
          _Btn('SEND TO DSP', onSend, dim: !connected),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool dim;
  const _Btn(this.label, this.onTap, {this.dim = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: dim ? Colors.white24 : Colors.white, width: 0.5),
        borderRadius: BorderRadius.circular(4),
        color: dim ? Colors.transparent : Colors.white.withValues(alpha: 0.05),
      ),
      child: Text(label,
          style: TextStyle(
            color: dim ? Colors.white54 : Colors.white,
            fontSize: 11, letterSpacing: 2,
          )),
    ),
  );
}

// ── INPUT/OUTPUT 탭 ───────────────────────────────────
class _SectionTabs extends ConsumerWidget {
  final bool showInput;
  final DspController ctrl;
  final DspState state;
  const _SectionTabs({required this.showInput, required this.ctrl, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(channelLinkProvider);

    // OUTPUT 탭 목록: L 탭 → 🔗 버튼 → R 탭 순으로 삽입
    final outputWidgets = <Widget>[];
    for (int i = 0; i < state.outputs.length; i++) {
      outputWidgets.add(_Tab(
        label: state.outputs[i].name,
        selected: !showInput && state.selectedOutput == i,
        onTap: () => ctrl.selectOutput(i),
        muted: state.outputs[i].muted,
      ));
      // L 탭 뒤에 🔗 버튼 삽입 (even index = L)
      if (i.isEven && i + 1 < state.outputs.length) {
        final group = channelGroupOf(i);
        final linked = group < links.length && links[group];
        outputWidgets.add(_LinkToggle(
          linked: linked,
          onToggle: () {
            final updated = List<bool>.from(links);
            updated[group] = !updated[group];
            ref.read(channelLinkProvider.notifier).state = updated;
          },
        ));
      }
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: Row(
        children: [
          // INPUT 탭
          ...state.inputs.asMap().entries.map((e) => _Tab(
            label: e.value.name,
            selected: showInput && state.selectedInput == e.key,
            onTap: () => ctrl.selectInput(e.key),
          )),
          Container(width: 1, height: 32, color: Colors.white12),
          // OUTPUT 탭 + 🔗 토글
          ...outputWidgets,
        ],
      ),
    );
  }
}

class _LinkToggle extends StatelessWidget {
  final bool linked;
  final VoidCallback onToggle;
  const _LinkToggle({required this.linked, required this.onToggle});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onToggle,
    child: Container(
      width: 22,
      height: 32,
      alignment: Alignment.center,
      child: Text(
        linked ? '🔗' : '⛓️',
        style: const TextStyle(fontSize: 10),
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.selected,
      required this.onTap, this.muted = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? Colors.white : Colors.transparent, width: 1.5),
        ),
      ),
      child: Text(label,
          style: TextStyle(
            color: muted ? Colors.red.withValues(alpha: 0.6)
                : selected ? Colors.white : Colors.white60,
            fontSize: 13, letterSpacing: 1.5,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w300,
          )),
    ),
  );
}

// ── OUTPUT 뷰 ────────────────────────────────────────
class _OutputView extends ConsumerWidget {
  final DspState state;
  final DspController ctrl;
  const _OutputView({required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxBands = ref.watch(systemProfileProvider).maxPeqBands;
    final outIdx = state.selectedOutput;
    final out = state.outputs[outIdx];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 좌측: 채널 스트립 목록
        SizedBox(
          width: 220,
          child: ClipRect(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: state.outputs.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutputChannelStrip(
                channel: e.value,
                selected: e.key == outIdx,
                onSelect: () => ctrl.selectOutput(e.key),
                onGainChanged: (v) => ctrl.updateOutputGain(e.key, v),
                onDelayChanged: (v) => ctrl.updateOutputDelay(e.key, v),
                onMuteToggle: () => ctrl.toggleMute(e.key),
                onPolarityToggle: () => ctrl.togglePolarity(e.key),
              ),
            )).toList(),
          ),
          ),
        ),

        // 우측: Bode plot + 크로스오버 + PEQ
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 12, 16, 32),
            children: [
              // Bode plot
              DspBodePlot(
                bands: out.bands,
                hpFilter: out.hpFilter,
                lpFilter: out.lpFilter,
                gainDb: out.gainDb,
              ),
              const SizedBox(height: 12),

              // 크로스오버
              const Text('CROSSOVER',
                  style: TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 3)),
              const SizedBox(height: 8),
              CrossoverEditor(
                hpFilter: out.hpFilter,
                lpFilter: out.lpFilter,
                onHpChanged: (f) => ctrl.updateHpFilter(outIdx, f),
                onLpChanged: (f) => ctrl.updateLpFilter(outIdx, f),
              ),
              const SizedBox(height: 16),

              // PEQ 밴드 (20밴드)
              Row(
                children: [
                  const Text('PEQ',
                      style: TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 3)),
                  const SizedBox(width: 12),
                  Text('$maxBands BANDS',
                      style: const TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => ctrl.resetOutputBands(outIdx, bandCount: maxBands),
                    child: const Text('RESET BANDS',
                        style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 4개씩 행으로 — maxBands 수만 렌더링, 마지막 행 빈 슬롯으로 4칸 고정
              ...List.generate((maxBands / 4).ceil(), (row) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(4, (col) {
                      final bandIdx = row * 4 + col;
                      if (bandIdx < maxBands) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: col < 3 ? 5 : 0),
                            child: PeqBandEditor(
                              band: out.bands[bandIdx],
                              index: bandIdx,
                              selected: state.selectedBand == bandIdx,
                              onChanged: (b) => ctrl.updateOutputBand(outIdx, bandIdx, b),
                              onSelect: () => ctrl.selectBand(bandIdx),
                            ),
                          ),
                        );
                      }
                      return const Expanded(child: SizedBox());
                    }),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

// ── INPUT 뷰 ─────────────────────────────────────────
class _InputView extends StatelessWidget {
  final DspState state;
  final DspController ctrl;
  const _InputView({required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final inIdx = state.selectedInput;
    final inp = state.inputs[inIdx];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 좌측: 입력 채널 스트립
        SizedBox(
          width: 220,
          child: ClipRect(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: state.inputs.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InputChannelStrip(
                channel: e.value,
                selected: e.key == inIdx,
                onSelect: () => ctrl.selectInput(e.key),
                onGainChanged: (v) => ctrl.updateInputGain(e.key, v),
              ),
            )).toList(),
          ),
          ),
        ),

        // 우측: PEQ 10밴드
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 12, 16, 32),
            children: [
              DspBodePlot(
                bands: inp.bands,
                hpFilter: inp.hpFilter,
                lpFilter: inp.lpFilter,
                gainDb: inp.gainDb,
              ),
              const SizedBox(height: 16),
              const Text('INPUT PEQ',
                  style: TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 3)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(inp.bands.length, (i) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < inp.bands.length - 1 ? 5 : 0),
                    child: PeqBandEditor(
                      band: inp.bands[i],
                      index: i,
                      selected: state.selectedBand == i,
                      onChanged: (b) => ctrl.updateInputBand(inIdx, i, b),
                      onSelect: () => ctrl.selectBand(i),
                    ),
                  ),
                )),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 보드 선택 배너 ─────────────────────────────────────────────

class _BoardSelector extends StatelessWidget {
  final SystemProfile profile;
  final ValueChanged<SystemProfile> onSelect;

  const _BoardSelector({required this.profile, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F0F0F),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          const Text('BOARD',
              style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 3)),
          const SizedBox(width: 16),
          ...kAllSystemProfiles.map((p) => _ProfileChip(
            label: p.displayName,
            chipLabel: p.chipLabel,
            selected: p.id == profile.id,
            onTap: () => onSelect(p),
          )),
          const Spacer(),
        ],
      ),
    );
  }
}

// ── Master Volume ─────────────────────────────────────────────

class _MasterVolumeSection extends ConsumerWidget {
  const _MasterVolumeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vol = ref.watch(masterVolumeProvider);
    final ctrl = ref.read(masterVolumeProvider.notifier);

    return Container(
      color: const Color(0xFF0D0D0D),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('MASTER VOL',
                  style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 3)),
              const SizedBox(width: 12),
              Text('${vol.toStringAsFixed(1)} dB',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
              const Spacer(),
              // 테스트 버튼 3개
              for (final db in [-60.0, -50.0, -40.0]) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => ctrl.setVolume(db),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: vol == db ? Colors.white54 : Colors.white24, width: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('${db.toInt()}',
                        style: TextStyle(
                          color: vol == db ? Colors.white70 : Colors.white38,
                          fontSize: 10, letterSpacing: 1,
                        )),
                  ),
                ),
              ],
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 1.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white54,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: Colors.white12,
            ),
            child: Slider(
              value: vol,
              min: -70, max: 0,
              onChanged: (v) => ctrl.updateUiOnly(v),
              onChangeEnd: (v) => ctrl.setVolume(v),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  final String label;
  final String chipLabel;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileChip({
    required this.label, required this.chipLabel,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? Colors.white54 : Colors.white12,
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(3),
          color: selected ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 11, letterSpacing: 1,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w300,
                )),
            Text(chipLabel,
                style: TextStyle(
                  color: selected ? Colors.white54 : Colors.white24,
                  fontSize: 9, letterSpacing: 1,
                )),
          ],
        ),
      ),
    );
  }
}
