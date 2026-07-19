import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_measurement.dart';
import '../../../core/pro_measurement_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../core/pro_protection_data.dart';
import '../../../core/pro_optimizer_data.dart';
import '../../../core/pro_tuning_report_data.dart';
import '../../../core/pro_tuning_report_json.dart';
import '../../../core/pro_export_data.dart';
import '../../../core/pro_dsp_target_data.dart';
import '../../../core/pro_simulation_data.dart';
import '../../../core/pro_impedance_analysis.dart';
import '../../../core/pro_dsp_address_registry.dart';
import '../../../core/pro_sigma_mapping_data.dart';
import '../../../core/pro_adau1466_3way_address_map_embedded.dart';
import '../../../core/pro_address_validation_data.dart';
import '../../../core/pro_hardware_connection_data.dart';
import '../../../core/pro_deploy_package_data.dart';
import '../../../shared/pro_widgets.dart';
import 'pro_hardware_mvp_status_card.dart';

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

        // Unified tuning summary — rendered from a single frozen snapshot.
        // The same snapshot backs the JSON export action below.
        if (project != null) ...[
          Builder(builder: (context) {
            final report = buildTuningReport(project, mStore);
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReportExportBar(report: report),
                  const SizedBox(height: 12),
                  _TuningSummaryCard(report: report),
                ]);
          }),
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

        // Phase M: Measurement data readiness
        if (project != null) ...[
          _MeasurementDataCard(acoustic: project.acousticState),
          const SizedBox(height: 16),
        ],

        // Phase L: Simulation readiness
        if (project != null) ...[
          _SimulationReadinessCard(simState: project.simulationState),
          const SizedBox(height: 16),
        ],

        // Phase O: Impedance / load readiness
        if (project != null) ...[
          _ImpedanceReadinessCard(acoustic: project.acousticState),
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

          _DspMappingReadinessCard(exportState: project.exportState),
          const SizedBox(height: 16),

          _HardwareReadinessCard(hardwareState: project.hardwareState),
          const SizedBox(height: 16),

          _DeployReadinessCard(deployState: project.deployState),
          const SizedBox(height: 16),

          const _DspAddressMapReadinessCard(),
          const SizedBox(height: 16),

          _AddressValidationReadinessCard(
              validationState: project.addressValidationState),
          const SizedBox(height: 16),

          _TransportReadinessCard(
              connectionState: project.hardwareState.connectionState),
          const SizedBox(height: 16),

          const _TransportCommandReadinessCard(),
          const SizedBox(height: 16),

          const _UsbiExecutorReadinessCard(),
          const SizedBox(height: 16),
        ],

        // Hardware MVP status
        const HardwareMvpStatusCard(),
        const SizedBox(height: 16),

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

// ── Report Export Bar ─────────────────────────────────────────────────────────
// Generates a JSON artifact from the frozen TuningReportData snapshot and shows
// it in a copyable dialog. Presentation only — the serializer is pure and no
// file is written to disk (clipboard copy only).

class _ReportExportBar extends StatelessWidget {
  final TuningReportData report;
  const _ReportExportBar({required this.report});

  String _timestamp(DateTime dt) {
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  void _showJson(BuildContext context) {
    final json = encodeTuningReportJson(report);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kProSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: kProBorder),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    const Icon(Icons.data_object_outlined, color: kProAccent, size: 15),
                    const SizedBox(width: 8),
                    Text('TUNING REPORT · JSON', style: proLabel(size: 10, spacing: 1.5)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                      'Generated ${_timestamp(report.generatedAt)}  ·  schema v${report.schemaVersion}  ·  ${tuningReportFileName(report)}',
                      style: proSubtitle(size: 10, color: Colors.white38)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kProBg,
                        border: Border.all(color: kProBorder),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          json,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11, color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy_outlined, size: 14, color: kProAccent),
                      label: Text('Copy JSON',
                          style: proLabel(size: 10, color: kProAccent, spacing: 0.5)),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: json));
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('Report JSON copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ));
                        }
                      },
                    ),
                  ]),
                ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.description_outlined, color: Colors.white38, size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('REPORT ARTIFACT', style: proLabel(size: 9, spacing: 1.5)),
              const SizedBox(height: 2),
              Text(
                  'JSON · schema v${report.schemaVersion} · generated ${_timestamp(report.generatedAt)}',
                  style: proSubtitle(size: 10, color: Colors.white38)),
            ]),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.data_object_outlined, size: 14, color: kProAccent),
            label: Text('Generate JSON',
                style: proLabel(size: 10, color: kProAccent, spacing: 0.5)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kProBorder),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onPressed: () => _showJson(context),
          ),
        ]),
      );
}

// ── Unified Tuning Summary ────────────────────────────────────────────────────
// Renders entirely from a frozen TuningReportData snapshot (buildTuningReport).
// The same snapshot model is intended to back the report UI, future JSON export,
// and future PDF export — a single source of truth. Presentation only.

class _TuningSummaryCard extends StatelessWidget {
  final TuningReportData report;
  const _TuningSummaryCard({required this.report});

  Color _phaseColor(String status) => switch (status) {
        'good' => kProGreen,
        'check' => kProAmber,
        'misalign' => kProRed,
        _ => Colors.white38,
      };

