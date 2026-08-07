// Phase 2 — RoomMeasurementController tests.
//
// Same fake-mic-at-the-public-API-boundary pattern as
// live_measurement_controller_test.dart (real record/just_audio plugins have
// no test fake; startRoomMeasurement is overridden instead).
//
// What's tested:
//  1. capture() calls MicMeasurementController.startRoomMeasurement() with
//     leftActive matching the current step
//  2. BLE active -> bleWarmup=true
//  3. Accept (Before) writes leftSystemFrd / rightSystemFrd, never
//     driverChannels[i].frdData
//  4. Accept preserves the other side + the whole tuningState/driverChannels
//  5. Before/After stored separately
//  6. retry() persists nothing
//  7. Closed loop: After 1/2 evaluates 0 times
//  8. Closed loop: After 2/2 evaluates exactly 1 time, decision present
//  9. Closed loop: mismatched projectId is rejected (returns null)
// 10. Existing project decode compatibility (roomState defaults empty)

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/orchestrator/room_closed_loop.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/room_auto_peq_controller.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import '../support/capture_gate_fixtures.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeMicController extends mic.MicMeasurementController {
  // Capture is gated (Phase 3-D3): the gate's runtime preflight asks this
  // service for permission + a fresh device list. Serve the known-good chain
  // the shared fixtures seed, so these tests exercise capture mechanics
  // rather than re-testing the gate.
  @override
  MeasurementInputDeviceService get inputDeviceService =>
      fakeGateInputDeviceService();

  _FakeMicController(super.ref);
  bool? lastLeftActive;
  bool? lastBleWarmup;
  int callCount = 0;
  List<Map<String, double>> nextResponse = const [
    {'frequency': 60.0, 'db': -3.0},
    {'frequency': 500.0, 'db': -1.0},
    {'frequency': 5000.0, 'db': -2.0},
  ];

  @override
  Future<void> startRoomMeasurement({
    required bool leftActive,
    CalibrationCurve? calibrationCurve,
    bool bleWarmup = false,
  }) async {
    callCount++;
    lastLeftActive = leftActive;
    lastBleWarmup = bleWarmup;
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: nextResponse,
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

ProProject _project({String id = 'room-proj-1'}) =>
    withGateReadySetup(ProProject(
      id: id,
      name: 'Room Test Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      tuningState: TuningProjectState(peqChannels: const [
        PeqChannelState(channelId: 'ch_wf_l', bands: [
          PeqBand(id: 'existing-band', frequencyHz: 500, gainDb: -2.0, q: 1.2),
        ]),
      ]),
    ));

ParsedMeasurementData _frd(String id, {double magBase = -1.0}) =>
    ParsedMeasurementData(
      id: id,
      sourceFileName: '$id.frd',
      fileType: AcousticFileType.frd,
      importedAt: DateTime.utc(2025, 1, 1),
      points: [
        for (var f = 20.0; f <= 2000; f *= 1.3)
          MeasurementDataPoint(frequencyHz: f, magnitudeDb: magBase),
      ],
    );

