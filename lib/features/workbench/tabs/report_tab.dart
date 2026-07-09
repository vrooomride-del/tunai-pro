import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_measurement.dart';
import '../../../core/pro_measurement_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../core/pro_protection_data.dart';
import '../../../core/pro_optimizer_data.dart';
import '../../../core/pro_export_data.dart';
import '../../../core/pro_dsp_target_data.dart';
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

        // Phase C: Driver / acoustic readiness
        if (project != null) ...[
          _AcousticReadinessCard(acoustic: project.acousticState),
          const SizedBox(height: 16),
        ],

        // Phase D: Tuning readiness
        if (project != null) ...[
          _TuningReadinessCard(
            tuning: project.tuningState,
            acoustic: project.acousticState,
          ),
          const SizedBox(height: 16),
        ],

        // Phase E: Channel control readiness
        if (project != null) ...[
          _ChannelControlReadinessCard(
            tuning: project.tuningState,
            acoustic: project.acousticState,
          ),
          const SizedBox(height: 16),
        ],

        // Phase G: Optimizer readiness
        if (project != null) ...[
          _OptimizerReadinessCard(optimizer: project.optimizerState),
          const SizedBox(height: 16),
        ],

        // Phase F: Protection / verification readiness
        if (project != null) ...[
          _ProtectionReadinessCard(protection: project.protectionState),
          const SizedBox(height: 16),
        ],

        // Phase H: Export readiness
        if (project != null) ...[
          _ExportReadinessCard(exportState: project.exportState),
          const SizedBox(height: 16),
        ],

        // Phase I: DSP implementation readiness
        if (project != null) ...[
          _DspImplementationReadinessCard(exportState: project.exportState),
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


// ── Phase C: Acoustic Readiness Card ─────────────────────────────────────────

class _AcousticReadinessCard extends StatelessWidget {
  final MeasurementProjectState acoustic;
  const _AcousticReadinessCard({required this.acoustic});

  Color _readinessColor() {
    if (acoustic.importedFrdCount == 0) return const Color(0xFF6B7280);
    if (acoustic.hasMissingMeasurements) return kProAmber;
    return kProGreen;
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
      Text('MEASUREMENT READINESS (PHASE C)', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 12),
      _row('Driver channels', '${acoustic.totalDrivers}'),
      _row('FRD imported', '${acoustic.importedFrdCount} / ${acoustic.totalDrivers}'),
      _row('ZMA imported', '${acoustic.importedZmaCount} / ${acoustic.totalDrivers}'),
      _row('Target curve', acoustic.targetCurve.selectedPreset.label),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(width: 130, child: Text('Ready for PEQ / XO', style: proLabel(size: 10, spacing: 0.3))),
        ProStatusPill(label: acoustic.readinessLabel, color: _readinessColor()),
      ]),
      if (acoustic.hasMissingMeasurements) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
          const SizedBox(width: 6),
          Text('Missing FRD data on ${acoustic.totalDrivers - acoustic.importedFrdCount} channel(s). '
               'Import before optimization.',
              style: proSubtitle(size: 10)),
        ]),
      ],
    ]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 130, child: Text(label, style: proLabel(size: 10, spacing: 0.3))),
      Text(value, style: proValue(size: 11, color: Colors.white60)),
    ]),
  );
}

// ── Phase D: Tuning Readiness Card ───────────────────────────────────────────

class _TuningReadinessCard extends StatelessWidget {
  final TuningProjectState tuning;
  final MeasurementProjectState acoustic;
  const _TuningReadinessCard({required this.tuning, required this.acoustic});

  Color _readinessColor() {
    final label = tuning.readinessLabel;
    if (label == 'Ready for optimization draft') return kProGreen;
    if (label == 'No tuning configured') return const Color(0xFF6B7280);
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
      Text('TUNING READINESS (PHASE D)', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 12),
      _row('PEQ channels', '${tuning.peqChannels.length}'),
      _row('Total PEQ bands', '${tuning.totalPeqBands}'),
      _row('Active PEQ bands', '${tuning.activePeqBands}'),
      _row('XO channels configured', '${tuning.configuredXoChannels}'),
      _row('HPF configured', '${tuning.hpfCount}'),
      _row('LPF configured', '${tuning.lpfCount}'),
      _row('Polarity inverted', '${tuning.polarityInvertedCount}'),
      _row('Manual changes', tuning.hasManualChanges ? 'Yes' : 'No'),
      _row('Tuning revision', '${tuning.tuningRevision}'),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(width: 130, child: Text('Tuning status', style: proLabel(size: 10, spacing: 0.3))),
        ProStatusPill(label: tuning.readinessLabel, color: _readinessColor()),
      ]),
      if (acoustic.hasMissingMeasurements) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'FRD data missing on ${acoustic.totalDrivers - acoustic.importedFrdCount} channel(s). '
              'Optimization accuracy is reduced without full measurement data.',
              style: proSubtitle(size: 10),
            ),
          ),
        ]),
      ],
    ]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 130, child: Text(label, style: proLabel(size: 10, spacing: 0.3))),
      Text(value, style: proValue(size: 11, color: Colors.white60)),
    ]),
  );
}