  Color _confidenceColor(String confidence) => switch (confidence) {
        'high' => kProGreen,
        'medium' => kProAmber,
        'low' => Colors.white38,
        _ => Colors.white38,
      };

  String _timestamp(DateTime dt) {
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final m = report.measurement;
    final total = m.totalDrivers;
    final imported = m.frdImportedCount;
    final phase = report.phaseAlignment;
    final opt = report.optimizer;

    final frdLabel = total == 0
        ? 'No drivers'
        : imported >= total
            ? 'Complete'
            : imported == 0
                ? 'None'
                : 'Partial';
    final frdColor = total == 0
        ? Colors.white38
        : imported >= total
            ? kProGreen
            : imported == 0
                ? kProRed
                : kProAmber;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.tune_outlined, color: kProAccent.withValues(alpha: 0.6), size: 14),
          const SizedBox(width: 8),
          Text('TUNING SUMMARY', style: proLabel(size: 9, spacing: 1.8)),
          const Spacer(),
          Text('SIMULATION', style: proLabel(size: 8, color: Colors.white24)),
        ]),
        const SizedBox(height: 4),
        Text('Generated ${_timestamp(report.generatedAt)}  ·  snapshot v${report.schemaVersion}',
            style: proSubtitle(size: 9, color: Colors.white30)),
        const SizedBox(height: 12),

        // 1. Target curve
        _section('TARGET CURVE'),
        _row('Selected preset', report.targetCurve.presetLabel),

        // 2. Measurement
        _section('MEASUREMENT'),
        Row(children: [
          SizedBox(width: 150, child: Text('FRD availability', style: proLabel(size: 10, spacing: 0.3))),
          Text('$imported / $total drivers',
              style: proValue(size: 11, color: Colors.white60)),
          const SizedBox(width: 8),
          ProStatusPill(label: frdLabel, color: frdColor),
        ]),
        if (m.hasMissingMeasurements)
          _row('Missing measurements', '${total - imported} channel(s)'),
        _row('Measurement sessions',
            '${m.completedSessionCount} / ${m.sessionCount} completed'),
        _row('Accepted points', '${m.acceptedPoints} / ${m.totalPoints}'),

        // 3. Crossover
        _section('CROSSOVER'),
        _row('XO channels configured', '${report.crossover.configuredChannels}'),
        _row('HPF / LPF',
            '${report.crossover.hpfCount} / ${report.crossover.lpfCount}'),
        _row('Polarity inverted', '${report.crossover.polarityInvertedCount}'),

        // 3b. PEQ
        _section('PEQ'),
        _row('Active / total bands',
            '${report.peq.activeBands} / ${report.peq.totalBands}'),
        _row('PEQ channels', '${report.peq.channelCount}'),

        // 4. Phase alignment
        _section('PHASE ALIGNMENT'),
        if (phase.pairs.isEmpty)
          Text('No crossover pairs within ±1 octave to analyze.',
              style: proSubtitle(size: 10))
        else
          ...phase.pairs.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(
                    width: 150,
                    child: Text('${p.lowLabel} × ${p.highLabel}',
                        style: proLabel(size: 10, spacing: 0.3),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${p.crossoverHz.round()} Hz  ·  Δ${p.phaseDiffDeg.round()}°',
                      style: proValue(size: 11, color: Colors.white60)),
                  const SizedBox(width: 8),
                  ProStatusPill(
                      label: p.status.toUpperCase(), color: _phaseColor(p.status)),
                ]),
              )),
        if (phase.electricalOnly) ...[
          const SizedBox(height: 4),
          Text('Electrical phase simulation — measured acoustic phase not included.',
              style: proSubtitle(size: 9, color: Colors.white30)),
        ],

        // 5. Optimizer result (target-match projection)
        _section('OPTIMIZER RESULT'),
        if (opt.beforeScore == null || opt.afterScore == null)
          Text('No drivers available for target-match projection.',
              style: proSubtitle(size: 10))
        else ...[
          Wrap(spacing: 10, runSpacing: 8, children: [
            _MiniChip(label: 'BEFORE', value: '${opt.beforeScore!.round()}'),
            _MiniChip(label: 'AFTER', value: '${opt.afterScore!.round()}', color: kProGreen),
            _MiniChip(
                label: 'IMPROVEMENT',
                value: '${(opt.improvement ?? 0) >= 0 ? '+' : ''}${(opt.improvement ?? 0).round()}',
                color: (opt.improvement ?? 0) > 0.5
                    ? kProGreen
                    : ((opt.improvement ?? 0) < -0.5 ? kProAmber : null)),
            if (opt.confidence != null)
              _MiniChip(
                  label: 'CONFIDENCE',
                  value: opt.confidence!.toUpperCase(),
                  color: _confidenceColor(opt.confidence!)),
          ]),
          if (opt.simulatedProjection) ...[
            const SizedBox(height: 4),
            Text('Simulated target match (electrical + measured magnitude). '
                'Not a measured verification.',
                style: proSubtitle(size: 9, color: Colors.white30)),
          ],
        ],

        // Snapshot warnings
        if (report.warnings.isNotEmpty) ...[
          _section('WARNINGS'),
          ...report.warnings.map((w) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
                  const SizedBox(width: 6),
                  Expanded(child: Text(w, style: proSubtitle(size: 10))),
                ]),
              )),
        ],
      ]),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(label, style: proLabel(size: 9, color: kProAccent, spacing: 1.5)),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 150, child: Text(label, style: proLabel(size: 10, spacing: 0.3))),
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
      Text('MEASUREMENT READINESS', style: proLabel(size: 9, spacing: 1.8)),
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

