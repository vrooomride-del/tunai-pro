import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dsp_state.dart';
import '../dsp_controller.dart';
import '../../../core/ai_tuning_service.dart';

class AiTuningPanel extends ConsumerStatefulWidget {
  final List<Map<String, double>>? frequencyResponse;
  const AiTuningPanel({super.key, this.frequencyResponse});

  @override
  ConsumerState<AiTuningPanel> createState() => _AiTuningPanelState();
}

class _AiTuningPanelState extends ConsumerState<AiTuningPanel> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  AiTuningResult? _result;
  bool _expanded = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _ask() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() { _loading = true; _result = null; });

    final state = ref.read(dspProvider);
    final systemProfile = ref.read(systemProfileProvider);
    final result = await AiTuningService.suggest(
      dspState: state,
      userRequest: _ctrl.text.trim(),
      frequencyResponse: widget.frequencyResponse,
      systemProfile: systemProfile,
    );

    setState(() { _loading = false; _result = result; });
  }

  void _applyAll() {
    if (_result == null || !_result!.success) return;
    final dspCtrl = ref.read(dspProvider.notifier);
    final outIdx = ref.read(dspProvider).selectedOutput;
    for (final suggestion in _result!.bands) {
      if (suggestion.index >= 0 && suggestion.index < 20) {
        dspCtrl.updateOutputBand(outIdx, suggestion.index, suggestion.toPeqBand());
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 추천 파라미터 적용 완료')));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
        color: Color(0xFF0D0D0D),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더 토글
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24, width: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text('AI',
                        style: TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 2)),
                  ),
                  const SizedBox(width: 10),
                  const Text('TUNING ASSISTANT',
                      style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3)),
                  const Spacer(),
                  Icon(_expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                      color: Colors.white24, size: 16),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 입력창
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: '예: 저음이 너무 강해요 / 200Hz 피크 잡아줘 / 트위터가 너무 밝아',
                            hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                            enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white12, width: 0.5)),
                            focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white38, width: 0.5)),
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onSubmitted: (_) => _ask(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _loading ? null : _ask,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _loading ? Colors.white12 : Colors.white38,
                                width: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: _loading
                              ? const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(
                                      color: Colors.white38, strokeWidth: 1))
                              : const Text('ASK',
                                  style: TextStyle(color: Colors.white54,
                                      fontSize: 10, letterSpacing: 2)),
                        ),
                      ),
                    ],
                  ),

                  // 빠른 질문 버튼
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      '저음이 너무 강해요',
                      '고음이 너무 밝아요',
                      '중역대가 비어있어요',
                      '전체적으로 플랫하게',
                      '보컬을 더 선명하게',
                    ].map((q) => GestureDetector(
                      onTap: () {
                        _ctrl.text = q;
                        _ask();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white12, width: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(q,
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 10)),
                      ),
                    )).toList(),
                  ),

                  // 결과
                  if (_result != null) ...[
                    const SizedBox(height: 16),
                    if (!_result!.success)
                      Text(_result!.error ?? '오류',
                          style: const TextStyle(color: Colors.redAccent, fontSize: 11))
                    else ...[
                      // 분석
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white12, width: 0.5),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white.withValues(alpha: 0.02),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ANALYSIS',
                                style: TextStyle(color: Colors.white24,
                                    fontSize: 8, letterSpacing: 2)),
                            const SizedBox(height: 6),
                            Text(_result!.analysis,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11, height: 1.6)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // 추천 밴드 목록
                      ..._result!.bands.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white12, width: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24, width: 0.5),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Center(
                                  child: Text('${s.index + 1}',
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 9)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${s.frequency.toStringAsFixed(0)}Hz  '
                                      '${s.gainDb >= 0 ? '+' : ''}${s.gainDb.toStringAsFixed(1)}dB  '
                                      'Q${s.q.toStringAsFixed(2)}  '
                                      '${FilterType.values[s.type.clamp(0, 6)].label}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11,
                                          fontFamily: 'monospace'),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(s.reason,
                                        style: const TextStyle(
                                            color: Colors.white38, fontSize: 10)),
                                  ],
                                ),
                              ),
                              // 개별 적용
                              GestureDetector(
                                onTap: () {
                                  final dspCtrl = ref.read(dspProvider.notifier);
                                  final outIdx = ref.read(dspProvider).selectedOutput;
                                  dspCtrl.updateOutputBand(outIdx, s.index, s.toPeqBand());
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(
                                          'Band${s.index + 1} 적용됐습니다.')));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white24, width: 0.5),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text('APPLY',
                                      style: TextStyle(color: Colors.white38,
                                          fontSize: 9, letterSpacing: 1)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),

                      // 전체 적용
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(_result!.summary,
                                style: const TextStyle(
                                    color: Colors.white24, fontSize: 10, height: 1.5)),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _applyAll,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('APPLY ALL',
                                  style: TextStyle(color: Colors.white,
                                      fontSize: 10, letterSpacing: 2)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
