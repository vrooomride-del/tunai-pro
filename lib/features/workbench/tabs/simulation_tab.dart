// ── TUNAI PRO Phase L — Acoustic Simulation Tab ───────────────────────────────
// Draft response preview. Not final acoustic simulation. No hardware write.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_simulation_data.dart';
import '../../../core/pro_simulation_engine.dart';
import '../../../shared/pro_widgets.dart';

class SimulationTab extends ConsumerStatefulWidget {
  final String projectId;
  const SimulationTab({super.key, required this.projectId});

  @override
  ConsumerState<SimulationTab> createState() => _SimulationTabState();
}

class _SimulationTabState extends ConsumerState<SimulationTab> {
  bool _includeTarget = true;
  bool _includeDrivers = true;
  bool _includeSummed = true;
  bool _includePhase = false;
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;

    if (project == null) {
      return const Center(
          child: Text('Project not found',
              style: TextStyle(color: Colors.white38)));
    }

    final simState = project.simulationState;
    final activeRun = simState.activeRun;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────────────────
        Row(children: [
          Icon(Icons.show_chart_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Acoustic Simulation', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 6),
        Text(
          'Draft response preview for tuning review. '
          'Final acoustic verification requires measurement.',
          style: proSubtitle(),
        ),
        const SizedBox(height: 20),

        // ── Control panel ────────────────────────────────────────────────────
        _ControlPanel(
          includeTarget: _includeTarget,
          includeDrivers: _includeDrivers,
          includeSummed: _includeSummed,
          includePhase: _includePhase,
          running: _running,
          project: project,
          onTargetChanged: (v) => setState(() => _includeTarget = v),
          onDriversChanged: (v) => setState(() => _includeDrivers = v),
          onSummedChanged: (v) => setState(() => _includeSummed = v),
          onPhaseChanged: (v) => setState(() => _includePhase = v),
          onGenerate: () => _generate(project),
        ),
        const SizedBox(height: 16),

        // ── Graph ─────────────────────────────────────────────────────────────
        if (activeRun != null) ...[
          _GraphPanel(run: activeRun),
          const SizedBox(height: 16),

          // ── Curve list ───────────────────────────────────────────────────
          _CurveListPanel(run: activeRun),
          const SizedBox(height: 16),

          // ── Summary / warnings ───────────────────────────────────────────
          _SummaryPanel(run: activeRun),
        ] else ...[
          _EmptyGraphPlaceholder(),
          const SizedBox(height: 16),
          _NoRunPanel(),
        ],
      ]),
    );
  }

  Future<void> _generate(ProProject project) async {
    setState(() => _running = true);
    try {
      final config = SimulationRunConfig(
        includeTarget: _includeTarget,
        includeDrivers: _includeDrivers,
        includeSummed: _includeSummed,
        includePhasePlaceholder: _includePhase,
      );
      final result = generateSimulationDraft(project: project, config: config);

      final newState = project.simulationState.copyWith(
        runs: [...project.simulationState.runs, result],
        activeRunId: result.id,
        revision: project.simulationState.revision + 1,
      );
      await ref
          .read(proProjectStoreProvider.notifier)
          .updateSimulationState(widget.projectId, newState);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

// ── Control Panel ─────────────────────────────────────────────────────────────

class _ControlPanel extends StatelessWidget {
  final bool includeTarget;
  final bool includeDrivers;
  final bool includeSummed;
  final bool includePhase;
  final bool running;
  final ProProject project;
  final ValueChanged<bool> onTargetChanged;
  final ValueChanged<bool> onDriversChanged;
  final ValueChanged<bool> onSummedChanged;
  final ValueChanged<bool> onPhaseChanged;
  final VoidCallback onGenerate;

  const _ControlPanel({
    required this.includeTarget,
    required this.includeDrivers,
    required this.includeSummed,
    required this.includePhase,
    required this.running,
    required this.project,
    required this.onTargetChanged,
    required this.onDriversChanged,
    required this.onSummedChanged,
    required this.onPhaseChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final driverCount = project.acousticState.driverChannels.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SIMULATION CONFIG', style: proLabel(size: 9, spacing: 2)),
        const SizedBox(height: 12),

        // Config chips
        Wrap(spacing: 12, runSpacing: 8, children: [
          const _ConfigChip(label: 'SAMPLE RATE', value: '48 kHz'),
          const _ConfigChip(label: 'FREQ RANGE', value: '20 Hz – 20 kHz'),
          const _ConfigChip(label: 'RESOLUTION', value: '12 pts/oct'),
          _ConfigChip(label: 'DRIVERS', value: '$driverCount configured'),
        ]),
        const SizedBox(height: 12),

        // Toggles
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Toggle(label: 'Target', value: includeTarget, onChanged: onTargetChanged),
          _Toggle(label: 'Drivers', value: includeDrivers, onChanged: onDriversChanged),
          _Toggle(label: 'Summed', value: includeSummed, onChanged: onSummedChanged),
          _Toggle(label: 'Phase Placeholder', value: includePhase, onChanged: onPhaseChanged),
        ]),
        const SizedBox(height: 14),

        Row(children: [
          ElevatedButton.icon(
            onPressed: running ? null : onGenerate,
            icon: running
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5))
                : const Icon(Icons.play_arrow_outlined, size: 14),
            label: Text(running ? 'Generating…' : 'Generate Simulation Draft',
                style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kProAccent.withValues(alpha: 0.15),
              foregroundColor: kProAccent,
              side: BorderSide(color: kProAccent.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(3)),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Draft only — not hardware-ready.',
            style: TextStyle(fontSize: 9, color: Colors.white38),
          ),
        ]),
      ]),
    );
  }
}

