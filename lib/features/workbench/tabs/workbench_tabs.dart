// Re-export tabs that have been split into dedicated files
export 'measure_tab.dart';
export 'analyze_tab.dart';
export 'report_tab.dart';

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

class CrossoverTab extends StatelessWidget {
  final String projectId;
  const CrossoverTab({super.key, required this.projectId});
  @override
  Widget build(BuildContext context) => _StatusAwarePlaceholder(
    projectId: projectId,
    title: 'Crossover Designer',
    subtitle: 'Configure crossover frequency, slope, polarity, and routing.',
    icon: Icons.device_hub_outlined,
    stats: const [
      ProQuickStat('HP FREQ', '—'),
      ProQuickStat('LP FREQ', '—'),
      ProQuickStat('SLOPE', '—'),
      ProQuickStat('POLARITY', '—'),
    ],
    readinessMessage: (s) => s.isAtLeast(ProfileStatus.tuned)
        ? 'Tuning data available.'
        : 'Create tuning decisions after measurement.',
  );
}

class PeqTab extends StatelessWidget {
  final String projectId;
  const PeqTab({super.key, required this.projectId});
  @override
  Widget build(BuildContext context) => _StatusAwarePlaceholder(
    projectId: projectId,
    title: 'Parametric EQ',
    subtitle: 'Review and edit correction filters.',
    icon: Icons.tune_outlined,
    stats: const [
      ProQuickStat('BANDS', '0 / 8'),
      ProQuickStat('MAX GAIN', '—'),
      ProQuickStat('ALGORITHM', 'Biquad IIR'),
      ProQuickStat('FORMAT', 'Direct Form II'),
    ],
    readinessMessage: (s) => s.isAtLeast(ProfileStatus.tuned)
        ? 'Tuning data available.'
        : 'Create tuning decisions after measurement.',
  );
}

class DelayPhaseTab extends StatelessWidget {
  final String projectId;
  const DelayPhaseTab({super.key, required this.projectId});
  @override
  Widget build(BuildContext context) => _StatusAwarePlaceholder(
    projectId: projectId,
    title: 'Time Alignment',
    subtitle: 'Adjust delay and phase for driver integration and imaging.',
    icon: Icons.access_time_outlined,
    stats: const [
      ProQuickStat('L DELAY', '0.00 ms'),
      ProQuickStat('R DELAY', '0.00 ms'),
      ProQuickStat('PHASE', '0°'),
      ProQuickStat('RESOLUTION', '0.02 ms'),
    ],
    readinessMessage: (s) => s.isAtLeast(ProfileStatus.tuned)
        ? 'Tuning data available.'
        : 'Create tuning decisions after measurement.',
  );
}

class LimiterTab extends StatelessWidget {
  final String projectId;
  const LimiterTab({super.key, required this.projectId});
  @override
  Widget build(BuildContext context) => _StatusAwarePlaceholder(
    projectId: projectId,
    title: 'Limiter',
    subtitle: 'Set safe output boundaries for the speaker system.',
    icon: Icons.shield_outlined,
    stats: const [
      ProQuickStat('THRESHOLD', '—'),
      ProQuickStat('ATTACK', '—'),
      ProQuickStat('RELEASE', '—'),
      ProQuickStat('MODE', 'RMS / Peak'),
    ],
    readinessMessage: (s) => s.isAtLeast(ProfileStatus.tuned)
        ? 'Tuning data available. Configure limits.'
        : 'Create tuning decisions after measurement.',
  );
}

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
