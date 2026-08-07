// ── TUNAI PRO Phase 3-D2 — Guided Setup readiness composition ──────────────
//
// Pure: composes microphone/device/quality facts into blockers/warnings and
// a single isReady verdict. No UI text formatting beyond the plain English
// strings the brief specifies verbatim — Korean/localized copy is the
// dialog's job, this module's strings are the canonical machine-checkable
// reasons.
library;

import '../calibration/microphone_profile_edit_rules.dart';
import 'measurement_input_device.dart';
import 'measurement_quality_model.dart';
import 'measurement_setup_readiness.dart';

abstract final class MeasurementSetupReadinessBuilder {
  static MeasurementSetupReadinessSnapshot build({
    required MeasurementSetupReadinessIdentity identity,
    required MicrophoneDisplayState microphoneState,
    required bool inputDeviceSelected,
    required bool inputDeviceAvailable,
    required bool permissionGranted,
    MeasurementQualityEvaluation? noiseFloorEvaluation,
    MeasurementQualityEvaluation? levelCheckEvaluation,
    MeasurementInputDeviceSnapshot? deviceSnapshot,
    bool explicitWarningAcknowledgement = false,
    MeasurementSetupSignalSide selectedSetupSignalSide =
        MeasurementSetupSignalSide.mono,
    required Duration validity,
    DateTime? now,
  }) {
    final blockers = <String>[];
    final warnings = <String>[];

    switch (microphoneState) {
      case MicrophoneDisplayState.notSelected:
        blockers.add('Select a measurement microphone.');
      case MicrophoneDisplayState.invalid:
        blockers.add('Calibration profile is invalid.');
      case MicrophoneDisplayState.explicitlyUncalibrated:
        if (!explicitWarningAcknowledgement) {
          blockers.add('Confirm using without calibration to continue.');
        } else {
          warnings.add('Using without calibration — accuracy may be reduced.');
        }
      case MicrophoneDisplayState.calibrationReady:
        break;
    }

    if (!permissionGranted) {
      blockers.add('Allow microphone access.');
    }
    if (!inputDeviceSelected) {
      blockers.add('Select an input device.');
    } else if (!inputDeviceAvailable) {
      blockers.add('Selected input device is unavailable.');
    }

    void applyEvaluation(MeasurementQualityEvaluation? eval, String label) {
      if (eval == null) return;
      for (final status in eval.statuses) {
        switch (status) {
          case MeasurementQualityStatus.ready:
            break;
          case MeasurementQualityStatus.clipping:
            blockers.add('$label signal is clipping.');
          case MeasurementQualityStatus.malformedCapture:
            blockers.add('Recorded file format is invalid.');
          case MeasurementQualityStatus.captureTooShort:
            blockers.add('$label capture was too short.');
          case MeasurementQualityStatus.sampleRateMismatch:
            blockers.add('Sample rate does not match.');
          case MeasurementQualityStatus.channelMismatch:
            blockers.add('Channel count does not match.');
          case MeasurementQualityStatus.inputLevelTooLow:
            blockers.add('Input signal is too low.');
          case MeasurementQualityStatus.inputLevelTooHigh:
            blockers.add('Input signal is too loud, causing distortion.');
          case MeasurementQualityStatus.noiseFloorTooHigh:
            warnings.add('Background noise is near the recommended limit.');
          case MeasurementQualityStatus.signalToNoiseTooLow:
            blockers.add('Signal-to-noise ratio is too low.');
          case MeasurementQualityStatus.permissionDenied:
            blockers.add('Allow microphone access.');
          case MeasurementQualityStatus.inputDeviceUnavailable:
            blockers.add('Selected input device is unavailable.');
        }
      }
    }

    applyEvaluation(noiseFloorEvaluation, 'Background noise');
    applyEvaluation(levelCheckEvaluation, 'Input level');

    if (noiseFloorEvaluation == null) {
      blockers.add('Background-noise check has not been run yet.');
    }
    if (levelCheckEvaluation == null) {
      blockers.add('Input-level check has not been run yet.');
    }

    final checkedAt = now ?? DateTime.now();
    final isReady = blockers.isEmpty;

    return MeasurementSetupReadinessSnapshot(
      identity: identity,
      generationId: MeasurementSetupReadinessSnapshot.newGenerationId(),
      noiseFloorEvaluation: noiseFloorEvaluation,
      levelCheckEvaluation: levelCheckEvaluation,
      deviceSnapshot: deviceSnapshot,
      blockers: List.unmodifiable(blockers.toSet()),
      warnings: List.unmodifiable(warnings.toSet()),
      checkedAt: checkedAt,
      expiresAt: checkedAt.add(validity),
      isReady: isReady,
      explicitWarningAcknowledgement: explicitWarningAcknowledgement,
      selectedSetupSignalSide: selectedSetupSignalSide,
    );
  }
}
