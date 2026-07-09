import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_measurement.dart';
import '../../../core/pro_measurement_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../shared/pro_widgets.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class MeasureTab extends ConsumerStatefulWidget {
  final String projectId;
  const MeasureTab({super.key, required this.projectId});

  @override
  ConsumerState<MeasureTab> createState() => _MeasureTabState();
}

class _MeasureTabState extends ConsumerState<MeasureTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(proMeasurementProvider.notifier).loadForProject(widget.projectId);
    });
  }

  ProProject? get _project => ref.watch(proProjectStoreProvider)
      .projects.where((p) => p.id == widget.projectId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final project = _project;
    final mStore = ref.watch(proMeasurementProvider);

    if (project == null) {
      return Center(child: Text('Project not found.', style: proSubtitle()));
    }

    final selectedSession = mStore.selectedSession;

    final acoustic = project.acousticState;

    return Column(children: [
      // ── Phase C: Driver readiness overview bar ────────────────────────────
      _DriverReadinessBar(acoustic: acoustic),
      Expanded(child: Row(children: [
      // ── Session list panel (left) ────────────────────────────────────────
      SizedBox(
        width: 280,
        child: _SessionListPanel(
          project: project,
          sessions: mStore.sessions,
          selectedId: mStore.selectedSessionId,
          onSelect: (id) =>
              ref.read(proMeasurementProvider.notifier).selectSession(id),
          onNew: () => _showNewSessionDialog(project),
          onRename: (s) => _showRenameDialog(project, s),
          onDuplicate: (s) => ref.read(proMeasurementProvider.notifier)
              .duplicateSession(project.id, s.id),
          onDelete: (s) => _confirmDeleteSession(project, s),
        ),
      ),
      Container(width: 0.5, color: kProBorder),
      // ── Session detail panel (right) ─────────────────────────────────────
      Expanded(
        child: selectedSession == null
            ? _ReadinessCard(project: project, sessionCount: mStore.sessions.length)
            : _SessionDetailPanel(
                project: project,
                session: selectedSession,
                onAddPoint: () => _showAddPointDialog(project, selectedSession),
                onSimulate: (pointId) => ref.read(proMeasurementProvider.notifier)
                    .simulateCapture(projectId: project.id, sessionId: selectedSession.id, pointId: pointId),
                onAccept: (pointId) => ref.read(proMeasurementProvider.notifier)
                    .acceptPoint(projectId: project.id, sessionId: selectedSession.id, pointId: pointId),
                onReject: (pointId) => ref.read(proMeasurementProvider.notifier)
                    .rejectPoint(projectId: project.id, sessionId: selectedSession.id, pointId: pointId),
                onDeletePoint: (pointId) => ref.read(proMeasurementProvider.notifier)
                    .deletePoint(projectId: project.id, sessionId: selectedSession.id, pointId: pointId),
                onMarkComplete: () => _confirmMarkComplete(project, selectedSession),
              ),
      ),
    ])),   // closes Expanded + Row
    ]);    // closes Column
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  Future<void> _showNewSessionDialog(ProProject project) async {
    final result = await showDialog<_NewSessionArgs>(
      context: context,
      builder: (ctx) => const _NewSessionDialog(),
    );
    if (result != null && mounted) {
      final session = await ref.read(proMeasurementProvider.notifier).addSession(
        projectId: project.id,
        name: result.name,
        sampleRate: result.sampleRate,
        sweepType: result.sweepType,
        micProfile: result.micProfile,
        notes: result.notes.isEmpty ? null : result.notes,
      );
      ref.read(proMeasurementProvider.notifier).selectSession(session.id);
    }
  }

  Future<void> _showRenameDialog(ProProject project, MeasurementSession session) async {
    final ctrl = TextEditingController(text: session.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kProPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: kProBorder),
        ),
        title: Text('Rename Session', style: proTitle(size: 14)),
        content: _ProTextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: proSubtitle(size: 12))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Rename', style: TextStyle(color: kProAccent, fontSize: 12)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName != null && newName.trim().isNotEmpty && mounted) {
      await ref.read(proMeasurementProvider.notifier)
          .renameSession(project.id, session.id, newName);
    }
  }

  Future<void> _confirmDeleteSession(ProProject project, MeasurementSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kProPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: kProBorder),
        ),
        title: Text('Delete Session', style: proTitle(size: 14, color: kProRed)),
        content: Text(
          'Delete "${session.name}"? This cannot be undone.',
          style: proSubtitle(size: 12),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: proSubtitle(size: 12))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kProRed, fontSize: 12)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(proMeasurementProvider.notifier)
          .deleteSession(project.id, session.id);
    }
  }

  Future<void> _showAddPointDialog(ProProject project, MeasurementSession session) async {
    final result = await showDialog<_NewPointArgs>(
      context: context,
      builder: (ctx) => _AddPointDialog(existingCount: session.points.length),
    );
    if (result != null && mounted) {
      final now = DateTime.now();
      final point = MeasurementPoint(
        id: '${now.millisecondsSinceEpoch}',
        label: result.label,
        channel: result.channel,
        position: result.position,
        distanceCm: result.distanceCm,
        angleDeg: result.angleDeg,
        notes: result.notes.isEmpty ? null : result.notes,
      );
      await ref.read(proMeasurementProvider.notifier).addPoint(
        projectId: project.id,
        sessionId: session.id,
        point: point,
      );
    }
  }

  Future<void> _confirmMarkComplete(ProProject project, MeasurementSession session) async {
    if (session.status == MeasurementSessionStatus.completed ||
        session.status == MeasurementSessionStatus.reviewed) { return; }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kProPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: kProBorder),
        ),
        title: Text('Mark Session Complete', style: proTitle(size: 14)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Mark "${session.name}" as completed?\n\nThis will advance the project status to Measured if it is currently Draft.',
            style: proSubtitle(size: 12),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: kProAmber.withValues(alpha: 0.06),
              border: Border.all(color: kProAmber.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'AI suggestions require expert verification.\nReview all captured points before proceeding to analysis.',
              style: proSubtitle(size: 10),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: proSubtitle(size: 12))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark Complete', style: TextStyle(color: kProGreen, fontSize: 12)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(proMeasurementProvider.notifier)
          .markSessionCompleted(project.id, session.id);
    }
  }
}

