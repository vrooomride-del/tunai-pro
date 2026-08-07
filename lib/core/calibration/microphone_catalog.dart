// ── TUNAI PRO Phase 3-C — Supported microphone catalog ─────────────────────
//
// Metadata-only reference list. Deliberately kept SEPARATE from any
// [CalibrationCurve] — a [SupportedMicrophoneDescriptor] never carries a
// curve, checksum, or sensitivity value, because model metadata is never
// calibration evidence. Selecting a catalog entry only pre-fills a new
// [MeasurementMicrophoneProfile]'s manufacturer/model/connectionType; the
// resulting profile still starts as [CalibrationSource.uncalibrated] with a
// null [MeasurementMicrophoneProfile.calibrationCurve] until the user
// actually imports a real calibration file through
// [CalibrationFileParser] — this file cannot make anything "calibrated" by
// itself.
//
// Hardcoded as a small `const` list for this phase. Every field is plain
// data (no behavior), so a future phase can move this list to a bundled
// JSON/asset resource without changing any call site's shape — only the
// loader.
library;

/// Which mic-direction angles a model's published calibration data (if any)
/// is commonly available for. Advisory only — the actual angle a particular
/// imported file covers always comes from that file's own parsed metadata,
/// never from this catalog.
enum SupportedMicOrientation {
  zeroDegree,
  ninetyDegree;

  String get label => this == SupportedMicOrientation.zeroDegree ? '0°' : '90°';
}

/// A reference entry describing a microphone MODEL — never an individual
/// unit, never a calibration curve. See file-level doc for the calibration
/// boundary this type must never cross.
class SupportedMicrophoneDescriptor {
  final String id;
  final String manufacturer;
  final String model;
  final String connectionType;

  /// True when genuine accuracy requires a calibration file tied to the
  /// individual physical unit (serial-specific), not just the model — e.g.
  /// most measurement mics ship with a per-unit calibration file/QR code.
  final bool requiresSerialCalibration;

  /// True when this model cannot be meaningfully used without SOME
  /// calibration file (even a generic model-average one) — as opposed to a
  /// mic that is reasonably flat/usable uncalibrated.
  final bool calibrationFileRequired;

  final List<SupportedMicOrientation> supportedOrientations;
  final SupportedMicOrientation recommendedOrientation;

  /// Short user-facing guidance, e.g. where to find the mic's calibration
  /// file. Never contains a URL to auto-fetch from — Phase 3-C never
  /// downloads calibration data.
  final String notes;

  /// Optional hint about the calibration file format this model's
  /// manufacturer typically ships (e.g. "two-column Hz/dB text, comma or
  /// whitespace separated") — informational only, never used to alter
  /// parsing behavior; [CalibrationFileParser] is format-agnostic already.
  final String? officialProfileFormatHint;

  const SupportedMicrophoneDescriptor({
    required this.id,
    required this.manufacturer,
    required this.model,
    required this.connectionType,
    required this.requiresSerialCalibration,
    required this.calibrationFileRequired,
    required this.supportedOrientations,
    required this.recommendedOrientation,
    required this.notes,
    this.officialProfileFormatHint,
  });
}

/// Minimal reference list — not exhaustive, not a product endorsement list.
/// Adding/removing/renaming an entry here never affects any already-saved
/// [MeasurementMicrophoneProfile] (those store their own manufacturer/model
/// strings directly, copied at creation time, not a reference to this list).
const List<SupportedMicrophoneDescriptor> kSupportedMicrophoneCatalog = [
  SupportedMicrophoneDescriptor(
    id: 'umik-1',
    manufacturer: 'miniDSP',
    model: 'UMIK-1',
    connectionType: 'USB',
    requiresSerialCalibration: true,
    calibrationFileRequired: true,
    supportedOrientations: [
      SupportedMicOrientation.zeroDegree,
      SupportedMicOrientation.ninetyDegree,
    ],
    recommendedOrientation: SupportedMicOrientation.zeroDegree,
    notes: 'Ships with a per-unit calibration file keyed to its serial number '
        '— import that file for this exact microphone; a generic/other '
        "unit's file will not be accurate.",
    officialProfileFormatHint: 'Two-column Hz / dB text file per serial.',
  ),
  SupportedMicrophoneDescriptor(
    id: 'umik-2',
    manufacturer: 'miniDSP',
    model: 'UMIK-2',
    connectionType: 'USB',
    requiresSerialCalibration: true,
    calibrationFileRequired: true,
    supportedOrientations: [
      SupportedMicOrientation.zeroDegree,
      SupportedMicOrientation.ninetyDegree,
    ],
    recommendedOrientation: SupportedMicOrientation.zeroDegree,
    notes: 'Ships with a per-unit calibration file keyed to its serial number '
        '— import that file for this exact microphone.',
    officialProfileFormatHint: 'Two-column Hz / dB text file per serial.',
  ),
  SupportedMicrophoneDescriptor(
    id: 'generic-electret-usb',
    manufacturer: 'Generic',
    model: 'Electret USB Measurement Mic',
    connectionType: 'USB',
    requiresSerialCalibration: false,
    calibrationFileRequired: false,
    supportedOrientations: [SupportedMicOrientation.zeroDegree],
    recommendedOrientation: SupportedMicOrientation.zeroDegree,
    notes: 'No individual calibration file exists for this class of mic — it '
        'can be used uncalibrated, or with a model-average correction file '
        'if one is imported manually.',
  ),
];
