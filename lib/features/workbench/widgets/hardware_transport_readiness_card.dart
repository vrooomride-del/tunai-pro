// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-3C, part A).
//
// UI extraction only: this is the same widget bundle that lived as the
// private `_TransportReadinessPanel` class (with its private
// `_TransportChip`, `_TransportDetailCard`, and `_TrRow` helpers) inside
// hardware_tab.dart, moved verbatim with no change to the transport chip
// list, the selected-detail card rows, the check/clear-selection buttons,
// or the global safety note. This widget is called from two places in
// hardware_tab.dart's `_HardwareTabState` (the main tab body and the
// alternate `_buildUsbiMasterVolumeHardwareTab()` view) — both call sites
// pass the same 8-parameter shape, only the last one supplying a non-default
// `realUsbiExecutorAvailable`. This widget only receives already-computed
// readiness state and calls the injected callbacks (onCheck/onSelect) — it
// does not read any provider/ref/controller, does not call any executor or
// native backend, does not touch BLE/USBi transport, and does not
// recompute readiness. All of that stays in hardware_tab.dart's
// `_HardwareTabState`. `_TransportChip`, `_TransportDetailCard`, and
// `_TrRow` stay private to this file — none are promoted to public.

import 'package:flutter/material.dart';

import '../../../core/pro_hardware_transport.dart';
import '../../../shared/pro_widgets.dart';

class HardwareTransportReadinessCard extends StatelessWidget {
  final HardwareTransportBackend selectedBackend;
  final List<HardwareTransportInfo> transportInfos;
  final bool checking;
  final String? checkMessage;
  final DateTime? lastChecked;
  final VoidCallback onCheck;
  final void Function(HardwareTransportBackend) onSelect;
  final bool realUsbiExecutorAvailable;

