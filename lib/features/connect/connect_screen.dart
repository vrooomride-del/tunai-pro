import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connect_controller.dart';

class ConnectScreen extends ConsumerWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectProvider);
    final ctrl = ref.read(connectProvider.notifier);
    final connected = state.connected;
    final scanning = state.connection == ConnectionStatus.scanning ||
        state.connection == ConnectionStatus.connecting;

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
                _ModeTab(
                  label: 'USB / UART',
                  active: state.mode == ConnectMode.uart,
                  onTap: connected ? null : () => ctrl.setMode(ConnectMode.uart),
                ),
                if (!Platform.isWindows) ...[
                  const SizedBox(width: 8),
                  _ModeTab(
                    label: 'BLE',
                    active: state.mode == ConnectMode.ble,
                    onTap: connected ? null : () => ctrl.setMode(ConnectMode.ble),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),

            const Text('DSP CONNECTION',
                style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 3)),
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
                    style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1),
                  ),
                  dropdownColor: const Color(0xFF111111),
                  underline: const SizedBox(),
                  isExpanded: true,
                  items: state.ports.map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 11)),
                  )).toList(),
                  onChanged: connected ? null : (v) => ctrl.selectPort(v!),
                ),
              ),
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
                  style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.6),
                ),
              ),
              const SizedBox(height: 12),
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
                      fontSize: 12, letterSpacing: 3,
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
                    'ADAU1466 보드가 탐지됐습니다. 현재 지원 준비 중입니다.\n'
                    'ADAU1701(JAB4) 보드에서 사용 가능합니다.',
                    style: TextStyle(color: Colors.amber, fontSize: 10, height: 1.5),
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
                    style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.5),
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
                      style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
                  const SizedBox(height: 12),
                  _infoRow('MODE', state.mode == ConnectMode.ble ? 'BLE' : 'UART'),
                  _infoRow(
                    state.mode == ConnectMode.ble ? 'DEVICE' : 'PORT',
                    state.deviceName ?? state.selectedPort ?? '-',
                  ),
                  if (state.mode == ConnectMode.uart) _infoRow('BAUD', '38400'),
                  _infoRow('TARGET', 'ADAU1701 via ICP5'),
                  _infoRow('STATUS', state.status,
                      error: state.status.startsWith('ERROR')),
                  if (state.mode == ConnectMode.uart && state.ports.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 8),
                    const Text('AVAILABLE PORTS',
                        style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    ...state.ports.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(p,
                          style: const TextStyle(color: Colors.white38, fontSize: 10)),
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
                style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1))),
        Expanded(
          child: Text(value,
              style: TextStyle(
                color: error ? Colors.redAccent : Colors.white,
                fontSize: 10,
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
          color: active ? Colors.black : Colors.white38,
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: active ? FontWeight.w600 : FontWeight.w300,
        ),
      ),
    ),
  );
}
