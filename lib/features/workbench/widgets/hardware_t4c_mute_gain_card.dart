// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-1D).
//
// UI extraction only: this is the same widget that lived as the private
// `_T4cMuteGainPanel` class inside hardware_tab.dart, moved verbatim (renamed
// to a public class so it can be imported) with no change to the guarded
// mute/gain validation logic, data flow, or callback signatures. Execution
// still only happens when: address is in the registry, value format is
// confirmed, device is open, and the user has confirmed — no automatic
// write, no liveWriteVerified promotion. MvpPanelContainer and T4cResultLog
// are shared with the other T4C cards via hardware_t4c_shared.dart
// (Phase 3-C-3D) rather than duplicated here.

import 'package:flutter/material.dart';

import '../../../core/pro_dsp_address_registry.dart';
import '../../../core/pro_usbi_executor_data.dart';
import '../../../shared/pro_widgets.dart';
import 'hardware_t4c_shared.dart' show MvpPanelContainer, T4cResultLog;

class HardwareT4cMuteGainCard extends StatelessWidget {
  final VerifiedDspAddress? selected;
  final bool deviceOpen;
  final bool confirmed;
  final bool executing;
  final UsbiExecutionResult? lastResult;
  final ValueChanged<VerifiedDspAddress?> onSelect;
  final ValueChanged<bool> onConfirmChanged;
  final VoidCallback onExecute;

  const HardwareT4cMuteGainCard({
    super.key,
    required this.selected,
    required this.deviceOpen,
    required this.confirmed,
    required this.executing,
    required this.lastResult,
    required this.onSelect,
    required this.onConfirmChanged,
    required this.onExecute,
  });

  @override
  Widget build(BuildContext context) {
    final registry = DspAddressRegistry.createDefault();
    final entries = [
      ...registry.addressesForKind(DspParameterKind.mute),
      ...registry.addressesForKind(DspParameterKind.gain),
    ];

    final bool hasValueFormat  = selected?.dataFormat != null;
    final bool isEligible      = selected?.isActualWriteEligible ?? false;
    final bool canExecute      = deviceOpen && confirmed && !executing &&
        selected != null && isEligible && hasValueFormat;

    return MvpPanelContainer(
      icon:       Icons.tune_outlined,
      title:      'USBi Temporary Mute/Gain Validation',
      badgeLabel: 'GUARDED',
      badgeColor: kProAmber,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (entries.isEmpty) ...[
          Row(children: [
            const Icon(Icons.info_outline, color: Colors.white24, size: 12),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No Mute/Gain addresses in registry. '
                'Address confirmation required before validation.',
                style: proSubtitle(size: 10),
              ),
            ),
          ]),
        ] else ...[
          Text('Select parameter:', style: proLabel(size: 9)),
          const SizedBox(height: 6),
          ...entries.map((addr) {
            final valueKnown = addr.dataFormat != null;
            final isSel      = selected?.id == addr.id;
            return GestureDetector(
              onTap: () => onSelect(addr),
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSel
                      ? kProAccent.withValues(alpha: 0.1)
                      : kProPanel,
                  border: Border.all(
                      color: isSel
                          ? kProAccent.withValues(alpha: 0.4)
                          : kProBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(addr.logicalName, style: proTitle(size: 11)),
                  Text(
                    '${addr.addressHex} · ${addr.verificationStatus.label}',
                    style: proLabel(size: 9, color: Colors.white38),
                  ),
                  if (!valueKnown)
                    const Text(
                      'blocked: value format requires confirmation',
                      style: TextStyle(fontSize: 9, color: kProAmber),
                    ),
                  if (valueKnown)
                    Text('format: ${addr.dataFormat}',
                        style: const TextStyle(
                            fontSize: 9, color: Colors.greenAccent)),
                ]),
              ),
            );
          }),

          if (selected != null) ...[
            const SizedBox(height: 10),
            if (!hasValueFormat)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kProAmber.withValues(alpha: 0.06),
                  border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Execution blocked: value format not confirmed for '
                  '${selected!.logicalName}.',
                  style: const TextStyle(fontSize: 9, color: kProAmber),
                ),
              )
            else if (!isEligible)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kProAmber.withValues(alpha: 0.06),
                  border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Execution blocked: ${selected!.logicalName} is not '
                  'live-write eligible (${selected!.verificationStatus.label}).',
                  style: const TextStyle(fontSize: 9, color: kProAmber),
                ),
              )
            else ...[
              Row(children: [
                Checkbox(
                  value: confirmed,
                  onChanged: deviceOpen
                      ? (v) => onConfirmChanged(v ?? false)
                      : null,
                  side: const BorderSide(color: Colors.white38),
                  activeColor: kProAccent,
                ),
                Expanded(
                  child: Text(
                    'I confirm this is a single-parameter Mute/Gain write. '
                    'No EEPROM. No Selfboot. No PEQ/XO/Delay/SafeLoad.',
                    style: proSubtitle(size: 9),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: canExecute ? onExecute : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: canExecute
                        ? kProAccent.withValues(alpha: 0.1)
                        : kProPanel,
                    border: Border.all(
                        color: canExecute
                            ? kProAccent.withValues(alpha: 0.4)
                            : kProBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    executing
                        ? 'Executing...'
                        : !deviceOpen
                            ? 'Device not open — connect USBi first'
                            : !confirmed
                                ? 'Check confirmation above'
                                : 'Execute Mute/Gain Write',
                    style: TextStyle(
                        fontSize: 11,
                        color: canExecute ? kProAccent : Colors.white24,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ],

          if (lastResult != null) ...[
            const SizedBox(height: 10),
            T4cResultLog(result: lastResult!),
          ],
        ],
      ]),
    );
  }
}
