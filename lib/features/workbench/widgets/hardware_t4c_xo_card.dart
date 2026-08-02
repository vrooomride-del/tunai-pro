// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-1G).
//
// UI extraction only: this is the same widget that lived as the private
// `_T4cXoPanel` class inside hardware_tab.dart, moved verbatim (renamed to
// a public class so it can be imported) with no change to the hard-blocked
// state. XO write stays hard-blocked here exactly as before: no XO
// execution, no SafeLoad, no speaker-connected testing — the three warning
// rows and the `blocked: true` MvpAddressRow flag are unchanged. This file
// does not touch XO logic, the blocked condition itself, DSP mapping,
// filter order, any executor, or providers/controllers/BLE/transport.
// MvpPanelContainer and MvpAddressRow are shared with the other T4C
// dry-run cards via hardware_t4c_shared.dart (Phase 3-C-3D) rather than
// duplicated here.

import 'package:flutter/material.dart';

import '../../../core/pro_dsp_address_registry.dart';
import '../../../shared/pro_widgets.dart';
import 'hardware_t4c_shared.dart' show MvpPanelContainer, MvpAddressRow;

class HardwareT4cXoCard extends StatelessWidget {
  const HardwareT4cXoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = DspAddressRegistry.createDefault()
        .addressesForKind(DspParameterKind.crossover);

    return MvpPanelContainer(
      icon:        Icons.device_hub_outlined,
      title:       'USBi Temporary XO Validation — BLOCKED',
      badgeLabel:  'BLOCKED',
      badgeColor:  Colors.redAccent,
      borderColor: Colors.red.withValues(alpha: 0.35),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.06),
            border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.block_outlined, color: Colors.redAccent, size: 12),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'XO write is hard-blocked. No XO execution. No SafeLoad. '
                  'No speaker-connected testing. No tweeter-risk path.',
                  style: TextStyle(fontSize: 9, color: Colors.redAccent),
                ),
              ),
            ]),
            SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'OUT1/2/3/4/7/8 output mapping must be verified without speakers first.',
                  style: TextStyle(fontSize: 9, color: kProAmber),
                ),
              ),
            ]),
            SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'BLOCKED UNTIL: SafeLoad validated + output mapping verified.',
                  style: TextStyle(fontSize: 9, color: kProAmber),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Text(
            'No XO addresses in registry.',
            style: proSubtitle(size: 10),
          )
        else
          ...entries.map(
              (a) => MvpAddressRow(addr: a, dryRunOnly: true, blocked: true)),
      ]),
    );
  }
}
