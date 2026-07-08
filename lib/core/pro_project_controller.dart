import 'package:flutter/foundation.dart';
import 'pro_project.dart';
import 'pro_project_repository.dart';

/// ChangeNotifier-based project controller.
/// Wraps ProProjectRepository and holds in-memory state for the UI.
class ProProjectController extends ChangeNotifier {
  ProProjectController._();
  static final ProProjectController instance = ProProjectController._();

  final _repo = ProProjectRepository.instance;

  List<ProProject> _projects = [];
  ProProject? _currentProject;
  bool _loading = false;
  String? _error;

  List<ProProject> get projects => List.unmodifiable(_projects);
  ProProject? get currentProject => _currentProject;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasProjects => _projects.isNotEmpty;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _projects = await _repo.loadProjects();
      final currentId = await _repo.loadCurrentProjectId();
      if (currentId != null) {
        _currentProject = _projects.where((p) => p.id == currentId).firstOrNull;
      }
      // If current was deleted, clear it
      if (_currentProject == null && currentId != null) {
        await _repo.clearCurrentProject();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── CRUD ────────────────────────────────────────────────────────────────────

  Future<ProProject> newProject({
    required String name,
    String speakerModel = 'TUNAI ONE',
    String roomName = 'Desk',
    int sampleRate = 48000,
    String dspTarget = 'ADAU1701',
    String channelConfig = '2-way stereo',
    String? notes,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Project name must not be empty.');
    final project = ProProject.create(
      name: trimmed,
      speakerModel: speakerModel,
      roomName: roomName,
      sampleRate: sampleRate,
      dspTarget: dspTarget,
      channelConfig: channelConfig,
    ).copyWith(notes: notes);
    await _repo.saveProject(project);
    _projects.insert(0, project);
    await openProject(project.id);
    return project;
  }

  Future<void> openProject(String id) async {
    final found = _projects.where((p) => p.id == id).firstOrNull;
    if (found == null) return;
    await _repo.setCurrentProject(id);
    _currentProject = found;
    notifyListeners();
  }

  Future<void> saveProject(ProProject project) async {
    await _repo.saveProject(project);
    final idx = _projects.indexWhere((p) => p.id == project.id);
    if (idx >= 0) {
      _projects[idx] = project;
    } else {
      _projects.insert(0, project);
    }
    if (_currentProject?.id == project.id) _currentProject = project;
    notifyListeners();
  }

  Future<void> renameProject(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw ArgumentError('Name must not be empty.');
    final updated = await _repo.renameProject(id, trimmed);
    final idx = _projects.indexWhere((p) => p.id == id);
    if (idx >= 0) _projects[idx] = updated;
    if (_currentProject?.id == id) _currentProject = updated;
    notifyListeners();
  }

  Future<ProProject> duplicateProject(String id) async {
    final source = _projects.where((p) => p.id == id).firstOrNull;
    if (source == null) throw StateError('Project $id not found');
    final dup = await _repo.duplicateProject(source);
    _projects.insert(0, dup);
    notifyListeners();
    return dup;
  }

  Future<void> deleteProject(String id) async {
    await _repo.deleteProject(id);
    _projects.removeWhere((p) => p.id == id);
    if (_currentProject?.id == id) _currentProject = null;
    notifyListeners();
  }

  // ── Status Transitions ──────────────────────────────────────────────────────

  Future<void> updateProject(ProProject updated) => saveProject(updated.touch());

  Future<void> updateProfileStatus(String id, ProfileStatus status) async {
    final proj = _projects.where((p) => p.id == id).firstOrNull;
    if (proj == null) return;
    await saveProject(proj.copyWith(profileStatus: status, updatedAt: DateTime.now()));
  }

  Future<void> updateSafetyStatus(String id, SafetyStatus status) async {
    final proj = _projects.where((p) => p.id == id).firstOrNull;
    if (proj == null) return;
    await saveProject(proj.copyWith(safetyStatus: status, updatedAt: DateTime.now()));
  }

  Future<void> updateHardwareConnection(String id, HardwareConnection connection) async {
    final proj = _projects.where((p) => p.id == id).firstOrNull;
    if (proj == null) return;
    await saveProject(proj.copyWith(connection: connection, updatedAt: DateTime.now()));
  }

  Future<void> updateNotes(String id, String notes) async {
    final proj = _projects.where((p) => p.id == id).firstOrNull;
    if (proj == null) return;
    await saveProject(proj.copyWith(notes: notes, updatedAt: DateTime.now()));
  }
}
