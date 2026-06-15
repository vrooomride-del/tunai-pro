import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import '../dsp_state.dart';
import '../../../core/dsp_engine.dart' as engine;

class DspBodePlot extends StatelessWidget {
  final List<PeqBand> bands;
  final CrossoverFilter hpFilter;
  final CrossoverFilter lpFilter;
  final double gainDb;
  const DspBodePlot({
    super.key,
    required this.bands,
    required this.hpFilter,
    required this.lpFilter,
    required this.gainDb,
  });

  @override
  Widget build(BuildContext context) {
    final response = _computeResponse();
    if (response.isEmpty) return const SizedBox(height: 220);

    final spots = response.map((r) {
      final logF = log(r['f']!) / log(10);
      return FlSpot(logF, r['db']!.clamp(-42.0, 24.0));
    }).toList();

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
      child: LineChart(
        LineChartData(
          backgroundColor: Colors.transparent,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Colors.white10, strokeWidth: 0.5),
            getDrawingVerticalLine: (_) =>
                const FlLine(color: Colors.white10, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 0.5,
                getTitlesWidget: (v, _) {
                  const labels = {20: '20', 50: '50', 100: '100', 200: '200',
                    500: '500', 1000: '1k', 2000: '2k', 5000: '5k',
                    10000: '10k', 20000: '20k'};
                  for (final e in labels.entries) {
                    if ((log(e.key) / log(10) - v).abs() < 0.03) {
                      return Text(e.value,
                          style: const TextStyle(color: Colors.white24, fontSize: 7));
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 6,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: const TextStyle(color: Colors.white24, fontSize: 7)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: log(20) / log(10),
          maxX: log(20000) / log(10),
          minY: -42, maxY: 24,
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(y: 0, color: Colors.white24, strokeWidth: 0.5),
            ],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.white,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, double>> _computeResponse() {
    const points = 300;
    final result = <Map<String, double>>[];

    for (int i = 0; i < points; i++) {
      final f = 20 * pow(1000, i / (points - 1)).toDouble();
      double totalDb = gainDb;

      // PEQ 밴드
      for (final band in bands) {
        if (!band.enabled) continue;
        final filter = engine.BiquadFilter(
          frequency: band.frequency,
          gainDb: band.gainDb,
          q: band.q,
          type: _mapType(band.type),
        );
        final coeff = engine.DspEngine.calculate(filter);
        totalDb += _biquadResponse(coeff, f);
      }

      // HP 크로스오버
      if (hpFilter.type != CrossoverType.bypass) {
        totalDb += _crossoverResponse(hpFilter, f, isHP: true);
      }

      // LP 크로스오버
      if (lpFilter.type != CrossoverType.bypass) {
        totalDb += _crossoverResponse(lpFilter, f, isHP: false);
      }

      result.add({'f': f, 'db': totalDb});
    }
    return result;
  }

  double _biquadResponse(engine.BiquadCoefficients c, double freq) {
    const sr = 48000;
    final w = 2 * pi * freq / sr;
    final cosW = cos(w); final sinW = sin(w);
    final cos2W = cos(2 * w); final sin2W = sin(2 * w);
    final numRe = c.b0 + c.b1 * cosW + c.b2 * cos2W;
    final numIm = c.b1 * sinW + c.b2 * sin2W;
    final denRe = 1 - c.a1 * cosW - c.a2 * cos2W;
    final denIm = -(-c.a1 * sinW - c.a2 * sin2W);
    final num = sqrt(numRe * numRe + numIm * numIm);
    final den = sqrt(denRe * denRe + denIm * denIm);
    if (den <= 0 || num <= 0) return 0;
    return 20 * log(num / den) / ln10;
  }

  double _crossoverResponse(CrossoverFilter xo, double freq, {required bool isHP}) {
    final fc = xo.frequency;
    final ratio = isHP ? freq / fc : fc / freq;
    int order;
    bool isLR;
    switch (xo.type) {
      case CrossoverType.butterworth12: order = 1; isLR = false; break;
      case CrossoverType.butterworth24: order = 2; isLR = false; break;
      case CrossoverType.lr12: order = 1; isLR = true; break;
      case CrossoverType.lr24: order = 2; isLR = true; break;
      case CrossoverType.lr48: order = 4; isLR = true; break;
      default: return 0;
    }
    final n = isLR ? order * 2 : order;
    final mag = 1 / sqrt(1 + pow(1 / ratio, 2 * n));
    return 20 * log(mag) / ln10;
  }

  engine.FilterType _mapType(FilterType t) {
    switch (t) {
      case FilterType.peaking:   return engine.FilterType.peaking;
      case FilterType.lowShelf:  return engine.FilterType.lowShelf;
      case FilterType.highShelf: return engine.FilterType.highShelf;
      case FilterType.lowPass:   return engine.FilterType.lowPass;
      case FilterType.highPass:  return engine.FilterType.highPass;
      case FilterType.notch:     return engine.FilterType.notch;
      case FilterType.allPass:   return engine.FilterType.peaking;
    }
  }
}
