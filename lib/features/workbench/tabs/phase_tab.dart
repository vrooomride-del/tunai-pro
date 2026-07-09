// ── Phase Tab — Phase E ───────────────────────────────────────────────────────
// Polarity and phase review per channel.
// Polarity source of truth: CrossoverChannelState.polarityInverted
// Phase offset stored in ChannelControlState.phaseOffsetDeg
// No DSP write. No SafeLoad. No register addresses. Data model only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';

class PhaseTab extends ConsumerStatefulWidget {
  final String projectId;
  const PhaseTab({super.key, required this.projectId});

  @override
  ConsumerState<PhaseTab> createState() => _PhaseTabState();
}

class _PhaseTabState extends ConsumerState<PhaseTab> {
  String? _selectedChannelId;

  TuningProjectState get _tuning => ref.read(proProjectStoreProvider)
      .projects.where((p) => p.id == widget.projectId).firstOrNull
      ?.tuningState ?? TuningProjectState.createDefault();

  Future<void> _togglePolarity(String channelId) async {
    final tuning = _tuning;
    final xoCh = tuning.getOrCreateCrossoverChannel(channelId);
    final newTuning = tuning.replaceCrossoverChannel(
        xoCh.copyWith(polarityInverted: !xoCh.polarityInverted));
    await ref.read(proProjectStoreProvider.notifier)
        .updateTuningState(widget.projectId, newTuning);
  }

  Future<void> _savePhaseOffset(String channelId, double deg) async {
    final tuning = _tuning;
    final ctrl = tuning.getOrCreateControl(channelId);
    final newTuning = tuning.replaceControl(ctrl.copyWith(phaseOffsetDeg: deg));
    await ref.read(proProjectStoreProvider.notifier)
        .updateTuningState(widget.projectId, newTuning);
  }

  Future<void> _resetPhase(String channelId) async {
    await _savePhaseOffset(channelId, 0.0);
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
    final xoCh = tuning.getOrCreateCrossoverChannel(selectedId);
    final ctrl = tuning.getOrCreateControl(selectedId);

    return Row(children: [
      // ── Left: channel list ──────────────────────────────────────────────
      SizedBox(
        width: 192,
        child: _PhaseChannelList(
          drivers: drivers,
          tuning: tuning,
          selectedId: selectedId,
          onSelect: (id) => setState(() => _selectedChannelId = id),
        ),
      ),
      Container(width: 0.5, color: kProBorder),

      // ── Right: phase / polarity editor ──────────────────────────────────
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.timeline_outlined,
                  color: kProAccent.withValues(alpha: 0.6), size: 16),
              const SizedBox(width: 8),
              Text('Phase / Polarity', style: proTitle(size: 15)),
              const Spacer(),
              Text('Rev ${tuning.tuningRevision}',
                  style: proLabel(size: 9, color: Colors.white24, spacing: 1)),
            ]),
            const SizedBox(height: 3),
            Text('Polarity and phase review per channel. '
                'Full acoustic phase tools will be added later.',
                style: proSubtitle()),
            const SizedBox(height: 16),

            // Channel header
            _PhaseChannelHeader(
                driver: selectedDriver, xoCh: xoCh, ctrl: ctrl),
            const SizedBox(height: 14),

            // Polarity card
            _PolarityCard(
              polarityInverted: xoCh.polarityInverted,
              onToggle: () => _togglePolarity(selectedId),
            ),
            const SizedBox(height: 10),