// ── Session List Panel ────────────────────────────────────────────────────────

class _SessionListPanel extends StatelessWidget {
  final ProProject project;
  final List<MeasurementSession> sessions;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onNew;
  final ValueChanged<MeasurementSession> onRename;
  final ValueChanged<MeasurementSession> onDuplicate;
  final ValueChanged<MeasurementSession> onDelete;

  const _SessionListPanel({
    required this.project,
    required this.sessions,
    required this.selectedId,
    required this.onSelect,
    required this.onNew,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kProSurface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Panel header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.mic_none_outlined, color: kProAccent, size: 14),
              const SizedBox(width: 8),
              Text('MEASUREMENT SESSIONS', style: proLabel(size: 9, color: kProAccent, spacing: 1.5)),
            ]),
            const SizedBox(height: 4),
            Text(project.name, style: proTitle(size: 11, color: Colors.white60),
                overflow: TextOverflow.ellipsis),
          ]),
        ),

        // New session button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: GestureDetector(
            onTap: onNew,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kProAccent.withValues(alpha: 0.1),
                border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add, color: kProAccent, size: 13),
                SizedBox(width: 6),
                Text('New Session', style: TextStyle(color: kProAccent, fontSize: 11)),
              ]),
            ),
          ),
        ),

        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
            child: Column(children: [
              const Icon(Icons.mic_off_outlined, color: Colors.white12, size: 28),
              const SizedBox(height: 10),
              Text('No sessions yet.', style: proSubtitle(size: 11)),
              const SizedBox(height: 4),
              Text('Create a measurement session\nto begin acoustic capture.',
                  style: proLabel(size: 9, color: Colors.white24, spacing: 0.3),
                  textAlign: TextAlign.center),
            ]),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: sessions.length,
              itemBuilder: (ctx, i) => _SessionTile(
                session: sessions[i],
                selected: sessions[i].id == selectedId,
                onTap: () => onSelect(sessions[i].id),
                onRename: () => onRename(sessions[i]),
                onDuplicate: () => onDuplicate(sessions[i]),
                onDelete: () => onDelete(sessions[i]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final MeasurementSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  Color _statusColor() => switch (session.status) {
    MeasurementSessionStatus.completed || MeasurementSessionStatus.reviewed => kProGreen,
    MeasurementSessionStatus.running => kProAccent,
    MeasurementSessionStatus.ready   => kProAmber,
    _                                => const Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: selected ? kProAccent.withValues(alpha: 0.08) : Colors.transparent,
          border: Border(left: BorderSide(
            color: selected ? kProAccent : Colors.transparent,
            width: 2,
          )),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.name, style: proTitle(size: 11,
                color: selected ? Colors.white : Colors.white70),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              ProStatusPill(label: session.status.label, color: _statusColor()),
              const SizedBox(width: 6),
              Text('${session.points.length} pts', style: proLabel(size: 9, color: Colors.white24, spacing: 0.3)),
            ]),
            const SizedBox(height: 3),
            Text('${session.sampleRateLabel} · ${session.sweepType.label}',
                style: proLabel(size: 9, color: Colors.white24, spacing: 0.3)),
          ])),
          PopupMenuButton<String>(
            color: kProPanel,
            iconColor: Colors.white24,
            iconSize: 14,
            padding: EdgeInsets.zero,
            onSelected: (v) {
              if (v == 'rename') onRename();
              if (v == 'duplicate') onDuplicate();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white70, fontSize: 12))),
              PopupMenuItem(value: 'duplicate', child: Text('Duplicate', style: TextStyle(color: Colors.white70, fontSize: 12))),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: kProRed, fontSize: 12))),
            ],
          ),
        ]),
      ),
    );
  }
}

