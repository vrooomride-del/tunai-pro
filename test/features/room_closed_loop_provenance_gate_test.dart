// Phase 3-D3C-2 §5/§9/§10/§11 — the provenance gate wired into the Room
// Closed Loop.
//
// The load-bearing assertions: a provenance-mismatched Before/After pair
// produces NO verdict at all (no improved, no worsened, no next-cycle, no
// rollback recommendation), and it does not disturb the pre-apply rollback
// snapshot — the user can simply re-measure After and get a valid comparison.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_before_after_comparison.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';

import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/features/workbench/tabs/room_auto_peq_controller.dart';

import '../support/capture_gate_fixtures.dart';

const _pid = 'room-cl-1';

class _FakeMicController extends mic.MicMeasurementController {
  _FakeMicController(super.ref);

  @override
  MeasurementInputDeviceService get inputDeviceService =>
      fakeGateInputDeviceService();

  @override
  Future<void> startRoomMeasurement({
    required bool leftActive,
    bool bleWarmup = false,
    CalibrationCurve? calibrationCurve,
  }) async {
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: const [
        {'frequency': 100.0, 'db': -3.0},
        {'frequency': 1000.0, 'db': -2.0},
      ],
      calibrationStatus: CalibrationStatus.calibrated,
      calibrationCurveChecksum: 'gate-test-curve',
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

ProProject _project() => withGateReadySetup(ProProject(
      id: _pid,
      name: 'Room CL',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ));

/// Seeds a Before pair whose provenance either matches what a live capture
/// in this project produces, or (when [mismatchedProfile]) deliberately
/// describes a different microphone.
RoomMeasurementProjectState _seededBefore({bool mismatchedProfile = false}) {
  MeasurementQualitySnapshot quality() {
    final base = MeasurementCaptureProvenanceBuilder.build(
      project: _project(),
      actualSampleRate: mic.MicMeasurementController.sampleRate,
      actualChannelCount: 1,
      now: DateTime.utc(2026, 1, 1),
    );
    final provenance = mismatchedProfile
        ? MeasurementCaptureProvenance(
            projectId: base.projectId,
            microphoneProfileChecksum: 'a-completely-different-microphone',
            calibrationCurveChecksum: base.calibrationCurveChecksum,
            calibrationAngle: base.calibrationAngle,
            inputDeviceSelectionIdentity: base.inputDeviceSelectionIdentity,
            setupReadinessGenerationId: base.setupReadinessGenerationId,
            qualityPolicyVersion: base.qualityPolicyVersion,
            actualSampleRate: base.actualSampleRate,
            actualChannelCount: base.actualChannelCount,
            capturedAt: base.capturedAt,
          )
        : base;
    return MeasurementQualitySnapshot(
      provenance: provenance,
      setupCalibrationStatus: CalibrationStatus.calibrated,
      setupNoiseFloorDbFs: -70,
      setupPeakDbFs: -6,
      setupRmsDbFs: -18,
      setupSignalToNoiseDb: 52,
      setupClippedSampleCount: 0,
      setupClippedSampleRatio: 0,
      setupCheckedAt: DateTime.utc(2026, 1, 1),
    );
  }

  ParsedMeasurementData frd(String id) => ParsedMeasurementData(
        id: id,
        sourceFileName: '$id.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2026, 1, 1),
        points: [
          for (var f = 20.0; f <= 2000; f *= 1.3)
            MeasurementDataPoint(frequencyHz: f, magnitudeDb: -6.0),
        ],
        calibrationStatus: CalibrationStatus.calibrated,
        calibrationCurveChecksum: 'gate-test-curve',
        qualitySnapshot: quality(),
        source: MeasurementDataSource.liveCapture,
      );

  RoomSystemMeasurement m(RoomSystemSide side) => RoomSystemMeasurement(
        side: side,
        phase: RoomMeasurementPhase.before,
        frd: frd('before_${side.name}'),
        capturedAt: DateTime.utc(2026, 1, 1),
        sampleRate: mic.MicMeasurementController.sampleRate,
        source: RoomMeasurementSource.live,
        projectId: _pid,
      );

  return RoomMeasurementProjectState.createDefault().copyWith(
    before: RoomMeasurementSnapshot(
        leftSystemFrd: m(RoomSystemSide.left),
        rightSystemFrd: m(RoomSystemSide.right)),
  );
}

Future<ProviderContainer> _seed({bool mismatchedProfile = false}) async {
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) => _FakeMicController(ref)),
  ]);
  await container.read(proProjectStoreProvider.notifier).addProject(_project());
  await container.read(proProjectStoreProvider.notifier).updateRoomState(
      _pid, _seededBefore(mismatchedProfile: mismatchedProfile));
  container.read(mic.micMeasurementProvider);
  return container;
}