// ── Phase M: Measurement Data Readiness Card ──────────────────────────────────

class _MeasurementDataCard extends StatelessWidget {
  final MeasurementProjectState acoustic;
  const _MeasurementDataCard({required this.acoustic});

  String get _readinessLabel {
    final frd = acoustic.parsedFrdCount;
    final zma = acoustic.parsedZmaCount;
    final total = acoustic.totalDrivers;
    if (frd == 0 && zma == 0) return 'No measurement data';
    if (frd < total) return 'Partial FRD data ($frd/$total drivers)';
    if (zma == 0) return 'FRD data ready';
    if (acoustic.missingPhaseCount > 0) return 'Measurement data has warnings';
    return 'FRD/ZMA data ready';
  }

  Color get _readinessColor {
    if (acoustic.parsedFrdCount == 0) return const Color(0xFF6B7280);
    if (acoustic.parsedFrdCount < acoustic.totalDrivers) return kProAmber;
    if (acoustic.missingPhaseCount > 0) return kProAmber;
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
      Text('MEASUREMENT DATA', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 12),
      _row('Driver channels', '${acoustic.totalDrivers}'),
      _row('FRD parsed', '${acoustic.parsedFrdCount} / ${acoustic.totalDrivers}'),
      _row('ZMA parsed', '${acoustic.parsedZmaCount} / ${acoustic.totalDrivers}'),
      _row('FRD with phase', '${acoustic.parsedFrdWithPhaseCount} / ${acoustic.parsedFrdCount}'),
      _row('Missing phase', '${acoustic.missingPhaseCount}'),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(width: 150, child: Text('Data readiness', style: proLabel(size: 10, spacing: 0.3))),
        ProStatusPill(label: _readinessLabel, color: _readinessColor),
      ]),
      if (acoustic.parsedFrdCount == 0) ...[
        const SizedBox(height: 8),
        const Row(children: [
          Icon(Icons.info_outline, color: Colors.white38, size: 12),
          SizedBox(width: 6),
          Expanded(
              child: Text(
            'No FRD data imported. Use the Import tab to paste and parse FRD files.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          )),
        ]),
      ] else if (acoustic.missingPhaseCount > 0) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
          const SizedBox(width: 6),
          Expanded(
              child: Text(
            '${acoustic.missingPhaseCount} driver(s) have FRD without phase data. '
            'Phase-aware summation will not be possible until phase data is available.',
            style: proSubtitle(size: 10),
          )),
        ]),
      ],
    ]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 150, child: Text(label, style: proLabel(size: 10, spacing: 0.3))),
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
      Text('TUNING READINESS', style: proLabel(size: 9, spacing: 1.8)),
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
      Text('CHANNEL CONTROL READINESS', style: proLabel(size: 9, spacing: 1.8)),
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

// ── Phase O: Impedance / Load Readiness Card ─────────────────────────────────

class _ImpedanceReadinessCard extends StatelessWidget {
  final MeasurementProjectState acoustic;
  const _ImpedanceReadinessCard({required this.acoustic});