// ── Readiness Card (no session selected) ─────────────────────────────────────

class _ReadinessCard extends StatelessWidget {
  final ProProject project;
  final int sessionCount;
  const _ReadinessCard({required this.project, required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mic_none_outlined, color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Measurement Workspace', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 6),
        Text('Capture, review, and organize acoustic measurements before analysis.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        // Readiness checklist
        _ChecklistCard(project: project, sessionCount: sessionCount),
        const SizedBox(height: 20),

        // Principle reminder
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MEASUREMENT PROTOCOL', style: proLabel(size: 9, spacing: 1.8)),
            const SizedBox(height: 10),
            const _ProtocolRow(Icons.chevron_right, 'Measurement data must be reviewed before tuning.'),
            const _ProtocolRow(Icons.chevron_right, 'AI suggestions require expert verification.'),
            const _ProtocolRow(Icons.chevron_right, 'AOS protection remains active throughout.'),
            const _ProtocolRow(Icons.chevron_right, 'DSP execution occurs only after verified deployment.'),
          ]),
        ),

        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.05),
            border: Border.all(color: kProAmber.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: kProAmber, size: 13),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Real measurement capture will be connected in a later phase. Use "Simulate Capture" to test the workflow.',
              style: proSubtitle(size: 10),
            )),
          ]),
        ),
      ]),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  final ProProject project;
  final int sessionCount;
  const _ChecklistCard({required this.project, required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    final isConnected = project.connection == HardwareConnection.connected ||
        project.connection == HardwareConnection.simulation;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('MEASUREMENT READINESS', style: proLabel(size: 9, spacing: 1.8)),
        const SizedBox(height: 12),
        _CheckRow('Project selected', true, project.name),
        _CheckRow('Hardware connection', isConnected, project.connection.label),
        _CheckRow('Sample rate', true, project.sampleRateLabel),
        _CheckRow('DSP target', true, project.dspTarget),
        const _CheckRow('Mic profile', true, 'Default'),
        _CheckRow('Sessions created', sessionCount > 0, '$sessionCount sessions'),
      ]),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool ok;
  final String value;
  const _CheckRow(this.label, this.ok, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(ok ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          color: ok ? kProGreen : Colors.white24, size: 13),
      const SizedBox(width: 10),
      SizedBox(width: 160, child: Text(label, style: proLabel(size: 10, spacing: 0.3))),
      Text(value, style: proValue(size: 10, color: ok ? Colors.white60 : Colors.white24)),
    ]),
  );
}

