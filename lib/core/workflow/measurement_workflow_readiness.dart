// ── TUNAI PRO Phase 3-D3C-3 §1/§2/§3/§14 — Measurement workflow read model ──
//
// The SINGLE typed read model Phase 3-E's Workspace Home renders. It answers
// "where is this project in the measurement workflow, and what is the one
// thing to do next" — nothing else. Home must not re-derive any of it.
//
// Every field is derived from persisted production state or from an existing
// gate's verdict. Nothing here is a convenience boolean invented to make a
// card look finished: a state the current architecture cannot PROVE is
// reported as unknown or false, never as complete.

library;

import '../hardware/hardware_connection_readiness.dart';
import '../pro_correction_cycle.dart';

/// What the user must do next. Exactly one of these is returned as the
/// primary action at any moment — [MeasurementWorkflowReadiness
/// .nextRecommendedAction] — so Home never re-runs a priority calculation.
enum MeasurementWorkflowAction {
  createOrOpenProject,
  selectMicrophone,
  fixCalibration,
  selectInputDevice,
  checkMeasurementSetup,
  measureFactoryDrivers,
  runFactoryGuidedTuning,
  measureRoomBefore,
  resolveRoomMeasurementQuality,
  generateRoomAutoPeq,
  deployRoomCorrection,
  measureRoomAfter,
  resolveBeforeAfterMismatch,
  reviewClosedLoop,
  complete,
}

/// Why the workflow cannot advance. Typed so Home branches on a code, never
/// on a message string.
enum MeasurementWorkflowBlockerCode {
  noProject,
  noMicrophone,
  calibrationInvalid,
  noInputDevice,
  setupRequired,
  factoryDriversMissing,
  factoryTuningIncomplete,
  roomBeforeIncomplete,
  roomBeforeQualityFailed,
  roomAutoPeqNotApproved,
  roomCorrectionNotDeployed,
  roomAfterIncomplete,
  beforeAfterMismatch,
}

/// Conditions worth telling the user about that do NOT stop the workflow.
enum MeasurementWorkflowWarningCode {
  calibrationPartial,
  calibrationUncalibrated,
  setupWarning,

  /// The project carries measurements from before provenance was recorded.
  /// They stay usable for Factory work; Room Auto PEQ will require fresh
  /// captures because of its own quality gate.
  legacyMeasurementData,

  closedLoopPolicyVersionMismatch,
  closedLoopUncalibrated,
}

/// The setup check's standing, distinguishing "never run" from "ran and
/// failed" from "ran, but the chain has changed since".
enum MeasurementWorkflowSetupState {
  notChecked,
  ready,

  /// Ready, but the check itself recorded a non-blocking warning.
  warning,

  /// The check ran and refused.
  blocked,

  /// The check is still within its validity window, but part of the
  /// measurement chain (mic, calibration, device, policy, format) changed
  /// since it ran.
  stale,

  /// Past its validity window.
  expired,
}

/// How the input device was chosen. `systemDefault` is a real user decision
/// and is never upgraded to a verified device identity.
enum MeasurementWorkflowInputSelectionKind {
  none,
  systemDefault,
  specificDevice,
}

/// Runtime state of the input device AS LAST KNOWN. This read model performs
/// no device enumeration (see §9) — live verification belongs to Guided
/// Setup and the capture preflight.
enum MeasurementWorkflowInputAvailability {
  /// A specific device backed by a currently-valid setup generation. Means
  /// "worked at the last successful check", never "confirmed present now".
  lastKnownValid,

  /// System-default selection. The concrete device is unknowable here and
  /// must never be shown as confirmed.
  systemDefaultUnverified,

  /// Nothing selected, or no valid setup to back the selection.
  unknown,
}

/// The five stages Home shows progress against.
enum MeasurementWorkflowStage {
  project,
  measurementSetup,
  factoryTuning,
  roomTuning,
  verification,
}

enum MeasurementWorkflowStageState {
  notStarted,
  inProgress,
  complete,
  blocked,
  warning,
}

class MeasurementWorkflowReadiness {
  // ── Project ────────────────────────────────────────────────────────────
  final bool hasProject;
  final String? projectId;
  final String? projectName;

  // ── Microphone ─────────────────────────────────────────────────────────
  final bool microphoneSelected;
  final String? microphoneLabel;

  /// The SELECTED PROFILE's calibration standing (not a past capture's).
  final MeasurementWorkflowCalibrationState calibrationStatus;

  // ── Input ──────────────────────────────────────────────────────────────
  final bool inputSelected;
  final String? inputLabel;
  final MeasurementWorkflowInputSelectionKind inputSelectionKind;

  /// False whenever the availability below is a default rather than
  /// something a successful setup actually established.
  final bool runtimeAvailabilityKnown;
  final MeasurementWorkflowInputAvailability runtimeAvailability;

  // ── Setup ──────────────────────────────────────────────────────────────
  final MeasurementWorkflowSetupState setupState;
  final String? setupGenerationId;
  final MeasurementWorkflowBlockerCode? setupPrimaryBlocker;
  final List<MeasurementWorkflowWarningCode> setupWarnings;

