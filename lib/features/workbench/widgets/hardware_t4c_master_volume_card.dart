// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-2B).
//
// UI extraction only: this is the same widget that lived as the private
// `_T4cMasterVolumePanel` class inside hardware_tab.dart, moved verbatim
// (renamed to a public class so it can be imported) with no change to the
// Master Volume address/packet computation, the device open/close button
// wiring, or the execute/restore button conditions. All 7 callbacks
// (onSideChanged/onValueChanged/onOpenDevice/onCloseDevice/
// onConfirmChanged/onExecute/onRestore) are still implemented at the call
// site in hardware_tab.dart — this widget only receives and displays state,
// it does not touch the USBi executor, device lifecycle, DSP address
// mapping, or any provider/controller/BLE/transport logic. CmdRow and
// T4cResultLog are shared with the other T4C cards via
// hardware_t4c_shared.dart (Phase 3-C-3D) rather than duplicated here.

import 'package:flutter/material.dart';

import '../../../core/pro_transport_command_data.dart';
import '../../../core/pro_usbi_packet_builder.dart';
import '../../../core/pro_usbi_executor_data.dart';
import 'hardware_t4c_shared.dart' show CmdRow, T4cResultLog;

class HardwareT4cMasterVolumeCard extends StatelessWidget {
  final String side;
  final double value;
  final bool deviceOpen;
  final bool checking;
  final String? openError;
  final bool executing;
  final bool userConfirmed;
  final UsbiExecutionResult? lastResult;
  final ValueChanged<String> onSideChanged;
  final ValueChanged<double> onValueChanged;
  final VoidCallback onOpenDevice;
  final VoidCallback onCloseDevice;
  final ValueChanged<bool> onConfirmChanged;
  final VoidCallback onExecute;
  final VoidCallback onRestore;

  const HardwareT4cMasterVolumeCard({
    super.key,
    required this.side,
    required this.value,
    required this.deviceOpen,
    required this.checking,
    required this.openError,
    required this.executing,
    required this.userConfirmed,
    required this.lastResult,
    required this.onSideChanged,
    required this.onValueChanged,
    required this.onOpenDevice,
    required this.onCloseDevice,
    required this.onConfirmChanged,
    required this.onExecute,
    required this.onRestore,
  });

