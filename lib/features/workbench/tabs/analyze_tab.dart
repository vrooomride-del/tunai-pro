import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_measurement.dart';
import '../../../core/pro_measurement_store.dart';
import '../../../shared/pro_widgets.dart';

class AnalyzeTab extends ConsumerWidget {
  final String projectId;
  const AnalyzeTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(proProjectStoreProvider)
        .projects.where((p) => p.id == projectId).firstOrNull;
    final mStore = ref.watch(proMeasurementProvider);

    final completedSessions = mStore.sessions
        .where((s) => s.status == MeasurementSessionStatus.completed ||
                      s.status == MeasurementSessionStatus.reviewed)
        .toList();
    final acceptedPoints = mStore.sessions
        .expand((s) => s.points)
        .where((p) => p.status == MeasurementPointStatus.accepted)
        .toList();
    final hasData = completedSessions.isNotEmpty || acceptedPoints.isNotEmpty;
    final lastSession = mStore.sessions.isNotEmpty
        ? mStore.sessions.reduce((a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bar_chart_outlined, color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Acoustic Analysis', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 6),
        Text('Review detected acoustic issues before tuning.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        if (!hasData) ...[
          // ── No measurement data ──────────────────────────────────────────
          _NoDataBanner(projectName: project?.name ?? '—'),
          const SizedBox(height: 20),
          Wrap(spacing: 10, runSpacing: 10, children: const [
            ProQuickStat('SESSIONS', '0'),
            ProQuickStat('ACCEPTED POINTS', '0'),
            ProQuickStat('LAST MEASUREMENT', '—'),
            ProQuickStat('CONFIDENCE', '—'),
          ].map((s) => _StatChip(stat: s)).toList()),
        ] else ...[
          // ── Measurement summary ──────────────────────────────────────────
          _MeasurementSummaryCard(
            sessionCount: mStore.sessions.length,
            completedCount: completedSessions.length,
            acceptedCount: acceptedPoints.length,
            lastDate: lastSession?.updatedAt,
          ),
          const SizedBox(height: 20),

          // ── Placeholder analysis cards ───────────────────────────────────
          Text('PRELIMINARY ANALYSIS', style: proLabel(size: 9, spacing: 1.8)),
          const SizedBox(height: 10),
          _AnalysisCard(
            title: 'Frequency Response Readiness',
            subtitle: 'Sufficient measurement points collected for FR analysis.',
            icon: Icons.show_chart_outlined,
            status: acceptedPoints.length >= 2 ? 'Ready' : 'Partial',
            statusColor: acceptedPoints.length >= 2 ? kProGreen : kProAmber,
            placeholder: 'FR analysis engine will be connected in a later phase.',
          ),
          const SizedBox(height: 10),
          const _AnalysisCard(
            title: 'Room Influence',
            subtitle: 'Room acoustic fingerprint based on captured measurement positions.',
            icon: Icons.home_outlined,
            status: 'Placeholder',
            statusColor: Color(0xFF6B7280),
            placeholder: 'Room analysis engine will be connected in a later phase.',
          ),
          const SizedBox(height: 10),
          const _AnalysisCard(
            title: 'Channel Balance',
            subtitle: 'Left / Right level and timing correlation across positions.',
            icon: Icons.balance_outlined,
            status: 'Placeholder',
            statusColor: Color(0xFF6B7280),
            placeholder: 'Channel analysis engine will be connected in a later phase.',
          ),
          const SizedBox(height: 10),
          _AnalysisCard(
            title: 'Data Confidence',
            subtitle: 'Confidence score based on measurement count and quality.',
            icon: Icons.verified_outlined,
            status: acceptedPoints.isNotEmpty ? 'Low — add more points' : 'No data',
            statusColor: acceptedPoints.isNotEmpty ? kProAmber : kProRed,
            placeholder: 'More accepted measurement points improve analysis confidence.',
          ),

          const SizedBox(height: 20),
          _PlaceholderNotice(),
        ],
      ]),
    );
  }
}

class _NoDataBanner extends StatelessWidget {
  final String projectName;
  const _NoDataBanner({required this.projectName});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: kProAmber.withValues(alpha: 0.05),
      border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.warning_amber_outlined, color: kProAmber, size: 14),
        const SizedBox(width: 8),
        Text('Measurements Required', style: proTitle(size: 13, color: kProAmber)),
      ]),
      const SizedBox(height: 8),
      Text(
        'Complete at least one measurement session before acoustic analysis.',
        style: proSubtitle(size: 12),
      ),
      const SizedBox(height: 6),
      Text(
        'Go to the Measure tab to create a session, add measurement points, and simulate or capture acoustic data.',
        style: proSubtitle(size: 11),
      ),
    ]),
  );
}

class _MeasurementSummaryCard extends StatelessWidget {
  final int sessionCount;
  final int completedCount;
  final int acceptedCount;
  final DateTime? lastDate;
  const _MeasurementSummaryCard({
    required this.sessionCount,
    required this.completedCount,
    required this.acceptedCount,
    required this.lastDate,
  });

  String _dateLabel(DateTime? dt) {
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.year}.${dt.month.toString().padLeft(2,'0')}.${dt.day.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProGreen.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.check_circle_outline, color: kProGreen, size: 14),
        const SizedBox(width: 8),
        Text('Measurement Data Available', style: proTitle(size: 12, color: kProGreen)),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _StatChip(stat: ProQuickStat('SESSIONS', '$sessionCount')),
        _StatChip(stat: ProQuickStat('COMPLETED', '$completedCount')),
        _StatChip(stat: ProQuickStat('ACCEPTED POINTS', '$acceptedCount')),
        _StatChip(stat: ProQuickStat('LAST UPDATED', _dateLabel(lastDate))),
      ]),
    ]),
  );
}

class _AnalysisCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String status;
  final Color statusColor;
  final String placeholder;
  const _AnalysisCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.statusColor,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: kProAccent.withValues(alpha: 0.5), size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: proTitle(size: 12))),
        ProStatusPill(label: status, color: statusColor),
      ]),
      const SizedBox(height: 6),
      Text(subtitle, style: proSubtitle(size: 11)),
      const SizedBox(height: 8),
      // Placeholder graph area
      Container(
        height: 60,
        decoration: BoxDecoration(
          color: kProPanel,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Center(
          child: Text(placeholder, style: proLabel(size: 9, color: Colors.white24, spacing: 0.3),
              textAlign: TextAlign.center),
        ),
      ),
    ]),
  );
}

class _PlaceholderNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(children: [
      const Icon(Icons.hourglass_empty_outlined, color: Colors.white24, size: 13),
      const SizedBox(width: 10),
      Expanded(child: Text(
        'Full acoustic analysis engine will be connected in a later phase. '
        'AI suggestions will require expert verification before tuning proceeds.',
        style: proSubtitle(size: 10),
      )),
    ]),
  );
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
      Text(stat.value, style: proValue(size: 12, color: Colors.white70)),
    ]),
  );
}
