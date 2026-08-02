// TUNAI PRO UI v2 — Hardware Tab structure cleanup (Phase 3-C-3D).
//
// Shared display helpers used by the T4C dry-run/guarded validation cards
// and the Transport Command Preview card. Moved verbatim out of
// hardware_tab.dart (where they previously lived as public classes so the
// already-extracted widget files could import them back) into this
// dedicated shared file, so that widgets/ no longer needs to import
// tabs/hardware_tab.dart. No class name, constructor, field, build
// structure, UI text, color, spacing, or condition was changed — this is a
// pure file-location move.

import 'package:flutter/material.dart';

import '../../../core/pro_dsp_address_registry.dart';
import '../../../core/pro_usbi_executor_data.dart';
import '../../../shared/pro_widgets.dart';

class CmdRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const CmdRow(this.label, this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 140,
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ),
      Expanded(
        child: Text(value,
            style: TextStyle(
                fontSize: 9,
                color: color ?? Colors.white60,
                fontFamily: 'monospace',
                fontWeight: color != null ? FontWeight.w500 : FontWeight.normal)),
      ),
    ]),
  );
}

class MvpAddressRow extends StatelessWidget {
  final VerifiedDspAddress addr;
  final bool dryRunOnly;
  final bool blocked;

  const MvpAddressRow({
    required this.addr,
    this.dryRunOnly = false,
    this.blocked    = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: kProPanel,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(addr.logicalName, style: proTitle(size: 10)),
              Text(
                '${addr.addressHex} · ${addr.verificationStatus.label}',
                style: proLabel(size: 8, color: Colors.white38),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: blocked
                  ? Colors.red.withValues(alpha: 0.1)
                  : kProAmber.withValues(alpha: 0.08),
              border: Border.all(
                  color: blocked
                      ? Colors.red.withValues(alpha: 0.3)
                      : kProAmber.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              blocked ? 'BLOCKED' : 'DRY RUN',
              style: TextStyle(
                  fontSize: 7,
                  color: blocked ? Colors.redAccent : kProAmber,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
}

class MvpPanelContainer extends StatelessWidget {
  final IconData icon;
  final String title;
  final String badgeLabel;
  final Color badgeColor;
  final Widget body;
  final Color? borderColor;

  const MvpPanelContainer({
    required this.icon,
    required this.title,
    required this.badgeLabel,
    required this.badgeColor,
    required this.body,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: borderColor ?? kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: (borderColor ?? kProBorder).withValues(alpha: 0.5),
                      width: 0.5)),
            ),
            child: Row(children: [
              Icon(icon, color: badgeColor, size: 13),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: proTitle(size: 12))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(badgeLabel,
                    style: TextStyle(
                        fontSize: 8,
                        color: badgeColor,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(14), child: body),
        ]),
      );
}

class T4cResultLog extends StatelessWidget {
  final UsbiExecutionResult result;
  const T4cResultLog({required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = result.status == UsbiExecutionStatus.ackReceived;
    final color = ok
        ? Colors.greenAccent
        : result.status == UsbiExecutionStatus.ackFailed
            ? Colors.orange
            : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Result: ${result.status.label}',
            style: TextStyle(
                fontSize: 9, color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        CmdRow('wasActualWrite', result.wasActualWrite.toString(),
            color: result.wasActualWrite ? Colors.greenAccent : null),
        CmdRow('ackReceived', result.ackReceived.toString()),
        if (result.ackByteHex != null)
          CmdRow('ACK bytes', result.ackByteHex!),
        if (result.error != null)
          CmdRow('Error', result.error!, color: Colors.redAccent),
      ]),
    );
  }
}
