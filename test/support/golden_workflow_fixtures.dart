// Shared builders for the Phase 3-F2 whole-workflow integration tests.
//
// Every step below advances the REAL production state through the REAL store
// notifier methods the app itself calls — never by constructing a finished
// ProProject. That is deliberate: a fixture that hands the evaluator an
// already-correct project cannot catch a broken transition, which is exactly
// how earlier phases shipped bugs that only appeared on the device.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/workbench/tabs/room_auto_peq_controller.dart';

import 'capture_gate_fixtures.dart';

const String kGoldenProjectId = 'golden-1';
const String kGoldenPackageId = 'room-pkg-golden';

/// Real wall clock — withGateReadySetup() stamps setup readiness with
/// DateTime.now(), so a frozen past instant would read as expired.
DateTime goldenNow() => DateTime.now();

final _stamp = DateTime.utc(2026, 1, 1);

// ── Project ────────────────────────────────────────────────────────────────

ProProject goldenBareProject({
  String id = kGoldenProjectId,
  String dspTarget = 'ADAU1701',
}) =>
    ProProject(
      id: id,
      name: 'Golden $id',
      speakerModel: 'TUNAI ONE',
      dspTarget: dspTarget,
      channelConfig: '2-way stereo',
      createdAt: _stamp,
      updatedAt: _stamp,
    );

// ── Measurement chain ──────────────────────────────────────────────────────

MeasurementMicrophoneSnapshot goldenMicSnapshot() {
  final p = gateReadyProfile();
  return MeasurementMicrophoneSnapshot(
    profileId: p.id,
    profileChecksum: p.checksum,
    manufacturer: p.manufacturer,
    model: p.model,
    calibrationSource: p.calibrationSource,
    calibrationCurve: p.calibrationCurve,
    orientation: CalibrationAngle.zeroDegree,
    inputDeviceId: kGateTestDeviceId,
    sampleRate: 48000,
    capturedAt: _stamp,
  );
}

MeasurementCaptureProvenance goldenProvenance(ProProject p) =>
    MeasurementCaptureProvenanceBuilder.build(
      project: p,
      actualSampleRate: 48000,
      actualChannelCount: 1,
      now: _stamp,
    );

/// A live-capture measurement whose provenance matches [p]'s current chain.
ParsedMeasurementData goldenFrd(
  String id,
  ProProject p, {
  MeasurementCaptureProvenance? provenance,
  MeasurementDataSource source = MeasurementDataSource.liveCapture,
  bool withQuality = true,
  double magnitudeDb = -6.0,
}) =>
    ParsedMeasurementData(
      id: id,
      sourceFileName: '$id.frd',
      fileType: AcousticFileType.frd,
      importedAt: _stamp,
      points: [
        for (var f = 20.0; f <= 2000; f *= 1.3)
          MeasurementDataPoint(frequencyHz: f, magnitudeDb: magnitudeDb),
      ],
      calibrationStatus: CalibrationStatus.calibrated,
      calibrationCurveChecksum: gateReadyCalibrationCurve().checksum,
      microphoneSnapshot: withQuality ? goldenMicSnapshot() : null,
      source: source,
      qualitySnapshot: withQuality
          ? MeasurementQualitySnapshot(
              provenance: provenance ?? goldenProvenance(p),
              setupCalibrationStatus: CalibrationStatus.calibrated,
              setupNoiseFloorDbFs: -70,
              setupPeakDbFs: -6,
              setupRmsDbFs: -18,
              setupSignalToNoiseDb: 52,
              setupClippedSampleCount: 0,
              setupClippedSampleRatio: 0,
              setupCheckedAt: _stamp,
            )
          : null,
    );

/// A provenance describing a DIFFERENT microphone — the realistic shape of a
/// Before/After or Left/Right mismatch.
MeasurementCaptureProvenance goldenOtherMicProvenance(
        MeasurementCaptureProvenance b) =>
    MeasurementCaptureProvenance(
      projectId: b.projectId,
      microphoneProfileChecksum: 'a-completely-different-microphone',
      calibrationCurveChecksum: b.calibrationCurveChecksum,
      calibrationAngle: b.calibrationAngle,
      inputDeviceSelectionIdentity: b.inputDeviceSelectionIdentity,
      setupReadinessGenerationId: b.setupReadinessGenerationId,
      qualityPolicyVersion: b.qualityPolicyVersion,
      actualSampleRate: b.actualSampleRate,
      actualChannelCount: b.actualChannelCount,
      capturedAt: b.capturedAt,
    );

// ── Factory drivers ────────────────────────────────────────────────────────

/// Four driver channels, [measured] of which carry parsed FRD data.
List<DriverChannel> goldenDrivers(ProProject p, {required int measured}) {
  const roles = [DriverRole.woofer, DriverRole.tweeter];
  const sides = [DriverSide.left, DriverSide.right];
  var i = 0;
  final out = <DriverChannel>[];
  for (final side in sides) {
    for (final role in roles) {
      final has = i < measured;
      out.add(DriverChannel(
        id: 'ch_${role.name}_${side.name}',
        name: '${role.name} ${side.name}',
        role: role,
        side: side,
        measurementStatus:
            has ? MeasurementStatus.validated : MeasurementStatus.empty,
        frdData: has ? goldenFrd('drv$i', p) : null,
      ));
      i++;
    }
  }
  return out;
}

