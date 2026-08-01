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
import '../../core/pro_measurement_parser.dart';
import '../../core/orchestrator/full_system_after_frd_input.dart';
import '../../core/orchestrator/guided_ai_project_apply.dart';
import '../../core/orchestrator/pro_guided_ai_controller.dart';
import '../../core/orchestrator/pro_guided_ai_state.dart';
import '../../core/orchestrator/pro_local_orchestrator_session.dart';
import '../../core/orchestrator/pro_orchestrator_plan.dart';
import '../../core/orchestrator/pro_orchestrator_types.dart';
import '../../core/pro_acoustic_data.dart' show DriverChannel;
import '../../core/pro_correction_cycle.dart';
import '../../core/pro_project_store.dart';
import '../../core/pro_project.dart';
import '../../core/spectrum_snapshot.dart';
import '../../core/workbench_tab_provider.dart';
import '../mic/mic_measurement_controller.dart';

class GuidedAiScreen extends ConsumerStatefulWidget {
  final String projectId;
  const GuidedAiScreen({super.key, required this.projectId});

  @override
  ConsumerState<GuidedAiScreen> createState() => _GuidedAiScreenState();
}

class _GuidedAiScreenState extends ConsumerState<GuidedAiScreen> {
  final _goalCtrl = TextEditingController();
  Future<void>? _activeGuidedRun;
  bool _confirmInProgress = false;
  bool _deployNavigationDone = false;
  int _onApplyCount = 0;
  FullSystemAfterFrdInput? _afterFrdInput;
  String? _afterFrdError;

  Future<void> _startGuidedRun(ProProject project) async {
    if (_activeGuidedRun != null) return;
    _deployNavigationDone = false;
    _onApplyCount = 0;
    try {
      final run = ref.read(guidedAiProvider.notifier).start(
            project: project,
            userGoal: _goalCtrl.text,
            onApply: (pid, applyResult) async {
              _onApplyCount++;
              debugPrint(
                  'ON_APPLY channelId=${applyResult.channelId} count=$_onApplyCount');
              if (!mounted) return;
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
              if (!op.wrote || op.updatedProject == null || !mounted) return;
              await ref
                  .read(proProjectStoreProvider.notifier)
                  .updateTuningState(
                    pid,
                    op.updatedProject!.tuningState,
                  );
            },
            onExportPackage: (pid, package) async {
              if (!mounted) return;
              final current = ref
                  .read(proProjectStoreProvider)
                  .projects
                  .where((p) => p.id == pid)
                  .firstOrNull;
              if (current == null) return;
              final updated = current.exportState.copyWith(
                packages: [
                  ...current.exportState.packages
                      .where((p) => p.id != package.id),
                  package,
                ],
                activePackageId: package.id,
              );
              if (!mounted) return;
              await ref
                  .read(proProjectStoreProvider.notifier)
                  .updateExportState(pid, updated);
            },
            onHardwareWritePlan: (pid, plan) async {
              debugPrint('WRITE_PLAN ops=${plan.operations.length}');
              if (!mounted || _deployNavigationDone) return;
              _deployNavigationDone = true;
              debugPrint('DEPLOY_HANDOFF');
              ref.read(workbenchTabProvider.notifier).go(kTabDeploy);
            },
          );
      _activeGuidedRun = run;
      await run;
    } catch (error) {
      if (mounted) ref.read(guidedAiProvider.notifier).reportFailure(error);
    } finally {
      _activeGuidedRun = null;
      if (mounted && _confirmInProgress) {
        setState(() => _confirmInProgress = false);
      }
    }
  }

  Future<void> _confirmApply(String stepId) async {
    debugPrint('CONTINUE_TAP');
    if (_confirmInProgress) return;
    setState(() => _confirmInProgress = true);
    try {
      debugPrint('CONFIRM_START');
      ref.read(guidedAiProvider.notifier).confirm(stepId);
      final run = _activeGuidedRun;
      if (run != null) await run;
      debugPrint('CONFIRM_END');
    } catch (error, stackTrace) {
      debugPrint('CONTINUE_ERROR $error');
      debugPrint('$stackTrace');
      if (mounted) ref.read(guidedAiProvider.notifier).reportFailure(error);
    } finally {
      if (mounted && _confirmInProgress) {
        setState(() => _confirmInProgress = false);
      }
    }
  }

