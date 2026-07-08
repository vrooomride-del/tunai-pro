import 'package:shared_preferences/shared_preferences.dart';
import 'pro_project.dart';

const _kProjectsKey = 'tunai_pro_projects';
const _kCurrentIdKey = 'tunai_pro_current_project_id';

/// Thin persistence layer for ProProject list.
/// All read/write logic is here; controllers call these methods.
class ProProjectRepository {
  ProProjectRepository._();
  static final ProProjectRepository instance = ProProjectRepository._();

  Future<List<ProProject>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProjectsKey);
    if (raw == null || raw.isEmpty) return [];
    return ProProject.decodeList(raw);
  }

  Future<void> saveProjects(List<ProProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProjectsKey, ProProject.encodeList(projects));
  }

  Future<void> saveProject(ProProject project) async {
    final list = await loadProjects();
    final idx = list.indexWhere((p) => p.id == project.id);
    if (idx >= 0) {
      list[idx] = project;
    } else {
      list.insert(0, project);
    }
    await saveProjects(list);
  }

  Future<void> deleteProject(String id) async {
    final list = await loadProjects();
    list.removeWhere((p) => p.id == id);
    await saveProjects(list);
    // Clear current if it was deleted
    final currentId = await loadCurrentProjectId();
    if (currentId == id) await clearCurrentProject();
  }

  Future<ProProject> duplicateProject(ProProject source) async {
    final now = DateTime.now();
    final dup = ProProject(
      id: now.millisecondsSinceEpoch.toString(),
      name: '${source.name} (Copy)',
      speakerModel: source.speakerModel,
      roomName: source.roomName,
      createdAt: now,
      updatedAt: now,
      sampleRate: source.sampleRate,
      dspTarget: source.dspTarget,
      channelConfig: source.channelConfig,
      profileStatus: ProfileStatus.draft,
      safetyStatus: SafetyStatus.notVerified,
      connection: HardwareConnection.disconnected,
      notes: source.notes,
    );
    await saveProject(dup);
    return dup;
  }

  Future<ProProject> renameProject(String id, String newName) async {
    final list = await loadProjects();
    final idx = list.indexWhere((p) => p.id == id);
    if (idx < 0) throw StateError('Project $id not found');
    final updated = list[idx].copyWith(name: newName, updatedAt: DateTime.now());
    list[idx] = updated;
    await saveProjects(list);
    return updated;
  }

  Future<void> setCurrentProject(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrentIdKey, id);
  }

  Future<String?> loadCurrentProjectId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCurrentIdKey);
  }

  Future<void> clearCurrentProject() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCurrentIdKey);
  }
}
