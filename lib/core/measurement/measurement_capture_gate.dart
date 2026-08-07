// ── TUNAI PRO Phase 3-D3 — shared Factory/Room capture gate ─────────────────
//
// ONE pure evaluator for "may a real measurement capture start right now?".
// Factory (LiveMeasurementController) and Room (RoomMeasurementController)
// both call this — the gate logic is never duplicated per path, so the two
// can never drift into disagreeing about what a trustworthy measurement
// chain is.
//
// Pure and synchronous: no provider reads, no I/O, no clock of its own
// (`now` is injected). Everything it decides is a function of its inputs,
// which is what lets the Capture button and the controller run the SAME
// evaluation and reach the same verdict — the UI does not compute its own
// readiness (Phase 3-D3 §2), it renders this result.
//
// Fail-closed by construction: anything unknown (no setup check, legacy
// calibration provenance, a readiness snapshot that no longer describes the
// current chain) blocks. Nothing is assumed Ready.
//
// Two live runtime facts cannot be derived from persisted project state and
// are therefore injected by the caller: the runtime input-device state
// (`inputAvailability`, derived from a FRESH enumeration via
// [MeasurementCaptureGate.resolveInputAvailability]) and whether microphone
// permission is currently granted (`microphonePermissionGranted`). Both
// default to null = unknown = blocked, never to "probably fine".
//
// System-default input is explicitly NOT assumed to exist: `record`'s
// `RecordConfig.device == null` asks the OS for its default input, macOS
// `AVCaptureDevice.default(for: .audio)` can return nil, and the plugin
// offers no "does a default input exist right now?" query. A system-default
// selection therefore preflights to `systemDefaultUnverified` at best (never
// `available`), requires a non-empty fresh enumeration + permission + a
// prior successful setup check on the same system-default selection, and
// leaves the recorder start as the final fail-closed authority. A recording
// failure is never converted into a measurement success.

library;

import '../calibration/calibration_types.dart';
import '../pro_project.dart';
import 'measurement_capture_gate_types.dart';
import 'measurement_input_device.dart';
import 'measurement_quality_policy.dart';
import 'measurement_setup_readiness.dart';
import 'measurement_setup_readiness_project_identity.dart';
import 'measurement_warning_acknowledgement.dart';

class MeasurementCaptureGateResult {
  /// True only when there are no blockers AND every raised warning is
  /// covered by an explicit acknowledgement for this exact chain identity.
  final bool canCapture;

  final List<MeasurementCaptureBlocker> blockers;
  final List<MeasurementCaptureWarning> warnings;

  /// True when warnings exist that are not (yet) covered by an
  /// acknowledgement. The UI shows the "확인하고 측정" flow for this; a
  /// controller called directly must refuse.
  final bool requiresExplicitWarningAcknowledgement;

  /// The setup readiness generation this verdict was computed against —
  /// recorded on the resulting capture so a later Accept can prove the
  /// capture happened under a still-current generation.
  final String? activeGenerationId;

  /// Microphone profile checksum (null when no profile / no checksum).
  final String? profileIdentity;

  /// `'system-default'` or `'device:<id>'`, or null when nothing selected.
  final String? deviceIdentity;

  /// The runtime device state this verdict was computed from. Exposed so the
  /// UI can label a system-default capture honestly
  /// ([MeasurementRuntimeInputAvailability.systemDefaultUnverified] must
  /// never be shown as "confirmed") instead of re-deriving its own guess.
  final MeasurementRuntimeInputAvailability? inputAvailability;

  const MeasurementCaptureGateResult({
    required this.canCapture,
    required this.blockers,
    required this.warnings,
    required this.requiresExplicitWarningAcknowledgement,
    required this.activeGenerationId,
    required this.profileIdentity,
    required this.deviceIdentity,
    this.inputAvailability,
  });

  /// The blocker to surface first — blockers are appended in measurement
  /// chain order, so the earliest problem is the one the user must fix
  /// first.
  MeasurementCaptureBlocker? get primaryBlocker =>
      blockers.isEmpty ? null : blockers.first;

  bool hasBlocker(MeasurementCaptureBlockerCode code) =>
      blockers.any((b) => b.code == code);

  bool hasWarning(MeasurementCaptureWarningCode code) =>
      warnings.any((w) => w.code == code);

  Set<MeasurementCaptureWarningCode> get warningCodes =>
      warnings.map((w) => w.code).toSet();
}

