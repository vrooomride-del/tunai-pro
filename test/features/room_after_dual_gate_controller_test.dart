// Phase 3-D3A-3 — RoomMeasurementController After dual-gate controller tests.
//
// Proves capture() itself (not just setMode/startNewAfterSession) enforces
// BOTH the hardware gate and the measurement gate in After mode, and that a
// direct capture() call bypassing the UI/mode-entry checks is gated exactly
// as strictly.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/orchestrator/room_after_capture_gate.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/room_auto_peq_controller.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import '../support/capture_gate_fixtures.dart';

class _FakeMicController extends mic.MicMeasurementController {
  @override
  MeasurementInputDeviceService get inputDeviceService =>
      fakeGateInputDeviceService();

  _FakeMicController(super.ref);
  int callCount = 0;

  @override
  Future<void> startRoomMeasurement({
    required bool leftActive,
    CalibrationCurve? calibrationCurve,
    bool bleWarmup = false,
  }) async {
    callCount++;
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: const [
        {'frequency': 80.0, 'db': -1.0},
        {'frequency': 800.0, 'db': -2.0},
      ],
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

ProProject _project({String id = 'room-dual-1'}) =>
    withGateReadySetup(ProProject(
      id: id,
      name: 'Room Dual Gate Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      tuningState: TuningProjectState(peqChannels: const []),
    ));

/// A project with NO measurement setup at all — its own gate blocks
/// (setupNotChecked) independent of hardware.
ProProject _projectNoSetup({String id = 'room-dual-2'}) => ProProject(
      id: id,
      name: 'Room Dual Gate No Setup',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      tuningState: TuningProjectState(peqChannels: const []),
    );

HardwareWriteExecutionResult _verifiedResultFor(String packageId) =>
    HardwareWriteExecutionResult(
      planId: '$packageId@2026-01-01T00:00:00.000Z',
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

HardwareWriteExecutionResult _ackOnlyResultFor(String packageId) =>
    HardwareWriteExecutionResult(
      planId: '$packageId@2026-01-01T00:00:00.000Z',
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
          status: HardwareWriteOpStatus.ackOnly,
          report: null,
          message: 'ack',
        ),
      ],
    );

class _Harness {
  final ProviderContainer container;
  final _FakeMicController fakeMic;
  final String projectId;
  const _Harness(this.container, this.fakeMic, this.projectId);

  RoomMeasurementController get ctrl =>
      container.read(roomMeasurementControllerProvider(projectId).notifier);
  RoomMeasurementState get state =>
      container.read(roomMeasurementControllerProvider(projectId));

  void authorizeHardware({String packageId = 'approved-room-pkg'}) {
    container.read(roomAutoPeqControllerProvider(projectId).notifier).state =
        RoomAutoPeqState(approvedPackageId: packageId);
    container.read(lastHardwareWriteResultProvider.notifier).state =
        _verifiedResultFor(packageId);
  }

  void authorizeHardwareAckOnly({String packageId = 'approved-room-pkg'}) {
    container.read(roomAutoPeqControllerProvider(projectId).notifier).state =
        RoomAutoPeqState(approvedPackageId: packageId);
    container.read(lastHardwareWriteResultProvider.notifier).state =
        _ackOnlyResultFor(packageId);
  }