class _ConfigChip extends StatelessWidget {
  final String label;
  final String value;
  const _ConfigChip({required this.label, required this.value});

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
      Text(value, style: proValue(size: 10, color: Colors.white60)),
    ]),
  );
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: value ? kProAccent.withValues(alpha: 0.08) : kProBg,
        border: Border.all(
            color: value
                ? kProAccent.withValues(alpha: 0.4)
                : kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          value ? Icons.check_box_outlined : Icons.check_box_outline_blank,
          size: 12,
          color: value ? kProAccent : Colors.white24,
        ),
        const SizedBox(width: 6),
        Text(label,
            style: proLabel(
                size: 9,
                color: value ? kProAccent : Colors.white38,
                spacing: 0.3)),
      ]),
    ),
  );
}

// ── Graph Panel ───────────────────────────────────────────────────────────────

class _GraphPanel extends StatelessWidget {
  final SimulationRunResult run;
  const _GraphPanel({required this.run});

  @override
  Widget build(BuildContext context) {
    final magnitudeCurves = run.curves
        .where((c) => c.scale == SimulationScale.magnitudeDb && c.hasPoints)
        .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('FREQUENCY RESPONSE', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          Text('20 Hz – 20 kHz',
              style: proLabel(size: 9, color: Colors.white24, spacing: 0.3)),
        ]),
        const SizedBox(height: 4),
        Text('Draft placeholder curves only. Not acoustically verified.',
            style: proSubtitle(size: 9)),
        const SizedBox(height: 10),

        SizedBox(
          height: 240,
          child: magnitudeCurves.isEmpty
              ? const Center(
                  child: Text('No magnitude curves',
                      style: TextStyle(color: Colors.white24, fontSize: 11)))
              : CustomPaint(
                  painter: _FrequencyGraphPainter(magnitudeCurves),
                  child: Container(),
                ),
        ),

        const SizedBox(height: 8),
        // Legend
        Wrap(spacing: 12, runSpacing: 6, children: [
          for (final entry in magnitudeCurves.asMap().entries)
            _LegendItem(
              label: entry.value.label,
              color: _curveColor(entry.key, entry.value.type),
            ),
        ]),
      ]),
    );
  }
}

Color _curveColor(int index, SimulationCurveType type) {
  switch (type) {
    case SimulationCurveType.target:
      return const Color(0xFFFFB74D); // amber
    case SimulationCurveType.summed:
      return const Color(0xFF4A9EFF); // accent blue
    case SimulationCurveType.driver:
      const driverColors = [
        Color(0xFF22C55E), // green
        Color(0xFF34D399),
        Color(0xFF6EE7B7),
        Color(0xFFA7F3D0),
        Color(0xFF10B981),
        Color(0xFF059669),
      ];
      return driverColors[index % driverColors.length];
    default:
      return Colors.white38;
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendItem({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 18, height: 2, color: color),
    const SizedBox(width: 6),
    Text(label,
        style: const TextStyle(fontSize: 9, color: Colors.white54)),
  ]);
}

