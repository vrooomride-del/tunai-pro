import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/spectrum_snapshot.dart';

/// 주파수 응답 Before/After 오버레이 차트 (로그 스케일 X축, 20Hz–20kHz)
///
/// - 회색 점선: Flat 기준 (0 dB)
/// - 빨강: before (측정 원본)
/// - 초록: afterAi (AI 보정 후 예측)
class FrequencyResponseChart extends StatelessWidget {
  final List<FrequencyBin>? before;
  final List<FrequencyBin>? afterAi;
  final double height;

  const FrequencyResponseChart({
    super.key,
    this.before,
    this.afterAi,
    this.height = 200,
  });

  static const double _logMin = 1.30103; // log10(20)
  static const double _logMax = 4.30103; // log10(20000)

  static const _labelFreqs = [
    20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0
  ];
  static const _labelStrs = [
    '20', '50', '100', '200', '500', '1k', '2k', '5k', '10k', '20k'
  ];

  List<FlSpot> _toSpots(List<FrequencyBin>? bins) {
    if (bins == null) return [];
    return bins
        .where((b) => b.frequency >= 20 && b.frequency <= 20000)
        .map((b) => FlSpot(
              math.log(b.frequency) / math.ln10,
              b.magnitude.clamp(-30.0, 30.0),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final beforeSpots = _toSpots(before);
    final afterSpots = _toSpots(afterAi);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          backgroundColor: Colors.transparent,
          minX: _logMin,
          maxX: _logMax,
          minY: -20,
          maxY: 20,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 10,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Color(0xFF1E1E1E),
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 10,
                reservedSize: 30,
                getTitlesWidget: (v, _) => Text(
                  '${v.toInt()}',
                  style: const TextStyle(color: Colors.white24, fontSize: 8),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 16,
                getTitlesWidget: (v, meta) {
                  for (int i = 0; i < _labelFreqs.length; i++) {
                    if ((math.log(_labelFreqs[i]) / math.ln10 - v).abs() <
                        0.015) {
                      return Text(_labelStrs[i],
                          style: const TextStyle(
                              color: Colors.white24, fontSize: 7));
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            // 회색 점선: 0dB 기준
            LineChartBarData(
              spots: const [
                FlSpot(_logMin, 0),
                FlSpot(_logMax, 0),
              ],
              isCurved: false,
              color: Colors.white12,
              barWidth: 1,
              dotData: const FlDotData(show: false),
              dashArray: [4, 4],
            ),
            // 빨강: before (측정 원본)
            if (beforeSpots.isNotEmpty)
              LineChartBarData(
                spots: beforeSpots,
                isCurved: true,
                curveSmoothness: 0.15,
                color: const Color(0xFFFF5252),
                barWidth: 1.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: const Color(0x0DFF5252),
                ),
              ),
            // 초록: afterAi (AI 보정 후 예측)
            if (afterSpots.isNotEmpty)
              LineChartBarData(
                spots: afterSpots,
                isCurved: true,
                curveSmoothness: 0.15,
                color: const Color(0xFF69F0AE),
                barWidth: 1.5,
                dotData: const FlDotData(show: false),
              ),
          ],
        ),
      ),
    );
  }
}

/// 차트 하단 범례 행
class FrequencyResponseLegend extends StatelessWidget {
  final bool hasBefore;
  final bool hasAfter;

  const FrequencyResponseLegend({
    super.key,
    this.hasBefore = false,
    this.hasAfter = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _dot(Colors.white24, 'FLAT'),
      const SizedBox(width: 12),
      if (hasBefore) ...[
        _dot(const Color(0xFFFF5252), 'RAW'),
        const SizedBox(width: 12),
      ],
      if (hasAfter) _dot(const Color(0xFF69F0AE), 'CORRECTED'),
    ]);
  }

  Widget _dot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 2, color: color),
          const SizedBox(width: 4),
          Text(label,
              style:
                  TextStyle(color: color, fontSize: 9, letterSpacing: 0.5)),
        ],
      );
}