// ── Phase E: Channel Control Readiness Card ───────────────────────────────────

class _ChannelControlReadinessCard extends StatelessWidget {
  final TuningProjectState tuning;
  final MeasurementProjectState acoustic;
  const _ChannelControlReadinessCard({required this.tuning, required this.acoustic});

  Color _readinessColor() {
    final label = tuning.channelControlReadinessLabel;
    if (label == 'Ready for verification draft') return kProGreen;
    if (label == 'No channel controls') return const Color(0xFF6B7280);
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
      Text('CHANNEL CONTROL READINESS (PHASE E)', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 12),
      _row('Channel controls', '${tuning.channelControls.length}'),
      _row('Gain trim channels', '${tuning.totalGainTrimChannels}'),
      _row('Gain range',
          tuning.channelControls.isEmpty
              ? '—'
              : '${tuning.gainMinDb >= 0 ? '+' : ''}${tuning.gainMinDb.toStringAsFixed(1)} '
                'to ${tuning.gainMaxDb >= 0 ? '+' : ''}${tuning.gainMaxDb.toStringAsFixed(1)} dB'),
      _row('Muted channels', '${tuning.totalMutedChannels}'),
      _row('Solo channels', '${tuning.totalSoloChannels}'),
      _row('Delay channels', '${tuning.totalDelayChannels}'),
      _row('Max delay', tuning.maxDelayMs == 0.0
          ? '—'
          : '${tuning.maxDelayMs.toStringAsFixed(2)} ms'),
      _row('Polarity inverted', '${tuning.polarityInvertedCount}'),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(width: 130, child: Text('Control status', style: proLabel(size: 10, spacing: 0.3))),
        ProStatusPill(label: tuning.channelControlReadinessLabel, color: _readinessColor()),
      ]),
      if (tuning.totalSoloChannels > 0) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${tuning.totalSoloChannels} solo channel(s) active. '
              'Verify solo state before export.',
              style: proSubtitle(size: 10),
            ),
          ),
        ]),
      ],
      if (acoustic.hasMissingMeasurements) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'FRD data missing on ${acoustic.totalDrivers - acoustic.importedFrdCount} channel(s). '
              'Gain and delay decisions may be inaccurate without full measurements.',
              style: proSubtitle(size: 10),
            ),
          ),
        ]),
      ],
    ]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 130, child: Text(label, style: proLabel(size: 10, spacing: 0.3))),
      Text(value, style: proValue(size: 11, color: Colors.white60)),
    ]),
  );
}

// ── Phase F: Protection Readiness Card ───────────────────────────────────────

class _ProtectionReadinessCard extends StatelessWidget {
  final ProtectionProjectState protection;
  const _ProtectionReadinessCard({required this.protection});

  Color _statusColor() => switch (protection.verificationStatus) {
    VerificationStatus.passed             => kProGreen,
    VerificationStatus.passedWithWarnings => kProAmber,
    VerificationStatus.failed             => kProRed,
    VerificationStatus.notReady           => const Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) {
    final topIssues = protection.issues.take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PROTECTION / VERIFICATION (PHASE F)',
            style: proLabel(size: 9, spacing: 1.8)),
        const SizedBox(height: 12),
        _row('Active rules', '${protection.activeRuleCount}'),
        _row('Warnings', '${protection.warningCount}'),
        _row('Critical issues', '${protection.criticalCount}'),
        _row('Total issues', '${protection.triggeredIssueCount}'),
        _row('Export locked', protection.exportLocked ? 'Yes' : 'No'),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
              width: 130,
              child: Text('Verification', style: proLabel(size: 10, spacing: 0.3))),
          ProStatusPill(
              label: protection.verificationStatus.label,
              color: _statusColor()),
        ]),
        if (topIssues.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('TOP ISSUES', style: proLabel(size: 9, spacing: 1.5)),
          const SizedBox(height: 6),
          ...topIssues.map((issue) {
            final color = switch (issue.severity) {
              ProtectionSeverity.critical => kProRed,
              ProtectionSeverity.warning  => kProAmber,
              ProtectionSeverity.info     => kProAccent,
            };
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.circle, color: color, size: 6),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(issue.message,
                        style: proSubtitle(size: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis)),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 130, child: Text(label, style: proLabel(size: 10, spacing: 0.3))),
      Text(value, style: proValue(size: 11, color: Colors.white60)),
    ]),
  );
}

