import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../connect/connect_controller.dart';
import '../../core/dsp/transport/dsp_transport_provider.dart';
import '../../core/profiles/system_profile.dart';
import 'dsp_unlock_flags.dart';

// ── 주소 상수 (ADAU1466 v0.8B Export18) ────────────────────────────────────
const _kDriverGainAddrs = [0x3B8, 0x3BB, 0x3C4, 0x3CA, 0x3C7, 0x3CD];
const _kDriverMuteAddrs = [0x60E, 0x60F, 0x613, 0x612, 0x610, 0x611];
// 아래 상수는 Step 3 SafeLoad 구현 시 사용 — 지금은 UI 표시용
const kDriverDelayAddrs = [0x3C1, 0x3C2, 0x408, 0x406, 0x405, 0x407];
const kGlobalPeqLAddr = 0x69;
const kGlobalPeqRAddr = 0x9B;
const _kPerDriverPeqAddrs = [0x21A, 0x27E, 0x326, 0x2F4, 0x24C, 0x2B0];
const _kDspMapVersion = 'ADAU1466 v0.8B Export18';

const _kChannelNames = [
  'WOO L', 'WOO R', 'MID L', 'MID R', 'TWE L', 'TWE R',
];

// ── 주소 상수 (ADAU1701 v0.8 Export14) ─────────────────────────────────────
const _kDspMapVersion1701 = 'ADAU1701 v0.8 Export14';
const _kGain1701Addrs = [0x0084, 0x0085, 0x0088, 0x0089];
const _kMute1701Addrs = [0x0086, 0x0087, 0x008A, 0x008B];
// delay addrs: 0x008C~0x008F (채널 미확정, 잠금)
const _kPeq1701Addrs = [0x0030, 0x0045, 0x0064, 0x0074];
const _kChannelNames1701 = ['WOO L', 'WOO R', 'TWE L', 'TWE R'];

final _gain1701Provider =
    StateProvider<List<double>>((ref) => List.filled(4, 0.0));
final _mute1701Provider =
    StateProvider<List<bool>>((ref) => List.filled(4, false));
final _delay1701Provider =
    StateProvider<List<double>>((ref) => List.filled(4, 0.0));

// Riverpod 상태
final _factoryUnlockedProvider = StateProvider<bool>((ref) => false);
final _gainProvider = StateProvider<List<double>>(
    (ref) => List.filled(6, 0.0));
final _muteProvider = StateProvider<List<bool>>(
    (ref) => List.filled(6, false));
final _delayProvider = StateProvider<List<double>>(
    (ref) => List.filled(6, 0.0));
final _globalPeqProvider = StateProvider<List<double>>(
    (ref) => List.filled(20, 0.0));

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(_factoryUnlockedProvider);
    final isAdau1466 = ref.watch(systemProfileProvider).isAdau1466;
    final dspMapVersion = isAdau1466 ? _kDspMapVersion : _kDspMapVersion1701;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MORE',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 6)),
            const SizedBox(height: 32),

            // ── Factory 모드 잠금/해제 ──────────────────────────────────────
            const _SectionHeader(label: 'FACTORY MODE'),
            const SizedBox(height: 12),
            if (!unlocked)
              GestureDetector(
                onTap: () =>
                    _showPinDialog(context, ref),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline,
                            color: Colors.white38, size: 16),
                        SizedBox(width: 10),
                        Text('FACTORY 모드 진입',
                            style: TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                                letterSpacing: 2)),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              _UnlockBadge(onLock: () =>
                  ref.read(_factoryUnlockedProvider.notifier).state = false),
              const SizedBox(height: 24),
              if (isAdau1466) _FactoryContent() else _Adau1701FactoryContent(),
            ],
            const SizedBox(height: 32),

            // ── DSP 맵 버전 ─────────────────────────────────────────────────
            const _SectionHeader(label: 'DSP MAP'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.memory_outlined,
                      color: Colors.white38, size: 14),
                  const SizedBox(width: 10),
                  Text(dspMapVersion,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          letterSpacing: 1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPinDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Factory 모드',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'PIN 입력',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white70)),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인',
                  style: TextStyle(color: Colors.white70))),
        ],
      ),
    );
    if (ok == true && controller.text == '1234') {
      ref.read(_factoryUnlockedProvider.notifier).state = true;
    } else if (ok == true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('PIN이 올바르지 않습니다'),
              backgroundColor: Color(0xFF1A1A1A)),
        );
      }
    }
  }
}

