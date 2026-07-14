// ── Gain Tab — Phase E ────────────────────────────────────────────────────────
// Channel level matching and output trim.
// No DSP write. No SafeLoad. No register addresses. Data model only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:math';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../core/pro_adau1466_gain_channel_registry.dart';
import '../../../core/pro_adau1466_operational_gain_executor.dart';
import '../../../core/pro_adau1466_mute_channel_registry.dart';
import '../../../core/pro_adau1466_operational_mute_executor.dart';

class GainTab extends ConsumerStatefulWidget {
  final String projectId;
  final ProUsbiNativeBackend? usbiBackend;
  final bool Function()? isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  final void Function(String warning)? onDspWriteStop;
  const GainTab(
      {super.key,
      required this.projectId,
      this.usbiBackend,
      this.isWindowsPlatform,
      this.deviceOpen = false,
      this.dspWritesDisabled = false,
      this.onDspWriteStop});

  @override
  ConsumerState<GainTab> createState() => _GainTabState();
}

class _GainTabState extends ConsumerState<GainTab> {
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
    final project =
        store.projects.where((p) => p.id == widget.projectId).firstOrNull;
    final drivers = project?.acousticState.driverChannels ?? [];
    final tuning = project?.tuningState ?? TuningProjectState.createDefault();
    final operational = OperationalAdau1466GainControls(
      backend: widget.usbiBackend ?? const ProUsbiNativeBackendDisabled(),
      isWindowsPlatform: widget.isWindowsPlatform ?? () => Platform.isWindows,
      deviceOpen: widget.deviceOpen,
      dspWritesDisabled: widget.dspWritesDisabled,
      onDspWriteStop: widget.onDspWriteStop,
    );
    final operationalMute = OperationalAdau1466MuteControls(
      backend: widget.usbiBackend ?? const ProUsbiNativeBackendDisabled(),
      isWindowsPlatform: widget.isWindowsPlatform ?? () => Platform.isWindows,
      deviceOpen: widget.deviceOpen,
      dspWritesDisabled: widget.dspWritesDisabled,
      onDspWriteStop: widget.onDspWriteStop,
    );

    if (drivers.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          operational,
          const SizedBox(height: 16),
          operationalMute
        ]),
      );
    }

    final selectedId = _selectedChannelId ?? drivers.first.id;
    final selectedDriver = drivers.firstWhere((d) => d.id == selectedId,
        orElse: () => drivers.first);
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            Text(
                'Channel level matching and output trim. '
                'Hardware write remains disabled. Use the Hardware tab for dry-run planning.',
                style: proSubtitle()),
            const SizedBox(height: 16),
            operational,
            const SizedBox(height: 16),
            operationalMute,
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
              onManual: (v) =>
                  _saveControl(ctrl.copyWith(gainDb: v.clamp(-24.0, 12.0))),
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
                  const Icon(Icons.bar_chart_outlined,
                      color: Colors.white12, size: 20),
                  const SizedBox(height: 6),
                  Text(
                      'Level and headroom preview — protection verification is available in the Protection tab',
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
  const _GainChannelList(
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
                            ctrl.gainDb == 0.0
                                ? '0.0 dB'
                                : '${ctrl.gainDb >= 0 ? '+' : ''}${ctrl.gainDb.toStringAsFixed(1)} dB',
                            style: proSubtitle(size: 9),
                          ),
                          if (ctrl.muted || ctrl.solo) ...[
                            const SizedBox(height: 4),
                            Wrap(spacing: 4, children: [
                              if (ctrl.muted)
                                const ProStatusPill(
                                    label: 'MUTE', color: kProRed),
                              if (ctrl.solo)
                                const ProStatusPill(
                                    label: 'SOLO', color: kProAmber),
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
  const _GainChannelHeader(
      {required this.driver,
      required this.ctrl,
      required this.onMute,
      required this.onSolo,
      required this.onReset});

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
          const SizedBox(width: 12),
          _ToggleBtn(
              label: 'MUTE', active: ctrl.muted, color: kProRed, onTap: onMute),
          const SizedBox(width: 6),
          _ToggleBtn(
              label: 'SOLO',
              active: ctrl.solo,
              color: kProAmber,
              onTap: onSolo),
          const SizedBox(width: 8),
          _SmallBtn(label: 'Reset Gain', onTap: onReset, color: kProRed),
        ]),
      );
}

