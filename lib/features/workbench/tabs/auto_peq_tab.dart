// Auto PEQ tab — entry point into the existing Guided AI deterministic pipeline.
//
// This tab performs NO acoustic computation and NO hardware deployment.
//
// An earlier revision of this tab drove a parallel AutoPeqEngine/AutoPeqPipeline
// that computed its own PEQ bands and wrote them straight to the transport via
// writePeqGain/writePeqFrequency/writePeqQ. That path bypassed every guard the
// tuning architecture is built on:
//
//   - CandidateGenerator only ever emits cuts (gainDb <= 0); the old engine
//     inverted dips into boosts of up to +12 dB and the pipeline clamped at
//     +/-20 dB before writing.
//   - CandidateSafetyPolicy.adau1701Icp5 (maxCutDb 6.0, gain envelope
//     -6.0..+3.0) and the noBoostGuard never ran.
//   - DspExportPackage, HardwareWritePlan, the capability/safety gate, the
//     user approval gate, ProHardwareWriteExecutor, the pre-apply rollback
//     snapshot, and CorrectionCycleEvaluator were all skipped.
//
// Both files are now deleted. The equivalent, guarded behaviour already exists
// end-to-end in ProGuidedAiController, surfaced by GuidedAiScreen (kTabGuidedAi).
// This tab therefore does one thing: check readiness and hand off, the same way
// Import tab does after parsing an FRD.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/orchestrator/pro_guided_ai_controller.dart'
    show ProGuidedAiController, FrdReadiness;
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/workbench_tab_provider.dart';
import '../../../shared/pro_widgets.dart';

class AutoPeqTab extends ConsumerWidget {
  final String projectId;
  const AutoPeqTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref
        .watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == projectId)
        .firstOrNull;

    // Gate on the exact same 4-channel readiness ProGuidedAiController.start()
    // enforces for a full-system apply — not "any single FRD parsed". Showing
    // a looser readiness here would send the user into Guided AI only to be
    // blocked there for a reason they were never told about.
    final readiness =
        project == null ? null : ProGuidedAiController.frdReadiness(project);
    final ready = readiness?.isFullyReady ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _HeaderCard(project: project),
        const SizedBox(height: 12),
        _ReadinessCard(readiness: readiness),
        const SizedBox(height: 12),
        _ActionCard(ready: ready),
      ]),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final ProProject? project;
  const _HeaderCard({required this.project});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_fix_high, color: kProAccent, size: 18),
          const SizedBox(width: 8),
          Text('Auto PEQ', style: proTitle(size: 15)),
          const Spacer(),
          if (project?.dspTarget != null)
            Text(project!.dspTarget, style: proSubtitle(size: 10)),
        ]),
        const SizedBox(height: 6),
        Text(
          '측정된 FRD를 기준으로 보정 후보를 생성하고, 안전 검증과 사용자 승인을 거쳐 '
          'DSP에 반영합니다.\n'
          '계산·안전·배포는 모두 Guided AI 파이프라인이 담당합니다 — 이 탭은 진입점입니다.',
          style: proSubtitle(size: 11),
        ),
      ]),
    );
  }
}

// ── Readiness ─────────────────────────────────────────────────────────────────

class _ReadinessCard extends StatelessWidget {
  final FrdReadiness? readiness;
  const _ReadinessCard({required this.readiness});

  @override
  Widget build(BuildContext context) {
    final r = readiness;
    final ready = r?.isFullyReady ?? false;
    final color = ready ? Colors.green : Colors.amber;
    final total = r?.requiredChannelIds.length ?? 4;
    final readyCount = r?.readyCount ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              r == null
                  ? '프로젝트를 먼저 선택하세요.'
                  : ready
                      ? '4채널 FRD 준비 완료 ($readyCount/$total) — 실행 가능.'
                      : '4채널 중 $readyCount/$total 준비됨 — 부족한 채널이 있습니다.',
              style: TextStyle(fontSize: 11, color: color, height: 1.4),
            ),
          ),
        ]),
        if (r != null && r.missingChannels.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final ch in r.missingChannels)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                const Icon(Icons.radio_button_unchecked,
                    size: 12, color: Colors.white24),
                const SizedBox(width: 8),
                Text(
                  '${ch.label} — FRD 없음',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ]),
            ),
          const SizedBox(height: 4),
          Text(
            'Import 탭에서 부족한 채널의 측정 파일을 불러오세요.',
            style: proSubtitle(size: 10),
          ),
        ],
      ]),
    );
  }
}

// ── Action ────────────────────────────────────────────────────────────────────

class _ActionCard extends ConsumerWidget {
  final bool ready;
  const _ActionCard({required this.ready});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          onPressed: ready
              ? () => ref.read(workbenchTabProvider.notifier).go(kTabGuidedAi)
              : null,
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('Guided AI에서 실행'),
          style: FilledButton.styleFrom(
            backgroundColor: kProAccent,
            disabledBackgroundColor: kProBorder,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        if (!ready) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(workbenchTabProvider.notifier).go(kTabImport),
            icon: const Icon(Icons.upload_file_outlined, size: 15),
            label: const Text('Import 탭으로 이동'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kProBorder),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          '승인 전에는 어떤 값도 하드웨어에 기록되지 않습니다.',
          style: proSubtitle(size: 10),
        ),
      ]),
    );
  }
}
