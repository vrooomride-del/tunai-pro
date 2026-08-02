// TUNAI PRO UI v2 — common label/value row.
//
// Replaces the per-tab private `_InfoRow` widgets duplicated across
// deploy_tab.dart / hardware_tab.dart / project_tab.dart. Not wired into
// those files yet.

import 'package:flutter/material.dart';

import '../design/pro_tokens.dart';

class ProInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  const ProInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: ProSpacing.xs),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(
                  color: ProColors.textTertiary,
                  fontSize: ProTypeScale.secondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: ProSpacing.sm),
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (icon != null) ...[
                    Icon(icon,
                        size: 13, color: valueColor ?? ProColors.textSecondary),
                    const SizedBox(width: ProSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: valueColor ?? ProColors.textPrimary,
                        fontSize: ProTypeScale.secondary,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
