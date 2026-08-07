// ── TUNAI PRO Phase 3-E §6/§21 — Continue Tuning routing ───────────────────
//
// ONE typed dispatch from MeasurementWorkflowAction to where that action
// actually happens. No string comparison, and no new navigation framework:
// every destination is an EXISTING kTabXxx constant handed to the existing
// workbenchTabProvider, then WorkbenchShell is opened exactly the way
// WorkspaceHome already opened it.
//
// Tab indices are never hardcoded here — the kTabXxx constants are the single
// source of truth for tab order (see workbench_tab_provider.dart).

library;

import '../../core/measurement_entry_intent.dart';
import '../../core/workbench_tab_provider.dart';
import '../../core/workflow/measurement_workflow_readiness.dart';

/// Where a Continue Tuning action lands.
///
/// [projectList] is the only destination outside the Workbench — everything
/// else opens the project's Workbench on a specific tab.
sealed class HomeActionDestination {
  const HomeActionDestination();
}

/// The project list / new-project entry point (no project open yet).
class HomeProjectListDestination extends HomeActionDestination {
  const HomeProjectListDestination();
}

/// Open the current project's Workbench focused on [tabIndex].
///
/// [intent] says WHAT to do on arrival — the Measure tab consumes it once
/// and opens the matching dialog, so a CTA never dumps the user onto a dense
/// professional tab to hunt for the right control (Phase 3-E P0 §4).
class HomeWorkbenchDestination extends HomeActionDestination {
  final int tabIndex;
  final MeasurementEntryIntent? intent;
  const HomeWorkbenchDestination(this.tabIndex, {this.intent});
}

/// Maps every action to a real, existing destination. Exhaustive by
/// construction — adding an action to the enum breaks this switch at compile
/// time rather than silently falling through to a default.
HomeActionDestination homeActionDestination(MeasurementWorkflowAction a) =>
    switch (a) {
      MeasurementWorkflowAction.createOrOpenProject =>
        const HomeProjectListDestination(),

      // The microphone manager and Guided Measurement Setup both live inside
      // the Measure tab, which is also where every capture happens — so the
      // tab is the same for all of these, and the INTENT is what differs.
      MeasurementWorkflowAction.selectMicrophone =>
        const HomeWorkbenchDestination(kTabMeasure,
            intent: MeasurementEntryIntent.manageMicrophone),
      MeasurementWorkflowAction.fixCalibration =>
        const HomeWorkbenchDestination(kTabMeasure,
            intent: MeasurementEntryIntent.manageCalibration),
      MeasurementWorkflowAction.selectInputDevice =>
        const HomeWorkbenchDestination(kTabMeasure,
            intent: MeasurementEntryIntent.selectInputDevice),
      MeasurementWorkflowAction.checkMeasurementSetup =>
        const HomeWorkbenchDestination(kTabMeasure,
            intent: MeasurementEntryIntent.runSetupCheck),
      MeasurementWorkflowAction.measureFactoryDrivers =>
        const HomeWorkbenchDestination(kTabMeasure,
            intent: MeasurementEntryIntent.factoryMeasurement),
      MeasurementWorkflowAction.measureRoomBefore =>
        const HomeWorkbenchDestination(kTabMeasure,
            intent: MeasurementEntryIntent.roomBefore),
      // A failed Before pair is a measurement-chain problem: send the user to
      // the microphone/setup surface, not to a capture button that will
      // reproduce the same mismatch.
      MeasurementWorkflowAction.resolveRoomMeasurementQuality =>
        const HomeWorkbenchDestination(kTabMeasure,
            intent: MeasurementEntryIntent.manageMicrophone),
      MeasurementWorkflowAction.measureRoomAfter ||
      MeasurementWorkflowAction.resolveBeforeAfterMismatch =>
        const HomeWorkbenchDestination(kTabMeasure,
            intent: MeasurementEntryIntent.roomAfter),
      // The Closed Loop verdict banner is rendered by RoomMeasurementSection,
      // i.e. also on the Measure tab.
      MeasurementWorkflowAction.reviewClosedLoop =>
        const HomeWorkbenchDestination(kTabMeasure,
            intent: MeasurementEntryIntent.closedLoopReview),
      MeasurementWorkflowAction.runFactoryGuidedTuning =>
        const HomeWorkbenchDestination(kTabGuidedAi),
      MeasurementWorkflowAction.generateRoomAutoPeq =>
        const HomeWorkbenchDestination(kTabAutoPeq),
      MeasurementWorkflowAction.deployRoomCorrection =>
        const HomeWorkbenchDestination(kTabDeploy),
      MeasurementWorkflowAction.complete =>
        const HomeWorkbenchDestination(kTabReport),
    };
