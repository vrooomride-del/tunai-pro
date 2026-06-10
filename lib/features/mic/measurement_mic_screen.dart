import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'mic_measurement_controller.dart';

class MicModel {
  final String id;
  final String name;
  final String manufacturer;
  final String capsule;
  final String connector;
  final bool needsScf;

  const MicModel({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.capsule,
    required this.connector,
    this.needsScf = true,
  });
}

const kMicModels = [
  MicModel(id: 'umik1', name: 'UMIK-1', manufacturer: 'miniDSP', capsule: 'Omni', connector: 'USB', needsScf: true),
  MicModel(id: 'umik2', name: 'UMIK-2', manufacturer: 'miniDSP', capsule: 'Omni', connector: 'USB', needsScf: true),
  MicModel(id: 'ecm8000', name: 'ECM8000', manufacturer: 'Behringer', capsule: 'Omni', connector: 'XLR', needsScf: true),
  MicModel(id: 'em272', name: 'EM272', manufacturer: 'Primo', capsule: 'Omni', connector: 'DIY', needsScf: false),
  MicModel(id: 'custom', name: 'CUSTOM', manufacturer: 'Direct Sourced', capsule: '-', connector: 'USB', needsScf: false),
];

class MicState {
  final String selectedMicId;
  final String? scfPath;
  final bool scfLoaded;
  final String status;
  final List<double>? scfCorrection;

  const MicState({
    this.selectedMicId = 'umik1',
    this.scfPath,
    this.scfLoaded = false,
    this.status = 'READY',
    this.scfCorrection,
  });

  MicState copyWith({
    String? selectedMicId,
    String? scfPath,
    bool? scfLoaded,
    String? status,
    List<double>? scfCorrection,
  }) => MicState(
    selectedMicId: selectedMicId ?? this.selectedMicId,
    scfPath: scfPath ?? this.scfPath,
    scfLoaded: scfLoaded ?? this.scfLoaded,
    status: status ?? this.status,
    scfCorrection: scfCorrection ?? this.scfCorrection,
  );
}

final micProvider = StateNotifierProvider<MicController, MicState>(
  (ref) => MicController(),
);

class MicController extends StateNotifier<MicState> {
  MicController() : super(const MicState());

  void selectMic(String id) {
    state = state.copyWith(selectedMicId: id, scfPath: null, scfLoaded: false, scfCorrection: null);
  }

  Future<void> loadScf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'cal'],
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    try {
      final lines = await File(path).readAsLines();
      // miniDSP SCF 파싱: 주파수 보정값 추출
      final corrections = <double>[];
      for (final line in lines) {
        if (line.startsWith('*') || line.trim().isEmpty) continue;
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final correction = double.tryParse(parts[1]);
          if (correction != null) corrections.add(correction);
        }
      }
      state = state.copyWith(
        scfPath: path,
        scfLoaded: corrections.isNotEmpty,
        scfCorrection: corrections.isNotEmpty ? corrections : null,
        status: corrections.isNotEmpty ? 'SCF LOADED (${corrections.length}pts)' : 'INVALID FILE',
      );
    } catch (_) {
      state = state.copyWith(status: 'FILE READ ERROR');
    }
  }

  void clearScf() {
    state = state.copyWith(scfPath: null, scfLoaded: false, scfCorrection: null, status: 'READY');
  }
}

