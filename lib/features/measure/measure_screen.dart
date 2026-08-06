import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/spectrum_snapshot.dart';
import '../../shared/frequency_response_chart.dart';
import '../connect/connect_controller.dart';
import '../mic/mic_measurement_controller.dart';
import '../mic/measurement_mic_screen.dart' show micProvider, MicState;

class MeasureScreen extends ConsumerWidget {
  const MeasureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(connectProvider).connected;
    final mic = ref.watch(micMeasurementProvider);
    final micCal = ref.watch(micProvider);
    final snap = ref.watch(spectrumSnapshotProvider);

    // Sync real measurement result into SpectrumSnapshot on completion.
    ref.listen(micMeasurementProvider, (prev, next) {
      if (next.status == MeasurementStatus.done &&
          next.frequencyResponse.isNotEmpty) {
        final bins = next.frequencyResponse
            .map((p) => FrequencyBin(
                  frequency: p['frequency']!,
                  magnitude: p['db']!,
                ))
            .toList();
        ref.read(spectrumSnapshotProvider.notifier).setBefore(bins);
      }
    });

    final isRunning = mic.status == MeasurementStatus.playing ||
        mic.status == MeasurementStatus.recording ||
        mic.status == MeasurementStatus.analyzing;
    final isDone = mic.status == MeasurementStatus.done;
    final isError = mic.status == MeasurementStatus.error;

    final progress = switch (mic.status) {
      MeasurementStatus.playing => 0.2,
      MeasurementStatus.recording => 0.5,
      MeasurementStatus.analyzing => 0.85,
      MeasurementStatus.done => 1.0,
      _ => null,
    };

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

            // ── SCF 캘리브레이션 ───────────────────────────────────────────
            _ScfRow(micCal: micCal),
            const SizedBox(height: 20),

            // ── 측정 버튼 ──────────────────────────────────────────────────
            if (!isRunning && !isDone) ...[
              GestureDetector(
                onTap: connected && !isRunning
                    ? () => ref
                        .read(micMeasurementProvider.notifier)
                        .startMeasurement(
                          bleWarmup: true,
                          scfCorrection: micCal.scfCorrection,
                        )
                    : null,
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
              if (!connected) ...[
                const SizedBox(height: 12),
                const Text('CONNECT 탭에서 먼저 연결하세요.',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1)),
              ],
              if (isError) ...[
                const SizedBox(height: 12),
                Text(
                  mic.error == 'MIC_PERMISSION_DENIED'
                      ? '마이크 권한이 없습니다. 시스템 설정에서 권한을 허용하세요.'
                      : '오류: ${mic.error}',
                  style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      letterSpacing: 0.5),
                ),
              ],
            ],

            // ── 진행 중 ────────────────────────────────────────────────────
            if (isRunning) ...[
              Container(
                height: 52,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white54)),
                      const SizedBox(width: 12),
                      Text(mic.message,
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                              letterSpacing: 2)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 3,
                ),
              ),
            ],

            // ── 완료 ───────────────────────────────────────────────────────
            if (isDone) ...[
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
              const SizedBox(height: 16),

              // ── 다음 단계 안내 ──────────────────────────────────────────
              // 이 화면은 측정 결과(measurement artifact)만 생성한다.
              // 보정 계산·안전 검증·승인·배포는 Guided AI 파이프라인의 책임이며,
              // 측정 UI가 DSP에 직접 쓰지 않는다.
              const _HandoffNote(),

              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  ref.read(spectrumSnapshotProvider.notifier).reset();
                  ref.read(micMeasurementProvider.notifier).reset();
                },
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

// ── 다음 단계 안내 ────────────────────────────────────────────────────────────

/// 측정 완료 후 안내 카드.
///
/// 이전 리비전에는 여기에 _DeploySection이 있었고, 버튼 하나가 곧바로
/// AutoPeqPipeline.runFromMeasured()를 호출해 transport에 PEQ를 직접 기록했다.
/// 그 경로는 CandidateSafetyPolicy, 승인 게이트, HardwareWritePlan,
/// 롤백 스냅샷을 모두 건너뛰었으므로 제거했다.
///
/// 측정 화면의 책임은 측정 결과 생성까지다. 보정 계산·안전 검증·승인·배포는
/// Guided AI 파이프라인(ProGuidedAiController)이 담당한다.
class _HandoffNote extends StatelessWidget {
  const _HandoffNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(children: [
        Icon(Icons.info_outline, color: Colors.white38, size: 14),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '측정이 저장되었습니다. 보정은 Guided AI 탭에서 '
            '안전 검증과 승인을 거쳐 진행됩니다.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

// ── SCF 캘리브레이션 로우 ─────────────────────────────────────────────────────

class _ScfRow extends ConsumerWidget {
  final MicState micCal;
  const _ScfRow({required this.micCal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(micProvider.notifier);
    return Row(children: [
      const Text('MIC CAL',
          style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          micCal.scfLoaded
              ? (micCal.scfPath?.split('/').last ?? 'SCF')
              : '없음 (폰 마이크 특성 미보정)',
          style: TextStyle(
            color: micCal.scfLoaded ? Colors.white70 : Colors.white24,
            fontSize: 11,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: micCal.scfLoaded ? ctrl.clearScf : ctrl.loadScf,
        child: Text(
          micCal.scfLoaded ? '제거' : 'SCF 로드',
          style: TextStyle(
            color: micCal.scfLoaded ? Colors.white38 : Colors.white60,
            fontSize: 11,
            decoration: TextDecoration.underline,
            decorationColor:
                micCal.scfLoaded ? Colors.white24 : Colors.white38,
          ),
        ),
      ),
    ]);
  }
}
