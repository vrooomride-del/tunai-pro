// ── TUNAI PRO Phase 3-D2 — project -> readiness identity ────────────────────
//
// Single shared derivation of MeasurementSetupReadinessIdentity from a
// ProProject's current state — both GuidedMeasurementSetupDialog and
// MicrophoneStatusCard call this instead of each re-deriving it, so
// "what counts as identity-relevant" is defined in exactly one place.
//
// Separate file from measurement_setup_readiness.dart specifically to avoid
// a circular import: ProProject itself holds a
// MeasurementSetupReadinessSnapshot field, so that core type must not
// depend on pro_project.dart.
library;

import '../pro_project.dart';
import 'measurement_quality_policy.dart';
import 'measurement_setup_readiness.dart';

abstract final class MeasurementSetupReadinessProjectIdentity {
  static MeasurementSetupReadinessIdentity forProject(
    ProProject project, {
    MeasurementQualityPolicy? policy,
  }) {
    final effectivePolicy = policy ?? MeasurementQualityPolicy.proProvisional();
    final profile = project.selectedMicrophoneProfile;
    final selection = project.selectedInputDevice;
    return MeasurementSetupReadinessIdentity(
      projectId: project.id,
      profileChecksum: profile?.checksum,
      calibrationCurveChecksum: profile?.calibrationCurve?.checksum,
      calibrationAngle: profile?.calibrationCurve?.angle.name,
      inputDeviceIdentity: selection == null
          ? MeasurementSetupReadinessIdentity.kSystemDefaultInputDeviceIdentity
          : (selection.useSystemDefault
              ? MeasurementSetupReadinessIdentity
                  .kSystemDefaultInputDeviceIdentity
              : MeasurementSetupReadinessIdentity.specificInputDeviceIdentity(
                  selection.deviceId!)),
      expectedSampleRate: effectivePolicy.expectedSampleRate,
      expectedChannelCount: effectivePolicy.expectedChannelCount,
      qualityPolicyVersion: effectivePolicy.version,
    );
  }
}
