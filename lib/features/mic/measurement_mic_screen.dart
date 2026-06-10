import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

// 마이크 모델 정의 — 기종 추가/변경 여기서만
class MicModel {
  final String id;
  final String name;
  final String manufacturer;
  final String capsule;
  final String connector;
  final bool needsScf; // SCF 교정파일 필요 여부

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
  MicModel(
    id: 'umik1',
    name: 'UMIK-1',
    manufacturer: 'miniDSP',
    capsule: 'Omni',
    connector: 'USB',
    needsScf: true,
  ),
  MicModel(
    id: 'umik2',
    name: 'UMIK-2',
    manufacturer: 'miniDSP',
    capsule: 'Omni',
    connector: 'USB',
    needsScf: true,
  ),
  MicModel(
    id: 'ecm8000',
    name: 'ECM8000',
    manufacturer: 'Behringer',
    capsule: 'Omni',
    connector: 'XLR',
    needsScf: true,
  ),
  MicModel(
    id: 'em272',
    name: 'EM272',
    manufacturer: 'Primo',
    capsule: 'Omni',
    connector: 'DIY',
    needsScf: false,
  ),
  MicModel(
    id: 'custom',
    name: 'CUSTOM',
    manufacturer: 'Direct Sourced',
    capsule: '-',
    connector: 'USB',
    needsScf: false,
  ),
];

// State
class MicState {
  final String selectedMicId;
  final String? scfPath;
  final bool scfLoaded;
  final String status;

  const MicState({
    this.selectedMicId = 'umik1',
    this.scfPath,
    this.scfLoaded = false,
    this.status = 'READY',
  });

  MicState copyWith({
    String? selectedMicId,
    String? scfPath,
    bool? scfLoaded,
    String? status,
  }) => MicState(
    selectedMicId: selectedMicId ?? this.selectedMicId,
    scfPath: scfPath ?? this.scfPath,
    scfLoaded: scfLoaded ?? this.scfLoaded,
    status: status ?? this.status,
  );
}

final micProvider = StateNotifierProvider<MicController, MicState>(
  (ref) => MicController(),
);

class MicController extends StateNotifier<MicState> {
  MicController() : super(const MicState());

  void selectMic(String id) {
    // 기종 바꾸면 SCF 초기화
    state = state.copyWith(selectedMicId: id, scfPath: null, scfLoaded: false);
  }

  Future<void> loadScf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'cal'],
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    // SCF 파일 유효성 간단 확인 (miniDSP 포맷: 첫줄 "Sens Factor")
    try {
      final lines = await File(path).readAsLines();
      final valid = lines.isNotEmpty &&
          (lines.first.contains('Sens') || lines.first.startsWith('*') || lines.length > 5);
      state = state.copyWith(
        scfPath: path,
        scfLoaded: valid,
        status: valid ? 'SCF LOADED' : 'INVALID FILE',
      );
    } catch (_) {
      state = state.copyWith(status: 'FILE READ ERROR');
    }
  }

  void clearScf() {
    state = state.copyWith(scfPath: null, scfLoaded: false, status: 'READY');
  }
}

// Screen
class MeasurementMicScreen extends ConsumerWidget {
  const MeasurementMicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(micProvider);
    final ctrl = ref.read(micProvider.notifier);
    final mic = kMicModels.firstWhere((m) => m.id == state.selectedMicId);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SingleChildScrollView(
        child: Padding(
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
    
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: state.scfLoaded ? Colors.white : Colors.white24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    state.status,
                    style: TextStyle(
                      color: state.scfLoaded ? Colors.white : Colors.white38,
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
                  final selected = m.id == state.selectedMicId;
                  return GestureDetector(
                    onTap: () => ctrl.selectMic(m.id),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected ? Colors.white : Colors.white24,
                        ),
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
            const SizedBox(height: 24),

            // 선택된 기종 스펙
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic_none, color: Colors.white38, size: 28),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mic.name,
                          style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2)),
                      const SizedBox(height: 4),
                      Text('${mic.manufacturer}  ·  ${mic.capsule}  ·  ${mic.connector}',
                          style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // SCF 교정파일 (기종에 따라 표시)
            const Text('CALIBRATION FILE (SCF)',
                style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        state.scfPath != null
                            ? state.scfPath!.split('/').last
                            : mic.needsScf ? 'REQUIRED — serial no. 기반 파일' : 'OPTIONAL',
                        style: TextStyle(
                          color: state.scfLoaded ? Colors.white : Colors.white24,
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: ctrl.loadScf,
                  child: Container(
                    height: 44,
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
                if (state.scfLoaded) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: ctrl.clearScf,
                    child: const Icon(Icons.close, color: Colors.white38, size: 16),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),

            // 안내
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SETUP GUIDE',
                      style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
                  const SizedBox(height: 10),
                  _guideRow('1', 'Mac USB에 측정 마이크 연결'),
                  _guideRow('2', 'SCF 교정파일 로드 (miniDSP 계정에서 다운로드)'),
                  _guideRow('3', 'CONNECT 탭에서 DSP 연결'),
                  _guideRow('4', 'PEQ 탭에서 측정 결과 기반 필터 조정'),
                ],
              ),
            ),

            // 측정 시작 버튼 (추후 REW 연동)
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('측정 기능 — 다음 업데이트에서 구현됩니다.')),
                );
              },
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: state.scfLoaded || !mic.needsScf ? Colors.white : Colors.white24,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    'START MEASUREMENT',
                    style: TextStyle(
                      color: state.scfLoaded || !mic.needsScf ? Colors.white : Colors.white24,
                      fontSize: 12, letterSpacing: 3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _guideRow(String num, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$num.  ', style: const TextStyle(color: Colors.white24, fontSize: 10)),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 10))),
      ],
    ),
  );
}
