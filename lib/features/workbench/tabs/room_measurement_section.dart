// Phase 2 — Stereo Room Measurement UI: 2-step Left/Right whole-system
// capture. Same Capture/Retry/Accept mechanics as LiveMeasurementSection
// (Factory), but there is no per-driver isolation step here — both drivers
// on the active side play together through the existing crossover, and the
// opposite speaker is silenced by the test signal itself (no DSP mute).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/deploy/pro_hardware_context_provider.dart';
import '../../../core/pro_project.dart';
import '../../../core/room_measurement_data.dart';
import '../../../core/workbench_tab_provider.dart';
import '../../../shared/pro_widgets.dart';
import 'live_measurement_controller.dart' show TransportKind;
import 'room_auto_peq_controller.dart';
import 'room_measurement_controller.dart';

class RoomMeasurementSection extends ConsumerWidget {
  final ProProject project;
  const RoomMeasurementSection({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl =
        ref.read(roomMeasurementControllerProvider(project.id).notifier);
    final state = ref.watch(roomMeasurementControllerProvider(project.id));
    // Watched here (not just read inside the controller) so this section
    // rebuilds when Room Auto PEQ approves or Deploy actually writes
    // hardware — afterModeAvailable/afterModeBlockedReason read them via
    // ref.read() internally, which is correct for actions but does not by
    // itself trigger a rebuild for display. Mirrors
    // LiveMeasurementSection's identical watch of the same two signals for
    // the Factory path.
    ref.watch(roomAutoPeqControllerProvider(project.id));
    ref.watch(lastHardwareWriteResultProvider);
    final afterAvailable = ctrl.afterModeAvailable;
    final afterBlockedReason = ctrl.afterModeBlockedReason;
    final reentryBlockedReason = ctrl.afterReentryBlockedReason;

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
          afterBlockedReason: afterBlockedReason,
          reentryBlockedReason: reentryBlockedReason,
        ),
        const SizedBox(height: 10),
        _ProgressRow(state: state, ctrl: ctrl),
        const SizedBox(height: 8),
        Text(
          '우퍼와 트위터가 함께 재생됩니다.',
          style: proSubtitle(size: 11),
        ),
        Text(
          '반대편 스피커는 테스트 신호에서 자동 제외됩니다.',
          style: proSubtitle(size: 11),
        ),
        const SizedBox(height: 12),
        _TransportRow(transportKind: ctrl.transportKind),
        const Divider(height: 24, color: kProBorder),
        _SideCaptureCard(state: state, ctrl: ctrl),
        if (state.mode == RoomMeasurementPhase.after &&
            state.closedLoopResult != null) ...[
          const SizedBox(height: 10),
          _ClosedLoopBanner(result: state.closedLoopResult!),
        ],
        const SizedBox(height: 12),
        _NavigationRow(ctrl: ctrl, mode: state.mode),
      ]),
    );
  }
}

// ── Header: project + Before/After toggle ──────────────────────────────────────

class _Header extends StatelessWidget {
  final ProProject project;
  final RoomMeasurementState state;
  final RoomMeasurementController ctrl;
  final bool afterAvailable;
  final String? afterBlockedReason;
  final String? reentryBlockedReason;
  const _Header({
    required this.project,
    required this.state,
    required this.ctrl,
    required this.afterAvailable,
    required this.afterBlockedReason,
    required this.reentryBlockedReason,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Icon(Icons.speaker_group_outlined, size: 16, color: kProAccent),
      const SizedBox(width: 8),
      Text('ROOM MEASUREMENT', style: proTitle(size: 13)),
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
        reentryBlockedReason: reentryBlockedReason,
      ),
    ]);
  }
}

class _ModeToggle extends StatelessWidget {
  final RoomMeasurementPhase mode;
  final RoomMeasurementController ctrl;
  final bool afterAvailable;
  final String? afterBlockedReason;
  final String? reentryBlockedReason;
  const _ModeToggle({
    required this.mode,
    required this.ctrl,
    required this.afterAvailable,
    required this.afterBlockedReason,
    required this.reentryBlockedReason,
  });

  @override
  Widget build(BuildContext context) {
    // A completed, already-evaluated cycle takes priority: re-entry via the
    // plain toggle is refused (setMode() itself also refuses it — this is
    // just the matching UI affordance), and "After 다시 측정" is the only
    // way forward, still subject to the same hardware gate.
    final afterEnabled = afterAvailable && reentryBlockedReason == null;
    final afterHint =
        reentryBlockedReason ?? (afterAvailable ? null : afterBlockedReason);
    return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _ModeChip(
                label: 'Before',
                selected: mode == RoomMeasurementPhase.before,
                onTap: () => ctrl.setMode(RoomMeasurementPhase.before),
              ),
              _ModeChip(
                label: 'After',
                selected: mode == RoomMeasurementPhase.after,
                onTap: afterEnabled
                    ? () => ctrl.setMode(RoomMeasurementPhase.after)
                    : null,
                disabledHint: afterEnabled ? null : afterHint,
              ),
            ]),
          ),
          if (reentryBlockedReason != null)
            Tooltip(
              message: afterAvailable ? '' : (afterBlockedReason ?? ''),
              child: OutlinedButton(
                onPressed: afterAvailable ? ctrl.startNewAfterSession : null,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kProBorder),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child:
                    const Text('After 다시 측정', style: TextStyle(fontSize: 10)),
              ),
            ),
        ]);
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

