// ── TUNAI PRO Phase N — Acoustic Data Models ─────────────────────────────────
// Driver channels, FRD/ZMA file references, measurement status, target curve,
// parsed measurement data, acoustic offset. No DSP writes. No hardware access.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'calibration/calibration_types.dart';
import 'measurement/measurement_quality_snapshot.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum DriverRole {
  tweeter,
  midrange,
  woofer,
  coaxTweeter,
  coaxWoofer,
  subwoofer,
  fullrange,
  passiveRadiator,
  unknown;

  String get label => switch (this) {
        DriverRole.tweeter => 'Tweeter',
        DriverRole.midrange => 'Midrange',
        DriverRole.woofer => 'Woofer',
        DriverRole.coaxTweeter => 'Coax Tweeter',
        DriverRole.coaxWoofer => 'Coax Woofer',
        DriverRole.subwoofer => 'Subwoofer',
        DriverRole.fullrange => 'Full Range',
        DriverRole.passiveRadiator => 'Passive Radiator',
        DriverRole.unknown => 'Unknown',
      };

  String get short => switch (this) {
        DriverRole.tweeter => 'TW',
        DriverRole.midrange => 'MR',
        DriverRole.woofer => 'WF',
        DriverRole.coaxTweeter => 'CTW',
        DriverRole.coaxWoofer => 'CWF',
        DriverRole.subwoofer => 'SUB',
        DriverRole.fullrange => 'FR',
        DriverRole.passiveRadiator => 'PR',
        DriverRole.unknown => '?',
      };

  String toJson() => name;
  static DriverRole fromJson(String s) => DriverRole.values
      .firstWhere((e) => e.name == s, orElse: () => DriverRole.unknown);
}

enum DriverSide {
  left,
  right,
  mono,
  shared;

  String get label => switch (this) {
        DriverSide.left => 'L',
        DriverSide.right => 'R',
        DriverSide.mono => 'Mono',
        DriverSide.shared => 'Shared',
      };

  String toJson() => name;
  static DriverSide fromJson(String s) => DriverSide.values
      .firstWhere((e) => e.name == s, orElse: () => DriverSide.mono);
}

enum MeasurementStatus {
  empty,
  imported,
  validated,
  needsReview,
  missingFile;

  String get label => switch (this) {
        MeasurementStatus.empty => 'Empty',
        MeasurementStatus.imported => 'Imported',
        MeasurementStatus.validated => 'Validated',
        MeasurementStatus.needsReview => 'Needs Review',
        MeasurementStatus.missingFile => 'Missing File',
      };

  String toJson() => name;
  static MeasurementStatus fromJson(String s) => MeasurementStatus.values
      .firstWhere((e) => e.name == s, orElse: () => MeasurementStatus.empty);
}

class ListeningPositionFrdSet {
  final String positionId;
  final String label;
  final Map<String, ParsedMeasurementData> channels;
  const ListeningPositionFrdSet(
      {required this.positionId, required this.label, required this.channels});
  bool get isComplete => const ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r']
      .every(channels.containsKey);
  Map<String, dynamic> toJson() => {
        'positionId': positionId,
        'label': label,
        'channels': {for (final e in channels.entries) e.key: e.value.toJson()},
      };
  factory ListeningPositionFrdSet.fromJson(Map<String, dynamic> j) =>
      ListeningPositionFrdSet(
        positionId: j['positionId'] as String? ?? '',
        label: j['label'] as String? ?? j['positionId'] as String? ?? '',
        channels: {
          for (final e
              in Map<String, dynamic>.from(j['channels'] as Map? ?? {}).entries)
            e.key: ParsedMeasurementData.fromJson(
                Map<String, dynamic>.from(e.value as Map))
        },
      );
}

class ListeningPositionFrdInput {
  final String positionId;
  final String label;
  final Map<String, ParsedMeasurementData> _channels = {};
  ListeningPositionFrdInput({required this.positionId, required this.label});
  Map<String, ParsedMeasurementData> get channels =>
      Map.unmodifiable(_channels);
  void add({required String channelId, required ParsedMeasurementData frd}) {
    if (!const ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r']
        .contains(channelId)) {
      throw ArgumentError.value(channelId, 'channelId');
    }
    if (_channels.containsKey(channelId)) {
      throw StateError('Position FRD already loaded for $channelId.');
    }
    if (!frd.hasMagnitude) {
      throw StateError('Position FRD has no magnitude data.');
    }
    _channels[channelId] = frd;
  }

