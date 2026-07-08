import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/pro_project.dart';
import '../../core/pro_project_store.dart';
import '../../shared/pro_widgets.dart';

class ProjectStatusBar extends ConsumerWidget {
  final String projectId;
  const ProjectStatusBar({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == projectId).firstOrNull;

    final name = project?.name ?? 'No Project';
    final device = project?.connection.label ?? HardwareConnection.disconnected.label;
    final sampleRate = project?.sampleRateLabel ?? '—';
    final dspTarget = project?.dspTarget ?? '—';
    final profileLabel = project?.profileStatus.label ?? '—';
    final safetyLabel = project?.safetyStatus.label ?? '—';
    final isConnected = project?.connection == HardwareConnection.connected;

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: kProPanel,
        border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
      ),
      child: Row(children: [
        const SizedBox(width: 16),
        _StatusItem(label: 'PROJECT', value: name),
        const _Div(),
        _StatusItem(
          label: 'DEVICE',
          value: device,
          valueColor: isConnected ? kProGreen : const Color(0xFF6B7280),
        ),
        const _Div(),
        _StatusItem(label: 'SAMPLE RATE', value: sampleRate),
        const _Div(),
        _StatusItem(label: 'DSP TARGET', value: dspTarget),
        const _Div(),
        _StatusItem(
          label: 'PROFILE',
          value: profileLabel,
          valueColor: _profileColor(project?.profileStatus),
        ),
        const _Div(),
        _StatusItem(
          label: 'SAFETY',
          value: safetyLabel,
          valueColor: _safetyColor(project?.safetyStatus),
        ),
        if (project != null && project.measurementCount > 0) ...[
          const _Div(),
          _StatusItem(
            label: 'SESSIONS',
            value: '${project.measurementCount}',
            valueColor: kProGreen,
          ),
        ],
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text(
            'AI suggests · Expert verifies · AOS protects · DSP executes',
            style: proLabel(size: 9, color: Colors.white24, spacing: 0.5),
          ),
        ),
      ]),
    );
  }

  Color _profileColor(ProfileStatus? s) => switch (s) {
    ProfileStatus.draft => const Color(0xFF6B7280),
    ProfileStatus.measured => kProAmber,
    ProfileStatus.tuned => kProAccent,
    ProfileStatus.verified => kProGreen,
    ProfileStatus.deployed => kProGreen,
    null => const Color(0xFF6B7280),
  };

  Color _safetyColor(SafetyStatus? s) => switch (s) {
    SafetyStatus.notVerified => const Color(0xFF6B7280),
    SafetyStatus.verified => kProGreen,
    SafetyStatus.warning => kProAmber,
    SafetyStatus.blocked => kProRed,
    null => const Color(0xFF6B7280),
  };
}

class _StatusItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _StatusItem({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: proLabel(size: 9, spacing: 1)),
      const SizedBox(width: 6),
      Text(value, style: proValue(size: 10, color: valueColor ?? Colors.white54)),
    ]),
  );
}

class _Div extends StatelessWidget {
  const _Div();
  @override
  Widget build(BuildContext context) =>
      Container(width: 0.5, height: 16, color: kProBorder);
}
