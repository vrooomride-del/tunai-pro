import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../connect/connect_controller.dart';

enum _AiPhase { idle, running, done }

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  _AiPhase _phase = _AiPhase.idle;
  int _score = 0;
  String _selectedRef = 'Neutral';

  static const _refPresets = ['Warm', 'Neutral', 'Clear'];
  static const _timelineSteps = [
    'Factory',
    'Measure',
    'AI',
    'User Edit',
    'AI Learn',
    'Final',
  ];

  Future<void> _runAi() async {
    setState(() => _phase = _AiPhase.running);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _phase = _AiPhase.done;
      _score = 78;
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(connectProvider).connected;

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
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: _phase == _AiPhase.done
                    ? Column(
                        children: [
                          Text('$_score',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 56,
                                  fontWeight: FontWeight.w100,
                                  letterSpacing: -2)),
                          const Text('/100',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 14)),
                        ],
                      )
                    : const Text('—',
                        style: TextStyle(
                            color: Colors.white24,
                            fontSize: 56,
                            fontWeight: FontWeight.w100)),
              ),
            ),
            const SizedBox(height: 12),

            // AI 설명 텍스트
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _phase == _AiPhase.done
                    ? '저역이 실내 정재파로 +4dB 과장되어 있습니다. '
                        'AI가 100~200Hz 구간 PEQ 보정을 적용했습니다. '
                        'Reference: $_selectedRef.'
                    : '측정 후 AI Room Correction을 실행하면 분석 결과가 여기에 표시됩니다.',
                style: TextStyle(
                    color: _phase == _AiPhase.done
                        ? Colors.white70
                        : Colors.white24,
                    fontSize: 12,
                    height: 1.6),
              ),
            ),
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
                    padding: EdgeInsets.only(
                        right: r == _refPresets.last ? 0 : 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRef = r),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              active ? Colors.white : Colors.transparent,
                          border: Border.all(
                              color:
                                  active ? Colors.white : Colors.white24),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(r.toUpperCase(),
                              style: TextStyle(
                                  color: active
                                      ? Colors.black
                                      : Colors.white54,
                                  fontSize: 11,
                                  letterSpacing: 2,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w300)),
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
              onTap: (connected && _phase != _AiPhase.running)
                  ? _runAi
                  : null,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: (connected && _phase != _AiPhase.running)
                      ? Colors.white
                      : Colors.transparent,
                  border: Border.all(
                      color: connected ? Colors.white : Colors.white24),
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
                          _phase == _AiPhase.done
                              ? 'AI 재실행'
                              : 'AI ROOM CORRECTION',
                          style: TextStyle(
                              color: (connected &&
                                      _phase != _AiPhase.running)
                                  ? Colors.black
                                  : Colors.white24,
                              fontSize: 14,
                              letterSpacing: 3)),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── AI Timeline ────────────────────────────────────────────────
            const Text('AI TIMELINE',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 16),
            _AiTimeline(
                steps: _timelineSteps,
                currentStep: _phase == _AiPhase.done ? 2 : 0),
          ],
        ),
      ),
    );
  }
}

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
