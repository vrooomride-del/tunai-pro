// ── PEQ Tab — Phase D ─────────────────────────────────────────────────────────
// Parametric EQ editor per driver channel.
// No DSP write. No SafeLoad. No register addresses. Data model only.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/adau1701_peq_response.dart';
import '../../../core/channel_compare_provider.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';
import '../../../shared/components/channel_selector_sidebar.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../widgets/adau1701_peq_response_graph.dart';
import '../widgets/current_driver_header.dart';
import '../widgets/graph_overlay_models.dart';
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

  /// Same mapping the graph already used pre-v3-1 (PeqBand -> PeqResponseBand,
  /// bypass folded into `enabled`) — extracted so v3-2's compare curves use
  /// byte-for-byte the same view-model construction as the primary curve.
  List<PeqResponseBand> _toResponseBands(PeqChannelState ch) => [
        for (final b in ch.bands)
          PeqResponseBand(
            frequencyHz: b.frequencyHz,
            gainDb: b.gainDb,
            q: b.q,
            enabled: b.enabled && !ch.bypassed,
          ),
      ];

  /// Maps DriverChannel + per-channel PEQ state onto the presentation-only
  /// ChannelSelectorItem — no domain type crosses into ChannelSelectorSidebar
  /// itself.
  ChannelSelectorItem _channelItem(
      DriverChannel d, TuningProjectState tuning) {
    final peqCh = tuning.peqChannels.firstWhere(
        (c) => c.channelId == d.id, orElse: () => PeqChannelState.empty(d.id));
    final badges = [
      if (peqCh.enabledBandCount > 0)
        '${peqCh.enabledBandCount} / ${PeqChannelState.bandCount} enabled',
      if (peqCh.bypassed) 'BYPASSED',
    ].join(' · ');
    return ChannelSelectorItem(
      id: d.id,
      label: d.name,
      subtitle: '${d.role.short}${badges.isEmpty ? '' : ' · $badges'}',
      status: peqCh.bypassed
          ? kProAmber
          : peqCh.enabledBandCount > 0
              ? kProAccent
              : null,
    );
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

    // ── v3-3 shared channel selection (was: local _selectedChannelId) ─────
    final compareState = ref.watch(channelCompareProvider);
    final driverIds = [for (final d in drivers) d.id];
    final selectedId = resolveSelectedChannelId(compareState, driverIds)!;
    if (compareState.currentChannelId != null &&
        !driverIds.contains(compareState.currentChannelId)) {
      // Stored selection belongs to a different project/driver set — correct
      // the shared provider after this frame (never mutate during build).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(channelCompareProvider.notifier).validateAgainstDrivers(driverIds);
        }
      });
    }
    final selectedDriver = drivers.firstWhere((d) => d.id == selectedId, orElse: () => drivers.first);
    // Fixed 10-slot model: always present exactly Band 1 .. Band 10.
    final peqCh = tuning.peqChannels
        .firstWhere(
          (c) => c.channelId == selectedId,
          orElse: () => PeqChannelState.fixed(selectedId),
        )
        .normalized();

    // ── v3-2 Channel Compare — role+side pairing, never DAC index ─────────
    final pairId = pairChannelIdFor(selectedId, drivers);
    final pairDriver =
        pairId == null ? null : drivers.where((d) => d.id == pairId).firstOrNull;
    final compareActive = compareState.compareEnabled &&
        pairId != null &&
        compareState.compareChannelIds.contains(pairId);

    List<PeqGraphCurve>? overlayCurves;
    if (compareActive) {
      final pairPeq = tuning.peqChannels
          .firstWhere((c) => c.channelId == pairId,
              orElse: () => PeqChannelState.fixed(pairId))
          .normalized();
      overlayCurves = [
        PeqGraphCurve(label: selectedDriver.name, bands: _toResponseBands(peqCh)),
        PeqGraphCurve(label: pairDriver!.name, bands: _toResponseBands(pairPeq)),
      ];
    }

    return Row(children: [
      // ── Left: channel list ──────────────────────────────────────────────
      ChannelSelectorSidebar(
        title: 'CHANNELS',
        items: [for (final d in drivers) _channelItem(d, tuning)],
        selectedId: selectedId,
        onSelected: (id) =>
            ref.read(channelCompareProvider.notifier).setCurrentChannel(id),
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
            ]),
            const SizedBox(height: 3),
            Text('Parametric correction per driver channel. Use the Optimizer tab for automated target matching.',
                style: proSubtitle()),
            const SizedBox(height: 16),
            hardwareAudit,
            const SizedBox(height: 16),

            // v3-3.5: shared driver identity header (name/role/side/DSP) —
            // replaces the identity block _ChannelHeader used to render
            // locally. Match readout intentionally not passed here: the
            // existing _CompareSection/_ChannelMatchReadout below already
            // owns that display (and its toggle/checkbox controls) — this
            // header would otherwise duplicate the same "Excellent"/dB text.
            CurrentDriverHeader(drivers: drivers),
            const SizedBox(height: 14),

            // Channel header controls (bypass/reset only — identity now
            // lives in CurrentDriverHeader above).
            _ChannelHeader(
              peqCh: peqCh,
              onBypass: () => _toggleBypass(selectedId),
              onReset: () => _resetChannel(selectedId),
            ),
            const SizedBox(height: 14),

            // v3-2: Compare section — only shown when the selected channel
            // has a same-role, opposite-side counterpart (e.g. Woofer L has
            // Woofer R). Pure UI state (channelCompareProvider); PEQ data
            // model and calculation are untouched.
            if (pairDriver != null) ...[
              _CompareSection(
                pairLabel: pairDriver.name,
                enabled: compareState.compareEnabled,
                checked: compareState.compareChannelIds.contains(pairId),
                onToggleEnabled: (v) => ref
                    .read(channelCompareProvider.notifier)
                    .setCompareEnabled(v),
                onToggleChannel: () => ref
                    .read(channelCompareProvider.notifier)
                    .toggleCompareChannel(pairId!),
                overlayCurves: overlayCurves,
              ),
              const SizedBox(height: 14),
            ],

            // Live PEQ magnitude response of this channel's fixed bands.
            // Editing an enabled band's frequency/gain/Q updates the curve
            // immediately (the tab rebuilds from tuning state on every change).
            // v3-2: when compare is active, overlayCurves/mode add a second
            // curve + the graph's own [Single][Overlay][Difference] header
            // (from v3-1) — the single-channel path below is otherwise
            // unchanged.
            Adau1701PeqResponseGraph(
              bands: _toResponseBands(peqCh),
              overlayCurves: overlayCurves,
              mode: compareActive ? compareState.mode : PeqGraphMode.single,
              onModeChanged: compareActive
                  ? (m) => ref.read(channelCompareProvider.notifier).setMode(m)
                  : null,
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

class _ChannelHeader extends StatelessWidget {
  final PeqChannelState peqCh;
  final VoidCallback onBypass;
  final VoidCallback onReset;
  const _ChannelHeader({required this.peqCh,
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
      Expanded(child: Text('PEQ Controls', style: proLabel(size: 9, spacing: 1.5))),
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

/// v3-2 Channel Compare — displayed only when the selected channel has a
/// same-role, opposite-side counterpart. Analysis/display only: the
/// Excellent/Good/Needs Tune label and dB readout never write back into any
/// PEQ data and never trigger automatic correction.
class _CompareSection extends StatelessWidget {
  final String pairLabel;
  final bool enabled;
  final bool checked;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onToggleChannel;
  final List<PeqGraphCurve>? overlayCurves;

  const _CompareSection({
    required this.pairLabel,
    required this.enabled,
    required this.checked,
    required this.onToggleEnabled,
    required this.onToggleChannel,
    required this.overlayCurves,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Compare', style: proLabel(size: 9, spacing: 1.5)),
            const SizedBox(width: 10),
            _ToggleBtn(
              label: enabled ? 'ON' : 'OFF',
              active: enabled,
              color: enabled ? kProGreen : Colors.white38,
              onTap: () => onToggleEnabled(!enabled),
            ),
          ]),
          if (enabled) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onToggleChannel,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  checked
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  size: 14,
                  color: checked ? kProAccent : Colors.white38,
                ),
                const SizedBox(width: 6),
                Text(pairLabel,
                    style: proValue(size: 11,
                        color: checked ? Colors.white : Colors.white54)),
              ]),
            ),
            if (checked && overlayCurves != null && overlayCurves!.length == 2) ...[
              const SizedBox(height: 8),
              _ChannelMatchReadout(curves: overlayCurves!),
            ],
          ],
        ]),
      );
}

