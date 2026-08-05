import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/adau1701_peq_response.dart';
import '../../../shared/pro_widgets.dart';
import 'graph_overlay_models.dart';

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
///
/// v3-1: optional multi-channel overlay/difference display. When
/// [overlayCurves] is null or empty, this widget's layout and rendering are
/// byte-for-byte identical to before v3-1 — [mode]/[onModeChanged] are
/// ignored and no header controls are added. Overlay/difference curves are
/// computed via [PeqGraphCurve.curveFor], which delegates to the existing,
/// unmodified `Adau1701PeqResponse.combinedCurve` — no new PEQ calculation.
class Adau1701PeqResponseGraph extends StatelessWidget {
  final List<PeqResponseBand> bands;
  final int? selectedBandIndex;
  final List<PeqResponseBand>? baselineBands;
  final double height;

  /// When true (default) the Y-axis half-range auto-scales between ±6, ±9 and
  /// ±12 dB from the combined curve. When false it stays at ±6 dB.
  final bool autoScale;

  /// Additional named curves to compare (e.g. "Woofer L" / "Woofer R") — see
  /// [mode]. Null/empty keeps this graph in its original single-channel
  /// layout regardless of [mode].
  final List<PeqGraphCurve>? overlayCurves;

  /// Rendering mode when [overlayCurves] is non-empty. Ignored otherwise.
  /// Defaults to [PeqGraphMode.single], which never reads [overlayCurves].
  final PeqGraphMode mode;

  /// Called when the user taps a mode header button. Null hides interaction
  /// (the header still renders, showing the current [mode], but is inert) —
  /// this graph never owns mode state itself.
  final ValueChanged<PeqGraphMode>? onModeChanged;

  const Adau1701PeqResponseGraph({
    super.key,
    required this.bands,
    this.selectedBandIndex,
    this.baselineBands,
    this.height = 400,
    this.autoScale = true,
    this.overlayCurves,
    this.mode = PeqGraphMode.single,
    this.onModeChanged,
  });

  bool get _hasOverlay => overlayCurves != null && overlayCurves!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final painter = _PeqResponsePainter(
      bands: bands,
      selectedBandIndex: selectedBandIndex,
      baselineBands: baselineBands,
      autoScale: autoScale,
      mode: _hasOverlay ? mode : PeqGraphMode.single,
      overlayCurves: _hasOverlay ? overlayCurves : null,
    );

    if (!_hasOverlay) {
      // Pre-v3-1 layout, unchanged.
      return Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: kProPanel,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.fromLTRB(8, 10, 12, 6),
        child: CustomPaint(size: Size.infinite, painter: painter),
      );
    }

    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: kProPanel,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PeqGraphModeRow(mode: mode, onModeChanged: onModeChanged),
          const SizedBox(height: 4),
          Expanded(
            child: CustomPaint(size: Size.infinite, painter: painter),
          ),
        ],
      ),
    );
  }
}

/// [Single] [Overlay] [Difference] header controls — only ever built when
/// the graph has overlay curves to show (see [Adau1701PeqResponseGraph._hasOverlay]).
class _PeqGraphModeRow extends StatelessWidget {
  final PeqGraphMode mode;
  final ValueChanged<PeqGraphMode>? onModeChanged;

  const _PeqGraphModeRow({required this.mode, required this.onModeChanged});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in PeqGraphMode.values) ...[
            _ModeButton(
              mode: m,
              selected: m == mode,
              onTap: onModeChanged == null ? null : () => onModeChanged!(m),
            ),
            if (m != PeqGraphMode.values.last) const SizedBox(width: 4),
          ],
        ],
      );
}

