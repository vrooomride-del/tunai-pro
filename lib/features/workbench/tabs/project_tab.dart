import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../shared/pro_widgets.dart';

class ProjectTab extends ConsumerWidget {
  const ProjectTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(proProjectProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.folder_outlined, color: kProAccent, size: 16),
          const SizedBox(width: 10),
          Text('Project Overview', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 6),
        Text('Manage project information, target hardware, and tuning status.', style: proSubtitle()),
        const SizedBox(height: 24),

        // Project details card
        _ProInfoCard(children: [
          _InfoRow('Project Name', project.name),
          _InfoRow('Device', project.deviceName),
          _InfoRow('Sample Rate', project.sampleRateLabel),
          _InfoRow('DSP Target', project.dspTarget),
          _InfoRow('Profile Status', project.profileStatusLabel),
          _InfoRow('Safety Status', project.safetyStatusLabel),
        ]),
        const SizedBox(height: 16),

        // Workflow status
        Text('WORKFLOW', style: proLabel(size: 10, spacing: 1.8)),
        const SizedBox(height: 10),
        const _WorkflowRow(step: 1, label: 'Measure', done: false),
        const _WorkflowRow(step: 2, label: 'Analyze', done: false),
        const _WorkflowRow(step: 3, label: 'Design Crossover + PEQ', done: false),
        const _WorkflowRow(step: 4, label: 'Verify Protection', done: false),
        const _WorkflowRow(step: 5, label: 'Deploy to Hardware', done: false),

        const SizedBox(height: 20),
        // Principle card
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
            Text('AI suggests.  Expert verifies.  AOS protects.  DSP executes.',
                style: proTitle(size: 12, color: Colors.white60)),
          ]),
        ),
      ]),
    );
  }
}

class _ProInfoCard extends StatelessWidget {
  final List<Widget> children;
  const _ProInfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
      SizedBox(width: 120, child: Text(label, style: proLabel(size: 10, spacing: 0.5))),
      Text(value, style: proValue(size: 11, color: Colors.white60)),
    ]),
  );
}

class _WorkflowRow extends StatelessWidget {
  final int step;
  final String label;
  final bool done;
  const _WorkflowRow({required this.step, required this.label, required this.done});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: done ? kProGreen.withValues(alpha: 0.15) : kProSurface,
          border: Border.all(color: done ? kProGreen : kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Center(child: done
            ? const Icon(Icons.check, color: kProGreen, size: 12)
            : Text('$step', style: proLabel(size: 9, color: Colors.white38))),
      ),
      const SizedBox(width: 10),
      Text(label, style: proValue(size: 11, color: done ? Colors.white60 : Colors.white38)),
    ]),
  );
}
