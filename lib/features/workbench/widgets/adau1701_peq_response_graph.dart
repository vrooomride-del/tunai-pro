import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/adau1701_peq_response.dart';
import '../../../shared/pro_widgets.dart';

/// PEQ response graph for one ADAU1701 output (its 10 fixed bands).
///
/// - X axis: logarithmic 20 Hz .. 20 kHz
/// - Y axis: dB (fixed −18 .. +18 for readability)
/// - Combined total curve (enabled bands only)
/// - Optional highlighted curve for [selectedBandIndex]
/// - Optional [baselineBands] curve drawn behind the edited/total curve
class Adau1701PeqResponseGraph extends StatelessWidget {
  final List<PeqResponseBand> bands;
  final int? selectedBandIndex;
  final List<PeqResponseBand>? baselineBands;
  final double height;

  const Adau1701PeqResponseGraph({
    super.key,
    required this.bands,
    this.selectedBandIndex,
    this.baselineBands,
    this.height = 400,
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
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 6),
      child: CustomPaint(
        size: Size.infinite,
        painter: _PeqResponsePainter(
          bands: bands,
          selectedBandIndex: selectedBandIndex,
          baselineBands: baselineBands,
        ),
      ),
    );
  }
}

class _PeqResponsePainter extends CustomPainter {
  final List<PeqResponseBand> bands;
  final int? selectedBandIndex;
  final List<PeqResponseBand>? baselineBands;

  static const double _dbMin = -18;
  static const double _dbMax = 18;
  static const _freqGrid = <double>[
    20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000
  ];
  static const _dbGrid = <double>[-12, -6, 0, 6, 12];

  _PeqResponsePainter({
    required this.bands,
    required this.selectedBandIndex,
    required this.baselineBands,
  });

  static const double _leftPad = 28; // room for dB labels
  static const double _bottomPad = 16; // room for Hz labels

  double _x(double freq, Size size) {
    final plotW = size.width - _leftPad;
    final t = (math.log(freq) - math.log(Adau1701PeqResponse.minHz)) /
        (math.log(Adau1701PeqResponse.maxHz) -
            math.log(Adau1701PeqResponse.minHz));
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

    final points = Adau1701PeqResponse.logFrequencyPoints(count: 220);

    // Baseline (current) curve — drawn first, muted.
    final baseline = baselineBands;
    if (baseline != null) {
      _drawCurve(
        canvas,
        size,
        points,
        Adau1701PeqResponse.combinedCurve(baseline, points),
        Colors.white24,
        strokeWidth: 1.0,
      );
    }

    // Highlighted selected band.
    final idx = selectedBandIndex;
    if (idx != null && idx >= 0 && idx < bands.length && bands[idx].enabled) {
      _drawCurve(
        canvas,
        size,
        points,
        Adau1701PeqResponse.bandCurve(bands[idx], points),
        kProAmber.withValues(alpha: 0.7),
        strokeWidth: 1.2,
      );
    }

    // Combined total curve (enabled bands only) — drawn on top.
    _drawCurve(
      canvas,
      size,
      points,
      Adau1701PeqResponse.combinedCurve(bands, points),
      kProAccent,
      strokeWidth: 1.6,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = kProBorder
      ..strokeWidth = 0.5;
    final zeroPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.8;

    for (final f in _freqGrid) {
      final x = _x(f, size);
      canvas.drawLine(
          Offset(x, 0), Offset(x, size.height - _bottomPad), gridPaint);
      _label(canvas, _freqLabel(f), Offset(x, size.height - _bottomPad + 2),
          align: TextAlign.center);
    }
    for (final db in _dbGrid) {
      final y = _y(db, size);
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width, y),
          db == 0 ? zeroPaint : gridPaint);
      _label(canvas, '${db > 0 ? '+' : ''}${db.toInt()}',
          Offset(0, y - 5), align: TextAlign.left);
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
    final dx = switch (align) {
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy));
  }

  static String _freqLabel(double f) =>
      f >= 1000 ? '${(f / 1000).toStringAsFixed(f % 1000 == 0 ? 0 : 1)}k' : '${f.toInt()}';

  @override
  bool shouldRepaint(_PeqResponsePainter old) =>
      old.bands != bands ||
      old.selectedBandIndex != selectedBandIndex ||
      old.baselineBands != baselineBands;
}
