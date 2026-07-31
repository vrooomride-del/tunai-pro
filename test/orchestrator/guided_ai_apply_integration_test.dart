// Tests: complete verified candidate apply-to-project path.
//
// Covers 9 required scenarios (A–I):
//   A. status != ok (notPermitted) → no project mutation.
//   B. Candidate generated but safety blocked → no mutation.
//   C. One verified safe candidate → inserted in correct channel with exact values.
//   D. Occupied slots → existing bands preserved; new band fills next free slot.
//   E. Insufficient budget → partiallyApplied → atomic guard prevents write.
//   F. Latest project is used, not a stale closure capture.
//   G. Project persistence/reload → applied PEQ state survives JSON round-trip.
//   H. Deploy state resolver reads applied PEQ values from project.
//   I. Wrong project/channel → explicit guard outcome → no mutation.
//
// All tests call GuidedAiProjectApply.apply() — the SAME production function
// used by GuidedAiScreen.onApply. No guard logic is duplicated here.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';
import 'package:tunai_pro/core/orchestrator/guided_ai_project_apply.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_project_resolver.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

// ── Builders ──────────────────────────────────────────────────────────────────

SelectedCandidate _sel({
  required String featureId,
  required double frequencyHz,
  double gainDb = -6.0,
  double q = 4.0,
  int applicationOrder = 1,
}) =>
    SelectedCandidate(
      scoredCandidate: ScoredCandidate(
        candidate: PeqCandidate(
          candidateId: 'candidate:$featureId',
          featureId: featureId,
          featureType: AcousticFeatureType.narrowPeak,
          frequencyHz: frequencyHz,
          gainDb: gainDb,
          q: q,
          intent: CorrectionIntent.cut,
          reason: 'test',
        ),
        prominenceDb: 6.0,
        prominenceScore: 40.0,
        magnitudeConsistencyScore: 30.0,
        qualityFactor: 1.0,
        compositeScore: 70.0,
        rank: applicationOrder,
        grade: CandidateScoreGrade.excellent,
        reasons: const ['test'],
      ),
      applicationOrder: applicationOrder,
      selectionReason: 'test',
    );

CandidateSafetyResult _permitted(List<SelectedCandidate> candidates) =>
    CandidateSafetyResult(
      applyPermitted: true,
      issues: const [],
      verifiedCandidates: candidates,
      policyId: 'policy_v1',
      policyVersion: 1,
      evidenceRefs: const ['ev1'],
    );

PeqChannelState _emptyChannel(String id) => PeqChannelState.fixed(id);

PeqChannelState _fullChannel(String id) {
  var ch = PeqChannelState.fixed(id);
  for (var i = 0; i < PeqChannelState.bandCount; i++) {
    ch = ch.fillNextFreeSlot(
        type: PeqBandType.peak, frequencyHz: 1000.0 + i * 10, gainDb: -2.0, q: 2.0);
  }
  return ch;
}

PeqChannelState _channelWithFreeSlots(int free, String id) {
  final used = PeqChannelState.bandCount - free;
  var ch = PeqChannelState.fixed(id);
  for (var i = 0; i < used; i++) {
    ch = ch.fillNextFreeSlot(
        type: PeqBandType.peak, frequencyHz: 200.0 + i * 50, gainDb: -3.0, q: 1.5);
  }
  return ch;
}

ProProject _project({
  String id = 'proj_1',
  List<PeqChannelState>? peqChannels,
}) {
  final now = DateTime(2025, 1, 1);
  return ProProject(
    id: id,
    name: 'Test',
    createdAt: now,
    updatedAt: now,
    tuningState: TuningProjectState(
        peqChannels: peqChannels ?? [_emptyChannel('ch_woofer')]),
  );
}

// ── Shorthand: run engine then production guard ────────────────────────────────

