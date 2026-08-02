// TUNAI PRO UI v2 — design tokens.
//
// Additive only. `lib/shared/pro_widgets.dart`'s kProBg/kProSurface/kProPanel/
// kProBorder/kProAccent/kProGreen/kProAmber/kProRed and its proLabel/proTitle/
// proSubtitle/proValue helpers are untouched and remain in use across every
// existing screen. Nothing here is wired into main.dart yet — v2 components
// opt into these tokens explicitly; v1 screens are unaffected.
//
// ProColors' first eight values are bit-for-bit identical to the kProXxx
// constants (see the accompanying token test) so v2 surfaces sit next to v1
// surfaces without a visible seam during the phased rollout.

import 'package:flutter/material.dart';

/// Color tokens. The first eight match `pro_widgets.dart` exactly; the rest
/// are additive depth/text steps introduced for v2.
abstract final class ProColors {
  // ── Compatible with pro_widgets.dart kProXxx — do not diverge ──────────────
  static const bg = Color(0xFF080C10);
  static const surface = Color(0xFF0F1419);
  static const panel = Color(0xFF141A21);
  static const border = Color(0xFF1E2832);
  static const accent = Color(0xFF4A9EFF);
  static const green = Color(0xFF22C55E);
  static const amber = Color(0xFFFFB74D);
  static const red = Color(0xFFEF5350);

  // ── Neutral surface scale (v2 depth cues, same hue family as bg/surface) ──
  /// Below `bg` — recessed/inset surfaces (e.g. input fields).
  static const surfaceSunken = Color(0xFF05070A);
  /// Above `panel` — raised surfaces (e.g. hovered rows, popovers).
  static const surfaceRaised = Color(0xFF1A222C);
  /// Above `surfaceRaised` — active/selected surfaces.
  static const surfaceOverlay = Color(0xFF212B37);

  // ── Text neutrals ───────────────────────────────────────────────────────
  static const textPrimary = Colors.white;
  /// Matches proValue's default color.
  static const textSecondary = Color(0xFF9CA3AF);
  /// Matches proSubtitle's default color.
  static const textTertiary = Color(0xFF6B7280);
  static const textDisabled = Color(0x61FFFFFF); // white @ 38%
}

/// Spacing scale, in logical pixels.
abstract final class ProSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Corner-radius scale.
abstract final class ProRadius {
  static const small = 4.0;
  static const medium = 8.0;
  static const large = 12.0;

  static const smallAll = BorderRadius.all(Radius.circular(small));
  static const mediumAll = BorderRadius.all(Radius.circular(medium));
  static const largeAll = BorderRadius.all(Radius.circular(large));
}

/// Elevation as soft dark-theme drop shadows — never a glow. Use sparingly;
/// most v2 surfaces should read through border + fill alone (see
/// ProColors.surfaceRaised/surfaceOverlay) and reserve `low`/`medium` for
/// genuinely floating content (menus, dialogs, popovers).
abstract final class ProElevation {
  static const List<BoxShadow> none = [];

  static const List<BoxShadow> low = [
    BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> medium = [
    BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
}

/// Motion durations + the default easing curve for v2 transitions.
abstract final class ProMotion {
  static const fast = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
}

/// Type scale anchors referenced by ProTheme's textTheme and by v2
/// components directly. Body-centric: 14 is the primary reading size, not a
/// label size — this is the main departure from v1's 9-13px range.
abstract final class ProTypeScale {
  static const body = 14.0;
  static const secondary = 12.0;
  static const label = 10.5;
}