class _ProtocolRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ProtocolRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: Colors.white24, size: 12),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: proSubtitle(size: 10))),
    ]),
  );
}

// ── Session Detail Panel ──────────────────────────────────────────────────────

class _SessionDetailPanel extends StatelessWidget {
  final ProProject project;
  final MeasurementSession session;
  final VoidCallback onAddPoint;
  final ValueChanged<String> onSimulate;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onReject;
  final ValueChanged<String> onDeletePoint;
  final VoidCallback onMarkComplete;

  const _SessionDetailPanel({
    required this.project,
    required this.session,
    required this.onAddPoint,
    required this.onSimulate,
    required this.onAccept,
    required this.onReject,
    required this.onDeletePoint,
    required this.onMarkComplete,
  });

  bool get _isCompleted =>
      session.status == MeasurementSessionStatus.completed ||
      session.status == MeasurementSessionStatus.reviewed;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Session header
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.name, style: proTitle(size: 15)),
            const SizedBox(height: 4),
            Row(children: [
              ProStatusPill(
                label: session.status.label,
                color: _isCompleted ? kProGreen : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 8),
              Text('${session.sampleRateLabel} · ${session.sweepType.label} · ${session.micProfile}',
                  style: proLabel(size: 9, color: Colors.white38, spacing: 0.3)),
            ]),
          ])),
          if (!_isCompleted)
            GestureDetector(
              onTap: onMarkComplete,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: kProGreen.withValues(alpha: 0.1),
                  border: Border.all(color: kProGreen.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Mark Complete', style: TextStyle(color: kProGreen, fontSize: 11)),
              ),
            ),
        ]),
        if (session.notes != null) ...[
          const SizedBox(height: 10),
          Text(session.notes!, style: proSubtitle(size: 11)),
        ],
        const SizedBox(height: 20),

        // Stats row
        Wrap(spacing: 10, runSpacing: 10, children: [
          _StatChip('POINTS', '${session.points.length}'),
          _StatChip('CAPTURED', '${session.capturedCount}'),
          _StatChip('ACCEPTED', '${session.acceptedCount}'),
          _StatChip('REJECTED', '${session.points.where((p) => p.status == MeasurementPointStatus.rejected).length}'),
        ]),
        const SizedBox(height: 20),

        // Points section
        Row(children: [
          Text('MEASUREMENT POINTS', style: proLabel(size: 9, spacing: 1.8)),
          const Spacer(),
          if (!_isCompleted)
            GestureDetector(
              onTap: onAddPoint,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: kProAccent, size: 13),
                SizedBox(width: 4),
                Text('Add Point', style: TextStyle(color: kProAccent, fontSize: 11)),
              ]),
            ),
        ]),
        const SizedBox(height: 10),

        if (session.points.isEmpty)
          _EmptyPoints(isCompleted: _isCompleted, onAdd: onAddPoint)
        else
          ...session.points.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PointCard(
              point: p,
              readOnly: _isCompleted,
              onSimulate: () => onSimulate(p.id),
              onAccept: () => onAccept(p.id),
              onReject: () => onReject(p.id),
              onDelete: () => onDeletePoint(p.id),
            ),
          )),

        if (_isCompleted) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: kProGreen.withValues(alpha: 0.05),
              border: Border.all(color: kProGreen.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_outline, color: kProGreen, size: 14),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Session complete. Measurement data is ready for acoustic analysis in the Analyze tab.',
                style: proSubtitle(size: 11),
              )),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 9)),
      const SizedBox(height: 4),
      Text(value, style: proValue(size: 14, color: Colors.white70)),
    ]),
  );
}

