// ── Gain Tab — Phase E ────────────────────────────────────────────────────────
// Channel level matching and output trim.
// No DSP write. No SafeLoad. No register addresses. Data model only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';

class GainTab extends ConsumerStatefulWidget {
  final String projectId;
  const GainTab({super.key, required this.projectId});

  @override
  ConsumerState<GainTab> createState() => _GainTabState();
}

class _GainTabState extends ConsumerState<GainTab> {
  String? _selectedChannelId;

  TuningProjectState get _tuning => ref.read(proProjectStoreProvider)
      .projects.where((p) => p.id == widget.projectId).firstOrNull
      ?.tuningState ?? TuningProjectState.createDefault();

  Future<void> _saveControl(ChannelControlState updated) async {
    final newTuning = _tuning.replaceControl(updated);
    await ref.read(proProjectStoreProvider.notifier)
        .updateTuningState(widget.projectId, newTuning);
  }

  Future<void> _adjustGain(String channelId, double delta) async {
    final ctrl = _tuning.getOrCreateControl(channelId);
    final newGain = (ctrl.gainDb + delta).clamp(-24.0, 12.0);
    await _saveControl(ctrl.copyWith(gainDb: newGain));
  }

  Future<void> _toggleMute(String channelId) async {
    final ctrl = _tuning.getOrCreateControl(channelId);
    await _saveControl(ctrl.copyWith(muted: !ctrl.muted));
  }

  Future<void> _toggleSolo(String channelId) async {
    final ctrl = _tuning.getOrCreateControl(channelId);
    await _saveControl(ctrl.copyWith(solo: !ctrl.solo));
  }

  Future<void> _resetGain(String channelId) async {
    final ctrl = _tuning.getOrCreateControl(channelId);
    await _saveControl(ctrl.copyWith(gainDb: 0.0, muted: false, solo: false));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == widget.projectId).firstOrNull;
    final drivers = project?.acousticState.driverChannels ?? [];
    final tuning = project?.tuningState ?? TuningProjectState.createDefault();

    if (drivers.isEmpty) {
      return const _EmptyState(
          message: 'No driver channels configured yet. Import measurements first.');
    }

    final selectedId = _selectedChannelId ?? drivers.first.id;
    final selectedDriver =
        drivers.firstWhere((d) => d.id == selectedId, orElse: () => drivers.first);
    final ctrl = tuning.getOrCreateControl(selectedId);

    return Row(children: [
      // ── Left: channel list ──────────────────────────────────────────────
      SizedBox(
        width: 192,
        child: _GainChannelList(
          drivers: drivers,
          tuning: tuning,
          selectedId: selectedId,
          onSelect: (id) => setState(() => _selectedChannelId = id),
        ),
      ),
      Container(width: 0.5, color: kProBorder),

      // ── Right: gain editor ──────────────────────────────────────────────
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.bar_chart_outlined,
                  color: kProAccent.withValues(alpha: 0.6), size: 16),
              const SizedBox(width: 8),
              Text('Gain / Trim', style: proTitle(size: 15)),
              const Spacer(),
              Text('Rev ${tuning.tuningRevision}',
                  style: proLabel(size: 9, color: Colors.white24, spacing: 1)),
            ]),
            const SizedBox(height: 3),
            Text('Channel level matching and output trim. '
                'Hardware write remains disabled. Use the Hardware tab for dry-run planning.',
                style: proSubtitle()),
            const SizedBox(height: 16),

            // Channel header
            _GainChannelHeader(
              driver: selectedDriver,
              ctrl: ctrl,
              onMute: () => _toggleMute(selectedId),
              onSolo: () => _toggleSolo(selectedId),
              onReset: () => _resetGain(selectedId),
            ),
            const SizedBox(height: 14),

            // Gain field + step buttons
            _GainEditor(
              ctrl: ctrl,
              onStep: (delta) => _adjustGain(selectedId, delta),
              onManual: (v) => _saveControl(ctrl.copyWith(gainDb: v.clamp(-24.0, 12.0))),
            ),
            const SizedBox(height: 14),

            // Level meter placeholder
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: kProSurface,
                border: Border.all(color: kProBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bar_chart_outlined, color: Colors.white12, size: 20),
                  const SizedBox(height: 6),
                  Text('Level and headroom preview — protection verification is available in the Protection tab',
                      style: proSubtitle(size: 9)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _GainChannelList extends StatelessWidget {
  final List<DriverChannel> drivers;
  final TuningProjectState tuning;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const _GainChannelList({required this.drivers, required this.tuning,
      required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    color: kProPanel,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Text('CHANNELS', style: proLabel(size: 9, color: Colors.white24, spacing: 2.5)),
      ),
      Expanded(
        child: ListView(
          padding: EdgeInsets.zero,
          children: drivers.map((d) {
            final active = d.id == selectedId;
            final ctrl = tuning.getOrCreateControl(d.id);
            return GestureDetector(
              onTap: () => onSelect(d.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: active ? kProAccent.withValues(alpha: 0.09) : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                        color: active ? kProAccent : Colors.transparent, width: 2),
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(d.name,
                          style: proTitle(size: 11,
                              color: active ? Colors.white : const Color(0xFF6B7280))),
                    ),
                    Text(d.role.short,
                        style: proLabel(size: 8,
                            color: active ? kProAccent : Colors.white24, spacing: 0.5)),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    ctrl.gainDb == 0.0
                        ? '0.0 dB'
                        : '${ctrl.gainDb >= 0 ? '+' : ''}${ctrl.gainDb.toStringAsFixed(1)} dB',
                    style: proSubtitle(size: 9),
                  ),
                  if (ctrl.muted || ctrl.solo) ...[
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, children: [
                      if (ctrl.muted) const ProStatusPill(label: 'MUTE', color: kProRed),
                      if (ctrl.solo)  const ProStatusPill(label: 'SOLO', color: kProAmber),
                    ]),
                  ],
                ]),
              ),
            );
          }).toList(),
        ),
      ),
    ]),
  );
}

