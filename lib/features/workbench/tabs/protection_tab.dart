// ── Protection Tab — Phase F ──────────────────────────────────────────────────
// AOS verification rule editor and issue viewer.
// No DSP write. No SafeLoad. No register addresses.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_protection_data.dart';
import '../../../core/pro_verification_engine.dart';
import '../../../shared/pro_widgets.dart';

class ProtectionTab extends ConsumerWidget {
  final String projectId;
  const ProtectionTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(proProjectStoreProvider);
    final project =
        store.projects.where((p) => p.id == projectId).firstOrNull;
    final protection =
        project?.protectionState ?? ProtectionProjectState.createDefault();

    Future<void> runVerification() async {
      if (project == null) return;
      final result = runProtectionVerification(
        acousticState: project.acousticState,
        tuningState: project.tuningState,
        protectionState: protection,
      );
      await ref
          .read(proProjectStoreProvider.notifier)
          .updateProtectionState(projectId, result);
    }

    Future<void> toggleRule(ProtectionRule rule) async {
      final updated = protection.copyWith(
        rules: protection.rules
            .map((r) => r.id == rule.id ? r.copyWith(enabled: !r.enabled) : r)
            .toList(),
      );
      await ref
          .read(proProjectStoreProvider.notifier)
          .updateProtectionState(projectId, updated);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.verified_user_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Protection / AOS Guard', style: proTitle(size: 16)),
          const Spacer(),
          Text('Rev ${protection.revision}',
              style: proLabel(size: 9, color: Colors.white24, spacing: 1)),
        ]),
        const SizedBox(height: 4),
        Text('Verification rules before optimization and export. '
            'Hardware protection will be added later.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        // Summary row
        _SummaryRow(protection: protection),
        const SizedBox(height: 12),

        // Run verification button
        GestureDetector(
          onTap: runVerification,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: kProAccent.withValues(alpha: 0.08),
              border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.play_arrow_outlined, color: kProAccent, size: 16),
              SizedBox(width: 8),
              Text('Run Verification',
                  style: TextStyle(
                      color: kProAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        // Rule list
        Text('PROTECTION RULES', style: proLabel(size: 9, spacing: 2)),
        const SizedBox(height: 8),
        ...protection.rules.map((rule) => _RuleCard(
              rule: rule,
              onToggle: () => toggleRule(rule),
            )),

        // Issue list
        if (protection.issues.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('VERIFICATION ISSUES (${protection.issues.length})',
              style: proLabel(size: 9, spacing: 2)),
          const SizedBox(height: 8),
          ...protection.issues.map((issue) => _IssueCard(issue: issue)),
        ] else if (protection.revision > 0) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: kProGreen.withValues(alpha: 0.06),
              border: Border.all(color: kProGreen.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_outline, color: kProGreen, size: 14),
              const SizedBox(width: 10),
              Text('No issues detected. Verification passed.',
                  style: proSubtitle(size: 11)),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final ProtectionProjectState protection;
  const _SummaryRow({required this.protection});

  Color _statusColor() => switch (protection.verificationStatus) {
    VerificationStatus.passed             => kProGreen,
    VerificationStatus.passedWithWarnings => kProAmber,
    VerificationStatus.failed             => kProRed,
    VerificationStatus.notReady           => const Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 10, children: [
    _SummaryChip(
      label: 'STATUS',
      value: protection.verificationStatus.label,
      color: _statusColor(),
    ),
    _SummaryChip(
      label: 'EXPORT',
      value: protection.exportLocked ? 'Locked' : 'Allowed',
      color: protection.exportLocked ? kProRed : kProGreen,
    ),
    _SummaryChip(
      label: 'WARNINGS',
      value: '${protection.warningCount}',
      color: protection.warningCount > 0 ? kProAmber : Colors.white38,
    ),
    _SummaryChip(
      label: 'CRITICAL',
      value: '${protection.criticalCount}',
      color: protection.criticalCount > 0 ? kProRed : Colors.white38,
    ),
  ]);
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 9, spacing: 1.5)),
      const SizedBox(height: 3),
      Text(value, style: proValue(size: 12, color: color)),
    ]),
  );
}

class _RuleCard extends StatelessWidget {
  final ProtectionRule rule;
  final VoidCallback onToggle;
  const _RuleCard({required this.rule, required this.onToggle});

  Color _severityColor() => switch (rule.severity) {
    ProtectionSeverity.critical => kProRed,
    ProtectionSeverity.warning  => kProAmber,
    ProtectionSeverity.info     => kProAccent,
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(children: [
      // Severity indicator
      Container(
        width: 3,
        height: 36,
        decoration: BoxDecoration(
          color: rule.enabled
              ? _severityColor().withValues(alpha: 0.7)
              : Colors.white12,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(rule.title,
                style: proTitle(size: 11,
                    color: rule.enabled ? Colors.white : Colors.white38)),
            const SizedBox(width: 8),
            ProStatusPill(
                label: rule.severity.label, color: _severityColor()),
            if (rule.threshold != 0) ...[
              const SizedBox(width: 6),
              Text(
                '${rule.threshold > 0 ? '>' : '<'} '
                '${rule.threshold.abs().toStringAsFixed(0)} ${rule.unit}',
                style: proLabel(size: 9, color: Colors.white38, spacing: 0.3),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Text(rule.description,
              style: proSubtitle(size: 9),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
      const SizedBox(width: 10),
      GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
                color: rule.enabled
                    ? kProAccent.withValues(alpha: 0.4)
                    : kProBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            rule.enabled ? 'ACTIVE' : 'BYPASS',
            style: TextStyle(
              color: rule.enabled ? kProAccent : Colors.white24,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    ]),
  );
}

class _IssueCard extends StatelessWidget {
  final VerificationIssue issue;
  const _IssueCard({required this.issue});

  Color _severityColor() => switch (issue.severity) {
    ProtectionSeverity.critical => kProRed,
    ProtectionSeverity.warning  => kProAmber,
    ProtectionSeverity.info     => kProAccent,
  };

  IconData _severityIcon() => switch (issue.severity) {
    ProtectionSeverity.critical => Icons.error_outline,
    ProtectionSeverity.warning  => Icons.warning_amber_outlined,
    ProtectionSeverity.info     => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: _severityColor().withValues(alpha: 0.05),
      border: Border.all(color: _severityColor().withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(_severityIcon(), color: _severityColor(), size: 14),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ProStatusPill(label: issue.severity.label, color: _severityColor()),
            if (issue.channelId != null) ...[
              const SizedBox(width: 6),
              Text('ch: ${issue.channelId}',
                  style: proLabel(size: 8, color: Colors.white24, spacing: 0.3)),
            ],
          ]),
          const SizedBox(height: 4),
          Text(issue.message, style: proSubtitle(size: 10)),
          if (issue.value != null && issue.threshold != null) ...[
            const SizedBox(height: 3),
            Text(
              'Value: ${issue.value!.toStringAsFixed(2)}  '
              'Threshold: ${issue.threshold!.toStringAsFixed(2)}',
              style: proLabel(size: 9, color: Colors.white24, spacing: 0.3),
            ),
          ],
        ]),
      ),
    ]),
  );
}
