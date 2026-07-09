// Re-export tabs that have been split into dedicated files
export 'measure_tab.dart';
export 'analyze_tab.dart';
export 'import_tab.dart';
export 'target_tab.dart';
export 'report_tab.dart';
export 'peq_tab.dart';
export 'xo_tab.dart';
export 'gain_tab.dart';
export 'delay_tab.dart';
export 'phase_tab.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../shared/pro_widgets.dart';

// ── Helper: project-aware placeholder ────────────────────────────────────────

class _StatusAwarePlaceholder extends ConsumerWidget {
  final String projectId;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<ProQuickStat> stats;
  final String Function(ProfileStatus status) readinessMessage;

  const _StatusAwarePlaceholder({
    required this.projectId,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.stats,
    required this.readinessMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == projectId).firstOrNull;
    final status = project?.profileStatus ?? ProfileStatus.draft;
    final msg = readinessMessage(status);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text(title, style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 8),
        Text(subtitle, style: proSubtitle()),
        const SizedBox(height: 16),

        // Readiness banner
        _ReadinessBanner(message: msg, status: status),
        const SizedBox(height: 20),

        // Graph placeholder
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white10, size: 36),
              const SizedBox(height: 12),
              Text('No data', style: proLabel(color: Colors.white24)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: stats.map((s) => _StatChip(stat: s)).toList(),
        ),
      ]),
    );
  }
}

class _ReadinessBanner extends StatelessWidget {
  final String message;
  final ProfileStatus status;
  const _ReadinessBanner({required this.message, required this.status});

  @override
  Widget build(BuildContext context) {
    final isReady = !message.startsWith('Run') && !message.startsWith('Create') && !message.startsWith('Verify');
    final color = isReady ? kProGreen : kProAmber;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Icon(
          isReady ? Icons.check_circle_outline : Icons.info_outline,
          color: color,
          size: 14,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: proSubtitle(size: 11))),
        ProStatusPill(label: status.label, color: isReady ? kProGreen : const Color(0xFF6B7280)),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final ProQuickStat stat;
  const _StatChip({required this.stat});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(stat.label, style: proLabel(size: 9)),
      const SizedBox(height: 4),
      Text(stat.value, style: proValue(size: 13, color: Colors.white70)),
    ]),
  );
}

// ── Individual Tab Widgets ────────────────────────────────────────────────────
// MeasureTab, AnalyzeTab, ReportTab are defined in dedicated files (re-exported above).

// PeqTab → peq_tab.dart (Phase D)
// XoTab (was CrossoverTab) → xo_tab.dart (Phase D)

// DelayPhaseTab, LimiterTab → replaced by PhaseTab, DelayTab, GainTab in Phase E

class ProtectionTab extends StatelessWidget {
  final String projectId;
  const ProtectionTab({super.key, required this.projectId});
  @override
  Widget build(BuildContext context) => _StatusAwarePlaceholder(
    projectId: projectId,
    title: 'Protection Validation',
    subtitle: 'Verify the profile against speaker, amplifier, and thermal limits.',
    icon: Icons.verified_user_outlined,
    stats: const [
      ProQuickStat('SPEAKER', 'Not checked'),
      ProQuickStat('AMPLIFIER', 'Not checked'),
      ProQuickStat('THERMAL', 'Not checked'),
      ProQuickStat('AOS STATUS', 'Inactive'),
    ],
    readinessMessage: (s) => s.isAtLeast(ProfileStatus.tuned)
        ? 'Ready for safety validation.'
        : 'Create a tuning profile first.',
  );
}

class CompareTab extends StatelessWidget {
  final String projectId;
  const CompareTab({super.key, required this.projectId});
  @override
  Widget build(BuildContext context) => _StatusAwarePlaceholder(
    projectId: projectId,
    title: 'Compare Profiles',
    subtitle: 'Compare original, generated, and manually edited profiles.',
    icon: Icons.compare_arrows_outlined,
    stats: const [
      ProQuickStat('PROFILE A', 'Original'),
      ProQuickStat('PROFILE B', 'Generated'),
      ProQuickStat('DELTA RMS', '—'),
      ProQuickStat('DELTA PEAK', '—'),
    ],
    readinessMessage: (s) => s.isAtLeast(ProfileStatus.measured)
        ? 'Measurement data available for comparison.'
        : 'Run measurement first.',
  );
}

class DeployTab extends StatelessWidget {
  final String projectId;
  const DeployTab({super.key, required this.projectId});
  @override
  Widget build(BuildContext context) => _StatusAwarePlaceholder(
    projectId: projectId,
    title: 'Deploy DSP Profile',
    subtitle: 'Write verified profiles to connected hardware.',
    icon: Icons.upload_outlined,
    stats: const [
      ProQuickStat('TARGET', 'Not selected'),
      ProQuickStat('STATUS', 'Not verified'),
      ProQuickStat('CHECKSUM', '—'),
      ProQuickStat('LAST DEPLOY', 'Never'),
    ],
    readinessMessage: (s) => s == ProfileStatus.verified || s == ProfileStatus.deployed
        ? 'Profile is ready to deploy.'
        : 'Verify protection before deployment.',
  );
}
