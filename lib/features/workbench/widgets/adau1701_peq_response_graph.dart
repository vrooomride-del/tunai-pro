import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/adau1701_peq_response.dart';
import '../../../shared/pro_widgets.dart';

/// PEQ response graph for one ADAU1701 output (its 10 fixed bands).
///
/// - X axis: logarithmic 20 Hz .. 20 kHz
/// - Y axis: dB, symmetric about 0 dB. Default ±6 dB so small PEQ changes are
///   clearly visible; with [autoScale] it widens to ±9 or ±12 dB only when the
///   combined curve needs the extra headroom.
/// - Combined total curve (enabled bands only) — the "after" curve
/// - Optional highlighted curve + on-curve marker and frequency/gain readout
///   for [selectedBandIndex]
/// - Optional [baselineBands] "before" curve drawn behind, with a before/after
///   legend
class Adau1701PeqResponseGraph extends StatelessWidget {
  final List<PeqResponseBand> bands;
  final int? selectedBandIndex;
  final List<PeqResponseBand>? baselineBands;
  final double height;

  /// When true (default) the Y-axis half-range auto-scales between ±6, ±9 and
  /// ±12 dB from the combined curve. When false it stays at ±6 dB.
  final bool autoScale;

  const Adau1701PeqResponseGraph({
    super.key,
    required this.bands,
    this.selectedBandIndex,
    this.baselineBands,
    this.height = 400,
    this.autoScale = true,
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
          autoScale: autoScale,
        ),
      ),
    );
  }
}

class _PeqResponsePainter extends CustomPainter {
  final List<PeqResponseBand> bands;
  final int? selectedBandIndex;
  final List<PeqResponseBand>? baselineBands;
  final bool autoScale;

  /// Tightest (default) symmetric Y half-range, in dB.
  static const double _minRange = 6;

  static const _freqGrid = <double>[
    20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000
  ];

