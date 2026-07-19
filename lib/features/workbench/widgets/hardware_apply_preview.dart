import 'package:flutter/material.dart';

import '../../../core/deploy/pro_hardware_capability.dart';
import '../../../core/deploy/pro_hardware_write_plan.dart';
import '../../../shared/pro_widgets.dart';

/// Read-only review of a [HardwareWritePlan] before any (future) execution.
///
/// Displays the plan's device profile, per-verification counts, the subset of
/// operations that are capture-proven (writable), and the blocked operations
/// grouped by reason. Purely presentational — it performs no writes and makes
/// no transport/preflight/executor calls.
class HardwareApplyPreview extends StatelessWidget {
  final HardwareWritePlan plan;

  const HardwareApplyPreview({super.key, required this.plan});

  static String paramLabel(HardwareParamKind kind) => switch (kind) {
        HardwareParamKind.peqGain => 'PEQ Gain',
        HardwareParamKind.peqFrequency => 'PEQ Frequency',
        HardwareParamKind.peqQ => 'PEQ Q',
        HardwareParamKind.crossoverHighPass => 'Crossover HPF',
        HardwareParamKind.crossoverLowPass => 'Crossover LPF',
        HardwareParamKind.channelGain => 'Channel Gain',
        HardwareParamKind.channelDelay => 'Channel Delay',
        HardwareParamKind.channelMute => 'Channel Mute',
        HardwareParamKind.channelPolarity => 'Channel Polarity',
      };

  static String bandLabel(int? bandIndex) =>
      bandIndex == null ? '—' : 'Band ${bandIndex + 1}';

  static String valueLabel(HardwareWriteOp op) {
    final v = op.targetValue;
    final n = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return switch (op.parameterKind) {
      HardwareParamKind.peqFrequency ||
      HardwareParamKind.crossoverHighPass ||
      HardwareParamKind.crossoverLowPass =>
        '$n Hz',
      HardwareParamKind.peqGain || HardwareParamKind.channelGain => '$n dB',
      HardwareParamKind.channelDelay => '$n ms',
      HardwareParamKind.channelMute ||
      HardwareParamKind.channelPolarity =>
        v == 0 ? 'off' : 'on',
      HardwareParamKind.peqQ => 'Q $n',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = plan.summary;
    final writable = plan.writableOperations;
    final blocked = plan.operations.where((o) => !o.writable).toList();

    // Group blocked ops by their reason string.
    final byReason = <String, List<HardwareWriteOp>>{};
    for (final o in blocked) {
      byReason.putIfAbsent(o.reason, () => []).add(o);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header + device
        Row(children: [
          Icon(Icons.memory_outlined, color: kProAccent.withValues(alpha: 0.6), size: 14),
          const SizedBox(width: 8),
          Text('HARDWARE APPLY PREVIEW', style: proLabel(size: 9, spacing: 1.8)),
          const Spacer(),
          Text('REVIEW ONLY', style: proLabel(size: 8, color: kProAmber)),
        ]),
        const SizedBox(height: 8),
        _kv('Device profile', plan.deviceProfile.deviceName),
        _kv('Transport', plan.deviceProfile.transport.label),

        // Summary counts
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 8, children: [
          _CountChip(label: 'TOTAL OPS', value: '${s.totalOps}'),
          _CountChip(label: 'WRITABLE', value: '${s.writableOps}',
              color: s.writableOps > 0 ? kProGreen : null),
          _CountChip(label: 'BLOCKED', value: '${s.totalOps - s.writableOps}',
              color: (s.totalOps - s.writableOps) > 0 ? kProAmber : null),
          _CountChip(label: 'CAPTURE PROVEN', value: '${s.captureProvenCount}',
              color: s.captureProvenCount > 0 ? kProGreen : null),
          _CountChip(label: 'UNVERIFIED', value: '${s.unverifiedCount}',
              color: s.unverifiedCount > 0 ? kProAmber : null),
          _CountChip(label: 'UNAVAILABLE', value: '${s.unavailableCount}',
              color: s.unavailableCount > 0 ? Colors.white38 : null),
        ]),

        // Writable operations
        const SizedBox(height: 16),
        Text('WRITABLE OPERATIONS (${writable.length})',
            style: proLabel(size: 9, color: kProGreen, spacing: 1.2)),
        const SizedBox(height: 6),
        if (writable.isEmpty)
          Text('No capture-proven operations in this plan.',
              style: proSubtitle(size: 10))
        else
          ...writable.map(_opRow),

        // Blocked operations grouped by reason
        const SizedBox(height: 16),
        Text('BLOCKED OPERATIONS (${blocked.length})',
            style: proLabel(size: 9, color: kProAmber, spacing: 1.2)),
        const SizedBox(height: 6),
        if (blocked.isEmpty)
          Text('No blocked operations.', style: proSubtitle(size: 10))
        else
          ...byReason.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.block_outlined, color: kProAmber, size: 11),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('${e.value.length}× — ${e.key}',
                              style: proSubtitle(size: 10, color: Colors.white54)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      ...e.value.map(_opRow),
                    ]),
              )),

        // Safety notice
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.08),
            border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            const Icon(Icons.lock_outline, color: kProAmber, size: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Hardware write is not implemented / requires approval. '
                'This is a review-only preview — no parameters are written to any device.',
                style: proSubtitle(size: 11, color: kProAmber),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 110, child: Text(k, style: proLabel(size: 10, spacing: 0.3))),
          Text(v, style: proValue(size: 11, color: Colors.white60)),
        ]),
      );

  Widget _opRow(HardwareWriteOp op) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
            width: 70,
            child: Text(op.channelId,
                style: proValue(size: 10, color: Colors.white54),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: Text(paramLabel(op.parameterKind),
                style: proLabel(size: 10, spacing: 0.2)),
          ),
          SizedBox(
            width: 64,
            child: Text(bandLabel(op.bandIndex),
                style: proSubtitle(size: 10, color: Colors.white38)),
          ),
          SizedBox(
            width: 78,
            child: Text(valueLabel(op),
                style: proValue(size: 10, color: Colors.white70),
                textAlign: TextAlign.right),
          ),
        ]),
      );
}

class _CountChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _CountChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: kProBg,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: proLabel(size: 8, spacing: 0.8)),
          const SizedBox(height: 2),
          Text(value, style: proValue(size: 13, color: color ?? Colors.white54)),
        ]),
      );
}
