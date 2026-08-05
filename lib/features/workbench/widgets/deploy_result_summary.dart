// TUNAI PRO UI/UX v3 Phase V3-6A — Deploy Result Summary.
//
// Single, shared source of the "did this deploy actually verify the DSP"
// wording — reused by deploy_dialog.dart, hardware_apply_flow.dart, and
// deploy_tab.dart, which previously each computed their own version of this
// same distinction independently (and, per the V3-5B audit, one of them —
// deploy_tab.dart — used to get it wrong via HardwareWriteExecutionResult
// .allWritten alone, which is also true for an all-ack-only result).
//
// Reuses only existing data: HardwareWriteExecutionResult, .allReadbackVerified,
// .allWritten, HardwareWriteOpStatus. No new state, no persistence, no write
// logic — this widget only reads a result object callers already have.

import 'package:flutter/material.dart';

import '../../../core/deploy/pro_hardware_write_executor.dart';
import '../../../shared/pro_widgets.dart';

class DeployResultSummary extends StatelessWidget {
  final HardwareWriteExecutionResult? result;

  /// Rendered instead of the default BLOCKED pill when [result] has one or
  /// more failed/blocked/timed-out outcomes — callers keep full ownership of
  /// their own failure-detail wording (e.g. deploy_dialog.dart's per-channel/
  /// band FAIL message). Receives the non-null result with failures.
  final Widget Function(HardwareWriteExecutionResult result)? failureBuilder;

  const DeployResultSummary({super.key, required this.result, this.failureBuilder});

  /// The exact two allowed result strings — never a third variant, and an
  /// ack-only result NEVER returns the verified label.
  static String labelFor(HardwareWriteExecutionResult result) =>
      result.allReadbackVerified ? 'Verified' : 'PASS_ACK (not DSP-verified)';

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) return const SizedBox.shrink();

    if (!r.executed || r.failures.isNotEmpty) {
      final builder = failureBuilder;
      if (builder != null) return builder(r);
      return _pill(
        icon: Icons.block_outlined,
        color: kProAmber,
        label: r.executed
            ? '${r.failedCount} operation(s) blocked or failed'
            : r.rejectionReason ?? 'Not executed',
      );
    }

    final verified = r.allReadbackVerified;
    return _pill(
      icon: verified ? Icons.check_circle_outline : Icons.info_outline,
      // Both success states share the same green treatment as the existing
      // precedent in deploy_dialog.dart/deploy_tab.dart — an ack-only result
      // is still a legitimate successful write, just not readback-verified;
      // only the TEXT distinguishes the two, never the color/severity.
      color: kProGreen,
      label: labelFor(r),
    );
  }

  Widget _pill({
    required IconData icon,
    required Color color,
    required String label,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: proValue(size: 11, color: color))),
        ]),
      );
}