class MeasurementMicScreen extends ConsumerWidget {
  const MeasurementMicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final micState = ref.watch(micProvider);
    final micCtrl = ref.read(micProvider.notifier);
    final measState = ref.watch(micMeasurementProvider);
    final measCtrl = ref.read(micMeasurementProvider.notifier);
    final mic = kMicModels.firstWhere((m) => m.id == micState.selectedMicId);
    final isMeasuring = measState.status == MeasurementStatus.playing ||
        measState.status == MeasurementStatus.recording ||
        measState.status == MeasurementStatus.analyzing;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                const Text('MEASUREMENT MIC',
                    style: TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w200, letterSpacing: 4)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: measState.status == MeasurementStatus.done
                          ? Colors.white
                          : micState.scfLoaded ? Colors.white54 : Colors.white24,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    measState.status == MeasurementStatus.idle ? micState.status
                        : measState.status == MeasurementStatus.done ? 'MEASURED'
                        : measState.status == MeasurementStatus.error ? 'ERROR'
                        : 'MEASURING...',
                    style: TextStyle(
                      color: measState.status == MeasurementStatus.done
                          ? Colors.white : Colors.white38,
                      fontSize: 9, letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // 마이크 기종 선택
            const Text('MODEL',
                style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3)),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: kMicModels.length,
                itemBuilder: (_, i) {
                  final m = kMicModels[i];
                  final selected = m.id == micState.selectedMicId;
                  return GestureDetector(
                    onTap: isMeasuring ? null : () => micCtrl.selectMic(m.id),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: selected ? Colors.white : Colors.white24),
                        borderRadius: BorderRadius.circular(4),
                        color: selected ? Colors.white.withOpacity(0.05) : Colors.transparent,
                      ),
                      child: Center(
                        child: Text(m.name,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white38,
                              fontSize: 10, letterSpacing: 1,
                            )),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // 기종 스펙
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic_none, color: Colors.white38, size: 24),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mic.name,
                          style: const TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2)),
                      const SizedBox(height: 3),
                      Text('${mic.manufacturer}  ·  ${mic.capsule}  ·  ${mic.connector}',
                          style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // SCF 교정파일
            const Text('CALIBRATION FILE (SCF)',
                style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        micState.scfPath != null
                            ? micState.scfPath!.split('/').last
                            : mic.needsScf ? 'REQUIRED' : 'OPTIONAL',
                        style: TextStyle(
                          color: micState.scfLoaded ? Colors.white : Colors.white24,
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: micCtrl.loadScf,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Text('LOAD',
                          style: TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 2)),
                    ),
                  ),
                ),
                if (micState.scfLoaded) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: micCtrl.clearScf,
                    child: const Icon(Icons.close, color: Colors.white38, size: 16),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            // Bode plot (측정 결과)
            if (measState.frequencyResponse.isNotEmpty) ...[
              const Text('FREQUENCY RESPONSE',
                  style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3)),
              const SizedBox(height: 8),
              _BodePlot(response: measState.frequencyResponse),
              const SizedBox(height: 24),
            ],

            // 상태 메시지
            if (isMeasuring)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1),
                    ),
                    const SizedBox(width: 12),
                    Text(measState.message,
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),

            if (measState.status == MeasurementStatus.error)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(measState.error ?? '',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),

            const SizedBox(height: 24),

            // 측정 버튼
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: isMeasuring ? null : () => measCtrl.startMeasurement(
                      scfCorrection: micState.scfCorrection,
                    ),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isMeasuring ? Colors.white12
                              : (micState.scfLoaded || !mic.needsScf) ? Colors.white : Colors.white38,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        color: isMeasuring ? Colors.transparent : Colors.transparent,
                      ),
                      child: Center(
                        child: Text(
                          isMeasuring ? measState.message : 'START MEASUREMENT',
                          style: TextStyle(
                            color: isMeasuring ? Colors.white24
                                : (micState.scfLoaded || !mic.needsScf) ? Colors.white : Colors.white38,
                            fontSize: 11, letterSpacing: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (measState.status == MeasurementStatus.done) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: measCtrl.reset,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Center(
                        child: Text('RESET',
                            style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BodePlot extends StatelessWidget {
  final List<Map<String, double>> response;
  const _BodePlot({required this.response});

  @override
  Widget build(BuildContext context) {
    if (response.isEmpty) return const SizedBox(height: 200);

    final spots = response.map((r) {
      final logFreq = log(r['frequency']!) / log(10);
      return FlSpot(logFreq, r['db']!.clamp(-40.0, 10.0));
    }).toList();

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LineChart(
        LineChartData(
          backgroundColor: Colors.transparent,
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => const FlLine(color: Colors.white10, strokeWidth: 0.5),
            getDrawingVerticalLine: (_) => const FlLine(color: Colors.white10, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, interval: 1,
                getTitlesWidget: (v, _) {
                  final freq = pow(10, v).toInt();
                  if ([20, 100, 1000, 10000].any((f) => (log(f)/log(10) - v).abs() < 0.05)) {
                    return Text(freq >= 1000 ? '${freq ~/ 1000}k' : '$freq',
                        style: const TextStyle(color: Colors.white24, fontSize: 8));
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, interval: 10,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: const TextStyle(color: Colors.white24, fontSize: 8)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: log(20) / log(10),
          maxX: log(20000) / log(10),
          minY: -40, maxY: 10,
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
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
