import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/deploy/pro_hardware_context_provider.dart';
import '../../core/orchestrator/pro_guided_ai_controller.dart';
import '../../core/orchestrator/pro_release_progress.dart';
import '../../core/pro_project.dart';
import '../../core/pro_project_store.dart';
import '../../shared/pro_widgets.dart';
import 'tabs/live_measurement_controller.dart';
import 'widgets/deploy_dialog.dart';

class ProjectStatusBar extends ConsumerWidget {
  final String projectId;
  const ProjectStatusBar({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == projectId).firstOrNull;

    final name = project?.name ?? 'No Project';
    final sampleRate = project?.sampleRateLabel ?? '—';
    final dspTarget = project?.dspTarget ?? '—';
    final profileLabel = project?.profileStatus.label ?? '—';
    final safetyLabel = project?.safetyStatus.label ?? '—';
    // isConnected reflects PASS_HANDSHAKE: _syncConnectionToStore in hardware_tab
    // only writes HardwareConnection.connected when handshakeComplete is true,
    // which requires DSP1701.100.00.01 firmware identity confirmation.
    final isConnected = project?.connection == HardwareConnection.connected;

    // project.connection is PERSISTED (SharedPreferences-backed) and survives
    // app restarts; activeAdau1701ContextProvider is a fresh, in-memory
    // StateProvider that always starts null on a new launch and is only
    // repopulated once hardware_tab's BLE connect flow runs again this
    // session. Without this check, a restart (or hot-restart) leaves
    // isConnected showing stale "connected" from the prior session while the
    // live context is actually null — deploy_dialog.dart then falls back to
    // a fresh, disconnected USB context and every single operation fails
    // preflight ("ADAU1701 identity handshake is required..."), even though
    // the button looked enabled. Requiring a live context here means the
    // button honestly reflects "will this deploy actually reach hardware",
    // not just the last-known persisted connection flag.
    final hasLiveContext = ref.watch(activeAdau1701ContextProvider) != null;

    // Hardware connection state UX fix: the top status bar previously showed
    // the raw persisted `project.connection.label` ("Connected") whenever
    // isConnected was true, with no live-transport check — after an app
    // restart this showed a stale "DEVICE Connected" even though
    // activeAdau1701ContextProvider was null (no real transport open) and
    // every deploy write would fail preflight. isLiveConnected mirrors the
    // same live-vs-persisted gate canDeploy already uses below, so the
    // status bar and the Deploy button never disagree about whether hardware
    // is actually reachable. "Transport Connected" (not "Device Connected")
    // is also deliberately not the same claim as PASS_ACK/DSP-verified
    // wording elsewhere (see deploy_dialog.dart) — this label only means the
    // transport link + identity handshake are live right now.
    final isLiveConnected = isConnected && hasLiveContext;
    final transportStatusLabel =
        isLiveConnected ? 'Transport Connected' : 'Disconnected';

    final canDeploy = project != null &&
        project.dspTarget == 'ADAU1701' &&
        isConnected &&
        hasLiveContext &&
        project.acousticState.driverChannels.isNotEmpty;

    // Single release-flow progress model — combines existing state
    // (frdReadiness, the live Guided AI state, the shared hardware-write
    // result, and how many After channels have been accepted so far) rather
    // than tracking a duplicate "what stage am I in" flag anywhere.
    final guidedAiState = ref.watch(guidedAiProvider);
    final lastHardwareWrite = ref.watch(lastHardwareWriteResultProvider);
    ref.watch(liveMeasurementControllerProvider(projectId));
    final afterAcceptedCount = ref
        .read(liveMeasurementControllerProvider(projectId).notifier)
        .afterByChannel
        .length;
    final progress = project == null
        ? null
        : ReleaseProgress.compute(
            project: project,
            guidedAiState: guidedAiState,
            lastHardwareWrite: lastHardwareWrite,
            afterAcceptedCount: afterAcceptedCount,
          );

    return Container(
      decoration: const BoxDecoration(
        color: kProPanel,
        border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _PrimaryContextRow(
          name: name,
          profileStatus: project?.profileStatus,
          profileColor: _profileColor(project?.profileStatus),
          nextStep: _nextStepFor(project?.profileStatus),
          canDeploy: canDeploy,
          onDeploy: () => showDeployDialog(
            context: context,
            projectId: projectId,
            channels: project!.acousticState.driverChannels,
            tuning: project.tuningState,
            previousAppliedGains: project.deployState.appliedGainsByChannel,
            previousAppliedXo: project.deployState.appliedXoByChannel,
          ),
        ),
        const Divider(height: 0.5, thickness: 0.5, color: kProBorder),
        SizedBox(
          height: 30,
          child: Row(children: [
            // Scrollable left section with project metadata
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  const SizedBox(width: 16),
                  _StatusItem(
                    label: 'TRANSPORT',
                    value: transportStatusLabel,
                    valueColor:
                        isLiveConnected ? kProGreen : const Color(0xFF6B7280),
                  ),
                  const _Div(),
                  _StatusItem(label: 'SAMPLE RATE', value: sampleRate),
                  const _Div(),
                  _StatusItem(
                      label: 'DSP TARGET', value: dspTarget, maxWidth: 100),
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
                  if (progress != null) ...[
                    const _Div(),
                    _StatusItem(
                      label: 'RELEASE',
                      value: progress.label(),
                      valueColor: _releaseStageColor(progress.stage),
                      maxWidth: 130,
                    ),
                  ],
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

  Color _releaseStageColor(ReleaseStage s) => switch (s) {
        ReleaseStage.noProject => const Color(0xFF6B7280),
        ReleaseStage.measuring => kProAmber,
        ReleaseStage.frdReady => kProAccent,
        ReleaseStage.awaitingApproval => kProAmber,
        ReleaseStage.deployReady => kProAccent,
        ReleaseStage.applied => kProGreen,
        ReleaseStage.afterInProgress => kProAmber,
        ReleaseStage.closedLoopComplete => kProGreen,
      };

  String _nextStepFor(ProfileStatus? s) => switch (s) {
        ProfileStatus.draft => 'Take your first measurements',
        ProfileStatus.measured => 'Start tuning your profile',
        ProfileStatus.tuned => 'Verify your tuning is safe',
        ProfileStatus.verified => 'Ready to deploy — see Deploy →',
        ProfileStatus.deployed => 'Review or refine anytime',
        null => '—',
      };
}

class _PrimaryContextRow extends StatelessWidget {
  final String name;
  final ProfileStatus? profileStatus;
  final Color profileColor;
  final String nextStep;
  final bool canDeploy;
  final VoidCallback onDeploy;

  const _PrimaryContextRow({
    required this.name,
    required this.profileStatus,
    required this.profileColor,
    required this.nextStep,
    required this.canDeploy,
    required this.onDeploy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Flexible(
          child: Text(
            name,
            style: proTitle(size: 12, color: Colors.white),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 10),
        const _Div(),
        const SizedBox(width: 10),
        Text(
          profileStatus?.label ?? '—',
          style: TextStyle(
              fontSize: 10, color: profileColor, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 10),
        const _Div(),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'Next: $nextStep',
            style: proSubtitle(size: 10, color: const Color(0xFF9CA3AF)),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const Spacer(),
        _DeployButton(enabled: canDeploy, onTap: onDeploy),
      ]),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final double? maxWidth;
  const _StatusItem(
      {required this.label,
      required this.value,
      this.valueColor,
      this.maxWidth});

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
              color: enabled ? kProAccent.withValues(alpha: 0.7) : kProBorder,
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
