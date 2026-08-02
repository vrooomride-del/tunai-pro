// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-2H).
//
// UI extraction only: this is the same widget that lived as the private
// `_WritePlanPanel` class (with its private `_StepRow` row helper) inside
// hardware_tab.dart, moved verbatim with no change to the "DRY RUN ONLY"
// badge, the column headers, the per-step order/logicalName/addressHex/
// addressVerified/status/warning rendering, or the empty-steps message.
// This widget only renders an already-computed `HardwareWritePlan` — it
// does not generate the write plan, judge validation/guard state, decide
// addresses, build commands, or touch providers/controllers/executors/
// BLE/transport/deploy. `_StepRow` stays private to this file — it is not
// promoted to public. `HardwareGuardPill` continues to be reused exactly
// as before, imported from the already-extracted
// `hardware_guard_checklist_card.dart` (not duplicated or reimplemented).

import 'package:flutter/material.dart';

import '../../../core/pro_hardware_connection_data.dart';
import '../../../shared/pro_widgets.dart';
import 'hardware_guard_checklist_card.dart';

class HardwareWritePlanCard extends StatelessWidget {
  final HardwareWritePlan plan;
  const HardwareWritePlanCard({super.key, required this.plan});

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: kProAmber.withValues(alpha: 0.12),
              border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('DRY RUN ONLY',
                style: TextStyle(fontSize: 8, color: kProAmber,
                    fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          ),
          const SizedBox(width: 10),
          Text(plan.summary, style: proSubtitle(size: 9)),
        ]),
        const SizedBox(height: 10),
        if (plan.steps.isEmpty)
          Text('No write steps generated.', style: proSubtitle())
        else ...[
          // Column headers
          Row(children: [
            SizedBox(width: 24, child: Text('#', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            Expanded(flex: 3, child: Text('LOGICAL NAME', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            SizedBox(width: 60, child: Text('ADDRESS', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            SizedBox(width: 50, child: Text('VERIFIED', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            SizedBox(width: 55, child: Text('STATUS', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
          ]),
          const SizedBox(height: 6),
          const Divider(color: kProBorder, height: 1),
          const SizedBox(height: 4),
          ...plan.steps.map((s) => _StepRow(step: s)),
        ],
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  final HardwareWritePlanStep step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 24,
          child: Text('${step.order + 1}',
              style: proSubtitle(size: 9)),
        ),
        Expanded(
          flex: 3,
          child: Text(step.logicalName,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ),
        SizedBox(
          width: 60,
          child: Text(step.addressHex ?? '—',
              style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: step.addressHex != null
                      ? const Color(0xFF4A9EFF)
                      : Colors.white24)),
        ),
        SizedBox(
          width: 50,
          child: Text(step.addressVerified ? 'Yes' : 'No',
              style: TextStyle(
                  fontSize: 9,
                  color: step.addressVerified ? kProGreen : Colors.white38)),
        ),
        SizedBox(width: 55, child: HardwareGuardPill(step.status)),
      ]),
      if (step.warning != null)
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 1),
          child: Text(step.warning!,
              style: proSubtitle(size: 9, color: kProAmber.withValues(alpha: 0.7))),
        ),
    ]),
  );
}
