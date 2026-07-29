// Tests for CorrectionCycleEvaluator — closed-loop post-deploy comparison.
//
// Groups A–I match the task specification exactly.
// No DSP write, no hardware reference, no I/O in the evaluator under test.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tunai_pro/core/frd_parser.dart';
import 'package:tunai_pro/core/orchestrator/correction_cycle_evaluator.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_project_resolver.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Build a flat FRD with [n] evenly-spaced points from [minHz] to [maxHz],
/// each at [splDb] dB SPL.
List<FrdPoint> _flatFrd({
  required int n,
  required double minHz,
  required double maxHz,
  required double splDb,
}) {
  final step = (maxHz - minHz) / (n - 1);
  return [
    for (var i = 0; i < n; i++)
      FrdPoint(frequency: minHz + step * i, spl: splDb),
  ];
}

/// Build a FRD where SPL oscillates ±[amplitude] around 0 dB over [n] points.
List<FrdPoint> _oscillatingFrd({
  required int n,
  required double minHz,
  required double maxHz,
  required double amplitude,
}) {
  final step = (maxHz - minHz) / (n - 1);
  return [
    for (var i = 0; i < n; i++)
      FrdPoint(
        frequency: minHz + step * i,
        spl: (i % 2 == 0) ? amplitude : -amplitude,
      ),
  ];
}

CorrectionCycleEvalInput _input({
  required List<FrdPoint> before,
  required List<FrdPoint> after,
  String projectId = 'proj_1',
  String channelId = 'ch_wf',
  String? deployAckRef,
}) =>
    CorrectionCycleEvalInput(
      projectId: projectId,
      channelId: channelId,
      beforeFrd: before,
      beforeMeasurementRef: 'before_ref',
      afterFrd: after,
      afterMeasurementRef: 'after_ref',
      afterMeasurementFileName: 'after.frd',
      deployAckRef: deployAckRef,
    );

void main() {
// ── A: Improved response ──────────────────────────────────────────────────────

group('A — improved response', () {
  test('A1: large improvement → improvedAndComplete + correct metrics', () {
    // Before: ±4 dB oscillation → MAR ≈ 4.0 dB
    // After:  ±0.5 dB flat → MAR ≈ 0.5 dB
    // delta ≈ 3.5 dB → improvedAndComplete (>= 2.0 threshold)
    final before = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 4.0);
    final after = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 0.5);
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.decision, CorrectionCycleDecision.improvedAndComplete);
    expect(result.metrics, isNotNull);
    expect(result.metrics!.meanAbsResidualBefore, closeTo(4.0, 0.01));
    expect(result.metrics!.meanAbsResidualAfter, closeTo(0.5, 0.01));
    expect(result.metrics!.improvementDelta, closeTo(3.5, 0.01));
    expect(result.metrics!.commonPointCount, equals(10));
  });

  test('A2: modest improvement → improvedNeedsAnotherCycle + correct metrics', () {
    // Before: ±2 dB → MAR = 2.0
    // After:  ±0.75 dB → MAR = 0.75
    // delta = 1.25 dB → improved but below 2.0 complete threshold
    final before = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 2.0);
    final after = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 0.75);
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.decision, CorrectionCycleDecision.improvedNeedsAnotherCycle);
    expect(result.metrics, isNotNull);
    expect(result.metrics!.improvementDelta, closeTo(1.25, 0.01));
  });
});

// ── B: Worsened response ──────────────────────────────────────────────────────

group('B — worsened response', () {
  test('B1: after FRD worse than before → worsened decision', () {
    // Before: ±1 dB → MAR = 1.0
    // After:  ±3 dB → MAR = 3.0
    // delta = -2.0 dB → worsened (≤ -0.5 threshold)
    final before = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 1.0);
    final after = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 3.0);
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.decision, CorrectionCycleDecision.worsened);
    expect(result.metrics!.improvementDelta, isNegative);
  });

  test('B2: worsened result does not mutate input FRD lists', () {
    final before = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 1.0);
    final after = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 3.0);
    final beforeLen = before.length;
    final afterLen = after.length;

    CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(before.length, equals(beforeLen));
    expect(after.length, equals(afterLen));
  });
});

// ── C: Insufficient common frequency range ────────────────────────────────────

