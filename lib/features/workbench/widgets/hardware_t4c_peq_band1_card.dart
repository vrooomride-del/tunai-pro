// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-1F).
//
// UI extraction only: this is the same widget that lived as the private
// `_T4cPeqBand1Panel` class inside hardware_tab.dart, moved verbatim
// (renamed to a public class so it can be imported) with no change to the
// Band 1 filter query, the "requires SafeLoad validation" hard-block
// messaging, or the coefficient label preview. It does not touch PEQ logic,
// DSP mapping, the address registry, any executor, or providers/
// controllers. MvpPanelContainer and MvpAddressRow are shared with the
// other T4C dry-run cards via hardware_t4c_shared.dart (Phase 3-C-3D)
// rather than duplicated here. `_coeffLabels` is private to this widget
// alone (no other site referenced it), so it moved along unchanged.

import 'package:flutter/material.dart';

import '../../../core/pro_dsp_address_registry.dart';
import '../../../shared/pro_widgets.dart';
import 'hardware_t4c_shared.dart' show MvpPanelContainer, MvpAddressRow;

class HardwareT4cPeqBand1Card extends StatelessWidget {
  const HardwareT4cPeqBand1Card({super.key});

  static const _coeffLabels = ['b0', 'b1', 'b2', 'a1', 'a2'];

  @override
  Widget build(BuildContext context) {
    final allPeq = DspAddressRegistry.createDefault()
        .addressesForKind(DspParameterKind.peq);
    final band1 = allPeq
        .where((a) =>
            a.bandOrStage == '1' ||
            a.id.contains('band1') ||
            a.id.contains('peq_1'))
        .toList();

    return MvpPanelContainer(
      icon:       Icons.graphic_eq_outlined,
      title:      'USBi Temporary PEQ Band 1 Validation — Dry Run Only',
      badgeLabel: 'DRY RUN ONLY',
      badgeColor: Colors.blueAccent,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.05),
            border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.block_outlined, color: Colors.redAccent, size: 12),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'PEQ coefficient write requires SafeLoad validation first. '
                'No PEQ write today.',
                style: TextStyle(fontSize: 9, color: Colors.redAccent),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text('PEQ Band 1 coefficient group (preview only):',
            style: proLabel(size: 9)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _coeffLabels
              .map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kProPanel,
                      border: Border.all(color: kProBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(c,
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white38,
                            fontFamily: 'monospace')),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        if (band1.isEmpty)
          Text(
            'No PEQ Band 1 addresses in registry. '
            'Address confirmation required.',
            style: proSubtitle(size: 10),
          )
        else
          ...band1.map((a) => MvpAddressRow(addr: a, dryRunOnly: true)),
      ]),
    );
  }
}
