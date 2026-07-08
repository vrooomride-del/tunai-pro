import 'dart:convert';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum MeasurementSessionStatus { draft, ready, running, completed, reviewed }

extension MeasurementSessionStatusX on MeasurementSessionStatus {
  String get label => switch (this) {
    MeasurementSessionStatus.draft     => 'Draft',
    MeasurementSessionStatus.ready     => 'Ready',
    MeasurementSessionStatus.running   => 'Running',
    MeasurementSessionStatus.completed => 'Completed',
    MeasurementSessionStatus.reviewed  => 'Reviewed',
  };
  String toJson() => name;
  static MeasurementSessionStatus fromJson(String s) =>
      MeasurementSessionStatus.values.firstWhere(
          (e) => e.name == s,
          orElse: () => MeasurementSessionStatus.draft);
}

enum MeasurementPointStatus { pending, ready, captured, rejected, accepted }

extension MeasurementPointStatusX on MeasurementPointStatus {
  String get label => switch (this) {
    MeasurementPointStatus.pending   => 'Pending',
    MeasurementPointStatus.ready     => 'Ready',
    MeasurementPointStatus.captured  => 'Captured',
    MeasurementPointStatus.rejected  => 'Rejected',
    MeasurementPointStatus.accepted  => 'Accepted',
  };
  String toJson() => name;
  static MeasurementPointStatus fromJson(String s) =>
      MeasurementPointStatus.values.firstWhere(
          (e) => e.name == s,
          orElse: () => MeasurementPointStatus.pending);
}

enum MeasurementChannel { left, right, mono, woofer, tweeter, midrange, subwoofer }

extension MeasurementChannelX on MeasurementChannel {
  String get label => switch (this) {
    MeasurementChannel.left      => 'Left',
    MeasurementChannel.right     => 'Right',
    MeasurementChannel.mono      => 'Mono',
    MeasurementChannel.woofer    => 'Woofer',
    MeasurementChannel.tweeter   => 'Tweeter',
    MeasurementChannel.midrange  => 'Midrange',
    MeasurementChannel.subwoofer => 'Subwoofer',
  };
  String toJson() => name;
  static MeasurementChannel fromJson(String s) =>
      MeasurementChannel.values.firstWhere(
          (e) => e.name == s,
          orElse: () => MeasurementChannel.left);
}

enum MeasurementPosition {
  listeningPosition, nearfield, leftSeat, rightSeat, center, custom
}

extension MeasurementPositionX on MeasurementPosition {
  String get label => switch (this) {
    MeasurementPosition.listeningPosition => 'Listening Position',
    MeasurementPosition.nearfield         => 'Nearfield',
    MeasurementPosition.leftSeat          => 'Left Seat',
    MeasurementPosition.rightSeat         => 'Right Seat',
    MeasurementPosition.center            => 'Center',
    MeasurementPosition.custom            => 'Custom',
  };
  String toJson() => name;
  static MeasurementPosition fromJson(String s) =>
      MeasurementPosition.values.firstWhere(
          (e) => e.name == s,
          orElse: () => MeasurementPosition.listeningPosition);
}

enum SweepType { logSweep, pinkNoise, manualImport, placeholder }

extension SweepTypeX on SweepType {
  String get label => switch (this) {
    SweepType.logSweep      => 'Log Sweep',
    SweepType.pinkNoise     => 'Pink Noise',
    SweepType.manualImport  => 'Manual Import',
    SweepType.placeholder   => 'Placeholder',
  };
  String toJson() => name;
  static SweepType fromJson(String s) =>
      SweepType.values.firstWhere(
          (e) => e.name == s,
          orElse: () => SweepType.placeholder);
}

// ── MeasurementResult ─────────────────────────────────────────────────────────

class MeasurementResult {
  final double peakLevelDb;
  final double noiseFloorDb;
  final String usableRange;
  final double confidence;
  final List<String> issues;

  const MeasurementResult({
    this.peakLevelDb = 0.0,
    this.noiseFloorDb = -90.0,
    this.usableRange = '20 Hz – 20 kHz',
    this.confidence = 0.0,
    this.issues = const [],
  });

  /// Placeholder result generated on simulate-capture
  factory MeasurementResult.placeholder() => const MeasurementResult(
    peakLevelDb: -6.0,
    noiseFloorDb: -78.0,
    usableRange: '40 Hz – 18 kHz',
    confidence: 0.72,
    issues: ['Placeholder capture — real measurement engine not connected.'],
  );

  Map<String, dynamic> toJson() => {
    'peakLevelDb': peakLevelDb,
    'noiseFloorDb': noiseFloorDb,
    'usableRange': usableRange,
    'confidence': confidence,
    'issues': issues,
  };

  factory MeasurementResult.fromJson(Map<String, dynamic> j) => MeasurementResult(
    peakLevelDb:  (j['peakLevelDb']  as num?)?.toDouble() ?? 0.0,
    noiseFloorDb: (j['noiseFloorDb'] as num?)?.toDouble() ?? -90.0,
    usableRange:  j['usableRange']   as String? ?? '—',
    confidence:   (j['confidence']   as num?)?.toDouble() ?? 0.0,
    issues: (j['issues'] as List?)?.cast<String>() ?? [],
  );
}

// ── MeasurementPoint ──────────────────────────────────────────────────────────

class MeasurementPoint {
  final String id;
  final String label;
  final MeasurementChannel channel;
  final MeasurementPosition position;
  final double distanceCm;
  final double angleDeg;
  final MeasurementPointStatus status;
  final DateTime? capturedAt;
  final String? notes;
  final MeasurementResult? result;