class _GainEditor extends StatefulWidget {
  final ChannelControlState ctrl;
  final void Function(double delta) onStep;
  final void Function(double value) onManual;
  const _GainEditor(
      {required this.ctrl, required this.onStep, required this.onManual});

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
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
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
                _SmallBtn(label: '−1 dB', onTap: () => widget.onStep(-1.0)),
                _SmallBtn(label: '−0.5 dB', onTap: () => widget.onStep(-0.5)),
                _SmallBtn(label: '+0.5 dB', onTap: () => widget.onStep(0.5)),
                _SmallBtn(label: '+1 dB', onTap: () => widget.onStep(1.0)),
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
  const _ToggleBtn(
      {required this.label,
      required this.active,
      required this.color,
      required this.onTap});

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
                  fontSize: 9,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w500)),
        ),
      );
}

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

class OperationalAdau1466GainControls extends StatefulWidget {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  final void Function(String warning)? onDspWriteStop;

  const OperationalAdau1466GainControls(
      {super.key,
      required this.backend,
      required this.isWindowsPlatform,
      required this.deviceOpen,
      this.dspWritesDisabled = false,
      this.onDspWriteStop});

  @override
  State<OperationalAdau1466GainControls> createState() =>
      _OperationalAdau1466GainControlsState();
}

