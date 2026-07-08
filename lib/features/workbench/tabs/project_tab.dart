import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../shared/pro_widgets.dart';

class ProjectTab extends ConsumerWidget {
  final String projectId;
  const ProjectTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == projectId).firstOrNull;

    if (project == null) {
      return Center(child: Text('Project not found.', style: proSubtitle()));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          const Icon(Icons.folder_outlined, color: kProAccent, size: 16),
          const SizedBox(width: 10),
          Text('Project Overview', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 6),
        Text('Manage project information, target hardware, and tuning status.',
            style: proSubtitle()),
        const SizedBox(height: 24),

        // ── 1. Project Information ──────────────────────────────────────────
        const _SectionLabel('PROJECT INFORMATION'),
        const SizedBox(height: 10),
        _InfoCard(children: [
          _InfoRow('Project Name', project.name),
          _InfoRow('Speaker Model', project.speakerModel),
          _InfoRow('Room / Location', project.roomName),
          _InfoRow('Sample Rate', project.sampleRateLabel),
          _InfoRow('DSP Target', project.dspTarget),
          _InfoRow('Channel Config', project.channelConfig),
          _InfoRow('Created', _dateLabel(project.createdAt)),
          _InfoRow('Last Updated', _dateLabel(project.updatedAt)),
        ]),
        const SizedBox(height: 20),

        // ── 2. Workflow Progress ────────────────────────────────────────────
        const _SectionLabel('WORKFLOW PROGRESS'),
        const SizedBox(height: 10),
        _WorkflowProgress(current: project.profileStatus),
        const SizedBox(height: 20),

        // ── 3. Quick Actions ───────────────────────────────────────────────
        const _SectionLabel('QUICK ACTIONS'),
        const SizedBox(height: 8),
        Text(
          'Manually advance the project status for testing. Real transitions will be triggered by each workbench module.',
          style: proSubtitle(size: 10),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _QuickActionButton(
            label: 'Mark as Measured',
            enabled: project.profileStatus == ProfileStatus.draft,
            onTap: () => ref.read(proProjectStoreProvider.notifier)
                .updateProfileStatus(projectId, ProfileStatus.measured),
          ),
          _QuickActionButton(
            label: 'Mark as Tuned',
            enabled: project.profileStatus == ProfileStatus.measured,
            onTap: () => ref.read(proProjectStoreProvider.notifier)
                .updateProfileStatus(projectId, ProfileStatus.tuned),
          ),
          _QuickActionButton(
            label: 'Mark as Verified',
            enabled: project.profileStatus == ProfileStatus.tuned,
            onTap: () {
              ref.read(proProjectStoreProvider.notifier)
                  .updateProfileStatus(projectId, ProfileStatus.verified);
              ref.read(proProjectStoreProvider.notifier)
                  .updateSafetyStatus(projectId, SafetyStatus.verified);
            },
          ),
          _QuickActionButton(
            label: 'Mark as Deployed',
            enabled: project.profileStatus == ProfileStatus.verified,
            onTap: () => ref.read(proProjectStoreProvider.notifier)
                .updateProfileStatus(projectId, ProfileStatus.deployed),
          ),
          _QuickActionButton(
            label: 'Reset to Draft',
            enabled: project.profileStatus != ProfileStatus.draft,
            color: kProRed,
            onTap: () {
              ref.read(proProjectStoreProvider.notifier)
                  .updateProfileStatus(projectId, ProfileStatus.draft);
              ref.read(proProjectStoreProvider.notifier)
                  .updateSafetyStatus(projectId, SafetyStatus.notVerified);
            },
          ),
        ]),

        const SizedBox(height: 24),

        // ── Principle card ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DESIGN PRINCIPLE', style: proLabel(size: 9, spacing: 1.8)),
            const SizedBox(height: 10),
            Text(
              'AI suggests.  Expert verifies.  AOS protects.  DSP executes.',
              style: proTitle(size: 12, color: Colors.white60),
            ),
          ]),
        ),
      ]),
    );
  }

  String _dateLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.year}.${dt.month.toString().padLeft(2,'0')}.${dt.day.toString().padLeft(2,'0')}';
  }
}

// ── Workflow Progress ─────────────────────────────────────────────────────────

class _WorkflowProgress extends StatelessWidget {
  final ProfileStatus current;
  const _WorkflowProgress({required this.current});

  static const _steps = [
    (ProfileStatus.draft, 'Draft', 'Project created'),
    (ProfileStatus.measured, 'Measured', 'Frequency response captured'),
    (ProfileStatus.tuned, 'Tuned', 'Crossover, PEQ, delay applied'),
    (ProfileStatus.verified, 'Verified', 'Protection and safety validated'),
    (ProfileStatus.deployed, 'Deployed', 'Profile written to hardware'),
  ];

  Color _stepColor(ProfileStatus step) {
    if (step.index < current.index) return kProGreen;
    if (step == current) return kProAccent;
    return const Color(0xFF374151);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: _steps.asMap().entries.map((e) {
          final i = e.key;
          final (step, label, desc) = e.value;
          final done = step.index < current.index;
          final active = step == current;
          final color = _stepColor(step);
          return Column(children: [
            if (i > 0)
              Container(
                width: 1,
                height: 12,
                margin: const EdgeInsets.only(left: 10),
                color: done ? kProGreen.withValues(alpha: 0.4) : kProBorder,
                alignment: Alignment.centerLeft,
              ),
            Row(children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: active
                      ? kProAccent.withValues(alpha: 0.15)
                      : done
                          ? kProGreen.withValues(alpha: 0.12)
                          : kProSurface,
                  border: Border.all(color: color.withValues(alpha: done || active ? 0.7 : 0.3)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(child: done
                  ? const Icon(Icons.check, color: kProGreen, size: 12)
                  : Text('${i + 1}', style: proLabel(size: 9, color: color))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: proValue(size: 11, color: active ? Colors.white : (done ? Colors.white60 : Colors.white38))),
                const SizedBox(height: 1),
                Text(desc, style: proLabel(size: 9, color: Colors.white24, spacing: 0.3)),
              ])),
              if (active)
                const ProStatusPill(label: 'Current', color: kProAccent),
            ]),
          ]);
        }).toList(),
      ),
    );
  }
}

// ── Quick Action Button ───────────────────────────────────────────────────────

class _QuickActionButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final Color color;

  const _QuickActionButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.color = kProAccent,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: enabled ? color.withValues(alpha: 0.1) : kProSurface,
        border: Border.all(color: enabled ? color.withValues(alpha: 0.4) : kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
            color: enabled ? color : Colors.white24,
            fontSize: 11,
          )),
    ),
  );
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: proLabel(size: 10, spacing: 1.8));
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(children: children),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 130, child: Text(label, style: proLabel(size: 10, spacing: 0.5))),
      Expanded(child: Text(value, style: proValue(size: 11, color: Colors.white60))),
    ]),
  );
}