class _ModeButton extends StatelessWidget {
  final PeqGraphMode mode;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeButton({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? kProAccent.withValues(alpha: 0.15) : null,
            border: Border.all(
              color: selected ? kProAccent : kProBorder,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            mode.label,
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
              color: selected ? kProAccent : Colors.white38,
            ),
          ),
        ),
      );
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

  final PeqGraphMode mode;
  final List<PeqGraphCurve>? overlayCurves;

  _PeqResponsePainter({
    required this.bands,
    required this.selectedBandIndex,
    required this.baselineBands,
    required this.autoScale,
    this.mode = PeqGraphMode.single,
    this.overlayCurves,
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

    if (mode == PeqGraphMode.overlay &&
        overlayCurves != null &&
        overlayCurves!.isNotEmpty) {
      _paintOverlay(canvas, size, points);
      return;
    }
    if (mode == PeqGraphMode.difference &&
        overlayCurves != null &&
        overlayCurves!.length == 2) {
      _paintDifference(canvas, size, points);
      return;
    }

    // Original single-channel path — unchanged.
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

  /// v3-1: draws every curve in [overlayCurves] together, each via
  /// [PeqGraphCurve.curveFor] (delegates to the unmodified
  /// `Adau1701PeqResponse.combinedCurve`) sampled at the same [points] grid.
  void _paintOverlay(Canvas canvas, Size size, List<double> points) {
    final curves = overlayCurves!;
    final computed = <List<double>>[];
    final allDb = <double>[];
    for (final c in curves) {
      final curve = c.curveFor(points);
      computed.add(curve);
      allDb.addAll(curve);
    }
    final range =
        autoScale ? Adau1701PeqResponse.autoScaleDbRange(allDb) : _minRange;

    _drawGrid(canvas, size, range);
    for (var i = 0; i < curves.length; i++) {
      final color = curves[i].color ??
          peqGraphOverlayPalette[i % peqGraphOverlayPalette.length];
      _drawCurve(canvas, size, points, computed[i], color, range,
          strokeWidth: 1.6);
    }
    _drawCustomLegend(canvas, size, [
      for (var i = 0; i < curves.length; i++)
        (
          curves[i].color ??
              peqGraphOverlayPalette[i % peqGraphOverlayPalette.length],
          curves[i].label
        ),
    ]);
  }

  /// v3-1: draws `overlayCurves[0] - overlayCurves[1]` (display-only,
  /// [PeqGraphOverlayMath.difference]) — never shown unless both curves were
  /// sampled at the same frequency grid (guaranteed here since both use the
  /// same [points]); the null-check below covers the general contract of
  /// [PeqGraphOverlayMath.difference] for any future direct callers.
  void _paintDifference(Canvas canvas, Size size, List<double> points) {
    final curves = overlayCurves!;
    final a = curves[0].curveFor(points);
    final b = curves[1].curveFor(points);
    final diff = PeqGraphOverlayMath.difference(a, b);

    final range = autoScale && diff != null
        ? Adau1701PeqResponse.autoScaleDbRange(diff)
        : _minRange;
    _drawGrid(canvas, size, range);

    if (diff == null) {
      // Insufficient data (mismatched/empty curves) — grid only, no curve,
      // per the "difference not shown when data insufficient" requirement.
      return;
    }
    _drawCurve(canvas, size, points, diff, kProAmber, range,
        strokeWidth: 1.6);
    _drawCustomLegend(canvas, size, [
      (kProAmber, '${curves[0].label} − ${curves[1].label}'),
    ]);
  }

  /// Shared legend painter for overlay/difference modes — separate from the
  /// original single-mode [_drawLegend] so that method's before/after
  /// behaviour is untouched.
  void _drawCustomLegend(Canvas canvas, Size size, List<(Color, String)> entries) {
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
    if (old.mode != mode) return true;
    if (_overlayCurvesDiffer(old.overlayCurves, overlayCurves)) return true;
    return false;
  }

  static bool _overlayCurvesDiffer(
      List<PeqGraphCurve>? a, List<PeqGraphCurve>? b) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label || a[i].color != b[i].color) return true;
      if (_bandsDiffer(a[i].bands, b[i].bands)) return true;
    }
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