  @override
  Widget build(BuildContext context) {
    final result = ProImpedanceAnalyzer.analyze(acousticState: acoustic);

    Color riskColor(ImpedanceRiskLevel risk) => switch (risk) {
      ImpedanceRiskLevel.critical => kProRed,
      ImpedanceRiskLevel.high     => kProRed.withValues(alpha: 0.8),
      ImpedanceRiskLevel.medium   => kProAmber,
      ImpedanceRiskLevel.low      => kProGreen,
      ImpedanceRiskLevel.none     => kProGreen,
      ImpedanceRiskLevel.unknown  => Colors.white38,
    };

    // Min impedance across project
    final zmaSummaries = result.summaries.where((s) => s.hasZma && s.minImpedanceOhm != null);
    double? projectMinZ;
    for (final s in zmaSummaries) {
      if (projectMinZ == null || s.minImpedanceOhm! < projectMinZ) {
        projectMinZ = s.minImpedanceOhm;
      }
    }

    // Worst phase angle
    double? worstPhase;
    for (final s in result.summaries) {
      if (s.maxPhaseAngleDeg != null) {
        if (worstPhase == null || s.maxPhaseAngleDeg! > worstPhase) {
          worstPhase = s.maxPhaseAngleDeg;
        }
      }
    }

    final zmaCount = acoustic.parsedZmaCount;
    final missingZma = result.missingZmaCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('IMPEDANCE / LOAD READINESS', style: proLabel(size: 9, spacing: 1.8)),
          const Spacer(),
          ProStatusPill(
            label: result.readinessLabel,
            color: riskColor(result.overallRisk),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, children: [
          _ReportChip(
            label: 'ZMA PARSED',
            value: '$zmaCount',
            color: zmaCount > 0 ? kProGreen : Colors.white38,
          ),
          _ReportChip(
            label: 'MISSING ZMA',
            value: '$missingZma',
            color: missingZma > 0 ? kProAmber : Colors.white38,
          ),
          if (projectMinZ != null)
            _ReportChip(
              label: 'MIN IMPEDANCE',
              value: '${projectMinZ.toStringAsFixed(1)} Ω',
              color: projectMinZ < 2.0
                  ? kProRed
                  : projectMinZ < 4.0
                      ? kProAmber
                      : kProGreen,
            ),
          if (worstPhase != null)
            _ReportChip(
              label: 'WORST ∠',
              value: '${worstPhase.toStringAsFixed(1)}°',
              color: worstPhase >= 60 ? kProAmber : Colors.white60,
            ),
          _ReportChip(
            label: 'OVERALL RISK',
            value: result.overallRisk.label,
            color: riskColor(result.overallRisk),
          ),
          _ReportChip(
            label: 'CRITICAL',
            value: '${result.criticalCount}',
            color: result.hasCritical ? kProRed : Colors.white38,
          ),
          _ReportChip(
            label: 'WARNINGS',
            value: '${result.warningCount}',
            color: result.hasWarnings ? kProAmber : Colors.white38,
          ),
        ]),
        const SizedBox(height: 8),
        const Row(children: [
          Icon(Icons.info_outline, color: Colors.white24, size: 11),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Advisory load analysis. Not a certified amplifier safety calculation. '
              'Hardware verification required.',
              style: TextStyle(
                  fontSize: 9, color: Colors.white24, fontFamily: 'monospace'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ReportChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ReportChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: kProBg,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 8, spacing: 1)),
      const SizedBox(height: 2),
      Text(value, style: proValue(size: 10, color: color)),
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
        Text('PROTECTION / VERIFICATION',
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

    final calcCount = draft?.calculatedCount ?? 0;
    final phCount = draft?.placeholderCount ?? 0;
    final verCount = draft?.requiresVerificationCount ?? 0;
    final totalStages = draft?.stageCount ?? 0;

    final xoStages = draft?.biquadStages
        .where((s) => s.title.contains('HPF') || s.title.contains('LPF'))
        .length ?? 0;
    final topologyWarningCount = draft?.warnings
        .where((w) => w.toLowerCase().contains('topolog') ||
            w.toLowerCase().contains('cascade') ||
            w.toLowerCase().contains('lr') ||
            w.toLowerCase().contains('butterworth'))
        .length ?? 0;

    String readinessLabel;
    if (isBlocked) {
      readinessLabel = 'Blocked by target capability';
    } else if (draft == null || totalStages == 0) {
      readinessLabel = 'No export package';
    } else if (verCount > 0) {
      readinessLabel = xoStages > 0
          ? 'Topology requires verification'
          : 'Some coefficients require verification';
    } else if (phCount > 0) {
      readinessLabel = 'Biquad placeholders only';
    } else if (xoStages > 0 && calcCount > 0) {
      readinessLabel = 'XO cascade draft generated';
    } else if (calcCount > 0) {
      readinessLabel = 'Draft coefficients generated';
    } else {
      readinessLabel = draft.readinessLabel;
    }

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
            if (xoStages > 0)
              _DspImplChip(label: 'XO CASCADE', value: '$xoStages',
                  color: const Color(0xFF4A9EFF)),
            if (calcCount > 0)
              _DspImplChip(label: 'CALCULATED', value: '$calcCount',
                  color: kProGreen),
            if (phCount > 0)
              _DspImplChip(label: 'PLACEHOLDER', value: '$phCount',
                  color: kProAmber),
            if (verCount > 0)
              _DspImplChip(label: 'NEEDS VERIFY', value: '$verCount',
                  color: kProRed),
            if (topologyWarningCount > 0)
              _DspImplChip(label: 'TOPO WARN', value: '$topologyWarningCount',
                  color: kProAmber),
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
          if (xoStages > 0) ...[
            const SizedBox(height: 4),
            const Row(children: [
              Icon(Icons.filter_alt_outlined,
                  color: Colors.white38, size: 11),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Crossover topology draft does not imply final '
                  'acoustic summation verification.',
                  style: TextStyle(
                      fontSize: 9, color: Colors.white38,
                      fontFamily: 'monospace'),
                ),
              ),
            ]),
          ],
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

// ── Phase L: Simulation Readiness Card ───────────────────────────────────────

class _SimulationReadinessCard extends StatelessWidget {
  final SimulationProjectState simState;
  const _SimulationReadinessCard({required this.simState});

  @override
  Widget build(BuildContext context) {
    final run = simState.activeRun;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.show_chart_outlined,
              color: Color(0xFF4A9EFF), size: 13),
          const SizedBox(width: 8),
          Text('SIMULATION', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          Text(simState.readinessLabel,
              style: proLabel(
                  size: 9, color: Colors.white38, spacing: 0.3)),
        ]),
        const SizedBox(height: 10),

        Wrap(spacing: 10, runSpacing: 8, children: [
          _DspImplChip(
            label: 'RUNS',
            value: '${simState.runCount}',
          ),
          _DspImplChip(
            label: 'ACTIVE CURVES',
            value: '${simState.activeCurveCount}',
          ),
          _DspImplChip(
            label: 'WARNINGS',
            value: '${simState.warningCount}',
            color: simState.warningCount > 0 ? kProAmber : null,
          ),
          if (run != null) ...[
            _DspImplChip(
              label: 'TARGET',
              value: run.hasTargetCurve ? 'Yes' : 'No',
              color: run.hasTargetCurve ? kProGreen : Colors.white38,
            ),
            _DspImplChip(
              label: 'SUMMED',
              value: run.hasSummedCurve ? 'Draft' : 'No',
              color: run.hasSummedCurve ? kProAmber : Colors.white38,
            ),
            () {
              final importedCount = run.curves
                  .where((c) =>
                      c.type == SimulationCurveType.driver &&
                      c.status == SimulationCurveStatus.imported)
                  .length;
              final placeholderCount = run.curves
                  .where((c) =>
                      c.type == SimulationCurveType.driver &&
                      c.status != SimulationCurveStatus.imported)
                  .length;
              return Row(mainAxisSize: MainAxisSize.min, children: [
                _DspImplChip(
                  label: 'FRD CURVES',
                  value: '$importedCount',
                  color: importedCount > 0 ? kProGreen : Colors.white38,
                ),
                const SizedBox(width: 10),
                _DspImplChip(
                  label: 'PLACEHOLDER',
                  value: '$placeholderCount',
                  color: placeholderCount > 0 ? kProAmber : kProGreen,
                ),
              ]);
            }(),
          ],
        ]),

        const SizedBox(height: 10),
        const Row(children: [
          Icon(Icons.info_outline, color: Colors.white24, size: 11),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Simulation is draft-only. Measurement verification remains required. '
              'Not final acoustic summation.',
              style: TextStyle(
                  fontSize: 9, color: Colors.white38,
                  fontFamily: 'monospace'),
            ),
          ),
        ]),

        if (run == null) ...[
          const SizedBox(height: 6),
          const Row(children: [
            Icon(Icons.warning_amber_outlined, color: kProAmber, size: 11),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'No simulation draft generated before export.',
                style: TextStyle(fontSize: 9, color: kProAmber),
              ),
            ),
          ]),
        ],

        if (run != null &&
            run.curves.any((c) =>
                c.type == SimulationCurveType.driver &&
                c.status != SimulationCurveStatus.imported)) ...[
          const SizedBox(height: 6),
          const Row(children: [
            Icon(Icons.warning_amber_outlined,
                color: kProAmber, size: 11),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Simulation still uses placeholder driver curves. '
                'Import FRD data and regenerate for measured-data simulation.',
                style: TextStyle(fontSize: 9, color: kProAmber),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ── Phase P: DSP Mapping Readiness Card ──────────────────────────────────────

class _DspMappingReadinessCard extends StatelessWidget {
  final ExportProjectState exportState;
  const _DspMappingReadinessCard({required this.exportState});

  @override
  Widget build(BuildContext context) {
    final platform = exportState.selectedTarget;
    final isAdau = platform == DspTargetPlatform.adau1466 ||
        platform == DspTargetPlatform.adau1701;

    final registry = DspAddressRegistry.createDefault();
    final platformAddresses = registry.addressesForPlatform(platform);
    final verifiedCount = platformAddresses
        .where((a) => a.verificationStatus == DspAddressVerificationStatus.verified)
        .length;

    final hasVerifiedMV = registry.hasVerifiedMasterVolume1466 &&
        platform == DspTargetPlatform.adau1466;

    // Derive mapping reference from active package if available
    final activePkg = exportState.activePackage;
    SigmaMappingReference? mappingRef;
    if (activePkg?.sigmaMappingReferenceJson != null) {
      mappingRef = SigmaMappingReference.fromJson(
          activePkg!.sigmaMappingReferenceJson!);
    }

    final requiresCaptureCount = mappingRef?.requiresCaptureCount ?? 0;

    String readinessLabel;
    if (!isAdau) {
      readinessLabel = 'Simulation target — no DSP mapping required';
    } else if (hasVerifiedMV && (mappingRef?.verifiedMappedCount ?? 0) > 0) {
      readinessLabel = 'Verified master volume mapping available';
    } else if (requiresCaptureCount > 0) {
      readinessLabel = 'Mapping requires SigmaStudio capture';
    } else {
      readinessLabel = 'Mapping requires SigmaStudio capture';
    }

    final hasFPDraft = activePkg?.fixedPointDraftJson != null;
    final fpStatus = hasFPDraft ? 'Fixed-point draft requires verification' : 'Not generated';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.hub_outlined, color: Color(0xFFA78BFA), size: 13),
          const SizedBox(width: 8),
          Text('DSP MAPPING READINESS', style: proLabel(size: 9, spacing: 2)),
        ]),
        const SizedBox(height: 10),
        _ReportChip(
          label: 'DSP TARGET',
          value: platform.label,
          color: Colors.white54,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'VERIFIED ADDRESSES',
          value: '$verifiedCount address(es) on ${platform.label}',
          color: verifiedCount > 0 ? const Color(0xFF4A9EFF) : Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'KNOWN MASTER VOLUME (ADAU1466)',
          value: hasVerifiedMV ? 'Yes — 0x67 (L), 0x64 (R)' : 'N/A',
          color: hasVerifiedMV ? const Color(0xFF4A9EFF) : Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'MAPPINGS REQUIRING CAPTURE',
          value: requiresCaptureCount > 0 ? '$requiresCaptureCount block(s)' : 'None',
          color: requiresCaptureCount > 0 ? kProAmber : Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'FIXED-POINT DRAFT',
          value: fpStatus,
          color: hasFPDraft ? const Color(0xFFA78BFA) : Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'READINESS',
          value: readinessLabel,
          color: Colors.white54,
        ),
        const SizedBox(height: 8),
        Text(
          'Verified addresses are references only. Hardware write remains disabled.',
          style: proSubtitle(size: 9),
        ),
      ]),
    );
  }
}

