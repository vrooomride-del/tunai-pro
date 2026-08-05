// ADAU1701 DSP Comparison — display-only result models (4-output).
//
// Compares MiUMAX PEQ reference values against a live readback snapshot for
// all 4 outputs. Pure computation; never reads BLE, writes DSP, or modifies
// any project/state/transport object.
//
// Match tolerances:
//   Frequency: exact (integer Hz encoding, zero rounding).
//   Gain:      ±0.05 dB  (one-decimal encoding → max rounding 0.05 dB).
//   Q:         ±0.05     (same).
//
// Bands with DataConfidence.unknown are included in result lists for display
// (reference freq is shown) but excluded from match count and total-comparable
// via isComparable = false.

import 'adau1701_output_role.dart';
import 'adau1701_peq_reference.dart';
import 'adau1701_state_decoder.dart';

const int _kFreqToleranceHz = 0;
const double _kGainToleranceDb = 0.05;
const double _kQTolerance = 0.05;

class PeqBandComparisonResult {
  final int bandIndex;
  final PeqBandReference reference;
  final PeqBandState readback;

  // Signed difference: readback − reference.
  final int freqDiffHz;
  final double gainDiffDb;
  final double qDiff;

  final bool isMatch;

  // False when reference.confidence == DataConfidence.unknown (Gain/Q not
  // captured). Excluded from match count and match score percentage.
  final bool isComparable;

  const PeqBandComparisonResult({
    required this.bandIndex,
    required this.reference,
    required this.readback,
    required this.freqDiffHz,
    required this.gainDiffDb,
    required this.qDiff,
    required this.isMatch,
    required this.isComparable,
  });
}

class OutputComparisonResult {
  final int outputIndex;
  final Adau1701OutputRole role;

  // Non-null for all 4 channels (Woofer channels have unknown-confidence bands).
  // Null only when forChannel() returns null (channel index out of range).
  final List<PeqBandComparisonResult>? bandComparisons;

  bool get hasReference => bandComparisons != null;

  // True when at least one band has isComparable = true (Tweeter L/R).
  // False for Woofer L/R (all bands have confidence == unknown).
  bool get hasComparableReference =>
      bandComparisons != null &&
      bandComparisons!.any((b) => b.isComparable);

  // Counts only isComparable bands.
  int get matchCount =>
      bandComparisons?.where((b) => b.isComparable && b.isMatch).length ?? 0;
  int get totalComparable =>
      bandComparisons?.where((b) => b.isComparable).length ?? 0;

  // 0–100 over comparable bands only; 0 when no comparable bands exist.
  double get matchScorePercent =>
      totalComparable == 0 ? 0.0 : matchCount / totalComparable * 100.0;

  const OutputComparisonResult({
    required this.outputIndex,
    required this.role,
    required this.bandComparisons,
  });
}

class DspComparisonSummary {
  final List<OutputComparisonResult> outputs;

  const DspComparisonSummary({required this.outputs});

  // Aggregated across all 4 outputs (Woofer unknown bands excluded).
  int get totalComparableBands =>
      outputs.fold(0, (s, o) => s + o.totalComparable);
  int get matchedBands => outputs.fold(0, (s, o) => s + o.matchCount);

  double get matchScorePercent => totalComparableBands == 0
      ? 0.0
      : matchedBands / totalComparableBands * 100.0;
}

abstract final class Adau1701DspComparison {
  static DspComparisonSummary compare(Adau1701StateSnapshot snapshot) {
    final results = <OutputComparisonResult>[];

    for (var ch = 0; ch < snapshot.outputs.length; ch++) {
      final role = miuMaxOutputRoles[ch];
      final refs = Adau1701MiuMaxPeqReference.forChannel(ch);
      final readbackOutput = snapshot.outputs[ch];

      List<PeqBandComparisonResult>? comparisons;
      if (refs != null) {
        comparisons = [];
        final count = refs.length < readbackOutput.peqBands.length
            ? refs.length
            : readbackOutput.peqBands.length;
        for (var i = 0; i < count; i++) {
          final ref = refs[i];
          final rb = readbackOutput.peqBands[i];
          final freqDiff = rb.frequencyHz - ref.frequencyHz;
          final gainDiff = rb.gainDb - ref.gainDb;
          final qDiff = rb.q - ref.q;
          final isComparable = ref.confidence != DataConfidence.unknown;
          comparisons.add(PeqBandComparisonResult(
            bandIndex: i,
            reference: ref,
            readback: rb,
            freqDiffHz: freqDiff,
            gainDiffDb: gainDiff,
            qDiff: qDiff,
            isComparable: isComparable,
            // Non-comparable bands are never counted as matches.
            isMatch: isComparable &&
                freqDiff.abs() <= _kFreqToleranceHz &&
                gainDiff.abs() <= _kGainToleranceDb &&
                qDiff.abs() <= _kQTolerance,
          ));
        }
      }

      results.add(OutputComparisonResult(
        outputIndex: ch,
        role: role,
        bandComparisons: comparisons,
      ));
    }

    return DspComparisonSummary(outputs: results);
  }
}
