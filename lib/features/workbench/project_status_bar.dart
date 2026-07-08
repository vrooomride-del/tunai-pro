import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/pro_project.dart';
import '../../shared/pro_widgets.dart';

class ProjectStatusBar extends ConsumerWidget {
  const ProjectStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(proProjectProvider);

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: kProPanel,
        border: Border(
          bottom: BorderSide(color: kProBorder, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          _StatusItem(label: 'PROJECT', value: project.name),
          _Divider(),
          _StatusItem(label: 'DEVICE', value: project.deviceName,
              valueColor: project.connection != HardwareConnection.none
                  ? kProGreen
                  : const Color(0xFF6B7280)),
          _Divider(),
          _StatusItem(label: 'SAMPLE RATE', value: project.sampleRateLabel),
          _Divider(),
          _StatusItem(label: 'DSP TARGET', value: project.dspTarget),
          _Divider(),
          _StatusItem(label: 'PROFILE', value: project.profileStatusLabel,
              valueColor: _profileColor(project.profileStatus)),
          _Divider(),
          _StatusItem(label: 'SAFETY', value: project.safetyStatusLabel,
              valueColor: _safetyColor(project.safetyStatus)),
          const Spacer(),
          // Principle tag
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              'AI suggests · Expert verifies · AOS protects · DSP executes',
              style: proLabel(size: 9, color: Colors.white24, spacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Color _profileColor(ProfileStatus s) => switch (s) {
    ProfileStatus.draft => const Color(0xFF6B7280),
    ProfileStatus.reviewing => kProAmber,
    ProfileStatus.verified => kProGreen,
    ProfileStatus.deployed => kProAccent,
  };

  Color _safetyColor(SafetyStatus s) => switch (s) {
    SafetyStatus.notVerified => const Color(0xFF6B7280),
    SafetyStatus.checking => kProAmber,
    SafetyStatus.passed => kProGreen,
    SafetyStatus.failed => kProRed,
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

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 0.5,
    height: 16,
    color: kProBorder,
  );
}
