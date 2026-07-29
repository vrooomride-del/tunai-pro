import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/pro_project.dart';
import '../../core/pro_project_store.dart';
import '../../shared/pro_widgets.dart';
import 'widgets/deploy_dialog.dart';

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
    // isConnected reflects PASS_HANDSHAKE: _syncConnectionToStore in hardware_tab
    // only writes HardwareConnection.connected when handshakeComplete is true,
    // which requires DSP1701.100.00.01 firmware identity confirmation.
    final isConnected = project?.connection == HardwareConnection.connected;

    final canDeploy = project != null &&
        project.dspTarget == 'ADAU1701' &&
        isConnected &&
        project.acousticState.driverChannels.isNotEmpty;

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: kProPanel,
        border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
      ),
      child: Row(children: [
        // Scrollable left section with project metadata
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              const SizedBox(width: 16),
              _StatusItem(label: 'PROJECT', value: name, maxWidth: 140),
              const _Div(),
              _StatusItem(
                label: 'DEVICE',
                value: device,
                valueColor: isConnected ? kProGreen : const Color(0xFF6B7280),
              ),
              const _Div(),
              _StatusItem(label: 'SAMPLE RATE', value: sampleRate),
              const _Div(),
              _StatusItem(label: 'DSP TARGET', value: dspTarget, maxWidth: 100),
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
                maxWidth: 110,
              ),
              if (project != null && project.measurementCount > 0) ...[
                const _Div(),
                _StatusItem(
                  label: 'SESSIONS',
                  value: '${project.measurementCount}',
                  valueColor: kProGreen,
                ),
              ],
              const SizedBox(width: 16),
            ]),
          ),
        ),
        // DEPLOY button — ADAU1701 + ICP5 handshake + channels required
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _DeployButton(
            enabled: canDeploy,
            onTap: () => showDeployDialog(
              context: context,
              projectId: projectId,
              channels: project!.acousticState.driverChannels,
              tuning: project.tuningState,
              previousAppliedGains: project.deployState.appliedGainsByChannel,
            ),
          ),
        ),
        // Fixed right safety badge — never overflows
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text(
            'AI suggests · Expert verifies · AOS protects',
            style: proLabel(size: 9, color: Colors.white24, spacing: 0.5),
            overflow: TextOverflow.ellipsis,
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
  final double? maxWidth;
  const _StatusItem({required this.label, required this.value, this.valueColor, this.maxWidth});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: proLabel(size: 9, spacing: 1)),
      const SizedBox(width: 6),
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? 200),
        child: Text(
          value,
          style: proValue(size: 10, color: valueColor ?? Colors.white54),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]),
  );
}

class _Div extends StatelessWidget {
  const _Div();
  @override
  Widget build(BuildContext context) =>
      Container(width: 0.5, height: 16, color: kProBorder);
}

class _DeployButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _DeployButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled
                  ? kProAccent.withValues(alpha: 0.7)
                  : kProBorder,
            ),
            borderRadius: BorderRadius.circular(3),
            color: enabled
                ? kProAccent.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              Icons.upload_outlined,
              size: 11,
              color: enabled ? kProAccent : Colors.white24,
            ),
            const SizedBox(width: 5),
            Text(
              'DEPLOY',
              style: proLabel(
                size: 9,
                color: enabled ? kProAccent : Colors.white24,
                spacing: 1.2,
              ),
            ),
          ]),
        ),
      );
}