CorrectionCycle goldenCycle(
  String projectId, {
  CorrectionCycleDecision decision =
      CorrectionCycleDecision.improvedAndComplete,
  int cycleNumber = 1,
}) =>
    CorrectionCycle(
      projectId: projectId,
      channelId: 'ch_woofer_left',
      cycleNumber: cycleNumber,
      beforeMeasurementRef: 'before-$cycleNumber',
      peqSnapshot: const PeqChannelState(channelId: 'ch_woofer_left'),
      decision: decision,
      completedAt: _stamp,
      createdAt: _stamp,
    );

// ── Room ───────────────────────────────────────────────────────────────────

RoomSystemMeasurement goldenRoomMeasurement(
  ProProject p,
  RoomSystemSide side,
  RoomMeasurementPhase phase, {
  MeasurementCaptureProvenance? provenance,
  bool withQuality = true,
  double magnitudeDb = -6.0,
}) =>
    RoomSystemMeasurement(
      side: side,
      phase: phase,
      frd: goldenFrd('${phase.name}_${side.name}', p,
          provenance: provenance,
          withQuality: withQuality,
          magnitudeDb: magnitudeDb),
      capturedAt: _stamp,
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: p.id,
    );

RoomMeasurementSnapshot goldenRoomSnapshot(
  ProProject p,
  RoomMeasurementPhase phase, {
  required int count,
  MeasurementCaptureProvenance? rightProvenance,
  MeasurementCaptureProvenance? provenance,
  bool withQuality = true,
  double magnitudeDb = -6.0,
}) =>
    RoomMeasurementSnapshot(
      leftSystemFrd: count >= 1
          ? goldenRoomMeasurement(p, RoomSystemSide.left, phase,
              provenance: provenance,
              withQuality: withQuality,
              magnitudeDb: magnitudeDb)
          : null,
      rightSystemFrd: count >= 2
          ? goldenRoomMeasurement(p, RoomSystemSide.right, phase,
              provenance: rightProvenance ?? provenance,
              withQuality: withQuality,
              magnitudeDb: magnitudeDb)
          : null,
    );

// ── Hardware ───────────────────────────────────────────────────────────────

HardwareWriteExecutionResult goldenWriteResult({
  String packageId = kGoldenPackageId,
  String? planId,
  bool executed = true,
  HardwareWriteOpStatus status = HardwareWriteOpStatus.written,
}) =>
    HardwareWriteExecutionResult(
      planId: planId ?? '$packageId@2026-01-01T00:00:00.000Z',
      executed: executed,
      rejectionReason: null,
      outcomes: [
        HardwareWriteOpOutcome(
          op: const HardwareWriteOp(
            channelId: 'ch_wf_l',
            parameterKind: HardwareParamKind.peqGain,
            bandIndex: 0,
            targetValue: -1.0,
            verification: HardwareParamVerification.captureProven,
            writable: true,
            reason: 'golden',
          ),
          status: status,
          report: null,
          message: 'ok',
        ),
      ],
    );

/// Marks the project's persisted identity confirmation AND installs a live
/// ADAU1701 session, mirroring what hardware_tab's sync does on a real
/// PASS_HANDSHAKE. [handshaken] false leaves the session mid-connect.
Future<void> goldenConnectHardware(
  ProviderContainer c, {
  String projectId = kGoldenProjectId,
  bool handshaken = true,
}) async {
  final transport = handshaken
      ? (FakeHandshakenTransport()..markReady())
      : FakeHandshakenTransport();
  c.read(activeAdau1701ContextProvider.notifier).state =
      Adau1701HardwareContext.fromTransport(transport);
  if (handshaken) {
    await c
        .read(proProjectStoreProvider.notifier)
        .updateHardwareConnection(projectId, HardwareConnection.connected);
  }
}

/// Drops the live session exactly as a BLE disconnect / onDone callback does.
void goldenDisconnectHardware(ProviderContainer c) {
  c.read(activeAdau1701ContextProvider.notifier).state = null;
}

/// A transport whose readiness can be toggled without any real I/O. It
/// satisfies the SAME contract the production context checks
/// (isConnected && handshakeComplete && detectedProfile != null).
class FakeHandshakenTransport extends Icp5UsbTransport {
  bool _ready = false;

  void markReady() => _ready = true;

  @override
  bool get isConnected => _ready;

  @override
  bool get handshakeComplete => _ready;

  @override
  String? get detectedProfile => _ready ? 'ICP5-ADAU1701' : null;
}

/// Approves a Room correction, as RoomAutoPeqController.approve() does.
void goldenApproveRoomCorrection(
  ProviderContainer c, {
  String projectId = kGoldenProjectId,
  String packageId = kGoldenPackageId,
}) {
  c.read(roomAutoPeqControllerProvider(projectId).notifier).state =
      const RoomAutoPeqState(approvedPackageId: kGoldenPackageId);
}
