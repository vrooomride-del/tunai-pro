// One-click DEPLOY dialog.
//
// Flow: plan → confirm → executing → result (PASS_ACK / failure)
// Restore: re-runs the same executor with previousAppliedGains values.
//
// Uses only the existing executor/write-port/transport chain.
// No new writer. No new transport. No fake data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/deploy/adau1701_engineering_export.dart';
import '../../../core/deploy/pro_hardware_capability.dart';
import '../../../core/deploy/pro_adau1701_hardware_context.dart';
import '../../../core/deploy/pro_hardware_context_provider.dart';
import '../../../core/deploy/pro_hardware_write_approval.dart';
import '../../../core/deploy/pro_hardware_write_executor.dart';
import '../../../core/deploy/pro_hardware_write_plan.dart';
import '../../../core/transport/icp5_transports.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_deploy_package_data.dart' show AppliedXoChannelState;
import '../../../core/pro_export_data.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/components/info_row.dart';
import '../../../shared/pro_widgets.dart';
import 'deploy_result_summary.dart';
import 'deploy_step_ladder.dart';

// ── Public entry point ────────────────────────────────────────────────────────

/// Opens the deploy dialog. Call from the top-right DEPLOY button.
///
/// [overridePort] is for testing only — injects a fake write port so the
/// dialog can be exercised without a live hardware context.
Future<void> showDeployDialog({
  required BuildContext context,
  required String projectId,
  required List<DriverChannel> channels,
  required TuningProjectState tuning,
  required Map<String, double> previousAppliedGains,
  Map<String, AppliedXoChannelState> previousAppliedXo = const {},
  Icp5PeqWritePort? overridePort,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeployDialogBody(
      projectId: projectId,
      channels: channels,
      tuning: tuning,
      previousAppliedGains: previousAppliedGains,
      previousAppliedXo: previousAppliedXo,
      overridePort: overridePort,
    ),
  );
}

// ── Dialog body ───────────────────────────────────────────────────────────────

enum _Phase { plan, executing, result }

class _DeployDialogBody extends ConsumerStatefulWidget {
  final String projectId;
  final List<DriverChannel> channels;
  final TuningProjectState tuning;
  final Map<String, double> previousAppliedGains;
  final Map<String, AppliedXoChannelState> previousAppliedXo;
  final Icp5PeqWritePort? overridePort;

  const _DeployDialogBody({
    required this.projectId,
    required this.channels,
    required this.tuning,
    required this.previousAppliedGains,
    this.previousAppliedXo = const {},
    this.overridePort,
  });

  @override
  ConsumerState<_DeployDialogBody> createState() => _DeployDialogBodyState();
}

class _DeployDialogBodyState extends ConsumerState<_DeployDialogBody> {
  _Phase _phase = _Phase.plan;
  HardwareWriteExecutionResult? _result;
  HardwareWriteProgress? _progress;
  bool _isRestoring = false;
  bool _restored = false;

  late HardwareWritePlan _plan;
  late bool _hasWritableOps;

  @override
  void initState() {
    super.initState();
    _buildPlan(widget.previousAppliedGains);
  }

  void _buildPlan(Map<String, double> previousApplied) {
    final gainPkg = buildAdau1701GainExportPackage(
      channels: widget.channels,
      tuning: widget.tuning,
      previousAppliedGains: previousApplied.isEmpty ? null : previousApplied,
    );
    // PEQ and XO are independent builders (Phase 7-4A). PEQ stays full-state
    // (unchanged); XO is diff-only against widget.previousAppliedXo — an
    // unchanged channel produces no XO block at all, so an XO-only edit
    // cannot resend another channel's crossover, and never touches PEQ.
    final peqBlocks = buildAdau1701PeqExportBlocks(
      channels: widget.channels,
      tuning: widget.tuning,
    );
    final xoBlocks = buildAdau1701XoExportBlocks(
      channels: widget.channels,
      tuning: widget.tuning,
      previousAppliedXo: widget.previousAppliedXo,
    );
    final muteDelayBlocks = buildAdau1701MuteDelayExportBlocks(
      channels: widget.channels,
      tuning: widget.tuning,
    );
    final allBlocks = [
      ...gainPkg.parameterBlocks,
      ...peqBlocks,
      ...xoBlocks,
      ...muteDelayBlocks
    ];
    final pkg = gainPkg.copyWith(
      status:
          allBlocks.isEmpty ? ExportStatus.notReady : ExportStatus.draftReady,
      parameterBlocks: allBlocks,
    );
    _plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
    _hasWritableOps = _plan.writableOperations.isNotEmpty;
  }

