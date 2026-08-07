// TUNAI PRO Phase 2 — Stereo Room Measurement data model.
//
// Whole-system Left/Right captures, kept entirely separate from
// driverChannels[i].frdData (Factory per-driver tuning). Nothing here is
// read by the Factory Guided AI path (ProGuidedAiController.frdReadiness,
// requiredFullSystemChannelIds) — the two live side by side in ProProject.

import 'pro_acoustic_data.dart' show ParsedMeasurementData;
import 'room_workflow_persistence.dart'
    show
        PersistedRoomClosedLoopResult,
        RoomAutoPeqApproval,
        VerifiedDeploymentReceipt;

enum RoomSystemSide {
  left,
  right;

  String get label => switch (this) {
        RoomSystemSide.left => 'Left',
        RoomSystemSide.right => 'Right',
      };

  String toJson() => name;
  static RoomSystemSide fromJson(String s) => RoomSystemSide.values
      .firstWhere((e) => e.name == s, orElse: () => RoomSystemSide.left);
}

enum RoomMeasurementPhase {
  before,
  after;

  String toJson() => name;
  static RoomMeasurementPhase fromJson(String s) =>
      RoomMeasurementPhase.values.firstWhere((e) => e.name == s,
          orElse: () => RoomMeasurementPhase.before);
}

enum RoomMeasurementSource {
  live,
  import;

  String toJson() => name;
  static RoomMeasurementSource fromJson(String s) => RoomMeasurementSource
      .values
      .firstWhere((e) => e.name == s, orElse: () => RoomMeasurementSource.live);
}

/// One whole-system Left or Right capture (woofer + tweeter playing together
/// through the existing crossover), with the metadata required to prove
/// identity/provenance before it is used for Auto PEQ or Closed Loop.
class RoomSystemMeasurement {
  final RoomSystemSide side;
  final RoomMeasurementPhase phase;
  final ParsedMeasurementData frd;
  final DateTime capturedAt;
  final int sampleRate;
  final RoomMeasurementSource source;
  final String projectId;
  final String? cycleId;

  const RoomSystemMeasurement({
    required this.side,
    required this.phase,
    required this.frd,
    required this.capturedAt,
    required this.sampleRate,
    required this.source,
    required this.projectId,
    this.cycleId,
  });

  Map<String, dynamic> toJson() => {
        'side': side.toJson(),
        'phase': phase.toJson(),
        'frd': frd.toJson(),
        'capturedAt': capturedAt.toIso8601String(),
        'sampleRate': sampleRate,
        'source': source.toJson(),
        'projectId': projectId,
        if (cycleId != null) 'cycleId': cycleId,
      };

  factory RoomSystemMeasurement.fromJson(Map<String, dynamic> j) =>
      RoomSystemMeasurement(
        side: RoomSystemSide.fromJson(j['side'] as String? ?? 'left'),
        phase: RoomMeasurementPhase.fromJson(j['phase'] as String? ?? 'before'),
        frd: ParsedMeasurementData.fromJson(
            Map<String, dynamic>.from(j['frd'] as Map)),
        capturedAt: DateTime.tryParse(j['capturedAt'] as String? ?? '') ??
            DateTime.now(),
        sampleRate: j['sampleRate'] as int? ?? 48000,
        source:
            RoomMeasurementSource.fromJson(j['source'] as String? ?? 'live'),
        projectId: j['projectId'] as String? ?? '',
        cycleId: j['cycleId'] as String?,
      );
}

/// One phase's (Before or After) Left+Right pair. Either side may still be
/// missing — readiness is 0/2, 1/2, or 2/2.
class RoomMeasurementSnapshot {
  final RoomSystemMeasurement? leftSystemFrd;
  final RoomSystemMeasurement? rightSystemFrd;

  const RoomMeasurementSnapshot({this.leftSystemFrd, this.rightSystemFrd});

  int get readyCount =>
      (leftSystemFrd != null ? 1 : 0) + (rightSystemFrd != null ? 1 : 0);
  bool get isComplete => leftSystemFrd != null && rightSystemFrd != null;

  RoomSystemMeasurement? forSide(RoomSystemSide side) => switch (side) {
        RoomSystemSide.left => leftSystemFrd,
        RoomSystemSide.right => rightSystemFrd,
      };

  RoomMeasurementSnapshot copyWith({
    RoomSystemMeasurement? leftSystemFrd,
    RoomSystemMeasurement? rightSystemFrd,
  }) =>
      RoomMeasurementSnapshot(
        leftSystemFrd: leftSystemFrd ?? this.leftSystemFrd,
        rightSystemFrd: rightSystemFrd ?? this.rightSystemFrd,
      );

  RoomMeasurementSnapshot withSide(
          RoomSystemSide side, RoomSystemMeasurement measurement) =>
      switch (side) {
        RoomSystemSide.left => copyWith(leftSystemFrd: measurement),
        RoomSystemSide.right => copyWith(rightSystemFrd: measurement),
      };

  Map<String, dynamic> toJson() => {
        if (leftSystemFrd != null) 'leftSystemFrd': leftSystemFrd!.toJson(),
        if (rightSystemFrd != null) 'rightSystemFrd': rightSystemFrd!.toJson(),
      };

