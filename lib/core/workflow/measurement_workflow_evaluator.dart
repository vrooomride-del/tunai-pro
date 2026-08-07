// ── TUNAI PRO Phase 3-D3C-3 §4/§5/§6/§7/§8/§9/§10/§11/§12 — derivation ─────
//
// Pure derivation of [MeasurementWorkflowReadiness]. No I/O, no provider
// reads, no DSP write, no acoustic math, no device enumeration.
//
// Everything this file decides is either read straight off persisted project
// state or delegated to the gate that already owns that decision:
//   - project / microphone / calibration / input / setup → MeasurementCaptureGate
//   - Room Before pair quality                           → RoomBeforePairQualityGate
//   - Room correction actually deployed                  → RoomAfterGate
//   - Before/After comparability                         → RoomBeforeAfterComparisonGate
// No threshold, coverage window or hardware-success rule is re-implemented
// here. Where a gate says no, this model says no for the same reason.
//
// Simulated data (MeasurementSession / simulateCapture / placeholder results)
// is structurally unreachable from here: this file only ever reads
// ProProject, RoomAutoPeqState and HardwareWriteExecutionResult, none of
// which the simulation path writes to.

library;

import '../calibration/calibration_frequency_coverage.dart';
import '../hardware/hardware_connection_readiness.dart';
import '../calibration/calibration_types.dart';
import '../calibration/microphone_profile_edit_rules.dart';
import '../measurement/measurement_capture_gate.dart';
import '../measurement/measurement_capture_gate_types.dart';
import '../orchestrator/room_after_gate.dart';
import '../orchestrator/room_auto_peq.dart'
    show roomAutoPeqMinHz, roomAutoPeqMaxHz;
import '../orchestrator/room_before_after_comparison_gate.dart';
import '../orchestrator/room_before_pair_quality_gate.dart';
import '../deploy/pro_hardware_write_executor.dart'
    show HardwareWriteExecutionResult;
import '../measurement/measurement_before_after_comparison.dart';
import '../pro_acoustic_data.dart';
import '../pro_correction_cycle.dart';
import '../pro_project.dart';
import 'measurement_workflow_readiness.dart';