// ── Phase Q: Hardware Readiness Card ─────────────────────────────────────────

class _HardwareReadinessCard extends StatelessWidget {
  final HardwareProjectState hardwareState;
  const _HardwareReadinessCard({required this.hardwareState});

  @override
  Widget build(BuildContext context) {
    final conn = hardwareState.connectionState;
    final plan = hardwareState.activePlan;

    final readiness = plan == null
        ? 'No export package'
        : plan.blockedStepCount > 0
            ? 'Unverified mappings block write'
            : plan.dryRunOnly
                ? 'Dry-run plan ready'
                : 'Hardware write disabled';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.security_outlined, color: Color(0xFFA78BFA), size: 13),
          const SizedBox(width: 8),
          Text('HARDWARE READINESS', style: proLabel(size: 9, spacing: 2)),
        ]),
        const SizedBox(height: 10),
        _ReportChip(
          label: 'TRANSPORT',
          value: conn.transportType.label,
          color: Colors.white54,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'CONNECTION STATUS',
          value: conn.connectionStatus.label,
          color: conn.connectionStatus == HardwareConnectionStatus.simulated
              ? const Color(0xFF4A9EFF)
              : Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'TARGET DEVICE',
          value: conn.targetDevice.label,
          color: Colors.white54,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'WRITE PLANS',
          value: '${hardwareState.planCount} plan(s)',
          color: Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'DRY-RUN ONLY',
          value: plan != null ? (plan.dryRunOnly ? 'Yes' : 'No') : 'N/A',
          color: plan?.dryRunOnly ?? true ? kProAmber : const Color(0xFFEF4444),
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'BLOCKED CHECKS',
          value: '${hardwareState.blockedCheckCount}',
          color: hardwareState.blockedCheckCount > 0
              ? const Color(0xFFEF4444)
              : Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'WARNING CHECKS',
          value: '${hardwareState.warningCheckCount}',
          color: hardwareState.warningCheckCount > 0 ? kProAmber : Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'VERIFIED STEPS',
          value: plan != null ? '${plan.verifiedStepCount}' : 'N/A',
          color: (plan?.verifiedStepCount ?? 0) > 0
              ? const Color(0xFF4A9EFF)
              : Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'BLOCKED STEPS',
          value: plan != null ? '${plan.blockedStepCount}' : 'N/A',
          color: (plan?.blockedStepCount ?? 0) > 0
              ? const Color(0xFFEF4444)
              : Colors.white38,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'READINESS',
          value: readiness,
          color: Colors.white54,
        ),
        const SizedBox(height: 8),
        Text(
          'Hardware write remains disabled. Use the Hardware tab for dry-run planning.',
          style: proSubtitle(size: 9),
        ),
      ]),
    );
  }
}

