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
import '../../../core/pro_adau1466_operational_delay_executor.dart';

class DelayTab extends ConsumerStatefulWidget {
  final String projectId;
  final ProUsbiNativeBackend? usbiBackend;
  final bool Function()? isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  final void Function(String warning)? onDspWriteStop;
  const DelayTab(
      {super.key,
      required this.projectId,
      this.usbiBackend,
      this.isWindowsPlatform,
      this.deviceOpen = false,
      this.dspWritesDisabled = false,
      this.onDspWriteStop});

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
      onDspWriteStop: widget.onDspWriteStop,
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

class OperationalAdau1466DelayAudit extends StatefulWidget {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  final void Function(String warning)? onDspWriteStop;
  const OperationalAdau1466DelayAudit(
      {super.key,
      required this.backend,
      required this.isWindowsPlatform,
      required this.deviceOpen,
      required this.dspWritesDisabled,
      this.onDspWriteStop});

  @override
  State<OperationalAdau1466DelayAudit> createState() =>
      _OperationalAdau1466DelayAuditState();
}

class _OperationalAdau1466DelayAuditState
    extends State<OperationalAdau1466DelayAudit> {
  late ProAdau1466OperationalDelayExecutor _executor;
  late final Map<String, int> _confirmed;
  late final Map<String, int> _preview;
  final Map<String, String> _ack = {};
  final Set<String> _links = {};
  bool _writing = false;
  bool _localStop = false;

  @override
  void initState() {
    super.initState();
    _createExecutor();
    _confirmed = {
      for (final channel in ProAdau1466DelayAuditRegistry.channels)
        channel.channel: channel.exportedBaselineWord
    };
    _preview = Map.of(_confirmed);
  }

  void _createExecutor() {
    _executor = ProAdau1466OperationalDelayExecutor(
        backend: widget.backend, isWindowsPlatform: widget.isWindowsPlatform);
  }

  @override
  void didUpdateWidget(covariant OperationalAdau1466DelayAudit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend ||
        oldWidget.isWindowsPlatform != widget.isWindowsPlatform) {
      _createExecutor();
    }
  }

  static String _hex(int value, int width) =>
      '0x${value.toRadixString(16).padLeft(width, '0').toUpperCase()}';

  bool _enabled(Adau1466MappedDelayAudit channel) =>
      !_writing &&
      !_localStop &&
      !widget.dspWritesDisabled &&
      widget.deviceOpen &&
      _executor.isRealExecutorAvailable &&
      channel.writeEnabled;

  String _linkKey(String channel) => switch (channel) {
        'WFL' || 'WFR' => 'WFL + WFR',
        'MID_L' || 'MID_R' => 'MID_L + MID_R',
        _ => 'TWL + TWR',
      };
  String _pairFor(String channel) => switch (channel) {
        'WFL' => 'WFR',
        'WFR' => 'WFL',
        'MID_L' => 'MID_R',
        'MID_R' => 'MID_L',
        'TWL' => 'TWR',
        _ => 'TWL',
      };

  void _stop(String warning) {
    _localStop = true;
    widget.onDspWriteStop?.call(warning);
  }

  Future<bool> _writeOne(Adau1466MappedDelayAudit channel, int samples) async {
    final result = await _executor.writeOnce(
        channel: channel, samples: samples, deviceOpen: widget.deviceOpen);
    _ack[channel.channel] = result.ackStatus;
    if (result.success) _confirmed[channel.channel] = samples;
    _preview[channel.channel] = _confirmed[channel.channel]!;
    return result.success;
  }

  Future<void> _commit(Adau1466MappedDelayAudit source, int samples,
      {bool honorLink = true}) async {
    if (!_enabled(source)) return;
    setState(() => _writing = true);
    final pair = ProAdau1466DelayAuditRegistry.find(_pairFor(source.channel));
    final linked = honorLink &&
        _links.contains(_linkKey(source.channel)) &&
        pair != null &&
        pair.writeEnabled;
    if (!linked) {
      await _writeOne(source, samples);
    } else {
      final sourceIsRight = source.channel.endsWith('_R') ||
          source.channel == 'WFR' ||
          source.channel == 'TWR';
      final left = sourceIsRight ? pair : source;
      final right = sourceIsRight ? source : pair;
      final leftPrevious = _confirmed[left.channel]!;
      if (await _writeOne(left, samples) && !await _writeOne(right, samples)) {
        final rollback = await _executor.writeOnce(
            channel: left,
            samples: leftPrevious,
            deviceOpen: widget.deviceOpen);
        _ack[left.channel] = rollback.success ? 'ROLLED_BACK' : 'FAIL';
        if (rollback.success) {
          _confirmed[left.channel] = leftPrevious;
          _preview[left.channel] = leftPrevious;
        } else {
          _stop(
              'STOP — linked Delay rollback failed. All DSP writes disabled.');
        }
      }
    }
    if (mounted) setState(() => _writing = false);
  }

