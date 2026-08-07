// ── TUNAI PRO Phase 3-D3A-3 — Room After dual-gate Capture control ──────────
//
// The After-mode counterpart of MeasurementCaptureReadyControl: renders the
// COMPOSITE RoomAfterCaptureGateResult (hardware AND measurement) instead of
// a bare measurement gate. Ordering (hardware first, then measurement setup,
// then measurement warning, then Capture) falls directly out of
// RoomAfterCaptureGateResult.primaryBlocker — this widget never re-derives
// or re-orders it.
//
// Reuses the existing typed remediation dispatch and warning-acknowledgement
// dialog verbatim for the measurement-side blockers/warnings — only the
// hardware-side "go to Deploy" remediation is new here, and it's just a tab
// navigation, not a new flow.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/measurement/measurement_capture_gate.dart';
import '../../../core/measurement/measurement_capture_presentation.dart';
import '../../../core/orchestrator/room_after_capture_gate.dart';
import '../../../core/orchestrator/room_after_capture_presentation.dart';
import '../../../core/workbench_tab_provider.dart';
import '../../../shared/pro_widgets.dart';
import 'measurement_capture_remediation.dart';

class RoomAfterCaptureReadyControl extends ConsumerStatefulWidget {
  final String projectId;
  final Future<RoomAfterCaptureGateResult> Function() evaluateGate;
  final void Function(MeasurementCaptureGateResult gate) acknowledgeWarnings;
  final VoidCallback capture;

  const RoomAfterCaptureReadyControl({
    super.key,
    required this.projectId,
    required this.evaluateGate,
    required this.acknowledgeWarnings,
    required this.capture,
  });

  @override
  ConsumerState<RoomAfterCaptureReadyControl> createState() =>
      _RoomAfterCaptureReadyControlState();
}

class _RoomAfterCaptureReadyControlState
    extends ConsumerState<RoomAfterCaptureReadyControl> {
  RoomAfterCaptureGateResult? _gate;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant RoomAfterCaptureReadyControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final gate = await widget.evaluateGate();
    if (!mounted) return;
    setState(() => _gate = gate);
  }

  Future<void> _handleRemediation(RoomAfterCaptureGateResult gate) async {
    final remediation = gate.primaryRemediation;
    if (remediation == null) return;
    switch (remediation.kind) {
      case RoomAfterCaptureRemediationKind.deployCorrection:
        ref.read(workbenchTabProvider.notifier).go(kTabDeploy);
      case RoomAfterCaptureRemediationKind.measurement:
        await runMeasurementCaptureRemediation(
          context,
          remediation: remediation.measurementRemediation!,
          projectId: widget.projectId,
        );
      case RoomAfterCaptureRemediationKind.acknowledgeMeasurementWarning:
        await _handleWarningConfirm(gate.measurementGate);
        return;
    }
    if (mounted) await _refresh();
  }

  Future<void> _handleWarningConfirm(
      MeasurementCaptureGateResult measurementGate) async {
    final confirmed = await showMeasurementWarningAcknowledgementDialog(context,
        gate: measurementGate);
    if (!confirmed) return;
    widget.acknowledgeWarnings(measurementGate);
    widget.capture();
    if (mounted) unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final gate = _gate;

    if (gate == null) {
      return const _DisabledAfterCaptureButton(reason: '측정 준비 상태를 확인하는 중입니다.');
    }

    final blocker = gate.primaryBlocker;
    if (blocker != null) {
      // Warning is the only non-hardware, non-measurement-blocker case that
      // still needs the acknowledge-and-measure CTA instead of a plain
      // disabled button + remediation link.
      if (blocker.code ==
          RoomAfterCaptureBlockerCode.measurementSetupWarningNotAcknowledged) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final warning in gate.measurementGate.warnings) ...[
            Text(
              measurementCaptureWarningText(warning.code),
              style: const TextStyle(color: kProAmber, fontSize: 11),
            ),
            const SizedBox(height: 6),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _handleWarningConfirm(gate.measurementGate),
              icon: const Icon(Icons.warning_amber_rounded, size: 14),
              label: const Text(kMeasurementCaptureWarningConfirmLabel),
              style: FilledButton.styleFrom(backgroundColor: kProAmber),
            ),
          ),
        ]);
      }

      final remediation = gate.primaryRemediation;
      final remediationLabel = remediation == null
          ? null
          : switch (remediation.kind) {
              RoomAfterCaptureRemediationKind.deployCorrection =>
                kRoomAfterCaptureDeployRemediationLabel,
              RoomAfterCaptureRemediationKind.measurement =>
                measurementCaptureRemediationLabel(
                    remediation.measurementRemediation!),
              RoomAfterCaptureRemediationKind.acknowledgeMeasurementWarning =>
                kMeasurementCaptureWarningConfirmLabel,
            };
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _DisabledAfterCaptureButton(),
        const SizedBox(height: 8),
        Text(
          roomAfterCaptureBlockerText(gate),
          style: const TextStyle(color: kProRed, fontSize: 11),
        ),
        if (remediationLabel != null) ...[
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: () => _handleRemediation(gate),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kProBorder)),
            child: Text(remediationLabel, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ]);
    }

    // canCapture == true: both hardware and measurement gates passed.
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: widget.capture,
        icon: const Icon(Icons.fiber_manual_record, size: 14),
        label: const Text('Capture'),
        style: FilledButton.styleFrom(backgroundColor: kProAccent),
      ),
    );
  }
}

class _DisabledAfterCaptureButton extends StatelessWidget {
  final String? reason;
  const _DisabledAfterCaptureButton({this.reason});

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.fiber_manual_record, size: 14),
        label: const Text('Capture'),
      ),
    );
    if (reason == null) return button;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      button,
      const SizedBox(height: 6),
      Text(reason!,
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ]);
  }
}
