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
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_export_data.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';

// ── Public entry point ────────────────────────────────────────────────────────

/// Opens the deploy dialog. Call from the top-right DEPLOY button.
Future<void> showDeployDialog({
  required BuildContext context,
  required String projectId,
  required List<DriverChannel> channels,
  required TuningProjectState tuning,
  required Map<String, double> previousAppliedGains,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeployDialogBody(
      projectId: projectId,
      channels: channels,
      tuning: tuning,
      previousAppliedGains: previousAppliedGains,
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

  const _DeployDialogBody({
    required this.projectId,
    required this.channels,
    required this.tuning,
    required this.previousAppliedGains,
  });

  @override
  ConsumerState<_DeployDialogBody> createState() => _DeployDialogBodyState();
}

class _DeployDialogBodyState extends ConsumerState<_DeployDialogBody> {
  _Phase _phase = _Phase.plan;
  HardwareWriteExecutionResult? _result;
  bool _isRestoring = false;

  late HardwareWritePlan _plan;
  late bool _hasWritableOps;

  @override
  void initState() {
    super.initState();
    _buildPlan(widget.previousAppliedGains);
  }

  void _buildPlan(Map<String, double> previousApplied) {
    final pkg = buildAdau1701GainExportPackage(
      channels: widget.channels,
      tuning: widget.tuning,
      previousAppliedGains: previousApplied.isEmpty ? null : previousApplied,
    );
    _plan = buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
    _hasWritableOps = _plan.writableOperations.isNotEmpty;
  }

  Future<void> _execute() async {
    if (!_hasWritableOps) return;
    setState(() => _phase = _Phase.executing);

    // Prefer the active context (BLE when BLE is connected, USB otherwise).
    // Falls back to USB-only provider so the dialog always has a context to
    // attempt — the USB context will fail closed via preflight if not ready.
    final Adau1701HardwareContext ctx =
        ref.read(activeAdau1701ContextProvider) ??
            ref.read(adau1701Icp5UsbContextProvider);
    final approval =
        HardwareWriteApproval.approve(_plan, approver: 'deploy-dialog');
    final executor = HardwareWriteExecutor(ctx.writePort);
    final result = await executor.execute(approval);

    // Persist the successfully-written gains for rollback.
    if (result.executed) {
      final written = <String, double>{};
      for (final o in result.outcomes) {
        if (o.status == HardwareWriteOpStatus.written &&
            o.op.parameterKind == HardwareParamKind.channelGain) {
          written[o.op.channelId] = o.op.targetValue.toDouble();
        }
      }
      if (written.isNotEmpty && mounted) {
        await ref
            .read(proProjectStoreProvider.notifier)
            .updateDeployAppliedGains(widget.projectId, written);
      }
    }

    if (mounted) {
      setState(() {
        _result = result;
        _phase = _Phase.result;
      });
    }
  }

  Future<void> _restore() async {
    final prev = widget.previousAppliedGains;
    if (prev.isEmpty) return;
    setState(() => _isRestoring = true);

    // Build a restore package: write each channel's previous value.
    final restoreBlocks = prev.entries.map((e) {
      final ch = widget.channels.firstWhere(
        (c) => c.id == e.key,
        orElse: () => DriverChannel(
          id: e.key,
          name: e.key,
          role: DriverRole.unknown,
          side: DriverSide.mono,
        ),
      );
      return ExportParameterBlock(
        id: 'restore_${e.key}',
        type: ExportBlockType.gain,
        channelId: e.key,
        title: '${ch.name} Restore',
        summary: '${e.value >= 0 ? '+' : ''}${e.value.toStringAsFixed(1)} dB',
        parameters: {'gainDb': e.value},
      );
    }).toList();

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
    final approval =
        HardwareWriteApproval.approve(restorePlan, approver: 'deploy-dialog-restore');
    final executor = HardwareWriteExecutor(ctx.writePort);
    final result = await executor.execute(approval);

    // Persist restored values.
    if (result.executed) {
      final restored = <String, double>{};
      for (final o in result.outcomes) {
        if (o.status == HardwareWriteOpStatus.written &&
            o.op.parameterKind == HardwareParamKind.channelGain) {
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
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: kProPanel,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
                _body(),
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
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: kProAccent),
          ),
      ]);

  Widget _body() {
    return switch (_phase) {
      _Phase.plan => _planView(),
      _Phase.executing => _executingView(),
      _Phase.result => _resultView(),
    };
  }

  Widget _planView() {
    if (!_hasWritableOps) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _plan.operations.isEmpty
              ? 'No driver channels configured.'
              : 'No gain changes since last deploy.',
          style: proSubtitle(size: 11),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PENDING WRITES',
          style: proLabel(size: 9, color: Colors.white38, spacing: 1.5)),
      const SizedBox(height: 8),
      ...(_plan.writableOperations.map((op) {
        final prev = widget.previousAppliedGains[op.channelId];
        final prevLabel = prev != null
            ? '${prev >= 0 ? '+' : ''}${prev.toStringAsFixed(1)} dB'
            : 'Unknown';
        final newLabel =
            '${op.targetValue >= 0 ? '+' : ''}${op.targetValue.toStringAsFixed(1)} dB';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                flex: 3,
                child: Text(op.channelId,
                    style: proValue(size: 11, color: Colors.white70))),
            Expanded(
                flex: 2,
                child: Text('Channel Gain',
                    style: proSubtitle(size: 10))),
            Expanded(
                flex: 2,
                child: Text(prevLabel,
                    style: proSubtitle(size: 10,
                        color: Colors.white38))),
            const Icon(Icons.arrow_forward, size: 10, color: Colors.white24),
            const SizedBox(width: 4),
            Expanded(
                flex: 2,
                child: Text(newLabel,
                    style: proValue(size: 11, color: kProAccent))),
          ]),
        );
      })),
      const SizedBox(height: 8),
      Text(
        'This will write ${_plan.writableOperations.length} operation(s) '
        'through the connected ICP5 transport.',
        style: proSubtitle(size: 10, color: Colors.white38),
      ),
    ]);
  }

  Widget _executingView() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Writing to DSP…',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      );

  Widget _resultView() {
    final r = _result;
    if (r == null) return const SizedBox.shrink();

    final allWritten = r.allWritten;
    final color = allWritten ? kProGreen : kProAmber;
    final label = allWritten
        ? 'PASS_ACK — DSP write confirmed.'
        : r.executed
            ? '일부 쓰기 실패 (${r.failedCount + r.blockedCount}개).'
            : r.rejectionReason ?? '쓰기 미실행';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          Icon(
            allWritten ? Icons.check_circle_outline : Icons.block_outlined,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text(label, style: proValue(size: 11, color: color)),
          ),
        ]),
      ),
      if (r.outcomes.isNotEmpty) ...[
        const SizedBox(height: 10),
        ...r.outcomes.map((o) {
          final c = o.status == HardwareWriteOpStatus.written
              ? kProGreen
              : o.status == HardwareWriteOpStatus.blockedByPreflight
                  ? kProAmber
                  : kProRed;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(
                  child: Text(
                '${o.op.channelId} Channel Gain',
                style: proSubtitle(size: 10),
              )),
              Flexible(
                child: Text(
                  o.status == HardwareWriteOpStatus.blockedByPreflight
                      ? o.message
                      : o.status.label,
                  style: proValue(size: 10, color: c),
                  textAlign: TextAlign.end,
                ),
              ),
            ]),
          );
        }),
      ],
      if (_isRestoring) ...[
        const SizedBox(height: 8),
        const Text('Restoring…',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    ]);
  }

  Widget _actions() {
    final canRestore = widget.previousAppliedGains.isNotEmpty &&
        _phase == _Phase.result &&
        !_isRestoring;

    return Row(children: [
      if (canRestore)
        OutlinedButton.icon(
          icon: const Icon(Icons.restore, size: 13),
          label: const Text('RESTORE'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kProAmber,
            side: BorderSide(color: kProAmber.withValues(alpha: 0.5)),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle:
                const TextStyle(fontSize: 10, letterSpacing: 0.8),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle:
                const TextStyle(fontSize: 10, letterSpacing: 0.8),
          ),
          onPressed: _execute,
        ),
      ],
    ]);
  }
}