  void leaveHardwareUnauthorized() {
    container.read(roomAutoPeqControllerProvider(projectId).notifier).state =
        const RoomAutoPeqState();
    container.read(lastHardwareWriteResultProvider.notifier).state = null;
  }
}

Future<_Harness> _buildHarness(ProProject project) async {
  late _FakeMicController fakeMicInstance;
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) {
      fakeMicInstance = _FakeMicController(ref);
      return fakeMicInstance;
    }),
  ]);
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  container.read(mic.micMeasurementProvider);
  return _Harness(container, fakeMicInstance, project.id);
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

  group('Before mode never requires the hardware gate', () {
    test(
        'valid measurement gate -> capture succeeds with hardware unauthorized',
        () async {
      final h = await _buildHarness(_project());
      addTearDown(h.container.dispose);
      h.leaveHardwareUnauthorized();
      h.ctrl.markReady();
      await h.ctrl.capture();
      expect(h.fakeMic.callCount, 1);
      expect(h.state.phase, RoomMeasurementPhaseUi.captured);
    });
  });

  group('After: dual gate enforcement in capture()', () {
    test('hardware only PASS, measurement setup FAIL -> recorder 0', () async {
      final h = await _buildHarness(_projectNoSetup());
      addTearDown(h.container.dispose);
      h.authorizeHardware();
      // Force into After mode directly (bypassing setMode's own entry gate)
      // to prove capture() re-checks fresh, not just mode-entry.
      h.container
          .read(roomMeasurementControllerProvider(h.projectId).notifier)
          .state = const RoomMeasurementState(
        mode: RoomMeasurementPhase.after,
        phase: RoomMeasurementPhaseUi.ready,
      );

      await h.ctrl.capture();

      expect(h.fakeMic.callCount, 0);
      expect(h.state.phase, RoomMeasurementPhaseUi.ready);
      expect(h.state.error, isNotNull);
      expect(
          h.state.afterCaptureGate!
              .hasBlocker(RoomAfterCaptureBlockerCode.measurementSetupBlocked),
          isTrue);
    });

    test('measurement only PASS, hardware FAIL -> recorder 0', () async {
      final h = await _buildHarness(_project());
      addTearDown(h.container.dispose);
      h.leaveHardwareUnauthorized();
      h.container
          .read(roomMeasurementControllerProvider(h.projectId).notifier)
          .state = const RoomMeasurementState(
        mode: RoomMeasurementPhase.after,
        phase: RoomMeasurementPhaseUi.ready,
      );

      await h.ctrl.capture();

      expect(h.fakeMic.callCount, 0);
      expect(
          h.state.afterCaptureGate!
              .hasBlocker(RoomAfterCaptureBlockerCode.correctionNotApproved),
          isTrue);
    });

    test('both PASS -> normal capture proceeds', () async {
      final h = await _buildHarness(_project());
      addTearDown(h.container.dispose);
      h.authorizeHardware();
      h.container
          .read(roomMeasurementControllerProvider(h.projectId).notifier)
          .state = const RoomMeasurementState(
        mode: RoomMeasurementPhase.after,
        phase: RoomMeasurementPhaseUi.ready,
      );

      await h.ctrl.capture();

      expect(h.fakeMic.callCount, 1);
      expect(h.state.phase, RoomMeasurementPhaseUi.captured);
      expect(h.state.afterCaptureGate!.canCapture, isTrue);
    });

    test('stale hardware result (mismatched package) -> recorder 0', () async {
      final h = await _buildHarness(_project());
      addTearDown(h.container.dispose);
      h.authorizeHardware(packageId: 'approved-pkg');
      // Overwrite with a result for a DIFFERENT plan — simulates a stale/
      // rollback/cross-project result landing in the shared provider.
      h.container.read(lastHardwareWriteResultProvider.notifier).state =
          _verifiedResultFor('some-other-pkg');
      h.container
          .read(roomMeasurementControllerProvider(h.projectId).notifier)
          .state = const RoomMeasurementState(
        mode: RoomMeasurementPhase.after,
        phase: RoomMeasurementPhaseUi.ready,
      );

      await h.ctrl.capture();

      expect(h.fakeMic.callCount, 0);
      expect(
          h.state.afterCaptureGate!
              .hasBlocker(RoomAfterCaptureBlockerCode.staleHardwareResult),
          isTrue);
    });

    test('ackOnly (not readback-verified) -> recorder 0', () async {
      final h = await _buildHarness(_project());
      addTearDown(h.container.dispose);
      h.authorizeHardwareAckOnly();
      h.container
          .read(roomMeasurementControllerProvider(h.projectId).notifier)
          .state = const RoomMeasurementState(
        mode: RoomMeasurementPhase.after,
        phase: RoomMeasurementPhaseUi.ready,
      );

      await h.ctrl.capture();

      expect(h.fakeMic.callCount, 0);
      expect(
          h.state.afterCaptureGate!
              .hasBlocker(RoomAfterCaptureBlockerCode.hardwareWriteNotVerified),
          isTrue);
    });

    test(
        'direct controller call bypass: capture() blocked even though mode '
        'was forced to after without ever calling setMode()', () async {
      final h = await _buildHarness(_project());
      addTearDown(h.container.dispose);
      h.leaveHardwareUnauthorized();
      // Never called setMode(after) or startNewAfterSession() — this proves
      // the P0 fix: capture() itself is the authority, not mode-entry alone.
      h.container
          .read(roomMeasurementControllerProvider(h.projectId).notifier)
          .state = const RoomMeasurementState(
        mode: RoomMeasurementPhase.after,
        phase: RoomMeasurementPhaseUi.ready,
      );

      await h.ctrl.capture();

      expect(h.fakeMic.callCount, 0);
      expect(h.state.phase, RoomMeasurementPhaseUi.ready);
    });

    test('runtime setup expiring just before capture -> recorder 0', () async {
      final h = await _buildHarness(_project());
      addTearDown(h.container.dispose);
      h.authorizeHardware();
      // Clear the setup readiness right before capture — simulates it
      // expiring/being invalidated between mode-entry and the Capture press.
      await h.container
          .read(proProjectStoreProvider.notifier)
          .updateSetupReadiness(h.projectId, null);
      h.container
          .read(roomMeasurementControllerProvider(h.projectId).notifier)
          .state = const RoomMeasurementState(
        mode: RoomMeasurementPhase.after,
        phase: RoomMeasurementPhaseUi.ready,
      );

      await h.ctrl.capture();

      expect(h.fakeMic.callCount, 0);
      expect(
          h.state.afterCaptureGate!
              .hasBlocker(RoomAfterCaptureBlockerCode.measurementSetupBlocked),
          isTrue);
    });
  });
}
