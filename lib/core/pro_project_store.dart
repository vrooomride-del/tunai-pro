import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pro_project.dart';
import 'pro_acoustic_data.dart';

const _kProjectsKey = 'tunai_pro_projects';
const _kCurrentIdKey = 'tunai_pro_current_project_id';

class ProProjectStore {
  final List<ProProject> projects;
  final String? currentProjectId;

  const ProProjectStore({
    this.projects = const [],
    this.currentProjectId,
  });

  ProProject? get currentProject =>
      currentProjectId == null
          ? null
          : projects.where((p) => p.id == currentProjectId).firstOrNull;

  ProProjectStore copyWith({
    List<ProProject>? projects,
    String? currentProjectId,
    bool clearCurrentId = false,
  }) => ProProjectStore(
    projects: projects ?? this.projects,
    currentProjectId: clearCurrentId ? null : (currentProjectId ?? this.currentProjectId),
  );
}

class ProProjectStoreNotifier extends StateNotifier<ProProjectStore> {
  ProProjectStoreNotifier() : super(const ProProjectStore()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProjectsKey);
    final currentId = prefs.getString(_kCurrentIdKey);
    final projects = raw != null ? ProProject.decodeList(raw) : <ProProject>[];
    state = ProProjectStore(projects: projects, currentProjectId: currentId);
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
      projects: state.projects.map((p) => p.id == project.id ? project : p).toList(),
    );
    await _persist();
  }

  Future<void> deleteProject(String id) async {
    final remaining = state.projects.where((p) => p.id != id).toList();
    final newCurrentId = state.currentProjectId == id
        ? (remaining.isNotEmpty ? remaining.last.id : null)
        : state.currentProjectId;
    state = ProProjectStore(projects: remaining, currentProjectId: newCurrentId);
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
    );
    await addProject(dup);
    return dup;
  }

  Future<void> renameProject(String id, String newName) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(name: newName, updatedAt: DateTime.now()));
  }

  Future<void> updateProfileStatus(String id, ProfileStatus status) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(profileStatus: status, updatedAt: DateTime.now()));
  }

  Future<void> updateSafetyStatus(String id, SafetyStatus status) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(safetyStatus: status, updatedAt: DateTime.now()));
  }

  Future<void> updateHardwareConnection(String id, HardwareConnection conn) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(connection: conn, updatedAt: DateTime.now()));
  }

  Future<void> updateAcousticState(String id, MeasurementProjectState acousticState) async {
    final project = state.projects.firstWhere((p) => p.id == id);
    await updateProject(project.copyWith(acousticState: acousticState, updatedAt: DateTime.now()));
  }
}

final proProjectStoreProvider =
    StateNotifierProvider<ProProjectStoreNotifier, ProProjectStore>(
        (ref) => ProProjectStoreNotifier());
