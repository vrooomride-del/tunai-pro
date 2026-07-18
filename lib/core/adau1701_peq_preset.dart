import 'adau1701_peq_response.dart';

/// Global user voicing presets for the ADAU1701 PEQ editor.
///
/// These modify only the PEQ editing MODEL (a bank of [PeqResponseBand]s) before
/// Apply. They are NOT output-specific DSP calibration and perform no DSP write,
/// transport, or address/mapping change. Values are conservative starting points
/// (≤ ±3 dB, Q 0.7–2.0) to be refined later after measurement/listening tests.
enum Adau1701PeqPreset {
  flat,
  neutral,
  warm,
  studioMonitor,

  /// Derived state: the model no longer matches any preset (user has edited it).
  custom;

  String get label => switch (this) {
        Adau1701PeqPreset.flat => 'Flat',
        Adau1701PeqPreset.neutral => 'Neutral',
        Adau1701PeqPreset.warm => 'Warm',
        Adau1701PeqPreset.studioMonitor => 'Studio Monitor',
        Adau1701PeqPreset.custom => 'Custom',
      };

  /// True for presets that define a concrete band curve (everything but custom).
  bool get hasCurve => this != Adau1701PeqPreset.custom;
}

abstract final class Adau1701PeqPresets {
  /// Fixed PEQ slot count per output.
  static const int bandCount = 10;

  /// Presets a user can pick to apply a curve. [Adau1701PeqPreset.custom] is
  /// derived from manual edits and is not directly applicable.
  static const List<Adau1701PeqPreset> selectable = [
    Adau1701PeqPreset.flat,
    Adau1701PeqPreset.neutral,
    Adau1701PeqPreset.warm,
    Adau1701PeqPreset.studioMonitor,
  ];

  /// The 10 fixed-slot bands for [preset]. Conservative voicing framework —
  /// gains within ~±3 dB, Q in 0.7–2.0, unused slots disabled. Model/UI only.
  /// Throws for [Adau1701PeqPreset.custom] (it has no fixed curve).
  static List<PeqResponseBand> bandsFor(Adau1701PeqPreset preset) {
    switch (preset) {
      case Adau1701PeqPreset.flat:
        // All bands disabled / 0 dB.
        return _fill(const []);
      case Adau1701PeqPreset.neutral:
        // Very subtle correction, close to flat.
        return _fill(const [
          PeqResponseBand(
              frequencyHz: 3500, gainDb: -0.5, q: 1.0, enabled: true),
        ]);
      case Adau1701PeqPreset.warm:
        // Gentle low-frequency enhancement + smooth upper-treble reduction.
        return _fill(const [
          PeqResponseBand(frequencyHz: 90, gainDb: 2.0, q: 0.7, enabled: true),
          PeqResponseBand(
              frequencyHz: 250, gainDb: 1.0, q: 0.9, enabled: true),
          PeqResponseBand(
              frequencyHz: 9000, gainDb: -2.0, q: 0.8, enabled: true),
        ]);
      case Adau1701PeqPreset.studioMonitor:
        // Balanced analytical voicing with slightly increased presence/air.
        return _fill(const [
          PeqResponseBand(
              frequencyHz: 200, gainDb: -0.5, q: 1.0, enabled: true),
          PeqResponseBand(
              frequencyHz: 3000, gainDb: 1.0, q: 1.2, enabled: true),
          PeqResponseBand(
              frequencyHz: 12000, gainDb: 1.5, q: 0.9, enabled: true),
        ]);
      case Adau1701PeqPreset.custom:
        throw ArgumentError('Adau1701PeqPreset.custom has no fixed curve.');
    }
  }

  /// Pads [active] with disabled slots to exactly [bandCount].
  static List<PeqResponseBand> _fill(List<PeqResponseBand> active) => [
        ...active,
        for (var i = active.length; i < bandCount; i++)
          const PeqResponseBand(
              frequencyHz: 1000, gainDb: 0, q: 1.0, enabled: false),
      ];
}
