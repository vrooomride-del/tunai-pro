// TUNAI PRO UI/UX v3 Phase V3-1 — Graph Overlay Foundation.
//
// Presentation-only view models for Adau1701PeqResponseGraph's multi-channel
// overlay/difference modes. This file introduces NO new PEQ calculation —
// [PeqGraphCurve.curveFor] delegates entirely to the existing, unmodified
// Adau1701PeqResponse.combinedCurve, and [PeqGraphOverlayMath.difference] is
// a display-only point-wise subtraction of two already-computed curves. It
// never reads, writes, or reinterprets PeqChannelState/PeqBand.

import 'package:flutter/material.dart';

import '../../../core/adau1701_peq_response.dart';

/// How Adau1701PeqResponseGraph renders its curve(s).
///
/// [single] is the default and matches the graph's pre-v3-1 behaviour
/// exactly (one channel's `bands`, optional `baselineBands`/marker).
enum PeqGraphMode {
  single,
  overlay,
  difference;

  String get label => switch (this) {
        PeqGraphMode.single => 'Single',
        PeqGraphMode.overlay => 'Overlay',
        PeqGraphMode.difference => 'Difference',
      };
}

/// One named curve for overlay/difference display — e.g. "Woofer L" vs
/// "Woofer R". Carries the same [PeqResponseBand] list the single-channel
/// graph already accepts; nothing here reinterprets or mutates that data.
@immutable
class PeqGraphCurve {
  final String label;
  final List<PeqResponseBand> bands;

  /// Optional explicit line color. When null, the graph assigns one from its
  /// default overlay palette by position.
  final Color? color;

  const PeqGraphCurve({
    required this.label,
    required this.bands,
    this.color,
  });

  /// Combined magnitude curve (dB per point) for this curve's bands, sampled
  /// at [freqPoints] — the exact same calculation
  /// (`Adau1701PeqResponse.combinedCurve`) the pre-existing single-channel
  /// graph already uses. Callers comparing two curves must sample both with
  /// the same [freqPoints] instance/grid (the graph widget always does this
  /// internally).
  List<double> curveFor(List<double> freqPoints) =>
      Adau1701PeqResponse.combinedCurve(bands, freqPoints);
}

/// Pure, graph-display-only math for comparing already-computed PEQ curves.
/// Never touches PeqBand/PeqChannelState and never changes
/// Adau1701PeqResponse's own calculation — this only combines its outputs.
abstract final class PeqGraphOverlayMath {
  /// Point-wise `a - b`. Returns null (no difference curve should be shown)
  /// when either curve is empty or they were not sampled at the same
  /// frequency grid (mismatched length) — a display-only safety check, not
  /// a PEQ calculation change.
  static List<double>? difference(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return null;
    if (a.length != b.length) return null;
    return [for (var i = 0; i < a.length; i++) a[i] - b[i]];
  }

  /// Mean absolute value of a difference curve — the single representative
  /// "how far apart are these two curves" number shown as e.g.
  /// "Difference: 1.8dB". Display-only; not a PEQ value and never fed back
  /// into any band/channel data.
  static double meanAbsoluteDifference(List<double> diff) {
    if (diff.isEmpty) return 0;
    var sum = 0.0;
    for (final d in diff) {
      sum += d.abs();
    }
    return sum / diff.length;
  }
}

/// v3-2: a purely informational "how well do these two channels match"
/// label for the Compare UI — analysis/display only. Never triggers,
/// suggests, or applies any automatic correction.
enum PeqChannelMatch {
  excellent,
  good,
  needsTune;

  String get label => switch (this) {
        PeqChannelMatch.excellent => 'Excellent',
        PeqChannelMatch.good => 'Good',
        PeqChannelMatch.needsTune => 'Needs Tune',
      };

  /// Thresholds on mean-absolute-difference (dB): <1 excellent, 1..3 good,
  /// >3 needs tune.
  static PeqChannelMatch fromMeanAbsDiff(double meanAbsDiffDb) {
    if (meanAbsDiffDb < 1) return PeqChannelMatch.excellent;
    if (meanAbsDiffDb <= 3) return PeqChannelMatch.good;
    return PeqChannelMatch.needsTune;
  }
}

/// Default overlay line colors, cycled by curve position when a
/// [PeqGraphCurve] doesn't specify its own [PeqGraphCurve.color].
const List<Color> peqGraphOverlayPalette = [
  Color(0xFF4A9EFF), // accent blue
  Color(0xFFFFB74D), // amber
  Color(0xFF22C55E), // green
  Color(0xFFA78BFA), // violet
  Color(0xFFEF5350), // red
  Color(0xFF26C6DA), // cyan
];
