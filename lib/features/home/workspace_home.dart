import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/pro_project.dart';
import '../../core/pro_project_store.dart';
import '../../shared/pro_widgets.dart';
import '../workbench/workbench_shell.dart';
import 'project_list_screen.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kProBg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Top header bar
          Container(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
            ),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TUNAI PRO', style: proTitle(size: 18, color: Colors.white)),
                const SizedBox(height: 3),
                Text('Acoustic Intelligence Workstation',
                    style: proLabel(size: 11, color: kProAccent, spacing: 1)),
              ]),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: kProSurface,
                  border: Border.all(color: kProBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'AI suggests · Expert verifies · AOS protects · DSP executes',
                  style: proLabel(size: 9, color: Colors.white38, spacing: 0.8),
                ),
              ),
            ]),
          ),

          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Measure, tune, verify, and deploy professional Sound Profiles.',
                  style: proSubtitle(size: 13, color: const Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 32),

                Text('START', style: proLabel(size: 10, spacing: 2)),
                const SizedBox(height: 12),
                _HomeGrid(children: [
                  ProHomeCard(
                    title: 'New Project',
                    subtitle: 'Create a new speaker or room tuning project.',
                    icon: Icons.add_circle_outline,
                    primary: true,
                    onTap: () => _showNewProjectDialog(context, ref),
                  ),
                  ProHomeCard(
                    title: 'Open Project',
                    subtitle: 'Continue working on a saved tuning project.',
                    icon: Icons.folder_open_outlined,
                    onTap: () => _goToProjectList(context),
                  ),
                ]),
                const SizedBox(height: 28),

                Text('HARDWARE & DATA', style: proLabel(size: 10, spacing: 2)),
                const SizedBox(height: 12),
                _HomeGrid(children: [
                  ProHomeCard(
                    title: 'Connect Hardware',
                    subtitle: 'Connect TUNAI ONE, ACM, USB, network, or AOS-compatible hardware.',
                    icon: Icons.usb_outlined,
                    onTap: () => _goToProjectList(context),
                  ),
                  ProHomeCard(
                    title: 'Import Data',
                    subtitle: 'Load FRD, ZMA, impulse response, or measurement files.',
                    icon: Icons.upload_file_outlined,
                    onTap: () => _goToProjectList(context),
                  ),
                ]),
                const SizedBox(height: 28),

                Text('TOOLS', style: proLabel(size: 10, spacing: 2)),
                const SizedBox(height: 12),
                _HomeGrid(children: [
                  ProHomeCard(
                    title: 'DSP Profile Generator',
                    subtitle: 'Convert tuning decisions into deployable DSP profiles.',
                    icon: Icons.settings_ethernet_outlined,
                    onTap: () => _goToProjectList(context),
                  ),
                  ProHomeCard(
                    title: 'Device Manager',
                    subtitle: 'Manage connected devices, firmware, and profile deployment.',
                    icon: Icons.devices_outlined,
                    onTap: () => _goToProjectList(context),
                  ),
                ]),

                const SizedBox(height: 40),
                Text('TUNAI PRO · Phase B · Project System',
                    style: proLabel(size: 9, color: Colors.white12, spacing: 1)),
              ]),
            ),
          ),
        ]),
      ),
    );
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

// ── Grid Layout ───────────────────────────────────────────────────────────────

class _HomeGrid extends StatelessWidget {
  final List<Widget> children;
  const _HomeGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final cols = constraints.maxWidth > 600 ? 2 : 1;
      if (cols == 1) {
        return Column(
          children: children
              .map((c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: c))
              .toList(),
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children.asMap().entries.map((e) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.key < children.length - 1 ? 10 : 0),
            child: e.value,
          ),
        )).toList(),
      );
    });
  }
}