  // ── Factory ────────────────────────────────────────────────────────────
  final int requiredDriverCount;
  final int measuredDriverCount;
  final bool driverMeasurementReady;
  final bool guidedTuningReady;

  /// Proven by at least one persisted [CorrectionCycle] that reached
  /// [CorrectionCycleDecision.improvedAndComplete] — never inferred from an
  /// export package existing.
  final bool factoryTuningCompleted;

  /// The verdict of the most recent COMPLETED Factory correction cycle for
  /// this project, or null when none has reached a verdict. Lets Home say
  /// "추가 보정 권장" vs "재검토 필요" instead of only "not finished".
  final CorrectionCycleDecision? factoryLastCycleDecision;

  // ── Room ───────────────────────────────────────────────────────────────
  final int beforeCount;
  final bool beforeMeasurementComplete;
  final bool beforeQualityReady;
  final bool roomAutoPeqReady;
  final bool roomAutoPeqApproved;

  /// RoomAfterGate's verdict — approved plan identity + matching write result
  /// + full readback verification. Never a bare "a write happened".
  final bool correctionDeployedAndVerified;
  final bool afterAvailable;
  final int afterCount;
  final bool afterMeasurementComplete;
  final bool beforeAfterComparable;
  final bool closedLoopComplete;
  final CorrectionCycleDecision? closedLoopDecision;
  final List<MeasurementWorkflowWarningCode> closedLoopWarnings;

  // ── Hardware ───────────────────────────────────────────────────────────
  /// Null when nobody has established a session for THIS project's DSP
  /// target — deliberately tri-state, so "not checked" never renders as
  /// "disconnected".
  final bool? hardwareConnected;

  /// The full typed hardware verdict (Phase 3-F1). Describes whether the
  /// current DSP SESSION is usable — never whether a particular correction
  /// was written; [correctionDeployedAndVerified] alone answers that.
  final HardwareConnectionState hardwareConnectionState;

  /// The live session (if any) matches this project's DSP target.
  final bool hardwareTargetCompatible;

  /// A handshake-verified, identity-confirmed session for this project.
  final bool hardwareReadyForDeploy;
  final bool roomCorrectionVerified;
  final String? deployBlockedReason;

  // ── Guidance ───────────────────────────────────────────────────────────
  final MeasurementWorkflowAction nextRecommendedAction;
  final MeasurementWorkflowBlockerCode? primaryBlocker;
  final List<MeasurementWorkflowWarningCode> warnings;

  /// Per-stage progress. Always contains an entry for every
  /// [MeasurementWorkflowStage].
  final Map<MeasurementWorkflowStage, MeasurementWorkflowStageState> stages;

  const MeasurementWorkflowReadiness({
    required this.hasProject,
    this.projectId,
    this.projectName,
    required this.microphoneSelected,
    this.microphoneLabel,
    required this.calibrationStatus,
    required this.inputSelected,
    this.inputLabel,
    required this.inputSelectionKind,
    required this.runtimeAvailabilityKnown,
    required this.runtimeAvailability,
    required this.setupState,
    this.setupGenerationId,
    this.setupPrimaryBlocker,
    required this.setupWarnings,
    required this.requiredDriverCount,
    required this.measuredDriverCount,
    required this.driverMeasurementReady,
    required this.guidedTuningReady,
    required this.factoryTuningCompleted,
    this.factoryLastCycleDecision,
    required this.beforeCount,
    required this.beforeMeasurementComplete,
    required this.beforeQualityReady,
    required this.roomAutoPeqReady,
    required this.roomAutoPeqApproved,
    required this.correctionDeployedAndVerified,
    required this.afterAvailable,
    required this.afterCount,
    required this.afterMeasurementComplete,
    required this.beforeAfterComparable,
    required this.closedLoopComplete,
    this.closedLoopDecision,
    required this.closedLoopWarnings,
    this.hardwareConnected,
    this.hardwareConnectionState = HardwareConnectionState.unknown,
    this.hardwareTargetCompatible = false,
    this.hardwareReadyForDeploy = false,
    required this.roomCorrectionVerified,
    this.deployBlockedReason,
    required this.nextRecommendedAction,
    this.primaryBlocker,
    required this.warnings,
    required this.stages,
  });

  MeasurementWorkflowStageState stage(MeasurementWorkflowStage s) =>
      stages[s] ?? MeasurementWorkflowStageState.notStarted;

  /// Completed-stage count out of five. Deliberately an integer ratio rather
  /// than a percentage — a "73%" here would be invented precision.
  int get completedStages => stages.values
      .where((s) => s == MeasurementWorkflowStageState.complete)
      .length;

  int get totalStages => MeasurementWorkflowStage.values.length;

  bool hasWarning(MeasurementWorkflowWarningCode code) =>
      warnings.contains(code);
}

/// The selected microphone profile's calibration standing, kept distinct from
/// CalibrationStatus (which describes a measurement) and mapped from the
/// existing CalibrationReadiness levels.
enum MeasurementWorkflowCalibrationState {
  none,
  calibrated,
  partiallyCalibrated,
  explicitlyUncalibrated,
  legacyUnknown,
  invalid,
}