abstract final class MeasurementCaptureGate {
  /// Derives the runtime device state from a FRESH enumeration. Callers
  /// (controller preflight and UI alike) use this instead of inventing their
  /// own rule, so "what counts as present" is defined once.
  ///
  /// A system-default selection never resolves to
  /// [MeasurementRuntimeInputAvailability.available]: the plugin cannot tell
  /// us which device (if any) the OS would pick, so the strongest honest
  /// verdict is [MeasurementRuntimeInputAvailability.systemDefaultUnverified]
  /// — and only when at least one input device actually exists.
  static MeasurementRuntimeInputAvailability resolveInputAvailability({
    required MeasurementInputDeviceSelection? selection,
    required List<MeasurementInputDeviceDescriptor> freshDevices,
  }) {
    if (selection == null || freshDevices.isEmpty) {
      return MeasurementRuntimeInputAvailability.unavailable;
    }
    if (selection.useSystemDefault) {
      return MeasurementRuntimeInputAvailability.systemDefaultUnverified;
    }
    return freshDevices.any((d) => d.id == selection.deviceId)
        ? MeasurementRuntimeInputAvailability.available
        : MeasurementRuntimeInputAvailability.unavailable;
  }

  static MeasurementCaptureGateResult evaluate({
    required ProProject? project,
    required DateTime now,
    MeasurementQualityPolicy? policy,
    MeasurementRuntimeInputAvailability? inputAvailability,
    bool? microphonePermissionGranted,
    MeasurementWarningAcknowledgement? acknowledgement,
  }) {
    final blockers = <MeasurementCaptureBlocker>[];
    final warnings = <MeasurementCaptureWarning>[];

    if (project == null) {
      return const MeasurementCaptureGateResult(
        canCapture: false,
        blockers: [
          MeasurementCaptureBlocker(
              MeasurementCaptureBlockerCode.noProject, '프로젝트가 열려 있지 않습니다.'),
        ],
        warnings: [],
        requiresExplicitWarningAcknowledgement: false,
        activeGenerationId: null,
        profileIdentity: null,
        deviceIdentity: null,
      );
    }

    final effectivePolicy = policy ?? MeasurementQualityPolicy.proProvisional();
    final profile = project.selectedMicrophoneProfile;
    final selection = project.selectedInputDevice;
    final readiness = project.currentSetupReadiness;
    final currentIdentity = MeasurementSetupReadinessProjectIdentity.forProject(
        project,
        policy: effectivePolicy);

    final profileIdentity = profile?.checksum;
    final deviceIdentity = selection == null
        ? null
        : (selection.useSystemDefault
            ? MeasurementSetupReadinessIdentity
                .kSystemDefaultInputDeviceIdentity
            : MeasurementSetupReadinessIdentity.specificInputDeviceIdentity(
                selection.deviceId!));

    // ── Chain step 1: microphone profile ──────────────────────────────────
    if (profile == null) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.noMicrophoneProfile,
          '측정 마이크가 선택되지 않았습니다.'));
    } else {
      _appendCalibrationVerdict(profile, blockers, warnings);
    }

    // ── Chain step 2: input device ────────────────────────────────────────
    //
    // A system-default selection gets NO free pass: `RecordConfig.device ==
    // null` asks the OS for its default input, and macOS
    // `AVCaptureDevice.default(for: .audio)` may return nil, so "there is a
    // default" is never assumed. The best a preflight can do is require a
    // non-empty fresh enumeration (plus permission, checked below, plus a
    // prior successful setup check on the SAME system-default selection,
    // which the readiness identity comparison already enforces) and then let
    // the recorder start be the final fail-closed authority.
    if (selection == null) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.noInputDeviceSelected,
          '입력 장치가 선택되지 않았습니다.'));
    } else if (inputAvailability !=
            MeasurementRuntimeInputAvailability.available &&
        inputAvailability !=
            MeasurementRuntimeInputAvailability.systemDefaultUnverified) {
      // Covers both `unavailable` and null (unknown) — unknown is never
      // upgraded to "probably fine".
      blockers.add(MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.inputDeviceUnavailable,
          selection.useSystemDefault
              ? '사용 가능한 입력 장치가 없습니다.'
              : '선택한 입력 장치를 찾을 수 없습니다.'));
    }

    // ── Chain step 3: microphone permission ───────────────────────────────
    if (microphonePermissionGranted != true) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.microphonePermissionDenied,
          '마이크 권한이 허용되지 않았습니다.'));
    }

    // ── Chain step 4: setup readiness ─────────────────────────────────────
    if (readiness == null) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupNotChecked, '측정 준비 확인이 필요합니다.'));
    } else {
      _appendReadinessVerdict(
          readiness, currentIdentity, now, blockers, warnings);
    }

    final raisedWarnings = warnings.map((w) => w.code).toSet();
    final acknowledged = raisedWarnings.isEmpty ||
        (acknowledgement != null &&
            readiness != null &&
            acknowledgement.covers(
              projectId: project.id,
              profileIdentity: profileIdentity,
              deviceIdentity: deviceIdentity ?? '',
              readinessGenerationId: readiness.generationId,
              raisedWarnings: raisedWarnings,
            ));

    return MeasurementCaptureGateResult(
      canCapture: blockers.isEmpty && acknowledged,
      blockers: List.unmodifiable(blockers),
      warnings: List.unmodifiable(warnings),
      requiresExplicitWarningAcknowledgement:
          raisedWarnings.isNotEmpty && !acknowledged,
      activeGenerationId: readiness?.generationId,
      profileIdentity: profileIdentity,
      deviceIdentity: deviceIdentity,
      inputAvailability: inputAvailability,
    );
  }

  /// Calibration provenance of the SELECTED PROFILE (not of a past capture).
  /// invalid / legacy-unknown block; explicitly-uncalibrated and partial
  /// coverage warn. Note this is the capture policy only — Room Auto PEQ
  /// applies its own, stricter calibration policy separately.
  static void _appendCalibrationVerdict(
    MeasurementMicrophoneProfile profile,
    List<MeasurementCaptureBlocker> blockers,
    List<MeasurementCaptureWarning> warnings,
  ) {
    if (profile.calibrationSource == CalibrationSource.uncalibrated) {
      warnings.add(const MeasurementCaptureWarning(
          MeasurementCaptureWarningCode.explicitlyUncalibrated,
          '보정되지 않은 마이크로 측정합니다.'));
      return;
    }
    final curve = profile.calibrationCurve;
    if (curve == null) {
      // A profile that claims a calibrated source but carries no curve is
      // unrecoverable provenance, not "probably fine".
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.legacyUnknownCalibration,
          '마이크 보정 정보가 없습니다.'));
      return;
    }
    if (!curve.isStructurallyValid) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.invalidCalibration,
          '마이크 보정 정보가 올바르지 않습니다.'));
    }
  }

  /// Setup readiness verdict: existence, its own recorded blockers, expiry,
  /// and a field-by-field identity comparison so the user is told exactly
  /// WHICH part of the chain changed rather than a generic "stale".
  static void _appendReadinessVerdict(
    MeasurementSetupReadinessSnapshot readiness,
    MeasurementSetupReadinessIdentity current,
    DateTime now,
    List<MeasurementCaptureBlocker> blockers,
    List<MeasurementCaptureWarning> warnings,
  ) {
    if (!readiness.isReady) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupNotReady, '측정 준비 확인에 실패했습니다.'));
      // Forward what the setup check itself decided (malformed capture,
      // clipping, blocking level/noise/SNR) rather than re-deriving any
      // threshold here.
      for (final b in readiness.blockers) {
        blockers.add(MeasurementCaptureBlocker(
            MeasurementCaptureBlockerCode.setupQuality, b));
      }
    }

    if (readiness.isExpired(now: now)) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupExpired, '측정 준비 확인이 만료되었습니다.'));
    }

    final was = readiness.identity;
    if (was.projectId != current.projectId) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupProjectMismatch,
          '측정 준비 확인이 다른 프로젝트에서 수행되었습니다.'));
    }
    if (was.profileChecksum != current.profileChecksum) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupProfileMismatch,
          '측정 준비 확인 이후 마이크가 변경되었습니다.'));
    }
    if (was.calibrationCurveChecksum != current.calibrationCurveChecksum) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupCalibrationCurveMismatch,
          '측정 준비 확인 이후 보정 커브가 변경되었습니다.'));
    }
    if (was.calibrationAngle != current.calibrationAngle) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupOrientationMismatch,
          '측정 준비 확인 이후 마이크 방향 설정이 변경되었습니다.'));
    }
    if (was.inputDeviceIdentity != current.inputDeviceIdentity) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupInputDeviceMismatch,
          '측정 준비 확인 이후 입력 장치가 변경되었습니다.'));
    }
    if (was.qualityPolicyVersion != current.qualityPolicyVersion) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupPolicyVersionMismatch,
          '측정 품질 정책이 변경되어 재확인이 필요합니다.'));
    }
    if (was.expectedSampleRate != current.expectedSampleRate) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupSampleRateMismatch,
          '측정 준비 확인의 샘플레이트가 현재 설정과 다릅니다.'));
    }
    if (was.expectedChannelCount != current.expectedChannelCount) {
      blockers.add(const MeasurementCaptureBlocker(
          MeasurementCaptureBlockerCode.setupChannelMismatch,
          '측정 준비 확인의 채널 수가 현재 설정과 다릅니다.'));
    }

    for (final w in readiness.warnings) {
      warnings.add(MeasurementCaptureWarning(
          MeasurementCaptureWarningCode.setupQuality, w));
    }
  }
}