class _GainChannelHeader extends StatelessWidget {
  final DriverChannel driver;
  final ChannelControlState ctrl;
  final VoidCallback onMute;
  final VoidCallback onSolo;
  final VoidCallback onReset;
  const _GainChannelHeader({required this.driver, required this.ctrl,
      required this.onMute, required this.onSolo, required this.onReset});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(driver.name, style: proTitle(size: 13)),
          Text('${driver.role.label} · ${driver.side.label} · OUT ${driver.dspOutputIndex ?? '—'}',
              style: proSubtitle(size: 10)),
        ]),
      ),
      const SizedBox(width: 12),
      _ToggleBtn(label: 'MUTE', active: ctrl.muted, color: kProRed, onTap: onMute),
      const SizedBox(width: 6),
      _ToggleBtn(label: 'SOLO', active: ctrl.solo, color: kProAmber, onTap: onSolo),
      const SizedBox(width: 8),
      _SmallBtn(label: 'Reset Gain', onTap: onReset, color: kProRed),
    ]),
  );
}

class _GainEditor extends StatefulWidget {
  final ChannelControlState ctrl;
  final void Function(double delta) onStep;
  final void Function(double value) onManual;
  const _GainEditor({required this.ctrl, required this.onStep, required this.onManual});

  @override
  State<_GainEditor> createState() => _GainEditorState();
}

class _GainEditorState extends State<_GainEditor> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.ctrl.gainDb.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(_GainEditor old) {
    super.didUpdateWidget(old);
    if (old.ctrl.gainDb != widget.ctrl.gainDb) {
      _ctrl.text = widget.ctrl.gainDb.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text);
    if (v != null) widget.onManual(v);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('GAIN TRIM', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Manual dB field
        SizedBox(
          width: 80,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('dB', style: proLabel(size: 8, spacing: 0.5)),
            const SizedBox(height: 3),
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: kProBg,
                border: Border.all(color: kProBorder),
                borderRadius: BorderRadius.circular(3),
              ),
              child: TextField(
                controller: _ctrl,
                onSubmitted: (_) => _commit(),
                onEditingComplete: _commit,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                style: proTitle(size: 11),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  border: InputBorder.none,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        // Step buttons — Flexible prevents overflow in narrow columns
        Flexible(
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            _SmallBtn(label: '−1 dB',   onTap: () => widget.onStep(-1.0)),
            _SmallBtn(label: '−0.5 dB', onTap: () => widget.onStep(-0.5)),
            _SmallBtn(label: '+0.5 dB', onTap: () => widget.onStep(0.5)),
            _SmallBtn(label: '+1 dB',   onTap: () => widget.onStep(1.0)),
          ]),
        ),
      ]),
      const SizedBox(height: 4),
      Text('Range: −24 to +12 dB', style: proSubtitle(size: 9)),
    ]),
  );
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _ToggleBtn({required this.label, required this.active,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(3),
        color: active ? color.withValues(alpha: 0.1) : Colors.transparent,
      ),
      child: Text(label,
          style: TextStyle(
              color: active ? color : Colors.white38,
              fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w500)),
    ),
  );
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _SmallBtn({required this.label, required this.onTap, this.color = kProAccent});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10)),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.bar_chart_outlined, color: Colors.white12, size: 28),
      const SizedBox(height: 12),
      Text(message, style: proSubtitle(size: 11), textAlign: TextAlign.center),
    ]),
  );
}