  ListeningPositionFrdSet build() {
    final result = ListeningPositionFrdSet(
        positionId: positionId, label: label, channels: channels);
    if (!result.isComplete) {
      throw StateError('All four position FRDs are required.');
    }
    return result;
  }
}

enum AcousticFileType {
  frd,
  zma,
  txt,
  csv,
  unknown;

  String get label => switch (this) {
        AcousticFileType.frd => '.frd',
        AcousticFileType.zma => '.zma',
        AcousticFileType.txt => '.txt',
        AcousticFileType.csv => '.csv',
        AcousticFileType.unknown => 'unknown',
      };

  static AcousticFileType fromExtension(String ext) {
    final lower = ext.toLowerCase().replaceFirst('.', '');
    return AcousticFileType.values.firstWhere(
      (e) => e.name == lower,
      orElse: () => AcousticFileType.unknown,
    );
  }

  String toJson() => name;
  static AcousticFileType fromJson(String s) => AcousticFileType.values
      .firstWhere((e) => e.name == s, orElse: () => AcousticFileType.unknown);
}

enum TargetCurvePreset {
  flat,
  studio,
  warm,
  nearfield,
  custom;

  String get label => switch (this) {
        TargetCurvePreset.flat => 'Flat',
        TargetCurvePreset.studio => 'Studio',
        TargetCurvePreset.warm => 'Warm',
        TargetCurvePreset.nearfield => 'Nearfield',
        TargetCurvePreset.custom => 'Custom',
      };

  String get description => switch (this) {
        TargetCurvePreset.flat =>
          '0 dB reference across the full frequency range.',
        TargetCurvePreset.studio =>
          'Slight high-frequency roll-off above 10 kHz. Professional mixing reference.',
        TargetCurvePreset.warm =>
          'Gentle bass lift (+2 dB shelf below 200 Hz). Relaxed listening target.',
        TargetCurvePreset.nearfield =>
          'Compensation for close-field monitoring. Elevated presence region.',
        TargetCurvePreset.custom =>
          'User-defined target curve. Specify manually or import from file.',
      };

  String toJson() => name;
  static TargetCurvePreset fromJson(String s) => TargetCurvePreset.values
      .firstWhere((e) => e.name == s, orElse: () => TargetCurvePreset.flat);
}

enum MeasurementParseStatus {
  notParsed,
  parsed,
  parsedWithWarnings,
  failed,
  unsupported;

  String get label => switch (this) {
        MeasurementParseStatus.notParsed => 'Not Parsed',
        MeasurementParseStatus.parsed => 'Parsed',
        MeasurementParseStatus.parsedWithWarnings => 'Parsed (Warnings)',
        MeasurementParseStatus.failed => 'Failed',
        MeasurementParseStatus.unsupported => 'Unsupported',
      };

  String toJson() => name;
  static MeasurementParseStatus fromJson(String s) =>
      MeasurementParseStatus.values.firstWhere((e) => e.name == s,
          orElse: () => MeasurementParseStatus.notParsed);
}

// ── Models ────────────────────────────────────────────────────────────────────

/// Single point from an FRD or ZMA file.
class MeasurementDataPoint {
  final double frequencyHz;
  final double? magnitudeDb;
  final double? phaseDeg;
  final double? impedanceOhm;
  final double? impedancePhaseDeg;

  const MeasurementDataPoint({
    required this.frequencyHz,
    this.magnitudeDb,
    this.phaseDeg,
    this.impedanceOhm,
    this.impedancePhaseDeg,
  });

  Map<String, dynamic> toJson() => {
        'f': frequencyHz,
        if (magnitudeDb != null) 'm': magnitudeDb,
        if (phaseDeg != null) 'p': phaseDeg,
        if (impedanceOhm != null) 'z': impedanceOhm,
        if (impedancePhaseDeg != null) 'zp': impedancePhaseDeg,
      };

  factory MeasurementDataPoint.fromJson(Map<String, dynamic> j) =>
      MeasurementDataPoint(
        frequencyHz: (j['f'] as num).toDouble(),
        magnitudeDb: (j['m'] as num?)?.toDouble(),
        phaseDeg: (j['p'] as num?)?.toDouble(),
        impedanceOhm: (j['z'] as num?)?.toDouble(),
        impedancePhaseDeg: (j['zp'] as num?)?.toDouble(),
      );
}