abstract final class MeasurementWorkflowEvaluator {
  static MeasurementWorkflowReadiness evaluate({
    required ProProject? project,
    required String? roomApprovedPackageId,
    required HardwareWriteExecutionResult? lastHardwareWriteResult,
    required DateTime now,
    CorrectionCycleDecision? closedLoopDecision,
    RoomBeforeAfterComparisonGateResult? closedLoopComparison,
    HardwareConnectionReadiness? hardware,
  }) {
    if (project == null) return _noProject();

    // ── Stages 1–5 come from the capture gate, not from a second opinion ──
    //
    // Two of the gate's inputs are RUNTIME facts (§9): a live device
    // enumeration and the microphone permission state. This read model must
    // never perform either, so both are supplied as "not the thing being
    // judged here" — a missing device or a denied permission is Guided
    // Setup's and the capture preflight's verdict to deliver, not Home's.
    // The gate's remaining verdicts (project, profile, calibration,
    // selection presence, setup readiness/identity/expiry) are all derived
    // from persisted state and are exactly what Home needs.
    final selection = project.selectedInputDevice;
    final gate = MeasurementCaptureGate.evaluate(
      project: project,
      now: now,
      inputAvailability: selection == null
          ? null
          : (selection.useSystemDefault
              ? MeasurementRuntimeInputAvailability.systemDefaultUnverified
              : MeasurementRuntimeInputAvailability.available),
      microphonePermissionGranted: true,
    );

    final profile = project.selectedMicrophoneProfile;
    final calibration = _calibrationState(profile);
    final setupState = _setupState(project, gate);
    final readiness = project.currentSetupReadiness;

    final inputKind = selection == null
        ? MeasurementWorkflowInputSelectionKind.none
        : (selection.useSystemDefault
            ? MeasurementWorkflowInputSelectionKind.systemDefault
            : MeasurementWorkflowInputSelectionKind.specificDevice);

    // A specific device is only ever "last known valid", and only while a
    // setup generation actually backs it. System default stays unverified by
    // construction — its concrete identity is unknowable without a scan.
    final availability = switch (inputKind) {
      MeasurementWorkflowInputSelectionKind.none =>
        MeasurementWorkflowInputAvailability.unknown,
      MeasurementWorkflowInputSelectionKind.systemDefault =>
        MeasurementWorkflowInputAvailability.systemDefaultUnverified,
      MeasurementWorkflowInputSelectionKind.specificDevice =>
        setupState == MeasurementWorkflowSetupState.ready ||
                setupState == MeasurementWorkflowSetupState.warning
            ? MeasurementWorkflowInputAvailability.lastKnownValid
            : MeasurementWorkflowInputAvailability.unknown,
    };

    // ── Factory ──────────────────────────────────────────────────────────
    final acoustic = project.acousticState;
    final requiredDrivers = acoustic.totalDrivers;
    final measuredDrivers = acoustic.parsedFrdCount;
    final driversReady =
        requiredDrivers > 0 && measuredDrivers >= requiredDrivers;

    // §5 — the ONLY persisted proof that Factory Guided Tuning finished is a
    // CorrectionCycle that reached a verdict of improvedAndComplete. An
    // export package, a deploy result or a non-empty tuning state prove
    // none of that, so none of them are consulted here.
    final ownCompletedCycles = [
      for (final c in project.correctionCycles)
        if (c.projectId == project.id && c.isComplete) c,
    ];
    final factoryCompleted = ownCompletedCycles
        .any((c) => c.decision == CorrectionCycleDecision.improvedAndComplete);
    // Latest by cycleNumber — the list is append-ordered, but ordering by the
    // cycle's own number is what the domain actually defines as "latest".
    final latestCycle = ownCompletedCycles.isEmpty
        ? null
        : ownCompletedCycles
            .reduce((a, b) => b.cycleNumber >= a.cycleNumber ? b : a);

    // ── Room ─────────────────────────────────────────────────────────────
    final room = project.roomState;
    final beforeCount = room.before.readyCount;
    final beforeComplete = room.before.isComplete;
    final beforeQuality = beforeComplete
        ? RoomBeforePairQualityGate.evaluate(
            projectId: project.id,
            left: room.before.leftSystemFrd,
            right: room.before.rightSystemFrd,
          ).canGenerate
        : false;

    final autoPeqApproved = roomApprovedPackageId != null;
    final afterGate = RoomAfterGate.evaluate(
      approvedPackageId: roomApprovedPackageId,
      lastResult: lastHardwareWriteResult,
    );
    final deployedAndVerified = afterGate.available;

    final afterCount = room.after.readyCount;
    final afterComplete = room.after.isComplete;

    final comparison = closedLoopComparison ??
        (beforeComplete && afterComplete
            ? RoomBeforeAfterComparisonGate.evaluateSnapshots(
                before: room.before, after: room.after)
            : null);
    final comparable = comparison?.canEvaluate ?? false;

    // A verdict only counts when the pair was actually comparable. A blocked
    // comparison is never reported as a completed loop.
    final loopComplete = comparable && closedLoopDecision != null;

    // ── Warnings ─────────────────────────────────────────────────────────
    final setupWarnings = <MeasurementWorkflowWarningCode>[
      for (final w in gate.warnings)
        switch (w.code) {
          MeasurementCaptureWarningCode.explicitlyUncalibrated =>
            MeasurementWorkflowWarningCode.calibrationUncalibrated,
          MeasurementCaptureWarningCode.partialCalibration =>
            MeasurementWorkflowWarningCode.calibrationPartial,
          MeasurementCaptureWarningCode.setupQuality =>
            MeasurementWorkflowWarningCode.setupWarning,
        },
    ];

    final closedLoopWarnings = <MeasurementWorkflowWarningCode>[
      for (final w
          in comparison?.warnings ?? const <MeasurementBeforeAfterWarning>[])
        switch (w.code) {
          MeasurementBeforeAfterWarningCode.qualityPolicyVersionMismatch =>
            MeasurementWorkflowWarningCode.closedLoopPolicyVersionMismatch,
          MeasurementBeforeAfterWarningCode.bothExplicitlyUncalibrated =>
            MeasurementWorkflowWarningCode.closedLoopUncalibrated,
        },
    ];

    final warnings = <MeasurementWorkflowWarningCode>{
      ...setupWarnings,
      ...closedLoopWarnings,
      // §12 — legacy data is surfaced, never migrated and never a blocker.
      if (_hasLegacyMeasurementData(project))
        MeasurementWorkflowWarningCode.legacyMeasurementData,
    }.toList();

    // ── §4 next action: first unmet condition wins, exactly one ──────────
    final (action, blocker) = _nextAction(
      gate: gate,
      setupState: setupState,
      driversReady: driversReady,
      requiredDrivers: requiredDrivers,
      factoryCompleted: factoryCompleted,
      beforeComplete: beforeComplete,
      beforeQuality: beforeQuality,
      autoPeqApproved: autoPeqApproved,
      deployedAndVerified: deployedAndVerified,
      afterComplete: afterComplete,
      comparable: comparable,
      loopComplete: loopComplete,
    );

    return MeasurementWorkflowReadiness(
      hasProject: true,
      projectId: project.id,
      projectName: project.name,
      microphoneSelected: profile != null,
      microphoneLabel: profile == null
          ? null
          : '${profile.manufacturer} ${profile.model}'.trim(),
      calibrationStatus: calibration,
      inputSelected: selection != null,
      inputLabel: selection?.labelSnapshot,
      inputSelectionKind: inputKind,
      runtimeAvailabilityKnown:
          availability == MeasurementWorkflowInputAvailability.lastKnownValid,
      runtimeAvailability: availability,
      setupState: setupState,
      setupGenerationId: readiness?.generationId,
      setupPrimaryBlocker: setupState == MeasurementWorkflowSetupState.ready ||
              setupState == MeasurementWorkflowSetupState.warning
          ? null
          : MeasurementWorkflowBlockerCode.setupRequired,
      setupWarnings: setupWarnings,
      requiredDriverCount: requiredDrivers,
      measuredDriverCount: measuredDrivers,
      driverMeasurementReady: driversReady,
      guidedTuningReady: driversReady,
      factoryTuningCompleted: factoryCompleted,
      factoryLastCycleDecision: latestCycle?.decision,
      beforeCount: beforeCount,
      beforeMeasurementComplete: beforeComplete,
      beforeQualityReady: beforeQuality,
      roomAutoPeqReady: beforeComplete && beforeQuality,
      roomAutoPeqApproved: autoPeqApproved,
      correctionDeployedAndVerified: deployedAndVerified,
      afterAvailable: deployedAndVerified,
      afterCount: afterCount,
      afterMeasurementComplete: afterComplete,
      beforeAfterComparable: comparable,
      closedLoopComplete: loopComplete,
      closedLoopDecision: loopComplete ? closedLoopDecision : null,
      closedLoopWarnings: closedLoopWarnings,
      // Phase 3-F1 — the live ADAU1701 session, derived by
      // HardwareConnectionEvaluator from the existing transport/handshake
      // contract. Still tri-state: "nobody has checked" stays null rather
      // than becoming a false that reads as "disconnected".
      hardwareConnected: hardware?.connectedTriState,
      hardwareConnectionState:
          hardware?.state ?? HardwareConnectionState.unknown,
      hardwareTargetCompatible: hardware?.targetCompatible ?? false,
      // Deliberately NOT combined with correctionDeployedAndVerified: this
      // says the DSP session is usable, that says a specific correction was
      // written and readback-verified. RoomAfterGate remains the only
      // authority on the latter.
      hardwareReadyForDeploy: hardware?.readyForDeploy ?? false,
      roomCorrectionVerified: deployedAndVerified,
      deployBlockedReason: autoPeqApproved && !deployedAndVerified
          ? afterGate.blockedReason
          : null,
      nextRecommendedAction: action,
      primaryBlocker: blocker,
      warnings: warnings,
      stages: _stages(
        setupState: setupState,
        driversReady: driversReady,
        measuredDrivers: measuredDrivers,
        factoryCompleted: factoryCompleted,
        beforeCount: beforeCount,
        beforeComplete: beforeComplete,
        beforeQuality: beforeQuality,
        deployedAndVerified: deployedAndVerified,
        afterCount: afterCount,
        afterComplete: afterComplete,
        comparable: comparable,
        loopComplete: loopComplete,
        hasSetupWarning: setupWarnings.isNotEmpty,
      ),
    );
  }