// ── _DeployReadinessCard ──────────────────────────────────────────────────────

class _DeployReadinessCard extends StatelessWidget {
  final DeployProjectState deployState;
  const _DeployReadinessCard({required this.deployState});

  @override
  Widget build(BuildContext context) {
    final activePkg = deployState.activePackage;
    final activePreset = deployState.activePreset;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.inventory_2_outlined,
              color: Color(0xFF34D399), size: 13),
          const SizedBox(width: 8),
          Text('DEPLOY READINESS', style: proLabel(size: 9, spacing: 2)),
        ]),
        const SizedBox(height: 10),
        _ReportChip(
            label: 'PACKAGES',
            value: '${deployState.packageCount}',
            color: kProAccent),
        const SizedBox(height: 6),
        _ReportChip(
            label: 'PRESETS',
            value: '${deployState.presetCount}',
            color: kProAccent),
        const SizedBox(height: 6),
        _ReportChip(
            label: 'READY',
            value: '${deployState.readyPackageCount}',
            color: kProGreen),
        const SizedBox(height: 6),
        _ReportChip(
            label: 'BLOCKED',
            value: '${deployState.blockedPackageCount}',
            color: const Color(0xFFEF4444)),
        if (activePkg != null) ...[
          const SizedBox(height: 6),
          _ReportChip(
              label: 'VERSION',
              value: activePkg.version,
              color: Colors.white54),
          const SizedBox(height: 6),
          _ReportChip(
              label: 'STATUS',
              value: activePkg.status.label,
              color: Colors.white54),
          const SizedBox(height: 6),
          _ReportChip(
              label: 'READINESS',
              value: activePkg.readinessLevel.label,
              color: Colors.white54),
          const SizedBox(height: 6),
          _ReportChip(
              label: 'WARNINGS',
              value: '${activePkg.snapshot.warnings.length}',
              color: kProAmber),
        ],
        if (activePreset != null) ...[
          const SizedBox(height: 6),
          _ReportChip(
              label: 'ACTIVE PRESET',
              value: activePreset.name,
              color: Colors.white54),
        ],
        const SizedBox(height: 6),
        _ReportChip(
            label: 'READINESS LABEL',
            value: deployState.readinessLabel,
            color: Colors.white38),
        const SizedBox(height: 8),
        Text(
          'Deploy package is review/dry-run only. No hardware write performed.',
          style: proSubtitle(size: 9),
        ),
      ]),
    );
  }
}

