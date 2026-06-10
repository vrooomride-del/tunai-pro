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

class DspScreen extends ConsumerWidget {
  const DspScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dspProvider);
    final ctrl = ref.read(dspProvider.notifier);
    final conn = ref.watch(connectProvider);
    final connected = conn.connection == UartConnectionState.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
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
              final ok = await ctrl.sendToDsp();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok ? '✓ DSP 적용 완료' : '전송 실패'),
              ));
            },
          ),

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
              await ctrl.savePreset(nameCtrl.text.trim());
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${nameCtrl.text} 저장됐습니다.')));
            },
            child: const Text('저장', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLoadDialog(BuildContext context, DspController ctrl) async {
    final presets = await ctrl.getPresets();
    if (presets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장된 프리셋이 없습니다.')));
      return;
    }
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
            children: presets.map((name) => ListTile(
              title: Text(name,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.white24, size: 16),
                onPressed: () async {
                  await ctrl.deletePreset(name);
                  Navigator.pop(context);
                },
              ),
              onTap: () async {
                await ctrl.loadPreset(name);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$name 불러왔습니다.')));
              },
            )).toList(),
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
                  style: TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 1)),
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
                  color: connected ? Colors.white54 : Colors.white24,
                  fontSize: 8, letterSpacing: 1,
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
        color: dim ? Colors.transparent : Colors.white.withOpacity(0.05),
      ),
      child: Text(label,
          style: TextStyle(
            color: dim ? Colors.white38 : Colors.white,
            fontSize: 9, letterSpacing: 2,
          )),
    ),
  );
}

// ── INPUT/OUTPUT 탭 ───────────────────────────────────
class _SectionTabs extends StatelessWidget {
  final bool showInput;
  final DspController ctrl;
  final DspState state;
  const _SectionTabs({required this.showInput, required this.ctrl, required this.state});

  @override
  Widget build(BuildContext context) {
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
          // OUTPUT 탭
          ...state.outputs.asMap().entries.map((e) => _Tab(
            label: e.value.name,
            selected: !showInput && state.selectedOutput == e.key,
            onTap: () => ctrl.selectOutput(e.key),
            muted: e.value.muted,
          )),
        ],
      ),
    );
  }
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
            color: muted ? Colors.red.withOpacity(0.5)
                : selected ? Colors.white : Colors.white38,
            fontSize: 9, letterSpacing: 1.5,
          )),
    ),
  );
}

// ── OUTPUT 뷰 ────────────────────────────────────────
class _OutputView extends StatelessWidget {
  final DspState state;
  final DspController ctrl;
  const _OutputView({required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final outIdx = state.selectedOutput;
    final out = state.outputs[outIdx];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 좌측: 채널 스트립 목록
        SizedBox(
          width: 200,
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
                  style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3)),
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
                      style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3)),
                  const SizedBox(width: 12),
                  Text('20 BANDS',
                      style: const TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => ctrl.resetOutputBands(outIdx),
                    child: const Text('RESET BANDS',
                        style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 5개씩 4행으로
              ...List.generate(4, (row) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(5, (col) {
                    final bandIdx = row * 5 + col;
                    if (bandIdx >= out.bands.length) return const Expanded(child: SizedBox());
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: col < 4 ? 5 : 0),
                        child: PeqBandEditor(
                          band: out.bands[bandIdx],
                          index: bandIdx,
                          selected: state.selectedBand == bandIdx,
                          onChanged: (b) => ctrl.updateOutputBand(outIdx, bandIdx, b),
                          onSelect: () => ctrl.selectBand(bandIdx),
                        ),
                      ),
                    );
                  }),
                ),
              )),
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
          width: 200,
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
                  style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3)),
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
