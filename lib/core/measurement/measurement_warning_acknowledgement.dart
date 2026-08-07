// ── TUNAI PRO Phase 3-D3 — typed capture-warning acknowledgement ────────────
//
// Warning-level capture conditions (e.g. "this microphone is explicitly
// uncalibrated") may be proceeded through, but never implicitly: the user
// must explicitly acknowledge them, and the acknowledgement is bound to the
// exact measurement-chain identity it was given for.
//
// Deliberately NOT a bool: a bare flag would survive a microphone swap, a
// device change, or a fresh setup check, silently authorising a capture the
// user never actually agreed to. Binding projectId + profile identity +
// device identity + readiness generationId means any of those changing
// invalidates the acknowledgement automatically, with no explicit "clear"
// step to forget.
//
// Scope note: acknowledging a CAPTURE warning is not an Auto PEQ override.
// Room Auto PEQ blocks explicitly-uncalibrated data by its own separate
// policy (Phase 3-D3 §12) and does not consult this type.

library;

import 'measurement_capture_gate_types.dart';

class MeasurementWarningAcknowledgement {
  final String projectId;

  /// The microphone profile checksum this acknowledgement was given for.
  /// Null only when the profile itself has no checksum (never used to match
  /// a *different* profile — see [coversIdentity]).
  final String? profileIdentity;

  /// `'system-default'` or `'device:<id>'` — the same discriminator
  /// [MeasurementSetupReadinessIdentity] uses, so a system-default ->
  /// specific-device switch also invalidates.
  final String deviceIdentity;

  /// The setup readiness generation this acknowledgement was given under.
  /// A fresh setup check produces a new generation and therefore requires a
  /// fresh acknowledgement.
  final String readinessGenerationId;

  /// Exactly which warning kinds the user acknowledged. A later capture that
  /// raises a warning kind NOT in this set is not covered.
  final Set<MeasurementCaptureWarningCode> warningCodes;

  final DateTime acknowledgedAt;

  const MeasurementWarningAcknowledgement({
    required this.projectId,
    required this.profileIdentity,
    required this.deviceIdentity,
    required this.readinessGenerationId,
    required this.warningCodes,
    required this.acknowledgedAt,
  });

  /// True when this acknowledgement was given for exactly the chain identity
  /// described by the arguments. Any mismatch (project, profile, device, or
  /// readiness generation) means it does not apply.
  bool coversIdentity({
    required String projectId,
    required String? profileIdentity,
    required String deviceIdentity,
    required String readinessGenerationId,
  }) =>
      this.projectId == projectId &&
      this.profileIdentity == profileIdentity &&
      this.deviceIdentity == deviceIdentity &&
      this.readinessGenerationId == readinessGenerationId;

  /// True when this acknowledgement covers the chain identity AND every
  /// warning code actually raised. A newly-appearing warning kind is never
  /// silently inherited from an older acknowledgement.
  bool covers({
    required String projectId,
    required String? profileIdentity,
    required String deviceIdentity,
    required String readinessGenerationId,
    required Set<MeasurementCaptureWarningCode> raisedWarnings,
  }) =>
      coversIdentity(
        projectId: projectId,
        profileIdentity: profileIdentity,
        deviceIdentity: deviceIdentity,
        readinessGenerationId: readinessGenerationId,
      ) &&
      raisedWarnings.every(warningCodes.contains);

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        if (profileIdentity != null) 'profileIdentity': profileIdentity,
        'deviceIdentity': deviceIdentity,
        'readinessGenerationId': readinessGenerationId,
        'warningCodes': warningCodes.map((c) => c.name).toList(),
        'acknowledgedAt': acknowledgedAt.toIso8601String(),
      };

  factory MeasurementWarningAcknowledgement.fromJson(Map<String, dynamic> j) =>
      MeasurementWarningAcknowledgement(
        projectId: j['projectId'] as String,
        profileIdentity: j['profileIdentity'] as String?,
        deviceIdentity: j['deviceIdentity'] as String,
        readinessGenerationId: j['readinessGenerationId'] as String,
        warningCodes: ((j['warningCodes'] as List?) ?? const [])
            .map((raw) => MeasurementCaptureWarningCode.values.firstWhere(
                  (c) => c.name == raw,
                  orElse: () => MeasurementCaptureWarningCode.setupQuality,
                ))
            .toSet(),
        acknowledgedAt:
            DateTime.tryParse(j['acknowledgedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
}