class _FactoryContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(connectProvider).connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Driver Gain ────────────────────────────────────────────────────
        const _SectionHeader(label: 'DRIVER GAIN'),
        const SizedBox(height: 4),
        const Text('즉시 write 가능 (Capture Window 불필요)',
            style: TextStyle(
                color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        _GainSliders(connected: connected),
        const SizedBox(height: 24),

        // ── Driver Mute ────────────────────────────────────────────────────
        const _SectionHeader(label: 'DRIVER MUTE'),
        const _LockedBadge(reason: 'Capture Window 확인 필요'),
        const SizedBox(height: 12),
        _MuteToggles(),
        const SizedBox(height: 24),

        // ── Driver Delay ───────────────────────────────────────────────────
        const _SectionHeader(label: 'DRIVER DELAY (samples)'),
        const _LockedBadge(reason: 'Capture Window 확인 필요'),
        const SizedBox(height: 12),
        _DelaySliders(),
        const SizedBox(height: 24),

        // ── Global PEQ ─────────────────────────────────────────────────────
        const _SectionHeader(label: 'GLOBAL PEQ L / R (20-band)'),
        const _LockedBadge(reason: 'SafeLoad 구현 완료 후 unlock'),
        const SizedBox(height: 12),
        _GlobalPeqSliders(),
        const SizedBox(height: 24),

        // ── Per-driver PEQ ─────────────────────────────────────────────────
        const _SectionHeader(label: 'PER-DRIVER PEQ (6ch × 20-band)'),
        const _LockedBadge(reason: 'SafeLoad 구현 완료 후 unlock'),
        const SizedBox(height: 12),
        _PerDriverPeqInfo(),
      ],
    );
  }
}

// ── Driver Gain 슬라이더 ─────────────────────────────────────────────────────
class _GainSliders extends ConsumerWidget {
  final bool connected;

  const _GainSliders({required this.connected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gains = ref.watch(_gainProvider);
    final transport = ref.watch(dspTransportProvider);

    return Column(
      children: List.generate(6, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(_kChannelNames[i],
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1)),
              ),
              Expanded(
                child: Slider(
                  value: gains[i],
                  min: -40,
                  max: 12,
                  divisions: 104,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white12,
                  onChanged: (connected && DspUnlockFlags.gainWriteUnlocked)
                      ? (v) {
                          final next = List<double>.from(gains);
                          next[i] = v;
                          ref.read(_gainProvider.notifier).state = next;
                        }
                      : null,
                  onChangeEnd:
                      (connected && DspUnlockFlags.gainWriteUnlocked)
                          ? (v) async {
                              if (transport == null) return;
                              final linear = pow(10.0, v / 20.0).toDouble();
                              final fixed =
                                  (linear * (1 << 27)).round();
                              final bytes = [
                                (fixed >> 24) & 0xFF,
                                (fixed >> 16) & 0xFF,
                                (fixed >> 8) & 0xFF,
                                fixed & 0xFF,
                              ];
                              await transport.writeParameter(
                                  _kDriverGainAddrs[i], bytes);
                            }
                          : null,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${gains[i].toStringAsFixed(1)}dB',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Driver Mute 토글 ─────────────────────────────────────────────────────────
class _MuteToggles extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mutes = ref.watch(_muteProvider);

    return Column(
      children: List.generate(6, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(_kChannelNames[i],
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1)),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message:
                    'addr: 0x${_kDriverMuteAddrs[i].toRadixString(16).toUpperCase()}',
                child: GestureDetector(
                  onTap: null, // DspUnlockFlags.muteWriteUnlocked = false
                  child: Container(
                    width: 48,
                    height: 26,
                    decoration: BoxDecoration(
                      color:
                          mutes[i] ? Colors.white24 : Colors.transparent,
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Center(
                      child: Text(mutes[i] ? 'MUTE' : 'ON',
                          style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 9,
                              letterSpacing: 1)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                  '0x${_kDriverMuteAddrs[i].toRadixString(16).toUpperCase()}',
                  style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      fontFamily: 'monospace')),
            ],
          ),
        );
      }),
    );
  }
}

// ── Driver Delay 슬라이더 (잠금) ──────────────────────────────────────────────
class _DelaySliders extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delays = ref.watch(_delayProvider);

    return Column(
      children: List.generate(6, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(_kChannelNames[i],
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1)),
              ),
              Expanded(
                child: Slider(
                  value: delays[i],
                  min: 0,
                  max: 100,
                  divisions: 100,
                  activeColor: Colors.white12,
                  inactiveColor: Colors.white12,
                  onChanged: null, // DspUnlockFlags.delayWriteUnlocked = false
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${delays[i].toStringAsFixed(0)}smp',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Global PEQ 슬라이더 (잠금) ────────────────────────────────────────────────
class _GlobalPeqSliders extends ConsumerWidget {
  static const _freqs = [
    '20', '32', '50', '80', '125', '200', '315', '500', '800', '1k',
    '1.6k', '2.5k', '4k', '6.3k', '10k', '12.5k', '14k', '16k', '18k', '20k',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bands = ref.watch(_globalPeqProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('L  (0x69) / R  (0x9B)',
            style: TextStyle(
                color: Colors.white24,
                fontSize: 10,
                fontFamily: 'monospace',
                letterSpacing: 0.5)),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(20, (i) {
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(
                          value: bands[i],
                          min: -12,
                          max: 12,
                          activeColor: Colors.white12,
                          inactiveColor: Colors.white12,
                          onChanged: null,
                        ),
                      ),
                    ),
                    Text(_freqs[i],
                        style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 7,
                            letterSpacing: 0)),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ── Per-driver PEQ 안내 ──────────────────────────────────────────────────────
class _PerDriverPeqInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(6, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(_kChannelNames[i],
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ),
              Text(
                  '0x${_kPerDriverPeqAddrs[i].toRadixString(16).toUpperCase()}  · 20-band',
                  style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5)),
            ],
          ),
        );
      }),
    );
  }
}

