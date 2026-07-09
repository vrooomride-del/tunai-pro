// ── PEQ Tab — Phase D ─────────────────────────────────────────────────────────
// Parametric EQ editor per driver channel.
// No DSP write. No SafeLoad. No register addresses. Data model only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';

class PeqTab extends ConsumerStatefulWidget {
  final String projectId;
  const PeqTab({super.key, required this.projectId});

  @override
  ConsumerState<PeqTab> createState() => _PeqTabState();
}

class _PeqTabState extends ConsumerState<PeqTab> {
  String? _selectedChannelId;

  TuningProjectState get _tuning => ref.read(proProjectStoreProvider)
      .projects.where((p) => p.id == widget.projectId).firstOrNull
      ?.tuningState ?? TuningProjectState.createDefault();

  PeqChannelState _peqForChannel(String channelId) {
    final tuning = _tuning;
    return tuning.peqChannels.firstWhere(
      (c) => c.channelId == channelId,
      orElse: () => PeqChannelState.empty(channelId),
    );
  }

  Future<void> _savePeqChannel(PeqChannelState updated) async {
    final tuning = _tuning;
    final exists = tuning.peqChannels.any((c) => c.channelId == updated.channelId);
    final newChannels = exists
        ? tuning.peqChannels.map((c) => c.channelId == updated.channelId ? updated : c).toList()
        : [...tuning.peqChannels, updated];
    await ref.read(proProjectStoreProvider.notifier).updateTuningState(
      widget.projectId,
      tuning.copyWith(
        peqChannels: newChannels,
        hasManualChanges: true,
        tuningRevision: tuning.tuningRevision + 1,
      ),
    );
  }

  Future<void> _addBand(String channelId) async {
    final ch = _peqForChannel(channelId);
    final band = PeqBand.create(type: PeqBandType.peak, frequencyHz: 1000.0, gainDb: 0.0, q: 1.41);
    await _savePeqChannel(ch.copyWith(bands: [...ch.bands, band]));
  }

  Future<void> _removeBand(String channelId, String bandId) async {
    final ch = _peqForChannel(channelId);
    await _savePeqChannel(ch.copyWith(bands: ch.bands.where((b) => b.id != bandId).toList()));
  }

  Future<void> _updateBand(String channelId, PeqBand band) async {
    final ch = _peqForChannel(channelId);
    await _savePeqChannel(ch.copyWith(bands: ch.bands.map((b) => b.id == band.id ? band : b).toList()));
  }

  Future<void> _toggleBypass(String channelId) async {
    final ch = _peqForChannel(channelId);
    await _savePeqChannel(ch.copyWith(bypassed: !ch.bypassed));
  }

  Future<void> _resetChannel(String channelId) async {
    await _savePeqChannel(PeqChannelState.empty(channelId));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == widget.projectId).firstOrNull;
    final drivers = project?.acousticState.driverChannels ?? [];
    final tuning = project?.tuningState ?? TuningProjectState.createDefault();

    if (drivers.isEmpty) {
      return const _EmptyState(message: 'No driver channels configured yet. Import measurements first.');
    }

    final selectedId = _selectedChannelId ?? drivers.first.id;
    final selectedDriver = drivers.firstWhere((d) => d.id == selectedId, orElse: () => drivers.first);
    final peqCh = tuning.peqChannels.firstWhere(
      (c) => c.channelId == selectedId,
      orElse: () => PeqChannelState.empty(selectedId),
    );

    return Row(children: [
      // ── Left: channel list ──────────────────────────────────────────────
      SizedBox(
        width: 192,
        child: _ChannelList(
          drivers: drivers,
          tuning: tuning,
          selectedId: selectedId,
          onSelect: (id) => setState(() => _selectedChannelId = id),
        ),
      ),
      Container(width: 0.5, color: kProBorder),

      // ── Right: PEQ editor ───────────────────────────────────────────────
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              Icon(Icons.tune_outlined, color: kProAccent.withValues(alpha: 0.6), size: 16),
              const SizedBox(width: 8),
              Text('PEQ Editor', style: proTitle(size: 15)),
              const Spacer(),
              Text('Rev ${tuning.tuningRevision}',
                  style: proLabel(size: 9, color: Colors.white24, spacing: 1)),
            ]),
            const SizedBox(height: 3),
            Text('Parametric correction per driver channel. Use the Optimizer tab for automated target matching.',
                style: proSubtitle()),
            const SizedBox(height: 16),

