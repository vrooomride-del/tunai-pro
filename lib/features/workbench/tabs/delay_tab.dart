// ── Delay Tab — Phase E ───────────────────────────────────────────────────────
// Time alignment per driver channel.
// No DSP write. No SafeLoad. No register addresses. Data model only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';

class DelayTab extends ConsumerStatefulWidget {
  final String projectId;
  const DelayTab({super.key, required this.projectId});

  @override
  ConsumerState<DelayTab> createState() => _DelayTabState();
}

class _DelayTabState extends ConsumerState<DelayTab> {
  String? _selectedChannelId;

  TuningProjectState get _tuning => ref.read(proProjectStoreProvider)
      .projects.where((p) => p.id == widget.projectId).firstOrNull
      ?.tuningState ?? TuningProjectState.createDefault();

  Future<void> _saveControl(ChannelControlState updated) async {
    final newTuning = _tuning.replaceControl(updated);
    await ref.read(proProjectStoreProvider.notifier)
        .updateTuningState(widget.projectId, newTuning);
  }

  Future<void> _adjustDelay(String channelId, double delta) async {
    final ctrl = _tuning.getOrCreateControl(channelId);
    final newDelay = (ctrl.delayMs + delta).clamp(0.0, 20.0);
    await _saveControl(ctrl.copyWith(delayMs: newDelay));
  }

  Future<void> _resetDelay(String channelId) async {
    final ctrl = _tuning.getOrCreateControl(channelId);
    await _saveControl(ctrl.copyWith(delayMs: 0.0));
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
        child: _DelayChannelList(
          drivers: drivers,
          tuning: tuning,
          selectedId: selectedId,
          onSelect: (id) => setState(() => _selectedChannelId = id),
        ),
      ),
      Container(width: 0.5, color: kProBorder),

      // ── Right: delay editor ─────────────────────────────────────────────
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.access_time_outlined,
                  color: kProAccent.withValues(alpha: 0.6), size: 16),
              const SizedBox(width: 8),
              Text('Delay / Alignment', style: proTitle(size: 15)),
              const Spacer(),
              Text('Rev ${tuning.tuningRevision}',
                  style: proLabel(size: 9, color: Colors.white24, spacing: 1)),
            ]),
            const SizedBox(height: 3),
            Text('Time alignment per driver channel. '
                'Acoustic verification will be added later.',
                style: proSubtitle()),
            const SizedBox(height: 16),

            // Channel header
            _DelayChannelHeader(driver: selectedDriver, ctrl: ctrl),
            const SizedBox(height: 14),

            // Delay editor
            _DelayEditor(
              ctrl: ctrl,
              onStep: (delta) => _adjustDelay(selectedId, delta),
              onManual: (v) => _saveControl(ctrl.copyWith(delayMs: v.clamp(0.0, 20.0))),
              onReset: () => _resetDelay(selectedId),
            ),
            const SizedBox(height: 14),

            // Graph placeholder
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: kProSurface,
                border: Border.all(color: kProBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timeline_outlined, color: Colors.white12, size: 20),
                  const SizedBox(height: 6),
                  Text('Impulse and acoustic phase alignment preview — coming later',
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

class _DelayChannelList extends StatelessWidget {
  final List<DriverChannel> drivers;
  final TuningProjectState tuning;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const _DelayChannelList({required this.drivers, required this.tuning,
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
                    ctrl.delayMs == 0.0
                        ? '0.00 ms'
                        : '${ctrl.delayMs.toStringAsFixed(2)} ms',
                    style: proSubtitle(size: 9),
                  ),
                  if (ctrl.hasDelay) ...[
                    const SizedBox(height: 3),
                    Text('≈ ${ctrl.delayDistanceCm.toStringAsFixed(1)} cm',
                        style: proSubtitle(size: 9,
                            color: kProAccent.withValues(alpha: 0.7))),
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

class _DelayChannelHeader extends StatelessWidget {
  final DriverChannel driver;
  final ChannelControlState ctrl;
  const _DelayChannelHeader({required this.driver, required this.ctrl});

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
      if (ctrl.hasDelay) ...[
        const SizedBox(width: 12),
        const ProStatusPill(label: 'DELAY ACTIVE', color: kProAccent),
      ],
    ]),
  );
}

class _DelayEditor extends StatefulWidget {
  final ChannelControlState ctrl;
  final void Function(double delta) onStep;
  final void Function(double value) onManual;
  final VoidCallback onReset;
  const _DelayEditor({required this.ctrl, required this.onStep,
      required this.onManual, required this.onReset});

  @override
  State<_DelayEditor> createState() => _DelayEditorState();
}

class _DelayEditorState extends State<_DelayEditor> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.ctrl.delayMs.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(_DelayEditor old) {
    super.didUpdateWidget(old);
    if (old.ctrl.delayMs != widget.ctrl.delayMs) {
      _ctrl.text = widget.ctrl.delayMs.toStringAsFixed(2);
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
  Widget build(BuildContext context) {
    final distCm = widget.ctrl.delayDistanceCm;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TIME DELAY', style: proLabel(size: 9, spacing: 1.8)),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          // ms field
          SizedBox(
            width: 80,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ms', style: proLabel(size: 8, spacing: 0.5)),
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
                      const TextInputType.numberWithOptions(decimal: true),
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
          // Step buttons
          Wrap(spacing: 6, children: [
            _SmallBtn(label: '−0.10', onTap: () => widget.onStep(-0.10)),
            _SmallBtn(label: '−0.01', onTap: () => widget.onStep(-0.01)),
            _SmallBtn(label: '+0.01', onTap: () => widget.onStep(0.01)),
            _SmallBtn(label: '+0.10', onTap: () => widget.onStep(0.10)),
          ]),
          const SizedBox(width: 12),
          _SmallBtn(label: 'Reset', onTap: widget.onReset, color: kProRed),
        ]),
        const SizedBox(height: 10),
        Text(
          widget.ctrl.delayMs == 0.0
              ? '≈ 0 cm acoustic offset'
              : '≈ ${distCm.toStringAsFixed(1)} cm acoustic offset',
          style: proValue(size: 11,
              color: widget.ctrl.hasDelay
                  ? kProAccent.withValues(alpha: 0.8)
                  : Colors.white24),
        ),
        const SizedBox(height: 3),
        Text('Range: 0.00 – 20.00 ms', style: proSubtitle(size: 9)),
      ]),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

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
      const Icon(Icons.access_time_outlined, color: Colors.white12, size: 28),
      const SizedBox(height: 12),
      Text(message, style: proSubtitle(size: 11), textAlign: TextAlign.center),
    ]),
  );
}