  const MeasurementPoint({
    required this.id,
    required this.label,
    this.channel = MeasurementChannel.left,
    this.position = MeasurementPosition.listeningPosition,
    this.distanceCm = 100.0,
    this.angleDeg = 0.0,
    this.status = MeasurementPointStatus.pending,
    this.capturedAt,
    this.notes,
    this.result,
  });

  MeasurementPoint copyWith({
    String? label,
    MeasurementChannel? channel,
    MeasurementPosition? position,
    double? distanceCm,
    double? angleDeg,
    MeasurementPointStatus? status,
    DateTime? capturedAt,
    String? notes,
    MeasurementResult? result,
  }) => MeasurementPoint(
    id: id,
    label: label ?? this.label,
    channel: channel ?? this.channel,
    position: position ?? this.position,
    distanceCm: distanceCm ?? this.distanceCm,
    angleDeg: angleDeg ?? this.angleDeg,
    status: status ?? this.status,
    capturedAt: capturedAt ?? this.capturedAt,
    notes: notes ?? this.notes,
    result: result ?? this.result,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'channel': channel.toJson(),
    'position': position.toJson(),
    'distanceCm': distanceCm,
    'angleDeg': angleDeg,
    'status': status.toJson(),
    if (capturedAt != null) 'capturedAt': capturedAt!.toIso8601String(),
    if (notes != null) 'notes': notes,
    if (result != null) 'result': result!.toJson(),
  };

  factory MeasurementPoint.fromJson(Map<String, dynamic> j) => MeasurementPoint(
    id:         j['id'] as String,
    label:      j['label'] as String? ?? 'Point',
    channel:    MeasurementChannelX.fromJson(j['channel'] as String? ?? 'left'),
    position:   MeasurementPositionX.fromJson(j['position'] as String? ?? 'listeningPosition'),
    distanceCm: (j['distanceCm'] as num?)?.toDouble() ?? 100.0,
    angleDeg:   (j['angleDeg']   as num?)?.toDouble() ?? 0.0,
    status:     MeasurementPointStatusX.fromJson(j['status'] as String? ?? 'pending'),
    capturedAt: j['capturedAt'] != null ? DateTime.tryParse(j['capturedAt'] as String) : null,
    notes:      j['notes'] as String?,
    result:     j['result'] != null
        ? MeasurementResult.fromJson(Map<String, dynamic>.from(j['result'] as Map))
        : null,
  );
}

// ── MeasurementSession ────────────────────────────────────────────────────────

class MeasurementSession {
  final String id;
  final String projectId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MeasurementSessionStatus status;
  final int sampleRate;
  final SweepType sweepType;
  final String micProfile;
  final String? notes;
  final List<MeasurementPoint> points;

  const MeasurementSession({
    required this.id,
    required this.projectId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.status = MeasurementSessionStatus.draft,
    this.sampleRate = 48000,
    this.sweepType = SweepType.placeholder,
    this.micProfile = 'Default',
    this.notes,
    this.points = const [],
  });

  factory MeasurementSession.create({
    required String projectId,
    required String name,
    int sampleRate = 48000,
    SweepType sweepType = SweepType.placeholder,
    String micProfile = 'Default',
    String? notes,
  }) {
    final now = DateTime.now();
    return MeasurementSession(
      id: '${now.millisecondsSinceEpoch}',
      projectId: projectId,
      name: name.trim().isEmpty ? 'Measurement Session' : name.trim(),
      createdAt: now,
      updatedAt: now,
      sampleRate: sampleRate,
      sweepType: sweepType,
      micProfile: micProfile,
      notes: notes,
    );
  }

  int get acceptedCount => points.where((p) => p.status == MeasurementPointStatus.accepted).length;
  int get capturedCount => points.where((p) =>
      p.status == MeasurementPointStatus.captured ||
      p.status == MeasurementPointStatus.accepted).length;
  bool get hasAnyData => points.any((p) => p.result != null);

  String get sampleRateLabel => '${(sampleRate / 1000).toStringAsFixed(0)} kHz';

  MeasurementSession copyWith({
    String? name,
    DateTime? updatedAt,
    MeasurementSessionStatus? status,
    int? sampleRate,
    SweepType? sweepType,
    String? micProfile,
    String? notes,
    List<MeasurementPoint>? points,
  }) => MeasurementSession(
    id: id,
    projectId: projectId,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    status: status ?? this.status,
    sampleRate: sampleRate ?? this.sampleRate,
    sweepType: sweepType ?? this.sweepType,
    micProfile: micProfile ?? this.micProfile,
    notes: notes ?? this.notes,
    points: points ?? this.points,
  );

  MeasurementSession touch() => copyWith(updatedAt: DateTime.now());

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.toJson(),
    'sampleRate': sampleRate,
    'sweepType': sweepType.toJson(),
    'micProfile': micProfile,
    if (notes != null) 'notes': notes,
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory MeasurementSession.fromJson(Map<String, dynamic> j) => MeasurementSession(
    id:          j['id'] as String,
    projectId:   j['projectId'] as String? ?? '',
    name:        j['name'] as String? ?? 'Session',
    createdAt:   DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:   DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    status:      MeasurementSessionStatusX.fromJson(j['status'] as String? ?? 'draft'),
    sampleRate:  j['sampleRate'] as int? ?? 48000,
    sweepType:   SweepTypeX.fromJson(j['sweepType'] as String? ?? 'placeholder'),
    micProfile:  j['micProfile'] as String? ?? 'Default',
    notes:       j['notes'] as String?,
    points: (j['points'] as List? ?? [])
        .map((e) => MeasurementPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  static String encodeList(List<MeasurementSession> list) =>
      jsonEncode(list.map((s) => s.toJson()).toList());

  static List<MeasurementSession> decodeList(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => MeasurementSession.fromJson(
          Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }
}