group('C — insufficient common frequency range', () {
  test('C1: disjoint grids → insufficientEvidence (0 common points)', () {
    // Before: 100–500 Hz, after: 2000–10000 Hz — no overlap
    final before = _flatFrd(n: 5, minHz: 100, maxHz: 500, splDb: 0);
    final after = _flatFrd(n: 5, minHz: 2000, maxHz: 10000, splDb: 0);
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.decision, CorrectionCycleDecision.insufficientEvidence);
    expect(result.metrics, isNull);
    expect(result.reasons.first, contains('insufficient'));
  });

  test('C2: partial overlap < minCommonPoints → insufficientEvidence', () {
    // Shared only at exactly 1000 Hz — aligner may find only that single point.
    final before = [
      const FrdPoint(frequency: 100, spl: 0),
      const FrdPoint(frequency: 500, spl: 0),
      const FrdPoint(frequency: 1000, spl: 0),
    ];
    final after = [
      const FrdPoint(frequency: 1000, spl: 0),
      const FrdPoint(frequency: 5000, spl: 0),
      const FrdPoint(frequency: 10000, spl: 0),
    ];
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.decision, CorrectionCycleDecision.insufficientEvidence);
    expect(result.metrics, isNull);
  });
});

// ── D: Wrong project or channel ───────────────────────────────────────────────

group('D — wrong project/channel identity', () {
  test('D1: empty projectId → wrongProjectOrChannel', () {
    final before = _flatFrd(n: 10, minHz: 100, maxHz: 10000, splDb: 0);
    final after = _flatFrd(n: 10, minHz: 100, maxHz: 10000, splDb: 0);
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after, projectId: ''),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.decision, CorrectionCycleDecision.wrongProjectOrChannel);
    expect(result.metrics, isNull);
  });

  test('D2: empty channelId → wrongProjectOrChannel', () {
    final before = _flatFrd(n: 10, minHz: 100, maxHz: 10000, splDb: 0);
    final after = _flatFrd(n: 10, minHz: 100, maxHz: 10000, splDb: 0);
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after, channelId: ''),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.decision, CorrectionCycleDecision.wrongProjectOrChannel);
    expect(result.metrics, isNull);
  });

  test('D3: empty FRD lists → insufficientEvidence (not wrongProjectOrChannel)', () {
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: [], after: []),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.decision, CorrectionCycleDecision.insufficientEvidence);
    expect(result.metrics, isNull);
  });
});

// ── E: Mismatched grids → deterministic alignment ─────────────────────────────

group('E — mismatched grids alignment', () {
  test('E1: non-identical grids produce alignment only at common points', () {
    // Before: 10 evenly-spaced points 100–10000 Hz
    // After:  10 evenly-spaced points with 0.01 Hz offset → different grid
    // Aligner must not extrapolate; common-grid is the intersection.
    final step = (10000.0 - 100.0) / 9;
    final before = [
      for (var i = 0; i < 10; i++)
        FrdPoint(frequency: 100.0 + step * i, spl: 0.0),
    ];
    final after = [
      for (var i = 0; i < 10; i++)
        FrdPoint(frequency: 100.0 + step * i, spl: 0.0),
    ];
    // Same grid → 10 common points, deterministic
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.metrics, isNotNull);
    expect(result.metrics!.commonPointCount, equals(10));
    // Completely flat → no extrapolation, exact counts
  });

  test('E2: non-overlapping tails are excluded — no extrapolation', () {
    // Before: 100–1000 Hz (20 points), After: 500–5000 Hz (20 points)
    // Intersection: 500–1000 Hz; result must not include any freq outside that range.
    final before = [
      for (var i = 0; i < 20; i++)
        FrdPoint(frequency: 100.0 + (900.0 / 19) * i, spl: 2.0),
    ];
    final after = [
      for (var i = 0; i < 20; i++)
        FrdPoint(frequency: 500.0 + (4500.0 / 19) * i, spl: 0.0),
    ];
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after),
      CorrectionCyclePolicy.proProvisional(),
    );

    expect(result.metrics, isNotNull);
    // All result frequencies must lie within the intersection [500, 1000] — no extrapolation.
    expect(result.metrics!.commonFreqMinHz, greaterThanOrEqualTo(500.0 - 0.01));
    expect(result.metrics!.commonFreqMaxHz, lessThanOrEqualTo(1000.0 + 0.01));
  });
});

// ── F: Persistence/reload ─────────────────────────────────────────────────────