class _EmptyPoints extends StatelessWidget {
  final bool isCompleted;
  final VoidCallback onAdd;
  const _EmptyPoints({required this.isCompleted, required this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(children: [
      const Icon(Icons.radio_button_unchecked, color: Colors.white12, size: 28),
      const SizedBox(height: 12),
      Text('No measurement points yet.', style: proTitle(size: 12, color: Colors.white38)),
      const SizedBox(height: 6),
      Text(
        isCompleted
            ? 'This session was completed without points.'
            : 'Add measurement points for each listening position or driver.',
        style: proSubtitle(size: 11),
        textAlign: TextAlign.center,
      ),
      if (!isCompleted) ...[
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: kProAccent.withValues(alpha: 0.1),
              border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Add Measurement Point', style: TextStyle(color: kProAccent, fontSize: 11)),
          ),
        ),
      ],
    ]),
  );
}

// ── Point Card ────────────────────────────────────────────────────────────────

class _PointCard extends StatelessWidget {
  final MeasurementPoint point;
  final bool readOnly;
  final VoidCallback onSimulate;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  const _PointCard({
    required this.point,
    required this.readOnly,
    required this.onSimulate,
    required this.onAccept,
    required this.onReject,
    required this.onDelete,
  });

  Color _statusColor() => switch (point.status) {
    MeasurementPointStatus.accepted  => kProGreen,
    MeasurementPointStatus.captured  => kProAccent,
    MeasurementPointStatus.rejected  => kProRed,
    MeasurementPointStatus.ready     => kProAmber,
    MeasurementPointStatus.pending   => const Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) {
    final result = point.result;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(point.label, style: proTitle(size: 12)),
            const SizedBox(height: 4),
            Row(children: [
              ProStatusPill(label: point.status.label, color: _statusColor()),
              const SizedBox(width: 8),
              Text('${point.channel.label} · ${point.position.label}',
                  style: proLabel(size: 9, color: Colors.white38, spacing: 0.3)),
              const SizedBox(width: 8),
              Text('${point.distanceCm.toStringAsFixed(0)} cm · ${point.angleDeg.toStringAsFixed(0)}°',
                  style: proLabel(size: 9, color: Colors.white24, spacing: 0.3)),
            ]),
          ])),
          if (!readOnly)
            PopupMenuButton<String>(
              color: kProPanel,
              iconColor: Colors.white24,
              iconSize: 14,
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: kProRed, fontSize: 12))),
              ],
            ),
        ]),

        // Result card
        if (result != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: kProPanel,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('CAPTURE RESULT', style: proLabel(size: 8, color: kProAccent, spacing: 1.5)),
                const Spacer(),
                Text('Confidence: ${(result.confidence * 100).toStringAsFixed(0)}%',
                    style: proLabel(size: 8, color: Colors.white38, spacing: 0.3)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _ResultItem('PEAK', '${result.peakLevelDb.toStringAsFixed(1)} dBFS'),
                const SizedBox(width: 16),
                _ResultItem('NOISE FLOOR', '${result.noiseFloorDb.toStringAsFixed(1)} dBFS'),
                const SizedBox(width: 16),
                _ResultItem('USABLE RANGE', result.usableRange),
              ]),
              if (result.issues.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(result.issues.first,
                    style: proLabel(size: 8, color: kProAmber, spacing: 0.3)),
              ],
            ]),
          ),
        ],

        // Actions
        if (!readOnly) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (point.status == MeasurementPointStatus.pending ||
                point.status == MeasurementPointStatus.ready)
              _PointActionButton('Simulate Capture', kProAccent, onSimulate),
            if (point.status == MeasurementPointStatus.captured)
              _PointActionButton('Accept', kProGreen, onAccept),
            if (point.status == MeasurementPointStatus.captured)
              _PointActionButton('Reject', kProRed, onReject),
            if (point.status == MeasurementPointStatus.rejected)
              _PointActionButton('Simulate Capture', kProAccent, onSimulate),
          ]),
        ],
      ]),
    );
  }
}

