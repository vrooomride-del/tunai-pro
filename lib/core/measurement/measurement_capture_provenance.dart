// ── TUNAI PRO Phase 3-D3A-2 — capture-time provenance ────────────────────────
//
// Pins the project/profile/calibration/device/setup identity AND the actual
// recorded WAV format at the exact moment a capture succeeds and a Preview
// is produced. Immutable — never mutated, never recomputed from "whatever
// the project looks like now". [MeasurementPreviewAcceptanceGate] compares
// this frozen snapshot against the CURRENT project at Accept time; Accept
// itself never re-derives what was true at Capture time from current state.
//
// Built once, by [MeasurementCaptureProvenanceBuilder.build], from the same
// project reference the calling controller already has in hand right after
// a successful capture — never a second, later read of the project store.
library;

import '../pro_project.dart';
import 'measurement_input_device.dart';
import 'measurement_quality_policy.dart';
import 'measurement_setup_readiness.dart';

/// The one shared derivation of a project's current input-device identity
/// string — used by both the provenance builder (at capture time) and
/// [MeasurementPreviewAcceptanceGate] (at accept time), so "what counts as
/// the same device" can never drift between the two moments being compared.
/// Mirrors [MeasurementSetupReadinessProjectIdentity.forProject]'s identical
/// null-selection-defaults-to-system-default convention.
String measurementInputDeviceSelectionIdentity(
  MeasurementInputDeviceSelection? selection,
) =>
    selection == null
        ? MeasurementSetupReadinessIdentity.kSystemDefaultInputDeviceIdentity
        : (selection.useSystemDefault
            ? MeasurementSetupReadinessIdentity
                .kSystemDefaultInputDeviceIdentity
            : MeasurementSetupReadinessIdentity.specificInputDeviceIdentity(
                selection.deviceId!));

class MeasurementCaptureProvenance {
  final String projectId;

  /// [MeasurementMicrophoneProfile.checksum] at capture time. Empty string
  /// when no profile was selected (should be unreachable — the capture gate
  /// blocks capture without a profile — but never null so downstream
  /// comparisons stay total functions).
  final String microphoneProfileChecksum;

  /// Null when the profile carried no calibration curve (e.g. explicitly
  /// uncalibrated).
  final String? calibrationCurveChecksum;

  /// [CalibrationAngle.name] of the calibration curve in effect, or null
  /// when there was no curve to have an angle.
  final String? calibrationAngle;

  /// Canonical identity string — `'system-default'` or `'device:<id>'` —
  /// from [MeasurementSetupReadinessIdentity], never a raw OS label.
  final String inputDeviceSelectionIdentity;

  /// The setup-readiness generation this capture relied on. Null when no
  /// setup check had been recorded (should be unreachable in production —
  /// the capture gate requires one — but kept nullable defensively).
  final String? setupReadinessGenerationId;

  final String qualityPolicyVersion;

  /// From the recorded WAV's own fmt chunk — never the RecordConfig request.
  final int actualSampleRate;
  final int actualChannelCount;

  final DateTime capturedAt;

  const MeasurementCaptureProvenance({
    required this.projectId,
    required this.microphoneProfileChecksum,
    required this.calibrationCurveChecksum,
    required this.calibrationAngle,
    required this.inputDeviceSelectionIdentity,
    required this.setupReadinessGenerationId,
    required this.qualityPolicyVersion,
    required this.actualSampleRate,
    required this.actualChannelCount,
    required this.capturedAt,
  });

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'microphoneProfileChecksum': microphoneProfileChecksum,
        if (calibrationCurveChecksum != null)
          'calibrationCurveChecksum': calibrationCurveChecksum,
        if (calibrationAngle != null) 'calibrationAngle': calibrationAngle,
        'inputDeviceSelectionIdentity': inputDeviceSelectionIdentity,
        if (setupReadinessGenerationId != null)
          'setupReadinessGenerationId': setupReadinessGenerationId,
        'qualityPolicyVersion': qualityPolicyVersion,
        'actualSampleRate': actualSampleRate,
        'actualChannelCount': actualChannelCount,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory MeasurementCaptureProvenance.fromJson(Map<String, dynamic> j) =>
      MeasurementCaptureProvenance(
        projectId: j['projectId'] as String? ?? '',
        microphoneProfileChecksum:
            j['microphoneProfileChecksum'] as String? ?? '',
        calibrationCurveChecksum: j['calibrationCurveChecksum'] as String?,
        calibrationAngle: j['calibrationAngle'] as String?,
        inputDeviceSelectionIdentity: j['inputDeviceSelectionIdentity']
                as String? ??
            MeasurementSetupReadinessIdentity.kSystemDefaultInputDeviceIdentity,
        setupReadinessGenerationId: j['setupReadinessGenerationId'] as String?,
        qualityPolicyVersion: j['qualityPolicyVersion'] as String? ?? '',
        actualSampleRate: j['actualSampleRate'] as int? ?? 0,
        actualChannelCount: j['actualChannelCount'] as int? ?? 0,
        capturedAt: DateTime.tryParse(j['capturedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      other is MeasurementCaptureProvenance &&
      other.projectId == projectId &&
      other.microphoneProfileChecksum == microphoneProfileChecksum &&
      other.calibrationCurveChecksum == calibrationCurveChecksum &&
      other.calibrationAngle == calibrationAngle &&
      other.inputDeviceSelectionIdentity == inputDeviceSelectionIdentity &&
      other.setupReadinessGenerationId == setupReadinessGenerationId &&
      other.qualityPolicyVersion == qualityPolicyVersion &&
      other.actualSampleRate == actualSampleRate &&
      other.actualChannelCount == actualChannelCount &&
      other.capturedAt == capturedAt;

  @override
  int get hashCode => Object.hash(
        projectId,
        microphoneProfileChecksum,
        calibrationCurveChecksum,
        calibrationAngle,
        inputDeviceSelectionIdentity,
        setupReadinessGenerationId,
        qualityPolicyVersion,
        actualSampleRate,
        actualChannelCount,
        capturedAt,
      );
}

/// The ONE builder Factory and Room both call — so a provenance snapshot's
/// shape/derivation can never drift between the two capture paths.
abstract final class MeasurementCaptureProvenanceBuilder {
  static MeasurementCaptureProvenance build({
    required ProProject project,
    required int actualSampleRate,
    required int actualChannelCount,
    MeasurementQualityPolicy? policy,
    DateTime? now,
  }) {
    final effectivePolicy = policy ?? MeasurementQualityPolicy.proProvisional();
    final profile = project.selectedMicrophoneProfile;
    final curve = profile?.calibrationCurve;
    return MeasurementCaptureProvenance(
      projectId: project.id,
      microphoneProfileChecksum: profile?.checksum ?? '',
      calibrationCurveChecksum: curve?.checksum,
      calibrationAngle: curve?.angle.name,
      inputDeviceSelectionIdentity:
          measurementInputDeviceSelectionIdentity(project.selectedInputDevice),
      setupReadinessGenerationId: project.currentSetupReadiness?.generationId,
      qualityPolicyVersion: effectivePolicy.version,
      actualSampleRate: actualSampleRate,
      actualChannelCount: actualChannelCount,
      capturedAt: now ?? DateTime.now(),
    );
  }
}
