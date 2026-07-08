import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai_tuning_service.dart';
import '../../core/profiles/system_profile.dart';
import '../../core/sound_score_calculator.dart';
import '../../core/spectrum_snapshot.dart';
import '../../shared/frequency_response_chart.dart';
import '../connect/connect_controller.dart';
import '../dsp/dsp_controller.dart';

enum _AiPhase { idle, running, done }

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  _AiPhase _phase = _AiPhase.idle;
  AiTuningResult? _result;
  String _selectedRef = 'Neutral';
  bool _applying = false;

  static const _refPresets = ['Warm', 'Neutral', 'Clear'];
  static const _timelineSteps = [
    'Factory', 'Measure', 'AI', 'User Edit', 'AI Learn', 'Final',
  ];

  static const _refDescriptions = {
    'Warm': '저역 강조, 부드러운 고역',
    'Neutral': '평탄한 응답, 측정 기반',
    'Clear': '고역 선명, 보컬 강조',
  };

  Future<void> _runAi() async {
    setState(() { _phase = _AiPhase.running; _result = null; });

    final snap = ref.read(spectrumSnapshotProvider);
    final dspState = ref.read(dspProvider);
    final profile = ref.read(systemProfileProvider);
    final score = ref.read(soundScoreProvider);

    final freqResponse = snap.before
        ?.map((b) => <String, double>{'freq': b.frequency, 'spl': b.magnitude})
        .toList();

    final refNote = _selectedRef != 'Neutral' ? ' Reference: $_selectedRef.' : '';
    final scoreNote = score != null ? ' Current Score: ${score.total}/100.' : '';

    final result = await AiTuningService.suggest(
      dspState: dspState,
      userRequest: 'AI Room Correction 자동 최적화.$refNote$scoreNote',
      frequencyResponse: freqResponse,
      systemProfile: profile,
    );

    if (!mounted) return;

    // afterAi 스펙트럼 계산 (before 곡선에 AI 밴드 합성)
    if (result.success && snap.before != null) {
      final corrections = result.bands
          .map((b) => (freq: b.frequency, gain: b.gainDb, q: b.q))
          .toList();
      final afterBins =
          SpectrumSnapshotController.applyCorrections(snap.before!, corrections);
      ref.read(spectrumSnapshotProvider.notifier).setAfterAi(afterBins);
    }

    setState(() { _phase = _AiPhase.done; _result = result; });
  }

  Future<void> _applyToDsp() async {
    if (_result == null || !_result!.success) return;
    setState(() => _applying = true);

    final ctrl = ref.read(dspProvider.notifier);
    final outIdx = ref.read(dspProvider).selectedOutput;
    for (int i = 0; i < _result!.bands.length; i++) {
      ctrl.updateOutputBand(outIdx, i, _result!.bands[i].toPeqBand());
    }

    setState(() => _applying = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI 보정 적용 완료 — DSP 탭에서 APPLY를 눌러야 실제 전송됩니다'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(connectProvider).connected;
    final snap = ref.watch(spectrumSnapshotProvider);
    final score = ref.watch(soundScoreProvider);
    final hasMeasurement = snap.before != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 6)),
            const SizedBox(height: 8),
            const Text('Room Correction · Sound Score · Reference',
                style: TextStyle(
                    color: Colors.white38, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 32),

            // ── Sound Score ────────────────────────────────────────────────
            const Text('SOUND SCORE',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 16),
            _SoundScoreCard(score: score, phase: _phase, result: _result),
            const SizedBox(height: 24),

            // ── Reference 프리셋 ───────────────────────────────────────────
            const Text('REFERENCE',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 12),
            Row(
              children: _refPresets.map((r) {
                final active = r == _selectedRef;
                return Expanded(
                  child: Padding(
                    padding:
                        EdgeInsets.only(right: r == _refPresets.last ? 0 : 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRef = r),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: active ? Colors.white : Colors.transparent,
                          border: Border.all(
                              color: active ? Colors.white : Colors.white24),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(r.toUpperCase(),
                                style: TextStyle(
                                    color:
                                        active ? Colors.black : Colors.white54,
                                    fontSize: 11,
                                    letterSpacing: 2,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.w300)),
                            Text(_refDescriptions[r] ?? '',
                                style: TextStyle(
                                    color: active
                                        ? Colors.black54
                                        : Colors.white24,
                                    fontSize: 8,
                                    letterSpacing: 0.3)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // ── AI Room Correction 버튼 ────────────────────────────────────
            GestureDetector(
              onTap: (connected && hasMeasurement && _phase != _AiPhase.running)
                  ? _runAi
                  : null,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: (connected && hasMeasurement &&
                          _phase != _AiPhase.running)
                      ? Colors.white
                      : Colors.transparent,
                  border: Border.all(
                      color: (connected && hasMeasurement)
                          ? Colors.white
                          : Colors.white24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: _phase == _AiPhase.running
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white54))
                      : Text(
                          _phase == _AiPhase.done ? 'AI 재실행' : 'AI ROOM CORRECTION',
                          style: TextStyle(
                              color: (connected && hasMeasurement &&
                                      _phase != _AiPhase.running)
                                  ? Colors.black
                                  : Colors.white24,
                              fontSize: 14,
                              letterSpacing: 3)),
                ),
              ),
            ),

            if (!hasMeasurement) ...[
              const SizedBox(height: 8),
              const Text('MEASURE 탭에서 먼저 측정을 완료하세요',
                  style: TextStyle(
                      color: Colors.white24, fontSize: 11, letterSpacing: 1)),
            ],

            const SizedBox(height: 24),

            // ── Before/After 그래프 ────────────────────────────────────────
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
                      height: 200,
                    ),
            ),

            // ── AI 결과 ────────────────────────────────────────────────────
            if (_result != null) ...[
              const SizedBox(height: 24),
              if (_result!.success) ...[
                // 적용 버튼
                GestureDetector(
                  onTap: _applying ? null : _applyToDsp,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _applying
                          ? Colors.transparent
                          : Colors.white.withValues(alpha: 0.08),
                      border: Border.all(
                          color: _applying ? Colors.white12 : Colors.white54),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: _applying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: Colors.white54))
                          : const Text('DSP에 적용',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  letterSpacing: 2)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // AI 분석 설명
                if (_result!.analysis.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_result!.analysis,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12, height: 1.6)),
                  ),
                const SizedBox(height: 12),
                // 밴드 리스트
                ..._result!.bands.asMap().entries.map((e) {
                  final i = e.key;
                  final b = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: b.enabled
                                ? Colors.white24
                                : Colors.white12),
                        borderRadius: BorderRadius.circular(6),
                        color: b.enabled
                            ? Colors.white.withValues(alpha: 0.02)
                            : Colors.transparent,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            SizedBox(
                              width: 20,
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      color: b.enabled
                                          ? Colors.white38
                                          : Colors.white12,
                                      fontSize: 11,
                                      fontFamily: 'monospace')),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${b.frequency.toStringAsFixed(0)} Hz',
                                        style: TextStyle(
                                            color: b.enabled
                                                ? Colors.white
                                                : Colors.white38,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500)),
                                    const Text('FREQ',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 10,
                                            letterSpacing: 1)),
                                  ]),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${b.gainDb >= 0 ? '+' : ''}${b.gainDb.toStringAsFixed(1)} dB',
                                        style: TextStyle(
                                            color: b.enabled
                                                ? Colors.white70
                                                : Colors.white38,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500)),
                                    const Text('GAIN',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 10,
                                            letterSpacing: 1)),
                                  ]),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Q ${b.q.toStringAsFixed(2)}',
                                        style: TextStyle(
                                            color: b.enabled
                                                ? Colors.white60
                                                : Colors.white24,
                                            fontSize: 14)),
                                    const Text('Q',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 10,
                                            letterSpacing: 1)),
                                  ]),
                            ),
                          ]),
                          if (b.reason.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('→ "${b.reason}"',
                                style: TextStyle(
                                    color: b.enabled
                                        ? Colors.white38
                                        : Colors.white12,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic)),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_result!.error ?? 'AI 오류가 발생했습니다.',
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12, height: 1.5)),
                ),
              ],
            ],

            const SizedBox(height: 32),

            // ── AI Timeline ────────────────────────────────────────────────
            const Text('AI TIMELINE',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 16),
            _AiTimeline(
              steps: _timelineSteps,
              currentStep: _phase == _AiPhase.done ? 2 : (hasMeasurement ? 1 : 0),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sound Score 카드 ─────────────────────────────────────────────────────────

class _SoundScoreCard extends StatelessWidget {
  final SoundScoreResult? score;
  final _AiPhase phase;
  final AiTuningResult? result;

  const _SoundScoreCard({this.score, required this.phase, this.result});

  @override
  Widget build(BuildContext context) {
    final hasScore = score != null;
    final displayScore = score?.total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            hasScore ? '$displayScore' : '—',
            style: TextStyle(
              color: hasScore ? Colors.white : Colors.white24,
              fontSize: 52,
              fontWeight: FontWeight.w100,
              letterSpacing: -2,
            ),
          ),
          const SizedBox(width: 4),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('/100',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ),
        ]),
        if (hasScore) ...[
          const SizedBox(height: 10),
          _ScoreBar(label: 'FLATNESS', value: score!.flatness, max: 40),
          const SizedBox(height: 6),
          _ScoreBar(label: 'BASS EXT', value: score!.bassExt, max: 20),
          const SizedBox(height: 6),
          _ScoreBar(label: 'TREBLE', value: score!.trebleRolloff, max: 20),
          const SizedBox(height: 6),
          _ScoreBar(label: 'CH MATCH', value: score!.channelMatch, max: 20,
              note: '(stereo 측정 필요)'),
          const SizedBox(height: 12),
          Text(score!.explanation,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 11, height: 1.5)),
        ] else
          const Text('MEASURE 탭에서 측정을 완료하면 Score가 표시됩니다',
              style: TextStyle(
                  color: Colors.white24, fontSize: 11, height: 1.4)),
      ]),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final String? note;

  const _ScoreBar(
      {required this.label,
      required this.value,
      required this.max,
      this.note});

  @override
  Widget build(BuildContext context) {
    final ratio = (value / max).clamp(0.0, 1.0);
    return Row(children: [
      SizedBox(
        width: 68,
        child: Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 9, letterSpacing: 1)),
      ),
      Expanded(
        child: Stack(children: [
          Container(height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2))),
          FractionallySizedBox(
            widthFactor: ratio,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                  color: ratio > 0.7
                      ? Colors.greenAccent
                      : ratio > 0.4
                          ? Colors.amber
                          : Colors.redAccent,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      Text('$value/$max',
          style: const TextStyle(
              color: Colors.white38, fontSize: 9, fontFamily: 'monospace')),
      if (note != null) ...[
        const SizedBox(width: 4),
        Text(note!,
            style: const TextStyle(color: Colors.white12, fontSize: 8)),
      ],
    ]);
  }
}

// ── AI Timeline ──────────────────────────────────────────────────────────────

class _AiTimeline extends StatelessWidget {
  final List<String> steps;
  final int currentStep;

  const _AiTimeline({required this.steps, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: steps.asMap().entries.map((e) {
        final i = e.key;
        final label = e.value;
        final done = i <= currentStep;
        final isLast = i == steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? Colors.white : Colors.transparent,
                        border: Border.all(
                            color: done ? Colors.white : Colors.white24,
                            width: 1),
                      ),
                      child: done
                          ? const Icon(Icons.check,
                              size: 12, color: Colors.black)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: done ? Colors.white60 : Colors.white24,
                            fontSize: 9,
                            letterSpacing: 0.5)),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.only(bottom: 22),
                    color: done && i < currentStep
                        ? Colors.white38
                        : Colors.white12,
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
