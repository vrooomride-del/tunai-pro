// ── TUNAI PRO Phase 3-C — Calibration curve preview ─────────────────────────
//
// Renders a MICROPHONE CALIBRATION curve (frequency correction, dB, applied
// to what the mic hears) — never an acoustic/speaker response or PEQ curve.
// Titles and labels below say "Calibration Curve" / "Correction (dB)"
// explicitly so this can never be mistaken for a driver FRD or Auto PEQ
// graph elsewhere in the app.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/calibration/calibration_types.dart';
import '../../shared/pro_widgets.dart';

class CalibrationCurvePreview extends StatelessWidget {
  final CalibrationCurve? curve;

  const CalibrationCurvePreview({super.key, required this.curve});

  @override
  Widget build(BuildContext context) {
    final c = curve;
    if (c == null || c.points.isEmpty || !c.isStructurallyValid) {
      return Container(
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kProPanel,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          c == null ? 'No calibration curve loaded.' : '보정 곡선에 유효한 데이터가 없습니다.',
          style: proSubtitle(size: 11),
        ),
      );
    }

    final corrections = c.points.map((p) => p.correctionDb).toList();
    final minCorrection = corrections.reduce(math.min);
    final maxCorrection = corrections.reduce(math.max);
    final checksumShort =
        c.checksum.length >= 8 ? c.checksum.substring(0, 8) : c.checksum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CALIBRATION CURVE', style: proLabel(size: 10)),
        const SizedBox(height: 6),
        Container(
          height: 140,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kProPanel,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            painter: _CalibrationCurvePainter(curve: c),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 4, children: [
          _InfoItem('Points', '${c.points.length}'),
          _InfoItem('Valid range',
              '${c.validMinFrequencyHz.toStringAsFixed(0)}–${c.validMaxFrequencyHz.toStringAsFixed(0)} Hz'),
          _InfoItem('Correction range',
              '${minCorrection.toStringAsFixed(2)} to ${maxCorrection.toStringAsFixed(2)} dB'),
          _InfoItem('Angle', c.angle.label),
          _InfoItem('Source', c.sourceIdentity),
          _InfoItem('Checksum', checksumShort),
        ]),
        if (c.parserWarnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kProAmber.withValues(alpha: 0.08),
              border: Border.all(color: kProAmber.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Warnings',
                    style: TextStyle(color: kProAmber, fontSize: 11)),
                const SizedBox(height: 4),
                for (final w in c.parserWarnings)
                  Text(w, style: proSubtitle(size: 10)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: proLabel(size: 9)),
          Text(value, style: proValue(size: 11)),
        ],
      );
}

class _CalibrationCurvePainter extends CustomPainter {
  final CalibrationCurve curve;
  _CalibrationCurvePainter({required this.curve});

  static double _log10(double v) => math.log(v) / math.ln10;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final freqMin = curve.validMinFrequencyHz;
    final freqMax = curve.validMaxFrequencyHz;
    if (!freqMin.isFinite || !freqMax.isFinite || freqMax <= freqMin) return;

    final corrections = curve.points.map((p) => p.correctionDb).toList();
    final rawMin = corrections.reduce(math.min);
    final rawMax = corrections.reduce(math.max);
    // Never shrink an out-of-proportion correction to "look normal" — pad a
    // small margin around the actual data range, with a sane minimum span
    // so a near-flat curve doesn't render as a single edge-to-edge line.
    final span = math.max(rawMax - rawMin, 1.0);
    final dbMin = rawMin - span * 0.15;
    final dbMax = rawMax + span * 0.15;

    final logMin = _log10(freqMin);
    final logMax = _log10(freqMax);

    double xFor(double freqHz) =>
        (_log10(freqHz) - logMin) / (logMax - logMin) * size.width;
    double yFor(double db) =>
        size.height - (db - dbMin) / (dbMax - dbMin) * size.height;

    final gridPaint = Paint()
      ..color = kProBorder
      ..strokeWidth = 0.5;
    // 0 dB reference line, only if within range.
    if (dbMin < 0 && dbMax > 0) {
      final y0 = yFor(0);
      canvas.drawLine(Offset(0, y0), Offset(size.width, y0), gridPaint);
    }

    final linePaint = Paint()
      ..color = kProAccent
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var i = 0; i < curve.points.length; i++) {
      final p = curve.points[i];
      final x = xFor(p.frequencyHz);
      final y = yFor(p.correctionDb);
      if (!x.isFinite || !y.isFinite) continue;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    final pointPaint = Paint()..color = kProAccent;
    for (final p in curve.points) {
      final x = xFor(p.frequencyHz);
      final y = yFor(p.correctionDb);
      if (!x.isFinite || !y.isFinite) continue;
      canvas.drawCircle(Offset(x, y), 2.0, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CalibrationCurvePainter oldDelegate) =>
      oldDelegate.curve.checksum != curve.checksum;
}