// ── Phase U1: DSP Address Map Readiness Card ──────────────────────────────────

class _DspAddressMapReadinessCard extends StatelessWidget {
  const _DspAddressMapReadinessCard();

  @override
  Widget build(BuildContext context) {
    final registry = createTunaiAdau1466ThreeWayRegistry();
    final imported  = registry.has3WayAddressMap;
    final verified  = registry.verifiedCount;
    final exported  = registry.exportConfirmedCount + registry.peqRowCount;
    final total     = registry.totalImportedCount;

    String readinessLabel;
    Color readinessColor;
    if (imported && verified >= 2) {
      readinessLabel = 'Address map imported · Master volume verified';
      readinessColor = Colors.greenAccent;
    } else if (imported) {
      readinessLabel = 'Address map imported · Live validation required';
      readinessColor = Colors.orange;
    } else {
      readinessLabel = 'Address map not loaded';
      readinessColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.map_outlined, size: 13, color: Colors.white38),
          const SizedBox(width: 6),
          Text('DSP ADDRESS MAP', style: proLabel(size: 9, spacing: 1.8)),
        ]),
        const SizedBox(height: 12),
        _ReportChip(
          label: 'MAP IMPORTED',
          value: imported ? 'YES' : 'NO',
          color: imported ? Colors.greenAccent : Colors.red,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'TOTAL ADDRESSES',
          value: '$total',
          color: Colors.white70,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'VERIFIED',
          value: '$verified',
          color: Colors.greenAccent,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'EXPORT CONFIRMED',
          value: '$exported',
          color: Colors.orange,
        ),
        const SizedBox(height: 6),
        const _ReportChip(
          label: 'MASTER VOLUME',
          value: 'Verified (0x0067 / 0x0064)',
          color: Colors.greenAccent,
        ),
        const SizedBox(height: 6),
        const _ReportChip(
          label: 'PEQ / XO',
          value: 'Blocked until live validation',
          color: Colors.orange,
        ),
        const SizedBox(height: 6),
        _ReportChip(
          label: 'READINESS',
          value: readinessLabel,
          color: readinessColor,
        ),
        const SizedBox(height: 8),
        Text(
          'Physical routing: OUT1=TWL · OUT2=MID_L · OUT3=WFL · OUT4=TWR · OUT7=MID_R · OUT8=WFR. '
          'Verify Sigma output cell names against physical pins before write.',
          style: proSubtitle(size: 9),
        ),
      ]),
    );
  }
}

// ── Phase U2: Address Validation Readiness Card ───────────────────────────────

class _AddressValidationReadinessCard extends StatelessWidget {
  final AddressValidationProjectState validationState;
  const _AddressValidationReadinessCard({required this.validationState});

  @override
  Widget build(BuildContext context) {
    final tasks = validationState.tasks;
    final hasQueue = tasks.isNotEmpty;
    final next = validationState.nextRecommendedGroup;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.task_alt_outlined, size: 13, color: Colors.white38),
          const SizedBox(width: 7),
          Text('Address Validation Readiness', style: proLabel()),
        ]),
        const SizedBox(height: 10),
        if (!hasQueue) ...[
          Text(
            'Validation queue not generated. '
            'Go to Hardware tab → Address Live Validation Manager → Generate Validation Queue.',
            style: proSubtitle(size: 10),
          ),
        ] else ...[
          _ValStatRow('Total tasks', '${tasks.length}'),
          _ValStatRow('Verified', '${validationState.verifiedCount}',
              color: Colors.greenAccent),
          _ValStatRow('Failed', '${validationState.failedCount}',
              color: validationState.failedCount > 0 ? Colors.redAccent : null),
          _ValStatRow('Blocked', '${validationState.blockedCount}',
              color: validationState.blockedCount > 0 ? Colors.orange : null),
          _ValStatRow('High Risk', '${validationState.highRiskCount}',
              color: validationState.highRiskCount > 0 ? Colors.purpleAccent : null),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(validationState.readinessLabel,
                style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ),
          if (next != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              Text('Next group: ', style: proSubtitle(size: 9)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kProAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(next.label,
                    style: const TextStyle(fontSize: 9, color: kProAccent,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ],
        ],
        const SizedBox(height: 8),
        Text(
          'Validation manager does not write hardware. '
          'Expert review required before any address becomes write-eligible.',
          style: proSubtitle(size: 9),
        ),
      ]),
    );
  }
}

class _ValStatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _ValStatRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 80,
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ),
      Text(value,
          style: TextStyle(fontSize: 9,
              color: color ?? Colors.white60,
              fontWeight: color != null ? FontWeight.w600 : FontWeight.normal)),
    ]),
  );
}

// ── Phase T2 Revised: Transport Readiness Card ────────────────────────────────

class _TransportReadinessCard extends StatelessWidget {
  final HardwareConnectionState connectionState;
  const _TransportReadinessCard({required this.connectionState});

