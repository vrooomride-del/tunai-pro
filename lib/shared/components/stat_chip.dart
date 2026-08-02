// TUNAI PRO UI v2 — common label/value chip.
//
// Replaces the per-tab private `_StatChip` widgets duplicated across
// pro_widgets.dart / analyze_tab.dart / export_tab.dart / measure_tab.dart /
// report_tab.dart. Not wired into those files yet.

import 'package:flutter/material.dart';

import '../design/pro_tokens.dart';

class ProStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  const ProStatChip({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: ProSpacing.md, vertical: ProSpacing.sm),
        decoration: BoxDecoration(
          color: ProColors.surface,
          border: Border.all(color: ProColors.border),
          borderRadius: ProRadius.mediumAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: ProColors.textTertiary,
                fontSize: ProTypeScale.label,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: valueColor ?? ProColors.textPrimary),
                  const SizedBox(width: ProSpacing.xs),
                ],
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? ProColors.textPrimary,
                    fontSize: ProTypeScale.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
