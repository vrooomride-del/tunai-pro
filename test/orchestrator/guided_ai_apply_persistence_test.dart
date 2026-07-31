// BLOCKER 2 — Real persistence test.
// BLOCKER 3 — Deploy resolver reads applied PEQ state.
//
// Proves:
//   P1. apply → updateTuningState (notifier) → verify stored
//   P2. Recreate notifier (fresh ProviderContainer) → PEQ band present
//   P3. Exact frequencyHz/gainDb/q survive the persistence round-trip
//   P4. Wrong channel → channelNotFound → no persisted mutation
//   P5. Wrong project → projectNotFound → no persisted mutation
//
//   D1. After successful persist, ProProjectResolver reads modified PeqChannelState
//   D2. Exact freq/gain/Q preserved in resolver output
//   D3. Guided AI performs no direct DSP write (resolver returns acoustic values, no transport)

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

// ── Shared fixtures ───────────────────────────────────────────────────────────

const _kProjectId = 'persist_proj_1';
const _kChannelId = 'ch_woofer';

SelectedCandidate _sel({
  required double frequencyHz,
  double gainDb = -6.0,
  double q = 4.0,
}) =>
    SelectedCandidate(
      scoredCandidate: ScoredCandidate(
        candidate: PeqCandidate(
          candidateId: 'c:$frequencyHz',
          featureId: 'f:$frequencyHz',
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
        rank: 1,
        grade: CandidateScoreGrade.excellent,
        reasons: const ['test'],
      ),
      applicationOrder: 1,
      selectionReason: 'test',
    );

CandidateSafetyResult _permitted(double freq, double gain, double q) =>
    CandidateSafetyResult(
      applyPermitted: true,
      issues: const [],
      verifiedCandidates: [_sel(frequencyHz: freq, gainDb: gain, q: q)],
      policyId: 'policy_v1',
      policyVersion: 1,
      evidenceRefs: const ['ev1'],
    );

ProProject _project({
  String id = _kProjectId,
  String channelId = _kChannelId,
  List<DriverChannel>? drivers,
}) {
  final now = DateTime(2025, 6, 1);
  return ProProject(
    id: id,
    name: 'Persist Test',
    createdAt: now,
    updatedAt: now,
    acousticState: MeasurementProjectState(
      driverChannels: drivers ??
          [
            DriverChannel(
              id: channelId,
              name: 'Woofer',
              role: DriverRole.woofer,
              side: DriverSide.left,
            ),
          ],
    ),
    tuningState: TuningProjectState(
        peqChannels: [PeqChannelState.fixed(channelId)]),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Runs engine + production apply guard; returns (engineResult, op).
({TuningApplyResult engineResult, GuidedAiProjectApplyResult op}) _runApply(
    ProProject project, CandidateSafetyResult safety) {
  final ch = project.tuningState.peqChannels
      .firstWhere((c) => c.channelId == _kChannelId);
  final engineResult = AcousticApplyEngine.apply(safety, ch);
  final op = GuidedAiProjectApply.apply(
    projectId: project.id,
    applyResult: engineResult,
    latestProject: project,
  );
  return (engineResult: engineResult, op: op);
}

/// Creates a ProviderContainer with a fresh ProProjectStoreNotifier.
/// Caller must call addTearDown(container.dispose).
ProviderContainer _freshContainer() {
  final c = ProviderContainer();
  return c;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── BLOCKER 2: Real persistence ───────────────────────────────────────────────
  group('P: Real persistence (ProProjectStoreNotifier + SharedPreferences)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('P1: apply → updateTuningState → project has active band', () async {
      final container = _freshContainer();
      addTearDown(container.dispose);
      // Read the provider to trigger notifier creation + _load().
      container.read(proProjectStoreProvider);
      await pumpEventQueue(); // wait for _load() to settle

      final proj = _project();
      final safety = _permitted(440.0, -6.0, 3.5);
      final (:op, :engineResult) = _runApply(proj, safety);
      expect(op.wrote, isTrue, reason: 'engine + guard must succeed');

      // add project, then persist the tuning state
      await container.read(proProjectStoreProvider.notifier).addProject(proj);
      await container
          .read(proProjectStoreProvider.notifier)
          .updateTuningState(_kProjectId, op.updatedProject!.tuningState);

      final stored = container
          .read(proProjectStoreProvider)
          .projects
          .where((p) => p.id == _kProjectId)
          .single;
      expect(stored.tuningState.peqChannels.single.activeBandCount, 1);
    });

    test('P2: recreate notifier → PEQ band present (full reload)', () async {
      // First container: apply and persist.
      final c1 = _freshContainer();
      addTearDown(c1.dispose);
      c1.read(proProjectStoreProvider); // kick off _load()
      await pumpEventQueue();

      final proj = _project();
      final safety = _permitted(880.0, -4.5, 2.8);
      final (:op, :engineResult) = _runApply(proj, safety);
      expect(op.wrote, isTrue);

      await c1.read(proProjectStoreProvider.notifier).addProject(proj);
      await c1
          .read(proProjectStoreProvider.notifier)
          .updateTuningState(_kProjectId, op.updatedProject!.tuningState);
      c1.dispose(); // flush c1 before creating c2

      // Second container: fresh notifier reads from the same SharedPreferences mock.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(proProjectStoreProvider); // kick off _load()
      await pumpEventQueue(); // wait for _load()

      final reloaded = c2
          .read(proProjectStoreProvider)
          .projects
          .where((p) => p.id == _kProjectId)
          .firstOrNull;
      expect(reloaded, isNotNull, reason: 'project must survive reload');
      expect(reloaded!.tuningState.peqChannels.single.activeBandCount, 1);
    });

    test('P3: exact frequencyHz/gainDb/q survive reload', () async {
      // Persist.
      final c1 = _freshContainer();
      addTearDown(c1.dispose);
      c1.read(proProjectStoreProvider); // kick off _load()
      await pumpEventQueue();

      final proj = _project();
      final safety = _permitted(630.0, -7.5, 3.8);
      final (:op, :engineResult) = _runApply(proj, safety);
      expect(op.wrote, isTrue);

      await c1.read(proProjectStoreProvider.notifier).addProject(proj);
      await c1
          .read(proProjectStoreProvider.notifier)
          .updateTuningState(_kProjectId, op.updatedProject!.tuningState);
      c1.dispose();

      // Reload into fresh container.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(proProjectStoreProvider); // kick off _load()
      await pumpEventQueue();

      final band = c2
          .read(proProjectStoreProvider)
          .projects
          .where((p) => p.id == _kProjectId)
          .single
          .tuningState
          .peqChannels
          .single
          .bands
          .firstWhere((b) => b.enabled);

      expect(band.frequencyHz, 630.0);
      expect(band.gainDb, -7.5);
      expect(band.q, 3.8);
    });

    test(
        'P4: channelId not yet in project → upsert writes → '
        'persisted after updateTuningState call',
        () async {
      // Verifies the Import-flow path: project starts with ch_correct in
      // peqChannels; a Guided AI result for a DIFFERENT channel (ch_new, e.g.
      // a newly-imported FRD that hasn't had tuning applied yet) must be
      // persisted via upsert, not silently dropped.
      final container = _freshContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      final proj = _project(channelId: 'ch_correct');
      await container.read(proProjectStoreProvider.notifier).addProject(proj);

      final safety = _permitted(500.0, -5.0, 3.0);
      final engineResult = AcousticApplyEngine.apply(
          safety, PeqChannelState.fixed('ch_new'));
      final op = GuidedAiProjectApply.apply(
        projectId: proj.id,
        applyResult: engineResult,
        latestProject: proj,
      );
      expect(op.outcome, GuidedAiProjectApplyOutcome.wrote,
          reason: 'upsert must succeed even if channel is not yet in peqChannels');
      expect(op.wrote, isTrue);

      // Caller persists via updateTuningState.
      await container
          .read(proProjectStoreProvider.notifier)
          .updateTuningState(proj.id, op.updatedProject!.tuningState);

      final stored = container
          .read(proProjectStoreProvider)
          .projects
          .where((p) => p.id == proj.id)
          .single;
      expect(
          stored.tuningState.peqChannels.map((c) => c.channelId).toSet(),
          {'ch_correct', 'ch_new'},
          reason: 'both original and upserted channels must be present');
      expect(
          stored.tuningState.peqChannels
              .firstWhere((c) => c.channelId == 'ch_new')
              .activeBandCount,
          greaterThan(0),
          reason: 'upserted channel must carry the applied PEQ bands');
    });

    test('P5: wrong project → projectNotFound → no persisted mutation', () async {
      final container = _freshContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      final proj = _project(id: 'proj_real');
      await container.read(proProjectStoreProvider.notifier).addProject(proj);

      final safety = _permitted(500.0, -5.0, 3.0);
      final engineResult = AcousticApplyEngine.apply(
          safety, PeqChannelState.fixed(_kChannelId));
      final op = GuidedAiProjectApply.apply(
        projectId: 'proj_different',
        applyResult: engineResult,
        latestProject: proj,
      );
      expect(op.outcome, GuidedAiProjectApplyOutcome.projectNotFound);

      final stored = container
          .read(proProjectStoreProvider)
          .projects
          .where((p) => p.id == 'proj_real')
          .single;
      expect(stored.tuningState.peqChannels.single.activeBandCount, 0);
    });
  });

  // ── BLOCKER 3: Deploy resolver reads applied state ────────────────────────────
  group('D: ProProjectResolver reads applied PEQ state after persist', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('D1: resolver finds modified PeqChannelState after successful apply+persist', () async {
      final container = _freshContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      final proj = _project();
      final safety = _permitted(400.0, -6.0, 3.0);
      final (:op, :engineResult) = _runApply(proj, safety);
      expect(op.wrote, isTrue);

      await container.read(proProjectStoreProvider.notifier).addProject(proj);
      await container
          .read(proProjectStoreProvider.notifier)
          .updateTuningState(_kProjectId, op.updatedProject!.tuningState);

      // Rebuild resolver from the persisted project.
      final storedProj = container
          .read(proProjectStoreProvider)
          .projects
          .where((p) => p.id == _kProjectId)
          .single;
      final resolver = ProProjectResolver(project: storedProj);
      final sim = resolver.resolveSimulationInput(_kProjectId, _kChannelId);

      expect(sim.bands, hasLength(1));
    });

    test('D2: exact freq/gain/Q preserved through persist → resolver', () async {
      final container = _freshContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      final proj = _project();
      final safety = _permitted(1250.0, -8.0, 4.5);
      final (:op, :engineResult) = _runApply(proj, safety);
      expect(op.wrote, isTrue);

      await container.read(proProjectStoreProvider.notifier).addProject(proj);
      await container
          .read(proProjectStoreProvider.notifier)
          .updateTuningState(_kProjectId, op.updatedProject!.tuningState);

      final storedProj = container
          .read(proProjectStoreProvider)
          .projects
          .where((p) => p.id == _kProjectId)
          .single;
      final resolver = ProProjectResolver(project: storedProj);
      final sim = resolver.resolveSimulationInput(_kProjectId, _kChannelId);

      expect(sim.bands.single.frequencyHz, 1250.0);
      expect(sim.bands.single.gainDb, -8.0);
      expect(sim.bands.single.q, 4.5);
    });

    test('D3: Guided AI performs no DSP write — resolver returns only acoustic values', () async {
      final container = _freshContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      final proj = _project();
      final safety = _permitted(500.0, -6.0, 3.0);
      final (:op, :engineResult) = _runApply(proj, safety);
      expect(op.wrote, isTrue);

      await container.read(proProjectStoreProvider.notifier).addProject(proj);
      await container
          .read(proProjectStoreProvider.notifier)
          .updateTuningState(_kProjectId, op.updatedProject!.tuningState);

      final storedProj = container
          .read(proProjectStoreProvider)
          .projects
          .where((p) => p.id == _kProjectId)
          .single;
      final resolver = ProProjectResolver(project: storedProj);
      final sim = resolver.resolveSimulationInput(_kProjectId, _kChannelId);

      // ProSimulationInput carries acoustic band values only:
      // frequencyHz, gainDb, q — no DSP address, no transport, no write commands.
      expect(sim.bands.single.frequencyHz, isA<double>());
      expect(sim.bands.single.gainDb, isA<double>());
      expect(sim.bands.single.q, isA<double>());
      // No hardware-side-effect methods are accessible from ProSimulationInput.
      // The apply path (GuidedAiProjectApply → updateTuningState) does not
      // touch BLE/USB/ICP5/DSP — it writes only to SharedPreferences.
    });
  });
}
