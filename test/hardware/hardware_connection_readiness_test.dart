// Phase 3-F1 §11 — ADAU1701 hardware connection readiness.
//
// The property that matters most here is that nothing reads as ready without
// the FULL existing contract holding: a live session object, a completed
// identity handshake, and this project's own persisted confirmation. A
// transport that merely exists, or a persisted flag that survived a restart,
// must never be enough — that is exactly how a stale "connected" reaches a
// deploy screen.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/hardware/hardware_connection_provider.dart';
import 'package:tunai_pro/core/hardware/hardware_connection_readiness.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_provider.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';

HardwareConnectionReadiness _eval({
  String? target = 'ADAU1701',
  bool hasLiveContext = false,
  bool liveContextReady = false,
  String? transportKind = 'icp5',
  bool persistedConnected = false,
  bool persistedError = false,
}) =>
    HardwareConnectionEvaluator.evaluate(
      projectDspTarget: target,
      hasLiveContext: hasLiveContext,
      liveContextReady: liveContextReady,
      transportKind: transportKind,
      persistedConnected: persistedConnected,
      persistedError: persistedError,
    );

/// A fully connected, handshaken, identified ADAU1701 session.
HardwareConnectionReadiness _ready() => _eval(
    hasLiveContext: true, liveContextReady: true, persistedConnected: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. pure readiness', () {
    test('no project target -> unknown, not disconnected', () {
      final r = _eval(target: null);
      expect(r.state, HardwareConnectionState.unknown);
      expect(r.connectedTriState, isNull,
          reason: '"nobody checked" must never read as "disconnected"');
      expect(r.blocker, HardwareReadinessBlocker.noProject);
    });

    test('ADAU1701 project with no session -> disconnected', () {
      final r = _eval();
      expect(r.state, HardwareConnectionState.disconnected);
      expect(r.blocker, HardwareReadinessBlocker.notConnected);
      expect(r.readyForDeploy, isFalse);
      expect(r.transportKind, isNull, reason: 'no session, no transport');
    });

    test('a session that has not handshaken -> connecting', () {
      final r = _eval(hasLiveContext: true, liveContextReady: false);
      expect(r.state, HardwareConnectionState.connecting);
      expect(r.blocker, HardwareReadinessBlocker.handshakeIncomplete);
      expect(r.readyForDeploy, isFalse);
      expect(r.handshakeVerified, isFalse);
    });

    test(
        'handshaken but no persisted identity confirmation -> connected, '
        'NOT ready', () {
      final r = _eval(hasLiveContext: true, liveContextReady: true);
      expect(r.state, HardwareConnectionState.connected);
      expect(r.readyForDeploy, isFalse);
      expect(r.handshakeVerified, isFalse);
      expect(r.blocker, HardwareReadinessBlocker.identityNotConfirmed);
      expect(r.connectedTriState, isTrue);
    });

    test('the full contract -> readyForDeploy', () {
      final r = _ready();
      expect(r.state, HardwareConnectionState.readyForDeploy);
      expect(r.readyForDeploy, isTrue);
      expect(r.handshakeVerified, isTrue);
      expect(r.targetCompatible, isTrue);
      expect(r.activeTarget, HardwareDspTarget.adau1701);
      expect(r.transportKind, 'icp5');
      expect(r.blocker, isNull);
    });

    test('a connection error is never ready', () {
      final r = _eval(
          hasLiveContext: true,
          liveContextReady: true,
          persistedConnected: true,
          persistedError: true);
      expect(r.state, HardwareConnectionState.error);
      expect(r.readyForDeploy, isFalse);
      expect(r.blocker, HardwareReadinessBlocker.connectionError);
    });
  });

  group('2. stale state can never remain ready', () {
    test('a persisted connected flag alone is NOT connected', () {
      // Exactly the post-restart shape: the flag survived, the session did
      // not.
      final r = _eval(persistedConnected: true);
      expect(r.state, HardwareConnectionState.disconnected);
      expect(r.readyForDeploy, isFalse);
      expect(r.handshakeVerified, isFalse);
    });

    test('losing the session (disconnect / onDone / onError) drops readiness',
        () {
      expect(_ready().readyForDeploy, isTrue);
      // The disconnect callbacks null the active context.
      final after = _eval(hasLiveContext: false, persistedConnected: true);
      expect(after.state, HardwareConnectionState.disconnected);
      expect(after.readyForDeploy, isFalse);
    });

    test('a session that drops handshake falls back to connecting', () {
      final r = _eval(
          hasLiveContext: true,
          liveContextReady: false,
          persistedConnected: true);
      expect(r.state, HardwareConnectionState.connecting);
      expect(r.readyForDeploy, isFalse);
    });
  });

  group('3. project compatibility (§3/§10)', () {
    test('ADAU1466 project + ADAU1701 session -> incompatible, never ready',
        () {
      final r = _eval(
          target: 'ADAU1466',
          hasLiveContext: true,
          liveContextReady: true,
          persistedConnected: true);
      expect(r.state, HardwareConnectionState.incompatible);
      expect(r.readyForDeploy, isFalse);
      expect(r.targetCompatible, isFalse);
      expect(r.blocker, HardwareReadinessBlocker.targetMismatch);
      expect(r.projectTarget, HardwareDspTarget.adau1466);
      expect(r.activeTarget, HardwareDspTarget.adau1701);
    });

    test('ADAU1466 project with no session -> unknown, not disconnected', () {
      final r = _eval(target: 'ADAU1466');
      expect(r.state, HardwareConnectionState.unknown);
      expect(r.blocker, HardwareReadinessBlocker.targetNotSupported,
          reason: 'no ADAU1466 runtime path exists yet — that is not a '
              'failed connection');
      expect(r.connectedTriState, isNull);
    });

    test('an unrecognised target is never optimistically treated as 1701', () {
      final r = _eval(
          target: 'Sigma DSP Custom',
          hasLiveContext: true,
          liveContextReady: true,
          persistedConnected: true);
      expect(r.projectTarget, HardwareDspTarget.other);
      expect(r.readyForDeploy, isFalse);
      expect(r.state, HardwareConnectionState.incompatible);
    });

    test('target parsing tolerates formatting', () {
      for (final t in ['ADAU1701', 'adau-1701', 'ADAU 1701']) {
        expect(HardwareDspTarget.parse(t), HardwareDspTarget.adau1701,
            reason: t);
      }
      expect(HardwareDspTarget.parse(null), HardwareDspTarget.other);
    });
  });

  group('4. derived provider (§6)', () {
    ProProject project(String id, {String target = 'ADAU1701'}) => ProProject(
          id: id,
          name: 'HW $id',
          dspTarget: target,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );

    Future<ProviderContainer> seed(List<ProProject> projects,
        {String? current}) async {
      final c = ProviderContainer();
      for (final p in projects) {
        await c.read(proProjectStoreProvider.notifier).addProject(p);
      }
      if (current != null) {
        await c
            .read(proProjectStoreProvider.notifier)
            .setCurrentProject(current);
      }
      return c;
    }

    test('reads existing production state, with no session open', () async {
      final c = await seed([project('p1')], current: 'p1');
      addTearDown(c.dispose);
      final r = c.read(hardwareConnectionReadinessProvider);
      expect(r.state, HardwareConnectionState.disconnected);
      expect(c.read(activeAdau1701ContextProvider), isNull,
          reason: 'the provider must not open anything itself');
    });

    test('an unhandshaken live context reads as connecting, not ready',
        () async {
      final c = await seed([project('p1')], current: 'p1');
      addTearDown(c.dispose);

      // A real context around a real (unconnected) transport: the object
      // exists, so "a transport is non-null" is NOT enough to be ready.
      final ctx = Adau1701HardwareContext.fromTransport(Icp5UsbTransport());
      c.read(activeAdau1701ContextProvider.notifier).state = ctx;

      final r = c.read(hardwareConnectionReadinessProvider);
      expect(ctx.isReady, isFalse);
      expect(r.state, HardwareConnectionState.connecting);
      expect(r.readyForDeploy, isFalse);
    });

    test('project switch recomputes and leaks nothing', () async {
      final c = await seed([project('p1'), project('p2', target: 'ADAU1466')],
          current: 'p1');
      addTearDown(c.dispose);
      expect(c.read(hardwareConnectionReadinessProvider).projectTarget,
          HardwareDspTarget.adau1701);

      await c.read(proProjectStoreProvider.notifier).setCurrentProject('p2');
      final r = c.read(hardwareConnectionReadinessProvider);
      expect(r.projectTarget, HardwareDspTarget.adau1466);
      expect(r.state, HardwareConnectionState.unknown,
          reason: "the previous project's ADAU1701 verdict must not carry "
              'over');
    });

    test('the per-project family scopes to the id it is given', () async {
      final c = await seed([project('p1'), project('p2', target: 'ADAU1466')],
          current: 'p1');
      addTearDown(c.dispose);
      expect(
          c
              .read(hardwareConnectionReadinessForProjectProvider('p2'))
              .projectTarget,
          HardwareDspTarget.adau1466);
      expect(
          c
              .read(hardwareConnectionReadinessForProjectProvider('missing'))
              .state,
          HardwareConnectionState.unknown);
    });
  });

  group('5. workflow integration (§7/§9)', () {
    Future<ProviderContainer> seedWorkflow({String target = 'ADAU1701'}) async {
      final c = ProviderContainer();
      await c.read(proProjectStoreProvider.notifier).addProject(ProProject(
            id: 'wf',
            name: 'WF',
            dspTarget: target,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ));
      await c.read(proProjectStoreProvider.notifier).setCurrentProject('wf');
      return c;
    }

    test('hardware state is populated on the workflow model', () async {
      final c = await seedWorkflow();
      addTearDown(c.dispose);
      final r = c.read(measurementWorkflowReadinessProvider);
      expect(r.hardwareConnectionState, HardwareConnectionState.disconnected);
      expect(r.hardwareTargetCompatible, isTrue);
      expect(r.hardwareReadyForDeploy, isFalse);
      expect(r.hardwareConnected, isFalse);
    });

    test('not-ready hardware does not block early measurement steps', () async {
      final c = await seedWorkflow();
      addTearDown(c.dispose);
      final r = c.read(measurementWorkflowReadinessProvider);
      expect(r.hardwareReadyForDeploy, isFalse);
      expect(
          r.nextRecommendedAction, MeasurementWorkflowAction.selectMicrophone,
          reason: 'hardware must never be promoted ahead of measurement '
              'setup in the ladder');
    });

    test('ready hardware NEVER implies a correction was deployed', () {
      // The two are computed from entirely different inputs and must stay
      // that way: RoomAfterGate alone proves a package was written and
      // readback-verified.
      final r = _ready();
      expect(r.readyForDeploy, isTrue);

      const workflow = MeasurementWorkflowReadiness(
        hasProject: true,
        microphoneSelected: false,
        calibrationStatus: MeasurementWorkflowCalibrationState.none,
        inputSelected: false,
        inputSelectionKind: MeasurementWorkflowInputSelectionKind.none,
        runtimeAvailabilityKnown: false,
        runtimeAvailability: MeasurementWorkflowInputAvailability.unknown,
        setupState: MeasurementWorkflowSetupState.notChecked,
        setupWarnings: [],
        requiredDriverCount: 0,
        measuredDriverCount: 0,
        driverMeasurementReady: false,
        guidedTuningReady: false,
        factoryTuningCompleted: false,
        beforeCount: 0,
        beforeMeasurementComplete: false,
        beforeQualityReady: false,
        roomAutoPeqReady: false,
        roomAutoPeqApproved: false,
        correctionDeployedAndVerified: false,
        afterAvailable: false,
        afterCount: 0,
        afterMeasurementComplete: false,
        beforeAfterComparable: false,
        closedLoopComplete: false,
        closedLoopWarnings: [],
        hardwareConnected: true,
        hardwareConnectionState: HardwareConnectionState.readyForDeploy,
        hardwareTargetCompatible: true,
        hardwareReadyForDeploy: true,
        roomCorrectionVerified: false,
        nextRecommendedAction: MeasurementWorkflowAction.deployRoomCorrection,
        warnings: [],
        stages: {},
      );
      expect(workflow.hardwareReadyForDeploy, isTrue);
      expect(workflow.correctionDeployedAndVerified, isFalse,
          reason: 'a usable session is not a written correction');
      expect(workflow.roomCorrectionVerified, isFalse);
    });
  });
}
