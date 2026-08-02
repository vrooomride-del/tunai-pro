// TUNAI PRO UI v2 — Workspace Home current project status (Phase 4-A-1).
//
// Answers "what project am I working on?" and "what should I do next?".
// Reads ref.watch(proProjectStoreProvider).currentProject (the existing
// getter, no new lookup logic). Deliberately orientation-level only: shows
// project identity, plain-language stage, and a single next-step sentence
// + Continue button — no DSP target, sample rate, or channel-config
// specs (those stay inside Workbench/Hardware). Safety status is shown
// only when it needs attention (warning/blocked), never as a routine
// badge. One card, one focal action — not a stack of bordered chips.
//
// `onContinue`/`onNewProject`/`onOpenDemo` are supplied by WorkspaceHome and
// wrap its existing `_openWorkbench`/`_showNewProjectDialog`/
// `_openDemoProject` methods verbatim — this widget never navigates itself.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../shared/design/pro_tokens.dart';

class CurrentProjectStatusCard extends ConsumerWidget {
  final VoidCallback onContinue;
  final VoidCallback onNewProject;
  final VoidCallback onOpenDemo;

  const CurrentProjectStatusCard({
    super.key,
    required this.onContinue,
    required this.onNewProject,
    required this.onOpenDemo,
  });

  static const _stageNoun = {
    ProfileStatus.draft: 'Setup',
    ProfileStatus.measured: 'Measurement',
    ProfileStatus.tuned: 'Tuning',
    ProfileStatus.verified: 'Verification',
    ProfileStatus.deployed: 'Deployment',
  };

  static const _nextStep = {
    ProfileStatus.draft: ('Ready to take your first measurements.', 'Start Measuring'),
    ProfileStatus.measured: ('Your measurements are in — time to tune.', 'Continue Tuning'),
    ProfileStatus.tuned: ('Verify your tuning is safe before deploying.', 'Continue to Verify'),
    ProfileStatus.verified: ("You're ready to deploy this profile.", 'Continue to Deploy'),
    ProfileStatus.deployed: ('This profile is deployed. Review or refine it anytime.', 'Open Project'),
  };

  String _relativeTime(DateTime updatedAt) {
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${updatedAt.year}.${updatedAt.month.toString().padLeft(2, '0')}.${updatedAt.day.toString().padLeft(2, '0')}';
  }

  Color _safetyColor(SafetyStatus s) => switch (s) {
    SafetyStatus.notVerified => ProColors.textTertiary,
    SafetyStatus.verified => ProColors.green,
    SafetyStatus.warning => ProColors.amber,
    SafetyStatus.blocked => ProColors.red,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(proProjectStoreProvider).currentProject;

    return Container(
      margin: const EdgeInsets.fromLTRB(ProSpacing.xxl, 0, ProSpacing.xxl, 0),
      padding: const EdgeInsets.all(ProSpacing.xl),
      decoration: BoxDecoration(
        color: ProColors.surface,
        border: Border.all(color: ProColors.border),
        borderRadius: ProRadius.largeAll,
      ),
      child: project == null ? _buildEmpty(context) : _buildProject(context, project),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'No project open yet',
        style: TextStyle(
          color: ProColors.textPrimary,
          fontSize: ProTypeScale.body,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Start a new tuning project, or explore a preloaded demo.',
        style: TextStyle(color: ProColors.textTertiary, fontSize: ProTypeScale.secondary),
      ),
      const SizedBox(height: ProSpacing.lg),
      Row(children: [
        _FilledAction(label: 'New Project', onTap: onNewProject),
        const SizedBox(width: ProSpacing.sm),
        _OutlineAction(label: 'Try the Demo', onTap: onOpenDemo),
      ]),
    ]);
  }

  Widget _buildProject(BuildContext context, ProProject project) {
    final (nextStepLine, continueLabel) = _nextStep[project.profileStatus]!;
    final showSafetyNote = project.safetyStatus == SafetyStatus.warning ||
        project.safetyStatus == SafetyStatus.blocked;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        project.name,
        style: const TextStyle(
          color: ProColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 4),
      Text(
        '${project.speakerModel} · ${project.roomName} · Last worked on ${_relativeTime(project.updatedAt)}',
        style: const TextStyle(color: ProColors.textTertiary, fontSize: ProTypeScale.secondary),
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: ProSpacing.md),
      Text(
        "You're in the ${_stageNoun[project.profileStatus]} stage.",
        style: const TextStyle(color: ProColors.textSecondary, fontSize: ProTypeScale.body),
      ),
      const SizedBox(height: 2),
      Text(
        nextStepLine,
        style: const TextStyle(color: ProColors.textTertiary, fontSize: ProTypeScale.secondary),
      ),
      if (showSafetyNote) ...[
        const SizedBox(height: ProSpacing.sm),
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: _safetyColor(project.safetyStatus)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              project.safetyStatus == SafetyStatus.blocked
                  ? 'Needs a safety check before you can deploy.'
                  : 'A safety warning needs your attention.',
              style: TextStyle(color: _safetyColor(project.safetyStatus), fontSize: ProTypeScale.secondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ],
      const SizedBox(height: ProSpacing.lg),
      _FilledAction(label: continueLabel, onTap: onContinue),
    ]);
  }
}

class _FilledAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FilledAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: ProSpacing.lg, vertical: ProSpacing.sm + 2),
      decoration: BoxDecoration(
        color: ProColors.accent.withValues(alpha: 0.15),
        border: Border.all(color: ProColors.accent.withValues(alpha: 0.5)),
        borderRadius: ProRadius.smallAll,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: const TextStyle(
                color: ProColors.accent, fontSize: ProTypeScale.secondary, fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        const Icon(Icons.arrow_forward, size: 13, color: ProColors.accent),
      ]),
    ),
  );
}

class _OutlineAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: ProSpacing.lg, vertical: ProSpacing.sm + 2),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: ProColors.border),
        borderRadius: ProRadius.smallAll,
      ),
      child: Text(label,
          style: const TextStyle(color: ProColors.textSecondary, fontSize: ProTypeScale.secondary)),
    ),
  );
}
