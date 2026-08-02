// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-2G).
//
// UI extraction only: this is the same widget that lived as the private
// `_ConnectionPanel` class (with its private `_StatusDot` and `_SelectChip`
// helpers) inside hardware_tab.dart, moved verbatim with no change to the
// transport/target chip lists, the status dot color mapping, the "Check
// Connection Placeholder" button, or the `_timeLabel` formatting helper.
// This widget only receives `conn`/`onTransport`/`onTarget`/`onCheck` and
// calls the callbacks — it does not read any provider/ref/controller,
// does not touch BLE/USBi/ICP5 transport, connection state computation,
// or DSP target policy. All of that stays in hardware_tab.dart's
// `_HardwareTabState`. `_StatusDot` and `_SelectChip` stay private to this
// file — neither is promoted to public.

import 'package:flutter/material.dart';

import '../../../core/pro_hardware_connection_data.dart';
import '../../../shared/pro_widgets.dart';

class HardwareConnectionCard extends StatelessWidget {
  final HardwareConnectionState conn;
  final ValueChanged<HardwareTransportType> onTransport;
  final ValueChanged<HardwareTargetDevice> onTarget;
  final VoidCallback onCheck;

  const HardwareConnectionCard({
    super.key,
    required this.conn,
    required this.onTransport,
    required this.onTarget,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Transport selector
        Text('TRANSPORT', style: proLabel(size: 9, color: Colors.white38, spacing: 1.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final t in [
            HardwareTransportType.simulationOnly,
            HardwareTransportType.usbi,
            HardwareTransportType.ble,
            HardwareTransportType.usbAudio,
          ])
            _SelectChip(
              label: t.label,
              selected: conn.transportType == t,
              onTap: () => onTransport(t),
            ),
        ]),
        const SizedBox(height: 12),

        // Device target
        Text('DEVICE TARGET', style: proLabel(size: 9, color: Colors.white38, spacing: 1.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final d in [
            HardwareTargetDevice.simulation,
            HardwareTargetDevice.adau1466,
            HardwareTargetDevice.adau1701,
            HardwareTargetDevice.aosBox,
          ])
            _SelectChip(
              label: d.label,
              selected: conn.targetDevice == d,
              onTap: () => onTarget(d),
            ),
        ]),
        const SizedBox(height: 12),

        // Status row
        Row(children: [
          _StatusDot(status: conn.connectionStatus),
          const SizedBox(width: 8),
          Text(conn.connectionStatus.label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const Spacer(),
          if (conn.lastCheckedAt != null)
            Text(
              'Last checked: ${_timeLabel(conn.lastCheckedAt!)}',
              style: proSubtitle(size: 9),
            ),
        ]),
        const SizedBox(height: 10),

        // Check connection button
        GestureDetector(
          onTap: onCheck,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.refresh_outlined, size: 13, color: Colors.white38),
              const SizedBox(width: 6),
              Text('Check Connection Placeholder',
                  style: proLabel(size: 10, color: Colors.white38, spacing: 0)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Text('Simulated status only. No real hardware scan.',
            style: proSubtitle(size: 9)),
      ]),
    );
  }

  String _timeLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}

class _StatusDot extends StatelessWidget {
  final HardwareConnectionStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      HardwareConnectionStatus.connected  => kProGreen,
      HardwareConnectionStatus.simulated  => const Color(0xFF4A9EFF),
      HardwareConnectionStatus.detected   => const Color(0xFF4A9EFF),
      HardwareConnectionStatus.error      => const Color(0xFFEF4444),
      HardwareConnectionStatus.unauthorized => kProAmber,
      HardwareConnectionStatus.driverMissing => kProAmber,
      _                                   => Colors.white24,
    };
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? kProAccent.withValues(alpha: 0.12) : kProSurface,
        border: Border.all(
            color: selected
                ? kProAccent.withValues(alpha: 0.5)
                : kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: selected ? kProAccent : Colors.white38)),
    ),
  );
}
