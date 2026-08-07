import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'factory_sound_profile.dart';
import 'pro_correction_cycle.dart';
import 'pro_project.dart';
import 'pro_acoustic_data.dart';
import 'pro_tuning_data.dart';
import 'pro_protection_data.dart';
import 'pro_optimizer_data.dart';
import 'pro_export_data.dart';
import 'pro_simulation_data.dart';
import 'pro_hardware_connection_data.dart';
import 'pro_deploy_package_data.dart';
import 'pro_address_validation_data.dart';
import 'room_measurement_data.dart';
import 'calibration/calibration_types.dart';

const _kProjectsKey = 'tunai_pro_projects';
const _kCurrentIdKey = 'tunai_pro_current_project_id';

class ProProjectStore {
  final List<ProProject> projects;
  final String? currentProjectId;

  const ProProjectStore({
    this.projects = const [],
    this.currentProjectId,
  });

  ProProject? get currentProject => currentProjectId == null
      ? null
      : projects.where((p) => p.id == currentProjectId).firstOrNull;

  ProProjectStore copyWith({
    List<ProProject>? projects,
    String? currentProjectId,
    bool clearCurrentId = false,
  }) =>
      ProProjectStore(
        projects: projects ?? this.projects,
        currentProjectId:
            clearCurrentId ? null : (currentProjectId ?? this.currentProjectId),
      );
}

class ProProjectStoreNotifier extends StateNotifier<ProProjectStore> {
  ProProjectStoreNotifier() : super(const ProProjectStore()) {
    _load();
  }

