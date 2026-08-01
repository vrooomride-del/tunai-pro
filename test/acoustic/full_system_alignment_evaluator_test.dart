import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart';
import 'package:tunai_pro/core/acoustic/full_system_alignment_evaluator.dart';
import 'package:tunai_pro/core/acoustic/full_system_candidate_evaluator.dart';
import 'package:tunai_pro/core/orchestrator/guided_ai_project_apply.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _ids = ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'];
const _frequencies = [500.0, 1000.0, 2000.0];

ProProject _project({
  bool withPhase = true,
  bool advancedRightWoofer = false,
  bool invertedRightWoofer = false,
}) {
  final now = DateTime(2026, 8, 1);
  return ProProject(
    id: 'alignment-project',
    name: 'alignment-project',
    createdAt: now,
    updatedAt: now,
    acousticState: MeasurementProjectState(
      driverChannels: [
        for (var i = 0; i < _ids.length; i++)
          DriverChannel(
            id: _ids[i],
            name: _ids[i],
            role: i.isEven ? DriverRole.coaxTweeter : DriverRole.coaxWoofer,
            side: i < 2 ? DriverSide.left : DriverSide.right,
            frdData: ParsedMeasurementData(
              id: 'frd-${_ids[i]}',
              sourceFileName: '${_ids[i]}.frd',
              fileType: AcousticFileType.frd,
              importedAt: now,
              points: [
                for (final frequency in _frequencies)
                  MeasurementDataPoint(
                    frequencyHz: frequency,
                    magnitudeDb: -12.041199826559248,
                    phaseDeg: !withPhase
                        ? null
                        : invertedRightWoofer && i == 3
                            ? 180
                            : advancedRightWoofer && i == 3
                                ? 360 * frequency * 0.0002
                                : 0,
                  ),
              ],
            ),
          ),
      ],
    ),
    tuningState: TuningProjectState(
      crossoverChannels: [
        for (final id in _ids)
          CrossoverChannelState(
            channelId: id,
            bypassed: true,
            highPass: const CrossoverFilter(
              side: FilterSide.highPass,
              frequencyHz: 1000,
            ),
          ),
      ],
      channelControls: [
        for (final id in _ids)
          ChannelControlState(channelId: id, gainDb: -12.041199826559248),
      ],
    ),
  );
}

void main() {
  test('XO-region phase alignment selects the improving delay', () {
    final result = FullSystemAlignmentEvaluator.evaluate(
      project: _project(advancedRightWoofer: true),
    );

    expect(result.accepted, isTrue);
    expect(result.afterWeightedRmsDb, lessThan(result.beforeWeightedRmsDb));
    expect(result.tuning.getOrCreateControl('ch_wf_r').delayMs, 0.2);
    expect(result.channelIds, _ids);
  });

  test('polarity mismatch is corrected when it improves the composite sum', () {
    final result = FullSystemAlignmentEvaluator.evaluate(
      project: _project(invertedRightWoofer: true),
    );

    expect(result.accepted, isTrue);
    expect(
        result.tuning.getOrCreateCrossoverChannel('ch_wf_r').polarityInverted,
        isTrue);
  });

  test('missing phase fails closed without delay or polarity decisions', () {
    final project = _project(withPhase: false);
    final result = FullSystemAlignmentEvaluator.evaluate(project: project);

    expect(result.accepted, isFalse);
    expect(result.mode, FullSystemSummationMode.magnitudeOnly);
    expect(result.combinationsEvaluated, 0);
    expect(result.tuning.channelControls, project.tuningState.channelControls);
    expect(
        result.tuning.crossoverChannels, project.tuningState.crossoverChannels);
  });

  test('non-improving combinations are rejected and channel IDs stay intact',
      () {
    final result = FullSystemAlignmentEvaluator.evaluate(project: _project());

    expect(result.accepted, isFalse);
    expect(result.afterWeightedRmsDb,
        greaterThanOrEqualTo(result.beforeWeightedRmsDb - 0.01));
    expect(result.channelIds, isEmpty);
    expect(
      result.tuning.channelControls.map((control) => control.channelId).toSet(),
      _ids.toSet(),
    );
  });

  test('Guided AI project apply persists selected alignment before Deploy', () {
    final project = _project(advancedRightWoofer: true);
    final alignment = FullSystemAlignmentEvaluator.evaluate(project: project);
    final applyResult = TuningApplyResult(
      status: TuningApplyStatus.ok,
      updatedChannel: PeqChannelState.fixed('ch_tw_l'),
      applied: const [],
      skipped: const [],
      channelId: 'ch_tw_l',
      safetyPolicyId: 'safe',
      safetyPolicyVersion: 1,
      evidenceRefs: const [],
      reasons: const [],
      alignedTuningState: alignment.tuning,
    );

    final applied = GuidedAiProjectApply.apply(
      projectId: project.id,
      applyResult: applyResult,
      latestProject: project,
    );

    expect(applied.wrote, isTrue);
    expect(
      applied.updatedProject!.tuningState
          .getOrCreateControl('ch_wf_r')
          .delayMs,
      0.2,
    );
    expect(
      applied.updatedProject!.tuningState.crossoverChannels
          .map((channel) => channel.channelId)
          .toSet(),
      _ids.toSet(),
    );
  });
}