  int get _addrInt => side == 'L' ? kMasterVolumeLAddr : kMasterVolumeRAddr;
  String get _addrHex => side == 'L' ? '0x0067' : '0x0064';
  int get _fixedInt => value >= 1.0
      ? 0x01000000
      : value >= 0.5
          ? 0x00800000
          : 0x00000000;
  String get _fixedHex =>
      '0x${_fixedInt.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  String get _bodyHex {
    final b = buildParameterWriteBody(
        addressInt: _addrInt, fixedPointInt: _fixedInt);
    return bytesToHex(b);
  }

  bool get _canExecute =>
      deviceOpen && userConfirmed && !executing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A2E),
        border: Border.all(color: const Color(0xFF1E4080)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Build marker
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withValues(alpha: 0.1),
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text(
            'TUNAI PRO · T4C USBi MV Test Build · USBi MV executor present',
            style: TextStyle(fontSize: 8, color: Colors.blueAccent,
                fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
        ),
        const SizedBox(height: 10),

        // Section header
        Row(children: [
          const Icon(Icons.usb_outlined, size: 13, color: Colors.orange),
          const SizedBox(width: 6),
          const Text('USBi Temporary Master Volume Executor',
              style: TextStyle(fontSize: 11, color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),

        // Warning
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.07),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text(
            'PHASE T4C — Temporary USBi engineering path. '
            'ADAU1466 Master Volume L/R ONLY (0x0067 / 0x0064). '
            'Volatile write — no EEPROM, no Selfboot, no SafeLoad. '
            'ICP5 is the final transport target.',
            style: TextStyle(fontSize: 8, color: Colors.orange),
          ),
        ),
        const SizedBox(height: 12),

        // Backend status + open/close
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (deviceOpen ? Colors.greenAccent : Colors.orange)
                  .withValues(alpha: 0.1),
              border: Border.all(
                  color: (deviceOpen ? Colors.greenAccent : Colors.orange)
                      .withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              deviceOpen ? 'USBi CONNECTED' : 'USBi NOT OPEN',
              style: TextStyle(
                  fontSize: 8,
                  color: deviceOpen ? Colors.greenAccent : Colors.orange,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 24,
            child: OutlinedButton.icon(
              onPressed: (!deviceOpen && !checking) ? onOpenDevice : null,
              icon: checking
                  ? const SizedBox(width: 10, height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.2, color: Colors.white54))
                  : const Icon(Icons.usb_outlined, size: 11),
              label: const Text('Open USBi Device',
                  style: TextStyle(fontSize: 9)),
              style: OutlinedButton.styleFrom(
                foregroundColor: deviceOpen ? Colors.white24 : Colors.white70,
                side: BorderSide(
                    color: deviceOpen ? Colors.white12 : Colors.white38),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 24,
            child: OutlinedButton.icon(
              onPressed: deviceOpen ? onCloseDevice : null,
              icon: const Icon(Icons.usb_off_outlined, size: 11),
              label: const Text('Close', style: TextStyle(fontSize: 9)),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    deviceOpen ? Colors.redAccent : Colors.white24,
                side: BorderSide(
                    color: deviceOpen
                        ? Colors.redAccent.withValues(alpha: 0.5)
                        : Colors.white12),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
        ]),
        if (openError != null) ...[
          const SizedBox(height: 4),
          Text(openError!,
              style: const TextStyle(fontSize: 8, color: Colors.redAccent)),
        ],
        const SizedBox(height: 12),

        // Side selector: L / R
        Row(children: [
          const Text('Channel:',
              style: TextStyle(fontSize: 9, color: Colors.white38)),
          const SizedBox(width: 8),
          for (final s in ['L', 'R']) ...[
            GestureDetector(
              onTap: () => onSideChanged(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: side == s
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.white10,
                  border: Border.all(
                      color: side == s ? Colors.orange : Colors.white24),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(s,
                    style: TextStyle(
                        fontSize: 9,
                        color: side == s ? Colors.orange : Colors.white60,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),

        // Value preset: 1.0 / 0.5 / 0.0
        Row(children: [
          const Text('Value:',
              style: TextStyle(fontSize: 9, color: Colors.white38)),
          const SizedBox(width: 8),
          for (final v in [1.0, 0.5, 0.0]) ...[
            GestureDetector(
              onTap: () => onValueChanged(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: value == v
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.white10,
                  border: Border.all(
                      color: value == v ? Colors.orange : Colors.white24),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(v.toStringAsFixed(1),
                    style: TextStyle(
                        fontSize: 9,
                        color: value == v ? Colors.orange : Colors.white60,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),

        // Address / packet preview
        CmdRow('Address', '$_addrHex  (Master Volume $side)'),
        CmdRow('Fixed 8.24', _fixedHex),
        CmdRow('Body hex', _bodyHex),
        const SizedBox(height: 12),

        // Confirm checkbox
        Row(children: [
          SizedBox(
            width: 18, height: 18,
            child: Checkbox(
              value: userConfirmed,
              onChanged: deviceOpen
                  ? (v) => onConfirmChanged(v ?? false)
                  : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: Colors.orange,
              side: const BorderSide(color: Colors.white30),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'I understand this is a volatile Master Volume write only. '
              'No EEPROM. No Selfboot. Address is PASS_ACK; audible or measured verification is pending.',
              style: TextStyle(fontSize: 9, color: Colors.white60),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // Execute + Restore buttons
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: _canExecute ? onExecute : null,
                icon: executing
                    ? const SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white))
                    : const Icon(Icons.send_outlined, size: 13),
                label: Text(
                  executing
                      ? 'Sending...'
                      : !deviceOpen
                          ? 'Open USBi device first'
                          : !userConfirmed
                              ? 'Check confirmation above'
                              : 'Execute via USBi Temporary',
                  style: const TextStyle(fontSize: 10),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canExecute
                      ? Colors.orange.withValues(alpha: 0.8)
                      : Colors.white10,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: (deviceOpen && !executing) ? onRestore : null,
              icon: const Icon(Icons.restore_outlined, size: 13),
              label: const Text('Restore L/R to 1.0',
                  style: TextStyle(fontSize: 10)),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    deviceOpen ? Colors.white70 : Colors.white24,
                side: BorderSide(
                    color: deviceOpen ? Colors.white38 : Colors.white12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ]),

        // Result log
        if (lastResult != null) ...[
          const SizedBox(height: 12),
          T4cResultLog(result: lastResult!),
        ],

        // Footer
        const SizedBox(height: 10),
        const Text(
          'ICP5 remains final target. '
          'No PEQ/XO/Gain/Mute/Delay/SafeLoad/EEPROM/Selfboot.',
          style: TextStyle(fontSize: 8, color: Colors.white24),
        ),
      ]),
    );
  }
}
