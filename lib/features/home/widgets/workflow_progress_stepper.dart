// TUNAI PRO UI v2 — Workspace Home workflow progress stepper (Phase 4-A-1).
//
// Answers "what stage am I in?" using the existing, public `ProfileStatus`
// enum (lib/core/pro_project.dart) and its `isAtLeast()` ordering helper —
// no new enum, no new business logic. Reads
// ref.watch(proProjectStoreProvider).currentProject (the existing getter)
// and renders a plain dot-and-line stepper, not a boxed dashboard widget:
// five small dots joined by a line, with a plain-language caption under
// each (never the raw enum name). When there is no current project every
// step renders inactive — no fabricated progress.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../shared/design/pro_tokens.dart';

class WorkflowProgressStepper extends ConsumerWidget {
  const WorkflowProgressStepper({super.key});

  static const _captions = {
    ProfileStatus.draft: 'Set Up',
    ProfileStatus.measured: 'Measure',
    ProfileStatus.tuned: 'Tune',
    ProfileStatus.verified: 'Verify',
    ProfileStatus.deployed: 'Deploy',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(proProjectStoreProvider).currentProject;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ProSpacing.xxl),
      child: Row(
        children: [
          for (final entry in _captions.entries) ...[
            _Step(
              caption: entry.value,
              active: project != null && project.profileStatus.isAtLeast(entry.key),
              current: project?.profileStatus == entry.key,
            ),
            if (entry.key != ProfileStatus.deployed)
              Expanded(
                child: Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: ProSpacing.xs),
                  color: project != null && project.profileStatus.isAtLeast(entry.key)
                      ? ProColors.accent.withValues(alpha: 0.4)
                      : ProColors.border,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String caption;
  final bool active;
  final bool current;
  const _Step({required this.caption, required this.active, required this.current});

  @override
  Widget build(BuildContext context) {
    final color = active ? ProColors.accent : ProColors.textTertiary.withValues(alpha: 0.5);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: current ? 10 : 8,
        height: current ? 10 : 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color : Colors.transparent,
          border: Border.all(color: color, width: 1.4),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        caption,
        style: TextStyle(
          color: active ? ProColors.textSecondary : ProColors.textTertiary.withValues(alpha: 0.6),
          fontSize: ProTypeScale.label,
          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    ]);
  }
}
