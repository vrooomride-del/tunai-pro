// ── TUNAI PRO Phase 3-F1 §6 — derived hardware readiness provider ──────────
//
// Pure derivation over state other parts of the app already own. It starts no
// scan, opens no BLE/USB connection, runs no handshake, writes no DSP value,
// creates no timer and performs no I/O — it only reads and combines.
//
// Connecting remains entirely the Hardware tab's / connect flow's job; this
// provider is how the rest of the app asks what those flows established.

library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../deploy/pro_hardware_context_provider.dart';
import '../pro_project.dart';
import '../pro_project_store.dart';
import 'hardware_connection_readiness.dart';

/// Readiness for an explicit project id.
final hardwareConnectionReadinessForProjectProvider =
    Provider.family<HardwareConnectionReadiness, String>((ref, projectId) {
  final project = ref
      .watch(proProjectStoreProvider)
      .projects
      .where((p) => p.id == projectId)
      .firstOrNull;
  return _derive(ref, project);
});

/// Readiness for the store's CURRENT project — what Home renders.
final hardwareConnectionReadinessProvider =
    Provider<HardwareConnectionReadiness>((ref) {
  final project = ref.watch(proProjectStoreProvider).currentProject;
  return _derive(ref, project);
});

HardwareConnectionReadiness _derive(Ref ref, ProProject? project) {
  if (project == null) return HardwareConnectionReadiness.none;

  // The live, session-scoped context. Null after a restart, after a
  // disconnect callback, and after onDone/onError — which is what stops a
  // stale persisted flag from reading as connected.
  final context = ref.watch(activeAdau1701ContextProvider);

  return HardwareConnectionEvaluator.evaluate(
    projectDspTarget: project.dspTarget,
    hasLiveContext: context != null,
    // The existing ADAU1701 contract: connected + handshaken + identified.
    liveContextReady: context?.isReady ?? false,
    transportKind: context?.transportType.name,
    persistedConnected: project.connection == HardwareConnection.connected,
    persistedError: project.connection == HardwareConnection.error,
  );
}