            // Phase offset card
            _PhaseOffsetCard(
              ctrl: ctrl,
              onManual: (v) => _savePhaseOffset(selectedId, v.clamp(-180.0, 180.0)),
              onReset: () => _resetPhase(selectedId),
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
                  const Icon(Icons.show_chart, color: Colors.white12, size: 20),
                  const SizedBox(height: 6),
                  Text('Phase trace and summed response preview — '
                      'coming in optimizer phase',
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

class _PhaseChannelList extends StatelessWidget {
  final List<DriverChannel> drivers;
  final TuningProjectState tuning;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const _PhaseChannelList({required this.drivers, required this.tuning,
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
            final xoCh = tuning.getOrCreateCrossoverChannel(d.id);
            final ctrl = tuning.getOrCreateControl(d.id);
            final hasPhase = xoCh.polarityInverted || ctrl.phaseOffsetDeg != 0.0;
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
                  if (hasPhase) ...[
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, children: [
                      if (xoCh.polarityInverted)
                        const ProStatusPill(label: '∅ INV', color: kProAmber),
                      if (ctrl.phaseOffsetDeg != 0.0)
                        ProStatusPill(
                            label: '${ctrl.phaseOffsetDeg.toStringAsFixed(0)}°',
                            color: kProAccent),
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

class _PhaseChannelHeader extends StatelessWidget {
  final DriverChannel driver;
  final CrossoverChannelState xoCh;
  final ChannelControlState ctrl;
  const _PhaseChannelHeader(
      {required this.driver, required this.xoCh, required this.ctrl});

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
      Wrap(spacing: 6, children: [
        if (xoCh.polarityInverted)
          const ProStatusPill(label: 'POLARITY INV', color: kProAmber),
        if (ctrl.phaseOffsetDeg != 0.0)
          ProStatusPill(
              label: '${ctrl.phaseOffsetDeg.toStringAsFixed(0)}° OFFSET',
              color: kProAccent),
      ]),
    ]),
  );
}

class _PolarityCard extends StatelessWidget {
  final bool polarityInverted;
  final VoidCallback onToggle;
  const _PolarityCard({required this.polarityInverted, required this.onToggle});

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
          Text('POLARITY', style: proLabel(size: 9, spacing: 1.8)),
          const SizedBox(height: 4),
          Text(
            polarityInverted
                ? 'Inverted — signal phase flipped 180°'
                : 'Normal — signal polarity unchanged',
            style: proSubtitle(size: 10),
          ),
        ]),
      ),
      const SizedBox(width: 16),
      GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
                color: polarityInverted
                    ? kProAmber.withValues(alpha: 0.5)
                    : kProBorder),
            borderRadius: BorderRadius.circular(3),
            color: polarityInverted
                ? kProAmber.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
          child: Text(
            polarityInverted ? '∅ INVERTED' : '∅ NORMAL',
            style: TextStyle(
              color: polarityInverted ? kProAmber : Colors.white38,
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ]),
  );
}

class _PhaseOffsetCard extends StatefulWidget {
  final ChannelControlState ctrl;
  final void Function(double) onManual;
  final VoidCallback onReset;
  const _PhaseOffsetCard(
      {required this.ctrl, required this.onManual, required this.onReset});

  @override
  State<_PhaseOffsetCard> createState() => _PhaseOffsetCardState();
}

class _PhaseOffsetCardState extends State<_PhaseOffsetCard> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        TextEditingController(text: widget.ctrl.phaseOffsetDeg.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(_PhaseOffsetCard old) {
    super.didUpdateWidget(old);
    if (old.ctrl.phaseOffsetDeg != widget.ctrl.phaseOffsetDeg) {
      _ctrl.text = widget.ctrl.phaseOffsetDeg.toStringAsFixed(0);
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
      Text('PHASE OFFSET', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(
          width: 80,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('degrees', style: proLabel(size: 8, spacing: 0.5)),
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
        _SmallBtn(label: 'Reset Phase', onTap: widget.onReset, color: kProRed),
      ]),
      const SizedBox(height: 6),
      Text('Range: −180° to +180°', style: proSubtitle(size: 9)),
    ]),
  );
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
      const Icon(Icons.timeline_outlined, color: Colors.white12, size: 28),
      const SizedBox(height: 12),
      Text(message, style: proSubtitle(size: 11), textAlign: TextAlign.center),
    ]),
  );
}