  Future<void> _resetAll() async {
    if (_writing || _localStop || widget.dspWritesDisabled) return;
    setState(() => _writing = true);
    final changed = <(Adau1466MappedDelayAudit, int)>[];
    for (final channel in ProAdau1466DelayAuditRegistry.channels
        .where((entry) => entry.writeEnabled)) {
      final previous = _confirmed[channel.channel]!;
      if (await _writeOne(channel, channel.exportedBaselineWord)) {
        if (previous != channel.exportedBaselineWord) {
          changed.add((channel, previous));
        }
        continue;
      }
      for (final entry in changed.reversed) {
        final rollback = await _executor.writeOnce(
            channel: entry.$1,
            samples: entry.$2,
            deviceOpen: widget.deviceOpen);
        _ack[entry.$1.channel] =
            rollback.success ? 'BATCH_ROLLED_BACK' : 'FAIL';
        if (rollback.success) {
          _confirmed[entry.$1.channel] = entry.$2;
          _preview[entry.$1.channel] = entry.$2;
        } else {
          _stop('STOP — Delay batch rollback failed. All DSP writes disabled.');
          break;
        }
      }
      break;
    }
    if (mounted) setState(() => _writing = false);
  }

  @override
  Widget build(BuildContext context) {
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
              'USBi device: ${widget.deviceOpen ? "open" : "closed"} · '
              'real executor: ${_executor.isRealExecutorAvailable ? "available" : "unavailable"} · '
              'DSP writes: ${widget.dspWritesDisabled || _localStop ? "STOPPED" : "enabled"}',
              style: proSubtitle(size: 9)),
          const Text(
              'Unit: integer samples · time conversion/sample rate: pending',
              style: TextStyle(fontSize: 9, color: Colors.amber)),
          const Text(
              'Direct 6-byte parameter write; no SafeLoad. Channels without an individually proven configured Max remain disabled.',
              style: TextStyle(fontSize: 9, color: Colors.amber)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            for (final pair in ['WFL + WFR', 'MID_L + MID_R', 'TWL + TWR'])
              FilterChip(
                  key: Key('delay-link-$pair'),
                  label: Text('Link $pair'),
                  selected: _links.contains(pair),
                  onSelected: ProAdau1466DelayAuditRegistry.find(
                                  pair.split(' + ').first)!
                              .writeEnabled &&
                          ProAdau1466DelayAuditRegistry.find(
                                  pair.split(' + ').last)!
                              .writeEnabled &&
                          !_writing
                      ? (value) => setState(
                          () => value ? _links.add(pair) : _links.remove(pair))
                      : null),
            OutlinedButton(
                key: const Key('delay-reset-all'),
                onPressed: ProAdau1466DelayAuditRegistry.channels
                        .any((entry) => _enabled(entry))
                    ? _resetAll
                    : null,
                child: const Text('Reset All to Export Baseline')),
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
                          'configured Max ${channel.configuredMaxSamples?.toString() ?? "UNPROVEN — BLOCKED"} samples · '
                          'baseline ${channel.exportedBaselineWord} samples · '
                          'preview ${_preview[channel.channel]} samples · '
                          'confirmed ${_confirmed[channel.channel]} samples · '
                          'last ACK ${_ack[channel.channel] ?? "not written"}',
                          style: proSubtitle(size: 8)),
                      Text(
                          'format ${channel.parameterFormat} · range '
                          '${channel.validRawRange} · unit ${channel.engineeringUnit}',
                          style: proSubtitle(size: 8)),
                      if (channel.configuredMaxSamples != null)
                        Slider(
                            key: Key('delay-slider-${channel.channel}'),
                            min: 0,
                            max: channel.configuredMaxSamples!.toDouble(),
                            divisions: channel.configuredMaxSamples!,
                            value: _preview[channel.channel]!.toDouble(),
                            onChanged: _enabled(channel)
                                ? (value) => setState(() =>
                                    _preview[channel.channel] = value.round())
                                : null,
                            onChangeEnd: _enabled(channel)
                                ? (value) => _commit(channel, value.round())
                                : null),
                      OutlinedButton(
                          key: Key('delay-reset-${channel.channel}'),
                          onPressed: _enabled(channel)
                              ? () => _commit(
                                  channel, channel.exportedBaselineWord,
                                  honorLink: false)
                              : null,
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
