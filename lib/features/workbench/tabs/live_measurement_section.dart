// Live Measurement — the reachable UI for LiveMeasurementController.
//
// Deliberately not a new "expert" screen: one card, sequential channel
// capture, manual isolation instructions instead of any DSP-driven mute.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/deploy/pro_hardware_context_provider.dart';
import '../../../core/orchestrator/pro_guided_ai_controller.dart';
import '../../../core/pro_project.dart';
import '../../../core/workbench_tab_provider.dart';
import '../../../shared/pro_widgets.dart';
import 'live_measurement_controller.dart';

class LiveMeasurementSection extends ConsumerWidget {
  final ProProject project;
  const LiveMeasurementSection({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl =
        ref.read(liveMeasurementControllerProvider(project.id).notifier);
    final state = ref.watch(liveMeasurementControllerProvider(project.id));
    final readiness = ProGuidedAiController.frdReadiness(project);
    // Watched here (not just read inside the controller) purely so this
    // section rebuilds when Apply completes or Deploy actually writes
    // hardware — afterModeAvailable/afterModeBlockedReason read them via
    // ref.read() internally, which is correct for actions but does not by
    // itself trigger a rebuild for display.
    ref.watch(guidedAiProvider);
    ref.watch(lastHardwareWriteResultProvider);
    final afterAvailable = ctrl.afterModeAvailable;
    final afterBlockedReason = ctrl.afterModeBlockedReason;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Header(
            project: project,
            state: state,
            ctrl: ctrl,
            afterAvailable: afterAvailable,
            afterBlockedReason: afterBlockedReason),
        const SizedBox(height: 10),
        _ProgressRow(
          state: state,
          readiness: readiness,
          afterByChannel: ctrl.afterByChannel,
          totalChannels: ctrl.channels.length,
        ),
        const SizedBox(height: 12),
        _TransportRow(transportKind: ctrl.transportKind),
        const Divider(height: 24, color: kProBorder),
        _ChannelCaptureCard(project: project, state: state, ctrl: ctrl),
        const SizedBox(height: 10),
        _MissingChannelsRow(
          mode: state.mode,
          readiness: readiness,
          missingAfterIds: ctrl.missingAfterChannelIds,
          channels: ctrl.channels,
        ),
        if (state.mode == LiveMeasurementMode.after &&
            state.lastCompletedCycle != null) ...[
          const SizedBox(height: 10),
          _AfterCompleteBanner(cycle: state.lastCompletedCycle!),
        ],
        if (state.submitBlockedReason != null) ...[
          const SizedBox(height: 8),
          Text(state.submitBlockedReason!,
              style: const TextStyle(color: kProRed, fontSize: 11)),
        ],
        const SizedBox(height: 12),
        _NavigationRow(readiness: readiness, mode: state.mode),
      ]),
    );
  }
}

// ── Header: project + mode toggle ──────────────────────────────────────────────

class _Header extends StatelessWidget {
  final ProProject project;
  final LiveMeasurementState state;
  final LiveMeasurementController ctrl;
  final bool afterAvailable;
  final String? afterBlockedReason;
  const _Header({
    required this.project,
    required this.state,
    required this.ctrl,
    required this.afterAvailable,
    required this.afterBlockedReason,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Icon(Icons.graphic_eq, size: 16, color: kProAccent),
      const SizedBox(width: 8),
      Text('LIVE MEASUREMENT', style: proTitle(size: 13)),
      const SizedBox(width: 10),
      Expanded(
        child: Text(project.name,
            style: proSubtitle(size: 11), overflow: TextOverflow.ellipsis),
      ),
      _ModeToggle(
        mode: state.mode,
        ctrl: ctrl,
        afterAvailable: afterAvailable,
        afterBlockedReason: afterBlockedReason,
      ),
    ]);
  }
}

