import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'mic_measurement_controller.dart';
import 'speaker_profile_selector.dart';
import '../../core/speaker_profile.dart';
import '../../core/profiles/system_profile.dart';
import '../../features/dsp/dsp_controller.dart';
import '../../features/dsp/dsp_state.dart';
import '../../core/ai_tuning_service.dart';

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

class MeasurementMicScreen extends ConsumerStatefulWidget {
  const MeasurementMicScreen({super.key});
  @override
  ConsumerState<MeasurementMicScreen> createState() => _MeasurementMicScreenState();
}

class _MeasurementMicScreenState extends ConsumerState<MeasurementMicScreen> {
  SpeakerProfileState _speakerProfile = const SpeakerProfileState();
  bool _profileSelected = false;
  bool _channelMode = false;
  AiTuningResult? _aiResult;
  bool _aiLoading = false;
  bool _aiApplying = false;

  Future<void> _autoAnalyze(MicMeasurementState measState) async {
    if (_aiLoading) return;
    setState(() { _aiLoading = true; _aiResult = null; });
    final dspState = ref.read(dspProvider);
    final systemProfile = ref.read(systemProfileProvider);
    final result = await AiTuningService.suggest(
      dspState: dspState,
      userRequest: '측정된 주파수 응답을 분석하고 자연스럽고 균형잡힌 소리로 PEQ를 추천해줘',
      frequencyResponse: measState.frequencyResponse.isEmpty ? null : measState.frequencyResponse,
      speakerProfile: _speakerProfile.activeProfile,
      systemProfile: systemProfile,
    );
    if (mounted) setState(() { _aiLoading = false; _aiResult = result; });
  }

  Future<void> _applyAiToDsp() async {
    if (_aiResult == null || !_aiResult!.success) return;
    setState(() => _aiApplying = true);
    final dspCtrl = ref.read(dspProvider.notifier);
    final outIdx = ref.read(dspProvider).selectedOutput;
    for (final b in _aiResult!.bands) {
      if (!b.enabled) continue;
      dspCtrl.updateOutputBand(outIdx, b.index, b.toPeqBand());
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() => _aiApplying = false);
  }

