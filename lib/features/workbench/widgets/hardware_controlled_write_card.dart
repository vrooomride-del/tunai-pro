// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-3A).
//
// UI extraction only: this is the same widget bundle that lived as the
// private `_ControlledWritePanel` class (with its private `_VolumeRow`,
// `_DryRunPreviewPanel`, and `_WriteButton` helpers) inside hardware_tab.dart,
// moved verbatim with no change to the safety banner text, the L/R volume
// sliders, the dry-run preview table, the confirmation checkbox, the write
// button enabled condition, or the disabled-write footer text. This widget
// only receives already-computed values (leftVolume/rightVolume/
// dryRunRequests/userConfirmed/writing/lastLog) and calls the injected
// callbacks (onLeftChanged/onRightChanged/onGenerateDryRun/onConfirmChanged/
// onWrite) — it does not read any provider/ref/controller, does not call
// the USBi executor or any native backend, does not touch BLE/transport,
// does not look up DSP addresses, and does not build packets or perform
// fixed-point conversion. Master Volume computation, address mapping,
// dry-run/write/restore execution, and ACK handling all stay in
// hardware_tab.dart's `_HardwareTabState`.
//
// The one preserved reference, `ProUsbiTransport.isPlaceholder`, is a
// static const bool read (not a transport call) that was already part of
// the original `_canWrite` getter being moved verbatim — the button's
// enabled condition is preserved exactly as it was, per the "verbatim"
// requirement, and is not a new BLE/transport access.
//
// `HardwareWriteLogCard` continues to be reused exactly as before, imported
// from the already-extracted `hardware_write_log_card.dart` (not duplicated
// or reimplemented). `_VolumeRow`, `_DryRunPreviewPanel`, and `_WriteButton`
// stay private to this file — none are promoted to public.

import 'package:flutter/material.dart';

import '../../../core/pro_hardware_write_data.dart';
import '../../../core/pro_usbi_transport.dart';
import '../../../shared/pro_widgets.dart';
import 'hardware_write_log_card.dart';

class HardwareControlledWriteCard extends StatelessWidget {
  final double leftVolume;
  final double rightVolume;
  final List<HardwareWriteRequest>? dryRunRequests;
  final bool userConfirmed;
  final bool writing;
  final HardwareWriteLog? lastLog;
  final ValueChanged<double> onLeftChanged;
  final ValueChanged<double> onRightChanged;
  final VoidCallback onGenerateDryRun;
  final ValueChanged<bool> onConfirmChanged;
  final VoidCallback onWrite;

  const HardwareControlledWriteCard({
    super.key,
    required this.leftVolume,
    required this.rightVolume,
    required this.dryRunRequests,
    required this.userConfirmed,
    required this.writing,
    required this.lastLog,
    required this.onLeftChanged,
    required this.onRightChanged,
    required this.onGenerateDryRun,
    required this.onConfirmChanged,
    required this.onWrite,
  });

