// ── TUNAI PRO Phase 3-B — Measurement Microphone Calibration: typed core ──
//
// Data layer only. No file I/O, no DSP write, no UI. Separate module from
// FRD/ZMA (lib/core/frd_parser.dart, lib/core/pro_measurement_parser.dart) —
// a calibration curve is a microphone correction, never a driver response;
// the two must never be parsed or applied by the same code path.
//
// This phase does NOT hardcode any built-in microphone catalog and does NOT
// fabricate a default "calibrated" profile — CalibrationSource.uncalibrated
// plus CalibrationStatus.explicitlyUncalibrated is the only allowed default
// when nothing has been selected.

import 'dart:convert';
import 'package:crypto/crypto.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

/// The orientation a calibration curve was measured at. Free-field
/// measurement mic calibration is commonly published for one or both of
/// these angles; [unspecified] covers curves (or legacy data) that don't
/// declare one.
enum CalibrationAngle {
  zeroDegree,
  ninetyDegree,
  unspecified;

  String get label => switch (this) {
        CalibrationAngle.zeroDegree => '0°',
        CalibrationAngle.ninetyDegree => '90°',
        CalibrationAngle.unspecified => 'Unspecified',
      };

  String toJson() => name;
  static CalibrationAngle fromJson(String s) =>
      CalibrationAngle.values.firstWhere((e) => e.name == s,
          orElse: () => CalibrationAngle.unspecified);
}

/// Where a calibration curve/profile came from. [uncalibrated] is the only
/// value that may be used as a default — every other value requires an
/// actual curve to have been supplied.
enum CalibrationSource {
  builtIn,
  manufacturerFile,
  tunaiSerialProfile,
  userImported,
  uncalibrated;

  String toJson() => name;
  static CalibrationSource fromJson(String s) =>
      CalibrationSource.values.firstWhere((e) => e.name == s,
          orElse: () => CalibrationSource.uncalibrated);
}

/// How a [CalibrationCurve] is interpolated between declared points. Only one
/// policy exists today; the enum (rather than a hardcoded algorithm) exists
/// so a future policy can be added without changing every call site.
enum CalibrationInterpolationPolicy {
  /// x-axis is log10(frequencyHz), y-axis (correctionDb) is linearly
  /// interpolated between the two bracketing points on that log axis.
  /// Never extrapolated — frequencies outside [CalibrationCurve.validMinFrequencyHz,
  /// validMaxFrequencyHz] are always a coverage miss, never clamped.
  logFrequencyLinearDb;

  String toJson() => name;
  static CalibrationInterpolationPolicy fromJson(String s) =>
      CalibrationInterpolationPolicy.values.firstWhere((e) => e.name == s,
          orElse: () => CalibrationInterpolationPolicy.logFrequencyLinearDb);
}

/// Whether — and how completely — a measurement's frequency range is backed
/// by an actual calibration curve. NEVER inferred as [calibrated] by default;
/// callers must prove it with real coverage.
enum CalibrationStatus {
  /// Every point in the measurement's frequency range fell within the
  /// curve's valid range and was corrected.
  calibrated,

  /// Some, but not all, of the measurement's frequency range was covered by
  /// the curve. Never treated as fully [calibrated] anywhere downstream.
  partiallyCalibrated,

  /// The user/caller explicitly chose to measure without any calibration —
  /// a deliberate, known state, distinct from not having decided yet.
  explicitlyUncalibrated,

  /// Persisted data from before this schema existed, or from a decode where
  /// calibration provenance could not be recovered. Never assumed calibrated.
  legacyUnknown,

  /// A calibration curve or snapshot failed validation (NaN/Infinity,
  /// insufficient points, checksum mismatch, etc.) and must not be applied
  /// or trusted.
  invalid;

  String toJson() => name;
  static CalibrationStatus fromJson(String s) =>
      CalibrationStatus.values.firstWhere((e) => e.name == s,
          orElse: () => CalibrationStatus.legacyUnknown);
}

// ── Sanity-bound policy constants ───────────────────────────────────────────
//
// Named, single-source constants — never re-literaled in the parser,
// applicator, or elsewhere. Chosen conservatively wide: real free-field
// measurement-mic calibration curves for the audible range rarely exceed
// +/-10 dB even at the frequency extremes (large diaphragm proximity/
// diffraction effects), so +/-20 dB comfortably covers genuine calibration
// data while still catching an obviously wrong file (e.g. raw SPL values
// accidentally parsed as a correction delta, which routinely reach 80-100 dB).

/// A single calibration point's |correctionDb| must not exceed this to be
/// considered a plausible microphone correction value.
const double kCalibrationMaxAbsCorrectionDb = 20.0;

