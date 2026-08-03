// Pure, deterministic Factory Sound Profile builder.
//
// No I/O, no Riverpod, no DSP write, no hardware reference.
// Same inputs always produce the same result.

import 'dart:convert';

import 'factory_sound_profile.dart';
import 'pro_project.dart';
import 'pro_protection_data.dart';
import 'pro_tuning_data.dart';

// ── Known hardware targets ────────────────────────────────────────────────────

/// Hardware targets that are valid for Factory Sound Profile creation.
/// Simulation-only targets do not qualify.
const _kValidHardwareTargets = {
  'ADAU1701',
  'ADAU1466',
  'ADAU1401',
  'ADAU1401A',
};

// ── Builder ───────────────────────────────────────────────────────────────────

abstract final class FactoryProfileBuilder {
  // ── Eligibility gate ──────────────────────────────────────────────────────

  /// Check whether [project] is eligible for Factory Sound Profile creation.
  ///
  /// Returns [FactoryProfileEligibility.isApproved] == true only when ALL
  /// of the following are satisfied:
  ///
  ///  1. Project identity valid (`projectId` non-empty).
  ///  2. Hardware target is a known, non-simulation target.
  ///  3. At least one PEQ channel exists in `tuningState`.
  ///  4. No unresolved safety-blocked apply result (`exportLocked == false`
  ///     AND no critical protection issues).
  ///  5. At least one completed correction cycle exists, OR the caller
  ///     supplies [manualApproval] == true.
  ///  6. Project state is internally consistent (non-empty channel state).
  ///  7. `project.safetyStatus == SafetyStatus.verified` — a project whose
  ///     tuning was just software-rolled-back (safetyStatus reset to
  ///     notVerified) must not be eligible for a new factory profile until
  ///     it is re-verified.
  static FactoryProfileEligibility checkEligibility(
    ProProject project, {
    bool manualApproval = false,
  }) {
    final reasons = <String>[];

    // Rule 1 — project identity
    if (project.id.isEmpty) {
      reasons.add('Project ID is empty.');
    }

    // Rule 2 — hardware target
    if (project.dspTarget.isEmpty) {
      reasons.add('Hardware target is not set.');
    } else if (!_kValidHardwareTargets.contains(project.dspTarget)) {
      reasons.add(
        'Hardware target "${project.dspTarget}" is not supported for '
        'factory profile creation. '
        'Supported: ${_kValidHardwareTargets.join(", ")}.',
      );
    }

    // Rule 3 — PEQ channels
    if (project.tuningState.peqChannels.isEmpty) {
      reasons.add('No PEQ channel state exists in the project.');
    }

    // Rule 4 — safety / protection
    if (project.protectionState.exportLocked) {
      reasons.add(
        'Protection export lock is active — resolve all critical protection '
        'issues before creating a factory profile.',
      );
    } else if (project.protectionState.criticalCount > 0) {
      reasons.add(
        '${project.protectionState.criticalCount} critical protection '
        'issue(s) must be resolved.',
      );
    }

    // Rule 5 — completed cycle or manual approval
    final completedCycles = project.correctionCycles
        .where((c) => c.isComplete)
        .toList();
    if (completedCycles.isEmpty && !manualApproval) {
      reasons.add(
        'No completed correction cycle exists. Complete at least one '
        'post-deploy remeasurement cycle, or pass manualApproval=true '
        'for the engineering manual-approval path.',
      );
    }

    // Rule 6 — channel consistency
    for (final ch in project.tuningState.peqChannels) {
      if (ch.channelId.isEmpty) {
        reasons.add('A PEQ channel has an empty channelId.');
        break;
      }
    }

    // Rule 7 — safety verification
    if (project.safetyStatus != SafetyStatus.verified) {
      reasons.add(
        'Project safety status is "${project.safetyStatus.label}", not '
        'Verified. Re-verify tuning safety before creating a factory '
        'profile — this often follows a software tuning rollback.',
      );
    }

    final result = reasons.isEmpty
        ? FactoryProfileEligibilityResult.approved
        : FactoryProfileEligibilityResult.blocked;

    return FactoryProfileEligibility(result: result, reasons: reasons);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Build a new [FactorySoundProfile] from [project].
  ///
  /// Returns null when the project is not eligible and [manualApproval] is
  /// false. Pass [manualApproval] = true (with a non-null [approvalNote]) to
  /// take the engineering manual-approval bypass path.
  ///
  /// [profileName] defaults to the project name.
  /// [version] defaults to `project.factoryProfiles.length + 1`.
  static FactorySoundProfile? build(
    ProProject project, {
    String? profileName,
    int? version,
    bool manualApproval = false,
    String? approvalNote,
    DateTime? createdAt,
  }) {
    final eligibility =
        checkEligibility(project, manualApproval: manualApproval);
    if (!eligibility.isApproved) return null;

    // Deep-copy DSP state via JSON round-trip (no shared references).
    final tuningJson = jsonDecode(jsonEncode(project.tuningState.toJson()))
        as Map<String, dynamic>;
    final protectionJson =
        jsonDecode(jsonEncode(project.protectionState.toJson()))
            as Map<String, dynamic>;

    final tuningCopy = TuningProjectState.fromJson(tuningJson);
    final protectionCopy = ProtectionProjectState.fromJson(protectionJson);

    // Fingerprint covers the snapshot content only (not metadata like name/version).
    final fingerprintSource = jsonEncode({
      'tuning': tuningJson,
      'protection': protectionJson,
    });
    final fingerprint =
        FactorySoundProfile.computeFingerprint(fingerprintSource);

    final completedCycles = project.correctionCycles
        .where((c) => c.isComplete)
        .map((c) => c.cycleNumber)
        .toList();

    final measurementRefs = project.acousticState.driverChannels
        .map((d) => d.id)
        .toList();

    final validationNotes = project.protectionState.issues
        .map((i) => i.message)
        .toList();

    final now = createdAt ?? DateTime.now();

    return FactorySoundProfile(
      profileId:
          'fp_${project.id}_${now.millisecondsSinceEpoch}',
      projectId: project.id,
      profileName: profileName ?? project.name,
      version: version ?? (project.factoryProfiles.length + 1),
      createdAt: now,
      hardwareTarget: project.dspTarget,
      sampleRate: project.sampleRate,
      channelConfig: project.channelConfig,
      tuningSnapshot: tuningCopy,
      protectionSnapshot: protectionCopy,
      completedCycleNumbers: completedCycles,
      measurementRefs: measurementRefs,
      validationStatus: project.protectionState.verificationStatus.name,
      targetCurvePreset: project.acousticState.targetCurve.selectedPreset.name,
      validationNotes: validationNotes,
      projectFingerprint: fingerprint,
      manuallyApproved: manualApproval,
      approvalNote: approvalNote,
    );
  }

  // ── Re-export detection ───────────────────────────────────────────────────

  /// Returns true when the current project's DSP state fingerprint matches
  /// [existing.projectFingerprint] — i.e., re-exporting would produce the
  /// same data.
  static bool isUnchanged(ProProject project, FactorySoundProfile existing) {
    final tuningJson = jsonEncode(project.tuningState.toJson());
    final protectionJson = jsonEncode(project.protectionState.toJson());
    final source = jsonEncode({
      'tuning': jsonDecode(tuningJson),
      'protection': jsonDecode(protectionJson),
    });
    final currentFingerprint = FactorySoundProfile.computeFingerprint(source);
    return currentFingerprint == existing.projectFingerprint;
  }
}
