// Guided AI Flow screen.
//
// Connects user intent input to the Cloud Orchestrator → Local Orchestrator
// pipeline. Never displays a DSP number: only prose explanations, step labels,
// and improvement verdicts are shown.
//
// Existing AiScreen (aiTunePro path) is NOT modified by this file.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustic/acoustic_apply_engine.dart';
import '../../core/acoustic/closed_loop_evaluator.dart';
import '../../core/frd_parser.dart';
import '../../core/orchestrator/guided_ai_project_apply.dart';
import '../../core/orchestrator/pro_guided_ai_controller.dart';
import '../../core/orchestrator/pro_guided_ai_state.dart';
import '../../core/orchestrator/pro_local_orchestrator_session.dart';
import '../../core/orchestrator/pro_orchestrator_plan.dart';
import '../../core/orchestrator/pro_orchestrator_types.dart';
import '../../core/pro_correction_cycle.dart';
import '../../core/pro_project_store.dart';
import '../../core/spectrum_snapshot.dart';
import '../mic/mic_measurement_controller.dart';

class GuidedAiScreen extends ConsumerStatefulWidget {
  final String projectId;
  const GuidedAiScreen({super.key, required this.projectId});

  @override
  ConsumerState<GuidedAiScreen> createState() => _GuidedAiScreenState();
}

class _GuidedAiScreenState extends ConsumerState<GuidedAiScreen> {
  final _goalCtrl = TextEditingController();

  @override
  void dispose() {
    _goalCtrl.dispose();
    super.dispose();
  }

  Future<void> _importAfterFrd() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['frd', 'txt'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.path == null) return;

    final content = await File(file.path!).readAsString();
    final afterPoints = FrdParser.parseFrd(content);
    if (afterPoints.isEmpty) return;

    final aiState = ref.read(guidedAiProvider);
    if (aiState is! ProGuidedAiCompleted) return;
    if (aiState.loopPhase != ProClosedLoopPhase.awaitingAfterFrd) return;

    final project = ref
        .read(proProjectStoreProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;
    if (project == null) return;

    final driverCh = project.acousticState.driverChannels.firstOrNull;
    final beforePoints = driverCh?.frdData?.points
            .where((p) => p.magnitudeDb != null)
            .map((p) => FrdPoint(frequency: p.frequencyHz, spl: p.magnitudeDb!))
            .toList() ??
        <FrdPoint>[];

    final peqChannel = project.tuningState.peqChannels.firstOrNull;
    if (peqChannel == null) return;

    final beforeRef = aiState.beforeMeasurementRef ??
        'before_${widget.projectId}_${DateTime.now().millisecondsSinceEpoch}';
    final afterRef =
        'after_${widget.projectId}_${DateTime.now().millisecondsSinceEpoch}';

    final cycle = ref.read(guidedAiProvider.notifier).submitAfterFrd(
          projectId: widget.projectId,
          channelId: peqChannel.channelId,
          beforeFrdPoints: beforePoints,
          beforeMeasurementRef: beforeRef,
          afterFrdPoints: afterPoints,
          afterMeasurementRef: afterRef,
          afterMeasurementFileName: file.name,
          peqSnapshot: peqChannel,
          cycleNumber: project.correctionCycles.length + 1,
        );
    if (cycle == null) return;

    await ref
        .read(proProjectStoreProvider.notifier)
        .addCorrectionCycle(widget.projectId, cycle);
  }

