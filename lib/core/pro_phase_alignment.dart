import 'dart:math' as math;

import 'pro_crossover_response.dart';
import 'pro_phase_response.dart';
import 'pro_tuning_data.dart';

/// Alignment verdict from the electrical phase simulation.
enum XoAlignmentStatus {
  good,
  check,
  misalign;

  String get label => switch (this) {
        XoAlignmentStatus.good => 'GOOD',
        XoAlignmentStatus.check => 'CHECK',
        XoAlignmentStatus.misalign => 'MISALIGN',
      };
}

/// Per-driver input for phase-alignment analysis.
class XoAlignmentInput {
  final String label;
  final CrossoverChannelState channel;
  final double delayMs;
  final double phaseOffsetDeg;
  const XoAlignmentInput({
    required this.label,
    required this.channel,
    this.delayMs = 0.0,
    this.phaseOffsetDeg = 0.0,
  });
}

/// One analysed crossover between a low-side driver (LPF) and a high-side
/// driver (HPF).
class XoAlignmentPair {
  final String lowLabel;
  final String highLabel;
  final double crossoverHz;

  /// |Δ phase| at the crossover frequency, 0..180°.
  final double phaseDiffDeg;
  final double lowDelayMs;
  final double highDelayMs;
  final bool lowPolarityInverted;
  final bool highPolarityInverted;
  final XoAlignmentStatus status;

  const XoAlignmentPair({
    required this.lowLabel,
    required this.highLabel,
    required this.crossoverHz,
    required this.phaseDiffDeg,
    required this.lowDelayMs,
    required this.highDelayMs,
    required this.lowPolarityInverted,
    required this.highPolarityInverted,
    required this.status,
  });
}

/// Electrical phase-alignment analysis for the XO editor. Simulation only —
/// measured acoustic phase is NOT included. No DSP write / mapping.
abstract final class XoPhaseAlignment {
  /// Thresholds on the phase difference at the crossover frequency.
  static const double goodBelowDeg = 30;
  static const double checkBelowDeg = 60;

  static XoAlignmentStatus statusForPhaseDiff(double phaseDiffDeg) {
    final d = phaseDiffDeg.abs();
    if (d < goodBelowDeg) return XoAlignmentStatus.good;
    if (d <= checkBelowDeg) return XoAlignmentStatus.check;
    return XoAlignmentStatus.misalign;
  }

  /// Analyses every low-driver (LPF) × high-driver (HPF) crossover among
  /// [drivers] whose cutoffs are within ±1 octave, scoring each on the phase
  /// difference at the crossover frequency (the point of equal output).
  static List<XoAlignmentPair> analyze(List<XoAlignmentInput> drivers) {
    final freqs = CrossoverResponse.logFrequencyPoints(count: 400);
    final pairs = <XoAlignmentPair>[];

    for (final low in drivers) {
      final lpf = low.channel.lowPass;
      if (low.channel.bypassed || lpf == null || !lpf.enabled) continue;
      for (final high in drivers) {
        if (identical(low, high)) continue;
        final hpf = high.channel.highPass;
        if (high.channel.bypassed || hpf == null || !hpf.enabled) continue;

        // Cutoffs must be within ±1 octave to be a genuine crossover pair.
        final ratio = lpf.frequencyHz / hpf.frequencyHz;
        if (ratio < 0.5 || ratio > 2.0) continue;

        final xHz = _crossoverHz(low, high, freqs);
        if (xHz == null) continue;

        final phaseLow = CrossoverPhase.driverPhaseDeg(
            channel: low.channel,
            delayMs: low.delayMs,
            phaseOffsetDeg: low.phaseOffsetDeg,
            f: xHz);
        final phaseHigh = CrossoverPhase.driverPhaseDeg(
            channel: high.channel,
            delayMs: high.delayMs,
            phaseOffsetDeg: high.phaseOffsetDeg,
            f: xHz);
        final diff = CrossoverPhase.wrapDeg(phaseLow - phaseHigh).abs();

        pairs.add(XoAlignmentPair(
          lowLabel: low.label,
          highLabel: high.label,
          crossoverHz: xHz,
          phaseDiffDeg: diff,
          lowDelayMs: low.delayMs,
          highDelayMs: high.delayMs,
          lowPolarityInverted: low.channel.polarityInverted,
          highPolarityInverted: high.channel.polarityInverted,
          status: statusForPhaseDiff(diff),
        ));
      }
    }
    return pairs;
  }

  /// The frequency where the two drivers' magnitudes cross (equal output).
  /// Returns null if they never cross within a usable overlap.
  static double? _crossoverHz(
      XoAlignmentInput low, XoAlignmentInput high, List<double> freqs) {
    double? prevF;
    double? prevDelta;
    for (final f in freqs) {
      final lowDb = CrossoverResponse.channelMagnitudeDb(low.channel, f);
      final highDb = CrossoverResponse.channelMagnitudeDb(high.channel, f);
      final delta = lowDb - highDb; // + when low is louder
      if (prevDelta != null && prevF != null) {
        final crossed = (prevDelta <= 0 && delta >= 0) ||
            (prevDelta >= 0 && delta <= 0);
        // Require a real overlap (both within 24 dB of pass) at the crossing.
        if (crossed && lowDb > -24 && highDb > -24) {
          final t = prevDelta == delta
              ? 0.5
              : (0 - prevDelta) / (delta - prevDelta);
          // Interpolate in log-frequency for accuracy.
          final logF = math.log(prevF) + (math.log(f) - math.log(prevF)) * t;
          return math.exp(logF);
        }
      }
      prevF = f;
      prevDelta = delta;
    }
    return null;
  }
}
