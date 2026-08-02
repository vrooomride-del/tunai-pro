// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-1A).
//
// UI extraction only: this is the same widget that lived as the private
// `_WriteLogPanel` class inside hardware_tab.dart, moved verbatim (renamed
// to a public class so it can be imported) with no changes to the state it
// reads or how it's invoked. It is a pure display of an already-completed
// HardwareWriteLog entry — it does not touch BLE, ICP5, any transport,
// the DSP write executor, providers, HardwareConnection, or deploy logic.

import 'package:flutter/material.dart';

import '../../../core/pro_hardware_write_data.dart';
import '../../../shared/pro_widgets.dart';
import '../../../shared/components/info_row.dart';

class HardwareWriteLogCard extends StatelessWidget {
  final HardwareWriteLog log;
  const HardwareWriteLogCard({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final result = log.result;
    final status = result?.status ?? HardwareWriteStatus.notStarted;
    final statusColor = switch (status) {
      HardwareWriteStatus.success => kProGreen,
      HardwareWriteStatus.failed => const Color(0xFFEF4444),
      HardwareWriteStatus.blocked => kProAmber,
      _ => Colors.white38,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('WRITE LOG', style: proLabel(size: 9, spacing: 1.8)),
        const SizedBox(height: 10),
        ProInfoRow(label: 'Log ID', value: log.id),
        ProInfoRow(label: 'Status', value: status.label),
        ProInfoRow(
            label: 'Timestamp',
            value: log.createdAt.toIso8601String().substring(0, 19)),
        ProInfoRow(
            label: 'User Confirmed', value: log.userConfirmed ? 'Yes' : 'No'),
        ProInfoRow(
            label: 'Actual Write',
            value: result?.wasActualWrite == true ? 'Yes' : 'No'),
        if (result?.errorMessage != null)
          ProInfoRow(label: 'Error', value: result!.errorMessage!),
        const SizedBox(height: 8),
        Row(children: [
          const Text('STATUS  ',
              style: TextStyle(
                  fontSize: 9, color: Colors.white38, letterSpacing: 1)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(status.label,
                style: TextStyle(
                    fontSize: 9,
                    color: statusColor,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          result?.safetyNote ?? 'No write occurred.',
          style: proSubtitle(size: 9, color: Colors.white24),
        ),
        if (log.sessionNote.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(log.sessionNote, style: proSubtitle(size: 9)),
        ],
      ]),
    );
  }
}
