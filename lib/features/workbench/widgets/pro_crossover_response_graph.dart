import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_crossover_response.dart';
import '../../../core/pro_phase_alignment.dart';
import '../../../core/pro_phase_response.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../shared/pro_widgets.dart';

/// One driver's crossover + phase state for the XO response graph.
class XoGraphChannel {
  final String label;
  final DriverRole role;
  final CrossoverChannelState channel;
  final bool selected;

  /// Per-driver alignment delay (ms) and static phase offset (deg) from the
  /// project's channel-control state. Drive the phase-simulation panel.
  final double delayMs;
  final double phaseOffsetDeg;

  const XoGraphChannel({
    required this.label,
    required this.role,
    required this.channel,
    this.selected = false,
    this.delayMs = 0.0,
    this.phaseOffsetDeg = 0.0,
  });

  XoPhaseDriver get phaseDriver => XoPhaseDriver(
        channel: channel,
        delayMs: delayMs,
        phaseOffsetDeg: phaseOffsetDeg,
      );
}

/// Crossover response graph: per-driver magnitude curves + power-summed curve
/// on a log 20 Hz–20 kHz axis, with a phase-alignment strip below it.
///
/// Visualisation only — magnitudes come from [CrossoverResponse] (analog
/// approximation), phase from [CrossoverPhase]. No DSP write, address
/// mapping, or algorithm changes here.
class ProCrossoverResponseGraph extends StatelessWidget {
  final List<XoGraphChannel> channels;
  final double height;

  /// Optional, already-computed crossover pairs (e.g. from
  /// `XoPhaseAlignment.analyze(...)`, as xo_tab.dart's phase-alignment card
  /// already does) — when supplied, each pair's `crossoverHz` is drawn as a
  /// vertical marker on both panels. This widget never computes crossoverHz
  /// itself (no duplicated math): it only reads the already-public
  /// [XoAlignmentPair.crossoverHz] field the caller passes in.
  final List<XoAlignmentPair>? alignmentPairs;

  const ProCrossoverResponseGraph({
    super.key,
    required this.channels,
    this.height = 300,
    this.alignmentPairs,
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
          Text('MAGNITUDE (dB)', style: proSubtitle(size: 8)),
          Expanded(
            flex: 3,
            child: CustomPaint(
              size: Size.infinite,
              painter: _XoResponsePainter(
                  channels: channels, alignmentPairs: alignmentPairs),
            ),
          ),
          const SizedBox(height: 6),
          Text('PHASE ALIGNMENT (°)', style: proSubtitle(size: 8)),
          Expanded(
            flex: 2,
            child: CustomPaint(
              size: Size.infinite,
              painter: _XoPhasePainter(
                  channels: channels, alignmentPairs: alignmentPairs),
            ),
          ),
        ],
      ),
    );
  }
}

Color _alignmentStatusColor(XoAlignmentStatus status) => switch (status) {
      XoAlignmentStatus.good => kProGreen,
      XoAlignmentStatus.check => kProAmber,
      XoAlignmentStatus.misalign => kProRed,
    };

Color _roleColor(DriverRole role) => switch (role) {
      DriverRole.tweeter || DriverRole.coaxTweeter => kProAmber,
      DriverRole.woofer || DriverRole.coaxWoofer => kProAccent,
      DriverRole.subwoofer => const Color(0xFF7E57C2),
      _ => Colors.white54,
    };

class _XoResponsePainter extends CustomPainter {
  final List<XoGraphChannel> channels;
  final List<XoAlignmentPair>? alignmentPairs;

  static const double _dbMin = -24;
  static const double _dbMax = 6;
  static const _freqGrid = <double>[
    20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000
  ];
  static const _dbGrid = <double>[6, 0, -6, -12, -18, -24];
  static const double _leftPad = 28;
  static const double _bottomPad = 14;

  _XoResponsePainter({required this.channels, this.alignmentPairs});

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

    // Per-driver curves. Selected drivers get a soft halo behind the line
    // (a wider, low-alpha pass of the same curve) so the active channel
    // reads clearly even with several overlapping curves — visual-only,
    // the curve data itself is identical to the non-selected case.
    for (final ch in channels) {
      final curve = CrossoverResponse.channelCurve(ch.channel, points);
      curves.add(curve);
      final color = _roleColor(ch.role);
      if (ch.selected) {
        _drawCurve(canvas, size, points, curve, color.withValues(alpha: 0.28),
            strokeWidth: 5.5);
      }
      _drawCurve(canvas, size, points, curve, color,
          strokeWidth: ch.selected ? 2.4 : 1.3);
    }

    // Power-summed curve on top — the answer to "what does the listener
    // actually hear" — emphasized with a heavier stroke than any single
    // driver curve so it reads as the primary curve, not just another line.
    if (curves.isNotEmpty) {
      _drawCurve(
        canvas,
        size,
        points,
        CrossoverResponse.summedCurve(curves),
        Colors.white,
        strokeWidth: 2.6,
      );
    }

