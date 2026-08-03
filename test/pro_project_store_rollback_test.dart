// Phase 4-C-3B: ProProjectStoreNotifier.rollbackTuningState — software-only
// rollback of a worsened Guided AI correction cycle. Covers: exact tuning
// restoration, forward-only tuningRevision, deploy/export staleness
// invalidation, hardware-adjacent fields left untouched, correctionCycles
// history preserved, and double-tap protection.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_deploy_package_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

void main() {
  const pid = 'proj-rollback';
  final now = DateTime(2026, 8, 1);

  TuningProjectState currentTuning() => TuningProjectState(
        peqChannels: [
          PeqChannelState(channelId: 'ch_tw_l', bands: const [
            PeqBand(
                id: 'cur0',
                type: PeqBandType.peak,
                frequencyHz: 4000,
                gainDb: 3.0,
                q: 2.0),
          ]),
        ],
        crossoverChannels: const [
          CrossoverChannelState(
            channelId: 'ch_tw_l',
            polarityInverted: true,
            lowPass: CrossoverFilter(side: FilterSide.lowPass, frequencyHz: 500),
          ),
        ],
        channelControls: const [
          ChannelControlState(
            channelId: 'ch_tw_l',
            gainDb: 4.0,
            delayMs: 1.5,
            phaseOffsetDeg: 180.0,
            muted: true,
          ),
        ],
        tuningRevision: 9, // deliberately higher than the rollback snapshot's
      );

  TuningProjectState rollbackTuning() => TuningProjectState(
        peqChannels: [
          PeqChannelState(channelId: 'ch_tw_l', bands: const [
            PeqBand(
                id: 'prev0',
                type: PeqBandType.lowShelf,
                frequencyHz: 1000,
                gainDb: -2.0,
                q: 1.0),
          ]),
        ],
        crossoverChannels: const [
          CrossoverChannelState(
            channelId: 'ch_tw_l',
            polarityInverted: false,
            highPass:
                CrossoverFilter(side: FilterSide.highPass, frequencyHz: 2000),
          ),
        ],
        channelControls: const [
          ChannelControlState(
            channelId: 'ch_tw_l',
            gainDb: -1.0,
            delayMs: 0.2,
            phaseOffsetDeg: 0.0,
            muted: false,
          ),
        ],
        tuningRevision: 2, // an old, low revision — must never be reused
      );

  CorrectionCycle worsenedCycle({TuningProjectState? rollback}) =>
      CorrectionCycle(
        projectId: pid,
        channelId: 'full_system',
        cycleNumber: 1,
        beforeMeasurementRef: 'before-ref',
        peqSnapshot: PeqChannelState.empty('ch_tw_l'),
        afterMeasurementRef: 'after-ref',
        decision: CorrectionCycleDecision.worsened,
        createdAt: now,
        completedAt: now,
        rollbackTuningState: rollback ?? rollbackTuning(),
      );

  DeployPackageSnapshot snapshot() => DeployPackageSnapshot(
        projectId: pid,
        projectName: 'Test',
        projectStatus: 'Tuned',
        createdAt: now,
      );

  DeployPackage deployPkg(String id, DeployPackageStatus status) =>
      DeployPackage(
        id: id,
        version: 'v0.0.1',
        name: 'Package $id',
        kind: DeployPackageKind.fullProjectSnapshot,
        status: status,
        readinessLevel: DeployReadinessLevel.readyForReview,
        createdAt: now,
        updatedAt: now,
        snapshot: snapshot(),
      );

  DspExportPackage exportPkg(String id, ExportStatus status) =>
      DspExportPackage(id: id, status: status, tuningRevision: 9);

  ProProject baseProject({
    ProfileStatus profileStatus = ProfileStatus.verified,
    SafetyStatus safetyStatus = SafetyStatus.verified,
    List<CorrectionCycle> correctionCycles = const [],
    DeployProjectState? deployState,
    ExportProjectState? exportState,
  }) =>
      ProProject(
        id: pid,
        name: 'Rollback Test',
        createdAt: now,
        updatedAt: now,
        profileStatus: profileStatus,
        safetyStatus: safetyStatus,
        tuningState: currentTuning(),
        correctionCycles: correctionCycles,
        deployState: deployState ?? DeployProjectState(),
        exportState: exportState ?? ExportProjectState(),
      );

  Future<ProviderContainer> seededContainer(ProProject project) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    container.read(proProjectStoreProvider);
    await pumpEventQueue();
    await container.read(proProjectStoreProvider.notifier).addProject(project);
    return container;
  }

  ProProject readBack(ProviderContainer c) => c
      .read(proProjectStoreProvider)
      .projects
      .firstWhere((p) => p.id == pid);

  group('rollbackTuningState — restore exactness', () {
    test('restores every pre-apply field exactly (PEQ/XO/gain/delay/mute/'
        'phase), not the current values', () async {
      final cycle = worsenedCycle();
      final container = await seededContainer(baseProject());
      addTearDown(container.dispose);

      final ok = await container
          .read(proProjectStoreProvider.notifier)
          .rollbackTuningState(pid, cycle);
      expect(ok, isTrue);

      final restored = readBack(container).tuningState;
      final expected = cycle.rollbackTuningState!;

      expect(restored.peqChannels.single.bands.single.toJson(),
          expected.peqChannels.single.bands.single.toJson());
      expect(restored.crossoverChannels.single.toJson(),
          expected.crossoverChannels.single.toJson());
      final rc = restored.channelControls.single;
      final ec = expected.channelControls.single;
      expect(rc.gainDb, ec.gainDb);
      expect(rc.delayMs, ec.delayMs);
      expect(rc.muted, ec.muted);
      expect(rc.phaseOffsetDeg, ec.phaseOffsetDeg);

      // Sanity: these must NOT equal the pre-rollback current values.
      final current = currentTuning();
      expect(restored.peqChannels.single.bands.single.toJson(),
          isNot(current.peqChannels.single.bands.single.toJson()));
    });
  });

  group('rollbackTuningState — revision handling', () {
    test('tuningRevision is bumped forward from the CURRENT revision, never '
        "reused from the rollback snapshot's own (older) revision", () async {
      final cycle = worsenedCycle();
      final container = await seededContainer(baseProject());
      addTearDown(container.dispose);

      await container
          .read(proProjectStoreProvider.notifier)
          .rollbackTuningState(pid, cycle);

      final newRevision = readBack(container).tuningState.tuningRevision;
      expect(newRevision, currentTuning().tuningRevision + 1,
          reason: 'must be current+1');
      expect(newRevision, isNot(cycle.rollbackTuningState!.tuningRevision),
          reason: "must not reuse the snapshot's own older revision");
      expect(newRevision, greaterThan(cycle.rollbackTuningState!.tuningRevision));
    });
  });

  group('rollbackTuningState — deploy/export staleness invalidation', () {
    test('ready/exported deploy packages and draftReady/exported export '
        'packages are marked stale; draft/blocked/archived/notReady are not',
        () async {
      final deployState = DeployProjectState(packages: [
        deployPkg('d-ready', DeployPackageStatus.ready),
        deployPkg('d-exported', DeployPackageStatus.exported),
        deployPkg('d-draft', DeployPackageStatus.draft),
        deployPkg('d-blocked', DeployPackageStatus.blocked),
        deployPkg('d-archived', DeployPackageStatus.archived),
      ]);
      final exportState = ExportProjectState(packages: [
        exportPkg('e-draftready', ExportStatus.draftReady),
        exportPkg('e-exported', ExportStatus.exported),
        exportPkg('e-notready', ExportStatus.notReady),
        exportPkg('e-blocked', ExportStatus.blocked),
      ]);

      final container = await seededContainer(baseProject(
        deployState: deployState,
        exportState: exportState,
      ));
      addTearDown(container.dispose);

      await container
          .read(proProjectStoreProvider.notifier)
          .rollbackTuningState(pid, worsenedCycle());

      final result = readBack(container);
      DeployPackageStatus deployStatus(String id) =>
          result.deployState.packages.firstWhere((p) => p.id == id).status;
      ExportStatus exportStatusOf(String id) =>
          result.exportState.packages.firstWhere((p) => p.id == id).status;

      expect(deployStatus('d-ready'), DeployPackageStatus.stale);
      expect(deployStatus('d-exported'), DeployPackageStatus.stale);
      expect(deployStatus('d-draft'), DeployPackageStatus.draft);
      expect(deployStatus('d-blocked'), DeployPackageStatus.blocked);
      expect(deployStatus('d-archived'), DeployPackageStatus.archived);

      expect(exportStatusOf('e-draftready'), ExportStatus.stale);
      expect(exportStatusOf('e-exported'), ExportStatus.stale);
      expect(exportStatusOf('e-notready'), ExportStatus.notReady);
      expect(exportStatusOf('e-blocked'), ExportStatus.blocked);
    });
  });

  group('rollbackTuningState — hardware untouched', () {
    test('deployState.appliedGainsByChannel (the hardware-ACK record) is '
        'never modified by a software-only rollback', () async {
      final deployState = DeployProjectState(
        appliedGainsByChannel: const {'ch_tw_l': -3.5, 'ch_wf_l': -1.0},
      );
      final container =
          await seededContainer(baseProject(deployState: deployState));
      addTearDown(container.dispose);

      await container
          .read(proProjectStoreProvider.notifier)
          .rollbackTuningState(pid, worsenedCycle());

      expect(readBack(container).deployState.appliedGainsByChannel,
          {'ch_tw_l': -3.5, 'ch_wf_l': -1.0},
          reason: 'hardware-ACK gains must survive a software-only rollback '
              'unchanged — this method performs no hardware I/O');
    });

    test('safetyStatus resets to notVerified; profileStatus steps back to '
        'tuned only when it was verified/deployed', () async {
      final container = await seededContainer(baseProject(
        profileStatus: ProfileStatus.deployed,
        safetyStatus: SafetyStatus.verified,
      ));
      addTearDown(container.dispose);

      await container
          .read(proProjectStoreProvider.notifier)
          .rollbackTuningState(pid, worsenedCycle());

      final result = readBack(container);
      expect(result.safetyStatus, SafetyStatus.notVerified);
      expect(result.profileStatus, ProfileStatus.tuned);
    });

    test('profileStatus is left unchanged when it was not verified/deployed '
        '(e.g. draft/measured)', () async {
      final container = await seededContainer(baseProject(
        profileStatus: ProfileStatus.measured,
      ));
      addTearDown(container.dispose);

      await container
          .read(proProjectStoreProvider.notifier)
          .rollbackTuningState(pid, worsenedCycle());

      expect(readBack(container).profileStatus, ProfileStatus.measured);
    });
  });

  group('rollbackTuningState — correctionCycles history preserved', () {
    test('the worsened cycle (and any other history) remains in '
        'correctionCycles, unmodified, after rollback', () async {
      final cycle = worsenedCycle();
      final unrelated = CorrectionCycle(
        projectId: pid,
        channelId: 'full_system',
        cycleNumber: 0,
        beforeMeasurementRef: 'other-before',
        peqSnapshot: PeqChannelState.empty('ch_tw_l'),
        decision: CorrectionCycleDecision.improvedAndComplete,
        createdAt: now,
      );
      final container = await seededContainer(
          baseProject(correctionCycles: [unrelated, cycle]));
      addTearDown(container.dispose);

      await container
          .read(proProjectStoreProvider.notifier)
          .rollbackTuningState(pid, cycle);

      final history = readBack(container).correctionCycles;
      expect(history.length, 2);
      expect(history[0].cycleNumber, 0);
      expect(history[1].cycleNumber, 1);
      expect(history[1].decision, CorrectionCycleDecision.worsened);
      expect(history[1].rollbackTuningState!.toJson(),
          cycle.rollbackTuningState!.toJson(),
          reason: 'the persisted worsened cycle record itself must not be '
              'rewritten by the rollback it enables');
    });
  });

  group('rollbackTuningState — guard clauses', () {
    test('returns false and makes no change for a non-worsened decision',
        () async {
      final improved = CorrectionCycle(
        projectId: pid,
        channelId: 'full_system',
        cycleNumber: 1,
        beforeMeasurementRef: 'ref',
        peqSnapshot: PeqChannelState.empty('ch_tw_l'),
        decision: CorrectionCycleDecision.improvedAndComplete,
        createdAt: now,
        rollbackTuningState: rollbackTuning(), // hypothetically present
      );
      final container = await seededContainer(baseProject());
      addTearDown(container.dispose);

      final ok = await container
          .read(proProjectStoreProvider.notifier)
          .rollbackTuningState(pid, improved);

      expect(ok, isFalse);
      expect(readBack(container).tuningState.tuningRevision,
          currentTuning().tuningRevision);
    });

    test('returns false when rollbackTuningState is null', () async {
      final noRollback = CorrectionCycle(
        projectId: pid,
        channelId: 'full_system',
        cycleNumber: 1,
        beforeMeasurementRef: 'ref',
        peqSnapshot: PeqChannelState.empty('ch_tw_l'),
        decision: CorrectionCycleDecision.worsened,
        createdAt: now,
      );
      final container = await seededContainer(baseProject());
      addTearDown(container.dispose);

      final ok = await container
          .read(proProjectStoreProvider.notifier)
          .rollbackTuningState(pid, noRollback);

      expect(ok, isFalse);
    });
  });

  group('rollbackTuningState — double-tap protection', () {
    test('two calls fired back-to-back (before the first awaits) result in '
        'exactly one applied rollback, not a double revision bump', () async {
      final cycle = worsenedCycle();
      final container = await seededContainer(baseProject());
      addTearDown(container.dispose);
      final notifier = container.read(proProjectStoreProvider.notifier);

      // Fire both synchronously, without awaiting the first — this is the
      // scenario that would double-apply without the in-flight guard.
      final f1 = notifier.rollbackTuningState(pid, cycle);
      final f2 = notifier.rollbackTuningState(pid, cycle);
      final results = await Future.wait([f1, f2]);

      expect(results, containsAll([true, false]),
          reason: 'exactly one call should have actually applied the '
              'rollback; the other must no-op');
      expect(results.where((r) => r).length, 1);

      final newRevision = readBack(container).tuningState.tuningRevision;
      expect(newRevision, currentTuning().tuningRevision + 1,
          reason: 'revision must be bumped exactly once, not twice');
    });
  });
}