  @override
  Widget build(BuildContext context) {
    // When a mic measurement completes while awaiting closed-loop after data,
    // convert the raw frequency response to FrequencyBin and forward to the
    // AI controller. The map keys ('frequency', 'db') come from MicMeasurementController.
    ref.listen(micMeasurementProvider, (prev, next) {
      if (next.status != MeasurementStatus.done) return;
      final aiState = ref.read(guidedAiProvider);
      if (aiState is! ProGuidedAiCompleted) return;
      if (aiState.loopPhase != ProClosedLoopPhase.awaitingMeasurement) return;
      final bins = [
        for (final m in next.frequencyResponse)
          if (m['frequency'] != null && m['db'] != null)
            FrequencyBin(frequency: m['frequency']!, magnitude: m['db']!),
      ];
      ref.read(guidedAiProvider.notifier).submitAfterMeasurementFromBins(
            afterBins: bins,
            afterRef: 'mic_after_${DateTime.now().millisecondsSinceEpoch}',
          );
    });

    // Resolve the project the same way ProjectStatusBar does: look up by
    // widget.projectId in the projects list. This avoids depending on
    // currentProjectId, which may not be in sync when opening via the
    // Demo Workstation or New Project paths.
    final aiState = ref.watch(guidedAiProvider);
    final project = ref
        .watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'GUIDED AI',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 6),
              ),
              const SizedBox(height: 4),
              const Text(
                '분석 · 계획 · 후보 생성',
                style: TextStyle(
                    color: Colors.white38, fontSize: 12, letterSpacing: 1),
              ),
              const SizedBox(height: 32),

              // ── Input ──────────────────────────────────────────────────────
              if (aiState is ProGuidedAiIdle) ...[
                const Text('목표 설명',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 12, letterSpacing: 2)),
                const SizedBox(height: 8),
                TextField(
                  controller: _goalCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '예) 저음이 너무 부밍하고 고음이 날카롭게 들립니다.',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: project == null
                        ? null
                        : () {
                            ref.read(guidedAiProvider.notifier).start(
                                  project: project,
                                  userGoal: _goalCtrl.text,
                                  onApply: (pid, applyResult) async {
                                    // Read the latest project at apply time —
                                    // not the stale closure captured at
                                    // button-press time.
                                    final latestProject = ref
                                        .read(proProjectStoreProvider)
                                        .projects
                                        .where((p) => p.id == pid)
                                        .firstOrNull;
                                    final op = GuidedAiProjectApply.apply(
                                      projectId: pid,
                                      applyResult: applyResult,
                                      latestProject: latestProject,
                                    );
                                    if (!op.wrote ||
                                        op.updatedProject == null) {
                                      return;
                                    }
                                    await ref
                                        .read(proProjectStoreProvider.notifier)
                                        .updateTuningState(
                                            pid,
                                            op.updatedProject!.tuningState);
                                  },
                                );
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A2A),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('AI 분석 시작',
                        style: TextStyle(
                            color: Colors.white,
                            letterSpacing: 2,
                            fontSize: 13)),
                  ),
                ),
                if (project == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('프로젝트를 먼저 선택하세요.',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
              ],

              // ── Cloud calling ──────────────────────────────────────────────
              if (aiState is ProGuidedAiCloudCalling)
                const _StatusCard(
                    icon: Icons.cloud_outlined,
                    label: 'AI 플랜 요청 중…',
                    color: Colors.white38),

              // ── Executing ─────────────────────────────────────────────────
              if (aiState is ProGuidedAiExecuting) ...[
                _ExplanationCard(explanation: aiState.explanation.summary),
                const SizedBox(height: 16),
                _StepList(
                  steps: aiState.plan.steps,
                  completedRecords: aiState.completedSteps,
                  currentToolId: aiState.currentToolId,
                ),
              ],

              // ── Confirmation gate ──────────────────────────────────────────
              if (aiState is ProGuidedAiConfirmPending) ...[
                _ExplanationCard(explanation: aiState.explanation.summary),
                const SizedBox(height: 16),
                _StepList(
                  steps: aiState.plan.steps,
                  completedRecords: aiState.completedSteps,
                  currentToolId: aiState.request.toolId,
                ),
                const SizedBox(height: 24),
                _ConfirmationCard(
                  request: aiState.request,
                  onConfirm: () => ref
                      .read(guidedAiProvider.notifier)
                      .confirm(aiState.request.stepId),
                  onCancel: () => ref
                      .read(guidedAiProvider.notifier)
                      .cancel(aiState.request.stepId),
                ),
              ],

              // ── Completed ─────────────────────────────────────────────────
              if (aiState is ProGuidedAiCompleted) ...[
                _ExplanationCard(explanation: aiState.explanation.summary),
                const SizedBox(height: 16),
                _StepList(
                  steps: aiState.outcome.stepRecords
                      .map((r) => ProOrchestratorStep(
                            stepId: r.stepId,
                            toolId: r.toolId,
                            objective: r.summary,
                            inputRefs: const [],
                            outputRef: r.outputRef,
                            requiresUserConfirmation: false,
                          ))
                      .toList(),
                  completedRecords: aiState.outcome.stepRecords,
                ),
                const SizedBox(height: 16),
                if (aiState.applyResult != null)
                  _ApplyResultCard(result: aiState.applyResult!),
                if (aiState.loopPhase != null) ...[
                  const SizedBox(height: 12),
                  _LoopPhaseCard(phase: aiState.loopPhase!),
                ],
                // "Add After Measurement" — shown when apply succeeded and no
                // after FRD cycle is in progress or complete yet.
                if (aiState.loopPhase == ProClosedLoopPhase.awaitingMeasurement &&
                    aiState.applyResult?.status == TuningApplyStatus.ok) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(guidedAiProvider.notifier).enterAwaitingAfterFrd(),
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('After 측정 FRD 불러오기'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
                // FRD file import — shown when awaitingAfterFrd.
                if (aiState.loopPhase == ProClosedLoopPhase.awaitingAfterFrd) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _importAfterFrd,
                      icon: const Icon(Icons.folder_open_outlined, size: 16),
                      label: const Text('FRD 파일 선택'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E2A3A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
                // Cycle evaluation result.
                if (aiState.loopPhase == ProClosedLoopPhase.cycleComplete &&
                    aiState.completedCycle != null) ...[
                  const SizedBox(height: 12),
                  _CycleDecisionCard(
                    cycle: aiState.completedCycle!,
                    onContinue: () =>
                        ref.read(guidedAiProvider.notifier).reset(),
                    onComplete: () =>
                        ref.read(guidedAiProvider.notifier).reset(),
                  ),
                ],
                if (aiState.loopVerdict != null) ...[
                  const SizedBox(height: 12),
                  _VerdictCard(verdict: aiState.loopVerdict!),
                ],
                const SizedBox(height: 24),
                _ResetButton(
                    onReset: () => ref.read(guidedAiProvider.notifier).reset()),
              ],

              // ── Failed ────────────────────────────────────────────────────
              if (aiState is ProGuidedAiFailed) ...[
                _StatusCard(
                    icon: Icons.error_outline,
                    label: aiState.message,
                    color: Colors.redAccent),
                const SizedBox(height: 24),
                _ResetButton(
                    onReset: () => ref.read(guidedAiProvider.notifier).reset()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusCard(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label, style: TextStyle(color: color, fontSize: 13))),
        ],
      );
}

class _ExplanationCard extends StatelessWidget {
  final String explanation;
  const _ExplanationCard({required this.explanation});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(explanation,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.6)),
      );
}