/// A calibration curve's declared valid frequency range must sit within this
/// bound — matches the audible-adjacent range every other acoustic policy in
/// this codebase already uses (see MeasurementConfidencePolicy/
/// AcousticClassificationPolicy defaults).
const double kCalibrationMinPlausibleFrequencyHz = 1.0;
const double kCalibrationMaxPlausibleFrequencyHz = 200000.0;

// ── CalibrationPoint ──────────────────────────────────────────────────────────

class CalibrationPoint {
  final double frequencyHz;
  final double correctionDb;

  const CalibrationPoint({
    required this.frequencyHz,
    required this.correctionDb,
  });

  /// True only when both values are finite, frequency is strictly positive,
  /// and the correction is within [kCalibrationMaxAbsCorrectionDb].
  bool get isPlausible =>
      frequencyHz.isFinite &&
      correctionDb.isFinite &&
      frequencyHz > 0 &&
      correctionDb.abs() <= kCalibrationMaxAbsCorrectionDb;

  Map<String, dynamic> toJson() => {
        'frequencyHz': frequencyHz,
        'correctionDb': correctionDb,
      };

  factory CalibrationPoint.fromJson(Map<String, dynamic> j) => CalibrationPoint(
        frequencyHz: (j['frequencyHz'] as num).toDouble(),
        correctionDb: (j['correctionDb'] as num).toDouble(),
      );
}

// ── CalibrationCurve ──────────────────────────────────────────────────────────

/// An immutable, validated microphone calibration curve. Construct only via
/// [CalibrationFileParser] (lib/core/calibration/calibration_parser.dart) in
/// production — the plain constructor here performs no validation itself so
/// tests can build fixtures directly, but nothing in this codebase should
/// call it with unvalidated/untrusted data outside a test.
class CalibrationCurve {
  /// Ascending-sorted by frequencyHz, no duplicate frequencies. Immutable —
  /// never mutated after construction.
  final List<CalibrationPoint> points;
  final CalibrationAngle angle;
  final double validMinFrequencyHz;
  final double validMaxFrequencyHz;

  /// Free-form identity of where this curve came from (e.g. a filename or a
  /// profile id) — display/audit only, never parsed for meaning.
  final String sourceIdentity;

  /// sha256 of the canonical point list — see [CalibrationCurve.checksumFor].
  /// Used to detect a curve changing out from under a stored snapshot and to
  /// match a stored profile's checksum against what was actually applied.
  final String checksum;

  final CalibrationInterpolationPolicy interpolationPolicy;

  /// Non-fatal parser warnings (duplicate-identical collapse, skipped rows,
  /// etc.) carried alongside the curve for provenance/audit display.
  final List<String> parserWarnings;

  const CalibrationCurve({
    required this.points,
    this.angle = CalibrationAngle.unspecified,
    required this.validMinFrequencyHz,
    required this.validMaxFrequencyHz,
    required this.sourceIdentity,
    required this.checksum,
    this.interpolationPolicy =
        CalibrationInterpolationPolicy.logFrequencyLinearDb,
    this.parserWarnings = const [],
  });

  /// Structural validity, independent of how the curve was constructed:
  /// ascending-sorted, no duplicate/non-finite/implausible points, a real
  /// (non-degenerate) frequency range, and at least 2 points — a
  /// single-point curve cannot be interpolated and is rejected.
  bool get isStructurallyValid {
    if (points.length < 2) return false;
    if (!validMinFrequencyHz.isFinite ||
        !validMaxFrequencyHz.isFinite ||
        validMinFrequencyHz <= 0 ||
        validMaxFrequencyHz <= validMinFrequencyHz) {
      return false;
    }
    for (var i = 0; i < points.length; i++) {
      if (!points[i].isPlausible) return false;
      if (i > 0 && points[i].frequencyHz <= points[i - 1].frequencyHz) {
        return false; // not strictly ascending / duplicate frequency
      }
    }
    return true;
  }

