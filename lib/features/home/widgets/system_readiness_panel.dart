// ── TUNAI PRO Phase 3-E §9/§10 — D. System Readiness ───────────────────────
//
// Answers "what is ready?" — four rows, no more: microphone, input, setup,
// hardware. Not a number dump and not a second Continue card.
//
// The hardware row is the load-bearing one: `hardwareConnected == null`
// means NOBODY HAS CHECKED, which is neither a success nor a failure. It is
// rendered neutrally and must never read as Connected/Verified/Ready. When
// a project-identity-aware live connection provider exists, only this row
// changes.

import 'package:flutter/material.dart';

import '../../../core/hardware/hardware_connection_readiness.dart';
import '../../../core/workflow/measurement_workflow_presentation.dart';
import '../../../core/workflow/measurement_workflow_readiness.dart';
import '../../../shared/design/pro_tokens.dart';
import 'home_primitives.dart';

/// How a readiness row reads. `unchecked` is deliberately distinct from
/// `attention` so "not checked yet" never renders as a failure.
enum _RowTone { ok, attention, unchecked }

class SystemReadinessPanel extends StatelessWidget {
  final MeasurementWorkflowReadiness readiness;
  final VoidCallback onOpenSetup;
  final VoidCallback onOpenHardware;
  final VoidCallback onOpenMicrophone;

  const SystemReadinessPanel({
    super.key,
    required this.readiness,
    required this.onOpenSetup,
    required this.onOpenHardware,
    required this.onOpenMicrophone,
  });

  /// True when this row is what the workflow is currently waiting on — it
  /// gets a subtle highlight and a compact action, so the user does not have
  /// to work out which row the Continue card is talking about (§7).
  bool _isCurrent(Set<MeasurementWorkflowAction> actions) =>
      actions.contains(readiness.nextRecommendedAction);

  @override
  Widget build(BuildContext context) {
    final r = readiness;
    final hardware = measurementWorkflowHardwareText(r.hardwareConnectionState);

    return HomePanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const HomeSectionLabel('준비 상태'),
        const SizedBox(height: ProSpacing.lg),
        _Row(
          icon: Icons.mic_none_outlined,
          label: '측정 마이크',
          value: r.microphoneLabel ?? '선택되지 않음',
          detail: measurementWorkflowCalibrationText(r.calibrationStatus),
          tone: switch (r.calibrationStatus) {
            MeasurementWorkflowCalibrationState.calibrated => _RowTone.ok,
            MeasurementWorkflowCalibrationState.none => _RowTone.unchecked,
            _ => _RowTone.attention,
          },
          highlighted: _isCurrent({
            MeasurementWorkflowAction.selectMicrophone,
            MeasurementWorkflowAction.fixCalibration,
          }),
          actionLabel: '마이크 설정',
          onTap: onOpenMicrophone,
        ),
        _Row(
          icon: Icons.usb_outlined,
          label: '입력',
          value: r.inputLabel ?? '선택되지 않음',
          detail: measurementWorkflowInputStatusText(r),
          highlighted:
              _isCurrent({MeasurementWorkflowAction.selectInputDevice}),
          actionLabel: '입력 장치 선택',
          onTap: onOpenSetup,
          tone: switch (r.runtimeAvailability) {
            MeasurementWorkflowInputAvailability.lastKnownValid => _RowTone.ok,
            // System default is a valid choice, but it is NOT verified — a
            // neutral tone, never a green one.
            MeasurementWorkflowInputAvailability.systemDefaultUnverified =>
              _RowTone.unchecked,
            MeasurementWorkflowInputAvailability.unknown => _RowTone.unchecked,
          },
        ),
        _Row(
          icon: Icons.checklist_outlined,
          // Named for the CHECK itself, not the stage — the Journey already
          // owns the stage name "측정 준비" (§16: no repeated information).
          label: '측정 준비 확인',
          value: measurementWorkflowSetupStateText(r.setupState),
          detail: r.setupState == MeasurementWorkflowSetupState.ready
              ? null
              : '측정을 시작하기 전에 확인이 필요합니다.',
          tone: switch (r.setupState) {
            MeasurementWorkflowSetupState.ready => _RowTone.ok,
            MeasurementWorkflowSetupState.notChecked => _RowTone.unchecked,
            _ => _RowTone.attention,
          },
          highlighted:
              _isCurrent({MeasurementWorkflowAction.checkMeasurementSetup}),
          actionLabel: '측정 준비 확인',
          onTap: onOpenSetup,
        ),
        _Row(
          icon: Icons.memory_outlined,
          label: '하드웨어',
          value: hardware.title,
          detail: hardware.detail,
          // Only a genuinely deploy-ready session is green. "Not checked"
          // stays neutral grey — it is not a failure.
          tone: switch (r.hardwareConnectionState) {
            HardwareConnectionState.readyForDeploy => _RowTone.ok,
            HardwareConnectionState.unknown => _RowTone.unchecked,
            HardwareConnectionState.connecting ||
            HardwareConnectionState.connected =>
              _RowTone.unchecked,
            HardwareConnectionState.disconnected ||
            HardwareConnectionState.incompatible ||
            HardwareConnectionState.error =>
              _RowTone.attention,
          },
          actionLabel: '하드웨어 확인',
          onTap: onOpenHardware,
          last: true,
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final _RowTone tone;
  final VoidCallback? onTap;
  final bool last;

  /// This row is the current blocker.
  final bool highlighted;

  /// Compact secondary action. Deliberately never a filled/primary button —
  /// Continue Tuning owns the only primary CTA on Home (§7).
  final String? actionLabel;

  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.detail,
    this.onTap,
    this.last = false,
    this.highlighted = false,
    this.actionLabel,
  });