// ── Phase G: Optimizer Readiness Card ─────────────────────────────────────────

class _OptimizerReadinessCard extends StatelessWidget {
  final OptimizerProjectState optimizer;
  const _OptimizerReadinessCard({required this.optimizer});

  @override
  Widget build(BuildContext context) {
    final hasRuns = optimizer.runs.isNotEmpty;
    final activeRun = optimizer.activeRun;
    final accepted = optimizer.acceptedSuggestionCount;
    final pending = optimizer.pendingSuggestionCount;
    final staleWarning = accepted > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_outlined,
              color: kProAccent.withValues(alpha: 0.5), size: 13),
          const SizedBox(width: 8),
          Text('OPTIMIZER', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          Text(optimizer.readinessLabel,
              style: proLabel(size: 9, color: Colors.white38, spacing: 0.3)),
        ]),
        const SizedBox(height: 10),

        if (!hasRuns)
          Row(children: [
            const Icon(Icons.info_outline, color: Colors.white24, size: 12),
            const SizedBox(width: 8),
            Text('No optimizer runs yet. Open Optimizer tab to generate draft suggestions.',
                style: proSubtitle(size: 10)),
          ])
        else ...[
          Wrap(spacing: 10, runSpacing: 8, children: [
            _MiniChip(label: 'RUNS', value: '${optimizer.runs.length}'),
            _MiniChip(label: 'PENDING', value: '$pending',
                color: pending > 0 ? kProAmber : null),
            _MiniChip(label: 'ACCEPTED', value: '$accepted',
                color: accepted > 0 ? kProGreen : null),
            _MiniChip(label: 'REJECTED', value: '${optimizer.rejectedSuggestionCount}'),
            _MiniChip(label: 'LOCKED', value: '${optimizer.lockedSuggestionCount}'),
          ]),
          if (activeRun != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last run: ${_formatDate(activeRun.createdAt)}  ·  ${activeRun.summary}',
              style: proSubtitle(size: 9),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (staleWarning) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.warning_amber_outlined, color: kProAmber, size: 11),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Accepted suggestions may require re-verification in Protection tab.',
                  style: proSubtitle(size: 9, color: kProAmber.withValues(alpha: 0.8)),
                ),
              ),
            ]),
          ],
        ],
      ]),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class _MiniChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _MiniChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: kProBg,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 8, spacing: 1)),
      const SizedBox(height: 2),
      Text(value, style: proValue(size: 11, color: color ?? Colors.white54)),
    ]),
  );
}

// ── Phase H: Export Readiness Card ────────────────────────────────────────────

class _ExportReadinessCard extends StatelessWidget {
  final ExportProjectState exportState;
  const _ExportReadinessCard({required this.exportState});

  @override
  Widget build(BuildContext context) {
    final pkg = exportState.activePackage;
    final hasPackage = pkg != null;

    Color statusColor = switch (pkg?.status) {
      ExportStatus.draftReady => kProGreen,
      ExportStatus.blocked    => kProRed,
      ExportStatus.exported   => kProAccent,
      _                       => Colors.white38,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.upload_outlined,
              color: Color(0xFF4A9EFF), size: 13),
          const SizedBox(width: 8),
          Text('DSP EXPORT', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          Text(exportState.readinessLabel,
              style: proLabel(size: 9, color: Colors.white38, spacing: 0.3)),
        ]),
        const SizedBox(height: 10),