  _PeqResponsePainter({
    required this.bands,
    required this.selectedBandIndex,
    required this.baselineBands,
    required this.autoScale,
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

  double _y(double db, Size size, double range) {
    final plotH = size.height - _bottomPad;
    final t = (db + range) / (2 * range);
    return plotH - t.clamp(0.0, 1.0) * plotH;
  }

  /// dB grid lines for [range]: 2 dB steps at ±6, 3 dB steps at ±9 / ±12.
  List<int> _dbGridLines(double range) {
    final r = range.round();
    final step = range <= _minRange ? 2 : 3;
    return [for (var v = -r; v <= r; v += step) v];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final points = Adau1701PeqResponse.logFrequencyPoints(count: 220);
    // Combined total curve (enabled bands only) — also drives auto-scale.
    final combined = Adau1701PeqResponse.combinedCurve(bands, points);
    final range =
        autoScale ? Adau1701PeqResponse.autoScaleDbRange(combined) : _minRange;

    _drawGrid(canvas, size, range);

    // Baseline (current) curve — drawn first, muted.
    final baseline = baselineBands;
    if (baseline != null) {
      _drawCurve(
        canvas,
        size,
        points,
        Adau1701PeqResponse.combinedCurve(baseline, points),
        Colors.white24,
        range,
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
        range,
        strokeWidth: 1.2,
      );
    }

    // Combined total curve ("after") — drawn on top.
    _drawCurve(canvas, size, points, combined, kProAccent, range,
        strokeWidth: 1.6);

    // Selected-band marker + frequency/gain readout.
    final si = selectedBandIndex;
    if (si != null && si >= 0 && si < bands.length && bands[si].enabled) {
      _drawSelectedMarker(canvas, size, bands[si], combined, points, range);
    }

    // before/after legend.
    _drawLegend(canvas, size, showBefore: baseline != null);
  }

  void _drawSelectedMarker(Canvas canvas, Size size, PeqResponseBand band,
      List<double> combined, List<double> points, double range) {
    final f = band.frequencyHz
        .clamp(Adau1701PeqResponse.minHz, Adau1701PeqResponse.maxHz)
        .toDouble();
    // Sit the marker on the combined ("after") curve at the band's centre.
    final markerDb = Adau1701PeqResponse.combinedMagnitudeDb(bands, f);
    final mx = _x(f, size);
    final my = _y(markerDb, size, range);

    canvas.drawCircle(Offset(mx, my), 4,
        Paint()..color = kProAmber);
    canvas.drawCircle(
        Offset(mx, my),
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    final g = band.gainDb;
    final readout =
        '${_freqReadout(f)}  ·  ${g >= 0 ? '+' : ''}${g.toStringAsFixed(1)} dB';
    _readoutLabel(canvas, size, readout, Offset(mx, my));
  }

  void _readoutLabel(Canvas canvas, Size size, String text, Offset marker) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: kProAmber, fontSize: 9, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const pad = 3.0;
    var left = marker.dx + 8;
    var top = marker.dy - tp.height - 8;
    // Keep the readout inside the plot.
    if (left + tp.width + pad * 2 > size.width) {
      left = marker.dx - tp.width - 8 - pad * 2;
    }
    if (left < _leftPad) left = _leftPad;
    if (top < 0) top = marker.dy + 8;
    final rect = Rect.fromLTWH(
        left, top, tp.width + pad * 2, tp.height + pad * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    tp.paint(canvas, Offset(left + pad, top + pad));
  }

  void _drawLegend(Canvas canvas, Size size, {required bool showBefore}) {
    final entries = <(Color, String)>[
      if (showBefore) (Colors.white38, 'before'),
      (kProAccent, 'after'),
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
      y += tp.height + 3;
    }
  }

  static String _freqReadout(double f) =>
      f >= 1000 ? '${(f / 1000).toStringAsFixed(1)} kHz' : '${f.round()} Hz';

  void _drawGrid(Canvas canvas, Size size, double range) {
    final gridPaint = Paint()
      ..color = kProBorder
      ..strokeWidth = 0.5;
    // 0 dB reference line is brighter and thicker so the centre is obvious.
    final zeroPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.4;

    for (final f in _freqGrid) {
      final x = _x(f, size);
      canvas.drawLine(
          Offset(x, 0), Offset(x, size.height - _bottomPad), gridPaint);
      _label(canvas, _freqLabel(f), Offset(x, size.height - _bottomPad + 2),
          align: TextAlign.center);
    }
    for (final db in _dbGridLines(range)) {
      final y = _y(db.toDouble(), size, range);
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width, y),
          db == 0 ? zeroPaint : gridPaint);
      _label(canvas, '${db > 0 ? '+' : ''}$db', Offset(0, y - 5),
          align: TextAlign.left);
    }
  }

  void _drawCurve(Canvas canvas, Size size, List<double> freqs,
      List<double> db, Color color, double range,
      {required double strokeWidth}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < freqs.length; i++) {
      final p = Offset(_x(freqs[i], size), _y(db[i], size, range));
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
  bool shouldRepaint(_PeqResponsePainter old) {
    // The band list can be mutated in place by the caller (the ICP5 tuning
    // panel edits its 4×10 model in place and passes the same list instance),
    // so identity/length checks are unreliable. Compare field values so a
    // frequency/gain/Q/enabled edit always repaints the curve.
    if (old.autoScale != autoScale) return true;
    if (old.selectedBandIndex != selectedBandIndex) return true;
    if (_bandsDiffer(old.bands, bands)) return true;
    if (_bandsDiffer(old.baselineBands, baselineBands)) return true;
    return false;
  }

  static bool _bandsDiffer(
      List<PeqResponseBand>? a, List<PeqResponseBand>? b) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.enabled != y.enabled ||
          x.frequencyHz != y.frequencyHz ||
          x.gainDb != y.gainDb ||
          x.q != y.q) {
        return true;
      }
    }
    return false;
  }
}
