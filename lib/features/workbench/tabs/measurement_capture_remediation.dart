// ── TUNAI PRO Phase 3-D3A-1B — typed remediation + warning ack UX ───────────
//
// ONE dispatcher mapping [MeasurementCaptureRemediation] to the EXISTING
// navigation flows (Guided Measurement Setup dialog, Microphone Profile
// Manager dialog, Project List). No string comparisons, no new navigation
// system — this just routes the gate's typed verdict to flows that already
// exist. Also hosts the warning-acknowledgement confirmation dialog, which
// only ever calls the controller's own `acknowledgeWarnings(gate)` — it
// never assembles a [MeasurementWarningAcknowledgement] itself.

import 'package:flutter/material.dart';

import '../../../core/measurement/measurement_capture_gate.dart';
import '../../../core/measurement/measurement_capture_gate_types.dart';
import '../../../core/measurement/measurement_capture_presentation.dart';
import '../../home/project_list_screen.dart';
import '../../mic/guided_measurement_setup_dialog.dart';
import '../../mic/microphone_profile_manager_dialog.dart';
import '../../../shared/pro_widgets.dart';

/// Routes a blocker's typed remediation to the existing flow that resolves
/// it. `projectId` is passed straight through to the existing dialogs —
/// this never re-derives which project is active.
Future<void> runMeasurementCaptureRemediation(
  BuildContext context, {
  required MeasurementCaptureRemediation remediation,
  required String projectId,
}) async {
  switch (remediation) {
    case MeasurementCaptureRemediation.createOrOpenProject:
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const ProjectListScreen()),
      );
    case MeasurementCaptureRemediation.manageMicrophone:
      await showMicrophoneProfileManagerDialog(context, projectId: projectId);
    case MeasurementCaptureRemediation.selectInputDevice:
    case MeasurementCaptureRemediation.grantMicrophonePermission:
    case MeasurementCaptureRemediation.runSetupCheck:
    case MeasurementCaptureRemediation.checkInputDeviceAgain:
      await showGuidedMeasurementSetupDialog(context, projectId: projectId);
  }
}

/// Shows the acknowledge-and-measure confirmation dialog for every warning
/// in [gate]. Returns `true` only when the user pressed the confirm CTA —
/// callers must then call `controller.acknowledgeWarnings(gate)` themselves
/// (this dialog never builds the acknowledgement object). Cancel (or
/// dismissing the dialog) returns `false` and creates no acknowledgement.
Future<bool> showMeasurementWarningAcknowledgementDialog(
  BuildContext context, {
  required MeasurementCaptureGateResult gate,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: kProSurface,
      title: const Text('측정 전 확인'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final warning in gate.warnings) ...[
              Text(
                measurementCaptureWarningText(warning.code),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(kMeasurementCaptureWarningConfirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
