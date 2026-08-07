// ── TUNAI PRO Phase 3-E §19 — shared Home controls ─────────────────────────
//
// The small set of buttons and containers the Home sections share, built on
// the existing Pro design tokens. Kept here so "one primary action per
// screen" is enforceable by sight: there is exactly one HomePrimaryButton
// style, and Continue Tuning is the only place it appears when a project is
// open.

import 'package:flutter/material.dart';

import '../../../shared/design/pro_tokens.dart';

/// The single filled call-to-action style.
class HomePrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool large;

  const HomePrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: ProRadius.smallAll,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: large ? ProSpacing.xl : ProSpacing.lg,
              vertical: large ? ProSpacing.md + 2 : ProSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: ProColors.accent.withValues(alpha: 0.15),
              border:
                  Border.all(color: ProColors.accent.withValues(alpha: 0.5)),
              borderRadius: ProRadius.smallAll,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                label,
                style: TextStyle(
                  color: ProColors.accent,
                  fontSize: large ? ProTypeScale.body : ProTypeScale.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon ?? Icons.arrow_forward,
                  size: large ? 16 : 13, color: ProColors.accent),
            ]),
          ),
        ),
      );
}

/// A quiet, bordered action — never competes with the primary CTA.
class HomeSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const HomeSecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: ProRadius.smallAll,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: ProSpacing.lg, vertical: ProSpacing.sm + 2),
            decoration: BoxDecoration(
              border: Border.all(color: ProColors.border),
              borderRadius: ProRadius.smallAll,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: ProColors.textSecondary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                    color: ProColors.textSecondary,
                    fontSize: ProTypeScale.secondary),
              ),
            ]),
          ),
        ),
      );
}

/// The standard Home panel: a calm bordered surface, no glow, no gradient.
class HomePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const HomePanel({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding ?? const EdgeInsets.all(ProSpacing.xl),
        decoration: BoxDecoration(
          color: ProColors.surface,
          border: Border.all(color: ProColors.border),
          borderRadius: ProRadius.largeAll,
        ),
        child: child,
      );
}

/// A quiet uppercase section label.
class HomeSectionLabel extends StatelessWidget {
  final String text;
  const HomeSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: ProColors.textTertiary,
          fontSize: ProTypeScale.label,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w500,
        ),
      );
}
