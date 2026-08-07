// ── TUNAI PRO Phase 3-E §7/§8 — C. Tuning Journey ──────────────────────────
//
// Answers "where am I overall" with the five workflow stages, each in one of
// five states. Compact by default; a stage expands to a short, beginner-level
// detail line on tap.
//
// Every value — the stage state and every detail line — is read off
// MeasurementWorkflowReadiness. Nothing is recomputed here, and no percentage
// is derived: progress is whole stages or nothing.

import 'package:flutter/material.dart';

import '../../../core/workflow/measurement_workflow_presentation.dart';
import '../../../core/workflow/measurement_workflow_readiness.dart';
import '../../../shared/design/pro_tokens.dart';
import 'home_primitives.dart';

class TuningJourney extends StatefulWidget {
  final MeasurementWorkflowReadiness readiness;
  const TuningJourney({super.key, required this.readiness});

  @override
  State<TuningJourney> createState() => _TuningJourneyState();
}

class _TuningJourneyState extends State<TuningJourney> {
  MeasurementWorkflowStage? _expanded;

  @override
  Widget build(BuildContext context) {
    final r = widget.readiness;
    return HomePanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const HomeSectionLabel('튜닝 진행 상황'),
        const SizedBox(height: ProSpacing.lg),
        LayoutBuilder(builder: (context, constraints) {
          // Below ~720 the five stages stop fitting side by side; stacking is
          // the only layout that never truncates a stage name.
          final horizontal = constraints.maxWidth >= 720;
          final rows = [
            for (final s in MeasurementWorkflowStage.values)
              _StageDot(
                stage: s,
                state: r.stage(s),
                expanded: _expanded == s,
                horizontal: horizontal,
                onTap: () =>
                    setState(() => _expanded = _expanded == s ? null : s),
              ),
          ];
          if (!horizontal) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ProSpacing.sm),
                    child: row,
                  ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                Expanded(child: rows[i]),
                if (i != rows.length - 1)
                  Container(
                    width: 16,
                    height: 1,
                    margin: const EdgeInsets.only(top: 9),
                    color: ProColors.border,
                  ),
              ],
            ],
          );
        }),
        if (_expanded != null) ...[
          const SizedBox(height: ProSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(ProSpacing.md),
            decoration: const BoxDecoration(
              color: ProColors.surfaceSunken,
              borderRadius: ProRadius.smallAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _details(r, _expanded!))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      line,
                      style: const TextStyle(
                          color: ProColors.textSecondary,
                          fontSize: ProTypeScale.secondary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  /// §8 — short, beginner-level detail per stage, entirely from the readiness
  /// model. No domain recalculation, and no internal terminology.
  static List<String> _details(
      MeasurementWorkflowReadiness r, MeasurementWorkflowStage s) {
    switch (s) {
      case MeasurementWorkflowStage.project:
        return [r.projectName ?? '열려 있는 프로젝트가 없습니다.'];
      case MeasurementWorkflowStage.measurementSetup:
        return [
          '측정 마이크: ${r.microphoneLabel ?? '미선택'}',
          '마이크 보정: ${measurementWorkflowCalibrationText(r.calibrationStatus)}',
          '입력 장치: ${r.inputLabel ?? '미선택'}',
          '측정 준비: ${measurementWorkflowSetupStateText(r.setupState)}',
        ];
      case MeasurementWorkflowStage.factoryTuning:
        return [
          '유닛 측정: ${r.measuredDriverCount} / ${r.requiredDriverCount}',
          measurementWorkflowFactoryText(r),
        ];
      case MeasurementWorkflowStage.roomTuning:
        return [
          '보정 전 측정: ${r.beforeCount} / 2',
          if (r.beforeMeasurementComplete)
            '측정 품질: ${r.beforeQualityReady ? '사용 가능' : '재측정 필요'}',
          '보정안: ${r.roomAutoPeqApproved ? '승인됨' : '미생성'}',
          '스피커 적용: ${r.correctionDeployedAndVerified ? '적용 확인됨' : '미적용'}',
        ];
      case MeasurementWorkflowStage.verification:
        return [
          '보정 후 측정: ${r.afterCount} / 2',
          if (r.afterMeasurementComplete)
            '전후 비교: ${r.beforeAfterComparable ? '비교 가능' : '조건이 달라 비교 불가'}',
          if (r.closedLoopComplete) '결과 확인 완료',
        ];
    }
  }
}

class _StageDot extends StatelessWidget {
  final MeasurementWorkflowStage stage;
  final MeasurementWorkflowStageState state;
  final bool expanded;
  final bool horizontal;
  final VoidCallback onTap;

  const _StageDot({
    required this.stage,
    required this.state,
    required this.expanded,
    required this.horizontal,
    required this.onTap,
  });

  (Color, IconData?) get _visual => switch (state) {
        MeasurementWorkflowStageState.complete => (
            ProColors.green,
            Icons.check
          ),
        MeasurementWorkflowStageState.inProgress => (ProColors.accent, null),
        MeasurementWorkflowStageState.warning => (ProColors.amber, null),
        MeasurementWorkflowStageState.blocked => (
            ProColors.red,
            Icons.priority_high
          ),
        MeasurementWorkflowStageState.notStarted => (
            ProColors.textTertiary,
            null
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _visual;
    final filled = state != MeasurementWorkflowStageState.notStarted;
    final marker = Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(
            color: filled ? color : color.withValues(alpha: 0.4), width: 1.4),
      ),
      child: icon == null
          ? (state == MeasurementWorkflowStageState.inProgress
              ? Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: color),
                  ),
                )
              : null)
          : Icon(icon, size: 11, color: color),
    );

    final title = Text(
      measurementWorkflowStageTitle(stage),
      style: TextStyle(
        color: filled ? ProColors.textPrimary : ProColors.textTertiary,
        fontSize: ProTypeScale.secondary,
        fontWeight: expanded ? FontWeight.w600 : FontWeight.w400,
      ),
      overflow: TextOverflow.ellipsis,
    );
    final subtitle = Text(
      measurementWorkflowStageStateText(state),
      style: TextStyle(color: color, fontSize: ProTypeScale.label),
      overflow: TextOverflow.ellipsis,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: ProRadius.smallAll,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: horizontal
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  marker,
                  const SizedBox(height: 8),
                  title,
                  const SizedBox(height: 2),
                  subtitle,
                ])
              : Row(children: [
                  marker,
                  const SizedBox(width: ProSpacing.md),
                  Expanded(child: title),
                  subtitle,
                ]),
        ),
      ),
    );
  }
}
