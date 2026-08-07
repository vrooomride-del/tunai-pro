// ── TUNAI PRO Phase 3-E §4/§16 — A. Project Hero ───────────────────────────
//
// Answers ONE question: "what am I working on?" — identity, configuration,
// a single state line, and whole-stage progress. It deliberately does not
// answer "what next" (that is Continue Tuning), "where am I overall" (the
// Journey), or "what is ready" (System Readiness), so the four sections
// never repeat each other.
//
// All state comes from MeasurementWorkflowReadiness; only pure identity
// (speaker configuration, DSP target, last-worked-on) is read off the
// project itself.

import 'package:flutter/material.dart';

import '../../../core/pro_project.dart';
import '../../../core/workflow/measurement_workflow_presentation.dart';
import '../../../core/workflow/measurement_workflow_readiness.dart';
import '../../../shared/design/pro_tokens.dart';
import 'home_primitives.dart';

class ProjectHero extends StatelessWidget {
  final MeasurementWorkflowReadiness readiness;
  final ProProject? project;
  final VoidCallback onNewProject;
  final VoidCallback onOpenProject;
  final VoidCallback onOpenDemo;

  const ProjectHero({
    super.key,
    required this.readiness,
    required this.project,
    required this.onNewProject,
    required this.onOpenProject,
    required this.onOpenDemo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          ProSpacing.xxl, ProSpacing.xl, ProSpacing.xxl, ProSpacing.xl),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ProColors.border, width: 0.5)),
      ),
      child: readiness.hasProject && project != null
          ? _withProject(project!)
          : _empty(),
    );
  }

  Widget _empty() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Wordmark(),
          const SizedBox(height: ProSpacing.xl),
          const Text(
            '새 스피커 프로젝트를 시작하세요.',
            style: TextStyle(
              color: ProColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '측정부터 보정, 검증까지 단계별로 안내해 드립니다.',
            style: TextStyle(
                color: ProColors.textTertiary, fontSize: ProTypeScale.body),
          ),
          const SizedBox(height: ProSpacing.lg),
          Wrap(spacing: ProSpacing.sm, runSpacing: ProSpacing.sm, children: [
            HomePrimaryButton(label: '새 프로젝트', onTap: onNewProject),
            HomeSecondaryButton(label: '프로젝트 열기', onTap: onOpenProject),
            HomeSecondaryButton(label: '데모 살펴보기', onTap: onOpenDemo),
          ]),
        ],
      );

  Widget _withProject(ProProject p) {
    final progress = measurementWorkflowProgress(readiness);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Wordmark(),
      const SizedBox(height: ProSpacing.xl),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              p.name,
              style: const TextStyle(
                color: ProColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              '${p.channelConfig} · ${p.dspTarget}',
              style: const TextStyle(
                  color: ProColors.textTertiary,
                  fontSize: ProTypeScale.secondary,
                  letterSpacing: 0.4),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: ProSpacing.lg),
        _ProgressBadge(completed: progress.completed, total: progress.total),
      ]),
      const SizedBox(height: ProSpacing.md),
      Text(
        _stateLine(),
        style: const TextStyle(
            color: ProColors.textSecondary, fontSize: ProTypeScale.body),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ]);
  }

  /// One sentence describing where the project stands — never a second CTA,
  /// and never the same words the Continue card uses.
  String _stateLine() => switch (readiness.nextRecommendedAction) {
        MeasurementWorkflowAction.complete => '모든 단계가 완료되었습니다.',
        MeasurementWorkflowAction.reviewClosedLoop => '보정 결과를 확인할 수 있습니다.',
        _ => readiness.primaryBlocker == null
            ? '튜닝을 이어서 진행할 수 있습니다.'
            : measurementWorkflowBlockerText(readiness.primaryBlocker!),
      };
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Text(
          'TUNAI PRO',
          style: TextStyle(
            color: ProColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w300,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(width: ProSpacing.md),
        Text(
          'Acoustic Intelligence Workstation',
          style: TextStyle(
            color: ProColors.accent.withValues(alpha: 0.7),
            fontSize: ProTypeScale.label,
            letterSpacing: 0.6,
          ),
        ),
      ]);
}

class _ProgressBadge extends StatelessWidget {
  final int completed;
  final int total;
  const _ProgressBadge({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '$completed',
              style: const TextStyle(
                color: ProColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w300,
              ),
            ),
            Text(
              ' / $total',
              style: const TextStyle(
                color: ProColors.textTertiary,
                fontSize: 15,
                fontWeight: FontWeight.w300,
              ),
            ),
          ]),
          const Text(
            '단계 완료',
            style: TextStyle(
                color: ProColors.textTertiary, fontSize: ProTypeScale.label),
          ),
        ],
      );
}
