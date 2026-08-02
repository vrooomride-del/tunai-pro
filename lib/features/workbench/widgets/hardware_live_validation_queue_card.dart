// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-2E).
//
// UI extraction only: this is the same widget that lived as the private
// `_LiveValidationQueuePanel` class (with its private `_ValidationStep` row
// helper) inside hardware_tab.dart, moved verbatim with no change to the
// static step order/labels/notes, the "done" display styling, or the
// surrounding instructional text. `_ValidationStep` stays private to this
// file — it is not promoted to public and not used anywhere else. This is
// a purely static, hardcoded display list; it does not read any provider,
// controller, validation manager, address registry, executor, or
// BLE/transport state.

import 'package:flutter/material.dart';

import '../../../shared/pro_widgets.dart';

class HardwareLiveValidationQueueCard extends StatelessWidget {
  const HardwareLiveValidationQueueCard({super.key});

  static const _steps = [
    (order: '1', label: 'Master Volume L/R', note: 'PASS_ACK — audible verification pending', done: false),
    (order: '2', label: 'SafeLoad Protocol', note: '0x6000–0x6007 — data + trigger', done: false),
    (order: '3', label: 'Mute — 1 channel', note: 'Confirm mute state effect', done: false),
    (order: '4', label: 'Gain — 1 channel', note: 'Confirm level change effect', done: false),
    (order: '5', label: 'Delay — 1 channel', note: 'Confirm timing offset effect', done: false),
    (order: '6', label: 'PEQ Band 1 — 1 channel', note: 'Verify coefficient write via SafeLoad', done: false),
    (order: '7', label: 'XO HPF + LPF — last', note: 'Requires SafeLoad + routing verify', done: false),
  ];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Recommended order for one-parameter-at-a-time live capture.',
        style: proSubtitle(size: 9),
      ),
      const SizedBox(height: 8),
      for (final step in _steps) ...[
        _ValidationStep(
          order: step.order,
          label: step.label,
          note: step.note,
          done: step.done,
        ),
        const SizedBox(height: 5),
      ],
      const SizedBox(height: 6),
      Text(
        'Do not add actual write buttons for unvalidated groups. '
        'Each step requires expert confirmation before advancing.',
        style: proSubtitle(size: 9),
      ),
    ]),
  );
}

class _ValidationStep extends StatelessWidget {
  final String order;
  final String label;
  final String note;
  final bool done;
  const _ValidationStep({
    required this.order,
    required this.label,
    required this.note,
    required this.done,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done
            ? Colors.greenAccent.withValues(alpha: 0.15)
            : kProBorder.withValues(alpha: 0.3),
        border: Border.all(
            color: done ? Colors.greenAccent.withValues(alpha: 0.4) : kProBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(order,
          style: TextStyle(
              fontSize: 9,
              color: done ? Colors.greenAccent : Colors.white38,
              fontWeight: FontWeight.w600)),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: done ? Colors.greenAccent : Colors.white70)),
        Text(note, style: proSubtitle(size: 9)),
      ]),
    ),
    if (done)
      const Icon(Icons.check_circle_outline, size: 12, color: Colors.greenAccent),
  ]);
}
