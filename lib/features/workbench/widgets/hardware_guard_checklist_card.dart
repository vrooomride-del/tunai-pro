// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-1C).
//
// UI extraction only: HardwareGuardChecklistCard and HardwareGuardPill are
// the same widgets that lived as the private `_GuardChecklistPanel` and
// `_GuardPill` classes inside hardware_tab.dart (renamed to public so they
// can be imported), moved verbatim with no change to how guardChecks data
// is generated or passed in. HardwareGuardPill stays public because
// hardware_tab.dart's own write-plan step rows still use it — it is not
// duplicated there. This file only displays an existing HardwareWritePlan's
// guardChecks; it does not touch safety validation, guard evaluation,
// HardwareWritePlan construction, DSP/BLE/transport, or any
// provider/controller.

import 'package:flutter/material.dart';

import '../../../core/pro_hardware_connection_data.dart';
import '../../../shared/pro_widgets.dart';

class HardwareGuardChecklistCard extends StatelessWidget {
  final HardwareWritePlan plan;
  const HardwareGuardChecklistCard({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const HardwareGuardPill(HardwareGuardStatus.pass),
          const SizedBox(width: 6),
          Text(
              '${plan.guardChecks.where((c) => c.status == HardwareGuardStatus.pass).length}',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(width: 12),
          const HardwareGuardPill(HardwareGuardStatus.warning),
          const SizedBox(width: 6),
          Text('${plan.warningCheckCount}',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(width: 12),
          const HardwareGuardPill(HardwareGuardStatus.blocked),
          const SizedBox(width: 6),
          Text('${plan.blockedCheckCount}',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ]),
        const SizedBox(height: 10),
        ...plan.guardChecks.map((c) => _GuardCheckRow(check: c)),
      ]),
    );
  }
}

class _GuardCheckRow extends StatelessWidget {
  final HardwareGuardCheck check;
  const _GuardCheckRow({required this.check});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            HardwareGuardPill(check.status),
            const SizedBox(width: 8),
            Expanded(
              child: Text(check.title,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 2),
            child: Text(check.description, style: proSubtitle(size: 9)),
          ),
          if (check.recommendation != null)
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 1),
              child: Text('→ ${check.recommendation}',
                  style: proSubtitle(
                      size: 9, color: kProAmber.withValues(alpha: 0.7))),
            ),
        ]),
      );
}

class HardwareGuardPill extends StatelessWidget {
  final HardwareGuardStatus status;
  const HardwareGuardPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (status) {
      HardwareGuardStatus.pass => (kProGreen, kProGreen.withValues(alpha: 0.12)),
      HardwareGuardStatus.warning => (
          kProAmber,
          kProAmber.withValues(alpha: 0.12)
        ),
      HardwareGuardStatus.blocked => (
          const Color(0xFFEF4444),
          const Color(0xFFEF4444).withValues(alpha: 0.12)
        ),
      HardwareGuardStatus.notApplicable => (
          Colors.white24,
          Colors.white.withValues(alpha: 0.04)
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(status.label, style: TextStyle(fontSize: 8, color: color)),
    );
  }
}