class _OperationalAdau1466GainControlsState
    extends State<OperationalAdau1466GainControls> {
  late ProAdau1466OperationalGainExecutor _executor;
  late final Map<String, int> _confirmed;
  late final Map<String, int> _preview;
  final Map<String, String> _ack = {};
  final Set<String> _links = {};
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _executor = ProAdau1466OperationalGainExecutor(
      backend: widget.backend,
      isWindowsPlatform: widget.isWindowsPlatform,
    );
    _confirmed = {
      for (final c in ProAdau1466GainChannelRegistry.channels)
        c.channel: c.exportedRestoreWord
    };
    _preview = Map.of(_confirmed);
  }

  @override
  void didUpdateWidget(covariant OperationalAdau1466GainControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend) {
      _executor = ProAdau1466OperationalGainExecutor(
        backend: widget.backend,
        isWindowsPlatform: widget.isWindowsPlatform,
      );
    }
  }

  bool get _enabled =>
      !_writing &&
      !widget.dspWritesDisabled &&
      widget.deviceOpen &&
      _executor.isRealExecutorAvailable;

  static double _wordToDb(int word) =>
      word <= 0 ? -96 : 20 * log(word / 0x01000000) / ln10;
  static int _dbToWord(double db) =>
      (pow(10, db / 20) * 0x01000000).round().clamp(0, 0x00FFFFFF);
  static String _hex(int word) =>
      '0x${word.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  String? _pairFor(String channel) => switch (channel) {
        'WFL' => 'WFR',
        'WFR' => 'WFL',
        'MID_L' => 'MID_R',
        'MID_R' => 'MID_L',
        'TWL' => 'TWR',
        'TWR' => 'TWL',
        _ => null,
      };

  String _linkKey(String channel) => switch (channel) {
        'WFL' || 'WFR' => 'WFL+WFR',
        'MID_L' || 'MID_R' => 'MID_L+MID_R',
        _ => 'TWL+TWR',
      };

  Future<bool> _writeOne(Adau1466MappedGainChannel channel, int word) async {
    final result = await _executor.writeWithRollback(
      channel: channel,
      requestedWord: word,
      previousConfirmedWord: _confirmed[channel.channel]!,
      deviceOpen: widget.deviceOpen,
    );
    _ack[channel.channel] = result.ackStatus;
    if (result.restoreFailed) {
      widget.onDspWriteStop?.call(
          'STOP — ${channel.channel} Gain restore failed. All DSP writes disabled.');
    }
    if (result.success) _confirmed[channel.channel] = word;
    _preview[channel.channel] = _confirmed[channel.channel]!;
    return result.success;
  }

  Future<void> _commit(Adau1466MappedGainChannel source, int word,
      {bool honorLink = true}) async {
    if (!_enabled) {
      setState(() => _preview[source.channel] = _confirmed[source.channel]!);
      return;
    }
    setState(() => _writing = true);
    final link = honorLink && _links.contains(_linkKey(source.channel));
    if (!link) {
      await _writeOne(source, word);
    } else {
      final pair = ProAdau1466GainChannelRegistry.findByChannel(
          _pairFor(source.channel)!)!;
      final left = source.channel.endsWith('_R') ||
              source.channel == 'WFR' ||
              source.channel == 'TWR'
          ? pair
          : source;
      final right = identical(left, source) ? pair : source;
      final leftPrevious = _confirmed[left.channel]!;
      final leftOk = await _writeOne(left, word);
      if (leftOk) {
        final rightOk = await _writeOne(right, word);
        if (!rightOk) {
          final rollback = await _executor.writeWithRollback(
            channel: left,
            requestedWord: leftPrevious,
            previousConfirmedWord: leftPrevious,
            deviceOpen: widget.deviceOpen,
          );
          _ack[left.channel] = rollback.success ? 'ROLLED_BACK' : 'FAIL';
          _confirmed[left.channel] = leftPrevious;
          _preview[left.channel] = leftPrevious;
          if (!rollback.success || rollback.restoreFailed) {
            widget.onDspWriteStop?.call(
                'STOP — linked Gain rollback failed. All DSP writes disabled.');
          }
        }
      }
    }
    if (mounted) setState(() => _writing = false);
  }

  Future<void> _reset(Adau1466MappedGainChannel channel) =>
      _commit(channel, channel.exportedRestoreWord, honorLink: false);

  Future<void> _resetAll() async {
    for (final channel in ProAdau1466GainChannelRegistry.channels) {
      if (widget.dspWritesDisabled) break;
      await _commit(channel, channel.exportedRestoreWord, honorLink: false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
      key: const Key('operational-adau1466-gain-controls'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Operational ADAU1466 Gain Controls', style: proTitle(size: 13)),
        Text(
            'USBi device: ${widget.deviceOpen ? "open" : "closed"} · '
            'real executor: ${_executor.isRealExecutorAvailable ? "available" : "unavailable"} · '
            'DSP writes: ${widget.dspWritesDisabled ? "STOPPED" : "enabled"}',
            style: proSubtitle(size: 9)),
        const SizedBox(height: 8),
        Wrap(
            spacing: 12,
            children: ['WFL+WFR', 'MID_L+MID_R', 'TWL+TWR']
                .map((p) => FilterChip(
                    label: Text('Link $p'),
                    selected: _links.contains(p),
                    onSelected: _writing
                        ? null
                        : (v) => setState(
                            () => v ? _links.add(p) : _links.remove(p))))
                .toList()),
        const SizedBox(height: 8),
        for (final channel in ProAdau1466GainChannelRegistry.channels)
          _OperationalGainRow(
            channel: channel,
            previewWord: _preview[channel.channel]!,
            confirmedWord: _confirmed[channel.channel]!,
            ack: _ack[channel.channel] ?? 'not written',
            enabled: _enabled,
            wordToDb: _wordToDb,
            hex: _hex,
            onChanged: (db) =>
                setState(() => _preview[channel.channel] = _dbToWord(db)),
            onChangeEnd: (db) => _commit(channel, _dbToWord(db)),
            onReset: () => _reset(channel),
          ),
        OutlinedButton(
            key: const Key('gain-reset-all'),
            onPressed: _enabled ? _resetAll : null,
            child: const Text('Reset All to Exported Baselines')),
        const Text(
            'ACK means PASS_ACK only, never VERIFIED. Physical mapping and audible verification remain pending. '
            'XO, PEQ, Delay, EEPROM, Selfboot, and unmapped Gain 0x0057/0x0054 remain blocked.',
            style: TextStyle(fontSize: 8, color: Colors.white38)),
      ]));
}

