// MiUMAX ADAU1701 PEQ reference values for comparison — 4 outputs.
//
// All values are from MiUMAX screen capture or ICP5 USB hardware readback.
// No values are guessed or extrapolated.
//
// Confidence tiers:
//   hardwareConfirmed — byte offset AND value confirmed by physical capture.
//   candidateMapping  — value read from hardware or MiUMAX screen; offset is
//                       stride-6/stride-83 structural candidate (not fully
//                       independently captured by separate hex comparison).
//
// Read-only — no write, BLE, or deploy logic.

enum DataConfidence {
  hardwareConfirmed,
  candidateMapping,
  unknown; // reserved for future use; no current bands use this tier

  String get label => switch (this) {
        DataConfidence.hardwareConfirmed => 'Hardware Confirmed',
        DataConfidence.candidateMapping => 'Candidate Mapping',
        DataConfidence.unknown => 'Unknown',
      };
}

class PeqBandReference {
  final int frequencyHz;

  // Placeholder 0.0 dB when confidence == unknown — do NOT display or compare.
  final double gainDb;

  // Placeholder 1.0 when confidence == unknown — do NOT display or compare.
  final double q;

  final DataConfidence confidence;

  const PeqBandReference({
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.confidence,
  });
}

abstract final class Adau1701MiuMaxPeqReference {
  // ── Ch0: Tweeter L (DAC0) ─────────────────────────────────────────────────
  // Band 0 (1800 Hz / 0.0 dB / Q1.2): hardware-confirmed by physical capture.
  // Bands 1–9: values from ICP5 USB readback (stride-6 offset candidates).
  //   Band 2 gain=1.0 dB, Band 5–6 Q=1.0 confirmed by hardware readback.
  static const List<PeqBandReference> ch0Bands = [
    PeqBandReference(frequencyHz:  1800, gainDb:  0.0, q: 1.2, confidence: DataConfidence.hardwareConfirmed),
    PeqBandReference(frequencyHz:  2500, gainDb:  1.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  3300, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  4500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  6500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  8500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 11000, gainDb: -0.8, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 14500, gainDb: -0.3, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 18000, gainDb:  0.0, q: 0.7, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 20000, gainDb:  0.0, q: 0.7, confidence: DataConfidence.candidateMapping),
  ];

  // ── Ch1: Tweeter R (DAC1) ─────────────────────────────────────────────────
  // All candidateMapping — Ch1 channel base offset (stride-83, offset 102)
  // confirmed by frequency match; full independent hex capture pending.
  // Band 5–6 Q=1.0 confirmed by ICP5 USB readback.
  // Band 2 gain=0.0 dB (Tweeter R differs from Tweeter L's 1.0 dB on Band 2).
  static const List<PeqBandReference> ch1Bands = [
    PeqBandReference(frequencyHz:  1800, gainDb:  0.0, q: 1.2, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  2500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  3300, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  4500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  6500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  8500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 11000, gainDb: -0.8, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 14500, gainDb: -0.3, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 18000, gainDb:  0.0, q: 0.7, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 20000, gainDb:  0.0, q: 0.7, confidence: DataConfidence.candidateMapping),
  ];

  // ── Ch2: Woofer L (DAC2) ─────────────────────────────────────────────────
  // Gain/Q confirmed by ICP5 USB readback at stride-83 offset 185.
  // Frequency positions confirmed; channel layout pending full hex capture.
  static const List<PeqBandReference> ch2Bands = [
    PeqBandReference(frequencyHz:   60, gainDb: 0.5, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  120, gainDb: 0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  220, gainDb: 0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  350, gainDb: 0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  550, gainDb: 0.0, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  750, gainDb: 0.0, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 1200, gainDb: 0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 1800, gainDb: 0.0, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 2400, gainDb: 0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 3500, gainDb: 0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
  ];

  // ── Ch3: Woofer R (DAC3) ─────────────────────────────────────────────────
  // Same values as Woofer L — ICP5 USB readback at offset 268 confirms match.
  static const List<PeqBandReference> ch3Bands = ch2Bands;

  // Returns reference bands for the given 0-based output channel.
  // All 4 channels now have reference data (Woofer uses DataConfidence.unknown
  // for Gain/Q — those bands are excluded from match scoring).
  static List<PeqBandReference>? forChannel(int channelIndex) {
    return switch (channelIndex) {
      0 => ch0Bands,
      1 => ch1Bands,
      2 => ch2Bands,
      3 => ch3Bands,
      _ => null,
    };
  }
}
