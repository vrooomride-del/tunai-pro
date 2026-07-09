import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'project_status_bar.dart';
import 'tabs/project_tab.dart';
import 'tabs/workbench_tabs.dart';
import '../../core/pro_project_store.dart';
import '../../core/pro_measurement_store.dart';
import '../../shared/pro_widgets.dart';

class WorkbenchShell extends ConsumerStatefulWidget {
  final String projectId;
  const WorkbenchShell({super.key, required this.projectId});

  @override
  ConsumerState<WorkbenchShell> createState() => _WorkbenchShellState();
}

class _WorkbenchShellState extends ConsumerState<WorkbenchShell> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(proMeasurementProvider.notifier).loadForProject(widget.projectId);
    });
  }

  static const _tabs = [
    _TabDef('Project',   Icons.folder_outlined),
    _TabDef('Measure',   Icons.mic_none_outlined),
    _TabDef('Import',    Icons.folder_open_outlined),
    _TabDef('Target',    Icons.track_changes_outlined),
    _TabDef('Optimizer', Icons.auto_awesome_outlined),
    _TabDef('PEQ',       Icons.tune_outlined),
    _TabDef('XO',        Icons.device_hub_outlined),
    _TabDef('Phase',     Icons.timeline_outlined),
    _TabDef('Delay',     Icons.access_time_outlined),
    _TabDef('Gain',      Icons.bar_chart_outlined),
    _TabDef('Protection',Icons.verified_user_outlined),
    _TabDef('Export',    Icons.upload_outlined),
    _TabDef('Report',    Icons.summarize_outlined),
  ];

  List<Widget> _screens(String projectId) => [
    ProjectTab(projectId: projectId),
    MeasureTab(projectId: projectId),
    ImportTab(projectId: projectId),
    TargetTab(projectId: projectId),
    OptimizerTab(projectId: projectId),
    PeqTab(projectId: projectId),
    XoTab(projectId: projectId),
    PhaseTab(projectId: projectId),
    DelayTab(projectId: projectId),
    GainTab(projectId: projectId),
    ProtectionTab(projectId: projectId),
    ExportTab(projectId: projectId),
    ReportTab(projectId: projectId),
  ];

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == widget.projectId).firstOrNull;
    final screens = _screens(widget.projectId);

    return Scaffold(
      backgroundColor: kProBg,
      body: Column(children: [
        ProjectStatusBar(projectId: widget.projectId),
        Expanded(
          child: Row(children: [
            _Sidebar(
              tabs: _tabs,
              selected: _tabIndex,
              projectName: project?.name ?? 'Project',
              onSelect: (i) => setState(() => _tabIndex = i),
              onClose: () => Navigator.of(context).pop(),
            ),
            Container(width: 0.5, color: kProBorder),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: screens,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

class _TabDef {
  final String label;
  final IconData icon;
  const _TabDef(this.label, this.icon);
}

class _Sidebar extends StatelessWidget {
  final List<_TabDef> tabs;
  final int selected;
  final String projectName;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  const _Sidebar({
    required this.tabs,
    required this.selected,
    required this.projectName,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      color: kProPanel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Project name header
        GestureDetector(
          onTap: onClose,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
            ),
            child: Row(children: [
              const Icon(Icons.chevron_left, color: Colors.white38, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  projectName,
                  style: proTitle(size: 11, color: Colors.white60),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
        // Tab section label
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Text('WORKBENCH', style: proLabel(size: 9, color: Colors.white24, spacing: 2.5)),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: tabs.length,
            itemBuilder: (ctx, i) {
              final active = i == selected;
              return GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? kProAccent.withValues(alpha: 0.1) : Colors.transparent,
                    border: Border(
                      left: BorderSide(
                        color: active ? kProAccent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(children: [
                    Icon(tabs[i].icon, size: 14, color: active ? kProAccent : Colors.white38),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        tabs[i].label,
                        style: proTitle(size: 11, color: active ? Colors.white : const Color(0xFF6B7280)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          child: Text('TUNAI PRO · Phase G', style: proLabel(size: 9, color: Colors.white12, spacing: 1)),
        ),
      ]),
    );
  }
}
