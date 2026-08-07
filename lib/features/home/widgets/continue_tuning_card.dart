// ── TUNAI PRO Phase 3-E §5/§6 — B. Continue Tuning ─────────────────────────
//
// The most important card on Home, and the only place a primary CTA appears
// while a project is open.
//
// It renders MeasurementWorkflowReadiness.nextRecommendedAction verbatim —
// no priority is recalculated here, no condition is re-derived, and no
// second primary action is offered. Copy comes from
// measurement_workflow_presentation.dart; routing from home_navigation.dart.

import 'package:flutter/material.dart';

import '../../../core/workflow/measurement_workflow_presentation.dart';
import '../../../core/workflow/measurement_workflow_readiness.dart';
import '../../../shared/design/pro_tokens.dart';
import 'home_primitives.dart';

class ContinueTuningCard extends StatelessWidget {
  final MeasurementWorkflowReadiness readiness;

  /// Invoked with the action the card is showing. The caller performs the
  /// typed dispatch — this widget never navigates itself.
  final void Function(MeasurementWorkflowAction) onAction;

  const ContinueTuningCard({
    super.key,
    required this.readiness,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final action = readiness.nextRecommendedAction;
    final done = action == MeasurementWorkflowAction.complete;
    final blocker = readiness.primaryBlocker;

    return HomePanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        HomeSectionLabel(done ? '완료' : '다음 단계'),
        const SizedBox(height: ProSpacing.md),
        Text(
          measurementWorkflowActionTitle(action),
          style: const TextStyle(
            color: ProColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: ProSpacing.sm),
        Text(
          measurementWorkflowActionDescription(action),
          style: const TextStyle(
              color: ProColors.textTertiary,
              fontSize: ProTypeScale.body,
              height: 1.5),
        ),

        // §9 — the Deploy step surfaces a hardware blocker here, on the step
        // where it first matters, rather than by inserting a "connect
        // hardware" stage ahead of measurement.
        if (measurementWorkflowHardwareBlockerText(readiness) != null) ...[
          const SizedBox(height: ProSpacing.md),
          _Note(
            icon: Icons.memory_outlined,
            color: ProColors.amber,
            text: measurementWorkflowHardwareBlockerText(readiness)!,
          ),
        ],

        // Why this is next — shown only when something is actually blocking,
        // so a healthy project stays uncluttered.
        if (blocker != null) ...[
          const SizedBox(height: ProSpacing.md),
          _Note(
            icon: Icons.info_outline,
            color: ProColors.textSecondary,
            text: measurementWorkflowBlockerText(blocker),
          ),
        ],

        for (final w in readiness.warnings) ...[
          const SizedBox(height: ProSpacing.sm),
          _Note(
            icon: Icons.error_outline,
            color: ProColors.amber,
            text: measurementWorkflowWarningText(w),
          ),
        ],

        const SizedBox(height: ProSpacing.xl),
        // Exactly one primary action. Always.
        HomePrimaryButton(
          label: measurementWorkflowActionTitle(action),
          icon: done ? Icons.summarize_outlined : Icons.arrow_forward,
          large: true,
          onTap: () => onAction(action),
        ),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Note({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 13, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: ProTypeScale.secondary),
          ),
        ),
      ]);
}