            // Channel header + controls
            _ChannelHeader(
              driver: selectedDriver,
              peqCh: peqCh,
              onBypass: () => _toggleBypass(selectedId),
              onReset: () => _resetChannel(selectedId),
            ),
            const SizedBox(height: 14),

            // Graph placeholder
            _GraphPlaceholder(),
            const SizedBox(height: 14),

            // Band list
            if (peqCh.bands.isEmpty)
              _NoBandsState(onAdd: () => _addBand(selectedId))
            else ...[
              Row(children: [
                Text('BANDS (${peqCh.bands.length})', style: proLabel(size: 9, spacing: 2)),
                const Spacer(),
                _SmallBtn(label: '+ Add Band', onTap: () => _addBand(selectedId)),
              ]),
              const SizedBox(height: 8),
              ...peqCh.bands.asMap().entries.map((e) => _BandCard(
                index: e.key,
                band: e.value,
                onUpdate: (b) => _updateBand(selectedId, b),
                onRemove: () => _removeBand(selectedId, e.value.id),
              )),
            ],
          ]),
        ),
      ),
    ]);
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ChannelList extends StatelessWidget {
  final List<DriverChannel> drivers;
  final TuningProjectState tuning;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const _ChannelList({required this.drivers, required this.tuning,
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
            final peqCh = tuning.peqChannels.firstWhere(
                (c) => c.channelId == d.id, orElse: () => PeqChannelState.empty(d.id));
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
                    Text(d.name, style: proTitle(size: 11,
                        color: active ? Colors.white : const Color(0xFF6B7280))),
                    const Spacer(),
                    Text(d.role.short,
                        style: proLabel(size: 8, color: active ? kProAccent : Colors.white24, spacing: 0.5)),
                  ]),
                  if (peqCh.bands.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text('${peqCh.bands.length} band${peqCh.bands.length == 1 ? '' : 's'}',
                        style: proSubtitle(size: 9)),
                  ],
                  if (peqCh.bypassed) ...[
                    const SizedBox(height: 3),
                    const ProStatusPill(label: 'BYPASSED', color: kProAmber),
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

class _ChannelHeader extends StatelessWidget {
  final DriverChannel driver;
  final PeqChannelState peqCh;
  final VoidCallback onBypass;
  final VoidCallback onReset;
  const _ChannelHeader({required this.driver, required this.peqCh,
      required this.onBypass, required this.onReset});

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
      _ToggleBtn(
        label: peqCh.bypassed ? 'BYPASSED' : 'ACTIVE',
        active: !peqCh.bypassed,
        color: peqCh.bypassed ? kProAmber : kProGreen,
        onTap: onBypass,
      ),
      const SizedBox(width: 8),
      _SmallBtn(label: 'Reset', onTap: onReset, color: kProRed),
    ]),
  );
}

class _GraphPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 120,
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.show_chart, color: Colors.white12, size: 20),
        const SizedBox(height: 6),
        Text('Magnitude response preview — run Simulation to preview estimated response curves',
            style: proSubtitle(size: 9)),
      ]),
    ),
  );
}

class _NoBandsState extends StatelessWidget {
  final VoidCallback onAdd;
  const _NoBandsState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(children: [
        const Icon(Icons.tune_outlined, color: Colors.white12, size: 24),
        const SizedBox(height: 8),
        Text('No PEQ bands', style: proTitle(size: 12, color: Colors.white38)),
        const SizedBox(height: 4),
        Text('Add a band to begin parametric correction for this channel.',
            style: proSubtitle(size: 10), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        _SmallBtn(label: '+ Add Band', onTap: onAdd),
      ]),
    ),
  ]);
}

class _BandCard extends ConsumerStatefulWidget {
  final int index;
  final PeqBand band;
  final ValueChanged<PeqBand> onUpdate;
  final VoidCallback onRemove;
  const _BandCard({required this.index, required this.band,
      required this.onUpdate, required this.onRemove});

  @override
  ConsumerState<_BandCard> createState() => _BandCardState();
}

class _BandCardState extends ConsumerState<_BandCard> {
  late TextEditingController _freqCtrl;
  late TextEditingController _gainCtrl;
  late TextEditingController _qCtrl;