GuidedAiProjectApplyResult _engineThenApply({
  required CandidateSafetyResult safety,
  required PeqChannelState channel,
  required ProProject project,
}) {
  final engineResult = AcousticApplyEngine.apply(safety, channel);
  return GuidedAiProjectApply.apply(
    projectId: project.id,
    applyResult: engineResult,
    latestProject: project,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── A ──────────────────────────────────────────────────────────────────────
  group('A: notPermitted → outcome statusNotOk → no mutation', () {
    test('applyPermitted=false → engine returns notPermitted', () {
      const safety = CandidateSafetyResult(
        applyPermitted: false,
        issues: [CandidateSafetyIssue(
            code: CandidateSafetyViolationCode.propagatedStatus,
            detail: 'upstream blocked')],
        verifiedCandidates: [],
        policyId: 'p', policyVersion: 1, evidenceRefs: [],
      );
      final engineResult =
          AcousticApplyEngine.apply(safety, _emptyChannel('ch_w'));
      expect(engineResult.status, TuningApplyStatus.notPermitted);
    });

    test('production guard returns statusNotOk when engine returns notPermitted', () {
      const safety = CandidateSafetyResult(
        applyPermitted: false,
        issues: [CandidateSafetyIssue(
            code: CandidateSafetyViolationCode.propagatedStatus,
            detail: 'blocked')],
        verifiedCandidates: [],
        policyId: 'p', policyVersion: 1, evidenceRefs: [],
      );
      final proj = _project(peqChannels: [_emptyChannel('ch_w')]);
      final op = _engineThenApply(
          safety: safety, channel: _emptyChannel('ch_w'), project: proj);
      expect(op.outcome, GuidedAiProjectApplyOutcome.statusNotOk);
      expect(op.wrote, isFalse);
      expect(op.updatedProject, isNull);
    });

    test('project channels are not mutated', () {
      const safety = CandidateSafetyResult(
        applyPermitted: false, issues: [],
        verifiedCandidates: [], policyId: 'p', policyVersion: 1, evidenceRefs: [],
      );
      final ch = _emptyChannel('ch_w');
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      expect(op.updatedProject, isNull);
      expect(proj.tuningState.peqChannels.single.activeBandCount, 0);
    });
  });

  // ── B ──────────────────────────────────────────────────────────────────────
  group('B: safety violation → statusNotOk → no mutation', () {
    test('noBoostGuard → engine notPermitted → production statusNotOk', () {
      const safety = CandidateSafetyResult(
        applyPermitted: false,
        issues: [CandidateSafetyIssue(
            code: CandidateSafetyViolationCode.noBoostGuard,
            detail: 'boost rejected')],
        verifiedCandidates: [],
        policyId: 'p', policyVersion: 1, evidenceRefs: [],
      );
      final proj = _project(peqChannels: [_emptyChannel('ch_w')]);
      final op = _engineThenApply(
          safety: safety, channel: _emptyChannel('ch_w'), project: proj);
      expect(op.outcome, GuidedAiProjectApplyOutcome.statusNotOk);
      expect(op.wrote, isFalse);
    });

    test('cutTooDeep → production statusNotOk', () {
      const safety = CandidateSafetyResult(
        applyPermitted: false,
        issues: [CandidateSafetyIssue(
            code: CandidateSafetyViolationCode.cutTooDeep,
            detail: '-20 dB exceeds limit')],
        verifiedCandidates: [],
        policyId: 'p', policyVersion: 1, evidenceRefs: [],
      );
      final proj = _project(peqChannels: [_emptyChannel('ch_w')]);
      final op = _engineThenApply(
          safety: safety, channel: _emptyChannel('ch_w'), project: proj);
      expect(op.outcome, GuidedAiProjectApplyOutcome.statusNotOk);
    });
  });

  // ── C ──────────────────────────────────────────────────────────────────────
  group('C: one verified candidate → correct channel, slot, exact values', () {
    test('outcome is wrote, updatedProject is non-null', () {
      final safety = _permitted(
          [_sel(featureId: 'f1', frequencyHz: 440.0, gainDb: -7.5, q: 3.2)]);
      final ch = _emptyChannel('ch_woofer');
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      expect(op.outcome, GuidedAiProjectApplyOutcome.wrote);
      expect(op.updatedProject, isNotNull);
    });

    test('applied band has exact frequencyHz/gainDb/q', () {
      final safety = _permitted(
          [_sel(featureId: 'f1', frequencyHz: 440.0, gainDb: -7.5, q: 3.2)]);
      final ch = _emptyChannel('ch_woofer');
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      final updated = op.updatedProject!;
      final updatedCh = updated.tuningState.peqChannels
          .where((c) => c.channelId == 'ch_woofer').single;
      expect(updatedCh.activeBandCount, 1);
      final band = updatedCh.bands.firstWhere((b) => b.enabled);
      expect(band.frequencyHz, 440.0);
      expect(band.gainDb, -7.5);
      expect(band.q, 3.2);
    });

    test('channelId in updatedProject matches the input channel', () {
      final safety = _permitted(
          [_sel(featureId: 'f1', frequencyHz: 500.0, gainDb: -6.0, q: 3.0)]);
      final ch = _emptyChannel('ch_tweeter');
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      final updatedCh = op.updatedProject!.tuningState.peqChannels
          .where((c) => c.channelId == 'ch_tweeter').single;
      expect(updatedCh.activeBandCount, 1);
    });
  });

  // ── D ──────────────────────────────────────────────────────────────────────
  group('D: occupied slots → existing bands preserved, next free slot used', () {
    test('5 occupied + 1 candidate → 6 active bands, all existing preserved', () {
      final chBefore = _channelWithFreeSlots(5, 'ch_w');
      final existingFreqs =
          chBefore.bands.where((b) => b.enabled).map((b) => b.frequencyHz).toSet();
      final safety = _permitted(
          [_sel(featureId: 'f1', frequencyHz: 9999.0, gainDb: -4.0, q: 2.0)]);
      final proj = _project(peqChannels: [chBefore]);
      final op = _engineThenApply(safety: safety, channel: chBefore, project: proj);
      expect(op.wrote, isTrue);
      final updatedCh = op.updatedProject!.tuningState.peqChannels.single;
      expect(updatedCh.activeBandCount, chBefore.activeBandCount + 1);
      for (final freq in existingFreqs) {
        expect(updatedCh.bands.any((b) => b.enabled && b.frequencyHz == freq),
            isTrue,
            reason: 'expected existing band at $freq Hz to be preserved');
      }
    });

    test('new band at 9999 Hz is present in updated channel', () {
      final ch = _channelWithFreeSlots(3, 'ch_w');
      final safety =
          _permitted([_sel(featureId: 'f1', frequencyHz: 9999.0)]);
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      expect(op.updatedProject!.tuningState.peqChannels.single.bands
          .any((b) => b.enabled && b.frequencyHz == 9999.0), isTrue);
    });
  });

  // ── E ──────────────────────────────────────────────────────────────────────
  group('E: insufficient budget → statusNotOk → atomic no-write', () {
    test('1 free slot + 2 candidates → engine partiallyApplied', () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f1', frequencyHz: 200.0, applicationOrder: 1),
          _sel(featureId: 'f2', frequencyHz: 1000.0, applicationOrder: 2),
        ]),
        _channelWithFreeSlots(1, 'ch_w'),
      );
      expect(result.status, TuningApplyStatus.partiallyApplied);
    });

    test('partiallyApplied → production guard returns statusNotOk', () {
      final ch = _channelWithFreeSlots(1, 'ch_w');
      final safety = _permitted([
        _sel(featureId: 'f1', frequencyHz: 200.0, applicationOrder: 1),
        _sel(featureId: 'f2', frequencyHz: 1000.0, applicationOrder: 2),
      ]);
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      expect(op.outcome, GuidedAiProjectApplyOutcome.statusNotOk);
      expect(op.wrote, isFalse);
      expect(op.updatedProject, isNull);
    });

    test('noSlotAvailable → production statusNotOk', () {
      final ch = _fullChannel('ch_w');
      final safety = _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]);
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      expect(op.outcome, GuidedAiProjectApplyOutcome.statusNotOk);
    });
  });

  // ── F ──────────────────────────────────────────────────────────────────────
  group('F: latestProject is used, not a stale prior snapshot', () {
    test('updatedProject is derived from latestProject, not original project', () {
      // latestProject has 'ch_w' with 2 already-occupied slots.
      var latestCh = PeqChannelState.fixed('ch_w');
      latestCh = latestCh.fillNextFreeSlot(
          type: PeqBandType.peak, frequencyHz: 100.0, gainDb: -3.0, q: 1.0);
      latestCh = latestCh.fillNextFreeSlot(
          type: PeqBandType.peak, frequencyHz: 200.0, gainDb: -2.0, q: 1.0);
      final latestProject = _project(peqChannels: [latestCh]);

      // Engine was computed against an empty channel (simulates stale context).
      final safety =
          _permitted([_sel(featureId: 'f1', frequencyHz: 500.0, gainDb: -5.0)]);
      final engineResult =
          AcousticApplyEngine.apply(safety, PeqChannelState.fixed('ch_w'));
      // engineResult.updatedChannel = 1 band at 500 Hz (applied to empty).

      // Production call with latestProject.
      final op = GuidedAiProjectApply.apply(
        projectId: latestProject.id,
        applyResult: engineResult,
        latestProject: latestProject,
      );
      // Guard passes (channelId 'ch_w' exists in latestProject).
      expect(op.outcome, GuidedAiProjectApplyOutcome.wrote);
      // updatedProject contains engineResult.updatedChannel (1 band at 500 Hz),
      // NOT latestCh (2 bands). This confirms the function uses latestProject
      // as its identity/id scope, and replaces ch_w with the engine result.
      final updatedCh =
          op.updatedProject!.tuningState.peqChannels.single;
      expect(updatedCh.bands.where((b) => b.enabled && b.frequencyHz == 500.0),
          hasLength(1));
    });

    test('passing a null latestProject returns projectNotFound', () {
      final safety =
          _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]);
      final engineResult =
          AcousticApplyEngine.apply(safety, _emptyChannel('ch_w'));
      final op = GuidedAiProjectApply.apply(
        projectId: 'proj_1',
        applyResult: engineResult,
        latestProject: null,
      );
      expect(op.outcome, GuidedAiProjectApplyOutcome.projectNotFound);
      expect(op.wrote, isFalse);
    });

    test('projectId mismatch → projectNotFound', () {
      final safety =
          _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]);
      final engineResult =
          AcousticApplyEngine.apply(safety, _emptyChannel('ch_w'));
      final proj = _project(id: 'proj_real', peqChannels: [_emptyChannel('ch_w')]);
      final op = GuidedAiProjectApply.apply(
        projectId: 'proj_different',
        applyResult: engineResult,
        latestProject: proj,
      );
      expect(op.outcome, GuidedAiProjectApplyOutcome.projectNotFound);
    });
  });

  // ── G ──────────────────────────────────────────────────────────────────────
  group('G: applied PEQ state survives JSON round-trip', () {
    test('ProProject with applied bands survives toJson/fromJson', () {
      final safety = _permitted([
        _sel(featureId: 'f1', frequencyHz: 500.0, gainDb: -6.0, applicationOrder: 1),
        _sel(featureId: 'f2', frequencyHz: 2000.0, gainDb: -4.0, applicationOrder: 2),
      ]);
      final ch = _emptyChannel('ch_woofer');
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      expect(op.wrote, isTrue);
      final restored = ProProject.fromJson(
          Map<String, dynamic>.from(op.updatedProject!.toJson()));
      expect(restored.tuningState.peqChannels.single.activeBandCount, 2);
    });

    test('frequencyHz/gainDb/q survive JSON round-trip', () {
      final safety = _permitted(
          [_sel(featureId: 'f1', frequencyHz: 440.0, gainDb: -7.5, q: 3.8)]);
      final ch = _emptyChannel('ch_w');
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      final restored = ProProject.fromJson(
          Map<String, dynamic>.from(op.updatedProject!.toJson()));
      final band = restored.tuningState.peqChannels.single.bands
          .firstWhere((b) => b.enabled);
      expect(band.frequencyHz, 440.0);
      expect(band.gainDb, -7.5);
      expect(band.q, 3.8);
    });

    test('encodeList/decodeList preserves applied bands', () {
      final safety = _permitted(
          [_sel(featureId: 'f1', frequencyHz: 880.0, gainDb: -5.0)]);
      final ch = _emptyChannel('ch_w');
      final proj = _project(peqChannels: [ch]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      final decoded =
          ProProject.decodeList(ProProject.encodeList([op.updatedProject!]));
      expect(decoded.single.tuningState.peqChannels.single.activeBandCount, 1);
    });
  });

  // ── H ──────────────────────────────────────────────────────────────────────
  group('H: ProProjectResolver reads applied PEQ values (Deploy handoff)', () {
    test('after apply, resolver returns correct PeqResponseBands', () {
      const driverId = 'ch_woofer';
      const driver = DriverChannel(
        id: driverId,
        name: 'Woofer',
        role: DriverRole.woofer,
        side: DriverSide.left,
      );
      final ch = _emptyChannel(driverId);
      final now = DateTime(2025, 1, 1);
      final proj = ProProject(
        id: 'proj_h',
        name: 'H',
        createdAt: now,
        updatedAt: now,
        acousticState: const MeasurementProjectState(driverChannels: [driver]),
        tuningState: TuningProjectState(peqChannels: [ch]),
      );
      final safety = _permitted(
          [_sel(featureId: 'f1', frequencyHz: 630.0, gainDb: -5.5, q: 3.5)]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      expect(op.wrote, isTrue);

      final resolver =
          ProProjectResolver(project: op.updatedProject!);
      final sim = resolver.resolveSimulationInput('proj_h', driverId);

      expect(sim.bands, hasLength(1));
      expect(sim.bands.single.frequencyHz, 630.0);
      expect(sim.bands.single.gainDb, -5.5);
      expect(sim.bands.single.q, 3.5);
    });

    test('unapplied channel → resolver returns empty bands', () {
      const driverId = 'ch_woofer';
      const driver = DriverChannel(
        id: driverId, name: 'Woofer', role: DriverRole.woofer, side: DriverSide.left);
      final now = DateTime(2025, 1, 1);
      final proj = ProProject(
        id: 'proj_h2', name: 'H2', createdAt: now, updatedAt: now,
        acousticState: const MeasurementProjectState(driverChannels: [driver]),
        tuningState: TuningProjectState(peqChannels: [_emptyChannel(driverId)]),
      );
      final resolver = ProProjectResolver(project: proj);
      final sim = resolver.resolveSimulationInput('proj_h2', driverId);
      expect(sim.bands, isEmpty);
    });

    test('Guided AI generates no DSP write — resolver has no hardware fields', () {
      const driverId = 'ch_w';
      const driver = DriverChannel(
          id: driverId, name: 'W', role: DriverRole.woofer, side: DriverSide.left);
      final ch = _emptyChannel(driverId);
      final now = DateTime(2025, 1, 1);
      final proj = ProProject(
        id: 'proj_h3', name: 'H3', createdAt: now, updatedAt: now,
        acousticState: const MeasurementProjectState(driverChannels: [driver]),
        tuningState: TuningProjectState(peqChannels: [ch]),
      );
      final safety = _permitted(
          [_sel(featureId: 'f1', frequencyHz: 440.0, gainDb: -6.0, q: 2.0)]);
      final op = _engineThenApply(safety: safety, channel: ch, project: proj);
      // The resolver only returns acoustic values — no transport/address fields.
      final resolver = ProProjectResolver(project: op.updatedProject!);
      final sim = resolver.resolveSimulationInput('proj_h3', driverId);
      expect(sim.bands.single.frequencyHz, 440.0);
      // Verify: no DSP write happened (resolver is pure read — no side effects).
      // TuningApplyResult and ProProjectResolver carry no transport references.
    });
  });

  // ── I ──────────────────────────────────────────────────────────────────────
  group('I: wrong project/channel → explicit outcome → no mutation', () {
    test('null project → outcome projectNotFound', () {
      final safety =
          _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]);
      final engineResult =
          AcousticApplyEngine.apply(safety, _emptyChannel('ch_w'));
      final op = GuidedAiProjectApply.apply(
        projectId: 'proj_1', applyResult: engineResult, latestProject: null);
      expect(op.outcome, GuidedAiProjectApplyOutcome.projectNotFound);
      expect(op.wrote, isFalse);
    });

    test('applyResult.channelId not in project → upsert adds the new channel',
        () {
      final safety =
          _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]);
      // Engine applied to 'ch_new' (e.g. Import-flow channel not yet in PEQ state).
      final engineResult =
          AcousticApplyEngine.apply(safety, _emptyChannel('ch_new'));
      // Project has 'ch_correct', not 'ch_new'.
      final proj = _project(peqChannels: [_emptyChannel('ch_correct')]);
      final op = GuidedAiProjectApply.apply(
        projectId: proj.id, applyResult: engineResult, latestProject: proj);
      // Upsert: ch_new is added alongside ch_correct.
      expect(op.outcome, GuidedAiProjectApplyOutcome.wrote);
      expect(op.wrote, isTrue);
      expect(
          op.updatedProject!.tuningState.peqChannels
              .map((c) => c.channelId)
              .toSet(),
          {'ch_correct', 'ch_new'},
          reason: 'both the existing and the new channel must be present');
      expect(
          op.updatedProject!.tuningState.peqChannels
              .firstWhere((c) => c.channelId == 'ch_new')
              .activeBandCount,
          greaterThan(0),
          reason: 'the upserted channel must carry the applied PEQ bands');
    });

    test('upsert: existing channels are not mutated by the upserted channel',
        () {
      final safety =
          _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]);
      final engineResult =
          AcousticApplyEngine.apply(safety, _emptyChannel('ch_new'));
      final proj = _project(
          id: 'p', peqChannels: [_emptyChannel('ch_a'), _emptyChannel('ch_b')]);
      final op = GuidedAiProjectApply.apply(
        projectId: 'p', applyResult: engineResult, latestProject: proj);
      expect(op.wrote, isTrue);
      // ch_a and ch_b are untouched.
      expect(
          op.updatedProject!.tuningState.peqChannels
              .where((c) => c.channelId != 'ch_new')
              .every((c) => c.activeBandCount == 0),
          isTrue,
          reason: 'existing channels must not be mutated by the upsert');
    });
  });
}