    _drawCrossoverMarkers(canvas, size);
    _drawLegend(canvas, size);
  }

  /// Vertical marker + frequency label at each already-computed
  /// [XoAlignmentPair.crossoverHz] — no crossover-point math happens here,
  /// this only reads the field the caller (xo_tab.dart) already computed via
  /// XoPhaseAlignment.analyze(...).
  void _drawCrossoverMarkers(Canvas canvas, Size size) {
    final pairs = alignmentPairs;
    if (pairs == null || pairs.isEmpty) return;
    for (final pair in pairs) {
      final x = _x(pair.crossoverHz, size);
      final color = _alignmentStatusColor(pair.status);
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = 1.0;
      _drawDashedVertical(
          canvas, Offset(x, 0), size.height - _bottomPad, linePaint);
      _label(canvas, _freqLabel(pair.crossoverHz), Offset(x, 2),
          align: TextAlign.center, color: color);
    }
  }

  void _drawDashedVertical(
      Canvas canvas, Offset top, double bottom, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    var y = top.dy;
    while (y < bottom) {
      final segEnd = (y + dash).clamp(0.0, bottom);
      canvas.drawLine(Offset(top.dx, y), Offset(top.dx, segEnd), paint);
      y += dash + gap;
    }
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
    final entries = <(Color, String, bool)>[
      for (final ch in channels) (_roleColor(ch.role), ch.label, false),
      (Colors.white, 'SUMMED RESPONSE', true),
    ];
    var y = 2.0;
    for (final (color, label, emphasize) in entries) {
      final swatchW = emphasize ? 16.0 : 12.0;
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                color: emphasize ? Colors.white : Colors.white54,
                fontSize: 8,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400)),
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
          ..strokeWidth = emphasize ? 3 : 2,
      );
      tp.paint(canvas, Offset(textLeft, y));
      y += tp.height + 2;
    }
  }

  void _label(Canvas canvas, String text, Offset at,
      {TextAlign align = TextAlign.left, Color color = Colors.white38}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 8),
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

/// Phase-simulation panel: per-driver phase curves + complex-summed phase,
/// wrapped −180..+180°, on the same log 20 Hz–20 kHz axis.
class _XoPhasePainter extends CustomPainter {
  final List<XoGraphChannel> channels;
  final List<XoAlignmentPair>? alignmentPairs;

  static const double _degMax = 180;
  static const double _degMin = -180;
  static const _freqGrid = <double>[20, 100, 1000, 10000, 20000];
  static const _degGrid = <double>[180, 90, 0, -90, -180];
  static const double _leftPad = 28;
  static const double _bottomPad = 12;

  _XoPhasePainter({required this.channels, this.alignmentPairs});

  double _x(double freq, Size size) {
    final plotW = size.width - _leftPad;
    final t = (math.log(freq) - math.log(CrossoverResponse.minHz)) /
        (math.log(CrossoverResponse.maxHz) - math.log(CrossoverResponse.minHz));
    return _leftPad + t.clamp(0.0, 1.0) * plotW;
  }

  double _y(double deg, Size size) {
    final plotH = size.height - _bottomPad;
    final t = (deg - _degMin) / (_degMax - _degMin);
    return plotH - t.clamp(0.0, 1.0) * plotH;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = kProBorder
      ..strokeWidth = 0.5;
    final zero = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.0;
    for (final f in _freqGrid) {
      final x = _x(f, size);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height - _bottomPad), grid);
    }
    for (final d in _degGrid) {
      final y = _y(d, size);
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width, y),
          d == 0 ? zero : grid);
      _label(canvas, '${d > 0 ? '+' : ''}${d.toInt()}', Offset(0, y - 5));
    }

    if (channels.isEmpty) return;
    final points = CrossoverResponse.logFrequencyPoints(count: 200);

    // Per-driver phase (wrapped) — split into segments to avoid drawing the
    // vertical line across a −180/+180 wrap. Selected drivers get the same
    // soft-halo treatment as the magnitude panel for consistent emphasis.
    for (final ch in channels) {
      final curve = CrossoverPhase.driverPhaseCurve(
        channel: ch.channel,
        delayMs: ch.delayMs,
        phaseOffsetDeg: ch.phaseOffsetDeg,
        freqs: points,
      );
      final color = _roleColor(ch.role);
      if (ch.selected) {
        _drawWrapped(canvas, size, points, curve, color.withValues(alpha: 0.28),
            strokeWidth: 4.5);
      }
      _drawWrapped(canvas, size, points, curve, color,
          strokeWidth: ch.selected ? 1.8 : 1.1);
    }

    // Complex-summed phase — the same emphasis treatment as the magnitude
    // panel's summed curve.
    final summed = CrossoverPhase.summedPhaseCurve(
      drivers: [for (final ch in channels) ch.phaseDriver],
      freqs: points,
    );
    _drawWrapped(canvas, size, points, summed, Colors.white, strokeWidth: 2.2);

    _drawCrossoverMarkers(canvas, size);
  }

  /// Same already-computed crossoverHz markers as the magnitude panel — no
  /// duplicated crossover-point math, just reads [XoAlignmentPair.crossoverHz].
  void _drawCrossoverMarkers(Canvas canvas, Size size) {
    final pairs = alignmentPairs;
    if (pairs == null || pairs.isEmpty) return;
    for (final pair in pairs) {
      final x = _x(pair.crossoverHz, size);
      final color = _alignmentStatusColor(pair.status);
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = 1.0;
      canvas.drawLine(
          Offset(x, 0), Offset(x, size.height - _bottomPad), linePaint);
    }
  }

  void _drawWrapped(Canvas canvas, Size size, List<double> freqs,
      List<double> deg, Color color,
      {required double strokeWidth}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    Offset? prev;
    for (var i = 0; i < freqs.length; i++) {
      final p = Offset(_x(freqs[i], size), _y(deg[i], size));
      // Break the line when the wrapped phase jumps more than 180°.
      if (prev != null && (deg[i] - deg[i - 1]).abs() <= 180) {
        canvas.drawLine(prev, p, paint);
      }
      prev = p;
    }
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(color: Colors.white38, fontSize: 8)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_XoPhasePainter old) => true;
}
