import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connect_controller.dart';
import '../../core/profiles/system_profile.dart';

Future<void> _showBluetoothOffDialog(BuildContext context) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text(
        '블루투스가 꺼져 있습니다',
        style: TextStyle(color: Colors.white, fontSize: 15),
      ),
      content: const Text(
        '블루투스가 꺼져 있습니다. 설정에서 켜주세요.',
        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('닫기', style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            if (Platform.isMacOS) {
              // macOS 시스템 환경설정 → Bluetooth 패널 직접 열기
              await Process.run('open', [
                'x-apple.systempreferences:com.apple.preference.bluetooth',
              ]);
            }
          },
          child: const Text('Bluetooth 설정 열기',
              style: TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
}

class ConnectScreen extends ConsumerWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectProvider);
    final ctrl = ref.read(connectProvider.notifier);
    final profile = ref.watch(systemProfileProvider);
    final connected = state.connected;
    final scanning = state.connection == ConnectionStatus.scanning ||
        state.connection == ConnectionStatus.connecting;
    // Windows는 flutter_blue_plus가 네이티브 구현체를 제공하지 않아 BLE 자체가
    // 불가능함(fed6fff에서 크래시 방지로 탭을 숨김 — 플러그인 한계, 버그 아님).
    // ADAU1466(파란보드)이 온보드 QCC5125 BLE로만 연결되는 구성이라면 Windows에서는
    // 이 앱으로 연결할 방법이 없다 — UART 포트가 하나도 안 보이는 게 정상일 수 있음.
    final bleUnavailableOnWindows = Platform.isWindows;

    // Bluetooth OFF 감지 → 안내 다이얼로그 (BLE 모드일 때만)
    ref.listen<ConnectState>(connectProvider, (prev, next) {
      if (next.connection == ConnectionStatus.bluetoothOff &&
          prev?.connection != ConnectionStatus.bluetoothOff &&
          next.mode == ConnectMode.ble) {
        _showBluetoothOffDialog(context);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('TUNAI PRO',
                    style: TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w200, letterSpacing: 6)),
                const Spacer(),
                if (state.mode == ConnectMode.uart)
                  GestureDetector(
                    onTap: connected ? null : ctrl.scanPorts,
                    child: const Icon(Icons.refresh, color: Colors.white38, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 32),

            // ── 모드 탭 ──────────────────────────────────────────────────
            Row(
              children: [
                if (!Platform.isMacOS) ...[
                  _ModeTab(
                    label: 'USB / UART',
                    active: state.mode == ConnectMode.uart,
                    onTap: connected ? null : () => ctrl.setMode(ConnectMode.uart),
                  ),
                ],
                if (!Platform.isWindows) ...[
                  if (!Platform.isMacOS) const SizedBox(width: 8),
                  _ModeTab(
                    label: 'BLE',
                    active: state.mode == ConnectMode.ble,
                    onTap: connected ? null : () => ctrl.setMode(ConnectMode.ble),
                  ),
                ],
                if (Platform.isWindows) ...[
                  const SizedBox(width: 8),
                  _ModeTab(
                    label: 'USBi (ADAU1466)',
                    active: state.mode == ConnectMode.usbi,
                    onTap: connected ? null : () => ctrl.setMode(ConnectMode.usbi),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),

            // ── TARGET 보드 선택 (수동 오버라이드) ────────────────────────
            const Text('TARGET BOARD',
                style: TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButton<SystemProfile>(
                value: profile,
                dropdownColor: const Color(0xFF111111),
                underline: const SizedBox(),
                isExpanded: true,
                items: kAllSystemProfiles.map((p) => DropdownMenuItem(
                  value: p,
                  child: Text('${p.displayName} (${p.chipLabel})',
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                )).toList(),
                onChanged: connected
                    ? null
                    : (p) {
                        if (p != null) ref.read(systemProfileProvider.notifier).state = p;
                      },
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '연결 시 자동탐지가 성공하면 이 값을 덮어씁니다 — 자동탐지가 안 되거나 '
              '틀리게 판단할 때 수동으로 지정하세요.',
              style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.5),
            ),
            const SizedBox(height: 20),

            const Text('DSP CONNECTION',
                style: TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 16),

            // ── UART 포트 선택 ───────────────────────────────────────────
            if (state.mode == ConnectMode.uart) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButton<String>(
                  value: state.selectedPort,
                  hint: Text(
                    state.ports.isEmpty ? 'NO PORTS DETECTED' : 'SELECT PORT (ICP5 / CH34x)',
                    style: const TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 1),
                  ),
                  dropdownColor: const Color(0xFF111111),
                  underline: const SizedBox(),
                  isExpanded: true,
                  items: state.ports.map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  )).toList(),
                  onChanged: connected ? null : (v) => ctrl.selectPort(v!),
                ),
              ),
              if (state.ports.isEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    bleUnavailableOnWindows
                        ? '포트가 하나도 없습니다. USB 케이블/드라이버(CH34x, FTDI, CP210x 등)를 '
                          '확인하세요. 이 보드가 BLE(온보드 QCC5125 등)로만 연결되는 구성이라면, '
                          'Windows에서는 BLE를 지원하지 않아(flutter_blue_plus 플러그인 한계) '
                          '이 앱으로 연결할 수 없습니다 — macOS 버전을 사용하세요.'
                        : 'USB 케이블 연결과 드라이버(CH34x, FTDI, CP210x 등) 설치 여부를 확인하세요.',
                    style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.6),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],

            // ── BLE 안내 ─────────────────────────────────────────────────
            if (state.mode == ConnectMode.ble && !connected) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ICP5 BLE 동글이 Remote 모드(SW1=②)로 설정되어 있는지 확인하세요.',
                  style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.6),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── USBi 장치 선택 (ADAU1466) ─────────────────────────────────
            if (state.mode == ConnectMode.usbi) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButton<String>(
                  value: state.selectedUsbiInstanceId,
                  hint: Text(
                    state.usbiDevices.isEmpty ? 'NO USBi DETECTED (VID 0x0456)' : 'SELECT USBi DEVICE',
                    style: const TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 1),
                  ),
                  dropdownColor: const Color(0xFF111111),
                  underline: const SizedBox(),
                  isExpanded: true,
                  items: state.usbiDevices.map((d) => DropdownMenuItem(
                    value: d.instanceId,
                    child: Text(d.friendlyName,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: connected ? null : (v) => v == null ? null : ctrl.selectUsbiDevice(v),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: connected ? null : ctrl.scanUsbi,
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(Icons.refresh, color: Colors.white38, size: 12),
                    SizedBox(width: 6),
                    Text('다시 스캔', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
            ],

            // ── CONNECT / SCAN / DISCONNECT 버튼 ─────────────────────────
            GestureDetector(
              onTap: scanning ? null : (connected ? ctrl.disconnect : ctrl.connect),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: scanning ? Colors.white24 : Colors.white,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  color: connected ? Colors.white : Colors.transparent,
                ),
                child: Center(
                  child: Text(
                    connected
                        ? 'DISCONNECT'
                        : scanning
                            ? (state.mode == ConnectMode.ble ? 'SCANNING...' : 'CONNECTING...')
                            : (state.mode == ConnectMode.ble ? 'SCAN & CONNECT' : 'CONNECT'),
                    style: TextStyle(
                      color: connected
                          ? Colors.black
                          : scanning ? Colors.white38 : Colors.white,
                      fontSize: 14, letterSpacing: 3,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── 보드 자동탐지 배너 ─────────────────────────────────────────
            if (state.detectedBoard == DetectedBoard.adau1466) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.amber.withValues(alpha: 0.05),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 14),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'ADAU1466 보드가 탐지됐습니다. Gain/Delay/PEQ는 사용 가능하고, '
                    '크로스오버(XO)는 SafeLoad 프로토콜 실기기 검증 전까지 잠겨 있습니다.\n'
                    '위 TARGET에서 Isobarik/Reference 중 실제 보드에 맞는 쪽을 선택하세요.',
                    style: TextStyle(color: Colors.amber, fontSize: 12, height: 1.5),
                  )),
                ]),
              ),
              const SizedBox(height: 8),
            ] else if (connected && state.detectedBoard == DetectedBoard.unknown) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(children: [
                  Icon(Icons.help_outline, color: Colors.white38, size: 14),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    '보드를 자동으로 식별하지 못했습니다. 아래 목록에서 직접 선택하세요.',
                    style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
                  )),
                ]),
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 8),

            // ── 상태 패널 ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('STATUS',
                      style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 2)),
                  const SizedBox(height: 12),
                  _infoRow('MODE', switch (state.mode) {
                    ConnectMode.ble => 'BLE',
                    ConnectMode.usbi => 'USBi',
                    ConnectMode.uart => 'UART',
                  }),
                  _infoRow(
                    state.mode == ConnectMode.uart ? 'PORT' : 'DEVICE',
                    state.deviceName ?? state.selectedPort ?? '-',
                  ),
                  if (state.mode == ConnectMode.uart) _infoRow('BAUD', '38400'),
                  _infoRow('TARGET', '${profile.displayName} (${profile.chipLabel})'),
                  _infoRow('STATUS', state.status,
                      error: state.status.startsWith('ERROR')),
                  if (state.mode == ConnectMode.uart && state.ports.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 8),
                    const Text('AVAILABLE PORTS',
                        style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    ...state.ports.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(p,
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(width: 70,
            child: Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 1))),
        Expanded(
          child: Text(value,
              style: TextStyle(
                color: error ? Colors.redAccent : Colors.white,
                fontSize: 13,
              )),
        ),
      ],
    ),
  );
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ModeTab({required this.label, required this.active, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.transparent,
        border: Border.all(color: active ? Colors.white : Colors.white24),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.black : Colors.white60,
          fontSize: 13,
          letterSpacing: 2,
          fontWeight: active ? FontWeight.w600 : FontWeight.w300,
        ),
      ),
    ),
  );
}
