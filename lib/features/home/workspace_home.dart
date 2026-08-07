// ── TUNAI PRO Phase 3-E — Workspace Home ───────────────────────────────────
//
// A tuning console, not a menu of professional features. The screen answers
// five questions in order:
//   A. Project Hero        — what am I working on?
//   B. Continue Tuning     — what do I do next?          (the one primary CTA)
//   C. Tuning Journey      — where am I overall?
//   D. System Readiness    — what is ready?
//   E. Expert Tools        — where are the professional tools?
//
// measurementWorkflowReadinessProvider is the single source of truth: this
// file watches it once and passes the result down. No section re-derives a
// condition, recalculates a priority, or reads a gate itself.
//
// Nothing was removed from the Workbench — Expert Tools links to every
// existing tab through the existing kTabXxx constants and workbenchTabProvider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/pro_project.dart';
import '../../core/pro_project_store.dart';
import '../../core/pro_demo_project_factory.dart';
import '../../core/measurement_entry_intent.dart';
import '../../core/workbench_tab_provider.dart';
import '../../core/workflow/measurement_workflow_provider.dart';
import '../../core/workflow/measurement_workflow_readiness.dart';
import '../../shared/pro_widgets.dart';
import '../../shared/design/pro_tokens.dart';
import '../workbench/workbench_shell.dart';
import 'home_navigation.dart';
import 'project_list_screen.dart';
import 'widgets/continue_tuning_card.dart';
import 'widgets/expert_tools_section.dart';
import 'widgets/project_hero.dart';
import 'widgets/system_readiness_panel.dart';
import 'widgets/tuning_journey.dart';

/// Below this the two-column band (Continue + Readiness) stacks.
const double kHomeTwoColumnBreakpoint = 1100;

/// Keeps the content readable on very wide displays instead of stretching
/// cards across the full width (§20).
const double kHomeMaxContentWidth = 1320;

class WorkspaceHome extends ConsumerWidget {
  const WorkspaceHome({super.key});

  void _openWorkbench(BuildContext context, String projectId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WorkbenchShell(projectId: projectId)),
    );
  }

  void _goToProjectList(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProjectListScreen()),
    );
  }

  /// Opens the current project's Workbench focused on [tabIndex], reusing the
  /// existing cross-tab provider rather than introducing a second navigation
  /// mechanism.
  void _openWorkbenchTab(BuildContext context, WidgetRef ref, int tabIndex,
      {MeasurementEntryIntent? intent}) {
    final project = ref.read(proProjectStoreProvider).currentProject;
    if (project == null) {
      _goToProjectList(context);
      return;
    }
    ref.read(workbenchTabProvider.notifier).go(tabIndex);
    // Raised BEFORE the tab is built so the destination consumes it on its
    // first frame — one-shot, scoped to this project (§5).
    if (intent != null) {
      ref
          .read(measurementEntryIntentProvider.notifier)
          .request(intent, projectId: project.id);
    }
    _openWorkbench(context, project.id);
  }

  /// §6 — typed dispatch. Never a string comparison, never a literal index.
  void _runAction(
      BuildContext context, WidgetRef ref, MeasurementWorkflowAction action) {
    switch (homeActionDestination(action)) {
      case HomeProjectListDestination():
        _goToProjectList(context);
      case HomeWorkbenchDestination(:final tabIndex, :final intent):
        _openWorkbenchTab(context, ref, tabIndex, intent: intent);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(measurementWorkflowReadinessProvider);
    final project = ref.watch(proProjectStoreProvider).currentProject;

    return Scaffold(
      backgroundColor: ProColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kHomeMaxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProjectHero(
                    readiness: readiness,
                    project: project,
                    onNewProject: () => _showNewProjectDialog(context, ref),
                    onOpenProject: () => _goToProjectList(context),
                    onOpenDemo: () => _openDemoProject(context, ref),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(ProSpacing.xxl,
                        ProSpacing.xl, ProSpacing.xxl, ProSpacing.xxl),
                    child: readiness.hasProject
                        ? _projectBody(context, ref, readiness)
                        : _emptyBody(context, ref),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: ProSpacing.xl),
                    child: Center(
                      child: Text(
                        'TUNAI PRO · T4C',
                        style: TextStyle(
                            color:
                                ProColors.textTertiary.withValues(alpha: 0.4),
                            fontSize: 9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _projectBody(BuildContext context, WidgetRef ref,
      MeasurementWorkflowReadiness readiness) {
    final continueCard = ContinueTuningCard(
      readiness: readiness,
      onAction: (a) => _runAction(context, ref, a),
    );
    final readinessPanel = SystemReadinessPanel(
      readiness: readiness,
      onOpenSetup: () => _runAction(
          context, ref, MeasurementWorkflowAction.checkMeasurementSetup),
      onOpenHardware: () => _openWorkbenchTab(context, ref, kTabHardware),
      onOpenMicrophone: () =>
          _runAction(context, ref, MeasurementWorkflowAction.selectMicrophone),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < kHomeTwoColumnBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              continueCard,
              const SizedBox(height: ProSpacing.lg),
              readinessPanel,
            ],
          );
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: continueCard),
          const SizedBox(width: ProSpacing.lg),
          Expanded(flex: 2, child: readinessPanel),
        ]);
      }),
      const SizedBox(height: ProSpacing.lg),
      TuningJourney(readiness: readiness),
      const SizedBox(height: ProSpacing.lg),
      ExpertToolsSection(
        onOpenTab: (index) => _openWorkbenchTab(context, ref, index),
      ),
    ]);
  }

  /// §14 — with no project open, New/Open/Demo are what matter. The
  /// development-oriented tools are not shown here at all; they live inside
  /// the Workbench, which requires a project anyway.
  Widget _emptyBody(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ContinueTuningCard(
        readiness: ref.watch(measurementWorkflowReadinessProvider),
        onAction: (a) => _runAction(context, ref, a),
      ),
      const SizedBox(height: ProSpacing.lg),
      ProHomeCard(
        title: '데모 프로젝트 열기',
        subtitle: 'TUNAI ONE Coax Demo — 미리 준비된 측정 데이터로 전체 흐름을 살펴봅니다.',
        icon: Icons.science_outlined,
        onTap: () => _openDemoProject(context, ref),
      ),
    ]);
  }

  Future<void> _openDemoProject(BuildContext context, WidgetRef ref) async {
    final demo = createTunaiProDemoProject();
    await ref.read(proProjectStoreProvider.notifier).addProject(demo);
    if (context.mounted) _openWorkbench(context, demo.id);
  }

  Future<void> _showNewProjectDialog(
      BuildContext context, WidgetRef ref) async {
    final result = await showDialog<ProProject>(
      context: context,
      builder: (ctx) => const _NewProjectDialog(),
    );
    if (result != null && context.mounted) {
      await ref.read(proProjectStoreProvider.notifier).addProject(result);
      if (context.mounted) _openWorkbench(context, result.id);
    }
  }
}

