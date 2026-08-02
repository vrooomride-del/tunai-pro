// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-2F).
//
// UI extraction only: this is the same widget that lived as the private
// `_AddressValidationStatusPanel` class (with its private `_HwStatusRow`
// row helper) inside hardware_tab.dart, moved verbatim with no change to
// the `createTunaiAdau1466ThreeWayRegistry()` read-only call, the
// `countByKind`/`peqRowCount` count calculations, the row order/labels, the
// eligible/status/detail wording, or the closing guard-note text. This
// file does not touch the address registry definition or factory, address
// validation policy, DSP address mapping, SigmaStudio mapping, providers,
// controllers, executors, BLE/transport, deploy, or guard logic — it only
// displays counts that were already read-only in the original panel.
// `_HwStatusRow` stays private to this file — it is not promoted to public
// and not used anywhere else.

import 'package:flutter/material.dart';

import '../../../core/pro_dsp_address_registry.dart';
import '../../../core/pro_adau1466_3way_address_map_embedded.dart';
import '../../../shared/pro_widgets.dart';

class HardwareAddressValidationStatusCard extends StatelessWidget {
  const HardwareAddressValidationStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = createTunaiAdau1466ThreeWayRegistry();
    final muteCount    = registry.countByKind(DspParameterKind.mute);
    final gainCount    = registry.countByKind(DspParameterKind.gain);
    final delayCount   = registry.countByKind(DspParameterKind.delay);
    final xoCount      = registry.countByKind(DspParameterKind.crossover);
    final safeloadCount = registry.countByKind(DspParameterKind.safeload);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _HwStatusRow(
          label: 'Master Volume L/R',
          status: 'PASS_ACK',
          eligible: true,
          detail: '0x0067 / 0x0064 — audible verification pending',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'SafeLoad ($safeloadCount registers)',
          status: 'Export Confirmed',
          eligible: false,
          detail: '0x6000–0x6007 — needs live validation',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'Mute ($muteCount channels)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Blocked for actual write until capture',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'Gain / Driver ($gainCount)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Blocked for actual write until capture',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'Delay ($delayCount channels)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Blocked for actual write until capture',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'XO — HPF + LPF ($xoCount coefficients)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Safeload candidate — needs validation',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'PEQ Coefficients (${registry.peqRowCount} rows)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Safeload candidate — blocked until XO validated',
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.07),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'Export-confirmed address requires live validation before hardware write. '
            'Only Verified addresses pass actual write guard.',
            style: proSubtitle(size: 9),
          ),
        ),
      ]),
    );
  }
}

class _HwStatusRow extends StatelessWidget {
  final String label;
  final String status;
  final bool eligible;
  final String detail;
  const _HwStatusRow({
    required this.label,
    required this.status,
    required this.eligible,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final color = eligible ? Colors.greenAccent : Colors.orange;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(eligible ? Icons.check_circle_outline : Icons.info_outline,
          size: 12, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: proSubtitle(size: 10))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(status, style: TextStyle(fontSize: 8, color: color)),
            ),
          ]),
          Text(detail, style: proSubtitle(size: 9)),
        ]),
      ),
    ]);
  }
}
