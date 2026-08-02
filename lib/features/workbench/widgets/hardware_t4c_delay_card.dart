// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-1E).
//
// UI extraction only: this is the same widget that lived as the private
// `_T4cDelayPanel` class inside hardware_tab.dart, moved verbatim (renamed
// to a public class so it can be imported) with no change to the dry-run
// registry lookup or the "actual write disabled" messaging. It does not
// touch Delay verification logic, DSP delay address mapping, any executor,
// ACK/transport handling, or providers/controllers. MvpPanelContainer and
// MvpAddressRow are shared with the other T4C dry-run cards via
// hardware_t4c_shared.dart (Phase 3-C-3D) rather than duplicated here.

import 'package:flutter/material.dart';

import '../../../core/pro_dsp_address_registry.dart';
import '../../../shared/pro_widgets.dart';
import 'hardware_t4c_shared.dart' show MvpPanelContainer, MvpAddressRow;

class HardwareT4cDelayCard extends StatelessWidget {
  const HardwareT4cDelayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = DspAddressRegistry.createDefault()
        .addressesForKind(DspParameterKind.delay);

    return MvpPanelContainer(
      icon:       Icons.access_time_outlined,
      title:      'USBi Temporary Delay Validation — Dry Run Only',
      badgeLabel: 'DRY RUN ONLY',
      badgeColor: Colors.blueAccent,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.06),
            border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Delay requires oscilloscope or interface timing measurement. '
                'Actual write disabled today.',
                style: TextStyle(fontSize: 9, color: kProAmber),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Text(
            'No Delay addresses in registry. '
            'Address confirmation required before validation.',
            style: proSubtitle(size: 10),
          )
        else
          ...entries.map((a) => MvpAddressRow(addr: a, dryRunOnly: true)),
      ]),
    );
  }
}