  @override
  void initState() {
    super.initState();
    _freqCtrl = TextEditingController(text: widget.band.frequencyHz.toStringAsFixed(0));
    _gainCtrl = TextEditingController(text: widget.band.gainDb.toStringAsFixed(1));
    _qCtrl    = TextEditingController(text: widget.band.q.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(_BandCard old) {
    super.didUpdateWidget(old);
    if (old.band.frequencyHz != widget.band.frequencyHz) {
      _freqCtrl.text = widget.band.frequencyHz.toStringAsFixed(0);
    }
    if (old.band.gainDb != widget.band.gainDb) {
      _gainCtrl.text = widget.band.gainDb.toStringAsFixed(1);
    }
    if (old.band.q != widget.band.q) {
      _qCtrl.text = widget.band.q.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _freqCtrl.dispose();
    _gainCtrl.dispose();
    _qCtrl.dispose();
    super.dispose();
  }

  void _commit() {
    final freq = double.tryParse(_freqCtrl.text) ?? widget.band.frequencyHz;
    final gain = double.tryParse(_gainCtrl.text) ?? widget.band.gainDb;
    final q    = double.tryParse(_qCtrl.text)    ?? widget.band.q;
    widget.onUpdate(widget.band.copyWith(
      frequencyHz: freq.clamp(20, 20000),
      gainDb: gain.clamp(-30, 30),
      q: q.clamp(0.1, 20),
    ));
  }

  Color _statusColor(PeqBandStatus s) => switch (s) {
    PeqBandStatus.active    => kProGreen,
    PeqBandStatus.bypassed  => kProAmber,
    PeqBandStatus.suggested => kProAccent,
    PeqBandStatus.locked    => kProRed,
  };

  @override
  Widget build(BuildContext context) {
    final band = widget.band;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('#${widget.index + 1}',
              style: proLabel(size: 9, color: Colors.white24, spacing: 1)),
          const SizedBox(width: 8),
          // Type selector
          _CompactDropdown<PeqBandType>(
            value: band.type,
            items: PeqBandType.values,
            label: (t) => t.label,
            onChanged: (t) => widget.onUpdate(band.copyWith(type: t)),
          ),
          const SizedBox(width: 8),
          ProStatusPill(
              label: band.status.label, color: _statusColor(band.status)),
          const Spacer(),
          // Enable toggle
          GestureDetector(
            onTap: () => widget.onUpdate(band.copyWith(enabled: !band.enabled)),
            child: Icon(
              band.enabled ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: band.enabled ? kProGreen : Colors.white24,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onRemove,
            child: const Icon(Icons.close, color: Colors.white24, size: 14),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _FieldBox(label: 'Hz', controller: _freqCtrl,
              onSubmit: _commit, width: 80),
          if (band.type.hasGain) ...[
            const SizedBox(width: 8),
            _FieldBox(label: 'dB', controller: _gainCtrl,
                onSubmit: _commit, width: 72),
          ],
          if (band.type.hasQ) ...[
            const SizedBox(width: 8),
            _FieldBox(label: 'Q', controller: _qCtrl,
                onSubmit: _commit, width: 64),
          ],
          const Spacer(),
          Text(band.freqLabel,
              style: proValue(size: 10, color: Colors.white38)),
        ]),
      ]),
    );
  }
}

// ── Shared compact controls ───────────────────────────────────────────────────

class _CompactDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  const _CompactDropdown({required this.value, required this.items,
      required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButton<T>(
    value: value,
    dropdownColor: kProPanel,
    underline: const SizedBox(),
    isDense: true,
    style: proTitle(size: 11),
    iconEnabledColor: Colors.white24,
    iconSize: 14,
    items: items.map((i) => DropdownMenuItem(value: i,
        child: Text(label(i), style: proTitle(size: 11)))).toList(),
    onChanged: (v) { if (v != null) onChanged(v); },
  );
}

class _FieldBox extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final double width;
  const _FieldBox({required this.label, required this.controller,
      required this.onSubmit, required this.width});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 8, spacing: 0.5)),
      const SizedBox(height: 3),
      Container(
        height: 28,
        decoration: BoxDecoration(
          color: kProBg,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: TextField(
          controller: controller,
          onSubmitted: (_) => onSubmit(),
          onEditingComplete: onSubmit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: proTitle(size: 11),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            border: InputBorder.none,
          ),
        ),
      ),
    ]),
  );
}

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
        color: active ? color.withValues(alpha: 0.08) : Colors.transparent,
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w500)),
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
      const Icon(Icons.tune_outlined, color: Colors.white12, size: 28),
      const SizedBox(height: 12),
      Text(message, style: proSubtitle(size: 11), textAlign: TextAlign.center),
    ]),
  );
}
