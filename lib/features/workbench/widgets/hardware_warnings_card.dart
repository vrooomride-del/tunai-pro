// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-1B).
//
// UI extraction only: this is the same widget that lived as the private
// `_WarningsPanel` class inside hardware_tab.dart, moved verbatim (renamed
// to a public class so it can be imported) with no changes to how the
// warning data is generated or passed in. It only displays the
// blockedReason/warnings already present on an existing HardwareWritePlan —
// it does not touch the safety validator, hardware state, DSP logic, BLE,
// or any transport.

import 'package:flutter/material.dart';

import '../../../core/pro_hardware_connection_data.dart';
import '../../../shared/pro_widgets.dart';

class HardwareWarningsCard extends StatelessWidget {
  final HardwareWritePlan plan;
  const HardwareWarningsCard({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProAmber.withValues(alpha: 0.04),
        border: Border.all(color: kProAmber.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (plan.blockedReason != null) ...[
          Row(children: [
            const Icon(Icons.block_outlined, size: 12, color: kProAmber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(plan.blockedReason!,
                  style: const TextStyle(
                      fontSize: 10,
                      color: kProAmber,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 6),
        ],
        ...plan.warnings.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(fontSize: 9, color: Colors.white38)),
                    Expanded(child: Text(w, style: proSubtitle(size: 9))),
                  ]),
            )),
      ]),
    );
  }
}
