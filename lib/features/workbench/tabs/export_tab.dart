// ── Export Tab — Phase F ──────────────────────────────────────────────────────
// DSP export readiness gate. No actual export implemented yet.
// Export is gated on Protection verification status.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_protection_data.dart';
import '../../../shared/pro_widgets.dart';

class ExportTab extends ConsumerWidget {
  final String projectId;
  const ExportTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(proProjectStoreProvider);
    final project =
        store.projects.where((p) => p.id == projectId).firstOrNull;
    final protection =
        project?.protectionState ?? ProtectionProjectState.createDefault();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.upload_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('DSP Export', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 4),
        Text('Export verified tuning to DSP profile format. '
            'Actual hardware write will be added in a later phase.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        // Export gate status
        _ExportGate(protection: protection),
        const SizedBox(height: 20),

        // Export format info
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('EXPORT FORMATS (PLANNED)', style: proLabel(size: 9, spacing: 1.8)),
            const SizedBox(height: 10),
            const _FormatRow(label: 'SigmaStudio Parameter File', status: 'Planned'),
            const _FormatRow(label: 'ADAU1701 / ADAU1466 Binary', status: 'Planned'),
            const _FormatRow(label: 'TUNAI PRO JSON Archive', status: 'Planned'),
            const _FormatRow(label: 'Verification Report (PDF)', status: 'Planned'),
          ]),
        ),
        const SizedBox(height: 16),

        const Wrap(spacing: 10, runSpacing: 10, children: [
          _StatChip(label: 'TARGET DSP', value: '—'),
          _StatChip(label: 'CHECKSUM', value: '—'),
          _StatChip(label: 'LAST EXPORT', value: 'Never'),
          _StatChip(label: 'SIGNED BY', value: '—'),
        ]),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ExportGate extends StatelessWidget {
  final ProtectionProjectState protection;
  const _ExportGate({required this.protection});

  @override
  Widget build(BuildContext context) {
    final status = protection.verificationStatus;

    // Not yet verified
    if (status == VerificationStatus.notReady) {
      return const _GateBanner(
        icon: Icons.lock_outline,
        color: Color(0xFF6B7280),
        title: 'Export locked — run Protection verification first.',
        subtitle:
            'Open the Protection tab and run verification to check your tuning '
            'before export is available.',
      );
    }

    // Failed — critical issues block export
    if (status == VerificationStatus.failed) {
      return _GateBanner(
        icon: Icons.block_outlined,
        color: kProRed,
        title: 'Export blocked by critical protection issues.',
        subtitle: '${protection.criticalCount} critical issue(s) must be resolved before export. '
            'Open the Protection tab to review.',
      );
    }

    // Passed with warnings — draft available
    if (status == VerificationStatus.passedWithWarnings) {
      return _GateBanner(
        icon: Icons.warning_amber_outlined,
        color: kProAmber,
        title: 'Export draft available with warnings.',
        subtitle:
            '${protection.warningCount} warning(s) noted. Expert review is required before '
            'writing to hardware. Actual export will be available in a later phase.',
      );
    }

    // Fully passed
    return const _GateBanner(
      icon: Icons.check_circle_outline,
      color: kProGreen,
      title: 'Ready for DSP export draft.',
      subtitle: 'Verification passed. Actual DSP write will be available after '
          'hardware integration is complete in a later phase.',
    );
  }
}

class _GateBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _GateBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      border: Border.all(color: color.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: proTitle(size: 12, color: color)),
          const SizedBox(height: 4),
          Text(subtitle, style: proSubtitle(size: 11)),
        ]),
      ),
    ]),
  );
}

class _FormatRow extends StatelessWidget {
  final String label;
  final String status;
  const _FormatRow({required this.label, required this.status});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: proTitle(size: 11, color: Colors.white60))),
      Text(status, style: proLabel(size: 9, color: Colors.white24, spacing: 0.5)),
    ]),
  );
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 9)),
      const SizedBox(height: 4),
      Text(value, style: proValue(size: 12, color: Colors.white70)),
    ]),
  );
}