// ── 공용 위젯 ─────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(
          color: Colors.white60, fontSize: 13, letterSpacing: 3));
}

class _LockedBadge extends StatelessWidget {
  final String reason;

  const _LockedBadge({required this.reason});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.white24, size: 11),
            const SizedBox(width: 5),
            Text(reason,
                style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 10,
                    letterSpacing: 0.5)),
          ],
        ),
      );
}

// ── ADAU1701 Factory Content ─────────────────────────────────────────────────

class _Adau1701FactoryContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transport = ref.watch(dspTransportProvider);
    final connected = ref.watch(connectProvider).connected;
    final gains = ref.watch(_gain1701Provider);
    final mutes = ref.watch(_mute1701Provider);
    final delays = ref.watch(_delay1701Provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Driver Gain ──────────────────────────────────────────────────
        const _SectionHeader(label: 'DRIVER GAIN'),
        const SizedBox(height: 4),
        const Text('즉시 write 가능 (Capture Window 불필요)',
            style: TextStyle(
                color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        Column(
          children: List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(_kChannelNames1701[i],
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1)),
                  ),
                  Expanded(
                    child: Slider(
                      value: gains[i],
                      min: -40,
                      max: 12,
                      divisions: 104,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white12,
                      onChanged: (connected && DspUnlockFlags.gainWriteUnlocked)
                          ? (v) {
                              final next = List<double>.from(gains);
                              next[i] = v;
                              ref.read(_gain1701Provider.notifier).state = next;
                            }
                          : null,
                      onChangeEnd:
                          (connected && DspUnlockFlags.gainWriteUnlocked)
                              ? (v) async {
                                  if (transport == null) return;
                                  final linear =
                                      pow(10.0, v / 20.0).toDouble();
                                  final fixed =
                                      (linear * (1 << 23)).round();
                                  final bytes = [
                                    (fixed >> 24) & 0xFF,
                                    (fixed >> 16) & 0xFF,
                                    (fixed >> 8) & 0xFF,
                                    fixed & 0xFF,
                                  ];
                                  await transport.writeParameter(
                                      _kGain1701Addrs[i], bytes);
                                }
                              : null,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${gains[i].toStringAsFixed(1)}dB',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        // ── Driver Mute (잠금) ────────────────────────────────────────────
        const _SectionHeader(label: 'DRIVER MUTE'),
        const _LockedBadge(reason: 'Capture Window 확인 필요'),
        const SizedBox(height: 12),
        Column(
          children: List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(_kChannelNames1701[i],
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1)),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message:
                        'addr: 0x${_kMute1701Addrs[i].toRadixString(16).toUpperCase().padLeft(4, '0')}',
                    child: Container(
                      width: 48,
                      height: 26,
                      decoration: BoxDecoration(
                        color: mutes[i] ? Colors.white24 : Colors.transparent,
                        border: Border.all(color: Colors.white12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Center(
                        child: Text(mutes[i] ? 'MUTE' : 'ON',
                            style: const TextStyle(
                                color: Colors.white24,
                                fontSize: 9,
                                letterSpacing: 1)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                      '0x${_kMute1701Addrs[i].toRadixString(16).toUpperCase().padLeft(4, '0')}',
                      style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          fontFamily: 'monospace')),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        // ── Driver Delay (잠금) ───────────────────────────────────────────
        const _SectionHeader(label: 'DRIVER DELAY (samples)'),
        const _LockedBadge(reason: '채널 미확정'),
        const SizedBox(height: 12),
        Column(
          children: List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(_kChannelNames1701[i],
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1)),
                  ),
                  Expanded(
                    child: Slider(
                      value: delays[i],
                      min: 0,
                      max: 100,
                      divisions: 100,
                      activeColor: Colors.white12,
                      inactiveColor: Colors.white12,
                      onChanged: null,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${delays[i].toStringAsFixed(0)}smp',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        // ── Per-driver PEQ (잠금) ─────────────────────────────────────────
        const _SectionHeader(label: 'PER-DRIVER PEQ (4ch × 20-band)'),
        const _LockedBadge(reason: 'SafeLoad 구현 완료 후 unlock'),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(_kChannelNames1701[i],
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ),
                  Text(
                      '0x${_kPeq1701Addrs[i].toRadixString(16).toUpperCase().padLeft(4, '0')}  · 20-band',
                      style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5)),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _UnlockBadge extends StatelessWidget {
  final VoidCallback onLock;

  const _UnlockBadge({required this.onLock});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Icon(Icons.lock_open_outlined,
              color: Colors.white54, size: 13),
          const SizedBox(width: 6),
          const Text('Factory 모드 활성',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  letterSpacing: 1)),
          const Spacer(),
          GestureDetector(
            onTap: onLock,
            child: const Text('잠금',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white24)),
          ),
        ],
      );
}