class _ResultItem extends StatelessWidget {
  final String label;
  final String value;
  const _ResultItem(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: proLabel(size: 8, spacing: 0.8)),
    const SizedBox(height: 2),
    Text(value, style: proValue(size: 10, color: Colors.white60)),
  ]);
}

class _PointActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PointActionButton(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10)),
    ),
  );
}

// ── New Session Dialog ────────────────────────────────────────────────────────

class _NewSessionArgs {
  final String name;
  final int sampleRate;
  final SweepType sweepType;
  final String micProfile;
  final String notes;
  const _NewSessionArgs(this.name, this.sampleRate, this.sweepType, this.micProfile, this.notes);
}

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog();
  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  final _nameCtrl  = TextEditingController(text: 'Measurement Session 1');
  final _notesCtrl = TextEditingController();
  int _sampleRate  = 48000;
  SweepType _sweepType = SweepType.placeholder;
  String _micProfile = 'Default';

  static const _sampleRates  = [44100, 48000, 96000];
  static const _sweepTypes   = SweepType.values;
  static const _micProfiles  = ['Default', 'Calibrated', 'UMIK-1', 'ECM8000', 'Manual'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kProPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: kProBorder),
      ),
      child: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
            ),
            child: Row(children: [
              Text('New Measurement Session', style: proTitle(size: 14)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),

          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _DlgLabel('Session Name'),
              _ProTextField(controller: _nameCtrl, autofocus: true),
              const SizedBox(height: 14),

              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _DlgLabel('Sample Rate'),
                  _ProDropdown<int>(
                    value: _sampleRate,
                    items: _sampleRates,
                    labelOf: (v) => '${(v / 1000).toStringAsFixed(0)} kHz',
                    onChanged: (v) => setState(() => _sampleRate = v),
                  ),
                ])),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _DlgLabel('Sweep Type'),
                  _ProDropdown<SweepType>(
                    value: _sweepType,
                    items: _sweepTypes,
                    labelOf: (v) => v.label,
                    onChanged: (v) => setState(() => _sweepType = v),
                  ),
                ])),
              ]),
              const SizedBox(height: 14),

              const _DlgLabel('Mic Profile'),
              _ProDropdown<String>(
                value: _micProfile,
                items: _micProfiles,
                labelOf: (v) => v,
                onChanged: (v) => setState(() => _micProfile = v),
              ),
              const SizedBox(height: 14),

              const _DlgLabel('Notes (optional)'),
              _ProTextField(controller: _notesCtrl, maxLines: 3),
              const SizedBox(height: 18),
            ]),
          )),

          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: kProBorder, width: 0.5)),
            ),
            child: Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: proSubtitle(size: 12)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context, _NewSessionArgs(
                  _nameCtrl.text, _sampleRate, _sweepType, _micProfile, _notesCtrl.text,
                )),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: kProAccent.withValues(alpha: 0.12),
                    border: Border.all(color: kProAccent.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Create Session', style: TextStyle(color: kProAccent, fontSize: 12)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Add Point Dialog ──────────────────────────────────────────────────────────

class _NewPointArgs {
  final String label;
  final MeasurementChannel channel;
  final MeasurementPosition position;
  final double distanceCm;
  final double angleDeg;
  final String notes;
  const _NewPointArgs(this.label, this.channel, this.position,
      this.distanceCm, this.angleDeg, this.notes);
}

class _AddPointDialog extends StatefulWidget {
  final int existingCount;
  const _AddPointDialog({required this.existingCount});
  @override
  State<_AddPointDialog> createState() => _AddPointDialogState();
}

class _AddPointDialogState extends State<_AddPointDialog> {
  late final TextEditingController _labelCtrl;
  final _distCtrl  = TextEditingController(text: '100');
  final _angleCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  MeasurementChannel  _channel  = MeasurementChannel.left;
  MeasurementPosition _position = MeasurementPosition.listeningPosition;

  static const _defaultLabels = [
    'Listening Position L', 'Listening Position R',
    'Nearfield Woofer', 'Nearfield Tweeter', 'Center Seat',
  ];

  @override
  void initState() {
    super.initState();
    final i = widget.existingCount;
    final label = i < _defaultLabels.length ? _defaultLabels[i] : 'Point ${i + 1}';
    _labelCtrl = TextEditingController(text: label);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _distCtrl.dispose();
    _angleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: kProPanel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: kProBorder),
    ),
    child: SizedBox(
      width: 400,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
          ),
          child: Row(children: [
            Text('Add Measurement Point', style: proTitle(size: 14)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white38, size: 16),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),

        Flexible(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _DlgLabel('Label'),
            _ProTextField(controller: _labelCtrl, autofocus: true),
            const SizedBox(height: 12),

            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _DlgLabel('Channel'),
                _ProDropdown<MeasurementChannel>(
                  value: _channel,
                  items: MeasurementChannel.values,
                  labelOf: (v) => v.label,
                  onChanged: (v) => setState(() => _channel = v),
                ),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _DlgLabel('Position'),
                _ProDropdown<MeasurementPosition>(
                  value: _position,
                  items: MeasurementPosition.values,
                  labelOf: (v) => v.label,
                  onChanged: (v) => setState(() => _position = v),
                ),
              ])),
            ]),
            const SizedBox(height: 12),

            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _DlgLabel('Distance (cm)'),
                _ProTextField(controller: _distCtrl, numeric: true),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _DlgLabel('Angle (°)'),
                _ProTextField(controller: _angleCtrl, numeric: true),
              ])),
            ]),
            const SizedBox(height: 12),

            const _DlgLabel('Notes (optional)'),
            _ProTextField(controller: _notesCtrl, maxLines: 2),
            const SizedBox(height: 16),
          ]),
        )),

        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: kProBorder, width: 0.5)),
          ),
          child: Row(children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: proSubtitle(size: 12)),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                final label = _labelCtrl.text.trim();
                if (label.isEmpty) return;
                Navigator.pop(context, _NewPointArgs(
                  label, _channel, _position,
                  double.tryParse(_distCtrl.text) ?? 100.0,
                  double.tryParse(_angleCtrl.text) ?? 0.0,
                  _notesCtrl.text,
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: kProAccent.withValues(alpha: 0.12),
                  border: Border.all(color: kProAccent.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Add Point', style: TextStyle(color: kProAccent, fontSize: 12)),
              ),
            ),
          ]),
        ),
      ]),
    ),
  );
}