class _OperationalGainRow extends StatelessWidget {
  final Adau1466MappedGainChannel channel;
  final int previewWord;
  final int confirmedWord;
  final String ack;
  final bool enabled;
  final double Function(int) wordToDb;
  final String Function(int) hex;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onReset;
  const _OperationalGainRow(
      {required this.channel,
      required this.previewWord,
      required this.confirmedWord,
      required this.ack,
      required this.enabled,
      required this.wordToDb,
      required this.hex,
      required this.onChanged,
      required this.onChangeEnd,
      required this.onReset});

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(channel.channel, style: proTitle(size: 10))),
          Text(
              '${wordToDb(previewWord).toStringAsFixed(1)} dB · ${hex(previewWord)}',
              style: proSubtitle(size: 9))
        ]),
        Slider(
            key: Key('gain-slider-${channel.channel}'),
            min: -96,
            max: -0.1,
            value: wordToDb(previewWord).clamp(-96, -0.1),
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? onChangeEnd : null),
        Row(children: [
          Expanded(
              child: Text(
                  'confirmed ${wordToDb(confirmedWord).toStringAsFixed(1)} dB · ${hex(confirmedWord)} · ACK $ack',
                  style: proSubtitle(size: 8))),
          OutlinedButton(
              key: Key('gain-reset-${channel.channel}'),
              onPressed: enabled ? onReset : null,
              child: const Text('Reset baseline'))
        ]),
      ]));
}

class OperationalAdau1466MuteControls extends StatefulWidget {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  final void Function(String warning)? onDspWriteStop;

  const OperationalAdau1466MuteControls(
      {super.key,
      required this.backend,
      required this.isWindowsPlatform,
      required this.deviceOpen,
      this.dspWritesDisabled = false,
      this.onDspWriteStop});

  @override
  State<OperationalAdau1466MuteControls> createState() =>
      _OperationalAdau1466MuteControlsState();
}