// ── Frequency Response CustomPainter ─────────────────────────────────────────

class _FrequencyGraphPainter extends CustomPainter {
  final List<SimulationCurve> curves;

  const _FrequencyGraphPainter(this.curves);

  static const double _minDb = -24;
  static const double _maxDb = 12;
  static const double _minHz = 20;
  static const double _maxHz = 20000;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = EdgeInsets.fromLTRB(40, 8, 12, 24);
    final graphRect = Rect.fromLTRB(
      padding.left,
      padding.top,
      size.width - padding.right,
      size.height - padding.bottom,
    );

    _drawGrid(canvas, graphRect);
    _drawAxesLabels(canvas, size, graphRect);

    for (var i = 0; i < curves.length; i++) {
      _drawCurve(
          canvas, graphRect, curves[i], _curveColor(i, curves[i].type));
    }
  }

  double _xForFreq(double f, Rect r) {
    final logMin = math.log(_minHz);
    final logMax = math.log(_maxHz);
    final logF = math.log(f.clamp(_minHz, _maxHz));
    return r.left + (logF - logMin) / (logMax - logMin) * r.width;
  }

  double _yForDb(double db, Rect r) {
    final clamped = db.clamp(_minDb, _maxDb);
    return r.bottom - (clamped - _minDb) / (_maxDb - _minDb) * r.height;
  }

  void _drawGrid(Canvas canvas, Rect r) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1E2832)
      ..strokeWidth = 1;
    final gridPaintLight = Paint()
      ..color = const Color(0xFF2A3542)
      ..strokeWidth = 1;

    // Horizontal dB lines
    for (final db in [-24.0, -18.0, -12.0, -6.0, 0.0, 6.0, 12.0]) {
      final y = _yForDb(db, r);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y),
          db == 0 ? gridPaintLight : gridPaint);
    }

    // Vertical frequency lines
    const freqMarks = [
      20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000
    ];
    for (final f in freqMarks) {
      final x = _xForFreq(f.toDouble(), r);
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom),
          f == 1000 ? gridPaintLight : gridPaint);
    }
  }

  void _drawAxesLabels(Canvas canvas, Size size, Rect r) {
    const style = TextStyle(
        color: Color(0xFF4B5563), fontSize: 8, fontFamily: 'monospace');

    // dB labels
    for (final db in [-24.0, -18.0, -12.0, -6.0, 0.0, 6.0, 12.0]) {
      final y = _yForDb(db, r);
      _drawText(canvas, '${db.toInt()}', Offset(0, y - 5), style);
    }

    // Frequency labels
    const freqLabels = {
      20: '20', 50: '50', 100: '100', 200: '200',
      500: '500', 1000: '1k', 2000: '2k', 5000: '5k',
      10000: '10k', 20000: '20k',
    };
    for (final entry in freqLabels.entries) {
      final x = _xForFreq(entry.key.toDouble(), r);
      _drawText(canvas, entry.value,
          Offset(x - 6, size.height - 14), style);
    }
  }

  void _drawText(
      Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  void _drawCurve(
      Canvas canvas, Rect r, SimulationCurve curve, Color color) {
    if (curve.points.isEmpty) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool first = true;

    for (final pt in curve.points) {
      if (pt.frequencyHz < _minHz || pt.frequencyHz > _maxHz * 1.01) continue;
      final x = _xForFreq(pt.frequencyHz, r);
      final y = _yForDb(pt.value, r);
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    if (!first) canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FrequencyGraphPainter oldDelegate) =>
      oldDelegate.curves != curves;
}

class _EmptyGraphPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 240,
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
      Icon(Icons.show_chart_outlined, color: Colors.white12, size: 32),
      SizedBox(height: 10),
      Text('No simulation run yet',
          style: TextStyle(color: Colors.white24, fontSize: 12)),
      SizedBox(height: 4),
      Text('Generate a draft to preview frequency response.',
          style: TextStyle(color: Colors.white12, fontSize: 10)),
    ]),
  );
}

