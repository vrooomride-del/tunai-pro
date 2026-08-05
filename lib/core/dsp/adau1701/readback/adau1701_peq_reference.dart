// MiUMAX ADAU1701 PEQ reference values for comparison — 4 outputs.
//
// All values are from MiUMAX screen capture, NOT guessed or extrapolated.
//
// Confidence tiers:
//   hardwareConfirmed — byte offset AND value confirmed by physical capture.
//   candidateMapping  — value read from MiUMAX screen; offset is stride-6
//                       structural candidate (not independently captured).
//   unknown           — frequency position identified; Gain/Q not yet captured.
//                       Placeholder 0.0 dB / Q1.0 stored but never shown
//                       as a real reference — excluded from match scoring.
//
// Read-only — no write, BLE, or deploy logic.

enum DataConfidence {
  hardwareConfirmed,
  candidateMapping,
  unknown;

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
  // Bands 1–9: values from MiUMAX screen; offsets are stride-6 candidates.
  static const List<PeqBandReference> ch0Bands = [
    PeqBandReference(frequencyHz:  1800, gainDb:  0.0, q: 1.2, confidence: DataConfidence.hardwareConfirmed),
    PeqBandReference(frequencyHz:  2500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  3300, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  4500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  6500, gainDb:  0.0, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  8500, gainDb:  0.0, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 11000, gainDb: -0.8, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 14500, gainDb: -0.3, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 18000, gainDb:  0.0, q: 0.7, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 20000, gainDb:  0.0, q: 0.7, confidence: DataConfidence.candidateMapping),
  ];

  // ── Ch1: Tweeter R (DAC1) ─────────────────────────────────────────────────
  // Same EQ settings as Tweeter L. All candidateMapping — Ch1 channel base
  // offset (0x2202 payload stride-60 candidate) not yet hardware-confirmed.
  static const List<PeqBandReference> ch1Bands = [
    PeqBandReference(frequencyHz:  1800, gainDb:  0.0, q: 1.2, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  2500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  3300, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  4500, gainDb:  0.0, q: 1.0, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  6500, gainDb:  0.0, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz:  8500, gainDb:  0.0, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 11000, gainDb: -0.8, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 14500, gainDb: -0.3, q: 0.8, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 18000, gainDb:  0.0, q: 0.7, confidence: DataConfidence.candidateMapping),
    PeqBandReference(frequencyHz: 20000, gainDb:  0.0, q: 0.7, confidence: DataConfidence.candidateMapping),
  ];

  // ── Ch2: Woofer L (DAC2) ─────────────────────────────────────────────────
  // Frequency positions identified from MiUMAX screen.
  // Gain/Q not yet captured → confidence: unknown.
  // gainDb/q are placeholder values — NEVER used for display or match scoring.
  static const List<PeqBandReference> ch2Bands = [
    PeqBandReference(frequencyHz:   60, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
    PeqBandReference(frequencyHz:  120, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
    PeqBandReference(frequencyHz:  220, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
    PeqBandReference(frequencyHz:  350, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
    PeqBandReference(frequencyHz:  550, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
    PeqBandReference(frequencyHz:  750, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
    PeqBandReference(frequencyHz: 1200, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
    PeqBandReference(frequencyHz: 1800, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
    PeqBandReference(frequencyHz: 2400, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
    PeqBandReference(frequencyHz: 3500, gainDb: 0.0, q: 1.0, confidence: DataConfidence.unknown),
  ];

  // ── Ch3: Woofer R (DAC3) ─────────────────────────────────────────────────
  // Same frequency positions as Woofer L; Gain/Q not yet captured.
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