RoomSystemMeasurement _measurement({
  required RoomSystemSide side,
  required RoomMeasurementPhase phase,
  required String projectId,
  double magBase = -1.0,
}) =>
    RoomSystemMeasurement(
      side: side,
      phase: phase,
      frd: _frd('${side.name}_${phase.name}', magBase: magBase),
      capturedAt: DateTime.utc(2025, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: projectId,
    );

/// A HardwareWriteExecutionResult that RoomAfterGate accepts: planId
/// prefix-matches [packageId] and every op is DSP-readback-verified
/// (allReadbackVerified), not merely ack-only.
HardwareWriteExecutionResult _verifiedResultFor(String packageId) =>
    HardwareWriteExecutionResult(
      planId: '$packageId@2025-01-01T00:00:00.000Z',
      executed: true,
      rejectionReason: null,
      outcomes: [
        const HardwareWriteOpOutcome(
          op: HardwareWriteOp(
            channelId: 'ch_wf_l',
            parameterKind: HardwareParamKind.peqGain,
            bandIndex: 0,
            targetValue: -1.0,
            verification: HardwareParamVerification.captureProven,
            writable: true,
            reason: 'test',
          ),
          status: HardwareWriteOpStatus.written,
          report: null,
          message: 'ok',
        ),
      ],
    );

// ── Harness ───────────────────────────────────────────────────────────────────

class _Harness {
  final ProviderContainer container;
  final _FakeMicController fakeMic;
  const _Harness(this.container, this.fakeMic);

  ProProject get project => container
      .read(proProjectStoreProvider)
      .projects
      .firstWhere((p) => p.id == 'room-proj-1');

  RoomMeasurementController get ctrl =>
      container.read(roomMeasurementControllerProvider('room-proj-1').notifier);

  RoomMeasurementState get state =>
      container.read(roomMeasurementControllerProvider('room-proj-1'));

  /// Satisfies RoomAfterGate as if a real Room Auto PEQ correction had
  /// already been approved and DSP-readback-verified for this project — the
  /// only way setMode(RoomMeasurementPhase.after) proceeds after the safety
  /// audit fix. Tests that only care about After-mode capture/accept/closed
  /// -loop behavior call this first so they aren't also (accidentally)
  /// re-testing the gate itself.
  void authorizeAfterMode({String packageId = 'approved-room-pkg'}) {
    container
        .read(roomAutoPeqControllerProvider('room-proj-1').notifier)
        .state = RoomAutoPeqState(approvedPackageId: packageId);
    container.read(lastHardwareWriteResultProvider.notifier).state =
        _verifiedResultFor(packageId);
  }
}

Future<_Harness> _buildHarness({ProProject? seedProject}) async {
  late _FakeMicController fakeMicInstance;
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) {
      fakeMicInstance = _FakeMicController(ref);
      return fakeMicInstance;
    }),
  ]);
  addTearDown(container.dispose);
  await container
      .read(proProjectStoreProvider.notifier)
      .addProject(seedProject ?? _project());
  container.read(mic.micMeasurementProvider);
  return _Harness(container, fakeMicInstance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  const justAudioChannel = MethodChannel('com.ryanheise.just_audio.methods');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(justAudioChannel, (call) async => null);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(justAudioChannel, null);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. capture() invokes startRoomMeasurement with correct side', () {
    test('Left step -> leftActive=true', () async {
      final h = await _buildHarness();
      h.ctrl.markReady();
      await h.ctrl.capture();
      expect(h.fakeMic.callCount, 1);
      expect(h.fakeMic.lastLeftActive, isTrue);
    });

    test('Right step (after Left accepted) -> leftActive=false', () async {
      final h = await _buildHarness();
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();
      h.ctrl.markReady();
      await h.ctrl.capture();
      expect(h.fakeMic.callCount, 2);
      expect(h.fakeMic.lastLeftActive, isFalse);
    });
  });

  group('2. BLE warm-up propagation', () {
    test('no active BLE/USB context -> bleWarmup=false', () async {
      final h = await _buildHarness();
      h.ctrl.markReady();
      await h.ctrl.capture();
      expect(h.fakeMic.lastBleWarmup, isFalse);
    });
  });

  group('3-4. Accept storage', () {
    test('Before Left accept writes roomState.before.leftSystemFrd only',
        () async {
      final h = await _buildHarness();
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      final room = h.project.roomState;
      expect(room.before.leftSystemFrd, isNotNull);
      expect(room.before.rightSystemFrd, isNull);
      expect(room.after.leftSystemFrd, isNull);
    });

    test('driverChannels FRD and existing PEQ bands are untouched', () async {
      final h = await _buildHarness();
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      expect(
          h.project.acousticState.driverChannels
              .every((ch) => !ch.hasParsedFrd),
          isTrue,
          reason: 'Room capture must never write driverChannels[i].frdData.');
      final peq = h.project.tuningState.peqChannels
          .firstWhere((c) => c.channelId == 'ch_wf_l');
      expect(peq.bands.single.id, 'existing-band');
    });

    test('accepting Right preserves Left in the same snapshot', () async {
      final h = await _buildHarness();
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      final room = h.project.roomState;
      expect(room.before.leftSystemFrd, isNotNull);
      expect(room.before.rightSystemFrd, isNotNull);
      expect(room.before.isComplete, isTrue);
    });
  });

  group('5. Before/After stored separately', () {
    test('After accept never touches roomState.before', () async {
      final beforeRoom = RoomMeasurementProjectState(
        before: RoomMeasurementSnapshot(
          leftSystemFrd: _measurement(
              side: RoomSystemSide.left,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1'),
          rightSystemFrd: _measurement(
              side: RoomSystemSide.right,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1'),
        ),
      );
      final seed = _project().copyWith(roomState: beforeRoom);
      final h = await _buildHarness(seedProject: seed);

      h.authorizeAfterMode();
      h.ctrl.setMode(RoomMeasurementPhase.after);
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      final room = h.project.roomState;
      expect(room.before.leftSystemFrd!.frd.id,
          beforeRoom.before.leftSystemFrd!.frd.id);
      expect(room.after.leftSystemFrd, isNotNull);
      expect(room.after.rightSystemFrd, isNull);
    });
  });

  group('6. retry() persists nothing', () {
    test('retry after capture does not write roomState', () async {
      final h = await _buildHarness();
      h.ctrl.markReady();
      await h.ctrl.capture();
      h.ctrl.retry();
      expect(h.project.roomState.before.leftSystemFrd, isNull);
      expect(h.state.stepIndex, 0);
    });
  });

  group('7-9. Closed loop evaluation', () {
    test('After 1/2 does not evaluate (closedLoopResult stays null)', () async {
      final beforeRoom = RoomMeasurementProjectState(
        before: RoomMeasurementSnapshot(
          leftSystemFrd: _measurement(
              side: RoomSystemSide.left,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1'),
          rightSystemFrd: _measurement(
              side: RoomSystemSide.right,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1'),
        ),
      );
      final seed = _project().copyWith(roomState: beforeRoom);
      final h = await _buildHarness(seedProject: seed);
      h.authorizeAfterMode();
      h.ctrl.setMode(RoomMeasurementPhase.after);
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      expect(h.state.closedLoopResult, isNull);
    });

    test('After 2/2 evaluates exactly once with a decision', () async {
      final beforeRoom = RoomMeasurementProjectState(
        before: RoomMeasurementSnapshot(
          leftSystemFrd: _measurement(
              side: RoomSystemSide.left,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1',
              magBase: -6.0),
          rightSystemFrd: _measurement(
              side: RoomSystemSide.right,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1',
              magBase: -6.0),
        ),
      );
      final seed = _project().copyWith(roomState: beforeRoom);
      final h = await _buildHarness(seedProject: seed);
      h.authorizeAfterMode();
      h.ctrl.setMode(RoomMeasurementPhase.after);
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();
      expect(h.state.closedLoopResult, isNull); // 1/2 still
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      expect(h.state.closedLoopResult, isNotNull);
      expect(h.state.closedLoopResult!.left.decision, isNotNull);
      expect(h.state.closedLoopResult!.right.decision, isNotNull);
    });

    test('RoomClosedLoopEvaluator rejects mismatched projectId', () {
      final before = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(
            side: RoomSystemSide.left,
            phase: RoomMeasurementPhase.before,
            projectId: 'proj-a'),
        rightSystemFrd: _measurement(
            side: RoomSystemSide.right,
            phase: RoomMeasurementPhase.before,
            projectId: 'proj-a'),
      );
      final after = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(
            side: RoomSystemSide.left,
            phase: RoomMeasurementPhase.after,
            projectId: 'proj-B-mismatch'),
        rightSystemFrd: _measurement(
            side: RoomSystemSide.right,
            phase: RoomMeasurementPhase.after,
            projectId: 'proj-a'),
      );
      final result = RoomClosedLoopEvaluator.evaluate(
        projectId: 'proj-a',
        before: before,
        after: after,
      );
      expect(result, isNull);
    });

    test('RoomClosedLoopEvaluator returns null when After is 1/2', () {
      final before = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(
            side: RoomSystemSide.left,
            phase: RoomMeasurementPhase.before,
            projectId: 'proj-a'),
        rightSystemFrd: _measurement(
            side: RoomSystemSide.right,
            phase: RoomMeasurementPhase.before,
            projectId: 'proj-a'),
      );
      final after = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(
            side: RoomSystemSide.left,
            phase: RoomMeasurementPhase.after,
            projectId: 'proj-a'),
      );
      final result = RoomClosedLoopEvaluator.evaluate(
        projectId: 'proj-a',
        before: before,
        after: after,
      );
      expect(result, isNull);
    });
  });

  group('11. Closed loop re-entry guard (safety audit)', () {
    Future<_Harness> completedCycleHarness() async {
      final beforeRoom = RoomMeasurementProjectState(
        before: RoomMeasurementSnapshot(
          leftSystemFrd: _measurement(
              side: RoomSystemSide.left,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1',
              magBase: -6.0),
          rightSystemFrd: _measurement(
              side: RoomSystemSide.right,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1',
              magBase: -6.0),
        ),
      );
      final seed = _project().copyWith(roomState: beforeRoom);
      final h = await _buildHarness(seedProject: seed);
      h.authorizeAfterMode();
      h.ctrl.setMode(RoomMeasurementPhase.after);
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();
      expect(h.state.closedLoopResult, isNotNull,
          reason: 'harness precondition: a completed, evaluated cycle');
      return h;
    }

    test(
        're-tapping setMode(after) after a completed cycle does not '
        'silently reset stepIndex / discard the evaluation', () async {
      final h = await completedCycleHarness();
      final priorResult = h.state.closedLoopResult;
      final priorStepIndex = h.state.stepIndex;

      h.ctrl.setMode(RoomMeasurementPhase.after);

      expect(h.state.closedLoopResult, same(priorResult),
          reason: 'A completed evaluation must not be silently discarded.');
      expect(h.state.stepIndex, priorStepIndex,
          reason: 'setMode(after) must refuse to reset stepIndex once the '
              'cycle is already complete and evaluated.');
    });

    test('afterReentryBlockedReason is non-null once a cycle is complete',
        () async {
      final h = await completedCycleHarness();
      expect(h.ctrl.afterReentryBlockedReason, isNotNull);
    });

    test(
        'startNewAfterSession() is the only way to begin a new After '
        'capture — resets stepIndex and clears the prior evaluation', () async {
      final h = await completedCycleHarness();

      await h.ctrl.startNewAfterSession();

      expect(h.state.stepIndex, 0);
      expect(h.state.closedLoopResult, isNull);
      expect(h.ctrl.afterReentryBlockedReason, isNull);
    });

    test(
        'a fresh startNewAfterSession() capture cycle re-evaluates exactly '
        'once (not silently skipped)', () async {
      final h = await completedCycleHarness();
      await h.ctrl.startNewAfterSession();

      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();
      expect(h.state.closedLoopResult, isNull); // 1/2 in the new session
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      expect(h.state.closedLoopResult, isNotNull);
    });

    test('startNewAfterSession() itself is still hardware-gated', () async {
      final beforeRoom = RoomMeasurementProjectState(
        before: RoomMeasurementSnapshot(
          leftSystemFrd: _measurement(
              side: RoomSystemSide.left,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1'),
          rightSystemFrd: _measurement(
              side: RoomSystemSide.right,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1'),
        ),
      );
      final seed = _project().copyWith(roomState: beforeRoom);
      final h = await _buildHarness(seedProject: seed);
      // No authorizeAfterMode() call — hardware was never actually written.

      await h.ctrl.startNewAfterSession();

      expect(h.state.mode, RoomMeasurementPhase.before,
          reason: 'Must fail closed exactly like setMode(after) does.');
    });
  });

  group('10. Existing project JSON decode compatibility', () {
    test('project JSON without roomState decodes to empty Room state', () {
      final legacyJson = _project().toJson()..remove('roomState');
      final decoded = ProProject.fromJson(legacyJson);
      expect(decoded.roomState.before.isComplete, isFalse);
      expect(decoded.roomState.after.isComplete, isFalse);
      expect(decoded.tuningState.peqChannels, isNotEmpty);
    });

    test(
        'full Before+After+cycleId round-trip survives save/reload '
        '(safety audit coverage gap)', () {
      final withCycle = _measurement(
        side: RoomSystemSide.left,
        phase: RoomMeasurementPhase.after,
        projectId: 'room-proj-1',
      );
      final measurementWithCycleId = RoomSystemMeasurement(
        side: withCycle.side,
        phase: withCycle.phase,
        frd: withCycle.frd,
        capturedAt: withCycle.capturedAt,
        sampleRate: withCycle.sampleRate,
        source: withCycle.source,
        projectId: withCycle.projectId,
        cycleId: 'cycle-42',
      );
      final full = RoomMeasurementProjectState(
        before: RoomMeasurementSnapshot(
          leftSystemFrd: _measurement(
              side: RoomSystemSide.left,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1'),
          rightSystemFrd: _measurement(
              side: RoomSystemSide.right,
              phase: RoomMeasurementPhase.before,
              projectId: 'room-proj-1'),
        ),
        after: RoomMeasurementSnapshot(
          leftSystemFrd: measurementWithCycleId,
          rightSystemFrd: _measurement(
              side: RoomSystemSide.right,
              phase: RoomMeasurementPhase.after,
              projectId: 'room-proj-1'),
        ),
      );
      final seed = _project().copyWith(roomState: full);

      final roundTripped = ProProject.fromJson(seed.toJson());

      expect(roundTripped.roomState.before.isComplete, isTrue);
      expect(roundTripped.roomState.after.isComplete, isTrue);
      expect(roundTripped.roomState.before.leftSystemFrd!.frd.id,
          full.before.leftSystemFrd!.frd.id);
      expect(roundTripped.roomState.after.rightSystemFrd!.frd.id,
          full.after.rightSystemFrd!.frd.id);
      expect(roundTripped.roomState.after.leftSystemFrd!.cycleId, 'cycle-42');
      expect(roundTripped.roomState.after.rightSystemFrd!.cycleId, isNull);
      // driverChannels/tuningState round-trip unaffected by roomState.
      expect(roundTripped.tuningState.peqChannels, isNotEmpty);
    });
  });
}