  @override
  Widget build(BuildContext context) {
    final micState = ref.watch(micProvider);
    final micCtrl = ref.read(micProvider.notifier);
    final measState = ref.watch(micMeasurementProvider);
    final measCtrl = ref.read(micMeasurementProvider.notifier);
    final mic = kMicModels.firstWhere((m) => m.id == micState.selectedMicId);
    final isMeasuring = measState.status == MeasurementStatus.playing ||
        measState.status == MeasurementStatus.recording ||
        measState.status == MeasurementStatus.analyzing;

    ref.listen<MicMeasurementState>(micMeasurementProvider, (prev, next) {
      if (prev?.status != MeasurementStatus.done &&
          next.status == MeasurementStatus.done &&
          next.frequencyResponse.isNotEmpty) {
        _autoAnalyze(next);
      }
    });

    if (!_profileSelected) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SpeakerProfileSelector(
          onSelected: (profile) => setState(() {
            _speakerProfile = profile;
            _profileSelected = true;
          }),
        ),
      );
    }
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
                    style: TextStyle(color: Colors.white, fontSize: 16,
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
                          ? Colors.white : Colors.white60,
                      fontSize: 11, letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // 마이크 기종 선택
            const Text('MODEL',
                style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 3)),
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
                        color: selected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
                      ),
                      child: Center(
                        child: Text(m.name,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white60,
                              fontSize: 12, letterSpacing: 1,
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
                          style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 2)),
                      const SizedBox(height: 3),
                      Text('${mic.manufacturer}  ·  ${mic.capsule}  ·  ${mic.connector}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // SCF 교정파일
            const Text('CALIBRATION FILE (SCF)',
                style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 3)),
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
                          color: micState.scfLoaded ? Colors.white : Colors.white54,
                          fontSize: 12,
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
                          style: TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2)),
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
                  style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 3)),
              const SizedBox(height: 8),
              _BodePlot(
                response: measState.frequencyResponse,
                height: MediaQuery.of(context).size.height * 0.42,
              ),
              const SizedBox(height: 24),
            ],

            // AI 분석 결과
            if (_aiLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(children: [
                  SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 1)),
                  SizedBox(width: 12),
                  Text('AI가 주파수 응답을 분석 중입니다...',
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                ]),
              ),
            if (_aiResult != null) ...[
              // 트위터 경고 — 항상 표시
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.amber.withValues(alpha: 0.04),
                ),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('⚠️ ', style: TextStyle(fontSize: 12)),
                  Expanded(child: Text(
                    'PEQ 값 조정 시 트위터 채널 게인을 크게 올리지 마세요. '
                    '볼륨이 높은 상태에서 트위터가 손상될 수 있습니다.',
                    style: TextStyle(color: Colors.amber, fontSize: 12, height: 1.5),
                  )),
                ]),
              ),
              const SizedBox(height: 12),
              if (_aiResult!.success) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('AI 분석',
                        style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 3)),
                    const SizedBox(height: 8),
                    Text(_aiResult!.analysis,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.7)),
                    if (_aiResult!.summary.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_aiResult!.summary,
                          style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.5)),
                    ],
                  ]),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _aiApplying ? null : _applyAiToDsp,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(color: _aiApplying ? Colors.white24 : Colors.white),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(child: Text(
                      _aiApplying ? '적용 중...' : 'DSP에 적용',
                      style: TextStyle(
                        color: _aiApplying ? Colors.white38 : Colors.white,
                        fontSize: 13, letterSpacing: 3,
                      ),
                    )),
                  ),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('AI 오류: ${_aiResult!.error}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              const SizedBox(height: 16),
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
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),

                    if (measState.status == MeasurementStatus.error)
              _buildErrorWidget(measState.error),

            const SizedBox(height: 24),

            // 채널별 측정 결과 (크로스오버 추천)
            if (measState.channelResponses.isNotEmpty && measState.recommendedCrossovers.isNotEmpty)
              _buildChannelResults(measState),

            const SizedBox(height: 16),

            // 측정 모드 토글
            if (!isMeasuring) ...[
              Row(
                children: [
                  _ModeToggle(
                    label: 'FULL RANGE',
                    selected: !_channelMode,
                    onTap: () => setState(() => _channelMode = false),
                  ),
                  const SizedBox(width: 8),
                  _ModeToggle(
                    label: 'PER CHANNEL',
                    selected: _channelMode,
                    onTap: () => setState(() => _channelMode = true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // 측정 버튼
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: isMeasuring ? null : () => _startMeasurement(measCtrl, micState),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isMeasuring ? Colors.white12
                              : (micState.scfLoaded || !mic.needsScf) ? Colors.white : Colors.white38,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          isMeasuring ? measState.message
                              : _channelMode ? 'START CHANNEL MEASUREMENT'
                              : 'START MEASUREMENT',
                          style: TextStyle(
                            color: isMeasuring ? Colors.white24
                                : (micState.scfLoaded || !mic.needsScf) ? Colors.white : Colors.white60,
                            fontSize: 13, letterSpacing: 3,
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
                            style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 2)),
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

  void _startMeasurement(MicMeasurementController measCtrl, MicState micState) {
    if (_channelMode) {
      final profile = ref.read(systemProfileProvider);
      final dspCtrl = ref.read(dspProvider.notifier);
      measCtrl.startChannelMeasurement(
        channelNames: profile.channels.map((c) => c.name).toList(),
        channelTypes: profile.channels.map((c) => c.type).toList(),
        muteAllExcept: (idx) async {
          for (int i = 0; i < profile.channels.length; i++) {
            await dspCtrl.setMute(i, i != idx);
          }
        },
        unmuteAll: () async {
          for (int i = 0; i < profile.channels.length; i++) {
            await dspCtrl.setMute(i, false);
          }
        },
        applyLp: (i, f) => dspCtrl.updateLpFilter(i, f),
        applyHp: (i, f) => dspCtrl.updateHpFilter(i, f),
        xoverType: CrossoverType.lr24,
        scfCorrection: micState.scfCorrection,
      );
    } else {
      measCtrl.startMeasurement(
        scfCorrection: micState.scfCorrection,
        speakerProfile: _speakerProfile.activeProfile,
      );
    }
  }

  Widget _buildErrorWidget(String? error) {
    final isPermDenied = error == 'MIC_PERMISSION_DENIED';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: isPermDenied
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('마이크 접근 권한이 필요합니다.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: MicMeasurementController.openMicSettings,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white38),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('시스템 환경설정 열기 →',
                        style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1)),
                  ),
                ),
              ],
            )
          : Text(error ?? '',
              style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
    );
  }

  Widget _buildChannelResults(MicMeasurementState measState) {
    final profile = ref.read(systemProfileProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RECOMMENDED CROSSOVERS',
              style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 3)),
          const SizedBox(height: 10),
          ...List.generate(measState.recommendedCrossovers.length, (i) {
            final freq = measState.recommendedCrossovers[i];
            final lowerName = i < profile.channels.length ? profile.channels[i].name : 'CH${i+1}';
            final upperName = (i + 1) < profile.channels.length ? profile.channels[i + 1].name : 'CH${i+2}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text('$lowerName / $upperName',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const Spacer(),
                  Text(
                    freq != null ? '${freq.round()} Hz' : '—',
                    style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          const Text('자동으로 DSP에 적용되었습니다',
              style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
        ],
      ),
    );
  }
}  // end _MeasurementMicScreenState

class _ModeToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeToggle({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? Colors.white : Colors.white24),
          borderRadius: BorderRadius.circular(4),
          color: selected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white60,
              fontSize: 11, letterSpacing: 2,
            )),
      ),
    );
  }
}

class _BodePlot extends StatelessWidget {
  final List<Map<String, double>> response;
  final double height;
  const _BodePlot({required this.response, this.height = 200});

  @override
  Widget build(BuildContext context) {
    if (response.isEmpty) return SizedBox(height: height);

    final spots = response.map((r) {
      final logFreq = log(r['frequency']!) / log(10);
      return FlSpot(logFreq, r['db']!.clamp(-40.0, 10.0));
    }).toList();

    return Container(
      height: height,
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
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