  Color get _toneColor => switch (tone) {
        _RowTone.ok => ProColors.green,
        _RowTone.attention => ProColors.amber,
        // Deliberately a neutral grey: unchecked is not a problem.
        _RowTone.unchecked => ProColors.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    final body = Container(
      margin: EdgeInsets.only(bottom: last ? 0 : ProSpacing.xs),
      padding: EdgeInsets.fromLTRB(highlighted ? ProSpacing.sm : 0,
          ProSpacing.sm, highlighted ? ProSpacing.sm : 0, ProSpacing.sm),
      decoration: highlighted
          ? BoxDecoration(
              color: ProColors.accent.withValues(alpha: 0.06),
              border:
                  Border.all(color: ProColors.accent.withValues(alpha: 0.25)),
              borderRadius: ProRadius.smallAll,
            )
          : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: ProColors.textTertiary),
        ),
        const SizedBox(width: ProSpacing.md),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              label,
              style: const TextStyle(
                  color: ProColors.textTertiary, fontSize: ProTypeScale.label),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                  color: ProColors.textPrimary,
                  fontSize: ProTypeScale.secondary),
              overflow: TextOverflow.ellipsis,
            ),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Text(
                detail!,
                style:
                    TextStyle(color: _toneColor, fontSize: ProTypeScale.label),
              ),
            ],
            if (highlighted && actionLabel != null && onTap != null) ...[
              const SizedBox(height: ProSpacing.sm),
              HomeSecondaryButton(label: actionLabel!, onTap: onTap!),
            ],
          ]),
        ),
        if (onTap != null && !highlighted)
          const Padding(
            padding: EdgeInsets.only(left: ProSpacing.sm, top: 8),
            child: Icon(Icons.chevron_right,
                size: 16, color: ProColors.textTertiary),
          ),
      ]),
    );

    if (onTap == null || highlighted) return body;
    return Material(
      color: Colors.transparent,
      child:
          InkWell(onTap: onTap, borderRadius: ProRadius.smallAll, child: body),
    );
  }
}
