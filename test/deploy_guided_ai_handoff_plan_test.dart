// Regression coverage for the Guided AI apply → Deploy write-plan handoff.
//
// TUNAI_PRO_MASTER_HANDOFF.md flags "empty-package / No pending writes UX"
// as unverified. This confirms the actual persistence → plan-building path
// (the same one deploy_dialog.dart uses) produces writable ops once
// GuidedAiProjectApply has persisted real PEQ data, and stays correctly
// empty when no channel has ever been tuned.
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';
import 'package:tunai_pro/core/deploy/adau1701_engineering_export.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/orchestrator/guided_ai_project_apply.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _ids = ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'];

List<DriverChannel> _channels() => [
      for (final id in _ids)
        DriverChannel(
            id: id, name: id, role: DriverRole.tweeter, side: DriverSide.left),
    ];

ProProject _freshProject() {
  final now = DateTime(2025, 1, 1);
  return ProProject(
    id: 'proj_handoff',
    name: 'Handoff',
    createdAt: now,
    updatedAt: now,
    tuningState: TuningProjectState(peqChannels: const []),
  );
}

SelectedCandidate _sel(String featureId) => SelectedCandidate(
      scoredCandidate: ScoredCandidate(
        candidate: PeqCandidate(
          candidateId: 'candidate:$featureId',
          featureId: featureId,
          featureType: AcousticFeatureType.narrowPeak,
          frequencyHz: 120.0,
          gainDb: -3.0,
          q: 2.0,
          intent: CorrectionIntent.cut,
          reason: 'test',
        ),
        prominenceDb: 6.0,
        prominenceScore: 40.0,
        magnitudeConsistencyScore: 30.0,
        qualityFactor: 1.0,
        compositeScore: 70.0,
        rank: 1,
        grade: CandidateScoreGrade.excellent,
        reasons: const ['test'],
      ),
      applicationOrder: 1,
      selectionReason: 'test',
    );

/// Mirrors DeployDialog._buildPlan's gain+PEQ/XO assembly (no previous
/// applied gains/XO — matches a first-time deploy after Guided AI apply).
/// Phase 7-4A split PEQ and XO into independent builders; XO is diff-only
/// (see buildAdau1701XoExportBlocks), but Guided AI candidates in this test
/// are PEQ-only, so previousAppliedXo is irrelevant here.
HardwareWritePlan _buildDeployPlan(ProProject project) {
  final gainPkg = buildAdau1701GainExportPackage(
    channels: _channels(),
    tuning: project.tuningState,
  );
  final peqBlocks = buildAdau1701PeqExportBlocks(
    channels: _channels(),
    tuning: project.tuningState,
  );
  final xoBlocks = buildAdau1701XoExportBlocks(
    channels: _channels(),
    tuning: project.tuningState,
  );
  final allBlocks = [...gainPkg.parameterBlocks, ...peqBlocks, ...xoBlocks];
  final pkg = gainPkg.copyWith(
    status:
        allBlocks.isEmpty ? ExportStatus.notReady : ExportStatus.draftReady,
    parameterBlocks: allBlocks,
  );
  return buildHardwareWritePlan(pkg, HardwareDeviceProfiles.adau1701Icp5);
}

void main() {
  test('4-channel guided apply persists PEQ then Deploy plan has writable ops',
      () {
    var project = _freshProject();

    for (final id in _ids) {
      final channel = PeqChannelState.fixed(id);
      final safety = CandidateSafetyResult(
        applyPermitted: true,
        issues: const [],
        verifiedCandidates: [_sel(id)],
        policyId: 'p',
        policyVersion: 1,
        evidenceRefs: const [],
      );
      final engineResult = AcousticApplyEngine.apply(safety, channel);
      final op = GuidedAiProjectApply.apply(
        projectId: project.id,
        applyResult: engineResult,
        latestProject: project,
      );
      expect(op.wrote, isTrue,
          reason: 'apply for $id should write (${engineResult.status})');
      project = op.updatedProject!;
    }

    expect(project.tuningState.peqChannels, hasLength(_ids.length));

    final plan = _buildDeployPlan(project);
    expect(plan.writableOperations, isNotEmpty,
        reason:
            'Deploy plan must not be empty once 4-channel Guided AI apply has '
            'persisted real PEQ state — this is the exact "empty package" '
            'regression the master handoff flags.');
  });

  test('untouched project (no Guided AI apply yet) yields an empty plan', () {
    final project = _freshProject();
    final plan = _buildDeployPlan(project);
    expect(plan.operations, isEmpty,
        reason: 'A project with no PEQ/gain/XO configuration has nothing '
            'pending — the empty plan here is correct, not a bug.');
  });
}
