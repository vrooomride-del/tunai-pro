import 'package:flutter/material.dart';

import '../../../core/deploy/pro_adau1701_hardware_context.dart';
import '../../../core/deploy/pro_hardware_capability.dart';
import '../../../core/deploy/pro_hardware_write_approval.dart';
import '../../../core/deploy/pro_hardware_write_executor.dart';
import '../../../core/deploy/pro_hardware_write_plan.dart';
import '../../../core/pro_export_data.dart';
import '../../../shared/pro_widgets.dart';
import 'deploy_result_summary.dart';
import 'deploy_step_ladder.dart';
import 'hardware_apply_preview.dart';

/// Gated hardware-apply workflow for the Deploy tab.
///
/// Renders the plan preview, then a two-step gate: APPROVE VERIFIED WRITE builds
/// a [HardwareWriteApproval] (capture-proven ops only); APPLY VERIFIED SETTINGS
/// runs [HardwareWriteExecutor.execute] against the [Adau1701HardwareContext]'s
/// write port and shows per-operation results.
///
/// The UI calls only the approval/executor/context layers — never a transport,
/// gate, or DSP write directly.
class HardwareApplyFlow extends StatefulWidget {
  final DspExportPackage exportPackage;
  final HardwareDeviceProfile profile;

  /// Injectable for tests; defaults to the shared ICP5 USB context.
  final Adau1701HardwareContext Function()? contextFactory;

  /// Called once after execute() completes, with the result. Null = not wired.
  final ValueChanged<HardwareWriteExecutionResult>? onResult;

  const HardwareApplyFlow({
    super.key,
    required this.exportPackage,
    required this.profile,
    this.contextFactory,
    this.onResult,
  });

  @override
  State<HardwareApplyFlow> createState() => _HardwareApplyFlowState();
}

