import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_crossover_response.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';

/// One driver's crossover state for the XO response graph.
class XoGraphChannel {
  final String label;
  final DriverRole role;
  final CrossoverChannelState channel;
  final bool selected;

  const XoGraphChannel({
    required this.label,
    required this.role,
    required this.channel,
    this.selected = false,
  });
}

/// Crossover response graph: per-driver magnitude curves + power-summed curve
/// on a log 20 Hz–20 kHz axis, with a phase-preview placeholder strip.
///
/// Visualisation only — magnitudes come from [CrossoverResponse] (analog
/// approximation). No DSP write, address mapping, or phase model.
class ProCrossoverResponseGraph extends StatelessWidget {
  final List<XoGraphChannel> channels;
  final double height;

  const ProCrossoverResponseGraph({
    super.key,
    required this.channels,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: kProPanel,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _XoResponsePainter(channels: channels),
            ),
          ),
          // Phase-preview placeholder strip.
          const SizedBox(height: 4),
          Container(
            height: 22,
            width: double.infinity,
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.center,
            child: Text('PHASE PREVIEW — coming soon',
                style: proSubtitle(size: 8)),
          ),
        ],
      ),
    );
  }
}

Color _roleColor(DriverRole role) => switch (role) {
      DriverRole.tweeter || DriverRole.coaxTweeter => kProAmber,
      DriverRole.woofer || DriverRole.coaxWoofer => kProAccent,
      DriverRole.subwoofer => const Color(0xFF7E57C2),
      _ => Colors.white54,
    };

class _XoResponsePainter extends CustomPainter {
  final List<XoGraphChannel> channels;

  static const double _dbMin = -24;
  static const double _dbMax = 6;
  static const _freqGrid = <double>[
    20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000
  ];
  static const _dbGrid = <double>[6, 0, -6, -12, -18, -24];
  static const double _leftPad = 28;
  static const double _bottomPad = 14;

  _XoResponsePainter({required this.channels});

  double _x(double freq, Size size) {
    final plotW = size.width - _leftPad;
    final t = (math.log(freq) - math.log(CrossoverResponse.minHz)) /
        (math.log(CrossoverResponse.maxHz) - math.log(CrossoverResponse.minHz));
    return _leftPad + t.clamp(0.0, 1.0) * plotW;
  }

  double _y(double db, Size size) {
    final plotH = size.height - _bottomPad;
    final t = (db - _dbMin) / (_dbMax - _dbMin);
    return plotH - t.clamp(0.0, 1.0) * plotH;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final points = CrossoverResponse.logFrequencyPoints(count: 200);
    final curves = <List<double>>[];

    // Per-driver curves.
    for (final ch in channels) {
      final curve = CrossoverResponse.channelCurve(ch.channel, points);
      curves.add(curve);
      _drawCurve(canvas, size, points, curve, _roleColor(ch.role),
          strokeWidth: ch.selected ? 2.2 : 1.3);
    }

    // Power-summed curve on top.
    if (curves.isNotEmpty) {
      _drawCurve(
        canvas,
        size,
        points,
        CrossoverResponse.summedCurve(curves),
        Colors.white,
        strokeWidth: 1.8,
      );
    }

    _drawLegend(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = kProBorder
      ..strokeWidth = 0.5;
    final zeroPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.0;

    for (final f in _freqGrid) {
      final x = _x(f, size);
      canvas.drawLine(
          Offset(x, 0), Offset(x, size.height - _bottomPad), gridPaint);
      _label(canvas, _freqLabel(f), Offset(x, size.height - _bottomPad + 1),
          align: TextAlign.center);
    }
    for (final db in _dbGrid) {
      final y = _y(db, size);
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width, y),
          db == 0 ? zeroPaint : gridPaint);
      _label(canvas, '${db > 0 ? '+' : ''}${db.toInt()}', Offset(0, y - 5),
          align: TextAlign.left);
    }
  }

  void _drawCurve(Canvas canvas, Size size, List<double> freqs,
      List<double> db, Color color,
      {required double strokeWidth}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < freqs.length; i++) {
      final p = Offset(_x(freqs[i], size), _y(db[i], size));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawLegend(Canvas canvas, Size size) {
    final entries = <(Color, String)>[
      for (final ch in channels) (_roleColor(ch.role), ch.label),
      (Colors.white, 'summed'),
    ];
    var y = 2.0;
    for (final (color, label) in entries) {
      const swatchW = 12.0;
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: const TextStyle(color: Colors.white54, fontSize: 8)),
        textDirection: TextDirection.ltr,
      )..layout();
      final right = size.width - 2;
      final textLeft = right - tp.width;
      final swatchRight = textLeft - 4;
      canvas.drawLine(
        Offset(swatchRight - swatchW, y + tp.height / 2),
        Offset(swatchRight, y + tp.height / 2),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
      tp.paint(canvas, Offset(textLeft, y));
      y += tp.height + 2;
    }
  }

  void _label(Canvas canvas, String text, Offset at,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white38, fontSize: 8),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.center ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  static String _freqLabel(double f) => f >= 1000
      ? '${(f / 1000).toStringAsFixed(f % 1000 == 0 ? 0 : 1)}k'
      : '${f.toInt()}';

  @override
  bool shouldRepaint(_XoResponsePainter old) => true;
}