  factory RoomMeasurementSnapshot.fromJson(Map<String, dynamic> j) =>
      RoomMeasurementSnapshot(
        leftSystemFrd: j['leftSystemFrd'] != null
            ? RoomSystemMeasurement.fromJson(
                Map<String, dynamic>.from(j['leftSystemFrd'] as Map))
            : null,
        rightSystemFrd: j['rightSystemFrd'] != null
            ? RoomSystemMeasurement.fromJson(
                Map<String, dynamic>.from(j['rightSystemFrd'] as Map))
            : null,
      );

  static const empty = RoomMeasurementSnapshot();
}

/// Project-level Room Measurement state: Before and After snapshots.
/// Decode-resilient — a project persisted before this phase existed decodes
/// to `RoomMeasurementProjectState.createDefault()` (both snapshots empty).
class RoomMeasurementProjectState {
  final RoomMeasurementSnapshot before;
  final RoomMeasurementSnapshot after;

  /// Phase 3-F3 — restart-safe Room Auto PEQ approval record. Additive: a
  /// project persisted before this phase decodes with this null (unapproved
  /// safe default), never fabricated from any other field.
  final RoomAutoPeqApproval? approval;

  /// Phase 3-F3 — restart-safe proof that a specific plan actually executed
  /// and was fully DSP-readback verified. Single slot: always overwritten by
  /// the most recent Room-relevant verified deploy (correction or
  /// rollback), mirroring lastHardwareWriteResultProvider's existing
  /// single-slot "most recent write wins" semantics.
  final VerifiedDeploymentReceipt? deploymentReceipt;

  /// Phase 3-F3 — restart-safe summary of the real RoomClosedLoopEvaluator
  /// verdict for the current Before/After pair. Actively cleared by the
  /// controller on any Before/After change (see
  /// RoomMeasurementController.accept()/startNewAfterSession()); callers
  /// should also check [PersistedRoomClosedLoopResult.matchesCurrent] as a
  /// second layer before treating it as authoritative.
  final PersistedRoomClosedLoopResult? closedLoopResult;

  const RoomMeasurementProjectState({
    this.before = RoomMeasurementSnapshot.empty,
    this.after = RoomMeasurementSnapshot.empty,
    this.approval,
    this.deploymentReceipt,
    this.closedLoopResult,
  });

  RoomMeasurementProjectState copyWith({
    RoomMeasurementSnapshot? before,
    RoomMeasurementSnapshot? after,
    RoomAutoPeqApproval? approval,
    bool clearApproval = false,
    VerifiedDeploymentReceipt? deploymentReceipt,
    bool clearDeploymentReceipt = false,
    PersistedRoomClosedLoopResult? closedLoopResult,
    bool clearClosedLoopResult = false,
  }) =>
      RoomMeasurementProjectState(
        before: before ?? this.before,
        after: after ?? this.after,
        approval: clearApproval ? null : (approval ?? this.approval),
        deploymentReceipt: clearDeploymentReceipt
            ? null
            : (deploymentReceipt ?? this.deploymentReceipt),
        closedLoopResult: clearClosedLoopResult
            ? null
            : (closedLoopResult ?? this.closedLoopResult),
      );

  Map<String, dynamic> toJson() => {
        'before': before.toJson(),
        'after': after.toJson(),
        if (approval != null) 'approval': approval!.toJson(),
        if (deploymentReceipt != null)
          'deploymentReceipt': deploymentReceipt!.toJson(),
        if (closedLoopResult != null)
          'closedLoopResult': closedLoopResult!.toJson(),
      };

  factory RoomMeasurementProjectState.fromJson(Map<String, dynamic> j) {
    RoomAutoPeqApproval? approval;
    try {
      approval = j['approval'] != null
          ? RoomAutoPeqApproval.fromJson(
              Map<String, dynamic>.from(j['approval'] as Map))
          : null;
    } catch (_) {
      approval = null;
    }
    VerifiedDeploymentReceipt? deploymentReceipt;
    try {
      deploymentReceipt = j['deploymentReceipt'] != null
          ? VerifiedDeploymentReceipt.fromJson(
              Map<String, dynamic>.from(j['deploymentReceipt'] as Map))
          : null;
    } catch (_) {
      deploymentReceipt = null;
    }
    PersistedRoomClosedLoopResult? closedLoopResult;
    try {
      closedLoopResult = j['closedLoopResult'] != null
          ? PersistedRoomClosedLoopResult.fromJson(
              Map<String, dynamic>.from(j['closedLoopResult'] as Map))
          : null;
    } catch (_) {
      closedLoopResult = null;
    }
    return RoomMeasurementProjectState(
      before: j['before'] != null
          ? RoomMeasurementSnapshot.fromJson(
              Map<String, dynamic>.from(j['before'] as Map))
          : RoomMeasurementSnapshot.empty,
      after: j['after'] != null
          ? RoomMeasurementSnapshot.fromJson(
              Map<String, dynamic>.from(j['after'] as Map))
          : RoomMeasurementSnapshot.empty,
      approval: approval,
      deploymentReceipt: deploymentReceipt,
      closedLoopResult: closedLoopResult,
    );
  }

  static RoomMeasurementProjectState createDefault() =>
      const RoomMeasurementProjectState();
}
