// ── XO Tab — Phase D ──────────────────────────────────────────────────────────
// Crossover editor per driver channel.
// No DSP write. No SafeLoad. No register addresses. Data model only.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../core/pro_adau1466_xo_audit_registry.dart';

class XoTab extends ConsumerStatefulWidget {
  final String projectId;
  final ProUsbiNativeBackend? usbiBackend;
  final bool Function()? isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  const XoTab({super.key, required this.projectId, this.usbiBackend,
    this.isWindowsPlatform, this.deviceOpen = false,
    this.dspWritesDisabled = false});

  @override
  ConsumerState<XoTab> createState() => _XoTabState();
}

class _XoTabState extends ConsumerState<XoTab> {
  String? _selectedChannelId;

  TuningProjectState get _tuning => ref.read(proProjectStoreProvider)
      .projects.where((p) => p.id == widget.projectId).firstOrNull
      ?.tuningState ?? TuningProjectState.createDefault();

  Future<void> _saveXoChannel(CrossoverChannelState updated) async {
    final tuning = _tuning;
    final exists = tuning.crossoverChannels.any((c) => c.channelId == updated.channelId);
    final newChannels = exists
        ? tuning.crossoverChannels.map((c) => c.channelId == updated.channelId ? updated : c).toList()
        : [...tuning.crossoverChannels, updated];
    await ref.read(proProjectStoreProvider.notifier).updateTuningState(
      widget.projectId,
      tuning.copyWith(
        crossoverChannels: newChannels,
        hasManualChanges: true,
        tuningRevision: tuning.tuningRevision + 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == widget.projectId).firstOrNull;
    final drivers = project?.acousticState.driverChannels ?? [];
    final tuning  = project?.tuningState ?? TuningProjectState.createDefault();
    final hardwareAudit = Adau1466XoHardwareMappingPanel(
      backend: widget.usbiBackend ?? const ProUsbiNativeBackendDisabled(),
      isWindowsPlatform: widget.isWindowsPlatform ?? () => Platform.isWindows,
      deviceOpen: widget.deviceOpen,
      dspWritesDisabled: widget.dspWritesDisabled,
    );

    if (drivers.isEmpty) {
      return SingleChildScrollView(padding: const EdgeInsets.all(20),
        child: hardwareAudit);
    }

    final selectedId = _selectedChannelId ?? drivers.first.id;
    final selectedDriver = drivers.firstWhere((d) => d.id == selectedId, orElse: () => drivers.first);
    final xoCh = tuning.crossoverChannels.firstWhere(
      (c) => c.channelId == selectedId,
      orElse: () => CrossoverChannelState.empty(selectedId),
    );

    return Row(children: [
      // ── Left: channel list ──────────────────────────────────────────────
      SizedBox(
        width: 192,
        child: _XoChannelList(
          drivers: drivers,
          tuning: tuning,
          selectedId: selectedId,
          onSelect: (id) => setState(() => _selectedChannelId = id),
        ),
      ),
      Container(width: 0.5, color: kProBorder),

      // ── Right: XO editor ────────────────────────────────────────────────
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.device_hub_outlined, color: kProAccent.withValues(alpha: 0.6), size: 16),
              const SizedBox(width: 8),
              Text('Crossover Editor', style: proTitle(size: 15)),
              const Spacer(),
              Text('Rev ${tuning.tuningRevision}',
                  style: proLabel(size: 9, color: Colors.white24, spacing: 1)),
            ]),
            const SizedBox(height: 3),
            Text('High-pass and low-pass structure per channel. DSP export draft is available after protection verification.',
                style: proSubtitle()),
            const SizedBox(height: 16),
            hardwareAudit,
            const SizedBox(height: 16),

            // Channel header
            _XoChannelHeader(
              driver: selectedDriver,
              xoCh: xoCh,
              onBypass: () => _saveXoChannel(xoCh.copyWith(bypassed: !xoCh.bypassed)),
              onPolarity: () => _saveXoChannel(xoCh.copyWith(polarityInverted: !xoCh.polarityInverted)),
            ),
            const SizedBox(height: 14),

            // HPF card
            _FilterCard(
              label: 'HPF',
              side: FilterSide.highPass,
              filter: xoCh.highPass,
              onAdd: () => _saveXoChannel(xoCh.copyWith(
                highPass: const CrossoverFilter(
                  side: FilterSide.highPass,
                  type: CrossoverFilterType.linkwitzRiley,
                  slope: CrossoverSlope.db24,
                  frequencyHz: 2000.0,
                ),
              )),
              onRemove: () => _saveXoChannel(xoCh.copyWith(clearHighPass: true)),
              onUpdate: (f) => _saveXoChannel(xoCh.copyWith(highPass: f)),
            ),
            const SizedBox(height: 10),

            // LPF card
            _FilterCard(
              label: 'LPF',
              side: FilterSide.lowPass,
              filter: xoCh.lowPass,
              onAdd: () => _saveXoChannel(xoCh.copyWith(
                lowPass: const CrossoverFilter(
                  side: FilterSide.lowPass,
                  type: CrossoverFilterType.linkwitzRiley,
                  slope: CrossoverSlope.db24,
                  frequencyHz: 2000.0,
                ),
              )),
              onRemove: () => _saveXoChannel(xoCh.copyWith(clearLowPass: true)),
              onUpdate: (f) => _saveXoChannel(xoCh.copyWith(lowPass: f)),
            ),
            const SizedBox(height: 14),

            // Graph placeholder
            _XoGraphPlaceholder(),

            // Phase D notice
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: kProSurface,
                border: Border.all(color: kProBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                const Icon(Icons.hourglass_empty_outlined, color: Colors.white24, size: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Phase-aware simulation is available in the Simulation tab. '
                    'DSP export requires SigmaStudio address capture — not yet implemented.',
                    style: proSubtitle(size: 10),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class Adau1466XoHardwareMappingPanel extends StatelessWidget {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  const Adau1466XoHardwareMappingPanel({super.key, required this.backend,
    required this.isWindowsPlatform, required this.deviceOpen,
    required this.dspWritesDisabled});

  static String _hex(int value, int width) =>
      '0x${value.toRadixString(16).padLeft(width, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final realExecutor = isWindowsPlatform() && backend.isAvailable &&
        !backend.isFake;
    return Container(key: const Key('adau1466-xo-hardware-mapping'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kProSurface,
        border: Border.all(color: Colors.amber.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ADAU1466 XO Hardware Mapping', style: proTitle(size: 13)),
        Text('USBi device: ${deviceOpen ? "open" : "closed"} · '
            'real executor: ${realExecutor ? "available" : "unavailable"} · '
            'DSP writes: ${dspWritesDisabled ? "STOPPED" : "enabled"}',
            style: proSubtitle(size: 9)),
        const Text('AUDIT ONLY — all XO coefficient writes remain blocked.',
          style: TextStyle(fontSize: 9, color: Colors.amber)),
        const SizedBox(height: 8),
        Container(key: const Key('wfl-lpf2-safeload-diagnostic'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kProPanel,
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(3)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('WFL LPF_2 · Output1 / OUT3', style: proTitle(size: 10)),
            const Text('Signed ADAU1466 8.24 · coefficient order b2, b1, b0, a2, a1 · one atomic 20-byte SafeLoad',
              style: TextStyle(fontSize: 8, color: Colors.white54)),
            Text('280 Hz baseline: ${ProAdau1466WflLpf2DiagnosticEvidence.baseline280Hz.map((word) => _hex(word, 8)).join(" · ")}',
              style: proSubtitle(size: 8)),
            Text('280 Hz payload: ${ProAdau1466WflLpf2DiagnosticEvidence.baselinePayload.map((byte) => byte.toRadixString(16).padLeft(2, "0").toUpperCase()).join(" ")}',
              style: proSubtitle(size: 8)),
            Text('281 Hz test: ${ProAdau1466WflLpf2DiagnosticEvidence.test281Hz.map((word) => _hex(word, 8)).join(" · ")}',
              style: proSubtitle(size: 8)),
            Text('281 Hz payload: ${ProAdau1466WflLpf2DiagnosticEvidence.testPayload.map((byte) => byte.toRadixString(16).padLeft(2, "0").toUpperCase()).join(" ")}',
              style: proSubtitle(size: 8)),
            const Text('TEST 281 Hz — BLOCKED · RESTORE 280 Hz — BLOCKED',
              style: TextStyle(fontSize: 8, color: Colors.amber)),
            const Text(ProAdau1466WflLpf2DiagnosticEvidence.unresolvedTrigger,
              style: TextStyle(fontSize: 8, color: Colors.amber)),
            const Text('No trigger/count bytes are invented. No USBi transaction is emitted.',
              style: TextStyle(fontSize: 8, color: Colors.white38)),
          ])),
        const SizedBox(height: 8),
        for (final channel in ['WFL', 'MID_L', 'TWL', 'WFR', 'MID_R', 'TWR']) ...[
          Text(channel, style: proTitle(size: 11)),
          for (final block in ProAdau1466XoAuditRegistry.blocks
              .where((entry) => entry.channel == channel))
            Container(key: Key('xo-map-${block.channel}-${block.sigmaCell}'),
              margin: const EdgeInsets.only(top: 5, bottom: 7),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: kProPanel,
                border: Border.all(color: kProBorder),
                borderRadius: BorderRadius.circular(3)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${block.sigmaCell} · ${block.role}${block.safetyBlock ? " · SAFETY" : ""} · '
                      '${block.sigmaOutput} / ${block.physicalOutput}',
                      style: proTitle(size: 9)),
                  Text('slew ${block.slewSymbol} @ ${_hex(block.slewAddress, 4)} = '
                      '${_hex(block.slewWord, 8)}', style: proSubtitle(size: 8)),
                  Text('${block.coefficientSymbol} · ${block.addressRange} · '
                      '${block.coefficients.length} words', style: proSubtitle(size: 8)),
                  Text(block.coefficients.map((coefficient) =>
                      '${coefficient.label}@${_hex(coefficient.address, 4)}=${_hex(coefficient.exportedWord, 8)}')
                      .join(' · '), style: proSubtitle(size: 8)),
                  Text('export row order ${block.exportOrder} · ${block.topologyStatus}',
                      style: proSubtitle(size: 8)),
                  Text('${block.formatStatus} · ${block.transactionStatus}',
                      style: proSubtitle(size: 8)),
                  Text(block.bypassStatus, style: proSubtitle(size: 8)),
                  Text(block.blockedReason,
                      style: const TextStyle(fontSize: 8, color: Colors.amber)),
                ])),
        ],
        const Text('Required capture: WFL LPF_2 only — change one crossover parameter by one controlled step, capture slew write plus the complete five-coefficient SafeLoad transaction and ACKs, then restore the original setting and capture the complete restore transaction.',
          style: TextStyle(fontSize: 9, color: Colors.amber)),
        const Text('PASS_ACK only, never VERIFIED. Audible/measurement verification pending. RBJ output alone cannot enable writes. PEQ, arbitrary coefficients, legacy transport, ADAU1701, EEPROM, and Selfboot remain blocked.',
          style: TextStyle(fontSize: 8, color: Colors.white38)),
      ]));
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _XoChannelList extends StatelessWidget {
  final List<DriverChannel> drivers;
  final TuningProjectState tuning;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const _XoChannelList({required this.drivers, required this.tuning,
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
            final xoCh = tuning.crossoverChannels.firstWhere(
              (c) => c.channelId == d.id,
              orElse: () => CrossoverChannelState.empty(d.id),
            );
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
                  if (xoCh.isConfigured) ...[
                    const SizedBox(height: 3),
                    Wrap(spacing: 4, children: [
                      if (xoCh.hasHighPass)
                        const _XoBadge(label: 'HPF', color: kProAccent),
                      if (xoCh.hasLowPass)
                        const _XoBadge(label: 'LPF', color: kProAmber),
                      if (xoCh.polarityInverted)
                        const _XoBadge(label: '∅', color: kProRed),
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

class _XoBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _XoBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Text(label,
        style: TextStyle(color: color, fontSize: 8, letterSpacing: 0.5, fontWeight: FontWeight.w500)),
  );
}

class _XoChannelHeader extends StatelessWidget {
  final DriverChannel driver;
  final CrossoverChannelState xoCh;
  final VoidCallback onBypass;
  final VoidCallback onPolarity;
  const _XoChannelHeader({required this.driver, required this.xoCh,
      required this.onBypass, required this.onPolarity});

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
      _XoToggle(
        label: xoCh.bypassed ? 'BYPASSED' : 'ACTIVE',
        color: xoCh.bypassed ? kProAmber : kProGreen,
        active: !xoCh.bypassed,
        onTap: onBypass,
      ),
      const SizedBox(width: 8),
      _XoToggle(
        label: xoCh.polarityInverted ? '∅ INVERTED' : '∅ NORMAL',
        color: xoCh.polarityInverted ? kProRed : Colors.white24,
        active: xoCh.polarityInverted,
        onTap: onPolarity,
      ),
    ]),
  );
}

class _XoToggle extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _XoToggle({required this.label, required this.color,
      required this.active, required this.onTap});

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

class _FilterCard extends ConsumerStatefulWidget {
  final String label;
  final FilterSide side;
  final CrossoverFilter? filter;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final ValueChanged<CrossoverFilter> onUpdate;
  const _FilterCard({required this.label, required this.side, required this.filter,
      required this.onAdd, required this.onRemove, required this.onUpdate});

  @override
  ConsumerState<_FilterCard> createState() => _FilterCardState();
}

class _FilterCardState extends ConsumerState<_FilterCard> {
  late TextEditingController _freqCtrl;

  @override
  void initState() {
    super.initState();
    _freqCtrl = TextEditingController(
        text: widget.filter?.frequencyHz.toStringAsFixed(0) ?? '2000');
  }

  @override
  void didUpdateWidget(_FilterCard old) {
    super.didUpdateWidget(old);
    if (old.filter?.frequencyHz != widget.filter?.frequencyHz) {
      _freqCtrl.text = widget.filter?.frequencyHz.toStringAsFixed(0) ?? '2000';
    }
  }

  @override
  void dispose() {
    _freqCtrl.dispose();
    super.dispose();
  }

  void _commitFreq() {
    final f = widget.filter;
    if (f == null) return;
    final freq = double.tryParse(_freqCtrl.text) ?? f.frequencyHz;
    widget.onUpdate(f.copyWith(frequencyHz: freq.clamp(20, 20000)));
  }

  Color get _color => widget.side == FilterSide.highPass ? kProAccent : kProAmber;

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: f != null ? _color.withValues(alpha: 0.3) : kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: f == null
          ? _EmptyFilter(label: widget.label, color: _color, onAdd: widget.onAdd)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(widget.label,
                      style: TextStyle(color: _color, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 8),
                Text(f.summaryLabel, style: proValue(size: 10)),
                const Spacer(),
                GestureDetector(
                  onTap: () => widget.onUpdate(f.copyWith(enabled: !f.enabled)),
                  child: Icon(
                    f.enabled ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: f.enabled ? kProGreen : Colors.white24,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onRemove,
                  child: const Icon(Icons.close, color: Colors.white24, size: 14),
                ),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                // Type
                _FilterDropdown<CrossoverFilterType>(
                  label: 'TYPE',
                  value: f.type,
                  items: CrossoverFilterType.values,
                  labelOf: (t) => t.label,
                  onChanged: (t) => widget.onUpdate(f.copyWith(type: t)),
                ),
                const SizedBox(width: 12),
                // Slope
                _FilterDropdown<CrossoverSlope>(
                  label: 'SLOPE',
                  value: f.slope,
                  items: CrossoverSlope.values,
                  labelOf: (s) => s.label,
                  onChanged: (s) => widget.onUpdate(f.copyWith(slope: s)),
                ),
                const SizedBox(width: 12),
                // Frequency
                SizedBox(
                  width: 80,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hz', style: proLabel(size: 8, spacing: 0.5)),
                    const SizedBox(height: 3),
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: kProBg,
                        border: Border.all(color: kProBorder),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: TextField(
                        controller: _freqCtrl,
                        onSubmitted: (_) => _commitFreq(),
                        onEditingComplete: _commitFreq,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: proTitle(size: 11),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ]),
                ),
                const Spacer(),
                Text(f.freqLabel,
                    style: proValue(size: 10, color: _color.withValues(alpha: 0.7))),
              ]),
            ]),
    );
  }
}

class _EmptyFilter extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onAdd;
  const _EmptyFilter({required this.label, required this.color, required this.onAdd});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$label —', style: proLabel(size: 10, color: Colors.white24, spacing: 0.5)),
    const Spacer(),
    GestureDetector(
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text('+ Add $label', style: TextStyle(color: color, fontSize: 10)),
      ),
    ),
  ]);
}

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  const _FilterDropdown({required this.label, required this.value,
      required this.items, required this.labelOf, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: proLabel(size: 8, spacing: 0.5)),
    const SizedBox(height: 3),
    DropdownButton<T>(
      value: value,
      dropdownColor: kProPanel,
      underline: const SizedBox(),
      isDense: true,
      style: proTitle(size: 11),
      iconEnabledColor: Colors.white24,
      iconSize: 14,
      items: items.map((i) => DropdownMenuItem(value: i,
          child: Text(labelOf(i), style: proTitle(size: 11)))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  ]);
}

class _XoGraphPlaceholder extends StatelessWidget {
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
        Text('Summed acoustic response preview — available in the Simulation tab',
            style: proSubtitle(size: 9)),
      ]),
    ),
  );
}