  // Guards rollbackTuningState against a double-tap: two calls fired back to
  // back (before the first has reached its own `await`) would otherwise both
  // read the same pre-rollback project synchronously and each independently
  // bump tuningRevision, double-applying the restore. Checked and set
  // synchronously, before any await, so a second synchronous call sees its
  // project id already in flight and no-ops immediately.
  final Set<String> _rollbackInFlightIds = {};

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProjectsKey);
    final currentId = prefs.getString(_kCurrentIdKey);
    final projects = raw != null ? ProProject.decodeList(raw) : <ProProject>[];
    // A project referenced by the persisted current-id may have been dropped
    // by decodeList (corrupt/unparsable entry) — don't carry a dangling id
    // forward, or it would be re-persisted by the next _persist() call.
    final resolvedCurrentId =
        projects.any((p) => p.id == currentId) ? currentId : null;
    state = ProProjectStore(
        projects: projects, currentProjectId: resolvedCurrentId);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProjectsKey, ProProject.encodeList(state.projects));
    if (state.currentProjectId != null) {
      await prefs.setString(_kCurrentIdKey, state.currentProjectId!);
    } else {
      await prefs.remove(_kCurrentIdKey);
    }
  }

  Future<void> addProject(ProProject project) async {
    state = state.copyWith(
      projects: [...state.projects, project],
      currentProjectId: project.id,
    );
    await _persist();
  }

  Future<void> updateProject(ProProject project) async {
    state = state.copyWith(
      projects:
          state.projects.map((p) => p.id == project.id ? project : p).toList(),
    );
    await _persist();
  }

  Future<void> deleteProject(String id) async {
    final remaining = state.projects.where((p) => p.id != id).toList();
    final newCurrentId = state.currentProjectId == id
        ? (remaining.isNotEmpty ? remaining.last.id : null)
        : state.currentProjectId;
    state =
        ProProjectStore(projects: remaining, currentProjectId: newCurrentId);
    await _persist();
  }

  Future<void> setCurrentProject(String id) async {
    state = state.copyWith(currentProjectId: id);
    await _persist();
  }

  Future<ProProject> duplicateProject(String id) async {
    final original = state.projects.firstWhere((p) => p.id == id);
    final now = DateTime.now();

    // Re-create with new id
    final dup = ProProject(
      id: now.millisecondsSinceEpoch.toString(),
      name: '${original.name} (Copy)',
      speakerModel: original.speakerModel,
      roomName: original.roomName,
      createdAt: now,
      updatedAt: now,
      sampleRate: original.sampleRate,
      dspTarget: original.dspTarget,
      channelConfig: original.channelConfig,
      profileStatus: ProfileStatus.draft,
      safetyStatus: SafetyStatus.notVerified,
      connection: HardwareConnection.disconnected,
      acousticState: original.acousticState,
      tuningState: original.tuningState,
      protectionState: original.protectionState,
      optimizerState: original.optimizerState,
      exportState: original.exportState,
      simulationState: original.simulationState,
      hardwareState: original.hardwareState,
      deployState: original.deployState,
      addressValidationState: original.addressValidationState,
    );
    await addProject(dup);
    return dup;
  }

  Future<void> renameProject(String id, String newName) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(
        project.copyWith(name: newName, updatedAt: DateTime.now()));
  }

  Future<void> updateProfileStatus(String id, ProfileStatus status) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(
        project.copyWith(profileStatus: status, updatedAt: DateTime.now()));
  }

  Future<void> updateSafetyStatus(String id, SafetyStatus status) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(
        project.copyWith(safetyStatus: status, updatedAt: DateTime.now()));
  }

  // Called unawaited from hardware_tab.dart's BLE PASS_HANDSHAKE/disconnect
  // callbacks. A missing project (deleted mid-session, or the store not yet
  // loaded when a stale BLE transport fires its reconnect callback) must be a
  // silent no-op — an unawaited throw here would leave project.connection
  // stale while activeAdau1701ContextProvider has already been updated.
  Future<void> updateHardwareConnection(
      String id, HardwareConnection conn) async {
    final project = state.projects.where((p) => p.id == id).firstOrNull;
    if (project == null) return;
    await updateProject(
        project.copyWith(connection: conn, updatedAt: DateTime.now()));
  }

  Future<void> updateAcousticState(
      String id, MeasurementProjectState acousticState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(
        acousticState: acousticState, updatedAt: DateTime.now()));
  }

  Future<void> updateTuningState(
      String id, TuningProjectState tuningState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(
        project.copyWith(tuningState: tuningState, updatedAt: DateTime.now()));
  }

  Future<void> updateRoomState(
      String id, RoomMeasurementProjectState roomState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(
        project.copyWith(roomState: roomState, updatedAt: DateTime.now()));
  }

  /// Selects (or clears, when [profile] is null) the measurement microphone
  /// for project [id] only — never touches any other project, and never
  /// changes any already-captured measurement's stored
  /// MeasurementMicrophoneSnapshot.
  Future<void> updateSelectedMicrophoneProfile(
      String id, MeasurementMicrophoneProfile? profile) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(
      selectedMicrophoneProfile: profile,
      clearSelectedMicrophoneProfile: profile == null,
      updatedAt: DateTime.now(),
    ));
  }

  /// Replaces project [id]'s entire microphone profile roster — never
  /// touches any other project's roster, and never mutates a profile
  /// object already embedded in a past measurement's
  /// MeasurementMicrophoneSnapshot (those are immutable copies, unaffected
  /// by roster edits/deletes). Callers build the new list (add/edit/
  /// duplicate/delete) and pass it whole, mirroring updateRoomState.
  Future<void> updateMicrophoneProfiles(
      String id, List<MeasurementMicrophoneProfile> profiles) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(
      microphoneProfiles: profiles,
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> updateProtectionState(
      String id, ProtectionProjectState protectionState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(
        protectionState: protectionState, updatedAt: DateTime.now()));
  }

  Future<void> updateOptimizerState(
      String id, OptimizerProjectState optimizerState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(
        optimizerState: optimizerState, updatedAt: DateTime.now()));
  }

  Future<void> updateExportState(
      String id, ExportProjectState exportState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(
        project.copyWith(exportState: exportState, updatedAt: DateTime.now()));
  }

  Future<void> updateSimulationState(
      String id, SimulationProjectState simulationState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(
        simulationState: simulationState, updatedAt: DateTime.now()));
  }

  Future<void> updateHardwareState(
      String id, HardwareProjectState hardwareState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(
        hardwareState: hardwareState, updatedAt: DateTime.now()));
  }

  Future<void> updateDeployState(
      String id, DeployProjectState deployState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(
        project.copyWith(deployState: deployState, updatedAt: DateTime.now()));
  }

  /// Records confirmed ACK-applied gains per channel for rollback.
  /// Merges [gains] into the existing map so previously-applied channels
  /// that weren't part of this write are preserved. No-ops (fail-closed,
  /// same as [DeployProjectState.activePackage]) if [id] no longer names a
  /// project in the store — e.g. the project was deleted while a deploy or
  /// restore was in flight.
  Future<void> updateDeployAppliedGains(
      String id, Map<String, double> gains) async {
    final project = state.projects.where((p) => p.id == id).firstOrNull;
    if (project == null) return;
    final merged = {
      ...project.deployState.appliedGainsByChannel,
      ...gains,
    };
    final updated = project.deployState.copyWith(
      appliedGainsByChannel: merged,
      updatedAt: DateTime.now(),
    );
    await updateProject(
        project.copyWith(deployState: updated, updatedAt: DateTime.now()));
  }

  /// Records confirmed ACK-applied crossover state per channel (Phase 7-4A).
  /// Merges [xo] into the existing map, same pattern as
  /// [updateDeployAppliedGains]. buildAdau1701XoExportBlocks() diffs against
  /// this on the next deploy so only an actually-changed channel/side is
  /// re-sent. No-ops (fail-closed) if [id] no longer names a project.
  Future<void> updateDeployAppliedXo(
      String id, Map<String, AppliedXoChannelState> xo) async {
    final project = state.projects.where((p) => p.id == id).firstOrNull;
    if (project == null) return;
    final merged = {
      ...project.deployState.appliedXoByChannel,
      ...xo,
    };
    final updated = project.deployState.copyWith(
      appliedXoByChannel: merged,
      updatedAt: DateTime.now(),
    );
    await updateProject(
        project.copyWith(deployState: updated, updatedAt: DateTime.now()));
  }

  Future<void> updateAddressValidationState(
      String id, AddressValidationProjectState addressValidationState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(
        addressValidationState: addressValidationState,
        updatedAt: DateTime.now()));
  }

  /// Appends a new [CorrectionCycle] to the project's [correctionCycles] list
  /// and persists. The cycle must have [cycle.projectId] == [id].
  Future<void> addCorrectionCycle(String id, CorrectionCycle cycle) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    final updated = [
      ...project.correctionCycles,
      cycle,
    ];
    await updateProject(
        project.copyWith(correctionCycles: updated, updatedAt: DateTime.now()));
  }

  /// Replaces the [CorrectionCycle] at [cycleNumber] with [cycle] and persists.
  Future<void> updateCorrectionCycle(String id, CorrectionCycle cycle) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    final updated = project.correctionCycles
        .map((c) => c.cycleNumber == cycle.cycleNumber ? cycle : c)
        .toList();
    await updateProject(
        project.copyWith(correctionCycles: updated, updatedAt: DateTime.now()));
  }

  /// Software-only rollback of a [CorrectionCycleDecision.worsened] cycle:
  /// restores [cycle.rollbackTuningState] as the project's live `tuningState`
  /// and atomically updates every field that would otherwise silently go
  /// stale, in one [updateProject] write:
  ///  - `tuningState` is the restored (old) values, but assigned a NEW,
  ///    forward-moving `tuningRevision` (`current + 1`) — the snapshot's own,
  ///    older revision number is never reused, so the counter never regresses.
  ///  - `safetyStatus` resets to [SafetyStatus.notVerified] — the restored
  ///    tuning has not been re-verified at this point in time.
  ///  - `profileStatus` steps back to [ProfileStatus.tuned] only if it was
  ///    [ProfileStatus.verified] or [ProfileStatus.deployed]; otherwise
  ///    unchanged.
  ///  - Every `deployState`/`exportState` package currently `ready`/
  ///    `exported` (or `draftReady`/`exported`) is marked `stale`, since none
  ///    of them could possibly have been built from the brand-new revision.
  ///
  /// Deliberately NEVER touches: `deployState.appliedGainsByChannel` (the
  /// hardware-ACK'd gain record — decoupled from software `tuningState` by
  /// design), `correctionCycles` (the worsened cycle is preserved, unchanged,
  /// in history), `hardwareState`, or any transport/write/deploy-execution
  /// path — this method performs no hardware I/O whatsoever.
  ///
  /// No-ops (returns `false`, no store write) if [cycle.rollbackTuningState]
  /// is null or [cycle.decision] is not [CorrectionCycleDecision.worsened] —
  /// callers should only offer this for worsened cycles, but this guard
  /// makes the operation fail safe regardless of caller discipline.
  Future<bool> rollbackTuningState(String id, CorrectionCycle cycle) async {
    final rollback = cycle.rollbackTuningState;
    if (rollback == null ||
        cycle.decision != CorrectionCycleDecision.worsened) {
      return false;
    }
    // Synchronous check-and-set, before any await — see field doc above.
    if (_rollbackInFlightIds.contains(id)) return false;
    _rollbackInFlightIds.add(id);
    try {
      final project = state.projects.firstWhere((p) => p.id == id);
      final newRevision = project.tuningState.tuningRevision + 1;
      final now = DateTime.now();

      final restoredTuning = rollback.copyWith(
        tuningRevision: newRevision,
        updatedAt: now,
      );

      final newProfileStatus =
          (project.profileStatus == ProfileStatus.verified ||
                  project.profileStatus == ProfileStatus.deployed)
              ? ProfileStatus.tuned
              : project.profileStatus;

      final staleDeployPackages = project.deployState.packages
          .map((pkg) => (pkg.status == DeployPackageStatus.ready ||
                  pkg.status == DeployPackageStatus.exported)
              ? pkg.copyWith(status: DeployPackageStatus.stale, updatedAt: now)
              : pkg)
          .toList();
      final staleExportPackages = project.exportState.packages
          .map((pkg) => (pkg.status == ExportStatus.draftReady ||
                  pkg.status == ExportStatus.exported)
              ? pkg.copyWith(status: ExportStatus.stale)
              : pkg)
          .toList();

      await updateProject(project.copyWith(
        tuningState: restoredTuning,
        safetyStatus: SafetyStatus.notVerified,
        profileStatus: newProfileStatus,
        deployState:
            project.deployState.copyWith(packages: staleDeployPackages),
        exportState:
            project.exportState.copyWith(packages: staleExportPackages),
        updatedAt: now,
      ));
      return true;
    } finally {
      _rollbackInFlightIds.remove(id);
    }
  }

  /// Appends a new [FactorySoundProfile] to the project and persists.
  Future<void> addFactoryProfile(String id, FactorySoundProfile profile) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    final updated = [...project.factoryProfiles, profile];
    await updateProject(
        project.copyWith(factoryProfiles: updated, updatedAt: DateTime.now()));
  }

  /// Replaces the [FactorySoundProfile] matching [profile.profileId] and persists.
  Future<void> updateFactoryProfile(
      String id, FactorySoundProfile profile) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    final updated = project.factoryProfiles
        .map((p) => p.profileId == profile.profileId ? profile : p)
        .toList();
    await updateProject(
        project.copyWith(factoryProfiles: updated, updatedAt: DateTime.now()));
  }
}

final proProjectStoreProvider =
    StateNotifierProvider<ProProjectStoreNotifier, ProProjectStore>(
        (ref) => ProProjectStoreNotifier());
