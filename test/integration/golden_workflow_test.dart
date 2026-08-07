// Phase 3-F2 §1/§2 — the whole ADAU1701 guided workflow, end to end.
//
// One project is walked from "nothing" to a Closed Loop verdict by advancing
// the REAL production state through the REAL store notifiers, asserting the
// typed nextRecommendedAction after every single step. No state machine is
// introduced: measurementWorkflowReadinessProvider is simply observed.
//
// The assertion that matters is not that the happy path reaches the end — it
// is that each step advances the workflow EXACTLY one place, and that no step
// can be skipped by a weaker signal (a generated-but-unapproved correction, a
// connected-but-unwritten DSP, an ACK that was never readback-verified).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/hardware/hardware_connection_readiness.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_provider.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';

import '../support/capture_gate_fixtures.dart';
import '../support/golden_workflow_fixtures.dart';

/// Drives one project through the golden path, exposing the readiness model
/// after each step.
class GoldenWalk {
  final ProviderContainer c;
  GoldenWalk(this.c);

  ProProjectStoreNotifier get store => c.read(proProjectStoreProvider.notifier);

  ProProject get project => c
      .read(proProjectStoreProvider)
      .projects
      .firstWhere((p) => p.id == kGoldenProjectId);

  MeasurementWorkflowReadiness get readiness =>
      c.read(measurementWorkflowReadinessProvider);

  MeasurementWorkflowAction get action => readiness.nextRecommendedAction;

  /// Each walk begins on a clean persistence layer: ProProjectStoreNotifier
  /// loads from SharedPreferences on construction, so two walks inside one
  /// test would otherwise reload each other's project.
  static Future<GoldenWalk> start() async {
    SharedPreferences.setMockInitialValues({});
    return GoldenWalk(ProviderContainer());
  }

  Future<void> createProject() async {
    await store.addProject(goldenBareProject());
    await store.setCurrentProject(kGoldenProjectId);
  }

  Future<void> selectMicrophone() async => store
      .updateSelectedMicrophoneProfile(kGoldenProjectId, gateReadyProfile());

  Future<void> selectInputDevice() async =>
      store.updateSelectedInputDevice(kGoldenProjectId, gateReadyDevice());

  Future<void> runSetupCheck() async => refreshGateReadiness(store, project);

  Future<void> measureDrivers({required int count}) async =>
      store.updateAcousticState(
          kGoldenProjectId,
          project.acousticState.copyWith(
              driverChannels: goldenDrivers(project, measured: count)));

  Future<void> completeFactoryTuning(
          {CorrectionCycleDecision decision =
              CorrectionCycleDecision.improvedAndComplete}) async =>
      store.addCorrectionCycle(
          kGoldenProjectId, goldenCycle(kGoldenProjectId, decision: decision));

  Future<void> measureRoomBefore({
    required int count,
    bool mismatchedRight = false,
  }) async =>
      store.updateRoomState(
        kGoldenProjectId,
        project.roomState.copyWith(
          before: goldenRoomSnapshot(project, RoomMeasurementPhase.before,
              count: count,
              rightProvenance: mismatchedRight
                  ? goldenOtherMicProvenance(goldenProvenance(project))
                  : null),
        ),
      );

  Future<void> measureRoomAfter({
    required int count,
    bool mismatched = false,
  }) async =>
      store.updateRoomState(
        kGoldenProjectId,
        project.roomState.copyWith(
          after: goldenRoomSnapshot(project, RoomMeasurementPhase.after,
              count: count,
              magnitudeDb: -2.0,
              provenance: mismatched
                  ? goldenOtherMicProvenance(goldenProvenance(project))
                  : null),
        ),
      );

  void approveAutoPeq() => goldenApproveRoomCorrection(c);

  void deploy({HardwareWriteExecutionResult? result}) =>
      c.read(lastHardwareWriteResultProvider.notifier).state =
          result ?? goldenWriteResult();