class _OperationalAdau1466MuteControlsState
    extends State<OperationalAdau1466MuteControls> {
  late ProAdau1466OperationalMuteExecutor _executor;
  late final Map<String, int> _confirmed;
  final Map<String, String> _ack = {};
  final Set<String> _links = {};
  bool _writing = false;
  bool _localStop = false;

  @override
  void initState() {
    super.initState();
    _createExecutor();
    _confirmed = {
      for (final c in ProAdau1466MuteChannelRegistry.channels)
        c.channel: c.exportedState
    };
  }

  void _createExecutor() {
    _executor = ProAdau1466OperationalMuteExecutor(
      backend: widget.backend,
      isWindowsPlatform: widget.isWindowsPlatform,
    );
  }

  @override
  void didUpdateWidget(covariant OperationalAdau1466MuteControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend ||
        oldWidget.isWindowsPlatform != widget.isWindowsPlatform) {
      _createExecutor();
    }
  }

  bool get _enabled =>
      !_writing &&
      !_localStop &&
      !widget.dspWritesDisabled &&
      widget.deviceOpen &&
      _executor.isRealExecutorAvailable;

  static String _state(int value) =>
      value == 1 ? 'Checked state (1)' : 'Unchecked state (0)';
  static String _hexAddress(int address) =>
      '0x${address.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  String _linkKey(String channel) => switch (channel) {
        'WFL' || 'WFR' => 'WFL+WFR',
        'MID_L' || 'MID_R' => 'MID_L+MID_R',
        _ => 'TWL+TWR',
      };

  String? _pairFor(String channel) => switch (channel) {
        'WFL' => 'WFR',
        'WFR' => 'WFL',
        'MID_L' => 'MID_R',
        'MID_R' => 'MID_L',
        'TWL' => 'TWR',
        'TWR' => 'TWL',
        _ => null,
      };

  void _stop(String warning) {
    _localStop = true;
    widget.onDspWriteStop?.call(warning);
  }

  Future<bool> _writeOne(Adau1466MappedMuteChannel channel, int value) async {
    final previous = _confirmed[channel.channel]!;
    final result = await _executor.writeWithRollback(
      channel: channel,
      requestedState: value,
      previousConfirmedState: previous,
      deviceOpen: widget.deviceOpen,
    );
    _ack[channel.channel] = result.ackStatus;
    if (result.success) _confirmed[channel.channel] = value;
    if (result.restoreFailed) {
      _stop('STOP — ${channel.channel} state restore failed. '
          'All DSP writes disabled for this session.');
    }
    return result.success;
  }

  Future<void> _setStateFor(Adau1466MappedMuteChannel source, int value,
      {bool honorLink = true}) async {
    if (!_enabled) return;
    setState(() => _writing = true);
    final linked = honorLink && _links.contains(_linkKey(source.channel));
    if (!linked) {
      await _writeOne(source, value);
    } else {
      final pair =
          ProAdau1466MuteChannelRegistry.find(_pairFor(source.channel)!)!;
      final sourceIsRight = source.channel.endsWith('_R') ||
          source.channel == 'WFR' ||
          source.channel == 'TWR';
      final left = sourceIsRight ? pair : source;
      final right = sourceIsRight ? source : pair;
      final leftPrevious = _confirmed[left.channel]!;
      final leftOk = await _writeOne(left, value);
      if (leftOk) {
        final rightOk = await _writeOne(right, value);
        if (!rightOk) {
          final rollback = await _executor.writeWithRollback(
            channel: left,
            requestedState: leftPrevious,
            previousConfirmedState: leftPrevious,
            deviceOpen: widget.deviceOpen,
          );
          _ack[left.channel] = rollback.success ? 'ROLLED_BACK' : 'FAIL';
          _confirmed[left.channel] = leftPrevious;
          if (!rollback.success || rollback.restoreFailed) {
            _stop('STOP — linked state rollback failed. '
                'All DSP writes disabled for this session.');
          }
        }
      }
    }
    if (mounted) setState(() => _writing = false);
  }

  Future<void> _setAll(int value) async {
    for (final channel in ProAdau1466MuteChannelRegistry.channels) {
      if (_localStop || widget.dspWritesDisabled) break;
      await _setStateFor(channel, value, honorLink: false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
      key: const Key('operational-adau1466-mute-controls'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Operational ADAU1466 Mute Controls', style: proTitle(size: 13)),
        Text(
            'USBi device: ${widget.deviceOpen ? "open" : "closed"} · '
            'real executor: ${_executor.isRealExecutorAvailable ? "available" : "unavailable"} · '
            'DSP writes: ${widget.dspWritesDisabled || _localStop ? "STOPPED" : "enabled"}',
            style: proSubtitle(size: 9)),
        const Text(
            'Mute polarity is not audibly confirmed. Controls use the '
            'Sigma block states: checked=1 and unchecked=0.',
            style: TextStyle(fontSize: 9, color: Colors.amber)),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 6, children: [
          for (final pair in ['WFL+WFR', 'MID_L+MID_R', 'TWL+TWR'])
            FilterChip(
                key: Key('mute-link-$pair'),
                label: Text('Link $pair'),
                selected: _links.contains(pair),
                onSelected: _writing
                    ? null
                    : (value) => setState(
                        () => value ? _links.add(pair) : _links.remove(pair))),
          OutlinedButton(
              key: const Key('mute-all-checked'),
              onPressed: _enabled ? () => _setAll(1) : null,
              child: const Text('Set All Checked')),
          OutlinedButton(
              key: const Key('mute-all-unchecked'),
              onPressed: _enabled ? () => _setAll(0) : null,
              child: const Text('Set All Unchecked')),
        ]),
        const SizedBox(height: 8),
        for (final channel in ProAdau1466MuteChannelRegistry.channels)
          Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          '${channel.channel} · ${channel.sigmaCell} · '
                          '${_hexAddress(channel.address)}',
                          style: proTitle(size: 10)),
                      Text(channel.sigmaSymbol, style: proSubtitle(size: 8)),
                      Text(
                          'preview ${_state(_confirmed[channel.channel]!)} · '
                          'confirmed ${_state(_confirmed[channel.channel]!)} · '
                          'last ACK ${_ack[channel.channel] ?? "not written"}',
                          key: Key('mute-status-${channel.channel}'),
                          style: proSubtitle(size: 8)),
                    ])),
                OutlinedButton(
                    key: Key('mute-toggle-${channel.channel}'),
                    onPressed: _enabled
                        ? () => _setStateFor(
                            channel, _confirmed[channel.channel] == 1 ? 0 : 1)
                        : null,
                    child: Text(_confirmed[channel.channel] == 1
                        ? 'Set Unchecked'
                        : 'Set Checked')),
              ])),
        const Text(
            'Direct 4-byte integer writes only; no SafeLoad. ACK means '
            'PASS_ACK only, never VERIFIED. Audible/physical mapping remains pending. '
            'Delay, XO, PEQ, EEPROM, Selfboot, and unmapped mute parameters remain blocked.',
            style: TextStyle(fontSize: 8, color: Colors.white38)),
      ]));
}
