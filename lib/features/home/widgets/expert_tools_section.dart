// ── TUNAI PRO Phase 3-E §12/§14 — E. Expert Tools ──────────────────────────
//
// Every professional tab stays reachable — nothing was removed. They are
// simply moved out of the beginner's primary path into one collapsed
// section, so a development tool like the DSP Profile Generator no longer
// competes with Continue Tuning for attention.
//
// These are shortcuts to the EXISTING Workbench tabs via the existing
// kTabXxx constants. No tab is redesigned and no new screen is introduced.

import 'package:flutter/material.dart';

import '../../../core/workbench_tab_provider.dart';
import '../../../shared/design/pro_tokens.dart';
import 'home_primitives.dart';

class ExpertToolEntry {
  final String label;
  final IconData icon;
  final int tabIndex;
  const ExpertToolEntry(this.label, this.icon, this.tabIndex);
}

class ExpertToolGroup {
  final String title;
  final List<ExpertToolEntry> tools;
  const ExpertToolGroup(this.title, this.tools);
}

/// Mirrors the Workbench sidebar's own grouping, by index constant only —
/// it can never drift out of sync with the real tab order.
const kExpertToolGroups = <ExpertToolGroup>[
  ExpertToolGroup('측정', [
    ExpertToolEntry('Measure', Icons.mic_none_outlined, kTabMeasure),
    ExpertToolEntry('Import', Icons.folder_open_outlined, kTabImport),
    ExpertToolEntry('Target', Icons.track_changes_outlined, kTabTarget),
  ]),
  ExpertToolGroup('스피커 설계', [
    ExpertToolEntry('Optimizer', Icons.auto_awesome_outlined, kTabOptimizer),
    ExpertToolEntry('Guided AI', Icons.psychology_outlined, kTabGuidedAi),
    ExpertToolEntry('PEQ', Icons.tune_outlined, kTabPeq),
    ExpertToolEntry('Crossover', Icons.device_hub_outlined, kTabXo),
    ExpertToolEntry('Phase', Icons.timeline_outlined, kTabPhase),
    ExpertToolEntry('Delay', Icons.access_time_outlined, kTabDelay),
    ExpertToolEntry('Gain', Icons.bar_chart_outlined, kTabGain),
    ExpertToolEntry('Mute', Icons.volume_off_outlined, kTabMute),
    ExpertToolEntry('Auto PEQ', Icons.auto_fix_high_outlined, kTabAutoPeq),
  ]),
  ExpertToolGroup('검증 · 하드웨어', [
    ExpertToolEntry('Simulation', Icons.show_chart_outlined, kTabSimulation),
    ExpertToolEntry('Protection', Icons.verified_user_outlined, kTabProtection),
    ExpertToolEntry('Hardware', Icons.security_outlined, kTabHardware),
    ExpertToolEntry('Deploy', Icons.inventory_2_outlined, kTabDeploy),
  ]),
  ExpertToolGroup('프로젝트', [
    ExpertToolEntry('Project', Icons.folder_outlined, kTabProject),
    ExpertToolEntry('Export', Icons.upload_outlined, kTabExport),
    ExpertToolEntry('Report', Icons.summarize_outlined, kTabReport),
  ]),
];

class ExpertToolsSection extends StatefulWidget {
  final void Function(int tabIndex) onOpenTab;
  const ExpertToolsSection({super.key, required this.onOpenTab});

  @override
  State<ExpertToolsSection> createState() => _ExpertToolsSectionState();
}

class _ExpertToolsSectionState extends State<ExpertToolsSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return HomePanel(
      padding: const EdgeInsets.symmetric(
          horizontal: ProSpacing.xl, vertical: ProSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: ProRadius.smallAll,
            child: Row(children: [
              const HomeSectionLabel('EXPERT TOOLS'),
              const SizedBox(width: ProSpacing.sm),
              const Expanded(
                child: Text(
                  '전문 도구를 직접 열 수 있습니다.',
                  style: TextStyle(
                      color: ProColors.textTertiary,
                      fontSize: ProTypeScale.label),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(_open ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: ProColors.textTertiary),
            ]),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: ProSpacing.lg),
          for (final group in kExpertToolGroups) ...[
            Text(
              group.title,
              style: const TextStyle(
                  color: ProColors.textTertiary, fontSize: ProTypeScale.label),
            ),
            const SizedBox(height: ProSpacing.sm),
            Wrap(
              spacing: ProSpacing.sm,
              runSpacing: ProSpacing.sm,
              children: [
                for (final t in group.tools)
                  HomeSecondaryButton(
                    label: t.label,
                    icon: t.icon,
                    onTap: () => widget.onOpenTab(t.tabIndex),
                  ),
              ],
            ),
            const SizedBox(height: ProSpacing.lg),
          ],
        ],
      ]),
    );
  }
}