  List<HardwareWriteOp> get _blockedOps =>
      _plan.operations.where((o) => !o.writable).toList();

  Future<void> _execute() async {
    if (!_hasWritableOps) return;
    setState(() {
      _phase = _Phase.executing;
      _progress = null;
      _restored = false;
    });

    final Icp5PeqWritePort port;
    if (widget.overridePort != null) {
      port = widget.overridePort!;
    } else {
      // Prefer the active context (BLE when BLE is connected, USB otherwise).
      // Falls back to USB-only provider so the dialog always has a context to
      // attempt — the USB context will fail closed via preflight if not ready.
      final Adau1701HardwareContext ctx =
          ref.read(activeAdau1701ContextProvider) ??
              ref.read(adau1701Icp5UsbContextProvider);
      port = ctx.writePort;
    }
    final approval =
        HardwareWriteApproval.approve(_plan, approver: 'deploy-dialog');
    final executor = HardwareWriteExecutor(port);

    // Suspend the BLE heartbeat for the duration of the deploy. The heartbeat
    // grabs _busy between write operations and causes cascading NACKs
    // ("Another ICP5 transaction is active") on all remaining operations.
    // During deploy the app sends continuous writes so the ICP5 idle timer
    // cannot expire — heartbeat is unnecessary for this window.
    final rawTransport = widget.overridePort == null
        ? ref.read(activeAdau1701ContextProvider)?.transport
        : null;
    final bleTransport = rawTransport is Icp5BluetoothTransport ? rawTransport : null;
    bleTransport?.pauseHeartbeat();
    // If a heartbeat exchange was already in-flight when pauseHeartbeat() was
    // called, it holds _busy until its BLE exchange completes. Poll until clear
    // (up to 3.5 s — BLE readTimeout + quarantine) before starting writes.
    if (bleTransport != null) {
      const _pollMs = Duration(milliseconds: 50);
      var waited = 0;
      while (bleTransport.busy && waited < 3500) {
        await Future.delayed(_pollMs);
        waited += 50;
      }
    }

    final HardwareWriteExecutionResult result;
    try {
      result = await executor.execute(
        approval,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } finally {
      bleTransport?.resumeHeartbeat();
    }

    // Persist the acknowledged gains for rollback. Channel gain has no
    // readback service, so a successful write is always ackOnly, never
    // `written` — gating on `written` here would mean this never persists
    // anything. `succeeded` (written OR ackOnly) is the correct condition;
    // it does not claim DSP-side verification, only that the device
    // acknowledged the command (see HardwareWriteOpStatus docs).
    if (result.executed) {
      final written = <String, double>{};
      final xoChangedChannels = <String>{};
      for (final o in result.outcomes) {
        if (!o.succeeded) continue;
        if (o.op.parameterKind == HardwareParamKind.channelGain) {
          written[o.op.channelId] = o.op.targetValue.toDouble();
        } else if (o.op.parameterKind == HardwareParamKind.crossoverHighPass ||
            o.op.parameterKind == HardwareParamKind.crossoverLowPass) {
          xoChangedChannels.add(o.op.channelId);
        }
      }
      if (written.isNotEmpty && mounted) {
        await ref
            .read(proProjectStoreProvider.notifier)
            .updateDeployAppliedGains(widget.projectId, written);
      }
      // Record the full current XO state (not just the changed side) for
      // each channel with a successful write — the unchanged side, if any,
      // already matched by definition of the diff, so this accurately
      // reflects what hardware now holds. See buildAdau1701XoExportBlocks().
      if (xoChangedChannels.isNotEmpty && mounted) {
        final xoUpdates = <String, AppliedXoChannelState>{};
        for (final channelId in xoChangedChannels) {
          final xoCh = widget.tuning.crossoverChannels
              .where((c) => c.channelId == channelId)
              .firstOrNull;
          if (xoCh == null) continue;
          xoUpdates[channelId] = AppliedXoChannelState(
            channelId: channelId,
            highPassFrequency:
                xoCh.hasHighPass ? xoCh.highPass!.frequencyHz : null,
            lowPassFrequency:
                xoCh.hasLowPass ? xoCh.lowPass!.frequencyHz : null,
            filterType: xoCh.highPass?.type ?? xoCh.lowPass?.type,
            slope: xoCh.highPass?.slope ?? xoCh.lowPass?.slope,
          );
        }
        if (xoUpdates.isNotEmpty) {
          await ref
              .read(proProjectStoreProvider.notifier)
              .updateDeployAppliedXo(widget.projectId, xoUpdates);
        }
      }
    }

    if (mounted) {
      setState(() {
        _result = result;
        _phase = _Phase.result;
      });
    }
  }

  bool get _canRestoreGain => widget.previousAppliedGains.isNotEmpty;

  bool get _canRestorePeq =>
      _result?.outcomes.any((o) => o.report?.capturedOriginalState != null) ==
      true;

  bool get _canRestore => _canRestoreGain || _canRestorePeq;

  Future<void> _restore() async {
    if (!_canRestore) return;
    setState(() => _isRestoring = true);

    final prev = widget.previousAppliedGains;

    // Gain restore blocks: write each channel's previous applied gain.
    final restoreBlocks = <ExportParameterBlock>[];
    for (final e in prev.entries) {
      final ch = widget.channels.firstWhere(
        (c) => c.id == e.key,
        orElse: () => DriverChannel(
          id: e.key,
          name: e.key,
          role: DriverRole.unknown,
          side: DriverSide.mono,
        ),
      );
      restoreBlocks.add(ExportParameterBlock(
        id: 'restore_gain_${e.key}',
        type: ExportBlockType.gain,
        channelId: e.key,
        title: '${ch.name} Restore',
        summary: '${e.value >= 0 ? '+' : ''}${e.value.toStringAsFixed(1)} dB',
        parameters: {'gainDb': e.value},
      ));
    }

    // PEQ band 0 restore blocks: restore to capturedOriginalState for each
    // channel that has a pre-write snapshot. Deduplicate by channelId/band.
    final restoredPeqKeys = <String>{};
    for (final o in (_result?.outcomes ?? <HardwareWriteOpOutcome>[])) {
      final orig = o.report?.capturedOriginalState;
      if (orig == null) continue;
      final bandIdx = o.op.bandIndex ?? 0;
      final key = '${o.op.channelId}_$bandIdx';
      if (!restoredPeqKeys.add(key)) continue;
      restoreBlocks.add(ExportParameterBlock(
        id: 'restore_peq_$key',
        type: ExportBlockType.peq,
        channelId: o.op.channelId,
        title: '${o.op.channelId} PEQ B${bandIdx + 1} Restore',
        summary: 'Band ${bandIdx + 1}',
        parameters: {
          'bands': {
            'band_$bandIdx': {
              'freq_hz': orig.frequencyHz.toDouble(),
              'gain_db': orig.gainDb,
              'q': orig.q,
            }
          }
        },
      ));
    }

    final restorePkg = DspExportPackage(
      id: 'restore_${DateTime.now().millisecondsSinceEpoch}',
      targetPlatform: DspTargetPlatform.adau1701,
      format: ExportFormat.hardwareWritePlanPlaceholder,
      status: ExportStatus.draftReady,
      projectName: 'Restore',
      tuningRevision: 0,
      protectionRevision: 0,
      optimizerRevision: 0,
      parameterBlocks: restoreBlocks,
    );

    final restorePlan =
        buildHardwareWritePlan(restorePkg, HardwareDeviceProfiles.adau1701Icp5);
    final Adau1701HardwareContext ctx =
        ref.read(activeAdau1701ContextProvider) ??
            ref.read(adau1701Icp5UsbContextProvider);
    final approval = HardwareWriteApproval.approve(restorePlan,
        approver: 'deploy-dialog-restore');
    final executor = HardwareWriteExecutor(ctx.writePort);
    final result = await executor.execute(approval);

    // Persist restored values. See the same `succeeded` note in _execute().
    if (result.executed) {
      final restored = <String, double>{};
      for (final o in result.outcomes) {
        if (o.succeeded && o.op.parameterKind == HardwareParamKind.channelGain) {
          restored[o.op.channelId] = o.op.targetValue.toDouble();
        }
      }
      if (restored.isNotEmpty && mounted) {
        await ref
            .read(proProjectStoreProvider.notifier)
            .updateDeployAppliedGains(widget.projectId, restored);
      }
    }

    if (mounted) {
      setState(() {
        _result = result;
        _isRestoring = false;
        _restored = result.allPassed;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: kProPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, minWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 16),
                // Flexible + scroll so the body (in particular the blocked
                // list, now taller with a per-op reason line) shrinks to fit
                // the dialog's available height and scrolls internally
                // instead of overflowing the bottom of the dialog.
                Flexible(child: SingleChildScrollView(child: _body())),
                const SizedBox(height: 20),
                _actions(),
              ],
            ),
          ),
        ),
      );

  Widget _header() => Row(children: [
        Icon(Icons.memory_outlined,
            color: kProAccent.withValues(alpha: 0.7), size: 16),
        const SizedBox(width: 8),
        Text('DSP Write — ADAU1701', style: proTitle(size: 14)),
        const Spacer(),
        if (_phase == _Phase.executing)
          const SizedBox(
            width: 14,
            height: 14,
            child:
                CircularProgressIndicator(strokeWidth: 1.5, color: kProAccent),
          ),
      ]);

  /// V3-6A: the shared five-step ladder, computed entirely from state this
  /// dialog already tracks (_phase, _plan, _blockedOps, previousApplied*,
  /// _progress, _result) — no new state, no new persistence.
  List<DeployStepInfo> _deploySteps() {
    final blocked = _blockedOps;
    final hasPrevious =
        widget.previousAppliedGains.isNotEmpty || widget.previousAppliedXo.isNotEmpty;
    final r = _result;

    return [
      // This dialog only opens via the top-bar DEPLOY button, which is
      // itself gated on a live, handshake-verified connection — so by the
      // time this dialog is visible, project check has already passed.
      const DeployStepInfo(
        kind: DeployStepKind.projectCheck,
        status: DeployStepStatus.complete,
        detail: 'Hardware connected',
      ),
      DeployStepInfo(
        kind: DeployStepKind.writePlan,
        status: _phase == _Phase.plan
            ? DeployStepStatus.active
            : DeployStepStatus.complete,
        detail: '${_plan.writableOperations.length} operation(s)'
            '${blocked.isEmpty ? '' : ' · ${blocked.length} blocked'}',
      ),
      DeployStepInfo(
        kind: DeployStepKind.backupRestore,
        status: hasPrevious ? DeployStepStatus.complete : DeployStepStatus.pending,
        detail: hasPrevious
            ? 'Previous applied state available for restore'
            : 'No previous applied state to restore',
      ),
      DeployStepInfo(
        kind: DeployStepKind.apply,
        status: switch (_phase) {
          _Phase.plan => DeployStepStatus.pending,
          _Phase.executing => DeployStepStatus.active,
          _Phase.result => DeployStepStatus.complete,
        },
        detail: _phase == _Phase.executing && _progress != null
            ? '${_progress!.completed} / ${_progress!.total}'
            : null,
      ),
      DeployStepInfo(
        kind: DeployStepKind.result,
        status: r == null
            ? DeployStepStatus.pending
            : (r.failures.isEmpty
                ? DeployStepStatus.complete
                : DeployStepStatus.blocked),
      ),
    ];
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DeployStepLadder(steps: _deploySteps()),
        const SizedBox(height: 14),
        switch (_phase) {
          _Phase.plan => _planView(),
          _Phase.executing => _executingView(),
          _Phase.result => _resultView(),
        },
      ],
    );
  }

  Widget _planView() {
    final blocked = _blockedOps;
    if (!_hasWritableOps && blocked.isEmpty) {
      final String title;
      final String nextAction;
      if (widget.channels.isEmpty) {
        title = 'No driver channels configured.';
        nextAction = 'Add driver channels in the Import tab, then deploy again.';
      } else if (widget.tuning.peqChannels.isEmpty) {
        title = 'No pending writes.';
        nextAction =
            'No PEQ/Gain/XO configuration exists yet for these channels. '
            'Run Guided AI or manual tuning first, then deploy again.';
      } else {
        title = 'No pending writes.';
        nextAction = 'Current tuning already matches what was last deployed.';
      }
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: proSubtitle(size: 11)),
            const SizedBox(height: 4),
            Text(nextAction, style: proSubtitle(size: 10, color: Colors.white38)),
          ],
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_hasWritableOps) ...[
        Text('PENDING WRITES',
            style: proLabel(size: 9, color: Colors.white38, spacing: 1.5)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _plan.writableOperations.map((op) {
                final isGain =
                    op.parameterKind == HardwareParamKind.channelGain;
                final prev =
                    isGain ? widget.previousAppliedGains[op.channelId] : null;
                final prevLabel = prev != null
                    ? '${prev >= 0 ? '+' : ''}${prev.toStringAsFixed(1)} dB'
                    : '—';
                final newLabel = _opValueLabel(op);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(
                        flex: 3,
                        child: Text(op.channelId,
                            style: proValue(size: 11, color: Colors.white70))),
                    Expanded(
                        flex: 2,
                        child: Text(_opKindLabel(op),
                            style: proSubtitle(size: 10))),
                    Expanded(
                        flex: 2,
                        child: Text(prevLabel,
                            style:
                                proSubtitle(size: 10, color: Colors.white38))),
                    const Icon(Icons.arrow_forward,
                        size: 10, color: Colors.white24),
                    const SizedBox(width: 4),
                    Expanded(
                        flex: 2,
                        child: Text(newLabel,
                            style: proValue(size: 11, color: kProAccent))),
                  ]),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This will write ${_plan.writableOperations.length} operation(s) '
          'through the connected ICP5 transport.',
          style: proSubtitle(size: 10, color: Colors.white38),
        ),
      ],
      if (blocked.any((op) =>
          op.parameterKind == HardwareParamKind.crossoverHighPass ||
          op.parameterKind == HardwareParamKind.crossoverLowPass)) ...[
        if (_hasWritableOps) const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.08),
            border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Icon(Icons.block_outlined, size: 14, color: kProAmber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'XO hardware deployment temporarily blocked — mapping '
                'validation required.',
                style: proValue(size: 11, color: kProAmber),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
      ],
      if (blocked.isNotEmpty) ...[
        if (_hasWritableOps) const SizedBox(height: 12),
        Text('BLOCKED (${blocked.length})',
            style: proLabel(
                size: 9,
                color: kProAmber.withValues(alpha: 0.7),
                spacing: 1.5)),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: blocked
                  .map((op) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  flex: 3,
                                  child: Text(op.channelId,
                                      style: proValue(
                                          size: 11, color: Colors.white38))),
                              Expanded(
                                  flex: 3,
                                  child: Text(_opKindLabel(op),
                                      style: proSubtitle(
                                          size: 10, color: Colors.white38))),
                              Expanded(
                                  flex: 3,
                                  child: Text(_opValueLabel(op),
                                      style: proSubtitle(
                                          size: 10, color: Colors.white38))),
                              Text('BLOCKED',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: kProAmber.withValues(alpha: 0.7),
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.w600)),
                            ]),
                            const SizedBox(height: 2),
                            // Actual reason from HardwareWriteOp.reason (set by
                            // pro_hardware_write_plan.dart's _reasonFor()) —
                            // previously only a hardcoded generic header was
                            // shown here; this is the specific rationale for
                            // why this exact op is blocked.
                            Text(op.reason,
                                style: proSubtitle(
                                    size: 9, color: Colors.white24)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    ]);
  }

  static String _opKindLabel(HardwareWriteOp op) => switch (op.parameterKind) {
        HardwareParamKind.channelGain => 'Channel Gain',
        HardwareParamKind.channelMute => 'Mute',
        HardwareParamKind.channelDelay => 'Delay',
        HardwareParamKind.peqGain => 'PEQ B${(op.bandIndex ?? 0) + 1} Gain',
        HardwareParamKind.peqFrequency =>
          'PEQ B${(op.bandIndex ?? 0) + 1} Freq',
        HardwareParamKind.peqQ => 'PEQ B${(op.bandIndex ?? 0) + 1} Q',
        HardwareParamKind.crossoverHighPass => 'XO HPF',
        HardwareParamKind.crossoverLowPass => 'XO LPF',
        _ => op.parameterKind.name,
      };

  static String _opValueLabel(HardwareWriteOp op) {
    final v = op.targetValue.toDouble();
    return switch (op.parameterKind) {
      HardwareParamKind.channelMute => 'MUTED (State 0)',
      HardwareParamKind.channelDelay => '${v.toStringAsFixed(1)} ms',
      HardwareParamKind.peqFrequency ||
      HardwareParamKind.crossoverHighPass ||
      HardwareParamKind.crossoverLowPass =>
        v >= 1000
            ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)} kHz'
            : '${v.toStringAsFixed(0)} Hz',
      HardwareParamKind.peqQ => v.toStringAsFixed(1),
      _ => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
    };
  }

  Widget _executingView() {
    final p = _progress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
            'Writing to DSP…',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (p != null) ...[
            const SizedBox(width: 8),
            Text(
              '${p.completed + 1} / ${p.total}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            if (p.total > 0) ...[
              const SizedBox(width: 6),
              Text(
                '(${(p.completed / p.total * 100).round()}%)',
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ],
        ]),
        if (p != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: p.total > 0 ? p.completed / p.total : null,
              backgroundColor: Colors.white12,
              color: kProAccent,
              minHeight: 3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.label,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ]),
    );
  }

  Widget _resultView() {
    final r = _result;
    if (r == null) return const SizedBox.shrink();

    final failures = r.failures;
    final firstFailure = failures.isEmpty ? null : failures.first;
    final firstFailureIndex =
        firstFailure == null ? null : r.outcomes.indexOf(firstFailure) + 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // V3-6A: shared result wording ("Verified" / "PASS_ACK (not
      // DSP-verified)") — never labels an ack-only result as verified (see
      // DeployResultSummary.labelFor). V3-6B: the FAIL branch is now a
      // structured, scannable card (operation index/total, channel,
      // parameter, band, reason) instead of one dense inline string — same
      // underlying failure data, no change to how it's computed.
      DeployResultSummary(
        result: r,
        failureBuilder: (_) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.08),
            border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.block_outlined, color: kProAmber, size: 14),
              const SizedBox(width: 8),
              Text('FAIL ${failures.length}개',
                  style: proValue(size: 11, color: kProAmber)),
            ]),
            if (firstFailure != null) ...[
              const SizedBox(height: 8),
              ProInfoRow(
                  label: 'Operation',
                  value: '$firstFailureIndex / ${r.outcomes.length}'),
              ProInfoRow(label: 'Channel', value: firstFailure.op.channelId),
              ProInfoRow(
                  label: 'Parameter', value: _opKindLabel(firstFailure.op)),
              ProInfoRow(
                  label: 'Band',
                  value: firstFailure.op.bandIndex == null
                      ? '-'
                      : '${firstFailure.op.bandIndex! + 1}'),
              ProInfoRow(label: 'Reason', value: firstFailure.message),
            ],
          ]),
        ),
      ),
      if (r.outcomes.isNotEmpty) ...[
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: r.outcomes.asMap().entries.map((entry) {
                final index = entry.key;
                final o = entry.value;
                // V3-6B: blockedByPreflight (never truly attempted — the
                // existing preflight chain refused it) reads as amber, the
                // same as ackOnly, distinct from a genuine execution error
                // (failed/timedOut, red) — matches hardware_apply_flow.dart's
                // existing _statusColor mapping.
                final c = switch (o.status) {
                  HardwareWriteOpStatus.written => kProGreen,
                  HardwareWriteOpStatus.ackOnly => kProAmber,
                  HardwareWriteOpStatus.blockedByPreflight => kProAmber,
                  HardwareWriteOpStatus.failed => kProRed,
                  HardwareWriteOpStatus.timedOut => kProRed,
                  HardwareWriteOpStatus.unsupported => Colors.white38,
                };
                final statusText = switch (o.status) {
                  HardwareWriteOpStatus.written => o.status.label,
                  HardwareWriteOpStatus.ackOnly =>
                    o.message.isNotEmpty ? o.message : o.status.label,
                  _ => o.message.isNotEmpty ? o.message : o.status.label,
                };
                return Padding(
                  key: o.isFailure
                      ? ValueKey('deploy-failure-row-$index')
                      : ValueKey('deploy-success-row-$index'),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                      '${o.op.channelId} ${_opKindLabel(o.op)}',
                      style: proSubtitle(size: 10),
                    )),
                    Flexible(
                      child: Text(
                        statusText,
                        style: proValue(size: 10, color: c),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
        ),
      ],
      if (_isRestoring) ...[
        const SizedBox(height: 8),
        const Text('Restoring…',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    ]);
  }

  Widget _actions() {
    final canRestore = _canRestore && _phase == _Phase.result && !_isRestoring;

    // Build scope label for RESTORE button (shows only restorable items).
    final restoreScope = <String>[
      if (_canRestoreGain) 'GAIN',
      if (_canRestorePeq) 'PEQ B1',
    ];
    final restoreLabel = restoreScope.isEmpty
        ? 'RESTORE'
        : 'RESTORE (${restoreScope.join(' + ')})';

    return Row(children: [
      if (_restored)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            'RESTORED',
            style: TextStyle(
              color: kProGreen,
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
        )
      else if (canRestore)
        OutlinedButton.icon(
          icon: const Icon(Icons.restore, size: 13),
          label: Text(restoreLabel),
          style: OutlinedButton.styleFrom(
            foregroundColor: kProAmber,
            side: BorderSide(color: kProAmber.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(fontSize: 10, letterSpacing: 0.8),
          ),
          onPressed: _restore,
        ),
      const Spacer(),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white38,
          textStyle: const TextStyle(fontSize: 11),
        ),
        child: Text(_phase == _Phase.result ? 'CLOSE' : 'CANCEL'),
      ),
      if (_phase == _Phase.plan && _hasWritableOps) ...[
        const SizedBox(width: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_outlined, size: 13),
          label: const Text('APPROVE & WRITE'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kProAccent,
            side: BorderSide(color: kProAccent.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(fontSize: 10, letterSpacing: 0.8),
          ),
          onPressed: _execute,
        ),
      ],
    ]);
  }
}