/// Satisfies RoomAfterGate as if a Room correction had been approved and
/// DSP-readback-verified — the same technique room_measurement_controller_test
/// uses, so these tests aren't also re-testing the hardware gate.
void _authorizeAfterMode(ProviderContainer c,
    {String packageId = 'approved-room-pkg'}) {
  c.read(roomAutoPeqControllerProvider(_pid).notifier).state =
      RoomAutoPeqState(approvedPackageId: packageId);
  c.read(lastHardwareWriteResultProvider.notifier).state =
      HardwareWriteExecutionResult(
    planId: '$packageId@2026-01-01T00:00:00.000Z',
    executed: true,
    rejectionReason: null,
    outcomes: const [
      HardwareWriteOpOutcome(
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
}

/// Drives a full After L/R capture+accept sequence.
Future<void> _captureAfterPair(RoomMeasurementController ctrl) async {
  for (var i = 0; i < 2; i++) {
    ctrl.markReady();
    await ctrl.capture();
    await ctrl.accept();
  }
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

  RoomMeasurementController ctrlOf(ProviderContainer c) =>
      c.read(roomMeasurementControllerProvider(_pid).notifier);

  test('After 1/2 runs neither the comparison nor the evaluator', () async {
    final c = await _seed();
    addTearDown(c.dispose);
    _authorizeAfterMode(c);
    final ctrl = ctrlOf(c);
    ctrl.setMode(RoomMeasurementPhase.after);

    ctrl.markReady();
    await ctrl.capture();
    await ctrl.accept();

    expect(ctrl.state.closedLoopResult, isNull);
    expect(ctrl.state.closedLoopComparison, isNull,
        reason: 'the gate itself only runs on the 2/2 transition');
  });

  test('matching provenance -> comparison passes and the evaluator runs once',
      () async {
    final c = await _seed();
    addTearDown(c.dispose);
    _authorizeAfterMode(c);
    final ctrl = ctrlOf(c);
    ctrl.setMode(RoomMeasurementPhase.after);

    await _captureAfterPair(ctrl);

    expect(ctrl.state.closedLoopComparison?.canEvaluate, isTrue);
    expect(ctrl.state.closedLoopResult, isNotNull,
        reason: 'a valid pair must still produce exactly one verdict');
  });

  test('mismatched microphone -> evaluator never runs, no verdict of any kind',
      () async {
    final c = await _seed(mismatchedProfile: true);
    addTearDown(c.dispose);
    _authorizeAfterMode(c);
    final ctrl = ctrlOf(c);
    ctrl.setMode(RoomMeasurementPhase.after);

    await _captureAfterPair(ctrl);

    final comparison = ctrl.state.closedLoopComparison;
    expect(comparison, isNotNull);
    expect(comparison!.canEvaluate, isFalse);
    expect(
        comparison.hasBlocker(
            MeasurementBeforeAfterMismatchCode.differentMicrophoneProfile),
        isTrue);

    // No verdict at all — not improved, not worsened, not "needs another
    // cycle". A blocked comparison must never masquerade as a result.
    expect(ctrl.state.closedLoopResult, isNull);
  });

  test('a blocked comparison leaves the Before pair intact for a re-measure',
      () async {
    final c = await _seed(mismatchedProfile: true);
    addTearDown(c.dispose);
    _authorizeAfterMode(c);
    final ctrl = ctrlOf(c);
    ctrl.setMode(RoomMeasurementPhase.after);
    await _captureAfterPair(ctrl);

    final project = c
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == _pid);
    expect(project.roomState.before.isComplete, isTrue,
        reason: 'the Before measurements are untouched, so the user can '
            're-measure After and get a valid comparison');
    expect(project.tuningState, isNotNull,
        reason: 'a blocked comparison performs no rollback and discards '
            'nothing');
  });
}