  static String checksumFor(List<CalibrationPoint> sortedPoints) {
    final canonical = sortedPoints
        .map((p) =>
            '${p.frequencyHz.toStringAsFixed(6)}:${p.correctionDb.toStringAsFixed(6)}')
        .join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => p.toJson()).toList(),
        'angle': angle.toJson(),
        'validMinFrequencyHz': validMinFrequencyHz,
        'validMaxFrequencyHz': validMaxFrequencyHz,
        'sourceIdentity': sourceIdentity,
        'checksum': checksum,
        'interpolationPolicy': interpolationPolicy.toJson(),
        if (parserWarnings.isNotEmpty) 'parserWarnings': parserWarnings,
      };

  factory CalibrationCurve.fromJson(Map<String, dynamic> j) => CalibrationCurve(
        points: (j['points'] as List? ?? [])
            .map((e) =>
                CalibrationPoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        angle:
            CalibrationAngle.fromJson(j['angle'] as String? ?? 'unspecified'),
        validMinFrequencyHz:
            (j['validMinFrequencyHz'] as num?)?.toDouble() ?? 0.0,
        validMaxFrequencyHz:
            (j['validMaxFrequencyHz'] as num?)?.toDouble() ?? 0.0,
        sourceIdentity: j['sourceIdentity'] as String? ?? '',
        checksum: j['checksum'] as String? ?? '',
        interpolationPolicy: CalibrationInterpolationPolicy.fromJson(
            j['interpolationPolicy'] as String? ?? 'logFrequencyLinearDb'),
        parserWarnings:
            (j['parserWarnings'] as List?)?.cast<String>() ?? const [],
      );
}

// ── MeasurementMicrophoneProfile ─────────────────────────────────────────────

/// A user-registered measurement microphone. No built-in catalog exists yet
/// (Phase 3-C) — every instance of this type in this phase is either
/// constructed directly in a test or left entirely unselected (null) in a
/// project. `connectionType`/`manufacturer`/`model` are free-form strings on
/// purpose: hardcoding a fixed set of supported brands/connections is
/// explicitly out of scope for this phase.
class MeasurementMicrophoneProfile {
  final String id;
  final String manufacturer;
  final String model;
  final String? serialNumber;
  final String connectionType;
  final String? inputDeviceId;
  final CalibrationSource calibrationSource;
  final CalibrationCurve? calibrationCurve;
  final double? sensitivityMvPa;
  final double? splReferenceDb;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MeasurementMicrophoneProfile({
    required this.id,
    required this.manufacturer,
    required this.model,
    this.serialNumber,
    required this.connectionType,
    this.inputDeviceId,
    required this.calibrationSource,
    this.calibrationCurve,
    this.sensitivityMvPa,
    this.splReferenceDb,
    required this.createdAt,
    required this.updatedAt,
  });

  /// A profile is only genuinely calibrated if its source says so AND it
  /// actually carries a curve — a mismatched combination (e.g. source ==
  /// manufacturerFile but calibrationCurve == null) must never be treated as
  /// calibrated by any caller.
  bool get hasUsableCalibration =>
      calibrationSource != CalibrationSource.uncalibrated &&
      calibrationCurve != null;

