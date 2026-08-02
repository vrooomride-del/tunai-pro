// Locks the "visually compatible with pro_widgets.dart" claim in
// pro_tokens.dart's file header: ProColors' first eight values must stay
// bit-for-bit identical to the kProXxx constants v1 screens already use.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/shared/design/pro_tokens.dart';
import 'package:tunai_pro/shared/pro_widgets.dart' as v1;

void main() {
  group('ProColors — compatible with pro_widgets.dart kProXxx', () {
    test('matches each v1 constant exactly', () {
      expect(ProColors.bg, v1.kProBg);
      expect(ProColors.surface, v1.kProSurface);
      expect(ProColors.panel, v1.kProPanel);
      expect(ProColors.border, v1.kProBorder);
      expect(ProColors.accent, v1.kProAccent);
      expect(ProColors.green, v1.kProGreen);
      expect(ProColors.amber, v1.kProAmber);
      expect(ProColors.red, v1.kProRed);
    });

    test('v2 neutral surface scale stays within the same dark hue family', () {
      // Sunken should be darker than bg; raised/overlay lighter than panel,
      // in strictly increasing order — a monotonic depth scale.
      expect(_luma(ProColors.surfaceSunken), lessThan(_luma(ProColors.bg)));
      expect(_luma(ProColors.panel), lessThan(_luma(ProColors.surfaceRaised)));
      expect(_luma(ProColors.surfaceRaised),
          lessThan(_luma(ProColors.surfaceOverlay)));
    });
  });

  group('ProSpacing', () {
    test('is the requested 4/8/12/16/24/32 scale', () {
      expect(
        [
          ProSpacing.xs,
          ProSpacing.sm,
          ProSpacing.md,
          ProSpacing.lg,
          ProSpacing.xl,
          ProSpacing.xxl,
        ],
        [4.0, 8.0, 12.0, 16.0, 24.0, 32.0],
      );
    });
  });

  group('ProRadius', () {
    test('small < medium < large, and BorderRadius helpers match', () {
      expect(ProRadius.small, lessThan(ProRadius.medium));
      expect(ProRadius.medium, lessThan(ProRadius.large));
      expect(ProRadius.smallAll, BorderRadius.circular(ProRadius.small));
      expect(ProRadius.mediumAll, BorderRadius.circular(ProRadius.medium));
      expect(ProRadius.largeAll, BorderRadius.circular(ProRadius.large));
    });
  });

  group('ProElevation', () {
    test('none is empty; low/medium are subtle dark shadows, not glows', () {
      expect(ProElevation.none, isEmpty);
      for (final shadow in [...ProElevation.low, ...ProElevation.medium]) {
        // A "glow" would be a bright, saturated color; every token here must
        // be a translucent black.
        expect(shadow.color.a, lessThan(1.0));
        expect(shadow.color.r, 0);
        expect(shadow.color.g, 0);
        expect(shadow.color.b, 0);
      }
    });
  });

  group('ProMotion', () {
    test('fast < medium < slow', () {
      expect(ProMotion.fast, lessThan(ProMotion.medium));
      expect(ProMotion.medium, lessThan(ProMotion.slow));
    });
  });

  group('ProTypeScale', () {
    test('body is the largest (14px, reading-centric), label the smallest',
        () {
      expect(ProTypeScale.body, 14.0);
      expect(ProTypeScale.body, greaterThan(ProTypeScale.secondary));
      expect(ProTypeScale.secondary, greaterThan(ProTypeScale.label));
      expect(ProTypeScale.label, inInclusiveRange(10.0, 11.0));
    });
  });
}

double _luma(Color c) => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