  // ── §4 priority ladder ─────────────────────────────────────────────────

  static (MeasurementWorkflowAction, MeasurementWorkflowBlockerCode?)
      _nextAction({
    required MeasurementCaptureGateResult gate,
    required MeasurementWorkflowSetupState setupState,
    required bool driversReady,
    required int requiredDrivers,
    required bool factoryCompleted,
    required bool beforeComplete,
    required bool beforeQuality,
    required bool autoPeqApproved,
    required bool deployedAndVerified,
    required bool afterComplete,
    required bool comparable,
    required bool loopComplete,
  }) {
    // 2–5 are exactly the capture gate's own chain order, read off its
    // primary blocker so the two can never disagree about what is wrong.
    for (final b in gate.blockers) {
      switch (b.code) {
        case MeasurementCaptureBlockerCode.noMicrophoneProfile:
          return (
            MeasurementWorkflowAction.selectMicrophone,
            MeasurementWorkflowBlockerCode.noMicrophone
          );
        case MeasurementCaptureBlockerCode.invalidCalibration:
        case MeasurementCaptureBlockerCode.legacyUnknownCalibration:
          return (
            MeasurementWorkflowAction.fixCalibration,
            MeasurementWorkflowBlockerCode.calibrationInvalid
          );
        case MeasurementCaptureBlockerCode.noInputDeviceSelected:
          return (
            MeasurementWorkflowAction.selectInputDevice,
            MeasurementWorkflowBlockerCode.noInputDevice
          );
        default:
          break;
      }
    }
    if (setupState != MeasurementWorkflowSetupState.ready &&
        setupState != MeasurementWorkflowSetupState.warning) {
      return (
        MeasurementWorkflowAction.checkMeasurementSetup,
        MeasurementWorkflowBlockerCode.setupRequired
      );
    }

    // 6–7 Factory. A project with no driver channels defined has nothing to
    // measure yet, which is still "go measure the drivers".
    if (!driversReady) {
      return (
        MeasurementWorkflowAction.measureFactoryDrivers,
        MeasurementWorkflowBlockerCode.factoryDriversMissing
      );
    }
    if (!factoryCompleted) {
      return (
        MeasurementWorkflowAction.runFactoryGuidedTuning,
        MeasurementWorkflowBlockerCode.factoryTuningIncomplete
      );
    }

    // 8–15 Room.
    if (!beforeComplete) {
      return (
        MeasurementWorkflowAction.measureRoomBefore,
        MeasurementWorkflowBlockerCode.roomBeforeIncomplete
      );
    }
    if (!beforeQuality) {
      return (
        MeasurementWorkflowAction.resolveRoomMeasurementQuality,
        MeasurementWorkflowBlockerCode.roomBeforeQualityFailed
      );
    }
    if (!autoPeqApproved) {
      return (
        MeasurementWorkflowAction.generateRoomAutoPeq,
        MeasurementWorkflowBlockerCode.roomAutoPeqNotApproved
      );
    }
    if (!deployedAndVerified) {
      return (
        MeasurementWorkflowAction.deployRoomCorrection,
        MeasurementWorkflowBlockerCode.roomCorrectionNotDeployed
      );
    }
    if (!afterComplete) {
      return (
        MeasurementWorkflowAction.measureRoomAfter,
        MeasurementWorkflowBlockerCode.roomAfterIncomplete
      );
    }
    if (!comparable) {
      return (
        MeasurementWorkflowAction.resolveBeforeAfterMismatch,
        MeasurementWorkflowBlockerCode.beforeAfterMismatch
      );
    }
    if (!loopComplete) {
      return (MeasurementWorkflowAction.reviewClosedLoop, null);
    }
    return (MeasurementWorkflowAction.complete, null);
  }

