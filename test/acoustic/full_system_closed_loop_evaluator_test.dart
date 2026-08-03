import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/full_system_closed_loop_evaluator.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _ids = ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'];
const _frequencies = [100.0, 1000.0, 10000.0];

ProProject _project(List<double> magnitudes, {bool withPhase = true}) {
  final now = DateTime(2026, 8, 1);
  return ProProject(
    id: 'p',
    name: 'p',
    createdAt: now,
    updatedAt: now,
    acousticState: MeasurementProjectState(
      driverChannels: [
        for (var channel = 0; channel < _ids.length; channel++)
          DriverChannel(
            id: _ids[channel],
            name: _ids[channel],
            role:
                channel.isEven ? DriverRole.coaxTweeter : DriverRole.coaxWoofer,
            side: channel < 2 ? DriverSide.left : DriverSide.right,
            frdData: ParsedMeasurementData(
              id: 'frd-${_ids[channel]}',
              sourceFileName: '${_ids[channel]}.frd',
              fileType: AcousticFileType.frd,
              importedAt: now,
              points: [
                for (var i = 0; i < _frequencies.length; i++)
                  MeasurementDataPoint(
                    frequencyHz: _frequencies[i],
                    magnitudeDb: magnitudes[i],
                    phaseDeg: withPhase ? 0 : null,
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

Map<String, String> _refs(String prefix) => {
      for (final id in _ids) id: '$prefix:$id',
    };

FullSystemClosedLoopEvaluation _evaluate({
  required List<double> before,
  required List<double> after,
  int cycle = 1,
  bool safety = true,
  bool withPhase = true,
  Map<String, String>? afterRefs,
}) =>
    FullSystemClosedLoopEvaluator.evaluate(
      beforeProject: _project(before, withPhase: withPhase),
      afterProject: _project(after, withPhase: withPhase),
      previousTuningState: TuningProjectState.createDefault(),
      deployedTuningState: TuningProjectState.createDefault(),
      cycleNumber: cycle,
      safetyPassed: safety,
      beforeEvidenceRefs: _refs('before'),
      afterEvidenceRefs: afterRefs ?? _refs('after'),
    );

void main() {
  test('safe composite improvement is approved and creates bounded next cycle',
      () {
    final result = _evaluate(
      before: const [-8.0, -12.0, -8.0],
      after: const [-10.0, -12.0, -10.0],
    );

    expect(result.approved, isTrue);
    expect(result.decision, CorrectionCycleDecision.improvedNeedsAnotherCycle);
    expect(result.afterWeightedRmsDb, lessThan(result.beforeWeightedRmsDb));
    expect(result.nextCycle!.cycleNumber, 2);
    expect(result.nextCycle!.requiresUserApproval, isTrue,
        reason: 'no next-cycle write is allowed before explicit approval');
  });

  test('sub-threshold improvement terminates as converged', () {
    final result = _evaluate(
      before: const [-10.0, -12.0, -10.0],
      after: const [-10.1, -12.0, -10.1],
    );
    expect(result.decision, CorrectionCycleDecision.noMeaningfulImprovement);
    expect(result.converged, isTrue);
    expect(result.nextCycle, isNull);
  });

  test('worsening proposes the exact previous tuning state for rollback', () {
    final previous = TuningProjectState(
      channelControls: const [
        ChannelControlState(channelId: 'ch_tw_l', gainDb: -2)
      ],
    );
    final result = FullSystemClosedLoopEvaluator.evaluate(
      beforeProject: _project(const [-10.0, -12.0, -10.0]),
      afterProject: _project(const [-7.0, -12.0, -7.0]),
      previousTuningState: previous,
      deployedTuningState: TuningProjectState.createDefault(),
      cycleNumber: 1,
      safetyPassed: true,
      beforeEvidenceRefs: _refs('before'),
      afterEvidenceRefs: _refs('after'),
    );
    expect(result.decision, CorrectionCycleDecision.worsened);
    expect(result.rollbackSuggested, isTrue);
    expect(result.rollbackTuningState, same(previous));
  });

  test('cycle three is terminal even when residual improvement remains', () {
    final result = _evaluate(
      before: const [-6.0, -12.0, -6.0],
      after: const [-8.0, -12.0, -8.0],
      cycle: 3,
    );
    expect(result.decision, CorrectionCycleDecision.improvedAndComplete);
    expect(result.converged, isTrue);
    expect(result.nextCycle, isNull);
  });

  test('missing one of four channel refs blocks evaluation', () {
    final refs = _refs('after')..remove('ch_wf_r');
    final result = _evaluate(
      before: const [-8.0, -12.0, -8.0],
      after: const [-10.0, -12.0, -10.0],
      afterRefs: refs,
    );
    expect(result.decision, CorrectionCycleDecision.insufficientEvidence);
    expect(result.approved, isFalse);
  });

  test('phase-free next cycle cannot reconsider alignment', () {
    final result = _evaluate(
      before: const [-2.0, -6.0, -2.0],
      after: const [-4.0, -6.0, -4.0],
      withPhase: false,
    );
    expect(result.nextCycle!.alignmentReevaluationAllowed, isFalse);
  });

  // ── Phase 4-C-2A — Test A: next-cycle draft content ─────────────────────────

  test(
      'nextCycle.beforeProject carries After FRD as new Before, deployed '
      'tuning, and leaves inputs unmutated', () {
    const before = [-8.0, -12.0, -8.0];
    const after = [-10.0, -12.0, -10.0];
    final beforeProject = _project(before);
    final afterProject = _project(after);
    final previousTuning = TuningProjectState(
      channelControls: const [
        ChannelControlState(channelId: 'ch_tw_l', gainDb: -1),
      ],
    );
    final deployedTuning = TuningProjectState(
      channelControls: const [
        ChannelControlState(channelId: 'ch_tw_l', gainDb: -3),
      ],
    );

    final result = FullSystemClosedLoopEvaluator.evaluate(
      beforeProject: beforeProject,
      afterProject: afterProject,
      previousTuningState: previousTuning,
      deployedTuningState: deployedTuning,
      cycleNumber: 1,
      safetyPassed: true,
      beforeEvidenceRefs: _refs('before'),
      afterEvidenceRefs: _refs('after'),
    );

    expect(result.decision, CorrectionCycleDecision.improvedNeedsAnotherCycle);
    final draft = result.nextCycle;
    expect(draft, isNotNull);

    // Each channel's FRD in the draft's Before matches the After fixture,
    // not the original Before fixture.
    for (final channel in draft!.beforeProject.acousticState.driverChannels) {
      final magnitudes =
          channel.frdData!.points.map((p) => p.magnitudeDb).toList();
      expect(magnitudes, after,
          reason: 'channel ${channel.id} must carry the After FRD');
      expect(magnitudes, isNot(before),
          reason: 'channel ${channel.id} must not carry the original Before FRD');
    }

    // Tuning baseline is the deployed (cycle-1-corrected) tuning, not the
    // pre-cycle-1 tuning.
    expect(draft.beforeProject.tuningState, deployedTuning);
    expect(draft.beforeProject.tuningState, isNot(previousTuning));

    // Inputs are unmutated by the call.
    expect(
        beforeProject.acousticState.driverChannels
            .map((c) => c.frdData!.points.map((p) => p.magnitudeDb).toList()),
        everyElement(before));
    expect(
        afterProject.acousticState.driverChannels
            .map((c) => c.frdData!.points.map((p) => p.magnitudeDb).toList()),
        everyElement(after));
  });
}
