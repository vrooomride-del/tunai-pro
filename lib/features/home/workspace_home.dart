import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/pro_project.dart';
import '../../core/pro_project_store.dart';
import '../../core/pro_demo_project_factory.dart';
import '../../shared/pro_widgets.dart';
import '../../shared/design/pro_tokens.dart';
import '../workbench/workbench_shell.dart';
import 'project_list_screen.dart';
import 'widgets/home_hero_header.dart';
import 'widgets/workflow_progress_stepper.dart';
import 'widgets/current_project_status_card.dart';
import 'widgets/start_actions_section.dart';

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

  void _continueCurrentProject(BuildContext context, WidgetRef ref) {
    final project = ref.read(proProjectStoreProvider).currentProject;
    if (project != null) _openWorkbench(context, project.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ProColors.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const HomeHeroHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: ProSpacing.xxl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const WorkflowProgressStepper(),
                const SizedBox(height: ProSpacing.xl),
                CurrentProjectStatusCard(
                  onContinue: () => _continueCurrentProject(context, ref),
                  onNewProject: () => _showNewProjectDialog(context, ref),
                  onOpenDemo: () => _openDemoProject(context, ref),
                ),
                const SizedBox(height: ProSpacing.xxl),
                StartActionsSection(
                  onNewProject: () => _showNewProjectDialog(context, ref),
                  onOpenProject: () => _goToProjectList(context),
                  onOpenDemo: () => _openDemoProject(context, ref),
                  onConnectHardware: () => _goToProjectList(context),
                  onImportData: () => _goToProjectList(context),
                  onDspProfileGenerator: () => _goToProjectList(context),
                  onDeviceManager: () => _goToProjectList(context),
                ),
                const SizedBox(height: ProSpacing.xxl),
                Center(
                  child: Text('TUNAI PRO · T4C',
                      style: TextStyle(color: ProColors.textTertiary.withValues(alpha: 0.4), fontSize: 9)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _openDemoProject(BuildContext context, WidgetRef ref) async {
    final demo = createTunaiProDemoProject();
    await ref.read(proProjectStoreProvider.notifier).addProject(demo);
    if (context.mounted) _openWorkbench(context, demo.id);
  }

  Future<void> _showNewProjectDialog(BuildContext context, WidgetRef ref) async {
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
  static const _roomOptions = ['Desk', 'Living Room', 'Near Wall', 'Studio', 'Custom'];
  static const _sampleRates = [44100, 48000, 96000, 192000];
  static const _dspTargets = ['ADAU1701', 'ADAU1466', 'Sigma DSP Custom'];
  static const _channelConfigs = ['2-way stereo', '2-way mono', '3-way stereo', 'Subwoofer only'];

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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _FieldLabel('Project Name'),
                _TextInput(controller: _nameCtrl, autofocus: true),
                const SizedBox(height: 16),

                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _FieldLabel('Speaker Model'),
                    _DropInput<String>(
                      value: _speakerModel,
                      items: _speakerOptions,
                      labelOf: (s) => s,
                      onChanged: (v) => setState(() => _speakerModel = v),
                    ),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _FieldLabel('Room / Location'),
                    _DropInput<String>(
                      value: _roomName,
                      items: _roomOptions,
                      labelOf: (s) => s,
                      onChanged: (v) => setState(() => _roomName = v),
                    ),
                  ])),
                ]),
                const SizedBox(height: 16),

                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _FieldLabel('Sample Rate'),
                    _DropInput<int>(
                      value: _sampleRate,
                      items: _sampleRates,
                      labelOf: (v) => '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)} kHz',
                      onChanged: (v) => setState(() => _sampleRate = v),
                    ),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _FieldLabel('DSP Target'),
                    _DropInput<String>(
                      value: _dspTarget,
                      items: _dspTargets,
                      labelOf: (s) => s,
                      onChanged: (v) => setState(() => _dspTarget = v),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: kProAccent.withValues(alpha: 0.15),
                    border: Border.all(color: kProAccent.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Create Project', style: TextStyle(color: kProAccent, fontSize: 12)),
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
    child: Text(text, style: proLabel(size: 10, color: Colors.white38, spacing: 1)),
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
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: kProBorder)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kProAccent)),
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
      items: items.map((i) => DropdownMenuItem(
        value: i,
        child: Text(labelOf(i), style: proTitle(size: 12)),
      )).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  );
}