  const HardwareTransportReadinessCard({
    super.key,
    required this.selectedBackend,
    required this.transportInfos,
    required this.checking,
    required this.checkMessage,
    required this.lastChecked,
    required this.onCheck,
    required this.onSelect,
    this.realUsbiExecutorAvailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final selectedInfo = transportInfos
        .where((t) => t.backend == selectedBackend)
        .firstOrNull;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Transport selector chips
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final t in transportInfos)
          _TransportChip(
            info: t,
            isSelected: t.backend == selectedBackend,
            onTap: () => onSelect(t.backend),
          ),
      ]),
      const SizedBox(height: 12),

      // Selected transport detail card
      if (selectedInfo != null)
        _TransportDetailCard(
          info: selectedInfo,
          realUsbiExecutorAvailable: realUsbiExecutorAvailable,
        ),
      const SizedBox(height: 10),

      // Action row
      Row(children: [
        GestureDetector(
          onTap: checking ? null : onCheck,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: checking
                  ? kProSurface
                  : kProAccent.withValues(alpha: 0.08),
              border: Border.all(
                  color: checking
                      ? kProBorder
                      : kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                checking
                    ? Icons.hourglass_empty_outlined
                    : Icons.radar_outlined,
                size: 13,
                color: checking ? Colors.white24 : kProAccent,
              ),
              const SizedBox(width: 7),
              Text(
                checking ? 'Checking...' : 'Check Transport Readiness',
                style: TextStyle(
                  fontSize: 11,
                  color: checking ? Colors.white24 : kProAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => onSelect(HardwareTransportBackend.simulation),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Clear Selection',
                style: TextStyle(fontSize: 10, color: Colors.white38)),
          ),
        ),
      ]),

      // Check result message
      if (checkMessage != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(checkMessage!, style: proSubtitle(size: 9)),
        ),
      ],

      // Global safety note
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 11, color: Colors.white38),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              selectedBackend == HardwareTransportBackend.usbiWindowsTemporary
                  ? 'USBi Temporary executor available. '
                    'Master Volume L/R only. '
                    'All other writes remain blocked.'
                  : 'No transport backend is enabled for hardware write in this build. '
                    'Transport selection does not enable write. '
                    'Write capability remains: Dry-Run Only.',
              style: proSubtitle(size: 9),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _TransportChip extends StatelessWidget {
  final HardwareTransportInfo info;
  final bool isSelected;
  final VoidCallback onTap;
  const _TransportChip({
    required this.info,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isSelected ? kProAccent : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? kProAccent.withValues(alpha: 0.08)
              : kProSurface,
          border: Border.all(
              color: isSelected
                  ? kProAccent.withValues(alpha: 0.4)
                  : kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(info.displayName,
              style: TextStyle(
                  fontSize: 10, color: accent, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(info.platformHint,
              style: const TextStyle(fontSize: 8, color: Colors.white24)),
          if (info.backend.isTemporary)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('TEMPORARY',
                  style: TextStyle(
                      fontSize: 7,
                      color: Colors.orange.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
          if (info.backend.isFinalTarget)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('FINAL TARGET',
                  style: TextStyle(
                      fontSize: 7,
                      color: Colors.greenAccent.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
        ]),
      ),
    );
  }
}

class _TransportDetailCard extends StatelessWidget {
  final HardwareTransportInfo info;
  final bool realUsbiExecutorAvailable;
  const _TransportDetailCard({
    required this.info,
    this.realUsbiExecutorAvailable = false,
  });

  Color get _readinessColor => switch (info.readinessStatus) {
    TransportReadinessStatus.detected  => Colors.greenAccent,
    TransportReadinessStatus.connected => Colors.greenAccent,
    TransportReadinessStatus.detectionOnly => kProAccent,
    TransportReadinessStatus.placeholder   => Colors.white38,
    _ => info.readinessStatus.isWarning ? Colors.orange : Colors.white38,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProAccent.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(info.displayName,
            style: const TextStyle(fontSize: 11, color: Colors.white70,
                fontWeight: FontWeight.w500)),
        const Spacer(),
        // Write enabled: always false
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
              realUsbiExecutorAvailable ? 'MV WRITE ACTIVE' : 'WRITE DISABLED',
              style: TextStyle(fontSize: 7,
                  color: realUsbiExecutorAvailable ? kProAccent : Colors.orange,
                  fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ),
      ]),
      const SizedBox(height: 8),
      _TrRow('Backend',    info.backend.label),
      _TrRow('Platform', realUsbiExecutorAvailable ? 'Windows' : info.platformHint),
      _TrRow('Readiness', realUsbiExecutorAvailable
              ? 'Real executor available'
              : info.readinessStatus.label,
          color: _readinessColor),
      if (!realUsbiExecutorAvailable)
        _TrRow('Write Capability', info.writeCapability.label),
      _TrRow('Write Enabled',
          realUsbiExecutorAvailable
              ? 'MV L 0x0067 · MV R 0x0064'
              : info.backend == HardwareTransportBackend.usbiWindowsTemporary
              ? 'Temporary executor unavailable'
              : 'false — Write disabled'),
      if (realUsbiExecutorAvailable) ...[
        const _TrRow('Backend available', 'yes'),
        const _TrRow('Executor', 'real'),
      ] else ...[
        _TrRow('Placeholder', info.isPlaceholder ? 'Yes' : 'No'),
        _TrRow('Detection Only', info.isDetectionOnly ? 'Yes' : 'No'),
      ],
      if (info.backend == HardwareTransportBackend.usbiWindowsTemporary)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'USBi temporary engineering transport. '
              'Use only for controlled validation. '
              'Not the primary or final transport path.',
              style: TextStyle(fontSize: 9, color: Colors.orange),
            ),
          ),
        ),
      if (info.backend == HardwareTransportBackend.icp5)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.05),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'ICP5 is the final intended transport/programmer path. '
              'Packet format and protocol are TBD by hardware team.',
              style: TextStyle(fontSize: 9, color: Colors.greenAccent),
            ),
          ),
        ),
      if (info.backend == HardwareTransportBackend.bleMacos)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'macOS BLE transport planned. '
              'Detection/write backend not enabled in this build.',
              style: TextStyle(fontSize: 9, color: Colors.blueAccent),
            ),
          ),
        ),
      if (info.lastCheckedAt != null) ...[
        const SizedBox(height: 4),
        Text(
          'Last checked: '
          '${info.lastCheckedAt!.toLocal().toString().substring(0, 19)}',
          style: const TextStyle(fontSize: 8, color: Colors.white24),
        ),
      ],
    ]),
  );
}

class _TrRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _TrRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 110,
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ),
      Expanded(
        child: Text(value,
            style: TextStyle(
                fontSize: 9,
                color: color ?? Colors.white60,
                fontWeight:
                    color != null ? FontWeight.w500 : FontWeight.normal)),
      ),
    ]),
  );
}
