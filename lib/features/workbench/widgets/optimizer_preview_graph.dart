import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/pro_widgets.dart';

/// Before/After optimizer preview: three magnitude curves on a shared
/// log-frequency axis — the target curve, the current simulated response, and
/// the predicted response with the optimizer's PEQ suggestions applied.
///
/// Visualization only. Curves are supplied by the caller (built from
/// ProTargetCurve + ProSimulationOptimizer); this widget performs no
/// optimization and no DSP write.
class OptimizerPreviewGraph extends StatelessWidget {
  final List<double> freqs;
  final List<double> target;
  final List<double> before;
  final List<double> after;
  final double height;

  const OptimizerPreviewGraph({
    super.key,
    required this.freqs,
    required this.target,
    required this.before,
    required this.after,
    this.height = 220,
  });

  static const Color _targetColor = Colors.white38;
  static const Color _beforeColor = kProAmber;
  static const Color _afterColor = kProGreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: kProPanel,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('OPTIMIZER PREVIEW', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          Text('SIMULATION', style: proLabel(size: 8, color: Colors.white24)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: CustomPaint(
            size: Size.infinite,
            painter: _PreviewPainter(
              freqs: freqs,
              target: target,
              before: before,
              after: after,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Wrap(spacing: 16, runSpacing: 6, children: [
          _LegendItem(color: _targetColor, label: 'Target', dashed: true),
          _LegendItem(color: _beforeColor, label: 'Before'),
          _LegendItem(color: _afterColor, label: 'After (predicted)'),
        ]),
      ]),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const _LegendItem(
      {required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 2,
            color: dashed ? null : color,
            decoration: dashed
                ? BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: color, width: 2, style: BorderStyle.solid)),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          Text(label,
              style: proSubtitle(size: 9, color: Colors.white54)),
        ],
      );
}

class _PreviewPainter extends CustomPainter {
  final List<double> freqs;
  final List<double> target;
  final List<double> before;
  final List<double> after;

  static const double minHz = 20;
  static const double maxHz = 20000;
  static const double _leftPad = 30;
  static const double _bottomPad = 16;

  _PreviewPainter({
    required this.freqs,
    required this.target,
    required this.before,
    required this.after,
  });

  double _x(double freq, Size size) {
    final t = (math.log(freq) - math.log(minHz)) /
        (math.log(maxHz) - math.log(minHz));
    return _leftPad + t * (size.width - _leftPad);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotH = size.height - _bottomPad;

    // Symmetric dB range that fits all curves, clamped to a sane minimum.
    var maxAbs = 6.0;
    for (final c in [target, before, after]) {
      for (final v in c) {
        if (v.isFinite && v.abs() > maxAbs) maxAbs = v.abs();
      }
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
      _label(canvas, f >= 1000 ? '${(f / 1000).toStringAsFixed(0)}k' : f.toStringAsFixed(0),
          Offset(x - 8, plotH + 2), Colors.white30, size: 8);
    }

    _drawCurve(canvas, size, yForDb, target, OptimizerPreviewGraph._targetColor,
        width: 1, dashed: true);
    _drawCurve(canvas, size, yForDb, before, OptimizerPreviewGraph._beforeColor,
        width: 1.5);
    _drawCurve(canvas, size, yForDb, after, OptimizerPreviewGraph._afterColor,
        width: 2);
  }

  void _drawCurve(Canvas canvas, Size size, double Function(double) yForDb,
      List<double> curve, Color color,
      {double width = 1.5, bool dashed = false}) {
    if (curve.length != freqs.length || curve.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
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
      if (prev != null) {
        if (dashed) {
          _dashLine(canvas, prev, p, paint);
        } else {
          canvas.drawLine(prev, p, paint);
        }
      }
      prev = p;
    }
  }

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final start = a + dir * d;
      final end = a + dir * math.min(d + dash, total);
      canvas.drawLine(start, end, paint);
      d += dash + gap;
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color,
      {double size = 9}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.target != target || old.before != before || old.after != after;
}
