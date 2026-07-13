// ── TUNAI PRO Hardware MVP Status Card ────────────────────────────────────────
// Shows today's hardware validation MVP status.
// Imported by both hardware_tab.dart and report_tab.dart.

import 'package:flutter/material.dart';
import '../../../shared/pro_widgets.dart';

/// Today's Hardware MVP Status Card.
///
/// Static summary of what is confirmed, guarded, dry-run, blocked, or pending.
/// Does not trigger any hardware write.
class HardwareMvpStatusCard extends StatelessWidget {
  const HardwareMvpStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_outline, color: kProAccent, size: 13),
            const SizedBox(width: 8),
            Text("Today's Hardware MVP Status", style: proTitle(size: 12)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kProAccent.withValues(alpha: 0.07),
                border: Border.all(color: kProAccent.withValues(alpha: 0.25)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'TUNAI PRO · Hardware MVP Test Build · USBi MV confirmed · ICP5 final target',
                style: TextStyle(
                    fontSize: 7, color: kProAccent, letterSpacing: 0.3),
              ),
            ),
          ]),
        ),
        // Status rows
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _MvpRow(
              'Master Volume L/R',
              'live write confirmed (USBi, volatile only)',
              Colors.greenAccent,
              Icons.check_circle_outline,
            ),
            const _MvpRow(
              'USBi ACK',
              'confirmed — single-byte [01] accepted',
              Colors.greenAccent,
              Icons.check_circle_outline,
            ),
            const _MvpRow(
              'Mute/Gain',
              'guarded validation ready — requires address + value format confirmation',
              kProAmber,
              Icons.tune_outlined,
            ),
            const _MvpRow(
              'Delay',
              'dry-run only — requires oscilloscope / timing measurement',
              Colors.blueAccent,
              Icons.access_time_outlined,
            ),
            const _MvpRow(
              'PEQ',
              'dry-run only — requires SafeLoad validation first',
              Colors.blueAccent,
              Icons.graphic_eq_outlined,
            ),
            const _MvpRow(
              'XO',
              'BLOCKED — requires SafeLoad + output mapping verification',
              Colors.redAccent,
              Icons.block_outlined,
            ),
            const _MvpRow(
              'SafeLoad',
              'dry-run only — prerequisite for PEQ/XO live write',
              Colors.blueAccent,
              Icons.save_outlined,
            ),
            const _MvpRow(
              'EEPROM / Selfboot',
              'FORBIDDEN — not implemented, not planned for USBi path',
              Colors.redAccent,
              Icons.block_outlined,
            ),
            const _MvpRow(
              'ICP5',
              'final transport target — pending, not implemented yet',
              Colors.white38,
              Icons.pending_outlined,
            ),
            const _MvpRow(
              'BLE',
              'pending — not implemented',
              Colors.white38,
              Icons.bluetooth_outlined,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MvpRow extends StatelessWidget {
  final String label;
  final String status;
  final Color color;
  final IconData icon;

  const _MvpRow(this.label, this.status, this.color, this.icon);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 6),
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(fontSize: 9, color: Colors.white60)),
          ),
          Expanded(
            child: Text(status,
                style: TextStyle(
                    fontSize: 9,
                    color: color,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}
