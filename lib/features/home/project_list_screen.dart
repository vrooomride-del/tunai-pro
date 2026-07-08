import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/pro_project.dart';
import '../../core/pro_project_store.dart';
import '../../shared/pro_widgets.dart';
import '../workbench/workbench_shell.dart';

class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  void _openProject(BuildContext context, WidgetRef ref, ProProject project) {
    ref.read(proProjectStoreProvider.notifier).setCurrentProject(project.id);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => WorkbenchShell(projectId: project.id)),
    );
  }

  Future<void> _duplicateProject(BuildContext context, WidgetRef ref, ProProject project) async {
    final dup = await ref.read(proProjectStoreProvider.notifier).duplicateProject(project.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Duplicated as "${dup.name}"'),
        backgroundColor: kProPanel,
      ));
    }
  }

  Future<void> _renameProject(BuildContext context, WidgetRef ref, ProProject project) async {
    final ctrl = TextEditingController(text: project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kProPanel,
        title: Text('Rename Project', style: proTitle(size: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: proTitle(size: 13),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kProBorder)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kProAccent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: proSubtitle(size: 12)),
          ),
          TextButton(
            onPressed: () {
              final n = ctrl.text.trim();
              if (n.isNotEmpty) Navigator.pop(ctx, n);
            },
            child: const Text('Rename', style: TextStyle(color: kProAccent, fontSize: 12)),
          ),
        ],
      ),
    );
    if (name != null) {
      await ref.read(proProjectStoreProvider.notifier).renameProject(project.id, name);
    }
  }

  Future<void> _deleteProject(BuildContext context, WidgetRef ref, ProProject project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kProPanel,
        title: Text('Delete this project?', style: proTitle(size: 14)),
        content: Text('This cannot be undone.', style: proSubtitle()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: proSubtitle(size: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kProRed, fontSize: 12)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(proProjectStoreProvider.notifier).deleteProject(project.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(proProjectStoreProvider);
    final projects = store.projects.reversed.toList();

    return Scaffold(
      backgroundColor: kProBg,
      appBar: AppBar(
        backgroundColor: kProPanel,
        elevation: 0,
        title: Text('Open Project', style: proTitle(size: 14)),
        iconTheme: const IconThemeData(color: Colors.white70),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: kProBorder),
        ),
      ),
      body: projects.isEmpty
          ? _EmptyState(onNewProject: () => Navigator.pop(context))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _ProjectCard(
                project: projects[i],
                isCurrent: projects[i].id == store.currentProjectId,
                onOpen: () => _openProject(context, ref, projects[i]),
                onDuplicate: () => _duplicateProject(context, ref, projects[i]),
                onRename: () => _renameProject(context, ref, projects[i]),
                onDelete: () => _deleteProject(context, ref, projects[i]),
              ),
            ),
    );
  }
}

// ── Project Card ──────────────────────────────────────────────────────────────

class _ProjectCard extends StatelessWidget {
  final ProProject project;
  final bool isCurrent;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ProjectCard({
    required this.project,
    required this.isCurrent,
    required this.onOpen,
    required this.onDuplicate,
    required this.onRename,
    required this.onDelete,
  });

  String _updatedLabel() {
    final diff = DateTime.now().difference(project.updatedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${project.updatedAt.year}.${project.updatedAt.month.toString().padLeft(2,'0')}.${project.updatedAt.day.toString().padLeft(2,'0')}';
  }

  Color _statusColor(ProfileStatus s) => switch (s) {
    ProfileStatus.draft => const Color(0xFF6B7280),
    ProfileStatus.measured => kProAmber,
    ProfileStatus.tuned => kProAccent,
    ProfileStatus.verified => kProGreen,
    ProfileStatus.deployed => kProGreen,
  };

  Color _safetyColor(SafetyStatus s) => switch (s) {
    SafetyStatus.notVerified => const Color(0xFF6B7280),
    SafetyStatus.verified => kProGreen,
    SafetyStatus.warning => kProAmber,
    SafetyStatus.blocked => kProRed,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        decoration: BoxDecoration(
          color: isCurrent ? kProAccent.withValues(alpha: 0.07) : kProSurface,
          border: Border.all(color: isCurrent ? kProAccent.withValues(alpha: 0.3) : kProBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Name + actions
          Row(children: [
            Expanded(child: Text(project.name, style: proTitle(size: 13))),
            _OverflowMenu(
              onOpen: onOpen,
              onDuplicate: onDuplicate,
              onRename: onRename,
              onDelete: onDelete,
            ),
          ]),
          const SizedBox(height: 10),
          // Meta row
          Wrap(spacing: 8, runSpacing: 6, children: [
            _MetaChip(icon: Icons.speaker_outlined, text: project.speakerModel),
            _MetaChip(icon: Icons.room_outlined, text: project.roomName),
            _MetaChip(icon: Icons.memory_outlined, text: project.dspTarget),
            _MetaChip(icon: Icons.graphic_eq_outlined, text: project.sampleRateLabel),
            _MetaChip(icon: Icons.access_time_outlined, text: _updatedLabel()),
          ]),
          const SizedBox(height: 10),
          // Status pills
          Row(children: [
            ProStatusPill(
              label: project.profileStatus.label,
              color: _statusColor(project.profileStatus),
            ),
            const SizedBox(width: 6),
            ProStatusPill(
              label: 'Safety: ${project.safetyStatus.label}',
              color: _safetyColor(project.safetyStatus),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 6),
              const ProStatusPill(label: 'Current', color: kProAccent),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 10, color: Colors.white24),
    const SizedBox(width: 4),
    Text(text, style: proLabel(size: 10, color: const Color(0xFF6B7280), spacing: 0.3)),
  ]);
}

class _OverflowMenu extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _OverflowMenu({
    required this.onOpen,
    required this.onDuplicate,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    color: kProPanel,
    icon: const Icon(Icons.more_vert, color: Colors.white24, size: 18),
    onSelected: (v) {
      switch (v) {
        case 'open': onOpen();
        case 'duplicate': onDuplicate();
        case 'rename': onRename();
        case 'delete': onDelete();
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(value: 'open', child: Text('Open', style: proTitle(size: 12))),
      PopupMenuItem(value: 'duplicate', child: Text('Duplicate', style: proTitle(size: 12))),
      PopupMenuItem(value: 'rename', child: Text('Rename', style: proTitle(size: 12))),
      const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: kProRed, fontSize: 12))),
    ],
  );
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onNewProject;
  const _EmptyState({required this.onNewProject});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.folder_open_outlined, color: Colors.white12, size: 40),
        const SizedBox(height: 20),
        Text('No projects yet.', style: proTitle(size: 15, color: Colors.white60)),
        const SizedBox(height: 8),
        Text('Create your first tuning project to begin.', style: proSubtitle(size: 12), textAlign: TextAlign.center),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onNewProject,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: kProAccent.withValues(alpha: 0.12),
              border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('New Project', style: TextStyle(color: kProAccent, fontSize: 13)),
          ),
        ),
      ]),
    ),
  );
}