  bool get _canWrite =>
      dryRunRequests != null &&
      userConfirmed &&
      !writing &&
      !ProUsbiTransport.isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Safety banner
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.07),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_outlined, color: Color(0xFFEF4444), size: 13),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Experimental volatile write. ADAU1466 Master Volume only.\n'
              'Only addresses 0x67 (L) and 0x64 (R) are allowed. '
              'No EEPROM. No Selfboot. No SafeLoad. No Write-All.\n'
              'USBi write backend is not enabled in Phase T2. '
              'Detection does not imply write permission. '
              'Actual write remains disabled.',
              style: TextStyle(fontSize: 9, color: Color(0xFFEF4444), height: 1.5),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // Volume sliders
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('VOLUME TARGET (0.0 – 1.0)', style: proLabel(size: 9, spacing: 1.8)),
          const SizedBox(height: 12),
          _VolumeRow(
            label: 'Master Volume L  (0x67)',
            value: leftVolume,
            onChanged: onLeftChanged,
          ),
          const SizedBox(height: 8),
          _VolumeRow(
            label: 'Master Volume R  (0x64)',
            value: rightVolume,
            onChanged: onRightChanged,
          ),
        ]),
      ),
      const SizedBox(height: 10),

      // Generate Dry Run button
      GestureDetector(
        onTap: onGenerateDryRun,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: kProAccent.withValues(alpha: 0.08),
            border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.preview_outlined, size: 14, color: kProAccent),
            SizedBox(width: 8),
            Text('Generate Dry Run',
                style: TextStyle(fontSize: 12, color: kProAccent,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
      const SizedBox(height: 10),

      // Dry-run request preview
      if (dryRunRequests != null) ...[
        _DryRunPreviewPanel(requests: dryRunRequests!),
        const SizedBox(height: 12),

        // Confirmation checkbox
        GestureDetector(
          onTap: () => onConfirmChanged(!userConfirmed),
          child: Row(children: [
            Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: userConfirmed
                    ? kProAccent.withValues(alpha: 0.2)
                    : kProSurface,
                border: Border.all(
                    color: userConfirmed ? kProAccent : kProBorder),
                borderRadius: BorderRadius.circular(3),
              ),
              child: userConfirmed
                  ? const Icon(Icons.check, size: 11, color: kProAccent)
                  : null,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'I understand this is a volatile ADAU1466 Master Volume write only. '
                'No EEPROM. No Selfboot. No SafeLoad. No other registers.',
                style: TextStyle(fontSize: 10, color: Colors.white60, height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // Write button
        _WriteButton(
          canWrite:  _canWrite,
          writing:   writing,
          onWrite:   onWrite,
        ),
        const SizedBox(height: 6),
        const Text(
          'Write disabled — USBi write backend is not enabled in Phase T2. '
          'Detection does not imply write permission. '
          'Actual write remains disabled.',
          style: TextStyle(fontSize: 9, color: Colors.white38, height: 1.4),
        ),
        const SizedBox(height: 12),
      ],

      // Write log
      if (lastLog != null) ...[
        HardwareWriteLogCard(log: lastLog!),
      ],
    ]);
  }
}

class _VolumeRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _VolumeRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(
      width: 190,
      child: Text(label,
          style: const TextStyle(fontSize: 10, color: Colors.white60,
              fontFamily: 'monospace')),
    ),
    Expanded(
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: kProAccent.withValues(alpha: 0.7),
          inactiveTrackColor: kProBorder,
          thumbColor: kProAccent,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          trackHeight: 2,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        ),
        child: Slider(
          value: value,
          min: 0.0, max: 1.0,
          divisions: 100,
          onChanged: onChanged,
        ),
      ),
    ),
    SizedBox(
      width: 42,
      child: Text(value.toStringAsFixed(2),
          style: const TextStyle(fontSize: 10, color: Colors.white70,
              fontFamily: 'monospace'),
          textAlign: TextAlign.right),
    ),
  ]);
}

class _DryRunPreviewPanel extends StatelessWidget {
  final List<HardwareWriteRequest> requests;
  const _DryRunPreviewPanel({required this.requests});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: kProAccent.withValues(alpha: 0.10),
            border: Border.all(color: kProAccent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text('DRY RUN',
              style: TextStyle(fontSize: 8, color: kProAccent,
                  fontWeight: FontWeight.w600, letterSpacing: 0.6)),
        ),
        const SizedBox(width: 8),
        Text('${requests.length} write requests',
            style: proSubtitle(size: 9)),
      ]),
      const SizedBox(height: 10),
      // Header row
      Row(children: [
        Expanded(flex: 3, child: Text('TARGET', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
        SizedBox(width: 56, child: Text('ADDRESS', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
        SizedBox(width: 36, child: Text('VALUE', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
        SizedBox(width: 88, child: Text('FIXED-POINT HEX', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
      ]),
      const SizedBox(height: 6),
      const Divider(color: kProBorder, height: 1),
      const SizedBox(height: 4),
      ...requests.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Text(r.target.label,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 56,
            child: Text(r.addressHex,
                style: const TextStyle(fontSize: 10, color: Color(0xFF4A9EFF),
                    fontFamily: 'monospace')),
          ),
          SizedBox(
            width: 36,
            child: Text(r.valueDouble.toStringAsFixed(2),
                style: const TextStyle(fontSize: 10, color: Colors.white54,
                    fontFamily: 'monospace')),
          ),
          SizedBox(
            width: 88,
            child: Text(r.fixedPointHex,
                style: const TextStyle(fontSize: 10, color: Colors.white38,
                    fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      )),
    ]),
  );
}

class _WriteButton extends StatelessWidget {
  final bool canWrite;
  final bool writing;
  final VoidCallback onWrite;
  const _WriteButton({
    required this.canWrite,
    required this.writing,
    required this.onWrite,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: canWrite ? onWrite : null,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: canWrite
            ? const Color(0xFFEF4444).withValues(alpha: 0.12)
            : kProSurface,
        border: Border.all(
          color: canWrite
              ? const Color(0xFFEF4444).withValues(alpha: 0.5)
              : kProBorder,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          writing
              ? Icons.hourglass_empty_outlined
              : Icons.send_outlined,
          size: 14,
          color: canWrite
              ? const Color(0xFFEF4444)
              : Colors.white24,
        ),
        const SizedBox(width: 8),
        Text(
          writing
              ? 'Writing…'
              : 'Write Master Volume',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: canWrite
                ? const Color(0xFFEF4444)
                : Colors.white24,
          ),
        ),
      ]),
    ),
  );
}
