import 'package:flutter/material.dart';

import '../../../core/deploy/pro_adau1701_hardware_context.dart';
import '../../../core/deploy/pro_hardware_capability.dart';
import '../../../core/deploy/pro_hardware_write_approval.dart';
import '../../../core/deploy/pro_hardware_write_executor.dart';
import '../../../core/deploy/pro_hardware_write_plan.dart';
import '../../../core/pro_export_data.dart';
import '../../../shared/pro_widgets.dart';
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

  const HardwareApplyFlow({
    super.key,
    required this.exportPackage,
    required this.profile,
    this.contextFactory,
  });

  @override
  State<HardwareApplyFlow> createState() => _HardwareApplyFlowState();
}

class _HardwareApplyFlowState extends State<HardwareApplyFlow> {
  late HardwareWritePlan _plan;
  late Adau1701HardwareContext _context;
  HardwareWriteApproval? _approval;
  HardwareWriteExecutionResult? _result;
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
    setState(() => _applying = true);
    try {
      final result =
          await HardwareWriteExecutor(_context.writePort).execute(approval);
      if (mounted) setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = _approval?.isApproved ?? false;
    final ready = _context.isReady;
    final canApprove = _plan.summary.writableOps > 0 && !approved;
    final canApply = approved && ready && !_applying;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        HardwareWriteOpStatus.blockedByPreflight => kProAmber,
        HardwareWriteOpStatus.failed => kProRed,
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
        Wrap(spacing: 10, runSpacing: 8, children: [
          _CountChip(label: 'WRITTEN', value: '${result.writtenCount}',
              color: result.writtenCount > 0 ? kProGreen : null),
          _CountChip(label: 'BLOCKED', value: '${result.blockedCount}',
              color: result.blockedCount > 0 ? kProAmber : null),
          _CountChip(label: 'FAILED', value: '${result.failedCount}',
              color: result.failedCount > 0 ? kProRed : null),
          _CountChip(label: 'UNSUPPORTED', value: '${result.unsupportedCount}',
              color: result.unsupportedCount > 0 ? Colors.white38 : null),
        ]),
        const SizedBox(height: 10),
        ...result.outcomes.map((o) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
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
                    style: proValue(size: 10, color: _statusColor(o.status))),
              ]),
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