  @override
  Widget build(BuildContext context) {
    final selected = connectionState.selectedTransportBackend;
    final transports = connectionState.availableTransports;
    final selectedInfo = transports
        .where((t) => t.backend == selected)
        .firstOrNull;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.compare_arrows_outlined,
              size: 13, color: Colors.white38),
          const SizedBox(width: 7),
          Text('Transport Readiness', style: proLabel()),
        ]),
        const SizedBox(height: 10),

        // Selected backend
        _TRStatRow('Selected Backend', selected.label),
        _TRStatRow('Readiness',
            selectedInfo?.readinessStatus.label ?? 'Unknown'),
        _TRStatRow('Write Enabled', 'false — Phase T2 safety lock'),
        _TRStatRow('Write Capability',
            selectedInfo?.writeCapability.label ?? 'None'),

        const SizedBox(height: 10),
        Text('All transport backends', style: proLabel(size: 9)),
        const SizedBox(height: 6),
        for (final t in transports) ...[
          Row(children: [
            Icon(
              t.backend == selected
                  ? Icons.radio_button_checked_outlined
                  : Icons.radio_button_off_outlined,
              size: 11,
              color: t.backend == selected ? kProAccent : Colors.white24,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                t.displayName,
                style: TextStyle(
                  fontSize: 9,
                  color:
                      t.backend == selected ? Colors.white70 : Colors.white38,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(t.readinessStatus.label,
                  style: const TextStyle(fontSize: 7, color: Colors.white38)),
            ),
          ]),
          const SizedBox(height: 4),
        ],

        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.06),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text(
            'No transport backend is enabled for hardware write in this build. '
            'Transport selection does not enable write. '
            'All write capability remains at Dry-Run Only.',
            style: TextStyle(fontSize: 9, color: Colors.orange),
          ),
        ),
      ]),
    );
  }
}

class _TRStatRow extends StatelessWidget {
  final String label;
  final String value;
  const _TRStatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 120,
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(fontSize: 9, color: Colors.white60)),
      ),
    ]),
  );
}

// ── Phase T4A: USBi Executor Readiness Card ───────────────────────────────────

class _UsbiExecutorReadinessCard extends StatelessWidget {
  const _UsbiExecutorReadinessCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.usb_outlined, size: 13, color: Colors.white38),
        const SizedBox(width: 7),
        Text('USBi Temporary Executor Readiness', style: proLabel()),
      ]),
      const SizedBox(height: 10),

      _TRStatRow('Executor Phase',     'T4A — USBi Temporary'),
      _TRStatRow('Transport',          'usbiWindowsTemporary (Windows only)'),
      _TRStatRow('Write Scope',        'Master Volume L (0x0067) / R (0x0064)'),
      _TRStatRow('Native Backend',     'Pending — not implemented'),
      _TRStatRow('wasActualWrite',     'false by default; true only if ACK confirmed'),
      _TRStatRow('Guard Count',        'D1 Platform / D2 Transport / D3-D4 Address / D5 Value / D6 Confirm / D7 Backend'),
      _TRStatRow('Packet Format',      'Setup [40 B2 00 00 01 01 06 00] + Body [addr 2B + data 4B BE]'),
      _TRStatRow('ACK Format',         '[C0 B5 00 00 00 00 01 00] — byte 6 = 0x01 = success'),
      _TRStatRow('EEPROM / Selfboot',  'BLOCKED — forever'),
      _TRStatRow('SafeLoad',           'BLOCKED — forever in T4A'),
      _TRStatRow('Write-All',          'BLOCKED — not in scope'),
      _TRStatRow('Final Transport',    'ICP5 — not yet implemented'),

      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.06),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          'Phase T4A USBi executor is blocked until native write backend is '
          'implemented. All 7 guards must pass. wasActualWrite is false by '
          'default. USBi is temporary — ICP5 is the final transport.',
          style: TextStyle(fontSize: 9, color: Colors.orange),
        ),
      ),
    ]),
  );
}

// ── Phase T3: Transport Command Readiness Card ────────────────────────────────

class _TransportCommandReadinessCard extends StatelessWidget {
  const _TransportCommandReadinessCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.terminal_outlined, size: 13, color: Colors.white38),
        const SizedBox(width: 7),
        Text('Transport Command Readiness', style: proLabel()),
      ]),
      const SizedBox(height: 10),

      _TRStatRow('Command Envelope',   'Available (dry-run only)'),
      _TRStatRow('Supported Scope',
          'Master Volume L (0x0067) / R (0x0064)'),
      _TRStatRow('Executable Now',     'false — Phase T3 safety lock'),
      _TRStatRow('Transport Write',    'false — Phase T3 safety lock'),
      _TRStatRow('actualWriteAllowed', 'false — always'),
      _TRStatRow('Fixed-Point Format', '8.24  (1.0 = 0x01000000)'),
      _TRStatRow('Byte Order',         'Big-endian (MSB first)'),
      _TRStatRow('Blocked Parameters',
          'PEQ / XO / Gain / Mute / Delay / SafeLoad'),

      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.06),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          'Command envelope is dry-run only. '
          'No hardware packet is generated. '
          'No transport write is performed. '
          'No USB, BLE, or ICP5 bytes are produced.',
          style: TextStyle(fontSize: 9, color: Colors.orange),
        ),
      ),
    ]),
  );
}
