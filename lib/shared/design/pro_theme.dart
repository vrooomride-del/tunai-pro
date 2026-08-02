// TUNAI PRO UI v2 — component theme.
//
// Builds a complete dark ThemeData from pro_tokens.dart. NOT wired into
// main.dart yet: TunaiProApp still builds its own minimal ThemeData inline.
// This exists so v2 screens (and their widget tests) can opt in ahead of the
// full cutover, and so the cutover itself is a one-line MaterialApp.theme
// swap once v1 screens have migrated off ad hoc inline styling.
//
// Style direction: high-end acoustic workstation, not a diagnostic panel.
// No forced uppercase, no wide tracking, no glow — depth comes from the
// surface/border scale in pro_tokens.dart, restrained shadows only on
// genuinely floating content (dialogs, tooltips).

import 'package:flutter/material.dart';

import 'pro_tokens.dart';

ThemeData buildProThemeV2() {
  const colorScheme = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: ProColors.accent,
    onPrimary: ProColors.bg,
    secondary: ProColors.green,
    onSecondary: ProColors.bg,
    tertiary: ProColors.amber,
    onTertiary: ProColors.bg,
    error: ProColors.red,
    onError: ProColors.bg,
    surface: ProColors.surface,
    onSurface: ProColors.textPrimary,
  );

  const textTheme = _textTheme;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: ProColors.bg,
    colorScheme: colorScheme,
    textTheme: textTheme,
    dividerTheme: const DividerThemeData(
      color: ProColors.border,
      thickness: 0.5,
      space: 0.5,
    ),
    cardTheme: const CardThemeData(
      color: ProColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: ProRadius.mediumAll,
        side: BorderSide(color: ProColors.border, width: 0.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ProColors.accent,
        foregroundColor: ProColors.bg,
        disabledBackgroundColor: ProColors.surfaceRaised,
        disabledForegroundColor: ProColors.textDisabled,
        padding: const EdgeInsets.symmetric(
            horizontal: ProSpacing.lg, vertical: ProSpacing.md),
        shape: const RoundedRectangleBorder(borderRadius: ProRadius.mediumAll),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ProColors.textPrimary,
        disabledForegroundColor: ProColors.textDisabled,
        side: const BorderSide(color: ProColors.border),
        padding: const EdgeInsets.symmetric(
            horizontal: ProSpacing.lg, vertical: ProSpacing.md),
        shape: const RoundedRectangleBorder(borderRadius: ProRadius.mediumAll),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ProColors.textSecondary,
        disabledForegroundColor: ProColors.textDisabled,
        padding: const EdgeInsets.symmetric(
            horizontal: ProSpacing.md, vertical: ProSpacing.sm),
        shape: const RoundedRectangleBorder(borderRadius: ProRadius.smallAll),
        textStyle: textTheme.labelLarge,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(borderRadius: ProRadius.smallAll),
      side: const BorderSide(color: ProColors.border, width: 1.2),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return ProColors.surfaceRaised;
        }
        if (states.contains(WidgetState.selected)) return ProColors.accent;
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(ProColors.bg),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ProColors.surfaceSunken,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: ProSpacing.md, vertical: ProSpacing.md),
      hintStyle: textTheme.bodyLarge?.copyWith(color: ProColors.textTertiary),
      labelStyle:
          textTheme.bodyMedium?.copyWith(color: ProColors.textSecondary),
      border: const OutlineInputBorder(
        borderRadius: ProRadius.mediumAll,
        borderSide: BorderSide(color: ProColors.border),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: ProRadius.mediumAll,
        borderSide: BorderSide(color: ProColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: ProRadius.mediumAll,
        borderSide: BorderSide(color: ProColors.accent),
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: ProRadius.mediumAll,
        borderSide: BorderSide(color: ProColors.border),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: ProColors.panel,
      shape: RoundedRectangleBorder(borderRadius: ProRadius.largeAll),
      elevation: 0,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ProColors.surfaceRaised,
        borderRadius: ProRadius.smallAll,
        border: Border.all(color: ProColors.border),
        boxShadow: ProElevation.low,
      ),
      textStyle:
          textTheme.bodySmall?.copyWith(color: ProColors.textPrimary),
      padding: const EdgeInsets.symmetric(
          horizontal: ProSpacing.sm, vertical: ProSpacing.xs),
    ),
  );
}

// Body-centric scale (14px primary reading size), modest weight contrast for
// hierarchy instead of tracked all-caps labels. letterSpacing stays under 0.5
// everywhere — v1's 1.5-2.5 tracked labels are intentionally not carried over.
const _textTheme = TextTheme(
  titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w300,
      color: ProColors.textPrimary,
      letterSpacing: 0.1),
  titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: ProColors.textPrimary,
      letterSpacing: 0.1),
  titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: ProColors.textPrimary,
      letterSpacing: 0.1),
  bodyLarge: TextStyle(
      fontSize: ProTypeScale.body,
      fontWeight: FontWeight.w400,
      color: ProColors.textPrimary,
      height: 1.5),
  bodyMedium: TextStyle(
      fontSize: ProTypeScale.body,
      fontWeight: FontWeight.w400,
      color: ProColors.textSecondary,
      height: 1.5),
  bodySmall: TextStyle(
      fontSize: ProTypeScale.secondary,
      fontWeight: FontWeight.w400,
      color: ProColors.textTertiary,
      height: 1.5),
  labelLarge: TextStyle(
      fontSize: ProTypeScale.secondary,
      fontWeight: FontWeight.w500,
      color: ProColors.textPrimary,
      letterSpacing: 0.2),
  labelMedium: TextStyle(
      fontSize: ProTypeScale.label,
      fontWeight: FontWeight.w500,
      color: ProColors.textSecondary,
      letterSpacing: 0.3),
  labelSmall: TextStyle(
      fontSize: ProTypeScale.label,
      fontWeight: FontWeight.w400,
      color: ProColors.textTertiary,
      letterSpacing: 0.3),
);
