import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dsp/master_volume_controller.dart';
import '../connect/connect_controller.dart';
import 'test_tone_controller.dart';

class ListenScreen extends ConsumerStatefulWidget {
  const ListenScreen({super.key});

  @override
  ConsumerState<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends ConsumerState<ListenScreen> {
  bool _loopEnabled = false;

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(masterVolumeProvider);
    final ctrl = ref.read(masterVolumeProvider.notifier);
    final connected = ref.watch(connectProvider).connected;
    final toneIsPlaying = ref.watch(testToneProvider);
    final toneCtrl = ref.read(testToneProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('LISTEN',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 6)),
            const SizedBox(height: 32),

            // ── Master Volume ──────────────────────────────────────────────
            const Text('MASTER VOLUME',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('-70',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: volume,
                    min: -70,
                    max: 0,
                    divisions: 140,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white12,
                    onChanged: connected ? ctrl.updateUiOnly : null,
                    onChangeEnd: connected ? ctrl.setVolume : null,
                  ),
                ),
                const Text('0',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
            Center(
              child: Text(
                '${volume.toStringAsFixed(1)} dB',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 32),

            // ── 테스트 버튼 ────────────────────────────────────────────────
            const Text('TEST LEVELS',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 12),
            Row(
              children: [
                _TestButton(
                    label: '-60 dB',
                    enabled: connected,
                    onTap: () => ctrl.setVolume(-60)),
                const SizedBox(width: 8),
                _TestButton(
                    label: '-50 dB',
                    enabled: connected,
                    onTap: () => ctrl.setVolume(-50)),
                const SizedBox(width: 8),
                _TestButton(
                    label: '-40 dB',
                    enabled: connected,
                    onTap: () => ctrl.setVolume(-40)),
              ],
            ),
            const SizedBox(height: 24),

            // ── Test Tone ──────────────────────────────────────────────────
            const Text('TEST TONE',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _OutlineButton(
                    label: toneIsPlaying ? '1 kHz STOP' : '1 kHz SINE',
                    icon: toneIsPlaying
                        ? Icons.stop_circle_outlined
                        : Icons.music_note_outlined,
                    enabled: true,
                    onTap: toneCtrl.toggle,
                    active: toneIsPlaying,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: _ToggleButton(
                    label: 'LOOP',
                    active: _loopEnabled,
                    onTap: connected
                        ? () => setState(() => _loopEnabled = !_loopEnabled)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            if (!connected)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'CONNECT 탭에서 DSP를 연결하면 볼륨 조절이 활성화됩니다.',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 12, height: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _TestButton(
      {required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(
                  color: enabled ? Colors.white38 : Colors.white12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      color: enabled ? Colors.white70 : Colors.white24,
                      fontSize: 12,
                      letterSpacing: 1)),
            ),
          ),
        ),
      );
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final bool active;
  final VoidCallback? onTap;

  const _OutlineButton(
      {required this.label,
      required this.icon,
      required this.enabled,
      this.active = false,
      this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
            border: Border.all(
                color: active
                    ? Colors.white54
                    : enabled ? Colors.white38 : Colors.white12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: enabled ? Colors.white60 : Colors.white24),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: enabled ? Colors.white70 : Colors.white24,
                      fontSize: 12,
                      letterSpacing: 1.5)),
            ],
          ),
        ),
      );
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ToggleButton(
      {required this.label, required this.active, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            border: Border.all(
                color: onTap != null
                    ? (active ? Colors.white : Colors.white38)
                    : Colors.white12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: onTap != null
                        ? (active ? Colors.black : Colors.white70)
                        : Colors.white24,
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w300)),
          ),
        ),
      );
}