/// Phase 3-D3C — how a [ParsedMeasurementData] came to exist.
///
/// Explicit and stored, never inferred: a live Factory/Room capture and a
/// plain imported FRD are BOTH legitimate inputs but rest on different kinds
/// of evidence, and downstream (MeasurementEvidence, Guided AI confidence)
/// must not treat one as the other. Deliberately not derived from
/// `microphoneSnapshot != null` / `qualitySnapshot != null` / filename —
/// imported measurements may legitimately carry metadata too, so those are
/// not source discriminators.
enum MeasurementDataSource {
  /// Recorded by this app through the measurement chain (mic profile, input
  /// device, setup readiness, PCM quality analysis).
  liveCapture,

  /// Parsed from a user-supplied FRD/ZMA file.
  imported,

  /// Persisted before this field existed. Never assumed to be either — it is
  /// its own state, and consumers must not upgrade it to live-capture
  /// confidence.
  legacyUnknown;

  String toJson() => name;
  static MeasurementDataSource fromJson(String s) =>
      MeasurementDataSource.values.firstWhere((e) => e.name == s,
          orElse: () => MeasurementDataSource.legacyUnknown);
}

/// Fully parsed measurement data from a single FRD or ZMA file.
class ParsedMeasurementData {
  final String id;
  final String sourceFileName;
  final AcousticFileType fileType;
  final DateTime importedAt;

  /// The response consumers read today — calibrated when [calibrationStatus]
  /// is [CalibrationStatus.calibrated]/[CalibrationStatus.partiallyCalibrated],
  /// numerically identical to [rawPoints] otherwise. Field name/meaning is
  /// unchanged from before Phase 3-B — every existing reader keeps working.
  final List<MeasurementDataPoint> points;

  /// The response BEFORE calibration was applied — null only for data
  /// decoded from a pre-Phase-3-B project (see [effectiveRawPoints]).
  /// Never mutated once set; a fresh [CalibrationApplicationResult] always
  /// produces a new list.
  final List<MeasurementDataPoint>? rawPoints;

  /// The microphone/calibration configuration in effect AT CAPTURE TIME —
  /// an immutable copy, not a live reference. Null for imported files (no
  /// microphone was involved) or legacy data.
  final MeasurementMicrophoneSnapshot? microphoneSnapshot;

  /// Never assumed [CalibrationStatus.calibrated] by a default constructor
  /// value — callers must set this explicitly. Decoding legacy JSON (no
  /// field present) always yields [CalibrationStatus.legacyUnknown], never
  /// [CalibrationStatus.calibrated].
  final CalibrationStatus calibrationStatus;

  /// [CalibrationCurve.checksum] of the curve actually applied, when any.
  final String? calibrationCurveChecksum;

  final DateTime? calibrationAppliedAt;

  final String? warning;
  final String? notes;

  /// Phase 3-D3B — the capture-time provenance + setup-check quality record
  /// pinned by [MeasurementQualitySnapshotBuilder] at the moment THIS
  /// measurement was captured. Null for imported FRD/ZMA files (no capture
  /// ever happened) and for any measurement accepted before this field
  /// existed — a missing snapshot is "legacy/unknown quality provenance",
  /// never assumed Ready by any consumer.
  final MeasurementQualitySnapshot? qualitySnapshot;

  /// Phase 3-D3C — explicit provenance. Defaults to
  /// [MeasurementDataSource.legacyUnknown] so every already-persisted
  /// measurement decodes unchanged and is never silently promoted to
  /// live-capture provenance.
  final MeasurementDataSource source;

  const ParsedMeasurementData({
    required this.id,
    required this.sourceFileName,
    required this.fileType,
    required this.importedAt,
    required this.points,
    this.rawPoints,
    this.microphoneSnapshot,
    this.calibrationStatus = CalibrationStatus.legacyUnknown,
    this.calibrationCurveChecksum,
    this.calibrationAppliedAt,
    this.warning,
    this.notes,
    this.qualitySnapshot,
    this.source = MeasurementDataSource.legacyUnknown,
  });

  /// [rawPoints] when present, otherwise [points] — the legacy-decode
  /// fallback described in the Phase 3-B spec: a pre-existing project has no
  /// separately-stored raw response, so its only recorded response IS what
  /// "raw" means for it (status is [CalibrationStatus.legacyUnknown], so
  /// nothing downstream may treat it as calibrated regardless).
  List<MeasurementDataPoint> get effectiveRawPoints => rawPoints ?? points;

