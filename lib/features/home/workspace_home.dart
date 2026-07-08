import 'package:flutter/material.dart';
import '../../shared/pro_widgets.dart';
import '../workbench/workbench_shell.dart';

class WorkspaceHome extends StatelessWidget {
  const WorkspaceHome({super.key});

  void _openWorkbench(BuildContext context, {String name = 'Untitled Project'}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WorkbenchShell(projectName: name)),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    style: proLabel(size: 11, color: const Color(0xFF4A9EFF), spacing: 1)),
              ]),
              const Spacer(),
              // Principle tag
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

                // Section: Start
                Text('START', style: proLabel(size: 10, spacing: 2)),
                const SizedBox(height: 12),
                _HomeGrid(children: [
                  ProHomeCard(
                    title: 'New Project',
                    subtitle: 'Create a new speaker or room tuning project.',
                    icon: Icons.add_circle_outline,
                    primary: true,
                    onTap: () => _showNewProjectDialog(context),
                  ),
                  ProHomeCard(
                    title: 'Open Project',
                    subtitle: 'Continue working on a saved tuning project.',
                    icon: Icons.folder_open_outlined,
                    onTap: () => _openWorkbench(context),
                  ),
                ]),
                const SizedBox(height: 28),

                // Section: Hardware & Data
                Text('HARDWARE & DATA', style: proLabel(size: 10, spacing: 2)),
                const SizedBox(height: 12),
                _HomeGrid(children: [
                  ProHomeCard(
                    title: 'Connect Hardware',
                    subtitle: 'Connect TUNAI ONE, ACM, USB, network, or AOS-compatible hardware.',
                    icon: Icons.usb_outlined,
                    onTap: () => _openWorkbench(context),
                  ),
                  ProHomeCard(
                    title: 'Import Data',
                    subtitle: 'Load FRD, ZMA, impulse response, or measurement files.',
                    icon: Icons.upload_file_outlined,
                    onTap: () => _openWorkbench(context),
                  ),
                ]),
                const SizedBox(height: 28),

                // Section: Tools
                Text('TOOLS', style: proLabel(size: 10, spacing: 2)),
                const SizedBox(height: 12),
                _HomeGrid(children: [
                  ProHomeCard(
                    title: 'DSP Profile Generator',
                    subtitle: 'Convert tuning decisions into deployable DSP profiles.',
                    icon: Icons.settings_ethernet_outlined,
                    onTap: () => _openWorkbench(context),
                  ),
                  ProHomeCard(
                    title: 'Device Manager',
                    subtitle: 'Manage connected devices, firmware, and profile deployment.',
                    icon: Icons.devices_outlined,
                    onTap: () => _openWorkbench(context),
                  ),
                ]),

                const SizedBox(height: 40),
                // Version footer
                Text('TUNAI PRO · Phase A · Workstation Shell',
                    style: proLabel(size: 9, color: Colors.white12, spacing: 1)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _showNewProjectDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: 'Untitled Project');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kProPanel,
        title: Text('New Project', style: proTitle(size: 14)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Enter a project name.', style: proSubtitle(size: 12)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            style: proTitle(size: 13),
            decoration: InputDecoration(
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kProBorder)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kProAccent)),
              hintText: 'Project name',
              hintStyle: proSubtitle(size: 12),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: proSubtitle(size: 12)),
          ),
          TextButton(
            onPressed: () {
              final n = ctrl.text.trim();
              Navigator.pop(ctx, n.isEmpty ? 'Untitled Project' : n);
            },
            child: const Text('Create', style: TextStyle(color: kProAccent, fontSize: 12)),
          ),
        ],
      ),
    );
    if (name != null && context.mounted) {
      _openWorkbench(context, name: name);
    }
  }
}

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
        children: children.map((c) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: children.indexOf(c) < children.length - 1 ? 10 : 0,
            ),
            child: c,
          ),
        )).toList(),
      );
    });
  }
}