// ── Shared dialog widgets ─────────────────────────────────────────────────────

class _DlgLabel extends StatelessWidget {
  final String text;
  const _DlgLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(text, style: proLabel(size: 10, color: Colors.white38, spacing: 1)),
  );
}

class _ProTextField extends StatelessWidget {
  final TextEditingController controller;
  final bool autofocus;
  final bool numeric;
  final int maxLines;
  const _ProTextField({
    required this.controller,
    this.autofocus = false,
    this.numeric = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    maxLines: maxLines,
    keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
    style: proTitle(size: 12),
    decoration: const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: kProBorder)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kProAccent)),
      filled: true,
      fillColor: kProSurface,
    ),
  );
}

class _ProDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  const _ProDropdown({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: DropdownButton<T>(
      value: value,
      isExpanded: true,
      dropdownColor: kProPanel,
      underline: const SizedBox.shrink(),
      style: proTitle(size: 11),
      iconEnabledColor: Colors.white38,
      items: items.map((i) => DropdownMenuItem(
        value: i,
        child: Text(labelOf(i), style: proTitle(size: 11)),
      )).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  );
}

// ── Phase C: Driver Readiness Bar ─────────────────────────────────────────────

class _DriverReadinessBar extends StatelessWidget {
  final MeasurementProjectState acoustic;
  const _DriverReadinessBar({required this.acoustic});

  Color _statusColor(MeasurementStatus s) => switch (s) {
    MeasurementStatus.validated   => kProGreen,
    MeasurementStatus.imported    => kProAccent,
    MeasurementStatus.needsReview => kProAmber,
    MeasurementStatus.missingFile => kProRed,
    MeasurementStatus.empty       => const Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    decoration: const BoxDecoration(
      color: kProPanel,
      border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('DRIVER CHANNELS', style: proLabel(size: 9, color: Colors.white24, spacing: 2)),
        const Spacer(),
        Text(acoustic.readinessLabel, style: proSubtitle(size: 9)),
      ]),
      const SizedBox(height: 8),
      Row(
        children: acoustic.driverChannels.map((ch) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _ChannelPill(channel: ch, color: _statusColor(ch.measurementStatus)),
          ),
        )).toList(),
      ),
    ]),
  );
}

