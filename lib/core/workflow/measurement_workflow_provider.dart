// ── TUNAI PRO Phase 3-D3C-3 §1/§15 — the single Workspace Home provider ────
//
// Workspace Home needs exactly one watch:
//
//   final readiness = ref.watch(measurementWorkflowReadinessProvider);
//
// There is deliberately no second provider, and no per-card provider. All
// business logic lives in the pure MeasurementWorkflowEvaluator; this file
// only wires existing production state into it.
//
// It performs no I/O, no DSP write and no device enumeration — every source
// below is state some other part of the app already owns.

library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../deploy/pro_hardware_context_provider.dart';
import '../pro_project_store.dart';
import '../../features/workbench/tabs/room_auto_peq_controller.dart';
import '../../features/workbench/tabs/room_measurement_controller.dart';
import 'measurement_workflow_evaluator.dart';
import 'measurement_workflow_readiness.dart';

/// Derives [MeasurementWorkflowReadiness] for the store's CURRENT project.
///
/// Project-scoped state is read through the family providers keyed by that
/// project's id, so switching projects recomputes from the new project's own
/// state — nothing from the previous project can leak through.
final measurementWorkflowReadinessProvider =
    Provider<MeasurementWorkflowReadiness>((ref) {
  final project = ref.watch(proProjectStoreProvider).currentProject;
  if (project == null) {
    return MeasurementWorkflowEvaluator.evaluate(
      project: null,
      roomApprovedPackageId: null,
      lastHardwareWriteResult: null,
      now: DateTime.now(),
    );
  }

  final autoPeq = ref.watch(roomAutoPeqControllerProvider(project.id));
  final room = ref.watch(roomMeasurementControllerProvider(project.id));

  return MeasurementWorkflowEvaluator.evaluate(
    project: project,
    roomApprovedPackageId: autoPeq.approvedPackageId,
    lastHardwareWriteResult: ref.watch(lastHardwareWriteResultProvider),
    now: DateTime.now(),
    // The Closed Loop verdict and its comparison are computed once, on the
    // After 2/2 transition, by RoomMeasurementController. They are read here
    // rather than recomputed so the workflow can never produce a second,
    // independent verdict.
    closedLoopDecision: room.closedLoopResult?.decision,
    closedLoopComparison: room.closedLoopComparison,
  );
});