  MeasurementMicrophoneProfile copyWith({
    String? manufacturer,
    String? model,
    String? serialNumber,
    bool clearSerialNumber = false,
    String? connectionType,
    String? inputDeviceId,
    bool clearInputDeviceId = false,
    CalibrationSource? calibrationSource,
    CalibrationCurve? calibrationCurve,
    bool clearCalibrationCurve = false,
    double? sensitivityMvPa,
    double? splReferenceDb,
    DateTime? updatedAt,
  }) =>
      MeasurementMicrophoneProfile(
        id: id,
        manufacturer: manufacturer ?? this.manufacturer,
        model: model ?? this.model,
        serialNumber:
            clearSerialNumber ? null : (serialNumber ?? this.serialNumber),
        connectionType: connectionType ?? this.connectionType,
        inputDeviceId:
            clearInputDeviceId ? null : (inputDeviceId ?? this.inputDeviceId),
        calibrationSource: calibrationSource ?? this.calibrationSource,
        calibrationCurve: clearCalibrationCurve
            ? null
            : (calibrationCurve ?? this.calibrationCurve),
        sensitivityMvPa: sensitivityMvPa ?? this.sensitivityMvPa,
        splReferenceDb: splReferenceDb ?? this.splReferenceDb,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// sha256 over every field that affects a measurement's meaning — used to
  /// detect drift between a snapshot taken at capture time and the profile's
  /// current (possibly since-edited) state. Deliberately excludes
  /// createdAt/updatedAt (bookkeeping only, not measurement-affecting).
  String get checksum {
    final canonical = [
      id,
      manufacturer,
      model,
      serialNumber ?? '',
      connectionType,
      inputDeviceId ?? '',
      calibrationSource.name,
      calibrationCurve?.checksum ?? '',
      sensitivityMvPa?.toStringAsFixed(6) ?? '',
      splReferenceDb?.toStringAsFixed(6) ?? '',
    ].join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'manufacturer': manufacturer,
        'model': model,
        if (serialNumber != null) 'serialNumber': serialNumber,
        'connectionType': connectionType,
        if (inputDeviceId != null) 'inputDeviceId': inputDeviceId,
        'calibrationSource': calibrationSource.toJson(),
        if (calibrationCurve != null)
          'calibrationCurve': calibrationCurve!.toJson(),
        if (sensitivityMvPa != null) 'sensitivityMvPa': sensitivityMvPa,
        if (splReferenceDb != null) 'splReferenceDb': splReferenceDb,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MeasurementMicrophoneProfile.fromJson(Map<String, dynamic> j) =>
      MeasurementMicrophoneProfile(
        id: j['id'] as String,
        manufacturer: j['manufacturer'] as String? ?? '',
        model: j['model'] as String? ?? '',
        serialNumber: j['serialNumber'] as String?,
        connectionType: j['connectionType'] as String? ?? '',
        inputDeviceId: j['inputDeviceId'] as String?,
        calibrationSource: CalibrationSource.fromJson(
            j['calibrationSource'] as String? ?? 'uncalibrated'),
        calibrationCurve: j['calibrationCurve'] != null
            ? CalibrationCurve.fromJson(
                Map<String, dynamic>.from(j['calibrationCurve'] as Map))
            : null,
        sensitivityMvPa: (j['sensitivityMvPa'] as num?)?.toDouble(),
        splReferenceDb: (j['splReferenceDb'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

// ── MeasurementMicrophoneSnapshot ────────────────────────────────────────────

/// An immutable copy of a [MeasurementMicrophoneProfile] taken at the moment
/// a measurement was captured. Embeds the actual calibration curve (not just
/// a reference) so a later edit — or deletion — of the live profile can
/// never change what a past measurement means.
class MeasurementMicrophoneSnapshot {
  final String profileId;
  final String profileChecksum;
  final String manufacturer;
  final String model;
  final String? serialNumber;
  final CalibrationSource calibrationSource;
  final CalibrationCurve? calibrationCurve;
  final CalibrationAngle orientation;
  final String? inputDeviceId;
  final int sampleRate;
  final DateTime capturedAt;

  const MeasurementMicrophoneSnapshot({
    required this.profileId,
    required this.profileChecksum,
    required this.manufacturer,
    required this.model,
    this.serialNumber,
    required this.calibrationSource,
    this.calibrationCurve,
    this.orientation = CalibrationAngle.unspecified,
    this.inputDeviceId,
    required this.sampleRate,
    required this.capturedAt,
  });

  factory MeasurementMicrophoneSnapshot.of(
    MeasurementMicrophoneProfile profile, {
    required int sampleRate,
    CalibrationAngle? orientationOverride,
    DateTime? capturedAt,
  }) =>
      MeasurementMicrophoneSnapshot(
        profileId: profile.id,
        profileChecksum: profile.checksum,
        manufacturer: profile.manufacturer,
        model: profile.model,
        serialNumber: profile.serialNumber,
        calibrationSource: profile.calibrationSource,
        calibrationCurve: profile.calibrationCurve,
        orientation: orientationOverride ??
            profile.calibrationCurve?.angle ??
            CalibrationAngle.unspecified,
        inputDeviceId: profile.inputDeviceId,
        sampleRate: sampleRate,
        capturedAt: capturedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'profileId': profileId,
        'profileChecksum': profileChecksum,
        'manufacturer': manufacturer,
        'model': model,
        if (serialNumber != null) 'serialNumber': serialNumber,
        'calibrationSource': calibrationSource.toJson(),
        if (calibrationCurve != null)
          'calibrationCurve': calibrationCurve!.toJson(),
        'orientation': orientation.toJson(),
        if (inputDeviceId != null) 'inputDeviceId': inputDeviceId,
        'sampleRate': sampleRate,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory MeasurementMicrophoneSnapshot.fromJson(Map<String, dynamic> j) =>
      MeasurementMicrophoneSnapshot(
        profileId: j['profileId'] as String? ?? '',
        profileChecksum: j['profileChecksum'] as String? ?? '',
        manufacturer: j['manufacturer'] as String? ?? '',
        model: j['model'] as String? ?? '',
        serialNumber: j['serialNumber'] as String?,
        calibrationSource: CalibrationSource.fromJson(
            j['calibrationSource'] as String? ?? 'uncalibrated'),
        calibrationCurve: j['calibrationCurve'] != null
            ? CalibrationCurve.fromJson(
                Map<String, dynamic>.from(j['calibrationCurve'] as Map))
            : null,
        orientation: CalibrationAngle.fromJson(
            j['orientation'] as String? ?? 'unspecified'),
        inputDeviceId: j['inputDeviceId'] as String?,
        sampleRate: j['sampleRate'] as int? ?? 48000,
        capturedAt: DateTime.tryParse(j['capturedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