class _ModeToggle extends StatelessWidget {
  final LiveMeasurementMode mode;
  final LiveMeasurementController ctrl;
  final bool afterAvailable;
  final String? afterBlockedReason;
  const _ModeToggle({
    required this.mode,
    required this.ctrl,
    required this.afterAvailable,
    required this.afterBlockedReason,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _ModeChip(
          label: 'Before',
          selected: mode == LiveMeasurementMode.before,
          onTap: () => ctrl.setMode(LiveMeasurementMode.before),
        ),
        _ModeChip(
          label: 'After',
          selected: mode == LiveMeasurementMode.after,
          onTap: afterAvailable
              ? () => ctrl.setMode(LiveMeasurementMode.after)
              : null,
          disabledHint: afterAvailable ? null : afterBlockedReason,
        ),
      ]),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? disabledHint;
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: disabledHint ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? kProAccent.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              color: selected
                  ? kProAccent
                  : (enabled ? Colors.white54 : Colors.white24),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Progress row ──────────────────────────────────────────────────────────────

class _ProgressRow extends StatelessWidget {
  final LiveMeasurementState state;
  final FrdReadiness readiness;
  final Map<String, dynamic> afterByChannel;
  final int totalChannels;
  const _ProgressRow({
    required this.state,
    required this.readiness,
    required this.afterByChannel,
    required this.totalChannels,
  });

  @override
  Widget build(BuildContext context) {
    final isBefore = state.mode == LiveMeasurementMode.before;
    final saved = isBefore ? readiness.readyCount : afterByChannel.length;
    final total = readiness.requiredChannelIds.length;
    final complete = saved >= total && total > 0;
    return Row(children: [
      Icon(
        complete ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        size: 14,
        color: complete ? kProGreen : kProAmber,
      ),
      const SizedBox(width: 8),
      Text(
        '${isBefore ? 'Before' : 'After'} 채널 진행률: $saved/$total 저장됨',
        style: TextStyle(
          fontSize: 12,
          color: complete ? kProGreen : Colors.white70,
        ),
      ),
    ]);
  }
}

// ── Transport row ─────────────────────────────────────────────────────────────

class _TransportRow extends StatelessWidget {
  final TransportKind transportKind;
  const _TransportRow({required this.transportKind});

  @override
  Widget build(BuildContext context) {
    final (label, color, warmupNote) = switch (transportKind) {
      TransportKind.ble => ('BLE', kProAccent, 'BLE warm-up 2초 자동 적용'),
      TransportKind.usb => ('USB', kProGreen, 'BLE warm-up 불필요'),
      TransportKind.local => ('Local (미연결)', Colors.white38, 'BLE warm-up 불필요'),
    };
    return Row(children: [
      Icon(Icons.cable, size: 13, color: color),
      const SizedBox(width: 6),
      Text('연결: $label', style: TextStyle(fontSize: 11, color: color)),
      const SizedBox(width: 12),
      Text(warmupNote, style: proSubtitle(size: 10)),
    ]);
  }
}

// ── Channel capture card ───────────────────────────────────────────────────────

class _ChannelCaptureCard extends ConsumerWidget {
  final ProProject project;
  final LiveMeasurementState state;
  final LiveMeasurementController ctrl;
  const _ChannelCaptureCard({
    required this.project,
    required this.state,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channel = ctrl.currentChannel;

    if (channel == null) {
      final done = ctrl.channels.isNotEmpty;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kProPanel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kProBorder),
        ),
        child: Row(children: [
          Icon(
            done ? Icons.check_circle_outline : Icons.info_outline,
            size: 14,
            color: done ? kProGreen : Colors.white38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              done ? '이 라운드의 모든 채널을 측정했습니다.' : '이 프로젝트에는 측정할 채널이 없습니다.',
              style: TextStyle(
                  fontSize: 12, color: done ? kProGreen : Colors.white38),
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kProPanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kProBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.speaker, size: 14, color: kProAccent),
          const SizedBox(width: 8),
          Text('현재 측정 채널: ${channel.shortLabel}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 8),
        Text(
          'Hardware 탭에서 이 채널만 출력되도록 설정하세요.',
          style: proSubtitle(size: 11),
        ),
        const SizedBox(height: 10),
        _CaptureControls(state: state, ctrl: ctrl),
        if (state.error != null) ...[
          const SizedBox(height: 8),
          Text(state.error!,
              style: const TextStyle(color: kProRed, fontSize: 11)),
        ],
        if (state.phase == LiveMeasurementPhase.captured &&
            state.capturedResponse != null) ...[
          const SizedBox(height: 10),
          _FrdPreview(response: state.capturedResponse!),
        ],
      ]),
    );
  }
}

class _CaptureControls extends StatelessWidget {
  final LiveMeasurementState state;
  final LiveMeasurementController ctrl;
  const _CaptureControls({required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case LiveMeasurementPhase.idle:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: ctrl.markReady,
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kProBorder)),
            child: const Text('준비 완료', style: TextStyle(fontSize: 12)),
          ),
        );
      case LiveMeasurementPhase.ready:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: ctrl.capture,
            icon: const Icon(Icons.fiber_manual_record, size: 14),
            label: const Text('Capture'),
            style: FilledButton.styleFrom(backgroundColor: kProAccent),
          ),
        );
      case LiveMeasurementPhase.capturing:
        return const Row(children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: kProAccent),
          ),
          SizedBox(width: 10),
          Text('측정 중...',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]);
      case LiveMeasurementPhase.captured:
        return Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: ctrl.retry,
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kProBorder)),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: ctrl.accept,
              style: FilledButton.styleFrom(backgroundColor: kProGreen),
              child: const Text('Accept', style: TextStyle(fontSize: 12)),
            ),
          ),
        ]);
    }
  }
}