        if (!hasPackage)
          Row(children: [
            const Icon(Icons.info_outline, color: Colors.white24, size: 12),
            const SizedBox(width: 8),
            Text('No export package generated yet. Open Export tab.',
                style: proSubtitle(size: 10)),
          ])
        else ...[
          Wrap(spacing: 10, runSpacing: 8, children: [
            _ExportMiniChip(label: 'TARGET', value: exportState.selectedTarget.label),
            _ExportMiniChip(label: 'FORMAT', value: exportState.selectedFormat.label),
            _ExportMiniChip(label: 'PACKAGES', value: '${exportState.packageCount}'),
            _ExportMiniChip(
              label: 'STATUS',
              value: pkg.status.label,
              color: statusColor,
            ),
            _ExportMiniChip(label: 'BLOCKS', value: '${pkg.blockCount}'),
            _ExportMiniChip(
              label: 'WARNINGS',
              value: '${pkg.warningCount}',
              color: pkg.warningCount > 0 ? kProAmber : null,
            ),
          ]),
          if (pkg.blockedReason != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.block_outlined, color: kProRed, size: 11),
              const SizedBox(width: 6),
              Expanded(
                child: Text(pkg.blockedReason!,
                    style: proSubtitle(size: 9,
                        color: kProRed.withValues(alpha: 0.8))),
              ),
            ]),
          ],
        ],
      ]),
    );
  }
}

class _ExportMiniChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _ExportMiniChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: kProBg,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 8, spacing: 1)),
      const SizedBox(height: 2),
      Text(value, style: proValue(size: 11, color: color ?? Colors.white54)),
    ]),
  );
}

// ── Phase I: DSP Implementation Readiness Card ────────────────────────────────

class _DspImplementationReadinessCard extends StatelessWidget {
  final ExportProjectState exportState;
  const _DspImplementationReadinessCard({required this.exportState});

  @override
  Widget build(BuildContext context) {
    final pkg = exportState.activePackage;
    final profile = DspTargetProfile.forPlatform(exportState.selectedTarget);
    final isBlocked = pkg?.isBlocked ?? false;

    DspImplementationDraft? draft;
    if (pkg?.implementationDraftJson != null) {
      draft = DspImplementationDraft.fromJson(pkg!.implementationDraftJson!);
    }

    final readinessLabel = isBlocked
        ? 'Blocked by target capability'
        : draft?.readinessLabel ?? 'No export package';

    final calcCount = draft?.calculatedCount ?? 0;
    final phCount = draft?.placeholderCount ?? 0;
    final verCount = draft?.requiresVerificationCount ?? 0;
    final totalStages = draft?.stageCount ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.memory_outlined,
              color: Color(0xFF4A9EFF), size: 13),
          const SizedBox(width: 8),
          Text('DSP IMPLEMENTATION', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          Text(readinessLabel,
              style: proLabel(
                  size: 9,
                  color: isBlocked ? kProRed : Colors.white38,
                  spacing: 0.3)),
        ]),
        const SizedBox(height: 10),

        Wrap(spacing: 10, runSpacing: 8, children: [
          _DspImplChip(label: 'TARGET', value: profile.displayName),
          _DspImplChip(label: 'PRECISION', value: profile.precision.label),
          _DspImplChip(label: 'MAX CH', value: '${profile.maxChannels}'),
          _DspImplChip(label: 'MAX PEQ/CH',
              value: '${profile.maxPeqBandsPerChannel}'),
          _DspImplChip(label: 'SAMPLE RATES', value: profile.sampleRateLabel),
          if (draft != null) ...[
            _DspImplChip(label: 'TOTAL STAGES', value: '$totalStages'),
            if (calcCount > 0)
              _DspImplChip(label: 'CALCULATED', value: '$calcCount',
                  color: kProGreen),
            if (phCount > 0)
              _DspImplChip(label: 'PLACEHOLDER', value: '$phCount',
                  color: kProAmber),
            if (verCount > 0)
              _DspImplChip(label: 'NEEDS VERIFY', value: '$verCount',
                  color: kProRed),
          ],
        ]),

        if (draft != null && totalStages > 0) ...[
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.warning_amber_outlined,
                color: kProAmber, size: 11),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Coefficient draft does not imply hardware deployment readiness. '
                'Not ADAU fixed-point. No hardware address.',
                style: TextStyle(
                    fontSize: 9, color: kProAmber,
                    fontFamily: 'monospace'),
              ),
            ),
          ]),
        ],

        if (profile.warning != null) ...[
          const SizedBox(height: 6),
          Text(profile.warning!,
              style: proLabel(size: 9, color: Colors.white24, spacing: 0.2)),
        ],
      ]),
    );
  }
}

class _DspImplChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _DspImplChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: kProBg,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 8, spacing: 1)),
      const SizedBox(height: 2),
      Text(value, style: proValue(size: 11, color: color ?? Colors.white54)),
    ]),
  );
}
