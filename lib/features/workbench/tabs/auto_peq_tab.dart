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

    final frdCount = project?.acousticState.parsedFrdCount ?? 0;
    final ready = frdCount > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _HeaderCard(project: project),
        const SizedBox(height: 12),
        _ReadinessCard(frdCount: frdCount),
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
  final int frdCount;
  const _ReadinessCard({required this.frdCount});

  @override
  Widget build(BuildContext context) {
    final ready = frdCount > 0;
    final color = ready ? Colors.green : Colors.amber;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(
          ready ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            ready
                ? '측정 데이터 $frdCount개 — 실행 준비됨.'
                : 'FRD 파일이 없습니다. Import 탭에서 측정 파일을 먼저 불러오세요.',
            style: TextStyle(fontSize: 11, color: color, height: 1.4),
          ),
        ),
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