/// Computes and shows the mean-absolute difference between exactly two
/// compare curves + an Excellent/Good/Needs Tune label. Pure display —
/// see PeqGraphOverlayMath.difference/meanAbsoluteDifference and
/// PeqChannelMatch (graph_overlay_models.dart).
class _ChannelMatchReadout extends StatelessWidget {
  final List<PeqGraphCurve> curves;
  const _ChannelMatchReadout({required this.curves});

  @override
  Widget build(BuildContext context) {
    // Same sampling density the graph itself uses internally — this is a
    // display-only readout computed the same way the graph's own difference
    // mode would, not a new calculation.
    final points = Adau1701PeqResponse.logFrequencyPoints(count: 220);
    final a = curves[0].curveFor(points);
    final b = curves[1].curveFor(points);
    final diff = PeqGraphOverlayMath.difference(a, b);
    if (diff == null) return const SizedBox.shrink();

    final meanAbs = PeqGraphOverlayMath.meanAbsoluteDifference(diff);
    final match = PeqChannelMatch.fromMeanAbsDiff(meanAbs);
    final color = switch (match) {
      PeqChannelMatch.excellent => kProGreen,
      PeqChannelMatch.good => kProAmber,
      PeqChannelMatch.needsTune => kProRed,
    };

    return Row(children: [
      ProStatusPill(label: 'Channel Match · ${match.label}', color: color),
      const SizedBox(width: 10),
      Text('Difference: ${meanAbs.toStringAsFixed(1)}dB',
          style: proSubtitle(size: 10, color: Colors.white54)),
    ]);
  }
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