// ── Progress row: 0/2, 1/2, 2/2 ─────────────────────────────────────────────────

class _ProgressRow extends StatelessWidget {
  final RoomMeasurementState state;
  final RoomMeasurementController ctrl;
  const _ProgressRow({required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final snapshot = ctrl.currentSnapshot;
    final saved = snapshot.readyCount;
    const total = 2;
    final complete = saved >= total;
    final label =
        state.mode == RoomMeasurementPhase.before ? 'Before' : 'After';
    return Row(children: [
      Icon(
        complete ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        size: 14,
        color: complete ? kProGreen : kProAmber,
      ),
      const SizedBox(width: 8),
      Text(
        '$label 진행률: $saved/$total',
        style: TextStyle(
            fontSize: 12, color: complete ? kProGreen : Colors.white70),
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

// ── Side capture card ────────────────────────────────────────────────────────

class _SideCaptureCard extends StatelessWidget {
  final RoomMeasurementState state;
  final RoomMeasurementController ctrl;
  const _SideCaptureCard({required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final side = ctrl.currentSide;

    if (side == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kProPanel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kProBorder),
        ),
        child: const Row(children: [
          Icon(Icons.check_circle_outline, size: 14, color: kProGreen),
          SizedBox(width: 8),
          Expanded(
            child: Text('Left/Right 스피커 측정을 모두 완료했습니다.',
                style: TextStyle(fontSize: 12, color: kProGreen)),
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
          Text('현재 측정: ${side.label} 스피커 전체',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 10),
        _CaptureControls(state: state, ctrl: ctrl),
        if (state.error != null) ...[
          const SizedBox(height: 8),
          Text(state.error!,
              style: const TextStyle(color: kProRed, fontSize: 11)),
        ],
        if (state.phase == RoomMeasurementPhaseUi.captured &&
            state.capturedResponse != null) ...[
          const SizedBox(height: 10),
          _FrdPreview(response: state.capturedResponse!),
        ],
      ]),
    );
  }
}

class _CaptureControls extends StatelessWidget {
  final RoomMeasurementState state;
  final RoomMeasurementController ctrl;
  const _CaptureControls({required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case RoomMeasurementPhaseUi.idle:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: ctrl.markReady,
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kProBorder)),
            child: const Text('준비 완료', style: TextStyle(fontSize: 12)),
          ),
        );
      case RoomMeasurementPhaseUi.ready:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: ctrl.capture,
            icon: const Icon(Icons.fiber_manual_record, size: 14),
            label: const Text('Capture'),
            style: FilledButton.styleFrom(backgroundColor: kProAccent),
          ),
        );
      case RoomMeasurementPhaseUi.capturing:
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
      case RoomMeasurementPhaseUi.captured:
        return Column(children: [
          Row(children: [
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
          ]),
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

// ── Closed loop banner ───────────────────────────────────────────────────────

class _ClosedLoopBanner extends StatelessWidget {
  final dynamic result;
  const _ClosedLoopBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kProGreen.withValues(alpha: 0.08),
        border: Border.all(color: kProGreen.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_outline, size: 14, color: kProGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Left/Right After 측정 완료 — Closed Loop 판정: ${result.decision.name}',
            style: const TextStyle(color: kProGreen, fontSize: 11),
          ),
        ),
      ]),
    );
  }
}

// ── Navigation ────────────────────────────────────────────────────────────────

class _NavigationRow extends ConsumerWidget {
  final RoomMeasurementController ctrl;
  final RoomMeasurementPhase mode;
  const _NavigationRow({required this.ctrl, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beforeReady = ctrl.currentSnapshot.isComplete ||
        (mode == RoomMeasurementPhase.before && ctrl.isSequenceComplete);
    return Row(children: [
      if (mode == RoomMeasurementPhase.before)
        OutlinedButton.icon(
          onPressed: beforeReady
              ? () => ref.read(workbenchTabProvider.notifier).go(kTabAutoPeq)
              : null,
          icon: const Icon(Icons.auto_fix_high, size: 14),
          label:
              const Text('Room Auto PEQ로 이동', style: TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kProBorder)),
        ),
    ]);
  }
}
