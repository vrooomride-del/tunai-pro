// ── TUNAI PRO Phase 3-D3 — capture gate vocabulary ──────────────────────────
//
// Typed blocker/warning codes + the remediation action each maps to. Kept in
// its own file so the acknowledgement type and the gate evaluator can both
// depend on it without a cycle, and so the UI never re-invents its own
// parallel string matching: the button's disabled reason and the
// controller's refusal reason are literally the same value.

library;

/// Runtime presence of the input device a capture would actually record on.
///
/// Deliberately three-valued rather than a bool. The `record` plugin's
/// `RecordConfig.device == null` asks the OS for its *default* input, and on
/// macOS `AVCaptureDevice.default(for: .audio)` can return nil — a default
/// input is NOT guaranteed to exist, and the plugin exposes no API to query
/// "is there currently a system default input?" before starting. So a
/// system-default selection can never be preflighted to `available`; the
/// honest state is "not contradicted, but unverified", and the real
/// authority remains the recorder start itself (which fails closed).
enum MeasurementRuntimeInputAvailability {
  /// A SPECIFIC selected device id was found in a fresh enumeration.
  available,

  /// The specific selected device is gone, or no input devices exist at all.
  unavailable,

  /// System-default selection with at least one input device enumerated.
  /// Capture may be ATTEMPTED, but this must never be presented to the user
  /// as "device confirmed" — the exact default identity is unknowable here.
  systemDefaultUnverified,
}

/// Why a capture must not proceed. Ordered roughly by how early in the
/// measurement chain the problem occurs — [MeasurementCaptureGateResult]
/// surfaces the first one as the primary remediation prompt.
enum MeasurementCaptureBlockerCode {
  noProject,
  noMicrophoneProfile,
  noInputDeviceSelected,
  inputDeviceUnavailable,
  microphonePermissionDenied,
  invalidCalibration,
  legacyUnknownCalibration,
  setupNotChecked,
  setupNotReady,
  setupExpired,
  setupProjectMismatch,
  setupProfileMismatch,
  setupCalibrationCurveMismatch,
  setupOrientationMismatch,
  setupInputDeviceMismatch,
  setupPolicyVersionMismatch,
  setupSampleRateMismatch,
  setupChannelMismatch,

  /// A blocker the setup check itself recorded (malformed capture, clipping,
  /// or a level/noise/SNR value past the policy's blocking threshold). The
  /// gate never re-derives these thresholds — it forwards what
  /// MeasurementSetupReadinessBuilder already decided.
  setupQuality,
}

/// Conditions the user may proceed through, but only via an explicit
/// [MeasurementWarningAcknowledgement] bound to the current chain identity.
enum MeasurementCaptureWarningCode {
  explicitlyUncalibrated,
  partialCalibration,

  /// A warning the setup check itself recorded (policy warning-level noise
  /// or SNR).
  setupQuality,
}

/// What the UI should offer the user to resolve a blocker. The gate decides
/// this once; the Capture button and any inline banner both read it.
enum MeasurementCaptureRemediation {
  createOrOpenProject,
  manageMicrophone,
  selectInputDevice,
  checkInputDeviceAgain,
  grantMicrophonePermission,
  runSetupCheck,
}

extension MeasurementCaptureBlockerCodeX on MeasurementCaptureBlockerCode {
  MeasurementCaptureRemediation get remediation => switch (this) {
        MeasurementCaptureBlockerCode.noProject =>
          MeasurementCaptureRemediation.createOrOpenProject,
        MeasurementCaptureBlockerCode.noMicrophoneProfile ||
        MeasurementCaptureBlockerCode.invalidCalibration ||
        MeasurementCaptureBlockerCode.legacyUnknownCalibration =>
          MeasurementCaptureRemediation.manageMicrophone,
        MeasurementCaptureBlockerCode.noInputDeviceSelected =>
          MeasurementCaptureRemediation.selectInputDevice,
        MeasurementCaptureBlockerCode.inputDeviceUnavailable =>
          MeasurementCaptureRemediation.checkInputDeviceAgain,
        MeasurementCaptureBlockerCode.microphonePermissionDenied =>
          MeasurementCaptureRemediation.grantMicrophonePermission,
        // Every remaining case is "the setup check is missing, invalid,
        // expired, or no longer describes the current chain" -- all resolved
        // by running the Guided Measurement Setup check again.
        _ => MeasurementCaptureRemediation.runSetupCheck,
      };
}

class MeasurementCaptureBlocker {
  final MeasurementCaptureBlockerCode code;

  /// User-facing Korean message, matching the Phase 3-D3 §2 copy.
  final String message;

  const MeasurementCaptureBlocker(this.code, this.message);

  MeasurementCaptureRemediation get remediation => code.remediation;

  @override
  String toString() => '${code.name}: $message';
}

class MeasurementCaptureWarning {
  final MeasurementCaptureWarningCode code;
  final String message;

  const MeasurementCaptureWarning(this.code, this.message);

  @override
  String toString() => '${code.name}: $message';
}