  @override
  void dispose() {
    _goalCtrl.dispose();
    super.dispose();
  }

  void _beginAfterFrd(ProProject project) {
    setState(() {
      _afterFrdInput = FullSystemAfterFrdInput(project);
      _afterFrdError = null;
    });
    ref.read(guidedAiProvider.notifier).enterAwaitingAfterFrd();
  }

  Future<void> _importAfterFrd(String channelId) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['frd', 'txt'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.path == null) return;

    final content = await File(file.path!).readAsString();
    final parsed =
        ProMeasurementParser.parseFrd(fileName: file.name, content: content);
    final afterData = parsed.data;
    if (afterData == null || !afterData.hasMagnitude) return;

    final aiState = ref.read(guidedAiProvider);
    if (aiState is! ProGuidedAiCompleted) return;
    if (aiState.loopPhase != ProClosedLoopPhase.awaitingAfterFrd) return;

    final input = _afterFrdInput;
    if (input == null) return;
    try {
      input.add(channelId: channelId, afterFrd: afterData);
    } catch (error) {
      if (mounted) setState(() => _afterFrdError = '$error');
      return;
    }
    if (mounted) setState(() {});
    if (!input.isComplete) return;

    final beforeProject = input.beforeProject;
    final cycle = ref.read(guidedAiProvider.notifier).submitAfterFourChannelFrd(
          beforeProject: beforeProject,
          afterProject: input.buildAfterProject(),
          previousTuningState: beforeProject.tuningState,
          deployedTuningState: beforeProject.tuningState,
          cycleNumber: beforeProject.correctionCycles.length + 1,
          safetyPassed: beforeProject.safetyStatus == SafetyStatus.verified,
          beforeEvidenceRefs: input.beforeEvidenceRefs,
          afterEvidenceRefs: input.afterEvidenceRefs,
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

    // Expert single-channel handoff from Import tab (kept for Expert path only).
    final targetChannelId = ref.watch(guidedAiTargetChannelProvider);
    final frdChannels = project?.acousticState.driverChannels
            .where((d) => d.hasParsedFrd)
            .toList() ??
        [];
    // Resolve the target driver channel for Expert-mode display only.
    final DriverChannel? targetChannel = targetChannelId != null
        ? frdChannels.where((d) => d.id == targetChannelId).firstOrNull
        : null;
    final bool channelIdInvalid =
        targetChannelId != null && targetChannel == null;
    // 4-channel default mode: no single-channel selection required.
    // Required channels for full-system analysis.
    const requiredChannelIds = [
      'ch_tw_l',
      'ch_wf_l',
      'ch_tw_r',
      'ch_wf_r',
    ];

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
              const SizedBox(height: 16),
              _ContextRow(
                projectName: project?.name,
                hwTarget: project?.dspTarget,
                primaryFrdFilename: targetChannel?.frdFile?.fileName,
                driverChannelLabel: targetChannel?.shortLabel,
                repeatSweepCount: targetChannel?.additionalFrdSweeps.length,
                cycleNumber: (project?.correctionCycles.length ?? 0) + 1,
              ),
              const SizedBox(height: 20),

              // ── Input ──────────────────────────────────────────────────────
              if (aiState is ProGuidedAiIdle) ...[
                if ((project?.acousticState.parsedFrdCount ?? 0) == 0) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1200),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withAlpha(80)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_outlined,
                            color: Colors.amber, size: 15),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'FRD 파일이 없습니다 — Import 탭에서 측정 파일을 먼저 불러오세요.',
                            style: TextStyle(
                                color: Colors.amber, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (channelIdInvalid) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A0A00),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.block_outlined,
                            color: Colors.redAccent, size: 15),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '채널 없음: \'$targetChannelId\' — Import 탭에서 다시 선택하세요.',
                            style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // 4-channel FRD status — always shown when project has channels.
                if (project != null &&
                    project.acousticState.driverChannels.isNotEmpty) ...[
                  _FourChannelStatusPanel(
                    driverChannels: project.acousticState.driverChannels,
                    requiredChannelIds: requiredChannelIds,
                  ),
                  const SizedBox(height: 12),
                ],
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
                    onPressed: (project == null ||
                            project.acousticState.parsedFrdCount == 0 ||
                            channelIdInvalid)
                        ? null
                        : () async {
                            // 4-channel default: do not pass targetChannelId.
                            // Expert single-channel: targetChannelId is from
                            // Import tab handoff (guidedAiTargetChannelProvider).
                            // Clear provider after start so it doesn't linger.
                            ref
                                .read(guidedAiTargetChannelProvider.notifier)
                                .state = null;
                            await _startGuidedRun(project);
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
                  )
                else if (project.acousticState.parsedFrdCount == 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('분석 불가 — FRD 파일이 없습니다.',
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
                  candidatePreview: aiState.candidatePreview,
                  applyBlockedReason: aiState.applyBlockedReason,
                  targetChannelId: aiState.targetChannelId,
                  availablePeqSlots: aiState.availablePeqSlots,
                  beforeAfterSummary: aiState.beforeAfterSummary,
                  positionMetrics: aiState.positionMetrics,
                  positionRejectReasons: aiState.positionRejectReasons,
                  robustPrimaryBeforeRmsDb: aiState.robustPrimaryBeforeRmsDb,
                  robustPrimaryAfterRmsDb: aiState.robustPrimaryAfterRmsDb,
                  targetName: aiState.targetName,
                  targetPolicy: aiState.targetPolicy,
                  insufficientEvidence: aiState.insufficientEvidence,
                  confirmInProgress: _confirmInProgress,
                  onConfirm: () async =>
                      await _confirmApply(aiState.request.stepId),
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
                  _ApplyResultCard(
                    result: aiState.applyResult!,
                    onGoToDeploy: () =>
                        ref.read(workbenchTabProvider.notifier).go(kTabDeploy),
                  )
                else if (aiState.outcome.stepRecords.any((r) =>
                    r.toolId == ProOrchestratorToolId.acousticValidateSafety &&
                    r.status == ProStepStatus.failed)) ...[
                  const SizedBox(height: 12),
                  const _StatusCard(
                    icon: Icons.block_outlined,
                    label: '안전 검증 실패 — 적용이 차단되었습니다.',
                    color: Colors.redAccent,
                  ),
                ] else if (aiState.outcome.stepRecords.any((r) =>
                    r.toolId ==
                    ProOrchestratorToolId.acousticValidateSafety)) ...[
                  const SizedBox(height: 12),
                  _StatusCard(
                    icon: Icons.info_outline,
                    label: aiState.applyBlockedReason != null
                        ? '적용 차단: ${aiState.applyBlockedReason}'
                        : '적용 단계를 실행하지 않았습니다.',
                    color: Colors.white38,
                  ),
                ],
                if (aiState.loopPhase != null) ...[
                  const SizedBox(height: 12),
                  _LoopPhaseCard(phase: aiState.loopPhase!),
                ],
                // "Add After Measurement" — shown when apply succeeded and no
                // after FRD cycle is in progress or complete yet.
                if (aiState.loopPhase ==
                        ProClosedLoopPhase.awaitingMeasurement &&
                    aiState.applyResult?.status == TuningApplyStatus.ok) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: project == null
                          ? null
                          : () => _beginAfterFrd(project),
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
                if (aiState.loopPhase ==
                    ProClosedLoopPhase.awaitingAfterFrd) ...[
                  const SizedBox(height: 12),
                  const _FourChannelRemeasurementGuide(),
                  const SizedBox(height: 12),
                  for (final channelId in requiredChannelIds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _afterFrdInput?.afterByChannel
                                      .containsKey(channelId) ==
                                  true
                              ? null
                              : () => _importAfterFrd(channelId),
                          icon:
                              const Icon(Icons.folder_open_outlined, size: 16),
                          label: Text(_afterFrdInput?.afterByChannel
                                      .containsKey(channelId) ==
                                  true
                              ? '$channelId 준비 완료'
                              : '$channelId After FRD 선택'),
                        ),
                      ),
                    ),
                  if (_afterFrdError != null)
                    Text(_afterFrdError!,
                        style: const TextStyle(color: Colors.redAccent)),
                ],
                // evaluated phase: prompt next action.
                if (aiState.loopPhase == ProClosedLoopPhase.evaluated) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.folder_open_outlined, size: 16),
                      label: const Text('After FRD 불러오기'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E2A3A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(workbenchTabProvider.notifier)
                          .go(kTabDeploy),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: const BorderSide(color: Colors.white12),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('완료 — Deploy로 이동'),
                    ),
                  ),
                ],
                // Cycle evaluation result.
                if (aiState.loopPhase == ProClosedLoopPhase.cycleComplete &&
                    aiState.completedCycle != null) ...[
                  const SizedBox(height: 12),
                  _CycleDecisionCard(
                    cycle: aiState.completedCycle!,
                    cycleNumber: (project?.correctionCycles.length ?? 1),
                    onContinue: () =>
                        ref.read(guidedAiProvider.notifier).reset(),
                    onComplete: () {
                      ref.read(deployScrollTargetProvider.notifier).state =
                          DeployScrollTarget.factoryProfile;
                      ref.read(workbenchTabProvider.notifier).go(kTabDeploy);
                    },
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

class _ConfirmationCard extends StatefulWidget {
  final ProUserConfirmationRequest request;
  final List<CandidatePreviewEntry>? candidatePreview;
  final String? applyBlockedReason;
  final String? targetChannelId;
  final int? availablePeqSlots;
  final String? beforeAfterSummary;
  final Map<String, ({double before, double after, double improvement})>
      positionMetrics;
  final List<String> positionRejectReasons;
  final double? robustPrimaryBeforeRmsDb;
  final double? robustPrimaryAfterRmsDb;
  final String? targetName;
  final String? targetPolicy;

  /// True when the measurement has insufficientEvidence confidence. Requires
  /// an explicit Expert approval checkbox before the Apply button is enabled.
  final bool insufficientEvidence;
  final bool confirmInProgress;

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _ConfirmationCard({
    required this.request,
    this.candidatePreview,
    this.applyBlockedReason,
    this.targetChannelId,
    this.availablePeqSlots,
    this.beforeAfterSummary,
    this.positionMetrics = const {},
    this.positionRejectReasons = const [],
    this.robustPrimaryBeforeRmsDb,
    this.robustPrimaryAfterRmsDb,
    this.targetName,
    this.targetPolicy,
    this.insufficientEvidence = false,
    this.confirmInProgress = false,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_ConfirmationCard> createState() => _ConfirmationCardState();
}

class _ConfirmationCardState extends State<_ConfirmationCard> {
  bool _expertApprovalGranted = false;

  @override
  Widget build(BuildContext context) {
    final isBlocked = widget.applyBlockedReason != null ||
        (widget.insufficientEvidence && !_expertApprovalGranted);
    return _buildCard(isBlocked);
  }

  Widget _buildCard(bool isBlocked) => Container(
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
            Text(widget.request.explanation.summary,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5)),
            if (widget.candidatePreview != null &&
                widget.candidatePreview!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    '후보 ${widget.candidatePreview!.length}개',
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.5),
                  ),
                  if (widget.availablePeqSlots != null) ...[
                    const Text('  /  ',
                        style: TextStyle(color: Colors.white24, fontSize: 11)),
                    Text(
                      '슬롯 ${widget.availablePeqSlots}개 가용',
                      style: TextStyle(
                        color: widget.candidatePreview!.length >
                                widget.availablePeqSlots!
                            ? Colors.redAccent
                            : Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Table(
                columnWidths: const {
                  0: FixedColumnWidth(24),
                  1: FlexColumnWidth(2.5),
                  2: FixedColumnWidth(36),
                  3: FlexColumnWidth(2),
                  4: FlexColumnWidth(2),
                  5: FlexColumnWidth(1.5),
                  6: FlexColumnWidth(2),
                  7: FixedColumnWidth(44),
                },
                children: [
                  TableRow(
                    children: [
                      _th('#'),
                      _th('Ch'),
                      _th('Slot'),
                      _th('Freq'),
                      _th('Gain'),
                      _th('Q'),
                      _th('Grade'),
                      _th('Safety'),
                    ],
                  ),
                  for (final c in widget.candidatePreview!)
                    TableRow(
                      children: [
                        _td('${c.applicationOrder}'),
                        _td(c.channelId, overflow: TextOverflow.ellipsis),
                        _td(c.targetPeqSlot != null
                            ? '${c.targetPeqSlot}'
                            : '—'),
                        _td('${c.frequencyHz.round()} Hz'),
                        _td('${c.gainDb >= 0 ? '+' : ''}${c.gainDb.toStringAsFixed(1)} dB'),
                        _td(c.q.toStringAsFixed(2)),
                        _td(c.grade),
                        _tdSafety(c.safetyVerified),
                      ],
                    ),
                ],
              ),
            ],
            if (widget.beforeAfterSummary != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.show_chart,
                        color: Colors.white38, size: 13),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.beforeAfterSummary!,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.positionMetrics.isNotEmpty ||
                widget.positionRejectReasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Listening Position robustness',
                  style: TextStyle(color: Colors.white54, fontSize: 10)),
              const SizedBox(height: 5),
              if (widget.robustPrimaryBeforeRmsDb != null &&
                  widget.robustPrimaryAfterRmsDb != null)
                Text(
                  'Primary: ${widget.robustPrimaryBeforeRmsDb!.toStringAsFixed(1)} → '
                  '${widget.robustPrimaryAfterRmsDb!.toStringAsFixed(1)} dB',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              if (widget.positionMetrics.isNotEmpty)
                Text(
                  'Average: ${(widget.positionMetrics.values.map((m) => m.after).reduce((a, b) => a + b) / widget.positionMetrics.length).toStringAsFixed(1)} dB  '
                  'Worst: ${widget.positionMetrics.values.map((m) => m.after).reduce((a, b) => a < b ? a : b).toStringAsFixed(1)} dB',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              for (final entry in widget.positionMetrics.entries)
                Text(
                  '${entry.key}: ${entry.value.before.toStringAsFixed(1)} → '
                  '${entry.value.after.toStringAsFixed(1)} dB '
                  '(${entry.value.improvement >= 0 ? '+' : ''}'
                  '${entry.value.improvement.toStringAsFixed(1)} dB)',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              for (final reason in widget.positionRejectReasons)
                Text('Reject: $reason',
                    style: const TextStyle(color: Colors.amber, fontSize: 11)),
            ],
            if (widget.targetName != null) ...[
              const SizedBox(height: 6),
              Text('Target: ${widget.targetName}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
            if (widget.insufficientEvidence) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withAlpha(60)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber, size: 13),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '단일 FRD — 반복 측정 없음. 신뢰도가 낮습니다. Expert 승인 후에만 적용 가능합니다.',
                        style: TextStyle(
                            color: Colors.amber, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setState(
                    () => _expertApprovalGranted = !_expertApprovalGranted),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _expertApprovalGranted
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 16,
                        color: _expertApprovalGranted
                            ? Colors.white70
                            : Colors.white24,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Expert로서 낮은 신뢰도를 인지하고 적용을 승인합니다',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (widget.applyBlockedReason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.block_outlined,
                        color: Colors.redAccent, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '적용 차단: ${widget.applyBlockedReason}',
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
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
                    onPressed: isBlocked || widget.confirmInProgress
                        ? null
                        : widget.onConfirm,
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

  static Widget _th(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white38, fontSize: 10, letterSpacing: 1)),
      );

  static Widget _td(String t, {TextOverflow? overflow}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(t,
            overflow: overflow,
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
      );

  static Widget _tdSafety(bool verified) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            verified ? Icons.check_circle_outline : Icons.hourglass_empty,
            size: 11,
            color: verified ? const Color(0xFF4CAF50) : Colors.white24,
          ),
          const SizedBox(width: 3),
          Text(
            verified ? 'OK' : '대기',
            style: TextStyle(
                color: verified ? const Color(0xFF4CAF50) : Colors.white24,
                fontSize: 10),
          ),
        ]),
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

class _FourChannelRemeasurementGuide extends StatelessWidget {
  const _FourChannelRemeasurementGuide();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('4채널 재측정 안내',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            SizedBox(height: 8),
            Text(
              '• 적용된 DSP 상태 유지\n'
              '• 같은 마이크 위치·방향·높이\n'
              '• 같은 출력 레벨·입력 게인·샘플레이트·윈도우\n'
              '• ch_tw_l → ch_wf_l → ch_tw_r → ch_wf_r 순서\n'
              '• 가능하면 phase/time reference 유지\n'
              '• 유닛·인클로저·배선이 같으면 ZMA 재측정 불필요',
              style:
                  TextStyle(color: Colors.white60, fontSize: 12, height: 1.6),
            ),
          ],
        ),
      );
}

class _ApplyResultCard extends StatelessWidget {
  final TuningApplyResult result;
  final VoidCallback? onGoToDeploy;

  const _ApplyResultCard({required this.result, this.onGoToDeploy});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (result.status) {
      TuningApplyStatus.ok => ('프로젝트 PEQ 업데이트 완료', const Color(0xFF4CAF50)),
      TuningApplyStatus.partiallyApplied => ('일부 적용', Colors.amber),
      TuningApplyStatus.noSlotAvailable => (
          '슬롯 부족 — PEQ 밴드가 없습니다',
          Colors.redAccent
        ),
      TuningApplyStatus.notPermitted => (
          '적용 차단 — 안전 검증이 허가하지 않음',
          Colors.redAccent
        ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (result.applied.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final b in result.applied)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const SizedBox(width: 26),
                    Text(
                      '#${b.applicationOrder}  '
                      '${b.frequencyHz.round()} Hz  '
                      '${b.gainDb >= 0 ? '+' : ''}${b.gainDb.toStringAsFixed(1)} dB  '
                      'Q ${b.q.toStringAsFixed(2)}',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
          if (result.status == TuningApplyStatus.ok &&
              onGoToDeploy != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onGoToDeploy,
                icon: const Icon(Icons.inventory_2_outlined, size: 14),
                label: const Text('Deploy로 이동'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4CAF50),
                  side:
                      BorderSide(color: const Color(0xFF4CAF50).withAlpha(100)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CycleDecisionCard extends StatelessWidget {
  final CorrectionCycle cycle;
  final int cycleNumber;
  final VoidCallback onContinue;
  final VoidCallback onComplete;

  const _CycleDecisionCard({
    required this.cycle,
    required this.cycleNumber,
    required this.onContinue,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final decision = cycle.decision;
    final metrics = cycle.metrics;

    final (decisionLabel, decisionColor, icon) = switch (decision) {
      CorrectionCycleDecision.improvedAndComplete => (
          '개선 승인 · 완료',
          const Color(0xFF4CAF50),
          Icons.check_circle_outline,
        ),
      CorrectionCycleDecision.improvedNeedsAnotherCycle => (
          '개선 승인 · 다음 cycle 제안',
          Colors.amber,
          Icons.refresh,
        ),
      CorrectionCycleDecision.noMeaningfulImprovement => (
          '수렴 완료',
          Colors.white54,
          Icons.remove_circle_outline,
        ),
      CorrectionCycleDecision.worsened => (
          '악화 · rollback 제안',
          Colors.redAccent,
          Icons.warning_amber_outlined,
        ),
      CorrectionCycleDecision.insufficientEvidence => (
          '근거 부족',
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

    final canContinue =
        decision == CorrectionCycleDecision.improvedNeedsAnotherCycle;
    final isTerminal =
        decision == CorrectionCycleDecision.improvedAndComplete ||
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
              Expanded(
                child: Text(decisionLabel,
                    style: TextStyle(
                        color: decisionColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
              Text(
                'Cycle $cycleNumber',
                style: const TextStyle(
                    color: Colors.white24, fontSize: 10, letterSpacing: 1),
              ),
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
          if (decision ==
              CorrectionCycleDecision.improvedNeedsAnotherCycle) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'After 측정 결과가 다음 사이클의 Before로 사용됩니다.',
                style:
                    TextStyle(color: Colors.amber, fontSize: 11, height: 1.4),
              ),
            ),
          ],
          if (decision == CorrectionCycleDecision.worsened ||
              decision == CorrectionCycleDecision.wrongProjectOrChannel) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

class _ContextRow extends StatelessWidget {
  final String? projectName;
  final String? hwTarget;
  final String? primaryFrdFilename;
  final String? driverChannelLabel;
  final int? repeatSweepCount;
  final int cycleNumber;

  const _ContextRow({
    this.projectName,
    this.hwTarget,
    this.primaryFrdFilename,
    this.driverChannelLabel,
    this.repeatSweepCount,
    required this.cycleNumber,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          if (projectName != null) _Chip(Icons.folder_outlined, projectName!),
          if (hwTarget != null) _Chip(Icons.memory_outlined, hwTarget!),
          if (primaryFrdFilename != null)
            _Chip(Icons.graphic_eq_outlined, primaryFrdFilename!),
          if (driverChannelLabel != null)
            _Chip(Icons.speaker_outlined, driverChannelLabel!),
          if (repeatSweepCount != null && repeatSweepCount! > 0)
            _Chip(Icons.repeat_outlined, '스윕 +$repeatSweepCount'),
          _Chip(Icons.loop, 'Cycle $cycleNumber'),
        ],
      );
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white24),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white30, fontSize: 11)),
        ],
      );
}

// 4채널 FRD 준비 상태 패널 — Idle 화면에 표시.
class _FourChannelStatusPanel extends StatelessWidget {
  final List<DriverChannel> driverChannels;
  final List<String> requiredChannelIds;

  const _FourChannelStatusPanel({
    required this.driverChannels,
    required this.requiredChannelIds,
  });

  @override
  Widget build(BuildContext context) {
    final channelById = {for (final ch in driverChannels) ch.id: ch};
    final frdReadyCount = requiredChannelIds
        .where((id) => channelById[id]?.hasParsedFrd == true)
        .length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '4채널 시스템 튜닝',
                style: TextStyle(
                    color: Colors.white54, fontSize: 11, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                '$frdReadyCount / 4 FRD 준비',
                style: TextStyle(
                  color: frdReadyCount == 4
                      ? const Color(0xFF4CAF50)
                      : Colors.amber,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final id in requiredChannelIds)
            _ChannelStatusRow(channelId: id, channel: channelById[id]),
        ],
      ),
    );
  }
}

class _ChannelStatusRow extends StatelessWidget {
  final String channelId;
  final DriverChannel? channel;

  const _ChannelStatusRow({required this.channelId, this.channel});

  @override
  Widget build(BuildContext context) {
    final hasFrd = channel?.hasParsedFrd == true;
    final label = channel?.shortLabel ?? channelId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            hasFrd ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 13,
            color: hasFrd ? const Color(0xFF4CAF50) : Colors.white24,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: hasFrd ? Colors.white60 : Colors.white24,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hasFrd ? 'FRD 준비' : 'FRD 없음',
            style: TextStyle(
              color: hasFrd ? const Color(0xFF4CAF50) : Colors.white24,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
