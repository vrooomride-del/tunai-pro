// ── TUNAI PRO Phase 3-D3A-1B — gate-driven Capture control ───────────────────
//
// Single shared widget for the "ready phase" Capture button/blocker/warning
// display, used identically by Factory (LiveMeasurementSection) and Room
// (RoomMeasurementSection) so the two can never drift into presenting a
// different verdict for the same gate result (Phase 3-D3A-1B §2/§3/§8).
//
// This widget NEVER recomputes setup validity, profile/device identity,
// calibration validity, or warning status — it only renders whatever
// [MeasurementCaptureGateResult] `evaluateGate` returns and dispatches to
// the controller's own `acknowledgeWarnings`/`capture`. The gate itself
// already re-runs on every `capture()` call as final authority; this widget
// caches the LAST evaluation for display only (an async preflight cannot run
// on every build), and re-evaluates after any action that could change the
// verdict (remediation flow closed, warning acknowledged + captured).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/measurement/measurement_capture_gate.dart';
import '../../../core/measurement/measurement_capture_gate_types.dart';
import '../../../core/measurement/measurement_capture_presentation.dart';
import '../../../shared/pro_widgets.dart';
import 'measurement_capture_remediation.dart';

class MeasurementCaptureReadyControl extends StatefulWidget {
  final String projectId;
  final Future<MeasurementCaptureGateResult> Function() evaluateGate;
  final void Function(MeasurementCaptureGateResult gate) acknowledgeWarnings;
  final VoidCallback capture;

  const MeasurementCaptureReadyControl({
    super.key,
    required this.projectId,
    required this.evaluateGate,
    required this.acknowledgeWarnings,
    required this.capture,
  });

  @override
  State<MeasurementCaptureReadyControl> createState() =>
      _MeasurementCaptureReadyControlState();
}

class _MeasurementCaptureReadyControlState
    extends State<MeasurementCaptureReadyControl> {
  MeasurementCaptureGateResult? _gate;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant MeasurementCaptureReadyControl oldWidget) {
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

  Future<void> _handleRemediation(
      MeasurementCaptureRemediation remediation) async {
    await runMeasurementCaptureRemediation(
      context,
      remediation: remediation,
      projectId: widget.projectId,
    );
    if (mounted) await _refresh();
  }

  Future<void> _handleWarningConfirm(MeasurementCaptureGateResult gate) async {
    final confirmed =
        await showMeasurementWarningAcknowledgementDialog(context, gate: gate);
    if (!confirmed) return;
    widget.acknowledgeWarnings(gate);
    widget.capture();
    if (mounted) unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final gate = _gate;

    // Not-yet-evaluated: never presumed Ready — a safely disabled button.
    if (gate == null) {
      return const _DisabledCaptureButton(reason: '측정 준비 상태를 확인하는 중입니다.');
    }

    final systemDefaultNote = gate.inputAvailability ==
            MeasurementRuntimeInputAvailability.systemDefaultUnverified
        ? const _SystemDefaultNote()
        : null;

    if (gate.blockers.isNotEmpty) {
      final blocker = gate.primaryBlocker!;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (systemDefaultNote != null) ...[
          systemDefaultNote,
          const SizedBox(height: 8)
        ],
        const _DisabledCaptureButton(),
        const SizedBox(height: 8),
        Text(
          measurementCaptureBlockerText(blocker.code),
          style: const TextStyle(color: kProRed, fontSize: 11),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: () => _handleRemediation(blocker.remediation),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kProBorder)),
          child: Text(
            measurementCaptureRemediationLabel(blocker.remediation),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ]);
    }

    if (gate.requiresExplicitWarningAcknowledgement) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (systemDefaultNote != null) ...[
          systemDefaultNote,
          const SizedBox(height: 8)
        ],
        for (final warning in gate.warnings) ...[
          Text(
            measurementCaptureWarningText(warning.code),
            style: const TextStyle(color: kProAmber, fontSize: 11),
          ),
          const SizedBox(height: 6),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _handleWarningConfirm(gate),
            icon: const Icon(Icons.warning_amber_rounded, size: 14),
            label: const Text(kMeasurementCaptureWarningConfirmLabel),
            style: FilledButton.styleFrom(backgroundColor: kProAmber),
          ),
        ),
      ]);
    }

    // canCapture == true: normal Capture CTA.
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (systemDefaultNote != null) ...[
        systemDefaultNote,
        const SizedBox(height: 8)
      ],
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.capture,
          icon: const Icon(Icons.fiber_manual_record, size: 14),
          label: const Text('Capture'),
          style: FilledButton.styleFrom(backgroundColor: kProAccent),
        ),
      ),
    ]);
  }
}

class _DisabledCaptureButton extends StatelessWidget {
  final String? reason;
  const _DisabledCaptureButton({this.reason});

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

/// Phase 3-D3A-1B §7 — never labels a system-default selection as verified,
/// connected, available, or confirmed; the real device is only known once
/// the recorder actually starts.
class _SystemDefaultNote extends StatelessWidget {
  const _SystemDefaultNote();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        kMeasurementCaptureSystemDefaultLabel,
        style: TextStyle(color: Colors.white70, fontSize: 11),
      ),
      Text(
        kMeasurementCaptureSystemDefaultSubtext,
        style: proSubtitle(size: 10),
      ),
    ]);
  }
}
