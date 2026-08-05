// TUNAI PRO UI/UX v3 Phase V3-6A — Deploy Step Ladder.
//
// Shared, read-only visual chrome for the five deploy steps that
// deploy_dialog.dart, hardware_apply_flow.dart, and deploy_tab.dart each
// already track independently in their own local state:
//   PROJECT CHECK → WRITE PLAN → BACKUP/RESTORE → APPLY → RESULT
//
// This widget renders whatever [DeployStepInfo] list a caller builds from
// its OWN existing state (HardwareWriteApproval/HardwareWriteExecutionResult/
// connection providers/etc. already in use) — it introduces no new state
// model, no persistence, and no deploy/write logic of its own. Each host
// file computes its five steps' status/detail at build time from data it
// already has.

import 'package:flutter/material.dart';

import '../../../shared/pro_widgets.dart';

/// The five deploy steps every deploy UI in this app now shares. Order
/// matches the required ladder exactly.
enum DeployStepKind {
  projectCheck,
  writePlan,
  backupRestore,
  apply,
  result;

  String get label => switch (this) {
        DeployStepKind.projectCheck => 'PROJECT CHECK',
        DeployStepKind.writePlan => 'WRITE PLAN',
        DeployStepKind.backupRestore => 'BACKUP/RESTORE',
        DeployStepKind.apply => 'APPLY',
        DeployStepKind.result => 'RESULT',
      };
}

/// A step's current status, chosen by the caller from data it already has —
/// this widget performs no evaluation of its own.
enum DeployStepStatus { pending, active, complete, blocked }

class DeployStepInfo {
  final DeployStepKind kind;
  final DeployStepStatus status;

  /// Optional one-line detail shown under the step label (e.g. "128
  /// operations · 3 blocked"). Purely descriptive text supplied by the
  /// caller from data it already computed.
  final String? detail;

  const DeployStepInfo({
    required this.kind,
    required this.status,
    this.detail,
  });
}

/// Renders a vertical ladder of [DeployStepInfo]. Read-only — no callbacks,
/// no interactivity, no state of its own.
class DeployStepLadder extends StatelessWidget {
  final List<DeployStepInfo> steps;
  const DeployStepLadder({super.key, required this.steps});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final step in steps) _DeployStepRow(step: step),
          ],
        ),
      );
}

class _DeployStepRow extends StatelessWidget {
  final DeployStepInfo step;
  const _DeployStepRow({required this.step});

  Color get _color => switch (step.status) {
        DeployStepStatus.complete => kProGreen,
        DeployStepStatus.active => kProAccent,
        DeployStepStatus.blocked => kProAmber,
        DeployStepStatus.pending => Colors.white24,
      };

  IconData get _icon => switch (step.status) {
        DeployStepStatus.complete => Icons.check_circle_outline,
        DeployStepStatus.active => Icons.radio_button_checked,
        DeployStepStatus.blocked => Icons.error_outline,
        DeployStepStatus.pending => Icons.radio_button_unchecked,
      };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, size: 13, color: _color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step.kind.label,
                    style: TextStyle(
                      color: _color,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  if (step.detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      step.detail!,
                      style: proSubtitle(size: 9, color: Colors.white38),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}
