import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connect_controller.dart';

class ConnectScreen extends ConsumerWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectProvider);
    final ctrl = ref.read(connectProvider.notifier);
    final connected = state.connection == UartConnectionState.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Padding(
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
                GestureDetector(
                  onTap: ctrl.scanPorts,
                  child: const Icon(Icons.refresh, color: Colors.white38, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 48),
            const Text('DSP CONNECTION',
                style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 3)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButton<String>(
                value: state.selectedPort,
                hint: Text(
                  state.ports.isEmpty ? 'NO PORTS DETECTED' : 'SELECT UART PORT',
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
            GestureDetector(
              onTap: state.selectedPort == null ? null
                  : connected ? ctrl.disconnect : ctrl.connect,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: state.selectedPort == null ? Colors.white12 : Colors.white,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  color: connected ? Colors.white : Colors.transparent,
                ),
                child: Center(
                  child: Text(
                    connected ? 'DISCONNECT' : 'CONNECT',
                    style: TextStyle(
                      color: connected ? Colors.black
                          : state.selectedPort == null ? Colors.white24 : Colors.white,
                      fontSize: 12, letterSpacing: 3,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
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
                  _infoRow('PORT', state.selectedPort ?? '-',
                      error: state.status.startsWith('ERROR')),
                  _infoRow('BAUD', '38400'),
                  _infoRow('TARGET', 'ADAU1701 via ICP5'),
                  _infoRow('STATUS', state.status,
                      error: state.status.startsWith('ERROR')),
                  if (state.ports.isNotEmpty) ...[
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
