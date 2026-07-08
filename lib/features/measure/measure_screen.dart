import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    // TODO: 실측 연동 — 현재는 UI skeleton
    for (var i = 0; i <= 100; i += 5) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => _progress = i / 100.0);
    }
    if (mounted) setState(() => _phase = _MeasurePhase.done);
  }

  void _reset() => setState(() {
        _phase = _MeasurePhase.idle;
        _progress = 0;
      });

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(connectProvider).connected;

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
                style:
                    TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 32),

            // ── 측정 버튼 ──────────────────────────────────────────────────
            if (_phase == _MeasurePhase.idle) ...[
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
                                color:
                                    connected ? Colors.white : Colors.white24,
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
                        color: Colors.white38, fontSize: 11, letterSpacing: 1)),
              ],
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
                              strokeWidth: 1.5,
                              color: Colors.white54)),
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

            // ── Before / After 그래프 placeholder ──────────────────────────
            const Text('FREQUENCY RESPONSE',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 12),
            Container(
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Stack(
                children: [
                  // 그래프 placeholder (측정 전: 안내, 측정 후: 실제 데이터)
                  if (_phase != _MeasurePhase.done)
                    const Center(
                      child: Text('측정 후 그래프가 표시됩니다',
                          style: TextStyle(
                              color: Colors.white24, fontSize: 12)),
                    )
                  else
                    CustomPaint(
                      painter: _PlaceholderCurvePainter(),
                      child: const SizedBox.expand(),
                    ),
                  // 범례
                  const Positioned(
                    top: 10,
                    right: 12,
                    child: Row(
                      children: [
                        _LegendDot(color: Colors.white38, label: 'BEFORE'),
                        SizedBox(width: 12),
                        _LegendDot(color: Colors.white70, label: 'AFTER'),
                        SizedBox(width: 12),
                        _LegendDot(color: Colors.blueAccent, label: 'TARGET'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 8, height: 2, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 9, letterSpacing: 1)),
        ],
      );
}

class _PlaceholderCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height * 0.6);
    for (var x = 0.0; x <= size.width; x++) {
      final t = x / size.width;
      final y = size.height *
          (0.5 + 0.15 * _fakeResponse(t) - 0.05 * (t - 0.5) * (t - 0.5));
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  double _fakeResponse(double t) =>
      0.3 * (1 - t) + 0.2 * (t * (1 - t)) - 0.1 * t;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