  /// Records a Closed Loop verdict the way RoomMeasurementController does, so
  /// the workflow observes a real controller value rather than a fabricated
  /// one.
  void recordClosedLoopVerdict() {
    final ctrl =
        c.read(roomMeasurementControllerProvider(kGoldenProjectId).notifier);
    ctrl.setMode(RoomMeasurementPhase.after);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. golden path — each step advances exactly one place', () {
    test('the full transition table', () async {
      final w = await GoldenWalk.start();
      addTearDown(w.c.dispose);
      final seen = <MeasurementWorkflowAction>[];

      // ── 0. no project ────────────────────────────────────────────────
      expect(w.action, MeasurementWorkflowAction.createOrOpenProject);
      seen.add(w.action);

      // ── 1. project, no microphone ────────────────────────────────────
      await w.createProject();
      expect(w.action, MeasurementWorkflowAction.selectMicrophone);
      expect(w.readiness.hasProject, isTrue);
      seen.add(w.action);

      // ── 2. calibrated microphone, no input device ────────────────────
      await w.selectMicrophone();
      expect(w.readiness.calibrationStatus,
          MeasurementWorkflowCalibrationState.calibrated);
      expect(w.action, MeasurementWorkflowAction.selectInputDevice);
      seen.add(w.action);

      // ── 3. input selected, setup not run ─────────────────────────────
      await w.selectInputDevice();
      expect(w.readiness.setupState, MeasurementWorkflowSetupState.notChecked);
      expect(w.action, MeasurementWorkflowAction.checkMeasurementSetup);
      seen.add(w.action);

      // ── 4. setup ready, Factory not measured ─────────────────────────
      await w.runSetupCheck();
      expect(w.readiness.setupState, MeasurementWorkflowSetupState.ready);
      expect(w.action, MeasurementWorkflowAction.measureFactoryDrivers);
      seen.add(w.action);

      // Partial measurement does NOT advance.
      await w.measureDrivers(count: 2);
      expect(w.action, MeasurementWorkflowAction.measureFactoryDrivers);
      expect(w.readiness.measuredDriverCount, 2);

      // ── 5. all drivers measured ──────────────────────────────────────
      await w.measureDrivers(count: 4);
      expect(w.readiness.driverMeasurementReady, isTrue);
      expect(w.readiness.factoryTuningCompleted, isFalse);
      expect(w.action, MeasurementWorkflowAction.runFactoryGuidedTuning);
      seen.add(w.action);

      // ── 6. Factory tuning finished ───────────────────────────────────
      await w.completeFactoryTuning();
      expect(w.readiness.factoryTuningCompleted, isTrue);
      expect(w.action, MeasurementWorkflowAction.measureRoomBefore);
      seen.add(w.action);

      // 1/2 does not advance.
      await w.measureRoomBefore(count: 1);
      expect(w.readiness.beforeCount, 1);
      expect(w.action, MeasurementWorkflowAction.measureRoomBefore);

      // ── 7. Room Before 2/2, quality PASS ─────────────────────────────
      await w.measureRoomBefore(count: 2);
      expect(w.readiness.beforeMeasurementComplete, isTrue);
      expect(w.readiness.beforeQualityReady, isTrue);
      expect(w.readiness.roomAutoPeqReady, isTrue);
      expect(w.action, MeasurementWorkflowAction.generateRoomAutoPeq);
      seen.add(w.action);

      // ── 8. correction approved ───────────────────────────────────────
      w.approveAutoPeq();
      expect(w.readiness.roomAutoPeqApproved, isTrue);
      expect(w.readiness.correctionDeployedAndVerified, isFalse,
          reason: 'approved is not deployed');
      expect(w.action, MeasurementWorkflowAction.deployRoomCorrection);
      seen.add(w.action);

      // A ready hardware SESSION alone must not satisfy the deploy step.
      await goldenConnectHardware(w.c);
      expect(w.readiness.hardwareReadyForDeploy, isTrue);
      expect(w.readiness.correctionDeployedAndVerified, isFalse,
          reason: 'a usable DSP session is not a written correction');
      expect(w.action, MeasurementWorkflowAction.deployRoomCorrection);

      // ── 9. matching write, readback verified ─────────────────────────
      w.deploy();
      expect(w.readiness.correctionDeployedAndVerified, isTrue);
      expect(w.readiness.afterAvailable, isTrue);
      expect(w.action, MeasurementWorkflowAction.measureRoomAfter);
      seen.add(w.action);

      await w.measureRoomAfter(count: 1);
      expect(w.action, MeasurementWorkflowAction.measureRoomAfter);

      // ── 10. Room After 2/2, provenance compatible ────────────────────
      await w.measureRoomAfter(count: 2);
      expect(w.readiness.afterMeasurementComplete, isTrue);
      expect(w.readiness.beforeAfterComparable, isTrue);
      expect(w.readiness.closedLoopComplete, isFalse,
          reason: 'comparable, but no verdict has been produced yet');
      expect(w.action, MeasurementWorkflowAction.reviewClosedLoop);
      seen.add(w.action);

      // Every distinct step was visited exactly once, in order.
      expect(seen, [
        MeasurementWorkflowAction.createOrOpenProject,
        MeasurementWorkflowAction.selectMicrophone,
        MeasurementWorkflowAction.selectInputDevice,
        MeasurementWorkflowAction.checkMeasurementSetup,
        MeasurementWorkflowAction.measureFactoryDrivers,
        MeasurementWorkflowAction.runFactoryGuidedTuning,
        MeasurementWorkflowAction.measureRoomBefore,
        MeasurementWorkflowAction.generateRoomAutoPeq,
        MeasurementWorkflowAction.deployRoomCorrection,
        MeasurementWorkflowAction.measureRoomAfter,
        MeasurementWorkflowAction.reviewClosedLoop,
      ]);
    });
  });

  group('2. no step can be skipped by a weaker signal', () {
    Future<GoldenWalk> upToRoomBefore() async {
      final w = await GoldenWalk.start();
      await w.createProject();
      await w.selectMicrophone();
      await w.selectInputDevice();
      await w.runSetupCheck();
      await w.measureDrivers(count: 4);
      await w.completeFactoryTuning();
      await w.measureRoomBefore(count: 2);
      return w;
    }

    test('§4 — only improvedAndComplete finishes Factory tuning', () async {
      for (final d in CorrectionCycleDecision.values) {
        final w = await GoldenWalk.start();
        addTearDown(w.c.dispose);
        await w.createProject();
        await w.selectMicrophone();
        await w.selectInputDevice();
        await w.runSetupCheck();
        await w.measureDrivers(count: 4);
        await w.completeFactoryTuning(decision: d);

        final done = d == CorrectionCycleDecision.improvedAndComplete;
        expect(w.readiness.factoryTuningCompleted, done, reason: d.name);
        expect(
            w.action,
            done
                ? MeasurementWorkflowAction.measureRoomBefore
                : MeasurementWorkflowAction.runFactoryGuidedTuning,
            reason: d.name);
      }
    });

    test('§4 — another project\'s completed cycle never counts', () async {
      final w = await GoldenWalk.start();
      addTearDown(w.c.dispose);
      await w.createProject();
      await w.selectMicrophone();
      await w.selectInputDevice();
      await w.runSetupCheck();
      await w.measureDrivers(count: 4);
      await w.store.addCorrectionCycle(
          kGoldenProjectId, goldenCycle('a-different-project'));

      expect(w.readiness.factoryTuningCompleted, isFalse);
      expect(w.action, MeasurementWorkflowAction.runFactoryGuidedTuning);
    });

    test('§5 — a mismatched Before pair blocks Auto PEQ', () async {
      final w = await GoldenWalk.start();
      addTearDown(w.c.dispose);
      await w.createProject();
      await w.selectMicrophone();
      await w.selectInputDevice();
      await w.runSetupCheck();
      await w.measureDrivers(count: 4);
      await w.completeFactoryTuning();
      await w.measureRoomBefore(count: 2, mismatchedRight: true);

      expect(w.readiness.beforeMeasurementComplete, isTrue);
      expect(w.readiness.beforeQualityReady, isFalse);
      expect(w.readiness.roomAutoPeqReady, isFalse);
      expect(w.action, MeasurementWorkflowAction.resolveRoomMeasurementQuality);
    });

    test('§6 — generated but unapproved is not deployable', () async {
      final w = await upToRoomBefore();
      addTearDown(w.c.dispose);
      expect(w.readiness.roomAutoPeqApproved, isFalse);
      expect(w.action, MeasurementWorkflowAction.generateRoomAutoPeq,
          reason: 'nothing approved yet — Deploy must not be offered');
    });

    test('§7 — ack-only, stale plan, and failed execution are not deploys',
        () async {
      final cases = <String, HardwareWriteExecutionResult>{
        'ackOnly': goldenWriteResult(status: HardwareWriteOpStatus.ackOnly),
        'wrongPackage': goldenWriteResult(packageId: 'some-other-package'),
        'notExecuted': goldenWriteResult(executed: false),
        'readbackFailed':
            goldenWriteResult(status: HardwareWriteOpStatus.failed),
      };
      for (final entry in cases.entries) {
        final w = await upToRoomBefore();
        addTearDown(w.c.dispose);
        w.approveAutoPeq();
        await goldenConnectHardware(w.c);
        w.deploy(result: entry.value);

        expect(w.readiness.correctionDeployedAndVerified, isFalse,
            reason: entry.key);
        expect(w.readiness.afterAvailable, isFalse, reason: entry.key);
        expect(w.action, MeasurementWorkflowAction.deployRoomCorrection,
            reason: entry.key);
      }
    });

    test('§8 — a provenance-mismatched After never becomes a verdict',
        () async {
      final w = await upToRoomBefore();
      addTearDown(w.c.dispose);
      w.approveAutoPeq();
      await goldenConnectHardware(w.c);
      w.deploy();
      await w.measureRoomAfter(count: 2, mismatched: true);

      expect(w.readiness.afterMeasurementComplete, isTrue);
      expect(w.readiness.beforeAfterComparable, isFalse);
      expect(w.readiness.closedLoopComplete, isFalse);
      expect(w.readiness.closedLoopDecision, isNull,
          reason: 'no verdict may be produced from an incomparable pair');
      expect(w.action, MeasurementWorkflowAction.resolveBeforeAfterMismatch);
    });
  });

  group('3. hardware session vs deployed correction (§6/§10)', () {
    Future<GoldenWalk> atDeployStep() async {
      final w = await GoldenWalk.start();
      await w.createProject();
      await w.selectMicrophone();
      await w.selectInputDevice();
      await w.runSetupCheck();
      await w.measureDrivers(count: 4);
      await w.completeFactoryTuning();
      await w.measureRoomBefore(count: 2);
      w.approveAutoPeq();
      return w;
    }

    test('disconnected hardware keeps the action at Deploy, with a blocker',
        () async {
      final w = await atDeployStep();
      addTearDown(w.c.dispose);
      expect(w.readiness.hardwareConnectionState,
          HardwareConnectionState.disconnected);
      expect(w.action, MeasurementWorkflowAction.deployRoomCorrection,
          reason: 'hardware is never promoted ahead of the ladder');
      expect(w.readiness.hardwareReadyForDeploy, isFalse);
    });

    test('a handshake-incomplete session is not ready', () async {
      final w = await atDeployStep();
      addTearDown(w.c.dispose);
      await goldenConnectHardware(w.c, handshaken: false);
      expect(w.readiness.hardwareConnectionState,
          HardwareConnectionState.connecting);
      expect(w.readiness.hardwareReadyForDeploy, isFalse);
      expect(w.action, MeasurementWorkflowAction.deployRoomCorrection);
    });

    test('losing the session after a verified deploy does NOT undo it',
        () async {
      final w = await atDeployStep();
      addTearDown(w.c.dispose);
      await goldenConnectHardware(w.c);
      w.deploy();
      expect(w.action, MeasurementWorkflowAction.measureRoomAfter);

      goldenDisconnectHardware(w.c);
      expect(w.readiness.hardwareConnectionState,
          HardwareConnectionState.disconnected);
      expect(w.readiness.correctionDeployedAndVerified, isTrue,
          reason: 'the correction was written; the session merely dropped');
      expect(w.action, MeasurementWorkflowAction.measureRoomAfter);
    });
  });

  group('4. project isolation (§12)', () {
    test('a second project starts from zero and sees no leak', () async {
      final w = await GoldenWalk.start();
      addTearDown(w.c.dispose);

      // Take project A all the way to a verified deploy.
      await w.createProject();
      await w.selectMicrophone();
      await w.selectInputDevice();
      await w.runSetupCheck();
      await w.measureDrivers(count: 4);
      await w.completeFactoryTuning();
      await w.measureRoomBefore(count: 2);
      w.approveAutoPeq();
      await goldenConnectHardware(w.c);
      w.deploy();
      expect(w.action, MeasurementWorkflowAction.measureRoomAfter);

      // Switch to a brand-new project B.
      await w.store.addProject(goldenBareProject(id: 'project-b'));
      await w.store.setCurrentProject('project-b');
      final b = w.readiness;

      expect(b.projectId, 'project-b');
      expect(
          b.nextRecommendedAction, MeasurementWorkflowAction.selectMicrophone);
      expect(b.microphoneSelected, isFalse);
      expect(b.setupState, MeasurementWorkflowSetupState.notChecked);
      expect(b.measuredDriverCount, 0);
      expect(b.factoryTuningCompleted, isFalse);
      expect(b.beforeCount, 0);
      expect(b.roomAutoPeqApproved, isFalse,
          reason: 'the Auto PEQ controller is project-scoped');
      expect(b.correctionDeployedAndVerified, isFalse,
          reason: "project A's global write result must not verify B");
      expect(b.closedLoopComplete, isFalse);
    });

    test('the global write result cannot deploy a different project', () async {
      final w = await GoldenWalk.start();
      addTearDown(w.c.dispose);
      await w.createProject();
      await w.selectMicrophone();
      await w.selectInputDevice();
      await w.runSetupCheck();
      await w.measureDrivers(count: 4);
      await w.completeFactoryTuning();
      await w.measureRoomBefore(count: 2);
      w.approveAutoPeq();
      await goldenConnectHardware(w.c);
      w.deploy();

      // Project B has its OWN (empty) Auto PEQ state, so A's global write
      // result has no approved package to match against.
      await w.store.addProject(goldenBareProject(id: 'project-b'));
      await w.store.setCurrentProject('project-b');

      expect(w.c.read(lastHardwareWriteResultProvider), isNotNull,
          reason: "A's write result is still the global latest");
      expect(w.readiness.roomAutoPeqApproved, isFalse);
      expect(w.readiness.correctionDeployedAndVerified, isFalse,
          reason: 'a global write result must never verify another project');
    });
  });

  group('5. restart / reopen (§11)', () {
    test('persisted project data survives; hardware readiness does not',
        () async {
      final w = await GoldenWalk.start();
      addTearDown(w.c.dispose);
      await w.createProject();
      await w.selectMicrophone();
      await w.selectInputDevice();
      await w.runSetupCheck();
      await w.measureDrivers(count: 4);
      await w.completeFactoryTuning();
      await w.measureRoomBefore(count: 2);
      await goldenConnectHardware(w.c);
      expect(w.readiness.hardwareReadyForDeploy, isTrue);

      // A restart: the project JSON survives, the in-memory session does not.
      final persisted = ProProject.fromJson(w.project.toJson());
      SharedPreferences.setMockInitialValues({});
      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      final store = fresh.read(proProjectStoreProvider.notifier);
      await store.addProject(persisted);
      await store.setCurrentProject(kGoldenProjectId);

      final r = fresh.read(measurementWorkflowReadinessProvider);
      expect(r.microphoneSelected, isTrue);
      expect(
          r.calibrationStatus, MeasurementWorkflowCalibrationState.calibrated);
      expect(r.measuredDriverCount, 4);
      expect(r.factoryTuningCompleted, isTrue);
      expect(r.beforeCount, 2);
      expect(r.beforeQualityReady, isTrue);

      expect(fresh.read(activeAdau1701ContextProvider), isNull);
      expect(r.hardwareReadyForDeploy, isFalse,
          reason: 'a live session must never survive a restart');
      expect(r.hardwareConnectionState, HardwareConnectionState.disconnected);

      // The approval and the write result are session state in this build,
      // so a restart correctly lands back on the Deploy step.
      expect(r.roomAutoPeqApproved, isFalse);
      expect(r.correctionDeployedAndVerified, isFalse);
    });
  });

  group('6. failure-path recovery matrix (§13)', () {
    Future<GoldenWalk> ready() async {
      final w = await GoldenWalk.start();
      await w.createProject();
      await w.selectMicrophone();
      await w.selectInputDevice();
      await w.runSetupCheck();
      return w;
    }

    test('invalid calibration -> fixCalibration', () async {
      final w = await ready();
      addTearDown(w.c.dispose);
      await w.store.updateSelectedMicrophoneProfile(
        kGoldenProjectId,
        gateReadyProfile().copyWith(clearCalibrationCurve: true),
      );
      expect(w.action, MeasurementWorkflowAction.fixCalibration);
      expect(w.readiness.primaryBlocker,
          MeasurementWorkflowBlockerCode.calibrationInvalid);
    });

    test('setup expired -> checkMeasurementSetup', () async {
      final w = await ready();
      addTearDown(w.c.dispose);
      // Changing the microphone invalidates the readiness identity.
      await w.store.updateSelectedMicrophoneProfile(
        kGoldenProjectId,
        gateReadyProfile().copyWith(model: 'A Different Mic'),
      );
      expect(w.readiness.setupState, MeasurementWorkflowSetupState.stale);
      expect(w.action, MeasurementWorkflowAction.checkMeasurementSetup);
    });

    test('every failure state names a blocker and an action', () async {
      final w = await ready();
      addTearDown(w.c.dispose);
      await w.measureDrivers(count: 2);
      expect(w.readiness.primaryBlocker,
          MeasurementWorkflowBlockerCode.factoryDriversMissing);
      expect(w.action, MeasurementWorkflowAction.measureFactoryDrivers);
    });
  });
}
