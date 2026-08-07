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

import '../../../core/deploy/pro_hardware_context_provider.dart';
import '../../../core/orchestrator/pro_guided_ai_controller.dart'
    show ProGuidedAiController, FrdReadiness;
import '../../../core/orchestrator/room_after_gate.dart';
import '../../../core/orchestrator/room_auto_peq.dart'
    show roomAutoPeqMinHz, roomAutoPeqMaxHz;
import '../../../core/orchestrator/room_before_pair_quality_gate.dart';
import '../../../core/orchestrator/room_quality_presentation.dart';
import '../../../core/pro_correction_cycle.dart' show CorrectionCycleDecision;
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/workbench_tab_provider.dart';
import '../../../shared/pro_widgets.dart';
import '../../mic/microphone_profile_manager_dialog.dart';
import 'room_auto_peq_controller.dart';
import 'room_measurement_controller.dart'
    show roomMeasurementControllerProvider;

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
        if (project != null) ...[
          const SizedBox(height: 20),
          _RoomAutoPeqCard(projectId: projectId, project: project),
        ],
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

// ── Room Auto PEQ ─────────────────────────────────────────────────────────────
//
// Independent readiness/candidate path for the Phase 2 Stereo Room flow —
// Before Left+Right = 2/2, entirely separate from the Factory 4-driver
// readiness above. Reuses the same CandidateGenerator/CandidateSafetyPolicy/
// approval gate/DspExportPackage/HardwareWritePlan pipeline
// (RoomAutoPeqController -> lib/core/orchestrator/room_auto_peq.dart), just
// called directly instead of through the 4-channel orchestrator plan. On
// approval this only persists the DspExportPackage into exportState and
// hands off to Deploy — the exact same HardwareApplyFlow gate the Factory
// path already uses performs the actual write, on a separate explicit user
// action there.

class _RoomAutoPeqCard extends ConsumerWidget {
  final String projectId;
  final ProProject project;
  const _RoomAutoPeqCard({required this.projectId, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(roomAutoPeqControllerProvider(projectId).notifier);
    final state = ref.watch(roomAutoPeqControllerProvider(projectId));
    final before = project.roomState.before;
    final roomReady = before.isComplete;

    // Phase 3-D3B — 2/2 completeness alone is no longer sufficient; the
    // Left/Right pair must also carry trustworthy, matching quality
    // provenance. Evaluated fresh here so the button state and generate()'s
    // own refusal can never disagree (same contract as the Capture gates).
    final qualityGate = ctrl.qualityGate;
    final generateEnabled = roomReady && qualityGate.canGenerate;

    // Worsened verdict lives on RoomMeasurementController's closed-loop
    // result, not here — cross-read it (and the shared hardware-result
    // provider) so a rollback CTA can appear without a second, duplicate
    // evaluation or state store.
    final loopResult = ref
        .watch(roomMeasurementControllerProvider(projectId))
        .closedLoopResult;
    final lastHardwareResult = ref.watch(lastHardwareWriteResultProvider);
    final worsened = loopResult?.decision == CorrectionCycleDecision.worsened;
    final rollbackGate = RoomAfterGate.evaluate(
      approvedPackageId: state.rollbackApprovedPackageId,
      lastResult: lastHardwareResult,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.speaker_group_outlined, color: kProAccent, size: 18),
          const SizedBox(width: 8),
          Text('Room Auto PEQ', style: proTitle(size: 15)),
        ]),
        const SizedBox(height: 6),
        Text(
          'Stereo Room 측정(Left/Right 전체 스피커)을 기준으로 Woofer PEQ만 '
          '저역(${roomAutoPeqMinHz.toStringAsFixed(0)}-${roomAutoPeqMaxHz.toStringAsFixed(0)} Hz) '
          '범위에서 cut-only 보정합니다. Tweeter, XO, phase, delay는 변경하지 않습니다.',
          style: proSubtitle(size: 11),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Icon(
            generateEnabled
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined,
            size: 14,
            color: generateEnabled ? kProGreen : kProAmber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              generateEnabled
                  ? kRoomBeforePairQualityReadyText
                  : (roomReady
                      ? roomBeforePairQualityBlockerText(qualityGate)
                      : 'Before Left+Right: ${before.readyCount}/2'),
              style: TextStyle(
                  fontSize: 11, color: generateEnabled ? kProGreen : kProAmber),
            ),
          ),
        ]),
        if (roomReady && !generateEnabled) ...[
          const SizedBox(height: 6),
          _RoomQualityRemediationButton(
              projectId: projectId, gate: qualityGate),
        ],
        const SizedBox(height: 10),
        if (state.phase == RoomAutoPeqPhase.idle) ...[
          FilledButton.icon(
            onPressed: generateEnabled ? ctrl.generate : null,
            icon: const Icon(Icons.auto_fix_high, size: 15),
            label: const Text('Room Auto PEQ 후보 생성'),
            style: FilledButton.styleFrom(
              backgroundColor: kProAccent,
              disabledBackgroundColor: kProBorder,
            ),
          ),
        ] else if (state.phase == RoomAutoPeqPhase.noChange) ...[
          const Text('보정할 내용이 없습니다 — Room 응답이 이미 목표 범위 내에 있습니다.',
              style: TextStyle(fontSize: 11, color: Colors.white54)),
        ] else if (state.phase == RoomAutoPeqPhase.confirmPending) ...[
          for (final c in state.candidates.where((c) => c.hasChange))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${c.side.label} → ${c.channelId}: ${c.applyResult.applied.length}개 밴드 '
                '(cut ${c.applyResult.applied.map((b) => b.gainDb.toStringAsFixed(1)).join(", ")} dB)',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: ctrl.cancel,
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kProBorder)),
                child: const Text('취소', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  final approved = await ctrl.approve();
                  if (approved) {
                    ref.read(workbenchTabProvider.notifier).go(kTabDeploy);
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: kProGreen),
                child: const Text('승인 — Deploy로 이동',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ]),
        ] else if (state.phase == RoomAutoPeqPhase.approved) ...[
          const Text('승인 완료 — Deploy 탭에서 하드웨어에 실제로 적용하세요.',
              style: TextStyle(fontSize: 11, color: kProGreen)),
        ],
        if (worsened) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: kProBorder),
          const SizedBox(height: 12),
          _RollbackSection(
            projectId: projectId,
            ctrl: ctrl,
            state: state,
            rollbackGate: rollbackGate,
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 8),
          Text(state.error!,
              style: const TextStyle(color: kProRed, fontSize: 11)),
        ],
        const SizedBox(height: 8),
        Text('승인 전에는 어떤 값도 하드웨어에 기록되지 않습니다.', style: proSubtitle(size: 10)),
      ]),
    );
  }
}

