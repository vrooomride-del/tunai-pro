// TUNAI PRO UI v2 — common section header.
//
// Replaces the per-tab private `_SectionHeader` widgets duplicated across
// deploy_tab.dart / hardware_tab.dart with one component. Not wired into
// those files yet — this is the v2 primitive on its own.
//
// Renders exactly the text it's given: no forced uppercase, no wide
// tracking. Callers own casing/wording.

import 'package:flutter/material.dart';

import '../design/pro_tokens.dart';

class ProSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;

  /// Thin bottom rule, matching the manual `Container(height: 0.5, color:
  /// kProBorder)` dividers used throughout v1. Off by default for headers
  /// that sit directly above a bordered card.
  final bool showDivider;

  const ProSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: ProColors.accent.withValues(alpha: 0.7)),
          const SizedBox(width: ProSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: ProColors.textPrimary,
                  fontSize: ProTypeScale.body,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: ProColors.textTertiary,
                    fontSize: ProTypeScale.secondary,
                    height: 1.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: ProSpacing.sm),
          trailing!,
        ],
      ],
    );

    if (!showDivider) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        const SizedBox(height: ProSpacing.sm),
        const Divider(height: 0.5, thickness: 0.5, color: ProColors.border),
      ],
    );
  }
}