// ── New Project Dialog ────────────────────────────────────────────────────────

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _nameCtrl = TextEditingController(text: 'Untitled Project');
  String _speakerModel = 'TUNAI ONE';
  String _roomName = 'Desk';
  int _sampleRate = 48000;
  String _dspTarget = 'ADAU1701';
  String _channelConfig = '2-way stereo';

  static const _speakerOptions = ['TUNAI ONE', 'TUNAI REF', 'Custom'];
  static const _roomOptions = [
    'Desk',
    'Living Room',
    'Near Wall',
    'Studio',
    'Custom'
  ];
  static const _sampleRates = [44100, 48000, 96000, 192000];
  static const _dspTargets = ['ADAU1701', 'ADAU1466', 'Sigma DSP Custom'];
  static const _channelConfigs = [
    '2-way stereo',
    '2-way mono',
    '3-way stereo',
    'Subwoofer only'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kProPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: kProBorder),
      ),
      child: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 18),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
            ),
            child: Row(children: [
              Text('New Project', style: proTitle(size: 15)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),

          // Fields
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Project Name'),
                    _TextInput(controller: _nameCtrl, autofocus: true),
                    const SizedBox(height: 16),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const _FieldLabel('Speaker Model'),
                                _DropInput<String>(
                                  value: _speakerModel,
                                  items: _speakerOptions,
                                  labelOf: (s) => s,
                                  onChanged: (v) =>
                                      setState(() => _speakerModel = v),
                                ),
                              ])),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const _FieldLabel('Room / Location'),
                                _DropInput<String>(
                                  value: _roomName,
                                  items: _roomOptions,
                                  labelOf: (s) => s,
                                  onChanged: (v) =>
                                      setState(() => _roomName = v),
                                ),
                              ])),
                        ]),
                    const SizedBox(height: 16),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const _FieldLabel('Sample Rate'),
                                _DropInput<int>(
                                  value: _sampleRate,
                                  items: _sampleRates,
                                  labelOf: (v) =>
                                      '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)} kHz',
                                  onChanged: (v) =>
                                      setState(() => _sampleRate = v),
                                ),
                              ])),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const _FieldLabel('DSP Target'),
                                _DropInput<String>(
                                  value: _dspTarget,
                                  items: _dspTargets,
                                  labelOf: (s) => s,
                                  onChanged: (v) =>
                                      setState(() => _dspTarget = v),
                                ),
                              ])),
                        ]),
                    const SizedBox(height: 16),
                    const _FieldLabel('Channel Configuration'),
                    _DropInput<String>(
                      value: _channelConfig,
                      items: _channelConfigs,
                      labelOf: (s) => s,
                      onChanged: (v) => setState(() => _channelConfig = v),
                    ),
                    const SizedBox(height: 24),
                  ]),
            ),
          ),

          // Actions
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: kProBorder, width: 0.5)),
            ),
            child: Row(children: [
              Text(
                '$_dspTarget · ${(_sampleRate / 1000).toStringAsFixed(_sampleRate % 1000 == 0 ? 0 : 1)} kHz · $_channelConfig',
                style: proLabel(size: 9, color: Colors.white24, spacing: 0.5),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: proSubtitle(size: 12)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final name = _nameCtrl.text.trim();
                  final project = ProProject.create(
                    name: name.isEmpty ? 'Untitled Project' : name,
                    speakerModel: _speakerModel,
                    roomName: _roomName,
                    sampleRate: _sampleRate,
                    dspTarget: _dspTarget,
                    channelConfig: _channelConfig,
                  );
                  Navigator.pop(context, project);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: kProAccent.withValues(alpha: 0.15),
                    border:
                        Border.all(color: kProAccent.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Create Project',
                      style: TextStyle(color: kProAccent, fontSize: 12)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: proLabel(size: 10, color: Colors.white38, spacing: 1)),
      );
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final bool autofocus;
  const _TextInput({required this.controller, this.autofocus = false});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        style: proTitle(size: 13),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          enabledBorder:
              OutlineInputBorder(borderSide: BorderSide(color: kProBorder)),
          focusedBorder:
              OutlineInputBorder(borderSide: BorderSide(color: kProAccent)),
          filled: true,
          fillColor: kProSurface,
        ),
      );
}

class _DropInput<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const _DropInput({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: kProPanel,
          underline: const SizedBox.shrink(),
          style: proTitle(size: 12),
          iconEnabledColor: Colors.white38,
          items: items
              .map((i) => DropdownMenuItem(
                    value: i,
                    child: Text(labelOf(i), style: proTitle(size: 12)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );
}
