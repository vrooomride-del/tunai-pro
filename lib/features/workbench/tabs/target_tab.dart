// ── Target Tab — Phase C ──────────────────────────────────────────────────────
// Target curve preset selection, with a real target-curve preview graph
// (Phase 5-A-2) driven by the same ProTargetCurve.db formula the Optimizer
// and Guided AI evaluator already use. No FRD overlay, no before/after
// comparison here — that remains the Optimizer preview's job.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_simulation_optimizer.dart';
import '../../../core/pro_target_curve.dart';
import '../../../shared/pro_widgets.dart';

class TargetTab extends ConsumerWidget {
  final String projectId;
  const TargetTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acoustic = ref.watch(proProjectStoreProvider)
        .projects.where((p) => p.id == projectId).firstOrNull
        ?.acousticState ?? MeasurementProjectState.createDefault();
    final target = acoustic.targetCurve;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.track_changes_outlined, color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Target', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 4),
        Text('Select the target frequency response curve for optimization.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        // Current selection summary
        _CurrentTargetCard(target: target),
        const SizedBox(height: 16),

        // Preset selection
        Text('TARGET PRESETS', style: proLabel(size: 9, spacing: 2)),
        const SizedBox(height: 8),
        ...TargetCurvePreset.values.map((preset) => _PresetCard(
          preset: preset,
          selected: target.selectedPreset == preset,
          onSelect: () async {
            final project = ref.read(proProjectStoreProvider)
                .projects.where((p) => p.id == projectId).firstOrNull;
            if (project == null) return;
            await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
              projectId,
              project.acousticState.copyWith(
                targetCurve: target.copyWith(selectedPreset: preset),
              ),
            );
          },
        )),

        const SizedBox(height: 20),

        // Target curve preview
        Text('FREQUENCY RESPONSE PREVIEW', style: proLabel(size: 9, spacing: 2)),
        const SizedBox(height: 8),
        _TargetCurveGraph(preset: target.selectedPreset),

        const SizedBox(height: 20),

        // Phase D notice
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
                'Target curve matching and PEQ optimization will be available in Phase D. '
                'Import FRD data and select a target preset to prepare for optimization.',
                style: proSubtitle(size: 11),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _CurrentTargetCard extends StatelessWidget {
  final TargetCurveState target;
  const _CurrentTargetCard({required this.target});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CURRENT TARGET', style: proLabel(size: 9, spacing: 1.8)),
          const SizedBox(height: 6),
          Text(target.selectedPreset.label, style: proTitle(size: 14, color: kProAccent)),
          const SizedBox(height: 4),
          Text(target.selectedPreset.description, style: proSubtitle(size: 10)),
        ]),
      ),
      const ProStatusPill(label: 'SELECTED', color: kProAccent),
    ]),
  );
}

class _PresetCard extends StatelessWidget {
  final TargetCurvePreset preset;
  final bool selected;
  final VoidCallback onSelect;
  const _PresetCard({required this.preset, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onSelect,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: selected ? kProAccent.withValues(alpha: 0.06) : kProSurface,
        border: Border.all(color: selected ? kProAccent.withValues(alpha: 0.5) : kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(preset.label,
                style: proTitle(size: 12, color: selected ? kProAccent : Colors.white70)),
            const SizedBox(height: 3),
            Text(preset.description, style: proSubtitle(size: 10)),
          ]),
        ),
        if (selected)
          const Icon(Icons.check_circle_outline, color: kProAccent, size: 14)
        else
          const Icon(Icons.radio_button_unchecked, color: Colors.white12, size: 14),
      ]),
    ),
  );
}

// Real target-curve preview (Phase 5-A-2). Data comes only from
// ProTargetCurve.curve() over ProSimulationOptimizer.previewFrequencies() —
// the same canonical source the Optimizer and Guided AI evaluator already
// use. No FRD, no before/after comparison — target curve only.
class _TargetCurveGraph extends StatelessWidget {
  final TargetCurvePreset preset;
  const _TargetCurveGraph({required this.preset});

  @override
  Widget build(BuildContext context) {
    final freqs = ProSimulationOptimizer.previewFrequencies();
    final curve = ProTargetCurve.curve(preset, freqs);
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        size: const Size.fromHeight(160),
        painter: _TargetCurvePainter(freqs: freqs, curve: curve),
      ),
    );
  }
}

class _TargetCurvePainter extends CustomPainter {
  final List<double> freqs;
  final List<double> curve;

  static const double minHz = 20;
  static const double maxHz = 20000;
  static const double _leftPad = 30;
  static const double _bottomPad = 16;

  _TargetCurvePainter({required this.freqs, required this.curve});

  double _x(double freq, Size size) {
    final t = (math.log(freq) - math.log(minHz)) /
        (math.log(maxHz) - math.log(minHz));
    return _leftPad + t * (size.width - _leftPad);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotH = size.height - _bottomPad;

    // Symmetric dB range that fits the curve, clamped to a sane minimum.
    var maxAbs = 3.0;
    for (final v in curve) {
      if (v.isFinite && v.abs() > maxAbs) maxAbs = v.abs();
    }
    maxAbs = maxAbs.ceilToDouble();
    final range = maxAbs; // ± range dB

    double yForDb(double db) {
      final t = (range - db) / (2 * range); // +range at top, −range at bottom
      return t.clamp(0.0, 1.0) * plotH;
    }

    final grid = Paint()
      ..color = kProBorder
      ..strokeWidth = 1;

    // Horizontal dB grid + labels at 0 and ±range.
    for (final db in [range, 0.0, -range]) {
      final y = yForDb(db);
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width, y), grid);
      _label(canvas, '${db > 0 ? '+' : ''}${db.toStringAsFixed(0)}',
          Offset(0, y - 5), Colors.white30);
    }

    // Vertical decade grid + labels.
    for (final f in const [20.0, 100.0, 1000.0, 10000.0, 20000.0]) {
      final x = _x(f, size);
      canvas.drawLine(Offset(x, 0), Offset(x, plotH), grid);
      _label(
          canvas,
          f >= 1000 ? '${(f / 1000).toStringAsFixed(0)}k' : f.toStringAsFixed(0),
          Offset(x - 8, plotH + 2),
          Colors.white30,
          size: 8);
    }

    // Target curve — the only curve drawn.
    if (curve.length == freqs.length && curve.isNotEmpty) {
      final paint = Paint()
        ..color = kProAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      Offset? prev;
      for (var i = 0; i < freqs.length; i++) {
        final v = curve[i];
        if (!v.isFinite) {
          prev = null;
          continue;
        }
        final p = Offset(_x(freqs[i], size), yForDb(v));
        if (prev != null) canvas.drawLine(prev, p, paint);
        prev = p;
      }
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color,
      {double size = 9}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TargetCurvePainter old) =>
      old.curve != curve || old.freqs != freqs;
}