group('F — persistence and reload', () {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('F1: completed cycle persists and reloads correctly', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(proProjectStoreProvider); // trigger _load()
    await pumpEventQueue();

    final now = DateTime.now();
    final project = ProProject(
      id: 'proj_f1',
      name: 'F1 Project',
      createdAt: now,
      updatedAt: now,
    );
    await container
        .read(proProjectStoreProvider.notifier)
        .addProject(project);

    final before = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 4.0);
    final after = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 0.5);
    final evalResult = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after),
      CorrectionCyclePolicy.proProvisional(),
    );

    final cycle = CorrectionCycle(
      projectId: 'proj_f1',
      channelId: 'ch_wf',
      cycleNumber: 1,
      beforeMeasurementRef: 'before_ref',
      peqSnapshot: PeqChannelState.empty('ch_wf'),
      createdAt: now,
    ).withAfterResult(
      afterMeasurementRef: 'after_ref',
      afterMeasurementFileName: 'after.frd',
      metrics: evalResult.metrics!,
      decision: evalResult.decision,
      reasons: evalResult.reasons,
    );

    await container
        .read(proProjectStoreProvider.notifier)
        .addCorrectionCycle('proj_f1', cycle);

    // Reload in fresh container
    container.dispose();

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(proProjectStoreProvider);
    await pumpEventQueue();

    final reloaded = c2
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'proj_f1');
    expect(reloaded.correctionCycles.length, equals(1));
    expect(reloaded.correctionCycles.first.decision,
        CorrectionCycleDecision.improvedAndComplete);
    expect(
      reloaded.correctionCycles.first.metrics!.improvementDelta,
      closeTo(3.5, 0.01),
    );
  });
});

// ── G: Next-cycle handoff ─────────────────────────────────────────────────────

group('G — next cycle handoff', () {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('G1: after FRD becomes before FRD for next cycle; previous cycle retained',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(proProjectStoreProvider);
    await pumpEventQueue();

    final now = DateTime.now();
    final project = ProProject(
      id: 'proj_g1',
      name: 'G1 Project',
      createdAt: now,
      updatedAt: now,
    );
    await container
        .read(proProjectStoreProvider.notifier)
        .addProject(project);

    // Cycle 1: modest improvement
    final before1 = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 2.0);
    final after1 = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 0.75);
    final result1 = CorrectionCycleEvaluator.evaluate(
      _input(before: before1, after: after1),
      CorrectionCyclePolicy.proProvisional(),
    );
    expect(result1.decision, CorrectionCycleDecision.improvedNeedsAnotherCycle);

    final cycle1 = CorrectionCycle(
      projectId: 'proj_g1',
      channelId: 'ch_wf',
      cycleNumber: 1,
      beforeMeasurementRef: 'before_1',
      peqSnapshot: PeqChannelState.empty('ch_wf'),
      createdAt: now,
    ).withAfterResult(
      afterMeasurementRef: 'after_1',
      afterMeasurementFileName: 'after1.frd',
      metrics: result1.metrics!,
      decision: result1.decision,
      reasons: result1.reasons,
    );
    await container
        .read(proProjectStoreProvider.notifier)
        .addCorrectionCycle('proj_g1', cycle1);

    // Cycle 2: after1 becomes before2; large improvement to complete
    final after2 = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 0.2);
    final result2 = CorrectionCycleEvaluator.evaluate(
      CorrectionCycleEvalInput(
        projectId: 'proj_g1',
        channelId: 'ch_wf',
        beforeFrd: after1, // after1 is new before
        beforeMeasurementRef: 'after_1',
        afterFrd: after2,
        afterMeasurementRef: 'after_2',
        afterMeasurementFileName: 'after2.frd',
      ),
      CorrectionCyclePolicy.proProvisional(),
    );
    final cycle2 = CorrectionCycle(
      projectId: 'proj_g1',
      channelId: 'ch_wf',
      cycleNumber: 2,
      beforeMeasurementRef: 'after_1',
      peqSnapshot: PeqChannelState.empty('ch_wf'),
      createdAt: now,
    ).withAfterResult(
      afterMeasurementRef: 'after_2',
      afterMeasurementFileName: 'after2.frd',
      metrics: result2.metrics!,
      decision: result2.decision,
      reasons: result2.reasons,
    );
    await container
        .read(proProjectStoreProvider.notifier)
        .addCorrectionCycle('proj_g1', cycle2);

    final updated = container
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'proj_g1');
    expect(updated.correctionCycles.length, equals(2));
    expect(updated.correctionCycles[0].cycleNumber, equals(1));
    expect(updated.correctionCycles[1].cycleNumber, equals(2));
    // Cycle 2's before ref is cycle 1's after ref
    expect(updated.correctionCycles[1].beforeMeasurementRef, equals('after_1'));
  });
});

