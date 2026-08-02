// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-3C, part B).
//
// UI extraction only: this is the same widget bundle that lived as the
// private `_TransportCommandPreviewPanel` class (with its private
// `_CommandEnvelopeCard` helper) inside hardware_tab.dart, moved verbatim
// with no change to the transport/channel/preset selectors, the "Generate
// Dry-Run Command" button (still no Send/Execute button), or the envelope
// preview rows. This widget only receives an already-computed
// `TransportCommandEnvelope?` plus selection state and calls the injected
// callbacks (onSideChanged/onValueChanged/onGenerate) — it does not
// generate commands, compute payload/address/fixed-point values, call any
// executor, or touch BLE/USBi/transport. All of that stays in
// hardware_tab.dart's `_HardwareTabState` (`_generateTransportCommand`).
// `_CommandEnvelopeCard` stays private to this file — it is not promoted
// to public.
//
// `CmdRow` is shared with the T4C cards via hardware_t4c_shared.dart
// (Phase 3-C-3D) rather than duplicated here.

import 'package:flutter/material.dart';

import '../../../core/pro_hardware_transport.dart';
import '../../../core/pro_transport_command_data.dart';
import '../../../shared/pro_widgets.dart';
import 'hardware_t4c_shared.dart' show CmdRow;

class HardwareTransportCommandPreviewCard extends StatelessWidget {
  final HardwareTransportBackend selectedBackend;
  final String commandSide;
  final double commandValue;
  final TransportCommandEnvelope? envelope;
  final void Function(String) onSideChanged;
  final void Function(double) onValueChanged;
  final VoidCallback onGenerate;

  const HardwareTransportCommandPreviewCard({
    super.key,
    required this.selectedBackend,
    required this.commandSide,
    required this.commandValue,
    required this.envelope,
    required this.onSideChanged,
    required this.onValueChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Transport context pill
      Row(children: [
        const Icon(Icons.compare_arrows_outlined, size: 11, color: Colors.white38),
        const SizedBox(width: 5),
        Text('Transport: ', style: proSubtitle(size: 9)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: kProAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(selectedBackend.label,
              style: const TextStyle(fontSize: 9, color: kProAccent,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
      const SizedBox(height: 12),

      // L / R selector
      Row(children: [
        Text('Channel: ', style: proSubtitle(size: 9)),
        const SizedBox(width: 8),
        for (final side in ['L', 'R']) ...[
          GestureDetector(
            onTap: () => onSideChanged(side),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: commandSide == side
                    ? kProAccent.withValues(alpha: 0.12)
                    : kProSurface,
                border: Border.all(
                    color: commandSide == side
                        ? kProAccent.withValues(alpha: 0.5)
                        : kProBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                side == 'L' ? 'L  0x0067' : 'R  0x0064',
                style: TextStyle(
                    fontSize: 10,
                    color: commandSide == side ? kProAccent : Colors.white38,
                    fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 12),

      // Value presets
      Row(children: [
        Text('Preset: ', style: proSubtitle(size: 9)),
        const SizedBox(width: 8),
        for (final preset in [
          (label: '1.0  Unity', value: 1.0),
          (label: '0.5  −6 dB', value: 0.5),
          (label: '0.0  Mute', value: 0.0),
        ]) ...[
          GestureDetector(
            onTap: () => onValueChanged(preset.value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: (commandValue - preset.value).abs() < 0.001
                    ? kProAccent.withValues(alpha: 0.1)
                    : kProSurface,
                border: Border.all(
                    color: (commandValue - preset.value).abs() < 0.001
                        ? kProAccent.withValues(alpha: 0.4)
                        : kProBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(preset.label,
                  style: TextStyle(
                      fontSize: 9,
                      color: (commandValue - preset.value).abs() < 0.001
                          ? kProAccent
                          : Colors.white38,
                      fontFamily: 'monospace')),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      Text('Value: ${commandValue.toStringAsFixed(3)}',
          style: proSubtitle(size: 9)),
      const SizedBox(height: 12),

      // Generate button — NO send/execute button
      GestureDetector(
        onTap: onGenerate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: kProAccent.withValues(alpha: 0.08),
            border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.preview_outlined, size: 13, color: kProAccent),
            const SizedBox(width: 7),
            const Text('Generate Dry-Run Command',
                style: TextStyle(fontSize: 11, color: kProAccent,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      Text('No Send button. No Execute button. No hardware write.',
          style: proSubtitle(size: 8)),

      // Envelope preview card
      if (envelope != null) ...[
        const SizedBox(height: 12),
        _CommandEnvelopeCard(envelope: envelope!),
      ],
    ]);
  }
}

class _CommandEnvelopeCard extends StatelessWidget {
  final TransportCommandEnvelope envelope;
  const _CommandEnvelopeCard({required this.envelope});

  Color get _statusColor => switch (envelope.status) {
    TransportCommandStatus.dryRunReady    => kProAccent,
    TransportCommandStatus.blocked        => Colors.redAccent,
    TransportCommandStatus.failed         => Colors.redAccent,
    TransportCommandStatus.transportDisabled => Colors.orange,
    _ => Colors.white38,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(
          color: envelope.status == TransportCommandStatus.blocked
              ? Colors.redAccent.withValues(alpha: 0.3)
              : kProAccent.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('COMMAND ENVELOPE', style: proLabel(size: 9, spacing: 1.5)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: 0.1),
            border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(envelope.status.label,
              style: TextStyle(fontSize: 8, color: _statusColor,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 8),
      CmdRow('Parameter',    envelope.logicalName),
      CmdRow('Address',      envelope.addressHex),
      CmdRow('Platform',     envelope.targetPlatform.label),
      CmdRow('Transport',    envelope.transportBackend.label),
      if (envelope.valueFloat != null)
        CmdRow('Float Value',  envelope.valueFloat!.toStringAsFixed(4)),
      if (envelope.fixedPointHex != null)
        CmdRow('Fixed 8.24',  envelope.fixedPointHex!),
      if (envelope.fixedPointInt != null)
        CmdRow('Fixed Int',   '${envelope.fixedPointInt}'),
      CmdRow('Byte Order',   envelope.byteOrder),
      CmdRow('Write Mode',   envelope.writeMode.label),
      CmdRow('actualWriteAllowed', '${envelope.actualWriteAllowed}',
          color: Colors.orange),
      CmdRow('isExecutableNow', '${envelope.isExecutableNow}',
          color: Colors.orange),
      CmdRow('isDryRunOnly', '${envelope.isDryRunOnly}',
          color: Colors.greenAccent),
      CmdRow('isMasterVolume', '${envelope.isMasterVolumeCommand}',
          color: envelope.isMasterVolumeCommand ? Colors.greenAccent : Colors.redAccent),
      if (envelope.blockedReason != null) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.07),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text('BLOCKED: ${envelope.blockedReason}',
              style: const TextStyle(fontSize: 9, color: Colors.redAccent)),
        ),
      ] else if (envelope.notes != null) ...[
        const SizedBox(height: 6),
        Text(envelope.notes!, style: proSubtitle(size: 8)),
      ],
    ]),
  );
}
