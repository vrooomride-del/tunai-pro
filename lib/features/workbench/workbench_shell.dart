import 'package:flutter/material.dart';
import 'project_status_bar.dart';
import 'tabs/project_tab.dart';
import 'tabs/workbench_tabs.dart';
import '../../shared/pro_widgets.dart';

class WorkbenchShell extends StatefulWidget {
  final String projectName;
  const WorkbenchShell({super.key, this.projectName = 'Untitled Project'});

  @override
  State<WorkbenchShell> createState() => _WorkbenchShellState();
}

class _WorkbenchShellState extends State<WorkbenchShell> {
  int _tabIndex = 0;

  static const _tabs = [
    _TabDef('Project', Icons.folder_outlined),
    _TabDef('Measure', Icons.mic_none_outlined),
    _TabDef('Analyze', Icons.bar_chart_outlined),
    _TabDef('Crossover', Icons.device_hub_outlined),
    _TabDef('PEQ', Icons.tune_outlined),
    _TabDef('Delay / Phase', Icons.access_time_outlined),
    _TabDef('Limiter', Icons.shield_outlined),
    _TabDef('Protection', Icons.verified_user_outlined),
    _TabDef('Compare', Icons.compare_arrows_outlined),
    _TabDef('Deploy', Icons.upload_outlined),
    _TabDef('Report', Icons.summarize_outlined),
  ];

  static const _screens = [
    ProjectTab(),
    MeasureTab(),
    AnalyzeTab(),
    CrossoverTab(),
    PeqTab(),
    DelayPhaseTab(),
    LimiterTab(),
    ProtectionTab(),
    CompareTab(),
    DeployTab(),
    ReportTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kProBg,
      body: Column(children: [
        // Top status bar
        const ProjectStatusBar(),
        // Main content: sidebar + tab body
        Expanded(
          child: Row(children: [
            // Left sidebar
            _Sidebar(
              tabs: _tabs,
              selected: _tabIndex,
              onSelect: (i) => setState(() => _tabIndex = i),
            ),
            // Vertical divider
            Container(width: 0.5, color: kProBorder),
            // Tab content
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: _screens,
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
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.tabs, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      color: kProPanel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Workbench label
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
                    Icon(
                      tabs[i].icon,
                      size: 14,
                      color: active ? kProAccent : Colors.white38,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        tabs[i].label,
                        style: proTitle(
                          size: 11,
                          color: active ? Colors.white : const Color(0xFF6B7280),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
        // Bottom version tag
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          child: Text('TUNAI PRO · Phase A', style: proLabel(size: 9, color: Colors.white12, spacing: 1)),
        ),
      ]),
    );
  }
}