class _HardwareApplyFlowState extends State<HardwareApplyFlow> {
  late HardwareWritePlan _plan;
  late Adau1701HardwareContext _context;
  HardwareWriteApproval? _approval;
  HardwareWriteExecutionResult? _result;
  HardwareWriteProgress? _progress;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _plan = buildHardwareWritePlan(widget.exportPackage, widget.profile);
    _context = widget.contextFactory != null
        ? widget.contextFactory!()
        : Adau1701HardwareContext.icp5Usb();
  }

  @override
  void didUpdateWidget(HardwareApplyFlow old) {
    super.didUpdateWidget(old);
    if (old.exportPackage.id != widget.exportPackage.id ||
        old.profile.deviceId != widget.profile.deviceId) {
      setState(() {
        _plan = buildHardwareWritePlan(widget.exportPackage, widget.profile);
        _approval = null;
        _result = null;
      });
    }
  }

  void _approve() {
    setState(() {
      _approval = HardwareWriteApproval.approve(_plan, approver: 'deploy-ui');
      _result = null;
    });
  }

  Future<void> _apply() async {
    final approval = _approval;
    if (approval == null ||
        !approval.isApproved ||
        !_context.isReady ||
        _applying) {
      return;
    }
    setState(() {
      _applying = true;
      _progress = null;
    });
    try {
      final result = await HardwareWriteExecutor(_context.writePort).execute(
        approval,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) {
        setState(() => _result = result);
        widget.onResult?.call(result);
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// V3-6A: the shared five-step ladder, computed entirely from state this
  /// flow already tracks (_context, _plan, _approval, _applying, _progress,
  /// _result) — no new state, no new persistence. This flow has no restore
  /// concept of its own (unlike deploy_dialog.dart), so BACKUP/RESTORE is
  /// reported honestly as unavailable here rather than invented.
  List<DeployStepInfo> _deploySteps() {
    final approved = _approval?.isApproved ?? false;
    final ready = _context.isReady;
    final r = _result;

    return [
      DeployStepInfo(
        kind: DeployStepKind.projectCheck,
        status: ready ? DeployStepStatus.complete : DeployStepStatus.blocked,
        detail: ready ? 'Hardware connected' : 'Hardware disconnected',
      ),
      DeployStepInfo(
        kind: DeployStepKind.writePlan,
        status: approved ? DeployStepStatus.complete : DeployStepStatus.active,
        detail: '${_plan.summary.writableOps} operation(s)'
            '${_plan.summary.totalOps - _plan.summary.writableOps > 0 ? ' · ${_plan.summary.totalOps - _plan.summary.writableOps} blocked' : ''}',
      ),
      const DeployStepInfo(
        kind: DeployStepKind.backupRestore,
        status: DeployStepStatus.pending,
        detail: 'Restore not available in this flow',
      ),
      DeployStepInfo(
        kind: DeployStepKind.apply,
        status: r != null
            ? DeployStepStatus.complete
            : (_applying ? DeployStepStatus.active : DeployStepStatus.pending),
        detail: _applying && _progress != null
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

  @override
  Widget build(BuildContext context) {
    final approved = _approval?.isApproved ?? false;
    final ready = _context.isReady;
    final isStale = widget.exportPackage.status == ExportStatus.stale;
    // A stale package (tuning changed since it was built, e.g. after a
    // software rollback) must never reach approval, and therefore never
    // reach HardwareWriteExecutor — the smallest, single-point gate to
    // enforce that is refusing to approve it in the first place.
    final canApprove = _plan.summary.writableOps > 0 && !approved && !isStale;
    final canApply = approved && ready && !_applying;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DeployStepLadder(steps: _deploySteps()),
      const SizedBox(height: 12),
      HardwareApplyPreview(plan: _plan),
      const SizedBox(height: 12),

      // Two-step gate.
      Wrap(spacing: 10, runSpacing: 8, children: [
        _actionButton(
          label: 'APPROVE VERIFIED WRITE',
          icon: Icons.verified_outlined,
          onPressed: canApprove ? _approve : null,
        ),
        _actionButton(
          label: _applying ? 'APPLYING…' : 'APPLY VERIFIED SETTINGS',
          icon: Icons.upload_outlined,
          onPressed: canApply ? _apply : null,
          accent: kProGreen,
        ),
      ]),

      // Approval status.
      if (_approval != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          Icon(
            approved ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 12,
            color: approved ? kProGreen : kProAmber,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              approved
                  ? 'Approved ${_approval!.approvedCount} operation(s) by '
                      '${_approval!.approver}.'
                  : 'Approval ${_approval!.status.label}: '
                      '${_approval!.rejectionReason ?? ''}',
              style: proSubtitle(size: 10),
            ),
          ),
        ]),
      ],

      // Live progress during execution.
      if (_applying) ...[
        const SizedBox(height: 10),
        Row(children: [
          Text('Writing…', style: proSubtitle(size: 10)),
          if (_progress case final p?) ...[
            const SizedBox(width: 8),
            Text('${p.completed + 1} / ${p.total}',
                style: proSubtitle(size: 10, color: Colors.white38)),
            if (p.total > 0) ...[
              const SizedBox(width: 6),
              Text('(${(p.completed / p.total * 100).round()}%)',
                  style: proSubtitle(size: 9, color: Colors.white24)),
            ],
          ],
        ]),
        if (_progress case final p?) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: p.total > 0 ? p.completed / p.total : null,
              backgroundColor: kProBorder,
              color: kProAccent,
              minHeight: 3,
            ),
          ),
          const SizedBox(height: 4),
          Text(p.label,
              style: proSubtitle(size: 10, color: Colors.white38),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ],

      // Stale-package note — this package cannot be approved/applied at all
      // until a current one is built or selected.
      if (isStale) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.warning_amber_outlined, size: 12, color: kProAmber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Stale package — tuning changed after this package was '
              'created. Build or select a current package before deploying.',
              style: proSubtitle(size: 10, color: kProAmber),
            ),
          ),
        ]),
      ],

      // Readiness note.
      if (approved && !ready) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.link_off_outlined, size: 12, color: kProAmber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Hardware not ready — connect an ICP5 device before applying.',
              style: proSubtitle(size: 10, color: kProAmber),
            ),
          ),
        ]),
      ],

      // Execution results.
      if (_result != null) ...[
        const SizedBox(height: 12),
        _ResultsView(result: _result!),
      ],
    ]);
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    Color accent = kProAccent,
  }) {
    final enabled = onPressed != null;
    return OutlinedButton.icon(
      icon: Icon(icon,
          size: 14, color: enabled ? accent : Colors.white24),
      label: Text(label,
          style: proLabel(
              size: 10,
              color: enabled ? accent : Colors.white24,
              spacing: 0.5)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
            color: enabled ? accent.withValues(alpha: 0.5) : kProBorder),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      ),
      onPressed: onPressed,
    );
  }
}

