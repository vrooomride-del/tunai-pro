// Regression coverage for TUNAI_PRO_MASTER_HANDOFF.md item #2:
// "After-FRD/closed-loop 결과 -> report -> deploy package 연결".
//
// Confirms the full-system closed-loop result (before/after RMS, decision,
// rollback baseline, evidence refs, cycle count) survives the exact
// persistence path app re-entry relies on (ProProject.toJson/fromJson —
// the same round-trip pro_project_store.dart performs via SharedPreferences),
// and that buildTuningReport surfaces the restored data without loss or
// misrepresenting a non-success decision as a successful apply.
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_demo_project_factory.dart';
import 'package:tunai_pro/core/pro_measurement_store.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_report_data.dart';

void main() {
  group('full-system correction cycle survives project persistence', () {
    test('worsened cycle: rollback baseline + metrics round-trip exactly',
        () {
      final base = createTunaiProDemoProject();
      final rollbackState = base.tuningState.copyWith(tuningRevision: 7);
      final cycle = CorrectionCycle(
        projectId: base.id,
        channelId: 'full_system',
        cycleNumber: 2,
        beforeMeasurementRef: 'before:cycle2',
        peqSnapshot: base.tuningState.peqChannels.first,
        afterMeasurementRef: 'after:cycle2',
        afterMeasurementFileName: '4-channel FRD cycle 2',
        metrics: const CorrectionCycleMetrics(
          commonFreqMinHz: 0,
          commonFreqMaxHz: 0,
          commonPointCount: 4,
          meanAbsResidualBefore: 3.2,
          meanAbsResidualAfter: 3.9,
          improvementDelta: -0.7,
          peakErrorBefore: 3.2,
          peakErrorBeforeHz: 0,
          peakErrorAfter: 3.9,
          peakErrorAfterHz: 0,
          worsenedBandCount: 1,
          improvementCoverage: 0,
        ),
        decision: CorrectionCycleDecision.worsened,
        completedAt: DateTime(2026, 8, 2),
        createdAt: DateTime(2026, 8, 2),
        reasons: const ['composite weighted RMS worsened; rollback is proposed.'],
        fullSystemBeforeRefs: const {
          'ch_tw_l': 'before:ch_tw_l',
          'ch_wf_l': 'before:ch_wf_l',
          'ch_tw_r': 'before:ch_tw_r',
          'ch_wf_r': 'before:ch_wf_r',
        },
        fullSystemAfterRefs: const {
          'ch_tw_l': 'after:ch_tw_l',
          'ch_wf_l': 'after:ch_wf_l',
          'ch_tw_r': 'after:ch_tw_r',
          'ch_wf_r': 'after:ch_wf_r',
        },
        rollbackTuningState: rollbackState,
        safetyPassed: true,
        phaseAware: true,
      );
      final project = base.copyWith(correctionCycles: [cycle]);

      // The exact round-trip pro_project_store.dart performs for app re-entry.
      final restored = ProProject.fromJson(project.toJson());

      expect(restored.correctionCycles, hasLength(1));
      final restoredCycle = restored.correctionCycles.single;
      expect(restoredCycle.decision, CorrectionCycleDecision.worsened);
      expect(restoredCycle.cycleNumber, 2);
      expect(restoredCycle.metrics!.meanAbsResidualBefore, 3.2);
      expect(restoredCycle.metrics!.meanAbsResidualAfter, 3.9);
      expect(restoredCycle.metrics!.improvementDelta, -0.7);
      expect(restoredCycle.fullSystemBeforeRefs, cycle.fullSystemBeforeRefs);
      expect(restoredCycle.fullSystemAfterRefs, cycle.fullSystemAfterRefs);
      expect(restoredCycle.safetyPassed, isTrue);
      expect(restoredCycle.phaseAware, isTrue);
      // Rollback baseline (the previous tuning state) must not be dropped —
      // this is what a rollback action would restore.
      expect(restoredCycle.rollbackTuningState, isNotNull);
      expect(restoredCycle.rollbackTuningState!.tuningRevision, 7);

      // The same restored project must feed buildTuningReport without loss,
      // and must not present "worsened" as a success.
      final report =
          buildTuningReport(restored, const ProMeasurementStore());
      expect(report.correctionCycles, hasLength(1));
      final reportedCycle = report.correctionCycles.single;
      expect(reportedCycle['decision'], 'worsened');
      expect(reportedCycle['rollbackTuningState'], isNotNull);
      expect(reportedCycle['metrics']['improvementDelta'], -0.7);
    });

    test(
        'insufficientEvidence cycle (incomplete 4-channel data) is never '
        'reported as a success decision', () {
      final base = createTunaiProDemoProject();
      final cycle = CorrectionCycle(
        projectId: base.id,
        channelId: 'full_system',
        cycleNumber: 1,
        beforeMeasurementRef: '',
        peqSnapshot: base.tuningState.peqChannels.first,
        decision: CorrectionCycleDecision.insufficientEvidence,
        createdAt: DateTime(2026, 8, 2),
        completedAt: DateTime(2026, 8, 2),
        reasons: const ['all four Before and After FRD channels are required.'],
        // Only 2 of 4 required channels present — matches an aborted/partial
        // remeasurement, not a completed cycle.
        fullSystemBeforeRefs: const {'ch_tw_l': 'before:ch_tw_l'},
        fullSystemAfterRefs: const {'ch_tw_l': 'after:ch_tw_l'},
        safetyPassed: false,
      );
      final restored = ProProject.fromJson(
          base.copyWith(correctionCycles: [cycle]).toJson());

      final report =
          buildTuningReport(restored, const ProMeasurementStore());
      final reportedCycle = report.correctionCycles.single;
      expect(reportedCycle['decision'], 'insufficientEvidence');
      expect(
        const [
          'improvedAndComplete',
          'improvedNeedsAnotherCycle',
        ],
        isNot(contains(reportedCycle['decision'])),
      );
    });

    test('cycle count and history are preserved across multiple cycles', () {
      final base = createTunaiProDemoProject();
      CorrectionCycle cycleAt(int n, CorrectionCycleDecision decision) =>
          CorrectionCycle(
            projectId: base.id,
            channelId: 'full_system',
            cycleNumber: n,
            beforeMeasurementRef: 'before:$n',
            peqSnapshot: base.tuningState.peqChannels.first,
            afterMeasurementRef: 'after:$n',
            decision: decision,
            createdAt: DateTime(2026, 8, n),
            completedAt: DateTime(2026, 8, n),
          );
      final project = base.copyWith(correctionCycles: [
        cycleAt(1, CorrectionCycleDecision.improvedNeedsAnotherCycle),
        cycleAt(2, CorrectionCycleDecision.improvedAndComplete),
      ]);
      final restored = ProProject.fromJson(project.toJson());

      expect(restored.correctionCycles, hasLength(2));
      expect(restored.correctionCycles.map((c) => c.cycleNumber), [1, 2]);

      final report =
          buildTuningReport(restored, const ProMeasurementStore());
      expect(report.correctionCycles, hasLength(2));
    });
  });
}
