import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pro_measurement.dart';
import 'pro_project.dart';
import 'pro_project_store.dart';

// SharedPreferences key: sessions stored per-project
String _sessionsKey(String projectId) => 'tunai_pro_sessions_$projectId';

// ── State ─────────────────────────────────────────────────────────────────────

class ProMeasurementStore {
  /// Sessions for the currently active project
  final List<MeasurementSession> sessions;
  /// Currently open session id (null = session list view)
  final String? selectedSessionId;

  const ProMeasurementStore({
    this.sessions = const [],
    this.selectedSessionId,
  });

  MeasurementSession? get selectedSession =>
      selectedSessionId == null
          ? null
          : sessions.where((s) => s.id == selectedSessionId).firstOrNull;

  ProMeasurementStore copyWith({
    List<MeasurementSession>? sessions,
    String? selectedSessionId,
    bool clearSelection = false,
  }) => ProMeasurementStore(
    sessions: sessions ?? this.sessions,
    selectedSessionId: clearSelection ? null : (selectedSessionId ?? this.selectedSessionId),
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ProMeasurementNotifier extends StateNotifier<ProMeasurementStore> {
  final Ref _ref;
  String? _loadedProjectId;

  ProMeasurementNotifier(this._ref) : super(const ProMeasurementStore());

  // ── Persistence helpers ────────────────────────────────────────────────────

  Future<void> loadForProject(String projectId) async {
    if (_loadedProjectId == projectId) return;
    _loadedProjectId = projectId;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey(projectId));
    final sessions = raw != null ? MeasurementSession.decodeList(raw) : <MeasurementSession>[];
    state = ProMeasurementStore(sessions: sessions);
  }

  Future<void> _persist(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _sessionsKey(projectId), MeasurementSession.encodeList(state.sessions));
  }

  // ── Session selection ──────────────────────────────────────────────────────

  void selectSession(String? id) {
    state = state.copyWith(selectedSessionId: id, clearSelection: id == null);
  }

  // ── Session CRUD ───────────────────────────────────────────────────────────

  Future<MeasurementSession> addSession({
    required String projectId,
    required String name,
    int sampleRate = 48000,
    SweepType sweepType = SweepType.placeholder,
    String micProfile = 'Default',
    String? notes,
  }) async {
    final session = MeasurementSession.create(
      projectId: projectId,
      name: name,
      sampleRate: sampleRate,
      sweepType: sweepType,
      micProfile: micProfile,
      notes: notes,
    );
    state = state.copyWith(sessions: [...state.sessions, session]);
    await _persist(projectId);
    return session;
  }

  Future<void> updateSession(MeasurementSession session) async {
    state = state.copyWith(
      sessions: state.sessions.map((s) => s.id == session.id ? session : s).toList(),
    );
    await _persist(session.projectId);
  }

  Future<void> renameSession(String projectId, String sessionId, String newName) async {
    final s = state.sessions.firstWhere((s) => s.id == sessionId);
    await updateSession(s.copyWith(name: newName.trim(), updatedAt: DateTime.now()));
  }

  Future<MeasurementSession> duplicateSession(String projectId, String sessionId) async {
    final source = state.sessions.firstWhere((s) => s.id == sessionId);
    final now = DateTime.now();
    final dup = MeasurementSession(
      id: now.millisecondsSinceEpoch.toString(),
      projectId: projectId,
      name: '${source.name} (Copy)',
      createdAt: now,
      updatedAt: now,
      sampleRate: source.sampleRate,
      sweepType: source.sweepType,
      micProfile: source.micProfile,
      notes: source.notes,
      status: MeasurementSessionStatus.draft,
      // start fresh — no copied points
    );
    state = state.copyWith(sessions: [...state.sessions, dup]);
    await _persist(projectId);
    return dup;
  }

  Future<void> deleteSession(String projectId, String sessionId) async {
    state = state.copyWith(
      sessions: state.sessions.where((s) => s.id != sessionId).toList(),
      clearSelection: state.selectedSessionId == sessionId,
    );
    await _persist(projectId);
  }

  /// Mark session completed + update project profileStatus to Measured
  Future<void> markSessionCompleted(String projectId, String sessionId) async {
    final session = state.sessions.firstWhere((s) => s.id == sessionId);
    final updated = session.copyWith(
      status: MeasurementSessionStatus.completed,
      updatedAt: DateTime.now(),
    );
    await updateSession(updated);

    // Update project: increment measurementCount, advance to Measured if Draft
    final notifier = _ref.read(proProjectStoreProvider.notifier);
    final project = _ref.read(proProjectStoreProvider).projects
        .where((p) => p.id == projectId).firstOrNull;
    if (project != null) {
      final newStatus = project.profileStatus == ProfileStatus.draft
          ? ProfileStatus.measured
          : project.profileStatus;
      await notifier.updateProject(project.copyWith(
        measurementCount: state.sessions
            .where((s) => s.status == MeasurementSessionStatus.completed ||
                          s.status == MeasurementSessionStatus.reviewed)
            .length,
        activeProfileName: updated.name,
        profileStatus: newStatus,
        updatedAt: DateTime.now(),
      ));
    }
  }

  // ── Point CRUD ─────────────────────────────────────────────────────────────

  Future<void> addPoint({
    required String projectId,
    required String sessionId,
    required MeasurementPoint point,
  }) async {
    _updateSessionPoints(projectId, sessionId,
        (points) => [...points, point]);
  }

  Future<void> updatePoint({
    required String projectId,
    required String sessionId,
    required MeasurementPoint point,
  }) async {
    _updateSessionPoints(projectId, sessionId,
        (points) => points.map((p) => p.id == point.id ? point : p).toList());
  }

  Future<void> deletePoint({
    required String projectId,
    required String sessionId,
    required String pointId,
  }) async {
    _updateSessionPoints(projectId, sessionId,
        (points) => points.where((p) => p.id != pointId).toList());
  }

  Future<void> simulateCapture({
    required String projectId,
    required String sessionId,
    required String pointId,
  }) async {
    _updateSessionPoints(projectId, sessionId, (points) => points.map((p) {
      if (p.id != pointId) return p;
      return p.copyWith(
        status: MeasurementPointStatus.captured,
        capturedAt: DateTime.now(),
        result: MeasurementResult.placeholder(),
      );
    }).toList());
  }

  Future<void> acceptPoint({
    required String projectId,
    required String sessionId,
    required String pointId,
  }) async {
    _updateSessionPoints(projectId, sessionId, (points) => points.map((p) =>
        p.id == pointId
            ? p.copyWith(status: MeasurementPointStatus.accepted)
            : p).toList());
  }

  Future<void> rejectPoint({
    required String projectId,
    required String sessionId,
    required String pointId,
  }) async {
    _updateSessionPoints(projectId, sessionId, (points) => points.map((p) =>
        p.id == pointId
            ? p.copyWith(status: MeasurementPointStatus.rejected)
            : p).toList());
  }

  Future<void> _updateSessionPoints(
    String projectId,
    String sessionId,
    List<MeasurementPoint> Function(List<MeasurementPoint>) transform,
  ) async {
    final sessions = state.sessions.map((s) {
      if (s.id != sessionId) return s;
      return s.copyWith(
        points: transform(s.points),
        updatedAt: DateTime.now(),
      );
    }).toList();
    state = state.copyWith(sessions: sessions);
    await _persist(projectId);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final proMeasurementProvider =
    StateNotifierProvider<ProMeasurementNotifier, ProMeasurementStore>(
        (ref) => ProMeasurementNotifier(ref));
