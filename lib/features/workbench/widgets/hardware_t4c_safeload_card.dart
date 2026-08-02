// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-1H).
//
// UI extraction only: this is the same widget that lived as the private
// `_T4cSafeloadPanel` class inside hardware_tab.dart, moved verbatim
// (renamed to a public class so it can be imported) with no change to the
// dry-run registry lookup, the planned address preview, or the "no
// SafeLoad execution today" messaging. It does not touch SafeLoad logic,
// DSP write behavior, any executor, ACK handling, or providers/
// controllers/BLE/transport. `_plannedAddresses` is private to this widget
// alone (no other site referenced it), so it moved along unchanged.
//
// MvpPanelContainer and MvpAddressRow are shared with the other T4C
// dry-run cards via hardware_t4c_shared.dart (Phase 3-C-3D) rather than
// duplicated here — this file no longer imports tabs/hardware_tab.dart.

import 'package:flutter/material.dart';

import '../../../core/pro_dsp_address_registry.dart';
import '../../../shared/pro_widgets.dart';
import 'hardware_t4c_shared.dart' show MvpPanelContainer, MvpAddressRow;

class HardwareT4cSafeloadCard extends StatelessWidget {
  const HardwareT4cSafeloadCard({super.key});

  static const _plannedAddresses = [
    '0x6000', '0x6001', '0x6002', '0x6003',
    '0x6004', '0x6005', '0x6006', '0x6007',
  ];

  @override
  Widget build(BuildContext context) {
    final entries = DspAddressRegistry.createDefault()
        .addressesForKind(DspParameterKind.safeload);

    return MvpPanelContainer(
      icon:       Icons.save_outlined,
      title:      'SafeLoad Validation — Dry Run Only',
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
                'SafeLoad must be validated before PEQ/XO live coefficient write. '
                'No SafeLoad execution today.',
                style: TextStyle(fontSize: 9, color: kProAmber),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text('Planned SafeLoad address sequence (preview only):',
            style: proLabel(size: 9)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _plannedAddresses
              .map((hex) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kProPanel,
                      border: Border.all(color: kProBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(hex,
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white38,
                            fontFamily: 'monospace')),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            'No SafeLoad addresses in registry. '
            'Address confirmation required before live SafeLoad.',
            style: proSubtitle(size: 10),
          )
        else
          ...entries.map((a) => MvpAddressRow(addr: a, dryRunOnly: true)),
      ]),
    );
  }
}
