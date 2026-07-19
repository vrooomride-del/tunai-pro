import 'dart:math' as math;

import 'pro_acoustic_data.dart';

/// Reusable numeric sampler for the acoustic target curves.
///
/// Mirrors the per-preset shapes used by the simulation preview so the
/// optimizer and the simulation engine agree. Values are relative dB (0 dB =
/// on-target); this is a design/analysis curve, not a DSP write.
abstract final class ProTargetCurve {
  /// Target level (dB) at frequency [f] for [preset].
  static double db(TargetCurvePreset preset, double f) {
    switch (preset) {
      case TargetCurvePreset.flat:
        return 0.0;
      case TargetCurvePreset.warm:
        // Gentle low-frequency lift + smooth high-frequency roll-off.
        if (f < 200) return 2.0 * (1.0 - f / 200.0);
        if (f > 8000) return -1.5 * math.log(f / 8000) / math.ln2;
        return 0.0;
      case TargetCurvePreset.studio:
        // Slight top-octave roll-off.
        if (f > 10000) return -1.0 * math.log(f / 10000) / math.ln2;
        return 0.0;
      case TargetCurvePreset.nearfield:
        // Presence bump 1.5–5 kHz + close-field low-end reduction.
        var db = 0.0;
        if (f >= 1500 && f <= 5000) {
          const center = 2800.0;
          final x = math.log(f / center) / math.ln2;
          db = 1.5 * math.exp(-x * x * 2.0);
        }
        if (f < 80) db -= 3.0 * (1.0 - f / 80.0);
        return db;
      case TargetCurvePreset.custom:
        return 0.0;
    }
  }

  /// Target curve (dB per point) over [freqs].
  static List<double> curve(TargetCurvePreset preset, List<double> freqs) =>
      [for (final f in freqs) db(preset, f)];
}