  double get minFrequencyHz => points.isEmpty
      ? 0
      : points.map((p) => p.frequencyHz).reduce((a, b) => a < b ? a : b);
  double get maxFrequencyHz => points.isEmpty
      ? 0
      : points.map((p) => p.frequencyHz).reduce((a, b) => a > b ? a : b);
  int get pointCount => points.length;
  bool get hasMagnitude => points.any((p) => p.magnitudeDb != null);
  bool get hasPhase => points.any((p) => p.phaseDeg != null);
  bool get hasImpedance => points.any((p) => p.impedanceOhm != null);

  String get freqRangeLabel {
    if (points.isEmpty) return '—';
    return '${_hzLabel(minFrequencyHz)} – ${_hzLabel(maxFrequencyHz)}';
  }

  static String _hzLabel(double v) => v >= 1000
      ? '${(v / 1000).toStringAsFixed(1)} kHz'
      : '${v.toStringAsFixed(0)} Hz';

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceFileName': sourceFileName,
        'fileType': fileType.toJson(),
        'importedAt': importedAt.toIso8601String(),
        'points': points.map((p) => p.toJson()).toList(),
        if (rawPoints != null)
          'rawPoints': rawPoints!.map((p) => p.toJson()).toList(),
        if (microphoneSnapshot != null)
          'microphoneSnapshot': microphoneSnapshot!.toJson(),
        'calibrationStatus': calibrationStatus.toJson(),
        if (calibrationCurveChecksum != null)
          'calibrationCurveChecksum': calibrationCurveChecksum,
        if (calibrationAppliedAt != null)
          'calibrationAppliedAt': calibrationAppliedAt!.toIso8601String(),
        if (warning != null) 'warning': warning,
        if (notes != null) 'notes': notes,
        if (qualitySnapshot != null)
          'qualitySnapshot': qualitySnapshot!.toJson(),
        'source': source.toJson(),
      };

  factory ParsedMeasurementData.fromJson(Map<String, dynamic> j) {
    final points = (j['points'] as List? ?? [])
        .map((e) =>
            MeasurementDataPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    // Item-resilient: a corrupt calibration-related field must not fail the
    // whole ParsedMeasurementData decode (which itself must not fail the
    // whole project decode) — each falls back to its safe default.
    List<MeasurementDataPoint>? rawPoints;
    try {
      final raw = j['rawPoints'];
      if (raw is List) {
        rawPoints = raw
            .map((e) => MeasurementDataPoint.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      rawPoints = null;
    }

    MeasurementMicrophoneSnapshot? microphoneSnapshot;
    try {
      final snap = j['microphoneSnapshot'];
      if (snap is Map) {
        microphoneSnapshot = MeasurementMicrophoneSnapshot.fromJson(
            Map<String, dynamic>.from(snap));
      }
    } catch (_) {
      microphoneSnapshot = null;
    }

    var calibrationStatus = CalibrationStatus.legacyUnknown;
    try {
      final raw = j['calibrationStatus'];
      if (raw is String) calibrationStatus = CalibrationStatus.fromJson(raw);
    } catch (_) {
      calibrationStatus = CalibrationStatus.legacyUnknown;
    }

    MeasurementQualitySnapshot? qualitySnapshot;
    try {
      final raw = j['qualitySnapshot'];
      if (raw is Map) {
        qualitySnapshot =
            MeasurementQualitySnapshot.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {
      qualitySnapshot = null;
    }

    return ParsedMeasurementData(
      id: j['id'] as String,
      sourceFileName: j['sourceFileName'] as String,
      fileType:
          AcousticFileType.fromJson(j['fileType'] as String? ?? 'unknown'),
      importedAt:
          DateTime.tryParse(j['importedAt'] as String? ?? '') ?? DateTime.now(),
      points: points,
      rawPoints: rawPoints,
      microphoneSnapshot: microphoneSnapshot,
      calibrationStatus: calibrationStatus,
      calibrationCurveChecksum: j['calibrationCurveChecksum'] as String?,
      calibrationAppliedAt: j['calibrationAppliedAt'] != null
          ? DateTime.tryParse(j['calibrationAppliedAt'] as String)
          : null,
      warning: j['warning'] as String?,
      notes: j['notes'] as String?,
      qualitySnapshot: qualitySnapshot,
      // Absent on every pre-3-D3C record -> legacyUnknown, never upgraded.
      source: MeasurementDataSource.fromJson(
          j['source'] as String? ?? MeasurementDataSource.legacyUnknown.name),
    );
  }
}

/// Result of parsing an FRD or ZMA file.
class MeasurementParseResult {
  final MeasurementParseStatus status;
  final ParsedMeasurementData? data;
  final List<String> warnings;
  final List<String> errors;
  final String summary;

  const MeasurementParseResult({
    required this.status,
    this.data,
    this.warnings = const [],
    this.errors = const [],
    required this.summary,
  });
}

/// Approximate 3-D position of a driver's acoustic center relative to a
/// reference point (e.g. listening axis). Used to compute path-length delay
/// for phase-aware summation. Values in millimetres. All fields optional.
class DriverAcousticOffset {
  final double xMm;
  final double yMm;
  final double zMm;
  final double? distanceMm;
  final String? notes;

  const DriverAcousticOffset({
    this.xMm = 0.0,
    this.yMm = 0.0,
    this.zMm = 0.0,
    this.distanceMm,
    this.notes,
  });

  /// Euclidean distance in mm from origin if distanceMm not explicitly set.
  double get effectiveDistanceMm =>
      distanceMm ?? _sqrt(xMm * xMm + yMm * yMm + zMm * zMm);

  /// One-way path delay in seconds: d[mm] / 1000 / 343 m/s.
  double get pathDelaySeconds => effectiveDistanceMm / 1000.0 / 343.0;

  static double _sqrt(double v) {
    if (v <= 0) return 0.0;
    return v < 1e-12
        ? 0.0
        : v == 0
            ? 0
            : _sqrtImpl(v);
  }

  static double _sqrtImpl(double v) {
    // Use iterative Newton for minimal dart:math dependency
    double x = v / 2;
    for (var i = 0; i < 32; i++) {
      final xn = (x + v / x) / 2;
      if ((xn - x).abs() < 1e-9) return xn;
      x = xn;
    }
    return x;
  }

  bool get isZero =>
      xMm == 0.0 && yMm == 0.0 && zMm == 0.0 && distanceMm == null;

  DriverAcousticOffset copyWith({
    double? xMm,
    double? yMm,
    double? zMm,
    double? distanceMm,
    String? notes,
  }) =>
      DriverAcousticOffset(
        xMm: xMm ?? this.xMm,
        yMm: yMm ?? this.yMm,
        zMm: zMm ?? this.zMm,
        distanceMm: distanceMm ?? this.distanceMm,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'xMm': xMm,
        'yMm': yMm,
        'zMm': zMm,
        if (distanceMm != null) 'distanceMm': distanceMm,
        if (notes != null) 'notes': notes,
      };

  factory DriverAcousticOffset.fromJson(Map<String, dynamic> j) =>
      DriverAcousticOffset(
        xMm: (j['xMm'] as num?)?.toDouble() ?? 0.0,
        yMm: (j['yMm'] as num?)?.toDouble() ?? 0.0,
        zMm: (j['zMm'] as num?)?.toDouble() ?? 0.0,
        distanceMm: (j['distanceMm'] as num?)?.toDouble(),
        notes: j['notes'] as String?,
      );
}

class AcousticFileRef {
  final String id;
  final String fileName;
  final String? filePath;
  final AcousticFileType type;
  final DateTime importedAt;
  final int? pointCount;
  final double? minFrequency;
  final double? maxFrequency;
  final String? notes;
  final MeasurementParseStatus parseStatus;
  final String? parsedDataId;

  const AcousticFileRef({
    required this.id,
    required this.fileName,
    this.filePath,
    required this.type,
    required this.importedAt,
    this.pointCount,
    this.minFrequency,
    this.maxFrequency,
    this.notes,
    this.parseStatus = MeasurementParseStatus.notParsed,
    this.parsedDataId,
  });

  String get freqRangeLabel {
    if (minFrequency == null || maxFrequency == null) return '—';
    return '${_hz(minFrequency!)} – ${_hz(maxFrequency!)}';
  }

  static String _hz(double v) => v >= 1000
      ? '${(v / 1000).toStringAsFixed(1)} kHz'
      : '${v.toStringAsFixed(0)} Hz';

  AcousticFileRef copyWith({
    MeasurementParseStatus? parseStatus,
    String? parsedDataId,
    int? pointCount,
    double? minFrequency,
    double? maxFrequency,
    String? notes,
  }) =>
      AcousticFileRef(
        id: id,
        fileName: fileName,
        filePath: filePath,
        type: type,
        importedAt: importedAt,
        pointCount: pointCount ?? this.pointCount,
        minFrequency: minFrequency ?? this.minFrequency,
        maxFrequency: maxFrequency ?? this.maxFrequency,
        notes: notes ?? this.notes,
        parseStatus: parseStatus ?? this.parseStatus,
        parsedDataId: parsedDataId ?? this.parsedDataId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        if (filePath != null) 'filePath': filePath,
        'type': type.toJson(),
        'importedAt': importedAt.toIso8601String(),
        if (pointCount != null) 'pointCount': pointCount,
        if (minFrequency != null) 'minFrequency': minFrequency,
        if (maxFrequency != null) 'maxFrequency': maxFrequency,
        if (notes != null) 'notes': notes,
        'parseStatus': parseStatus.toJson(),
        if (parsedDataId != null) 'parsedDataId': parsedDataId,
      };

  factory AcousticFileRef.fromJson(Map<String, dynamic> j) => AcousticFileRef(
        id: j['id'] as String,
        fileName: j['fileName'] as String,
        filePath: j['filePath'] as String?,
        type: AcousticFileType.fromJson(j['type'] as String? ?? 'unknown'),
        importedAt: DateTime.tryParse(j['importedAt'] as String? ?? '') ??
            DateTime.now(),
        pointCount: j['pointCount'] as int?,
        minFrequency: (j['minFrequency'] as num?)?.toDouble(),
        maxFrequency: (j['maxFrequency'] as num?)?.toDouble(),
        notes: j['notes'] as String?,
        parseStatus: MeasurementParseStatus.fromJson(
            j['parseStatus'] as String? ?? 'notParsed'),
        parsedDataId: j['parsedDataId'] as String?,
      );
}

/// One repeated FRD measurement sweep stored alongside the primary FRD.
///
/// Used to build a multi-sweep evidence set for repeatability scoring.
/// [contentHash] is sha256('measurement_import_content_v1|' + content) and
/// serves as the duplicate-detection key — two entries with the same hash are
/// not independent evidence and one is discarded.
class FrdSweepEntry {
  static const String contentHashPrefix = 'measurement_import_content_v1';

  final String fileName;
  final String content;
  final String contentHash;

  const FrdSweepEntry({
    required this.fileName,
    required this.content,
    required this.contentHash,
  });

  factory FrdSweepEntry.fromRawContent(String fileName, String content) {
    final hash =
        sha256.convert(utf8.encode('$contentHashPrefix|$content')).toString();
    return FrdSweepEntry(
        fileName: fileName, content: content, contentHash: hash);
  }

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'content': content,
        'contentHash': contentHash,
      };

  factory FrdSweepEntry.fromJson(Map<String, dynamic> j) => FrdSweepEntry(
        fileName: j['fileName'] as String,
        content: j['content'] as String,
        contentHash: j['contentHash'] as String,
      );
}

class DriverChannel {
  final String id;
  final String name;
  final DriverRole role;
  final DriverSide side;
  final int? dspOutputIndex;
  final bool enabled;
  final AcousticFileRef? frdFile;
  final AcousticFileRef? zmaFile;
  final MeasurementStatus measurementStatus;
  final String? notes;
  // Phase M: parsed data, stored inline per driver
  final ParsedMeasurementData? frdData;
  final ParsedMeasurementData? zmaData;
  // Phase N: acoustic offset (3-D position relative to reference axis)
  final DriverAcousticOffset? acousticOffset;
  // Phase O: repeated FRD sweeps for multi-sweep repeatability evidence
  final List<FrdSweepEntry> additionalFrdSweeps;

  const DriverChannel({
    required this.id,
    required this.name,
    required this.role,
    required this.side,
    this.dspOutputIndex,
    this.enabled = true,
    this.frdFile,
    this.zmaFile,
    this.measurementStatus = MeasurementStatus.empty,
    this.notes,
    this.frdData,
    this.zmaData,
    this.acousticOffset,
    this.additionalFrdSweeps = const [],
  });

  String get shortLabel => '${role.short} · ${side.label}';
  bool get hasFrd => frdFile != null;
  bool get hasZma => zmaFile != null;
  bool get hasParsedFrd => frdData != null;
  bool get hasParsedZma => zmaData != null;

  DriverChannel copyWith({
    String? name,
    DriverRole? role,
    DriverSide? side,
    int? dspOutputIndex,
    bool? enabled,
    AcousticFileRef? frdFile,
    bool clearFrd = false,
    AcousticFileRef? zmaFile,
    bool clearZma = false,
    MeasurementStatus? measurementStatus,
    String? notes,
    ParsedMeasurementData? frdData,
    bool clearFrdData = false,
    ParsedMeasurementData? zmaData,
    bool clearZmaData = false,
    DriverAcousticOffset? acousticOffset,
    bool clearAcousticOffset = false,
    List<FrdSweepEntry>? additionalFrdSweeps,
  }) =>
      DriverChannel(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        side: side ?? this.side,
        dspOutputIndex: dspOutputIndex ?? this.dspOutputIndex,
        enabled: enabled ?? this.enabled,
        frdFile: clearFrd ? null : (frdFile ?? this.frdFile),
        zmaFile: clearZma ? null : (zmaFile ?? this.zmaFile),
        measurementStatus: measurementStatus ?? this.measurementStatus,
        notes: notes ?? this.notes,
        frdData: clearFrdData ? null : (frdData ?? this.frdData),
        zmaData: clearZmaData ? null : (zmaData ?? this.zmaData),
        acousticOffset: clearAcousticOffset
            ? null
            : (acousticOffset ?? this.acousticOffset),
        additionalFrdSweeps: additionalFrdSweeps ?? this.additionalFrdSweeps,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.toJson(),
        'side': side.toJson(),
        if (dspOutputIndex != null) 'dspOutputIndex': dspOutputIndex,
        'enabled': enabled,
        if (frdFile != null) 'frdFile': frdFile!.toJson(),
        if (zmaFile != null) 'zmaFile': zmaFile!.toJson(),
        'measurementStatus': measurementStatus.toJson(),
        if (notes != null) 'notes': notes,
        if (frdData != null) 'frdData': frdData!.toJson(),
        if (zmaData != null) 'zmaData': zmaData!.toJson(),
        if (acousticOffset != null) 'acousticOffset': acousticOffset!.toJson(),
        if (additionalFrdSweeps.isNotEmpty)
          'additionalFrdSweeps': [
            for (final s in additionalFrdSweeps) s.toJson()
          ],
      };

  factory DriverChannel.fromJson(Map<String, dynamic> j) => DriverChannel(
        id: j['id'] as String,
        name: j['name'] as String,
        role: DriverRole.fromJson(j['role'] as String? ?? 'unknown'),
        side: DriverSide.fromJson(j['side'] as String? ?? 'mono'),
        dspOutputIndex: j['dspOutputIndex'] as int?,
        enabled: j['enabled'] as bool? ?? true,
        frdFile: j['frdFile'] != null
            ? AcousticFileRef.fromJson(
                Map<String, dynamic>.from(j['frdFile'] as Map))
            : null,
        zmaFile: j['zmaFile'] != null
            ? AcousticFileRef.fromJson(
                Map<String, dynamic>.from(j['zmaFile'] as Map))
            : null,
        measurementStatus: MeasurementStatus.fromJson(
            j['measurementStatus'] as String? ?? 'empty'),
        notes: j['notes'] as String?,
        frdData: j['frdData'] != null
            ? ParsedMeasurementData.fromJson(
                Map<String, dynamic>.from(j['frdData'] as Map))
            : null,
        zmaData: j['zmaData'] != null
            ? ParsedMeasurementData.fromJson(
                Map<String, dynamic>.from(j['zmaData'] as Map))
            : null,
        acousticOffset: j['acousticOffset'] != null
            ? DriverAcousticOffset.fromJson(
                Map<String, dynamic>.from(j['acousticOffset'] as Map))
            : null,
        additionalFrdSweeps: (j['additionalFrdSweeps'] as List?)
                ?.map((e) =>
                    FrdSweepEntry.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );
}

class TargetCurveState {
  final TargetCurvePreset selectedPreset;
  final String? customName;
  final String? notes;

  const TargetCurveState({
    this.selectedPreset = TargetCurvePreset.flat,
    this.customName,
    this.notes,
  });

  TargetCurveState copyWith({
    TargetCurvePreset? selectedPreset,
    String? customName,
    String? notes,
  }) =>
      TargetCurveState(
        selectedPreset: selectedPreset ?? this.selectedPreset,
        customName: customName ?? this.customName,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'selectedPreset': selectedPreset.toJson(),
        if (customName != null) 'customName': customName,
        if (notes != null) 'notes': notes,
      };

  factory TargetCurveState.fromJson(Map<String, dynamic> j) => TargetCurveState(
        selectedPreset: TargetCurvePreset.fromJson(
            j['selectedPreset'] as String? ?? 'flat'),
        customName: j['customName'] as String?,
        notes: j['notes'] as String?,
      );
}

// Default 2-way stereo driver layout — flexible, not hardcoded to 2-way only.
List<DriverChannel> defaultDriverChannels() => [
      const DriverChannel(
          id: 'ch_tw_l',
          name: 'Tweeter L',
          role: DriverRole.coaxTweeter,
          side: DriverSide.left,
          dspOutputIndex: 1),
      const DriverChannel(
          id: 'ch_wf_l',
          name: 'Woofer L',
          role: DriverRole.coaxWoofer,
          side: DriverSide.left,
          dspOutputIndex: 2),
      const DriverChannel(
          id: 'ch_tw_r',
          name: 'Tweeter R',
          role: DriverRole.coaxTweeter,
          side: DriverSide.right,
          dspOutputIndex: 3),
      const DriverChannel(
          id: 'ch_wf_r',
          name: 'Woofer R',
          role: DriverRole.coaxWoofer,
          side: DriverSide.right,
          dspOutputIndex: 4),
    ];

class MeasurementProjectState {
  final List<DriverChannel> driverChannels;
  final List<AcousticFileRef> importedFiles;
  final TargetCurveState targetCurve;
  final List<ListeningPositionFrdSet> listeningPositions;

  const MeasurementProjectState({
    this.driverChannels = const [],
    this.importedFiles = const [],
    this.targetCurve = const TargetCurveState(),
    this.listeningPositions = const [],
  });

  // ── Computed readiness ────────────────────────────────────────────────────

  int get totalDrivers => driverChannels.length;
  int get importedFrdCount => driverChannels.where((d) => d.hasFrd).length;
  int get importedZmaCount => driverChannels.where((d) => d.hasZma).length;
  int get parsedFrdCount => driverChannels.where((d) => d.hasParsedFrd).length;
  int get parsedZmaCount => driverChannels.where((d) => d.hasParsedZma).length;
  int get parsedFrdWithPhaseCount =>
      driverChannels.where((d) => d.frdData?.hasPhase == true).length;
  int get missingPhaseCount => parsedFrdCount - parsedFrdWithPhaseCount;
  int get readyDriverCount => driverChannels
      .where((d) =>
          d.measurementStatus == MeasurementStatus.validated ||
          d.measurementStatus == MeasurementStatus.imported)
      .length;
  bool get hasMissingMeasurements => driverChannels.any((d) =>
      d.measurementStatus == MeasurementStatus.empty ||
      d.measurementStatus == MeasurementStatus.missingFile);
  bool get hasAnyFrd => importedFrdCount > 0;

  String get readinessLabel {
    if (importedFrdCount == 0) return 'No FRD data — import required';
    if (hasMissingMeasurements) {
      return 'Partial — $readyDriverCount / $totalDrivers channels ready';
    }
    if (driverChannels
        .any((d) => d.measurementStatus == MeasurementStatus.needsReview)) {
      return 'Needs review';
    }
    return 'Ready — $readyDriverCount / $totalDrivers channels';
  }

  MeasurementProjectState copyWith({
    List<DriverChannel>? driverChannels,
    List<AcousticFileRef>? importedFiles,
    TargetCurveState? targetCurve,
    List<ListeningPositionFrdSet>? listeningPositions,
  }) =>
      MeasurementProjectState(
        driverChannels: driverChannels ?? this.driverChannels,
        importedFiles: importedFiles ?? this.importedFiles,
        targetCurve: targetCurve ?? this.targetCurve,
        listeningPositions: listeningPositions ?? this.listeningPositions,
      );

  Map<String, dynamic> toJson() => {
        'driverChannels': driverChannels.map((d) => d.toJson()).toList(),
        'importedFiles': importedFiles.map((f) => f.toJson()).toList(),
        'targetCurve': targetCurve.toJson(),
        if (listeningPositions.isNotEmpty)
          'listeningPositions': [
            for (final p in listeningPositions) p.toJson()
          ],
      };

  factory MeasurementProjectState.fromJson(Map<String, dynamic> j) =>
      MeasurementProjectState(
        driverChannels: (j['driverChannels'] as List? ?? [])
            .map((e) =>
                DriverChannel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        importedFiles: (j['importedFiles'] as List? ?? [])
            .map((e) =>
                AcousticFileRef.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        targetCurve: j['targetCurve'] != null
            ? TargetCurveState.fromJson(
                Map<String, dynamic>.from(j['targetCurve'] as Map))
            : const TargetCurveState(),
        listeningPositions: (j['listeningPositions'] as List? ?? [])
            .map((e) => ListeningPositionFrdSet.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  static MeasurementProjectState createDefault() => MeasurementProjectState(
        driverChannels: defaultDriverChannels(),
        importedFiles: const [],
        targetCurve: const TargetCurveState(),
      );

  static String encodeList(List<MeasurementProjectState> list) =>
      jsonEncode(list.map((s) => s.toJson()).toList());
}
