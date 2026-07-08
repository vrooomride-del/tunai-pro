import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_measurement.dart';
import '../../../core/pro_measurement_store.dart';
import '../../../shared/pro_widgets.dart';

class ReportTab extends ConsumerWidget {
  final String projectId;
  const ReportTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(proProjectStoreProvider)
        .projects.where((p) => p.id == projectId).firstOrNull;
    final mStore = ref.watch(proMeasurementProvider);

    final completedSessions = mStore.sessions
        .where((s) => s.status == MeasurementSessionStatus.completed ||
                      s.status == MeasurementSessionStatus.reviewed)
        .toList();
    final allPoints = mStore.sessions.expand((s) => s.points).toList();
    final acceptedPoints = allPoints.where((p) => p.status == MeasurementPointStatus.accepted).toList();
    final lastSession = mStore.sessions.isNotEmpty
        ? mStore.sessions.reduce((a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b)
        : null;

    final readiness = _measurementReadiness(completedSessions.length, acceptedPoints.length);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.summarize_outlined, color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Tuning Report', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 6),
        Text('Export measurements, tuning decisions, and validation results.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        // Project summary
        if (project != null) ...[
          _ProjectSummaryCard(project: project),
          const SizedBox(height: 16),
        ],

        // Measurement summary
        _MeasurementSummaryCard(
          sessionCount: mStore.sessions.length,
          completedCount: completedSessions.length,
          pointCount: allPoints.length,
          acceptedCount: acceptedPoints.length,
          lastDate: lastSession?.updatedAt,
          readiness: readiness,
        ),
        const SizedBox(height: 16),

        // Report generation notice
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            const Icon(Icons.hourglass_empty_outlined, color: Colors.white24, size: 13),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Full report generation (PDF / JSON) will be available after the project is Verified. '
                'AI suggestions require expert verification before any report is signed.',
                style: proSubtitle(size: 11),
              ),
            ),
          ]),
        ),

        const SizedBox(height: 16),
        const Wrap(spacing: 10, runSpacing: 10, children: [
          _StatChipWidget(label: 'FORMAT', value: 'PDF / JSON'),
          _StatChipWidget(label: 'PAGES', value: '—'),
          _StatChipWidget(label: 'GENERATED', value: 'Never'),
          _StatChipWidget(label: 'SIGNED BY', value: '—'),
        ]),
      ]),
    );
  }

  String _measurementReadiness(int completed, int accepted) {
    if (completed == 0) return 'Not started';
    if (accepted == 0) return 'In progress — no accepted points';
    if (accepted < 2) return 'In progress — need more accepted points';
    return 'Ready for analysis';
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  final ProProject project;
  const _ProjectSummaryCard({required this.project});

  String _dateLabel(DateTime dt) {
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
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PROJECT SUMMARY', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 12),
      _row('Project', project.name),
      _row('Speaker', project.speakerModel),
      _row('Room', project.roomName),
      _row('DSP Target', project.dspTarget),
      _row('Sample Rate', project.sampleRateLabel),
      _row('Channel Config', project.channelConfig),
      _row('Profile Status', project.profileStatus.label),
      _row('Safety Status', project.safetyStatus.label),
      _row('Last Updated', _dateLabel(project.updatedAt)),
    ]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: proLabel(size: 10, spacing: 0.3))),
      Text(value, style: proValue(size: 11, color: Colors.white60)),
    ]),
  );
}

class _MeasurementSummaryCard extends StatelessWidget {
  final int sessionCount;
  final int completedCount;
  final int pointCount;
  final int acceptedCount;
  final DateTime? lastDate;
  final String readiness;

  const _MeasurementSummaryCard({
    required this.sessionCount,
    required this.completedCount,
    required this.pointCount,
    required this.acceptedCount,
    required this.lastDate,
    required this.readiness,
  });

  String _dateLabel(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.year}.${dt.month.toString().padLeft(2,'0')}.${dt.day.toString().padLeft(2,'0')}';
  }

  Color _readinessColor() {
    if (readiness == 'Ready for analysis') return kProGreen;
    if (readiness == 'Not started') return const Color(0xFF6B7280);
    return kProAmber;
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('MEASUREMENT SUMMARY', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 12),
      _row('Total sessions', '$sessionCount'),
      _row('Completed sessions', '$completedCount'),
      _row('Total points', '$pointCount'),
      _row('Accepted points', '$acceptedCount'),
      _row('Last measurement', _dateLabel(lastDate)),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(width: 110, child: Text('Readiness', style: proLabel(size: 10, spacing: 0.3))),
        ProStatusPill(label: readiness, color: _readinessColor()),
      ]),
    ]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: proLabel(size: 10, spacing: 0.3))),
      Text(value, style: proValue(size: 11, color: Colors.white60)),
    ]),
  );
}

class _StatChipWidget extends StatelessWidget {
  final String label;
  final String value;
  const _StatChipWidget({required this.label, required this.value});

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

