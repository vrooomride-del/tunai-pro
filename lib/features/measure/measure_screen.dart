import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/spectrum_snapshot.dart';
import '../../shared/frequency_response_chart.dart';
import '../connect/connect_controller.dart';

enum _MeasurePhase { idle, running, done }

class MeasureScreen extends ConsumerStatefulWidget {
  const MeasureScreen({super.key});

  @override
  ConsumerState<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends ConsumerState<MeasureScreen> {
  _MeasurePhase _phase = _MeasurePhase.idle;
  double _progress = 0;

  Future<void> _startMeasurement() async {
    setState(() {
      _phase = _MeasurePhase.running;
      _progress = 0;
    });
    // TODO: 실측 연동 (UMIK-1 / RTA 마이크) — 현재는 시뮬레이션
    for (var i = 0; i <= 100; i += 5) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => _progress = i / 100.0);
    }
    if (!mounted) return;
    // 측정 완료 → 모의 응답 스펙트럼 저장
    final mockBins = SpectrumSnapshotController.generateMockResponse();
    ref.read(spectrumSnapshotProvider.notifier).setBefore(mockBins);
    setState(() => _phase = _MeasurePhase.done);
  }

  void _reset() {
    ref.read(spectrumSnapshotProvider.notifier).reset();
    setState(() {
      _phase = _MeasurePhase.idle;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(connectProvider).connected;
    final snap = ref.watch(spectrumSnapshotProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MEASURE',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 6)),
            const SizedBox(height: 8),
            const Text('마이크 측정 → AI Room Correction',
                style: TextStyle(
                    color: Colors.white38, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 32),

            // ── 측정 버튼 ──────────────────────────────────────────────────
            if (_phase == _MeasurePhase.idle)
              GestureDetector(
                onTap: connected ? _startMeasurement : null,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: connected ? Colors.white : Colors.white24),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mic_none,
                            color: connected ? Colors.white : Colors.white24,
                            size: 18),
                        const SizedBox(width: 10),
                        Text('측정 시작',
                            style: TextStyle(
                                color: connected
                                    ? Colors.white
                                    : Colors.white24,
                                fontSize: 15,
                                letterSpacing: 3)),
                      ],
                    ),
                  ),
                ),
              ),

            if (_phase == _MeasurePhase.idle && !connected) ...[
              const SizedBox(height: 12),
              const Text('CONNECT 탭에서 먼저 연결하세요.',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 11, letterSpacing: 1)),
            ],

            if (_phase == _MeasurePhase.running) ...[
              Container(
                height: 52,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white54)),
                      SizedBox(width: 12),
                      Text('측정 중...',
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 15,
                              letterSpacing: 3)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white12,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toInt()}%',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11, letterSpacing: 1)),
            ],

            if (_phase == _MeasurePhase.done) ...[
              Container(
                height: 52,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white54),
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.white.withValues(alpha: 0.04),
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: Colors.white70, size: 18),
                      SizedBox(width: 10),
                      Text('측정 완료',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              letterSpacing: 3)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _reset,
                child: const Text('다시 측정',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white24)),
              ),
            ],

            const SizedBox(height: 32),

            // ── Frequency Response 차트 ────────────────────────────────────
            const Text('FREQUENCY RESPONSE',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 4),
            FrequencyResponseLegend(
              hasBefore: snap.before != null,
              hasAfter: snap.afterAi != null,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(4, 12, 8, 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: snap.before == null
                  ? const SizedBox(
                      height: 160,
                      child: Center(
                        child: Text('측정 후 그래프가 표시됩니다',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 12)),
                      ),
                    )
                  : FrequencyResponseChart(
                      before: snap.before,
                      afterAi: snap.afterAi,
                      height: 180,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