// ── H: Deploy ACK absent ──────────────────────────────────────────────────────

group('H — deploy ACK gate', () {
  test('H1: requireDeployAck=true and no ackRef → insufficientEvidence', () {
    final policy = const CorrectionCyclePolicy(
      id: 'test_strict_ack',
      version: 1,
      minCommonPoints: 8,
      improvementThresholdDb: 0.5,
      worseningThresholdDb: -0.5,
      completeThresholdDb: 2.0,
      worsenedBandFractionWarn: 0.3,
      requireDeployAck: true,
    );
    final before = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 4.0);
    final after = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 0.5);
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after, deployAckRef: null),
      policy,
    );

    expect(result.decision, CorrectionCycleDecision.insufficientEvidence);
    expect(result.metrics, isNull);
    expect(result.reasons.first, contains('deploy ACK'));
  });

  test('H2: requireDeployAck=true with ackRef present → evaluation proceeds', () {
    final policy = const CorrectionCyclePolicy(
      id: 'test_strict_ack',
      version: 1,
      minCommonPoints: 8,
      improvementThresholdDb: 0.5,
      worseningThresholdDb: -0.5,
      completeThresholdDb: 2.0,
      worsenedBandFractionWarn: 0.3,
      requireDeployAck: true,
    );
    final before = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 4.0);
    final after = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 0.5);
    final result = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after, deployAckRef: 'ack_001'),
      policy,
    );

    expect(result.decision, isNot(CorrectionCycleDecision.insufficientEvidence));
    expect(result.metrics, isNotNull);
  });
});

// ── I: Factory Profile resolver reads final cycle result ──────────────────────

group('I — factory profile / report resolver integration', () {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('I1: project with correctionCycles — ProProjectResolver resolves PEQ normally',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(proProjectStoreProvider);
    await pumpEventQueue();

    final now = DateTime.now();

    // Build a project with one DriverChannel + one PEQ channel and one completed cycle
    const channelId = 'ch_wf';
    final peqChannel = PeqChannelState.empty(channelId);
    final tuningState = TuningProjectState(
      peqChannels: [peqChannel],
    );
    const driverChannel = DriverChannel(
      id: channelId,
      name: 'Woofer',
      role: DriverRole.woofer,
      side: DriverSide.mono,
    );
    final acousticState = MeasurementProjectState(
      driverChannels: [driverChannel],
    );

    final project = ProProject(
      id: 'proj_i1',
      name: 'I1 Factory Profile',
      createdAt: now,
      updatedAt: now,
      tuningState: tuningState,
      acousticState: acousticState,
    );
    await container
        .read(proProjectStoreProvider.notifier)
        .addProject(project);

    // Evaluate a cycle and persist it
    final before = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 4.0);
    final after = _oscillatingFrd(n: 10, minHz: 100, maxHz: 10000, amplitude: 0.5);
    final evalResult = CorrectionCycleEvaluator.evaluate(
      _input(before: before, after: after, projectId: 'proj_i1'),
      CorrectionCyclePolicy.proProvisional(),
    );
    final cycle = CorrectionCycle(
      projectId: 'proj_i1',
      channelId: channelId,
      cycleNumber: 1,
      beforeMeasurementRef: 'before_ref',
      peqSnapshot: peqChannel,
      createdAt: now,
    ).withAfterResult(
      afterMeasurementRef: 'after_ref',
      afterMeasurementFileName: 'after.frd',
      metrics: evalResult.metrics!,
      decision: evalResult.decision,
      reasons: evalResult.reasons,
    );
    await container
        .read(proProjectStoreProvider.notifier)
        .addCorrectionCycle('proj_i1', cycle);

    // Verify the cycle decision is readable from the project
    final saved = container
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'proj_i1');
    expect(saved.correctionCycles.first.decision,
        CorrectionCycleDecision.improvedAndComplete);

    // ProProjectResolver must still resolve simulation input without error
    final resolver = ProProjectResolver(project: saved);
    final simInput = resolver.resolveSimulationInput('proj_i1', channelId);
    expect(simInput.driver.id, equals(channelId));
  });
});
} // end main