// ── Curve List Panel ──────────────────────────────────────────────────────────

class _CurveListPanel extends StatelessWidget {
  final SimulationRunResult run;
  const _CurveListPanel({required this.run});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('CURVES', style: proLabel(size: 9, spacing: 2)),
        const Spacer(),
        Text('${run.curveCount} curve(s)',
            style: proLabel(size: 9, color: Colors.white24, spacing: 0.3)),
      ]),
      const SizedBox(height: 10),
      ...run.curves.asMap().entries.map((entry) =>
          _CurveRow(curve: entry.value, colorIndex: entry.key)),
    ]),
  );
}

class _CurveRow extends StatelessWidget {
  final SimulationCurve curve;
  final int colorIndex;
  const _CurveRow({required this.curve, required this.colorIndex});

  @override
  Widget build(BuildContext context) {
    final color = _curveColor(colorIndex, curve.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: kProBg,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        Container(width: 14, height: 2,
            color: color.withValues(alpha: 0.9)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Expanded(
                  child: Text(curve.label, style: proTitle(size: 10))),
              if (curve.status == SimulationCurveStatus.imported)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: kProGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text('FRD',
                      style: TextStyle(
                          color: kProGreen, fontSize: 8,
                          letterSpacing: 0.5)),
                )
              else if (curve.type == SimulationCurveType.driver)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: kProAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text('placeholder',
                      style: TextStyle(
                          color: kProAmber, fontSize: 8,
                          letterSpacing: 0.3)),
                ),
            ]),
            if (curve.notes != null) ...[
              const SizedBox(height: 1),
              Text(curve.notes!,
                  style: proSubtitle(size: 8, color: Colors.white24)),
            ],
            if (curve.warning != null) ...[
              const SizedBox(height: 2),
              Text(curve.warning!,
                  style: proSubtitle(size: 9, color: Colors.white24)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Text('${curve.pointCount} pts',
            style: proLabel(size: 9, color: Colors.white24, spacing: 0.3)),
        const SizedBox(width: 8),
        ProStatusPill(
          label: curve.status.label,
          color: switch (curve.status) {
            SimulationCurveStatus.imported        => kProGreen,
            SimulationCurveStatus.calculatedDraft => kProAccent,
            SimulationCurveStatus.estimated       => kProAccent,
            SimulationCurveStatus.placeholder     => kProAmber,
            SimulationCurveStatus.empty           => Colors.white24,
            _                                     => kProAmber,
          },
        ),
      ]),
    );
  }
}

// ── Summary Panel ─────────────────────────────────────────────────────────────

class _SummaryPanel extends StatelessWidget {
  final SimulationRunResult run;
  const _SummaryPanel({required this.run});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('SIMULATION SUMMARY', style: proLabel(size: 9, spacing: 2)),
        const Spacer(),
        ProStatusPill(label: run.readiness.label, color: kProAmber),
      ]),
      const SizedBox(height: 8),
      Text(run.summary, style: proSubtitle(size: 10)),
      const SizedBox(height: 10),

      if (run.warnings.isNotEmpty) ...[
        Text('WARNINGS', style: proLabel(size: 8, spacing: 1.5)),
        const SizedBox(height: 6),
        ...run.warnings.map((w) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_outlined,
                color: kProAmber, size: 11),
            const SizedBox(width: 6),
            Expanded(
                child: Text(w,
                    style: proSubtitle(size: 9,
                        color: Colors.white38))),
          ]),
        )),
        const SizedBox(height: 8),
      ],

      const Row(children: [
        Icon(Icons.info_outline, color: Colors.white24, size: 11),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'Simulation is draft-only and does not replace measured verification. '
            'No hardware write.',
            style: TextStyle(fontSize: 9, color: Colors.white24,
                fontFamily: 'monospace'),
          ),
        ),
      ]),
    ]),
  );
}

class _NoRunPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Row(children: [
      Icon(Icons.info_outline, color: Colors.white24, size: 13),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          'Generate a simulation draft to preview frequency response curves. '
          'Placeholder data will be used until FRD import is complete.',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
      ),
    ]),
  );
}
