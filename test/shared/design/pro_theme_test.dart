import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/shared/design/pro_theme.dart';
import 'package:tunai_pro/shared/design/pro_tokens.dart';

void main() {
  group('buildProThemeV2', () {
    final theme = buildProThemeV2();

    test('is a dark, Material 3 theme rooted in ProColors', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, ProColors.bg);
      expect(theme.colorScheme.primary, ProColors.accent);
      expect(theme.colorScheme.error, ProColors.red);
    });

    test('textTheme is body-centric: bodyLarge is 14px, labels are smaller',
        () {
      expect(theme.textTheme.bodyLarge?.fontSize, ProTypeScale.body);
      expect(theme.textTheme.bodyMedium?.fontSize, ProTypeScale.body);
      expect(theme.textTheme.bodySmall?.fontSize, ProTypeScale.secondary);
      expect(theme.textTheme.labelMedium?.fontSize, lessThan(ProTypeScale.body));
    });

    test('no label style carries v1-style wide tracking (>0.5)', () {
      for (final style in [
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.titleSmall,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.textTheme.labelLarge,
        theme.textTheme.labelMedium,
        theme.textTheme.labelSmall,
      ]) {
        expect((style?.letterSpacing ?? 0).abs(), lessThanOrEqualTo(0.5),
            reason: '$style should not use v1-style wide letter-spacing');
      }
    });

    test('every required component theme is present', () {
      expect(theme.filledButtonTheme.style, isNotNull);
      expect(theme.outlinedButtonTheme.style, isNotNull);
      expect(theme.textButtonTheme.style, isNotNull);
      expect(theme.cardTheme, isNotNull);
      expect(theme.checkboxTheme, isNotNull);
      expect(theme.inputDecorationTheme, isNotNull);
      expect(theme.dialogTheme, isNotNull);
      expect(theme.dividerTheme, isNotNull);
      expect(theme.tooltipTheme, isNotNull);
    });

    test('dialogTheme background matches ProColors.panel (same as v1 main.dart)',
        () {
      expect(theme.dialogTheme.backgroundColor, ProColors.panel);
    });

    test('dividerTheme matches the v1 manual 0.5px border divider', () {
      expect(theme.dividerTheme.color, ProColors.border);
      expect(theme.dividerTheme.thickness, 0.5);
    });
  });
}
