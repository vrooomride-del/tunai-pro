// TUNAI PRO UI v2 — Hardware Tab extraction (Phase 3-C-3B).
//
// UI extraction only: this is the same widget bundle that lived as the
// private `_ValidationManagerPanel` class (with its private `_ValChip`,
// `_ValidationTaskRow`, `_ActiveTaskDetail`, and `_DetailRow` helpers)
// inside hardware_tab.dart, moved verbatim with no change to the summary
// chip counts, the generate-queue button, the safety note, the task list
// rows, the active task detail panel, or the Mark Failed/Block buttons.
// This widget only receives an already-computed `AddressValidationProjectState`
// plus the active task id and calls the injected callbacks
// (onGenerate/onSelectTask/onMarkFailed/onMarkBlocked) — it does not read
// any provider/ref/controller, does not call the address validation
// engine or any registry factory, does not touch BLE/USBi/transport, does
// not create or mutate validation tasks, and does not judge PASS/FAIL/ACK
// state. All of that stays in hardware_tab.dart's `_HardwareTabState`
// (`_generateValidationQueue`, `_setActiveTask`, `_markTaskFailed`,
// `_markTaskBlocked`). `_ValChip`, `_ValidationTaskRow`, `_ActiveTaskDetail`,
// and `_DetailRow` stay private to this file — none are promoted to public.

import 'package:flutter/material.dart';

import '../../../core/pro_address_validation_data.dart';
import '../../../shared/pro_widgets.dart';

class HardwareValidationManagerCard extends StatelessWidget {
  final AddressValidationProjectState validationState;
  final bool generating;
  final String? activeTaskId;
  final VoidCallback onGenerate;
  final void Function(String?) onSelectTask;
  final Future<void> Function(String) onMarkFailed;
  final Future<void> Function(String) onMarkBlocked;

  const HardwareValidationManagerCard({
    super.key,
    required this.validationState,
    required this.generating,
    required this.activeTaskId,
    required this.onGenerate,
    required this.onSelectTask,
    required this.onMarkFailed,
    required this.onMarkBlocked,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = validationState.tasks;
    final hasQueue = tasks.isNotEmpty;
    final activeTask = activeTaskId != null
        ? tasks.where((t) => t.id == activeTaskId).firstOrNull
        : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Summary chips
      if (hasQueue) ...[
        Wrap(spacing: 8, runSpacing: 6, children: [
          _ValChip('Queued', validationState.queuedCount, Colors.blue),
          _ValChip('Verified', validationState.verifiedCount, Colors.greenAccent),
          _ValChip('Failed', validationState.failedCount, Colors.redAccent),
          _ValChip('Blocked', validationState.blockedCount, Colors.orange),
          _ValChip('High Risk', validationState.highRiskCount, Colors.purpleAccent),
        ]),
        const SizedBox(height: 12),
      ],

      // Generate queue button
      GestureDetector(
        onTap: generating ? null : onGenerate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: generating ? kProSurface : kProAccent.withValues(alpha: 0.08),
            border: Border.all(
                color: generating ? kProBorder : kProAccent.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              generating ? Icons.hourglass_empty_outlined : Icons.playlist_add_outlined,
              size: 14,
              color: generating ? Colors.white24 : kProAccent,
            ),
            const SizedBox(width: 7),
            Text(
              generating
                  ? 'Generating queue...'
                  : hasQueue
                      ? 'Regenerate Validation Queue'
                      : 'Generate Validation Queue',
              style: TextStyle(
                fontSize: 11,
                color: generating ? Colors.white24 : kProAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
        ),
      ),

      // Safety note
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 11, color: Colors.white38),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Validation manager does not write hardware. '
              'It records readiness and observed results for expert review.',
              style: proSubtitle(size: 9),
            ),
          ),
        ]),
      ),

      // Task list
      if (hasQueue) ...[
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(children: [
            for (int i = 0; i < tasks.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: kProBorder),
              _ValidationTaskRow(
                task: tasks[i],
                isActive: tasks[i].id == activeTaskId,
                onTap: () => onSelectTask(
                    tasks[i].id == activeTaskId ? null : tasks[i].id),
              ),
            ],
          ]),
        ),
      ],

      // Active task detail
      if (activeTask != null) ...[
        const SizedBox(height: 12),
        _ActiveTaskDetail(
          task: activeTask,
          onMarkFailed: () => onMarkFailed(activeTask.id),
          onMarkBlocked: () => onMarkBlocked(activeTask.id),
        ),
      ],
    ]);
  }
}

