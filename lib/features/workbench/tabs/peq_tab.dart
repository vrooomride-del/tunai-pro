// ── PEQ Tab — Phase D ─────────────────────────────────────────────────────────
// Parametric EQ editor per driver channel.
// No DSP write. No SafeLoad. No register addresses. Data model only.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/adau1701_peq_response.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../widgets/adau1701_peq_response_graph.dart';
import 'pro_adau1466_peq_hardware_panel.dart';

class PeqTab extends ConsumerStatefulWidget {
  final String projectId;
  final ProUsbiNativeBackend? usbiBackend;
  final bool Function()? isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  const PeqTab({super.key, required this.projectId, this.usbiBackend,
    this.isWindowsPlatform, this.deviceOpen = false,
    this.dspWritesDisabled = false});

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

  // Fixed 10-slot PEQ: bands are addressed by slot index (0-9), never
  // added/removed. Updating a slot preserves the other nine.
  Future<void> _updateBandAt(String channelId, int index, PeqBand band) async {
    final ch = _peqForChannel(channelId).normalized();
    final bands = [...ch.bands];
    bands[index] = band;
    await _savePeqChannel(ch.copyWith(bands: bands));
  }

  Future<void> _toggleBypass(String channelId) async {
    final ch = _peqForChannel(channelId);
    await _savePeqChannel(ch.copyWith(bypassed: !ch.bypassed));
  }

  Future<void> _resetChannel(String channelId) async {
    // Reset to ten disabled fixed slots (not an empty band list).
    await _savePeqChannel(PeqChannelState.fixed(channelId));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == widget.projectId).firstOrNull;
    final drivers = project?.acousticState.driverChannels ?? [];
    final tuning = project?.tuningState ?? TuningProjectState.createDefault();
    final hardwareAudit = Adau1466PeqHardwareMappingPanel(
      backend: widget.usbiBackend ?? const ProUsbiNativeBackendDisabled(),
      isWindowsPlatform: widget.isWindowsPlatform ?? () => Platform.isWindows,
      deviceOpen: widget.deviceOpen,
      dspWritesDisabled: widget.dspWritesDisabled,
    );

    if (drivers.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          hardwareAudit,
          const SizedBox(height: 14),
          const _EmptyState(message: 'No driver channels configured yet. Import measurements first.'),
        ]),
      );
    }

    final selectedId = _selectedChannelId ?? drivers.first.id;
    final selectedDriver = drivers.firstWhere((d) => d.id == selectedId, orElse: () => drivers.first);
    // Fixed 10-slot model: always present exactly Band 1 .. Band 10.
    final peqCh = tuning.peqChannels
        .firstWhere(
          (c) => c.channelId == selectedId,
          orElse: () => PeqChannelState.fixed(selectedId),
        )
        .normalized();

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
            hardwareAudit,
            const SizedBox(height: 16),

            // Channel header + controls
            _ChannelHeader(
              driver: selectedDriver,
              peqCh: peqCh,
              onBypass: () => _toggleBypass(selectedId),
              onReset: () => _resetChannel(selectedId),
            ),
            const SizedBox(height: 14),

            // Live PEQ magnitude response of this channel's fixed bands.
            // Editing an enabled band's frequency/gain/Q updates the curve
            // immediately (the tab rebuilds from tuning state on every change).
            Adau1701PeqResponseGraph(
              bands: [
                for (final b in peqCh.bands)
                  PeqResponseBand(
                    frequencyHz: b.frequencyHz,
                    gainDb: b.gainDb,
                    q: b.q,
                    enabled: b.enabled && !peqCh.bypassed,
                  ),
              ],
              height: 240,
            ),
            const SizedBox(height: 14),

            // Fixed 10-band PEQ slots (Band 1 .. Band 10). No add/remove — each
            // card is one DSP PEQ slot; disable a slot to bypass it.
            Row(children: [
              Text('PEQ BANDS · ${PeqChannelState.bandCount} FIXED SLOTS',
                  style: proLabel(size: 9, spacing: 2)),
              const Spacer(),
              Text('${peqCh.enabledBandCount} enabled',
                  style: proSubtitle(size: 9)),
            ]),
            const SizedBox(height: 8),
            ...peqCh.bands.asMap().entries.map((e) => _BandCard(
                  index: e.key,
                  band: e.value,
                  onUpdate: (b) => _updateBandAt(selectedId, e.key, b),
                )),
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
                  if (peqCh.enabledBandCount > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                        '${peqCh.enabledBandCount} / ${PeqChannelState.bandCount} enabled',
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


class _BandCard extends ConsumerStatefulWidget {
  final int index;
  final PeqBand band;
  final ValueChanged<PeqBand> onUpdate;
  const _BandCard({required this.index, required this.band,
      required this.onUpdate});

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
          Text('Band ${widget.index + 1}',
              style: proLabel(size: 9, color: Colors.white38, spacing: 1)),
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
          // Enable / bypass this fixed slot (no removal — slots are permanent).
          GestureDetector(
            onTap: () => widget.onUpdate(band.copyWith(
              enabled: !band.enabled,
              status:
                  !band.enabled ? PeqBandStatus.active : PeqBandStatus.bypassed,
            )),
            child: Icon(
              band.enabled ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: band.enabled ? kProGreen : Colors.white24,
              size: 14,
            ),
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