class _StepList extends StatelessWidget {
  final List<ProOrchestratorStep> steps;
  final List<ProStepExecutionRecord> completedRecords;
  final ProOrchestratorToolId? currentToolId;

  const _StepList({
    required this.steps,
    required this.completedRecords,
    this.currentToolId,
  });

  @override
  Widget build(BuildContext context) {
    final doneIds = {for (final r in completedRecords) r.stepId};
    final failedIds = {
      for (final r in completedRecords)
        if (r.status == ProStepStatus.failed) r.stepId
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('STEPS',
            style: TextStyle(
                color: Colors.white38, fontSize: 11, letterSpacing: 2)),
        const SizedBox(height: 8),
        for (final step in steps)
          _StepRow(
            step: step,
            isDone: doneIds.contains(step.stepId),
            isFailed: failedIds.contains(step.stepId),
            isRunning: currentToolId == step.toolId,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final ProOrchestratorStep step;
  final bool isDone;
  final bool isFailed;
  final bool isRunning;

  const _StepRow({
    required this.step,
    required this.isDone,
    required this.isFailed,
    required this.isRunning,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;

    if (isFailed) {
      color = Colors.redAccent;
      icon = Icons.close;
    } else if (isDone) {
      color = const Color(0xFF4CAF50);
      icon = Icons.check;
    } else if (isRunning) {
      color = Colors.white70;
      icon = Icons.play_arrow;
    } else {
      color = Colors.white24;
      icon = Icons.circle_outlined;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.objective.isNotEmpty ? step.objective : step.toolId.name,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  final ProUserConfirmationRequest request;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _ConfirmationCard({
    required this.request,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('승인 필요',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2,
                    fontSize: 12)),
            const SizedBox(height: 8),
            Text(request.explanation.summary,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white38,
                      side: const BorderSide(color: Colors.white12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('계속'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _VerdictCard extends StatelessWidget {
  final ImprovementVerdict verdict;
  const _VerdictCard({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (verdict) {
      ImprovementVerdict.improved => ('개선됨', const Color(0xFF4CAF50)),
      ImprovementVerdict.neutral => ('변화 없음', Colors.white38),
      ImprovementVerdict.regressed => ('성능 저하', Colors.redAccent),
      ImprovementVerdict.inconclusive => ('결과 불명확', Colors.white54),
    };

    return Row(
      children: [
        Icon(Icons.analytics_outlined, color: color, size: 16),
        const SizedBox(width: 8),
        Text('Closed Loop: $label',
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _LoopPhaseCard extends StatelessWidget {
  final ProClosedLoopPhase phase;
  const _LoopPhaseCard({required this.phase});

  @override
  Widget build(BuildContext context) => switch (phase) {
        ProClosedLoopPhase.awaitingMeasurement =>
          const _AwaitingMeasurementCard(),
        ProClosedLoopPhase.awaitingAfterFrd => const _StatusCard(
            icon: Icons.upload_file_outlined,
            label: 'After FRD 파일 대기 중',
            color: Colors.white54,
          ),
        ProClosedLoopPhase.evaluated => const Row(
            children: [
              Icon(Icons.loop, color: Color(0xFF4CAF50), size: 16),
              SizedBox(width: 8),
              Text('Closed Loop 평가 완료',
                  style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ProClosedLoopPhase.cycleComplete => const _StatusCard(
            icon: Icons.check_circle_outline,
            label: '보정 사이클 완료',
            color: Color(0xFF4CAF50),
          ),
      };
}

class _AwaitingMeasurementCard extends StatelessWidget {
  const _AwaitingMeasurementCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: Color(0xFF4CAF50), size: 15),
                SizedBox(width: 8),
                Text(
                  '스피커 적용 완료',
                  style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sensors, color: Colors.white38, size: 14),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '개선 확인을 위한 재측정을 기다리는 중',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.only(left: 22),
              child: Text(
                '측정 앱에서 스피커를 다시 측정한 후 결과를 불러오세요.',
                style:
                    TextStyle(color: Colors.white30, fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _ApplyResultCard extends StatelessWidget {
  final TuningApplyResult result;
  const _ApplyResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (result.status) {
      TuningApplyStatus.ok => ('적용 완료', const Color(0xFF4CAF50)),
      TuningApplyStatus.partiallyApplied => ('일부 적용', Colors.amber),
      TuningApplyStatus.noSlotAvailable => ('슬롯 부족', Colors.redAccent),
      TuningApplyStatus.notPermitted => ('적용 차단', Colors.redAccent),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$label · ${result.applied.length}밴드 적용'
              '${result.skipped.isNotEmpty ? ' / ${result.skipped.length}밴드 스킵' : ''}',
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleDecisionCard extends StatelessWidget {
  final CorrectionCycle cycle;
  final VoidCallback onContinue;
  final VoidCallback onComplete;

  const _CycleDecisionCard({
    required this.cycle,
    required this.onContinue,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final decision = cycle.decision;
    final metrics = cycle.metrics;

    final (decisionLabel, decisionColor, icon) = switch (decision) {
      CorrectionCycleDecision.improvedAndComplete => (
          '개선 완료',
          const Color(0xFF4CAF50),
          Icons.check_circle_outline,
        ),
      CorrectionCycleDecision.improvedNeedsAnotherCycle => (
          '개선됨 — 추가 보정 권장',
          Colors.amber,
          Icons.refresh,
        ),
      CorrectionCycleDecision.noMeaningfulImprovement => (
          '의미 있는 개선 없음',
          Colors.white54,
          Icons.remove_circle_outline,
        ),
      CorrectionCycleDecision.worsened => (
          '성능 저하 감지',
          Colors.redAccent,
          Icons.warning_amber_outlined,
        ),
      CorrectionCycleDecision.insufficientEvidence => (
          '데이터 부족',
          Colors.white38,
          Icons.help_outline,
        ),
      CorrectionCycleDecision.wrongProjectOrChannel => (
          '프로젝트/채널 불일치',
          Colors.redAccent,
          Icons.error_outline,
        ),
      null => ('평가 미완료', Colors.white24, Icons.hourglass_empty),
    };

    final canContinue = decision == CorrectionCycleDecision.improvedNeedsAnotherCycle;
    final isTerminal = decision == CorrectionCycleDecision.improvedAndComplete ||
        decision == CorrectionCycleDecision.worsened ||
        decision == CorrectionCycleDecision.wrongProjectOrChannel;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: decisionColor.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: decisionColor, size: 16),
              const SizedBox(width: 8),
              Text(decisionLabel,
                  style: TextStyle(
                      color: decisionColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          if (metrics != null) ...[
            const SizedBox(height: 12),
            _MetricRow(
              label: 'MAR Before',
              value: '${metrics.meanAbsResidualBefore.toStringAsFixed(2)} dB',
            ),
            _MetricRow(
              label: 'MAR After',
              value: '${metrics.meanAbsResidualAfter.toStringAsFixed(2)} dB',
              highlight: metrics.improvementDelta > 0,
            ),
            _MetricRow(
              label: '개선량',
              value: '${metrics.improvementDelta >= 0 ? '+' : ''}'
                  '${metrics.improvementDelta.toStringAsFixed(2)} dB',
              highlight: metrics.improvementDelta > 0,
            ),
            if (metrics.worsenedBandCount > 0)
              _MetricRow(
                label: '악화 밴드',
                value: '${metrics.worsenedBandCount}개',
                warn: true,
              ),
          ],
          if (cycle.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...cycle.reasons.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $r',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11, height: 1.4)),
              ),
            ),
          ],
          if (decision == CorrectionCycleDecision.worsened ||
              decision == CorrectionCycleDecision.wrongProjectOrChannel) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                decision == CorrectionCycleDecision.worsened
                    ? '이전 설정으로 롤백을 권장합니다.'
                    : '프로젝트 또는 채널을 확인하세요.',
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 11, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (canContinue) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: onContinue,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A2A),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('추가 보정',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: onComplete,
                  style: FilledButton.styleFrom(
                    backgroundColor: isTerminal
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFF2A2A2A),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('완료',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final bool warn;

  const _MetricRow({
    required this.label,
    required this.value,
    this.highlight = false,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = warn
        ? Colors.amber
        : highlight
            ? const Color(0xFF4CAF50)
            : Colors.white54;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ResetButton extends StatelessWidget {
  final VoidCallback onReset;
  const _ResetButton({required this.onReset});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onReset,
        child: const Text('처음으로',
            style: TextStyle(color: Colors.white38, letterSpacing: 1)),
      );
}