class _FrdPreview extends StatelessWidget {
  final List<Map<String, double>> response;
  const _FrdPreview({required this.response});

  @override
  Widget build(BuildContext context) {
    if (response.isEmpty) return const SizedBox.shrink();
    final freqs = response.map((m) => m['frequency']).whereType<double>();
    final minF = freqs.isEmpty ? 0.0 : freqs.reduce((a, b) => a < b ? a : b);
    final maxF = freqs.isEmpty ? 0.0 : freqs.reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'FRD Preview — ${response.length} points · '
        '${minF.toStringAsFixed(0)}–${maxF.toStringAsFixed(0)} Hz',
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
    );
  }
}

// ── Missing channels ────────────────────────────────────────────────────────────

class _MissingChannelsRow extends StatelessWidget {
  final LiveMeasurementMode mode;
  final FrdReadiness readiness;
  final List<String> missingAfterIds;
  final List<dynamic> channels;
  const _MissingChannelsRow({
    required this.mode,
    required this.readiness,
    required this.missingAfterIds,
    required this.channels,
  });

  @override
  Widget build(BuildContext context) {
    final labels = mode == LiveMeasurementMode.before
        ? readiness.missingChannels.map((c) => c.label).toList()
        : missingAfterIds;
    if (labels.isEmpty) return const SizedBox.shrink();
    return Text(
      '누락 채널: ${labels.join(', ')}',
      style: const TextStyle(color: Colors.white38, fontSize: 11),
    );
  }
}

// ── After-complete banner ────────────────────────────────────────────────────────

class _AfterCompleteBanner extends StatelessWidget {
  final dynamic cycle;
  const _AfterCompleteBanner({required this.cycle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kProGreen.withValues(alpha: 0.08),
        border: Border.all(color: kProGreen.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(children: [
        Icon(Icons.check_circle_outline, size: 14, color: kProGreen),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'After 4채널 측정 완료 — Closed Loop 판정이 준비되었습니다.',
            style: TextStyle(color: kProGreen, fontSize: 11),
          ),
        ),
      ]),
    );
  }
}

// ── Navigation ────────────────────────────────────────────────────────────────

class _NavigationRow extends ConsumerWidget {
  final FrdReadiness readiness;
  final LiveMeasurementMode mode;
  const _NavigationRow({required this.readiness, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(children: [
      if (mode == LiveMeasurementMode.before)
        OutlinedButton.icon(
          onPressed: readiness.isFullyReady
              ? () => ref.read(workbenchTabProvider.notifier).go(kTabAutoPeq)
              : null,
          icon: const Icon(Icons.auto_fix_high, size: 14),
          label: const Text('Auto PEQ로 이동', style: TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kProBorder)),
        )
      else
        OutlinedButton.icon(
          onPressed: () =>
              ref.read(workbenchTabProvider.notifier).go(kTabGuidedAi),
          icon: const Icon(Icons.loop, size: 14),
          label: const Text('Closed Loop로 이동', style: TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kProBorder)),
        ),
    ]);
  }
}