// ── Room quality gate remediation ────────────────────────────────────────────
//
// Typed dispatch only — no string matching, no new navigation system. Both
// targets already exist: the Measure tab (for missing/legacy quality) and
// the existing Microphone Profile Manager dialog (for calibration coverage
// problems). Left/Right identity mismatches have no single-CTA fix (only
// consistent re-measurement resolves them), so [roomBeforePairQualityRemediation]
// returns null there and this widget renders nothing.

class _RoomQualityRemediationButton extends ConsumerWidget {
  final String projectId;
  final RoomBeforePairQualityGateResult gate;
  const _RoomQualityRemediationButton(
      {required this.projectId, required this.gate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remediation = roomBeforePairQualityRemediation(gate);
    if (remediation == null) return const SizedBox.shrink();
    final label = switch (remediation) {
      RoomBeforePairQualityRemediationKind.goToMeasureTab => 'Measure 탭으로 이동',
      RoomBeforePairQualityRemediationKind.manageMicrophone => '마이크 관리',
    };
    return OutlinedButton(
      onPressed: () {
        switch (remediation) {
          case RoomBeforePairQualityRemediationKind.goToMeasureTab:
            ref.read(workbenchTabProvider.notifier).go(kTabMeasure);
          case RoomBeforePairQualityRemediationKind.manageMicrophone:
            showMicrophoneProfileManagerDialog(context, projectId: projectId);
        }
      },
      style:
          OutlinedButton.styleFrom(side: const BorderSide(color: kProBorder)),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

// ── Rollback (worsened verdict) ─────────────────────────────────────────────
//
// Shown only when the Room Closed Loop evaluated a `worsened` decision.
// requestRollback() builds a rollback DspExportPackage/HardwareWritePlan
// from RoomAutoPeqController's pre-apply snapshot (captured at the original
// approve() call) and routes it through the identical exportState -> Deploy
// -> HardwareApplyFlow path as a normal correction. No automatic write:
// completion is only reported once RoomAfterGate confirms the rollback
// package's own planId was actually DSP-readback-verified — never merely
// "approved" or "Deploy tab opened".

class _RollbackSection extends ConsumerWidget {
  final String projectId;
  final RoomAutoPeqController ctrl;
  final RoomAutoPeqState state;
  final RoomAfterGateResult rollbackGate;
  const _RollbackSection({
    required this.projectId,
    required this.ctrl,
    required this.state,
    required this.rollbackGate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.trending_down, size: 14, color: kProRed),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Closed Loop 판정: 악화(worsened) — 적용 전 상태로 되돌릴 수 있습니다.',
            style: TextStyle(fontSize: 11, color: kProRed),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      if (state.rollbackPhase == RoomRollbackPhase.none) ...[
        OutlinedButton.icon(
          onPressed: () async {
            final approved = await ctrl.requestRollback();
            if (approved) {
              ref.read(workbenchTabProvider.notifier).go(kTabDeploy);
            }
          },
          icon: const Icon(Icons.undo, size: 15),
          label: const Text('적용 전 상태로 되돌리기'),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: kProRed),
            foregroundColor: kProRed,
          ),
        ),
      ] else ...[
        Row(children: [
          Icon(
            rollbackGate.available
                ? Icons.check_circle_outline
                : Icons.hourglass_empty,
            size: 14,
            color: rollbackGate.available ? kProGreen : kProAmber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rollbackGate.available
                  ? '복구 완료 — 하드웨어가 적용 전 상태로 확인되었습니다.'
                  : (rollbackGate.blockedReason ?? 'Deploy 탭에서 승인 후 적용하세요.'),
              style: TextStyle(
                fontSize: 11,
                color: rollbackGate.available ? kProGreen : kProAmber,
              ),
            ),
          ),
        ]),
      ],
    ]);
  }
}
