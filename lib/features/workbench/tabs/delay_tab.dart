// ── Delay Tab — Phase E ───────────────────────────────────────────────────────
// Time alignment per driver channel.
// No DSP write. No SafeLoad. No register addresses. Data model only.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../core/pro_adau1466_delay_audit_registry.dart';

class DelayTab extends ConsumerStatefulWidget {
  final String projectId;
  final ProUsbiNativeBackend? usbiBackend;
  final bool Function()? isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  const DelayTab(
      {super.key,
      required this.projectId,
      this.usbiBackend,
      this.isWindowsPlatform,
      this.deviceOpen = false,
      this.dspWritesDisabled = false});

  @override
  ConsumerState<DelayTab> createState() => _DelayTabState();
}

class _DelayTabState extends ConsumerState<DelayTab> {
  String? _selectedChannelId;

  TuningProjectState get _tuning =>
      ref
          .read(proProjectStoreProvider)
          .projects
          .where((p) => p.id == widget.projectId)
          .firstOrNull
          ?.tuningState ??
      TuningProjectState.createDefault();

  Future<void> _saveControl(ChannelControlState updated) async {
    final newTuning = _tuning.replaceControl(updated);
    await ref
        .read(proProjectStoreProvider.notifier)
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
    final project =
        store.projects.where((p) => p.id == widget.projectId).firstOrNull;
    final drivers = project?.acousticState.driverChannels ?? [];
    final tuning = project?.tuningState ?? TuningProjectState.createDefault();
    final audit = OperationalAdau1466DelayAudit(
      backend: widget.usbiBackend ?? const ProUsbiNativeBackendDisabled(),
      isWindowsPlatform: widget.isWindowsPlatform ?? () => Platform.isWindows,
      deviceOpen: widget.deviceOpen,
      dspWritesDisabled: widget.dspWritesDisabled,
    );

    if (drivers.isEmpty) {
      return SingleChildScrollView(
          padding: const EdgeInsets.all(20), child: audit);
    }

    final selectedId = _selectedChannelId ?? drivers.first.id;
    final selectedDriver = drivers.firstWhere((d) => d.id == selectedId,
        orElse: () => drivers.first);
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            Text(
                'Time alignment per driver channel. '
                'Acoustic impulse and delay alignment. Protection verification is available in the Protection tab.',
                style: proSubtitle()),
            const SizedBox(height: 16),
            audit,
            const SizedBox(height: 16),

            // Channel header
            _DelayChannelHeader(driver: selectedDriver, ctrl: ctrl),
            const SizedBox(height: 14),

            // Delay editor
            _DelayEditor(
              ctrl: ctrl,
              onStep: (delta) => _adjustDelay(selectedId, delta),
              onManual: (v) =>
                  _saveControl(ctrl.copyWith(delayMs: v.clamp(0.0, 20.0))),
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
                  const Icon(Icons.timeline_outlined,
                      color: Colors.white12, size: 20),
                  const SizedBox(height: 6),
                  Text(
                      'Impulse and acoustic alignment preview — run Simulation to preview response curves',
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

class OperationalAdau1466DelayAudit extends StatelessWidget {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  const OperationalAdau1466DelayAudit(
      {super.key,
      required this.backend,
      required this.isWindowsPlatform,
      required this.deviceOpen,
      required this.dspWritesDisabled});

  static String _hex(int value, int width) =>
      '0x${value.toRadixString(16).padLeft(width, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final realExecutor =
        isWindowsPlatform() && backend.isAvailable && !backend.isFake;
    return Container(
        key: const Key('adau1466-operational-delay-audit'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: Colors.amber.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ADAU1466 Operational Delay', style: proTitle(size: 13)),
          Text(
              'USBi device: ${deviceOpen ? "open" : "closed"} · '
              'real executor: ${realExecutor ? "available" : "unavailable"} · '
              'DSP writes: ${dspWritesDisabled ? "STOPPED" : "enabled"}',
              style: proSubtitle(size: 9)),
          const Text('Sample rate: UNPROVEN for these exported parameters',
              style: TextStyle(fontSize: 9, color: Colors.amber)),
          const Text(
              'EXPORT AUDIT ONLY — real Delay writes are blocked. Format, valid range, units, and write transaction require SigmaStudio capture.',
              style: TextStyle(fontSize: 9, color: Colors.amber)),
          const SizedBox(height: 8),
          const Wrap(spacing: 10, children: [
            FilterChip(
                label: Text('Link WFL + WFR'),
                selected: false,
                onSelected: null),
            FilterChip(
                label: Text('Link MID_L + MID_R'),
                selected: false,
                onSelected: null),
            FilterChip(
                label: Text('Link TWL + TWR'),
                selected: false,
                onSelected: null),
            OutlinedButton(
                onPressed: null, child: Text('Reset All to Export Baseline')),
          ]),
          const SizedBox(height: 8),
          for (final channel in ProAdau1466DelayAuditRegistry.channels)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${channel.channel} · ${channel.sigmaCell} · '
                          '${_hex(channel.address, 4)}',
                          style: proTitle(size: 10)),
                      Text(
                          '${channel.sigmaSymbol} · ${channel.sigmaOutput} / '
                          '${channel.physicalOutput}',
                          style: proSubtitle(size: 8)),
                      Text(
                          'baseline ${_hex(channel.exportedBaselineWord, 8)} · '
                          'preview ${_hex(channel.exportedBaselineWord, 8)} · '
                          'confirmed ${_hex(channel.exportedBaselineWord, 8)} · '
                          'last ACK not written',
                          style: proSubtitle(size: 8)),
                      Text(
                          'format ${channel.parameterFormat} · range '
                          '${channel.validRawRange} · unit ${channel.engineeringUnit}',
                          style: proSubtitle(size: 8)),
                      OutlinedButton(
                          key: Key('delay-reset-${channel.channel}'),
                          onPressed: null,
                          child: const Text('Reset to Export Baseline')),
                    ])),
          const Text(
              'PASS_ACK only, never VERIFIED. Physical/audible verification pending. XO, PEQ, arbitrary addresses, legacy transport, ADAU1701, EEPROM, and Selfboot remain blocked.',
              style: TextStyle(fontSize: 8, color: Colors.white38)),
        ]));
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DelayChannelList extends StatelessWidget {
  final List<DriverChannel> drivers;
  final TuningProjectState tuning;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const _DelayChannelList(
      {required this.drivers,
      required this.tuning,
      required this.selectedId,
      required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
        color: kProPanel,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Text('CHANNELS',
                style: proLabel(size: 9, color: Colors.white24, spacing: 2.5)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? kProAccent.withValues(alpha: 0.09)
                          : Colors.transparent,
                      border: Border(
                        left: BorderSide(
                            color: active ? kProAccent : Colors.transparent,
                            width: 2),
                      ),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(d.name,
                                  style: proTitle(
                                      size: 11,
                                      color: active
                                          ? Colors.white
                                          : const Color(0xFF6B7280))),
                            ),
                            Text(d.role.short,
                                style: proLabel(
                                    size: 8,
                                    color: active ? kProAccent : Colors.white24,
                                    spacing: 0.5)),
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
                            Text(
                                '≈ ${ctrl.delayDistanceCm.toStringAsFixed(1)} cm',
                                style: proSubtitle(
                                    size: 9,
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(driver.name, style: proTitle(size: 13)),
              Text(
                  '${driver.role.label} · ${driver.side.label} · OUT ${driver.dspOutputIndex ?? '—'}',
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
  const _DelayEditor(
      {required this.ctrl,
      required this.onStep,
      required this.onManual,
      required this.onReset});

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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          // Step buttons — Flexible prevents overflow in narrow columns
          Flexible(
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              _SmallBtn(label: '−0.10', onTap: () => widget.onStep(-0.10)),
              _SmallBtn(label: '−0.01', onTap: () => widget.onStep(-0.01)),
              _SmallBtn(label: '+0.01', onTap: () => widget.onStep(0.01)),
              _SmallBtn(label: '+0.10', onTap: () => widget.onStep(0.10)),
              _SmallBtn(label: 'Reset', onTap: widget.onReset, color: kProRed),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          widget.ctrl.delayMs == 0.0
              ? '≈ 0 cm acoustic offset'
              : '≈ ${distCm.toStringAsFixed(1)} cm acoustic offset',
          style: proValue(
              size: 11,
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
  const _SmallBtn(
      {required this.label, required this.onTap, this.color = kProAccent});

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