class _ChannelPill extends StatelessWidget {
  final DriverChannel channel;
  final Color color;
  const _ChannelPill({required this.channel, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      border: Border.all(color: color.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(channel.role.short,
            style: TextStyle(color: color, fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(channel.side.label, style: proLabel(size: 8, color: Colors.white24, spacing: 0.5)),
      ]),
      const SizedBox(height: 3),
      Text(channel.name, style: proTitle(size: 10, color: Colors.white60), overflow: TextOverflow.ellipsis),
      const SizedBox(height: 4),
      Row(children: [
        _FileIndicator(
          label: 'FRD',
          present: channel.hasFrd,
          parsed: channel.hasParsedFrd,
          hasPhase: channel.frdData?.hasPhase ?? false,
          color: kProAccent,
        ),
        const SizedBox(width: 4),
        _FileIndicator(
          label: 'ZMA',
          present: channel.hasZma,
          parsed: channel.hasParsedZma,
          hasPhase: channel.zmaData?.hasImpedance ?? false,
          color: kProAmber,
        ),
      ]),
      if (channel.hasParsedFrd) ...[
        const SizedBox(height: 3),
        Text(
          '${channel.frdData!.pointCount} pts  ${channel.frdData!.freqRangeLabel}'
          '${channel.frdData!.hasPhase ? "" : "  no phase"}',
          style: const TextStyle(color: Colors.white24, fontSize: 8),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ]),
  );
}

class _FileIndicator extends StatelessWidget {
  final String label;
  final bool present;
  final bool parsed;
  final bool hasPhase;
  final Color color;
  const _FileIndicator({
    required this.label,
    required this.present,
    this.parsed = false,
    this.hasPhase = false,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = parsed
        ? color
        : present
            ? color.withValues(alpha: 0.5)
            : Colors.white12;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: parsed
            ? color.withValues(alpha: 0.12)
            : present
                ? color.withValues(alpha: 0.05)
                : Colors.transparent,
        border: Border.all(
            color: parsed
                ? color.withValues(alpha: 0.5)
                : present
                    ? color.withValues(alpha: 0.25)
                    : Colors.white12),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                color: effectiveColor, fontSize: 8, letterSpacing: 0.5)),
        if (parsed) ...[
          const SizedBox(width: 3),
          Icon(Icons.check, color: effectiveColor, size: 8),
        ],
      ]),
    );
  }
}