  // ── §14 stage model ────────────────────────────────────────────────────

  static Map<MeasurementWorkflowStage, MeasurementWorkflowStageState> _stages({
    required MeasurementWorkflowSetupState setupState,
    required bool driversReady,
    required int measuredDrivers,
    required bool factoryCompleted,
    required int beforeCount,
    required bool beforeComplete,
    required bool beforeQuality,
    required bool deployedAndVerified,
    required int afterCount,
    required bool afterComplete,
    required bool comparable,
    required bool loopComplete,
    required bool hasSetupWarning,
  }) {
    final setup = switch (setupState) {
      MeasurementWorkflowSetupState.ready =>
        MeasurementWorkflowStageState.complete,
      MeasurementWorkflowSetupState.warning => hasSetupWarning
          ? MeasurementWorkflowStageState.warning
          : MeasurementWorkflowStageState.complete,
      MeasurementWorkflowSetupState.notChecked =>
        MeasurementWorkflowStageState.notStarted,
      MeasurementWorkflowSetupState.blocked =>
        MeasurementWorkflowStageState.blocked,
      MeasurementWorkflowSetupState.stale ||
      MeasurementWorkflowSetupState.expired =>
        MeasurementWorkflowStageState.inProgress,
    };

    final factory = factoryCompleted
        ? MeasurementWorkflowStageState.complete
        : (driversReady || measuredDrivers > 0
            ? MeasurementWorkflowStageState.inProgress
            : MeasurementWorkflowStageState.notStarted);

    final MeasurementWorkflowStageState roomStage;
    if (deployedAndVerified) {
      roomStage = MeasurementWorkflowStageState.complete;
    } else if (beforeComplete && !beforeQuality) {
      roomStage = MeasurementWorkflowStageState.blocked;
    } else if (beforeCount > 0) {
      roomStage = MeasurementWorkflowStageState.inProgress;
    } else {
      roomStage = MeasurementWorkflowStageState.notStarted;
    }

    final MeasurementWorkflowStageState verification;
    if (loopComplete) {
      verification = MeasurementWorkflowStageState.complete;
    } else if (afterComplete && !comparable) {
      verification = MeasurementWorkflowStageState.blocked;
    } else if (afterCount > 0) {
      verification = MeasurementWorkflowStageState.inProgress;
    } else {
      verification = MeasurementWorkflowStageState.notStarted;
    }

    return {
      MeasurementWorkflowStage.project: MeasurementWorkflowStageState.complete,
      MeasurementWorkflowStage.measurementSetup: setup,
      MeasurementWorkflowStage.factoryTuning: factory,
      MeasurementWorkflowStage.roomTuning: roomStage,
      MeasurementWorkflowStage.verification: verification,
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static MeasurementWorkflowSetupState _setupState(
      ProProject project, MeasurementCaptureGateResult gate) {
    if (project.currentSetupReadiness == null) {
      return MeasurementWorkflowSetupState.notChecked;
    }
    final codes = gate.blockers.map((b) => b.code).toSet();
    if (codes.contains(MeasurementCaptureBlockerCode.setupExpired)) {
      return MeasurementWorkflowSetupState.expired;
    }
    const identityDrift = {
      MeasurementCaptureBlockerCode.setupProjectMismatch,
      MeasurementCaptureBlockerCode.setupProfileMismatch,
      MeasurementCaptureBlockerCode.setupCalibrationCurveMismatch,
      MeasurementCaptureBlockerCode.setupOrientationMismatch,
      MeasurementCaptureBlockerCode.setupInputDeviceMismatch,
      MeasurementCaptureBlockerCode.setupPolicyVersionMismatch,
      MeasurementCaptureBlockerCode.setupSampleRateMismatch,
      MeasurementCaptureBlockerCode.setupChannelMismatch,
    };
    if (codes.any(identityDrift.contains)) {
      return MeasurementWorkflowSetupState.stale;
    }
    if (codes.contains(MeasurementCaptureBlockerCode.setupNotReady) ||
        codes.contains(MeasurementCaptureBlockerCode.setupQuality)) {
      return MeasurementWorkflowSetupState.blocked;
    }
    return gate.warnings.isEmpty
        ? MeasurementWorkflowSetupState.ready
        : MeasurementWorkflowSetupState.warning;
  }

  /// The SELECTED PROFILE's calibration standing.
  ///
  /// Delegates the base verdict to [deriveMicrophoneDisplayState], which the
  /// Measure tab's status card already uses — so Home and Measure can never
  /// disagree about the same microphone.
  ///
  /// `partiallyCalibrated` is then derived from the EXISTING Room coverage
  /// gate rather than a second opinion: a structurally valid curve that does
  /// not span the required 20–300 Hz band is real, usable calibration that
  /// nonetheless cannot back a Room correction, and saying "부분 보정" is
  /// more honest than a flat "보정 완료". No coverage maths is duplicated
  /// here — [CalibrationFrequencyCoverage] owns that window.
  static MeasurementWorkflowCalibrationState _calibrationState(
      MeasurementMicrophoneProfile? profile) {
    switch (deriveMicrophoneDisplayState(profile)) {
      case MicrophoneDisplayState.notSelected:
        return MeasurementWorkflowCalibrationState.none;
      case MicrophoneDisplayState.explicitlyUncalibrated:
        return MeasurementWorkflowCalibrationState.explicitlyUncalibrated;
      case MicrophoneDisplayState.invalid:
        // A profile claiming a calibrated source with no curve at all is
        // unrecoverable provenance, not a malformed file.
        return profile!.calibrationCurve == null
            ? MeasurementWorkflowCalibrationState.legacyUnknown
            : MeasurementWorkflowCalibrationState.invalid;
      case MicrophoneDisplayState.calibrationReady:
        final coversRoomBand = CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.calibrated,
          calibrationCurve: profile!.calibrationCurve,
          minFrequencyHz: roomAutoPeqMinHz,
          maxFrequencyHz: roomAutoPeqMaxHz,
        );
        return coversRoomBand
            ? MeasurementWorkflowCalibrationState.calibrated
            : MeasurementWorkflowCalibrationState.partiallyCalibrated;
    }
  }

  /// §12 — any existing measurement whose provenance predates
  /// [MeasurementDataSource]. Informational only: it never blocks, and no
  /// migration is attempted.
  static bool _hasLegacyMeasurementData(ProProject project) {
    bool legacy(ParsedMeasurementData? d) =>
        d != null && d.source == MeasurementDataSource.legacyUnknown;
    return project.acousticState.driverChannels.any((c) => legacy(c.frdData)) ||
        legacy(project.roomState.before.leftSystemFrd?.frd) ||
        legacy(project.roomState.before.rightSystemFrd?.frd);
  }

  static MeasurementWorkflowReadiness _noProject() =>
      const MeasurementWorkflowReadiness(
        hasProject: false,
        microphoneSelected: false,
        calibrationStatus: MeasurementWorkflowCalibrationState.none,
        inputSelected: false,
        inputSelectionKind: MeasurementWorkflowInputSelectionKind.none,
        runtimeAvailabilityKnown: false,
        runtimeAvailability: MeasurementWorkflowInputAvailability.unknown,
        setupState: MeasurementWorkflowSetupState.notChecked,
        setupWarnings: [],
        requiredDriverCount: 0,
        measuredDriverCount: 0,
        driverMeasurementReady: false,
        guidedTuningReady: false,
        factoryTuningCompleted: false,
        beforeCount: 0,
        beforeMeasurementComplete: false,
        beforeQualityReady: false,
        roomAutoPeqReady: false,
        roomAutoPeqApproved: false,
        correctionDeployedAndVerified: false,
        afterAvailable: false,
        afterCount: 0,
        afterMeasurementComplete: false,
        beforeAfterComparable: false,
        closedLoopComplete: false,
        closedLoopWarnings: [],
        roomCorrectionVerified: false,
        nextRecommendedAction: MeasurementWorkflowAction.createOrOpenProject,
        primaryBlocker: MeasurementWorkflowBlockerCode.noProject,
        warnings: [],
        stages: {
          MeasurementWorkflowStage.project:
              MeasurementWorkflowStageState.notStarted,
          MeasurementWorkflowStage.measurementSetup:
              MeasurementWorkflowStageState.notStarted,
          MeasurementWorkflowStage.factoryTuning:
              MeasurementWorkflowStageState.notStarted,
          MeasurementWorkflowStage.roomTuning:
              MeasurementWorkflowStageState.notStarted,
          MeasurementWorkflowStage.verification:
              MeasurementWorkflowStageState.notStarted,
        },
      );
}
