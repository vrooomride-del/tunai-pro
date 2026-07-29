// Immutable snapshot of an approved project DSP state for factory shipment.
//
// Never carries raw DSP register addresses, BLE/USB payloads, or SafeLoad
// packets. All DSP values are stored as their logical equivalents
// (frequencyHz, gainDb, q) already present in TuningProjectState.
//
// Profile persistence: stored in ProProject.factoryProfiles and serialized
// through the existing SharedPreferences path — no second storage backend.

import 'dart:convert';

import 'pro_protection_data.dart';
import 'pro_tuning_data.dart';

// ── Eligibility ───────────────────────────────────────────────────────────────

enum FactoryProfileEligibilityResult { approved, blocked }

class FactoryProfileEligibility {
  final FactoryProfileEligibilityResult result;
  final List<String> reasons;

  const FactoryProfileEligibility({
    required this.result,
    required this.reasons,
  });

  bool get isApproved =>
      result == FactoryProfileEligibilityResult.approved;

  // ── JSON ───────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'result': result.name,
        'reasons': reasons,
      };

  factory FactoryProfileEligibility.fromJson(Map<String, dynamic> j) =>
      FactoryProfileEligibility(
        result: FactoryProfileEligibilityResult.values.firstWhere(
          (e) => e.name == (j['result'] as String? ?? ''),
          orElse: () => FactoryProfileEligibilityResult.blocked,
        ),
        reasons:
            (j['reasons'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

// ── Profile model ─────────────────────────────────────────────────────────────

class FactorySoundProfile {
  /// Unique identifier for this profile record.
  final String profileId;

  /// Foreign key to the owning project.
  final String projectId;

  /// User-given name (e.g. "TUNAI ONE v1.0 Factory").
  final String profileName;

  /// Monotonically-incrementing version within this project.
  final int version;

  final DateTime createdAt;
  final DateTime? updatedAt;

  // ── Hardware context ───────────────────────────────────────────────────────

  /// DSP target string from the project (e.g. "ADAU1701").
  final String hardwareTarget;
  final int sampleRate;
  final String channelConfig;

  // ── Deep-copied DSP state snapshots ───────────────────────────────────────

  /// Immutable deep copy of the project's [TuningProjectState] at profile
  /// creation time. Later project edits do not affect this snapshot.
  final TuningProjectState tuningSnapshot;

  /// Immutable deep copy of the project's [ProtectionProjectState].
  final ProtectionProjectState protectionSnapshot;

  // ── References ─────────────────────────────────────────────────────────────

  /// Cycle numbers of the [CorrectionCycle]s that were completed when this
  /// profile was created. Acts as a foreign key into
  /// [ProProject.correctionCycles].
  final List<int> completedCycleNumbers;

  /// Measurement refs (driver channel IDs) that were present at creation time.
  final List<String> measurementRefs;

  // ── Validation summary ────────────────────────────────────────────────────

  /// Serialized name of [VerificationStatus] at creation time.
  final String validationStatus;

  /// Human-readable notes from protection issues at creation time.
  final List<String> validationNotes;

  // ── Fingerprint ────────────────────────────────────────────────────────────

  /// FNV-1a 32-bit hash of the JSON-encoded tuning + protection snapshot.
  /// Unchanged re-export of an identical state produces the same fingerprint.
  final String projectFingerprint;

  // ── Manual approval ───────────────────────────────────────────────────────

  /// True when an engineering team member explicitly approved this profile
  /// without a completed correction cycle (the manual-approval bypass path).
  final bool manuallyApproved;
  final String? approvalNote;

  const FactorySoundProfile({
    required this.profileId,
    required this.projectId,
    required this.profileName,
    required this.version,
    required this.createdAt,
    this.updatedAt,
    required this.hardwareTarget,
    required this.sampleRate,
    required this.channelConfig,
    required this.tuningSnapshot,
    required this.protectionSnapshot,
    this.completedCycleNumbers = const [],
    this.measurementRefs = const [],
    required this.validationStatus,
    this.validationNotes = const [],
    required this.projectFingerprint,
    this.manuallyApproved = false,
    this.approvalNote,
  });

  // ── Computed ───────────────────────────────────────────────────────────────

  bool get hasChannels => tuningSnapshot.peqChannels.isNotEmpty;
  bool get hasCycleEvidence => completedCycleNumbers.isNotEmpty || manuallyApproved;

  // ── JSON ───────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'profileId': profileId,
        'projectId': projectId,
        'profileName': profileName,
        'version': version,
        'createdAt': createdAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        'hardwareTarget': hardwareTarget,
        'sampleRate': sampleRate,
        'channelConfig': channelConfig,
        'tuningSnapshot': tuningSnapshot.toJson(),
        'protectionSnapshot': protectionSnapshot.toJson(),
        if (completedCycleNumbers.isNotEmpty)
          'completedCycleNumbers': completedCycleNumbers,
        if (measurementRefs.isNotEmpty) 'measurementRefs': measurementRefs,
        'validationStatus': validationStatus,
        if (validationNotes.isNotEmpty) 'validationNotes': validationNotes,
        'projectFingerprint': projectFingerprint,
        if (manuallyApproved) 'manuallyApproved': manuallyApproved,
        if (approvalNote != null) 'approvalNote': approvalNote,
      };

  factory FactorySoundProfile.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> sub(String key) =>
        Map<String, dynamic>.from((j[key] as Map?) ?? const {});
    return FactorySoundProfile(
      profileId: j['profileId'] as String,
      projectId: j['projectId'] as String,
      profileName: j['profileName'] as String? ?? 'Unnamed Profile',
      version: j['version'] as int? ?? 1,
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: j['updatedAt'] != null
          ? DateTime.tryParse(j['updatedAt'] as String)
          : null,
      hardwareTarget: j['hardwareTarget'] as String? ?? '',
      sampleRate: j['sampleRate'] as int? ?? 48000,
      channelConfig: j['channelConfig'] as String? ?? '',
      tuningSnapshot: j['tuningSnapshot'] != null
          ? TuningProjectState.fromJson(sub('tuningSnapshot'))
          : TuningProjectState.createDefault(),
      protectionSnapshot: j['protectionSnapshot'] != null
          ? ProtectionProjectState.fromJson(sub('protectionSnapshot'))
          : ProtectionProjectState.createDefault(),
      completedCycleNumbers: (j['completedCycleNumbers'] as List? ?? [])
          .map((e) => e as int)
          .toList(),
      measurementRefs:
          (j['measurementRefs'] as List? ?? []).map((e) => e.toString()).toList(),
      validationStatus: j['validationStatus'] as String? ?? 'notReady',
      validationNotes: (j['validationNotes'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      projectFingerprint: j['projectFingerprint'] as String? ?? '',
      manuallyApproved: j['manuallyApproved'] as bool? ?? false,
      approvalNote: j['approvalNote'] as String?,
    );
  }

  // ── FNV-1a 32-bit fingerprint ─────────────────────────────────────────────

  /// Deterministic, stable FNV-1a 32-bit hash of [source] bytes.
  /// Same input → same output across all Dart environments.
  static String computeFingerprint(String source) {
    final bytes = utf8.encode(source);
    var h = 2166136261; // FNV offset basis
    for (final b in bytes) {
      h = ((h ^ b) * 16777619) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