class _ValChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _ValChip(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text('$label  $count',
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
  );
}

class _ValidationTaskRow extends StatelessWidget {
  final AddressValidationTask task;
  final bool isActive;
  final VoidCallback onTap;
  const _ValidationTaskRow({
    required this.task,
    required this.isActive,
    required this.onTap,
  });

  Color get _riskColor => switch (task.risk) {
    AddressValidationRisk.low      => Colors.greenAccent,
    AddressValidationRisk.medium   => kProAmber,
    AddressValidationRisk.high     => Colors.orange,
    AddressValidationRisk.critical => Colors.redAccent,
  };

  Color get _statusColor => switch (task.currentStatus) {
    AddressValidationStatus.liveWriteVerified => Colors.greenAccent,
    AddressValidationStatus.failed            => Colors.redAccent,
    AddressValidationStatus.blocked           => Colors.orange,
    AddressValidationStatus.queued            => Colors.blue,
    _                                         => Colors.white38,
  };

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      color: isActive ? kProAccent.withValues(alpha: 0.05) : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        // Group badge
        Container(
          width: 60,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(task.group.label,
              style: const TextStyle(fontSize: 8, color: Colors.white54),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        // Name + address
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.logicalName,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(task.addressHex,
                style: const TextStyle(fontSize: 9, color: Colors.white38,
                    fontFamily: 'monospace')),
          ]),
        ),
        const SizedBox(width: 8),
        // Risk
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: _riskColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(task.risk.label,
              style: TextStyle(fontSize: 8, color: _riskColor)),
        ),
        const SizedBox(width: 6),
        // Status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(task.currentStatus.label,
              style: TextStyle(fontSize: 8, color: _statusColor)),
        ),
        if (isActive) ...[
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_up, size: 12, color: kProAccent),
        ],
      ]),
    ),
  );
}

class _ActiveTaskDetail extends StatelessWidget {
  final AddressValidationTask task;
  final VoidCallback onMarkFailed;
  final VoidCallback onMarkBlocked;
  const _ActiveTaskDetail({
    required this.task,
    required this.onMarkFailed,
    required this.onMarkBlocked,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProAccent.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(task.logicalName,
            style: proLabel(size: 11)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text('DRY-RUN ONLY',
              style: TextStyle(fontSize: 8, color: Colors.orange,
                  fontWeight: FontWeight.w600, letterSpacing: 0.6)),
        ),
      ]),
      const SizedBox(height: 8),
      _DetailRow('Address', task.addressHex),
      _DetailRow('Group', task.group.label),
      _DetailRow('Risk', task.risk.label),
      _DetailRow('Status', task.currentStatus.label),
      if (task.channel != null) _DetailRow('Channel', task.channel!),
      if (task.outputIndex != null) _DetailRow('Output', task.outputIndex!),
      if (task.coefficient != null) _DetailRow('Coefficient', task.coefficient!),
      if (task.expectedEffect != null) ...[
        const SizedBox(height: 6),
        Text('Expected Effect', style: proSubtitle(size: 9, color: Colors.white38)),
        const SizedBox(height: 3),
        Text(task.expectedEffect!,
            style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ],
      if (task.actualObservedEffect != null) ...[
        const SizedBox(height: 6),
        Text('Observed', style: proSubtitle(size: 9, color: Colors.white38)),
        const SizedBox(height: 3),
        Text(task.actualObservedEffect!,
            style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ],
      const SizedBox(height: 10),
      // Buttons
      Row(children: [
        // Mark Verified — disabled until wasActualWrite in future phases
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('Mark Verified (disabled — Phase U2)',
              style: TextStyle(fontSize: 9, color: Colors.white24)),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onMarkFailed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Mark Failed',
                style: TextStyle(fontSize: 9, color: Colors.redAccent)),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onMarkBlocked,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Block',
                style: TextStyle(fontSize: 9, color: Colors.orange)),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Text(
        'Validation manager does not write hardware. '
        '"Mark Verified" requires wasActualWrite = true, '
        'which is only enabled in future write phases.',
        style: proSubtitle(size: 9),
      ),
    ]),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 72,
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(fontSize: 9, color: Colors.white60)),
      ),
    ]),
  );
}