class _ResultsView extends StatelessWidget {
  final HardwareWriteExecutionResult result;
  const _ResultsView({required this.result});

  Color _statusColor(HardwareWriteOpStatus s) => switch (s) {
        HardwareWriteOpStatus.written => kProGreen,
        HardwareWriteOpStatus.ackOnly => kProAmber,
        HardwareWriteOpStatus.blockedByPreflight => kProAmber,
        HardwareWriteOpStatus.failed => kProRed,
        HardwareWriteOpStatus.timedOut => kProRed,
        HardwareWriteOpStatus.unsupported => Colors.white38,
      };

  @override
  Widget build(BuildContext context) {
    if (!result.executed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('Not executed: ${result.rejectionReason ?? ''}',
            style: proSubtitle(size: 10, color: kProAmber)),
      );
    }
    // V3-6B: result.failedCount (HardwareWriteExecutionResult, kept
    // unchanged) counts failed + timedOut + blockedByPreflight together — so
    // it double-counts the same ops already shown in the BLOCKED chip below.
    // This UI-local count excludes blockedByPreflight so the two chips never
    // overlap; the shared getter itself is untouched.
    final failedOnlyCount = result.outcomes
        .where((o) =>
            o.status == HardwareWriteOpStatus.failed ||
            o.status == HardwareWriteOpStatus.timedOut)
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('APPLY RESULTS', style: proLabel(size: 9, spacing: 1.5)),
        const SizedBox(height: 8),
        // V3-6A: this flow previously had no aggregate summary sentence at
        // all — only the per-op WRITTEN/BLOCKED/FAILED/UNSUPPORTED chips and
        // per-row status labels below. Shares the same wording/rule as
        // deploy_dialog.dart/deploy_tab.dart: an ack-only result is never
        // labeled "Verified".
        DeployResultSummary(result: result),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, children: [
          _CountChip(label: 'WRITTEN', value: '${result.writtenCount}',
              color: result.writtenCount > 0 ? kProGreen : null),
          _CountChip(label: 'BLOCKED', value: '${result.blockedCount}',
              color: result.blockedCount > 0 ? kProAmber : null),
          _CountChip(
              label: 'FAILED',
              value: '$failedOnlyCount',
              color: failedOnlyCount > 0 ? kProRed : null),
          _CountChip(label: 'UNSUPPORTED', value: '${result.unsupportedCount}',
              color: result.unsupportedCount > 0 ? Colors.white38 : null),
        ]),
        const SizedBox(height: 10),
        ...result.outcomes.map((o) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    SizedBox(
                      width: 70,
                      child: Text(o.op.channelId,
                          style: proValue(size: 10, color: Colors.white54),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: Text(
                          '${HardwareApplyPreview.paramLabel(o.op.parameterKind)} · '
                          '${HardwareApplyPreview.bandLabel(o.op.bandIndex)}',
                          style: proLabel(size: 10, spacing: 0.2)),
                    ),
                    Text(o.status.label,
                        style:
                            proValue(size: 10, color: _statusColor(o.status))),
                  ]),
                  // V3-6B: surfaces the failure/blocked reason that was
                  // previously only visible in deploy_dialog.dart, never here.
                  if (o.isFailure && o.message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(o.message,
                        style: proSubtitle(size: 9, color: _statusColor(o.status))),
                  ],
                ],
              ),
            )),
      ]),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _CountChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: kProBg,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: proLabel(size: 8, spacing: 0.8)),
          const SizedBox(height: 2),
          Text(value, style: proValue(size: 13, color: color ?? Colors.white54)),
        ]),
      );
}
