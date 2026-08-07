// Phase 3-D3C-3 §16 — MeasurementWorkflowReadiness derivation.
//
// The load-bearing property is that at every state exactly ONE next action is
// returned, and that it is the FIRST unmet condition on the §4 ladder. The
// second is that nothing here is optimistic: a state the app cannot prove —
// a hardware connection, a Factory tuning that never reached a verdict, a
// device that was never re-checked — is reported as unknown or false, never
// as done.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_policy.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness_project_identity.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_evaluator.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_presentation.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';

import '../support/capture_gate_fixtures.dart';

const _pid = 'wf-1';
final _now = DateTime.utc(2026, 8, 7, 12);

// ── Fixtures ────────────────────────────────────────────────────────────────

ProProject _bare() => ProProject(
      id: _pid,
      name: 'Workflow Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Project + microphone + input device + a valid setup readiness.
ProProject _setupReady() => withGateReadySetup(_bare());

MeasurementMicrophoneSnapshot _micSnapshot() {
  final profile = gateReadyProfile();
  return MeasurementMicrophoneSnapshot(
    profileId: profile.id,
    profileChecksum: profile.checksum,
    manufacturer: profile.manufacturer,
    model: profile.model,
    calibrationSource: profile.calibrationSource,
    calibrationCurve: profile.calibrationCurve,
    orientation: CalibrationAngle.zeroDegree,
    inputDeviceId: kGateTestDeviceId,
    sampleRate: 48000,
    capturedAt: DateTime.utc(2026, 1, 1),
  );
}

MeasurementCaptureProvenance _prov(ProProject p) =>
    MeasurementCaptureProvenanceBuilder.build(
      project: p,
      actualSampleRate: 48000,
      actualChannelCount: 1,
      now: DateTime.utc(2026, 1, 1),
    );

ParsedMeasurementData _frd(
  String id,
  ProProject p, {
  MeasurementDataSource source = MeasurementDataSource.liveCapture,
  MeasurementCaptureProvenance? provenance,
  bool withQuality = true,
}) =>
    ParsedMeasurementData(
      id: id,
      sourceFileName: '$id.frd',
      fileType: AcousticFileType.frd,
      importedAt: DateTime.utc(2026, 1, 1),
      points: [
        for (var f = 20.0; f <= 2000; f *= 1.3)
          MeasurementDataPoint(frequencyHz: f, magnitudeDb: -6.0),
      ],
      calibrationStatus: CalibrationStatus.calibrated,
      calibrationCurveChecksum: gateReadyCalibrationCurve().checksum,
      // Room Auto PEQ's quality gate checks 20–300 Hz calibration coverage
      // off this snapshot, so a "good" fixture must carry it.
      microphoneSnapshot: withQuality ? _micSnapshot() : null,
      source: source,
      qualitySnapshot: withQuality
          ? MeasurementQualitySnapshot(
              provenance: provenance ?? _prov(p),
              setupCalibrationStatus: CalibrationStatus.calibrated,
              setupNoiseFloorDbFs: -70,
              setupPeakDbFs: -6,
              setupRmsDbFs: -18,
              setupSignalToNoiseDb: 52,
              setupClippedSampleCount: 0,
              setupClippedSampleRatio: 0,
              setupCheckedAt: DateTime.utc(2026, 1, 1),
            )
          : null,
    );

/// Four driver channels, [measured] of which carry parsed FRD data.
ProProject _withDrivers(ProProject p, {required int measured}) {
  const roles = [DriverRole.woofer, DriverRole.tweeter];
  const sides = [DriverSide.left, DriverSide.right];
  var i = 0;
  final channels = <DriverChannel>[];
  for (final side in sides) {
    for (final role in roles) {
      final hasData = i < measured;
      channels.add(DriverChannel(
        id: 'ch_${role.name}_${side.name}',
        name: '${role.name} ${side.name}',
        role: role,
        side: side,
        measurementStatus:
            hasData ? MeasurementStatus.validated : MeasurementStatus.empty,
        frdData: hasData ? _frd('drv$i', p) : null,
      ));
      i++;
    }
  }
  return p.copyWith(
      acousticState: p.acousticState.copyWith(driverChannels: channels));
}

ProProject _withFactoryTuning(ProProject p,
        {CorrectionCycleDecision decision =
            CorrectionCycleDecision.improvedAndComplete}) =>
    p.copyWith(correctionCycles: [
      CorrectionCycle(
        projectId: p.id,
        channelId: 'ch_woofer_left',
        cycleNumber: 1,
        beforeMeasurementRef: 'before-1',
        peqSnapshot: const PeqChannelState(channelId: 'ch_woofer_left'),
        decision: decision,
        completedAt: DateTime.utc(2026, 2, 1),
        createdAt: DateTime.utc(2026, 2, 1),
      ),
    ]);

RoomSystemMeasurement _roomM(
  ProProject p,
  RoomSystemSide side,
  RoomMeasurementPhase phase, {
  MeasurementCaptureProvenance? provenance,
  MeasurementDataSource source = MeasurementDataSource.liveCapture,
  bool withQuality = true,
}) =>
    RoomSystemMeasurement(
      side: side,
      phase: phase,
      frd: _frd('${phase.name}_${side.name}', p,
          provenance: provenance, source: source, withQuality: withQuality),
      capturedAt: DateTime.utc(2026, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: p.id,
    );

ProProject _withRoom(
  ProProject p, {
  int before = 0,
  int after = 0,
  MeasurementCaptureProvenance? afterProvenance,
  bool beforeQualityBroken = false,
}) {
  RoomMeasurementSnapshot snap(
    int count,
    RoomMeasurementPhase phase, {
    MeasurementCaptureProvenance? rightProvenance,
    MeasurementCaptureProvenance? provenance,
  }) =>
      RoomMeasurementSnapshot(
        leftSystemFrd: count >= 1
            ? _roomM(p, RoomSystemSide.left, phase, provenance: provenance)
            : null,
        rightSystemFrd: count >= 2
            ? _roomM(p, RoomSystemSide.right, phase,
                provenance: rightProvenance ?? provenance)
            : null,
      );

  return p.copyWith(
    roomState: RoomMeasurementProjectState.createDefault().copyWith(
      before: snap(
        before,
        RoomMeasurementPhase.before,
        // A Right side captured with a different microphone is what a real
        // pair-quality failure looks like.
        rightProvenance: beforeQualityBroken ? _differentMic(_prov(p)) : null,
      ),
      after:
          snap(after, RoomMeasurementPhase.after, provenance: afterProvenance),
    ),
  );
}

MeasurementCaptureProvenance _differentMic(MeasurementCaptureProvenance b) =>
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

const _pkg = 'room-pkg-1';

HardwareWriteExecutionResult _writeResult({
  String planId = '$_pkg@2026-01-01T00:00:00.000Z',
  bool executed = true,
  HardwareParamVerification verification =
      HardwareParamVerification.captureProven,
  HardwareWriteOpStatus status = HardwareWriteOpStatus.written,
}) =>
    HardwareWriteExecutionResult(
      planId: planId,
      executed: executed,
      rejectionReason: null,
      outcomes: [
        HardwareWriteOpOutcome(
          op: HardwareWriteOp(
            channelId: 'ch_wf_l',
            parameterKind: HardwareParamKind.peqGain,
            bandIndex: 0,
            targetValue: -1.0,
            verification: verification,
            writable: true,
            reason: 'test',
          ),
          status: status,
          report: null,
          message: 'ok',
        ),
      ],
    );

MeasurementWorkflowReadiness _eval(
  ProProject? p, {
  String? approved,
  HardwareWriteExecutionResult? write,
  CorrectionCycleDecision? decision,
}) =>
    MeasurementWorkflowEvaluator.evaluate(
      project: p,
      roomApprovedPackageId: approved,
      lastHardwareWriteResult: write,
      now: _now,
      closedLoopDecision: decision,
    );

/// The project one step short of the Room flow: setup ready, all drivers
/// measured, Factory tuning finished.
ProProject _readyForRoom() =>
    _withFactoryTuning(_withDrivers(_setupReady(), measured: 4));

void main() {
  group('1. no project', () {
    test('reports createOrOpenProject and nothing else as done', () {
      final r = _eval(null);
      expect(r.hasProject, isFalse);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.createOrOpenProject);
      expect(r.primaryBlocker, MeasurementWorkflowBlockerCode.noProject);
      expect(r.completedStages, 0);
      expect(r.hardwareConnected, isNull);
    });
  });

  group('2. microphone / calibration / input', () {
    test('no microphone -> selectMicrophone', () {
      final r = _eval(_bare());
      expect(
          r.nextRecommendedAction, MeasurementWorkflowAction.selectMicrophone);
      expect(r.microphoneSelected, isFalse);
      expect(r.calibrationStatus, MeasurementWorkflowCalibrationState.none);
    });

    test('a profile claiming calibration with no curve -> fixCalibration', () {
      final p = _bare().copyWith(
        selectedMicrophoneProfile: MeasurementMicrophoneProfile(
          id: 'm',
          manufacturer: 'TUNAI',
          model: 'NoCurve',
          connectionType: 'usb',
          calibrationSource: CalibrationSource.manufacturerFile,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final r = _eval(p);
      expect(r.nextRecommendedAction, MeasurementWorkflowAction.fixCalibration);
      expect(r.calibrationStatus,
          MeasurementWorkflowCalibrationState.legacyUnknown);
    });

    test('an explicitly uncalibrated mic warns but does not block', () {
      final p = _bare().copyWith(
        selectedMicrophoneProfile: MeasurementMicrophoneProfile(
          id: 'm',
          manufacturer: 'TUNAI',
          model: 'Raw',
          connectionType: 'usb',
          calibrationSource: CalibrationSource.uncalibrated,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        selectedInputDevice: gateReadyDevice(),
      );
      final r = _eval(p);
      expect(r.calibrationStatus,
          MeasurementWorkflowCalibrationState.explicitlyUncalibrated);
      expect(r.warnings,
          contains(MeasurementWorkflowWarningCode.calibrationUncalibrated));
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.checkMeasurementSetup,
          reason: 'a warning must not divert the ladder');
    });

    test('no input device -> selectInputDevice', () {
      final p = _bare().copyWith(selectedMicrophoneProfile: gateReadyProfile());
      final r = _eval(p);
      expect(
          r.nextRecommendedAction, MeasurementWorkflowAction.selectInputDevice);
      expect(r.inputSelected, isFalse);
      expect(r.inputSelectionKind, MeasurementWorkflowInputSelectionKind.none);
      expect(
          r.runtimeAvailability, MeasurementWorkflowInputAvailability.unknown);
    });

    test('system default is never presented as a verified device', () {
      final p = _bare().copyWith(
        selectedMicrophoneProfile: gateReadyProfile(),
        selectedInputDevice: MeasurementInputDeviceSelection.systemDefault(
            labelSnapshot: '시스템 기본', selectedAt: DateTime.utc(2026, 1, 1)),
      );
      final r = _eval(p);
      expect(r.inputSelectionKind,
          MeasurementWorkflowInputSelectionKind.systemDefault);
      expect(r.runtimeAvailability,
          MeasurementWorkflowInputAvailability.systemDefaultUnverified);
      expect(r.runtimeAvailabilityKnown, isFalse,
          reason: 'the concrete default device is unknowable without a scan');
      expect(measurementWorkflowInputStatusText(r), isNot(contains('정상')));
    });

    test('a specific device is only last-known-valid, and only with a setup',
        () {
      expect(_eval(_setupReady()).runtimeAvailability,
          MeasurementWorkflowInputAvailability.lastKnownValid);
      // Same chain, but the setup check was never run.
      final noSetup = _setupReady().copyWith(clearCurrentSetupReadiness: true);
      expect(_eval(noSetup).runtimeAvailability,
          MeasurementWorkflowInputAvailability.unknown);
    });
  });

  group('3. setup states', () {
    ProProject withReadiness(MeasurementSetupReadinessSnapshot s) =>
        _setupReady().copyWith(currentSetupReadiness: s);

    MeasurementSetupReadinessSnapshot base({
      DateTime? expiresAt,
      List<String> blockers = const [],
      List<String> warnings = const [],
      bool isReady = true,
      MeasurementSetupReadinessIdentity? identity,
    }) =>
        MeasurementSetupReadinessSnapshot(
          identity: identity ??
              MeasurementSetupReadinessProjectIdentity.forProject(
                _setupReady(),
                policy: MeasurementQualityPolicy.proProvisional(),
              ),
          generationId: 'gen-x',
          blockers: blockers,
          warnings: warnings,
          checkedAt: _now.subtract(const Duration(minutes: 5)),
          expiresAt: expiresAt ?? _now.add(const Duration(hours: 6)),
          isReady: isReady,
        );

    test('never checked', () {
      final p = _setupReady().copyWith(clearCurrentSetupReadiness: true);
      final r = _eval(p);
      expect(r.setupState, MeasurementWorkflowSetupState.notChecked);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.checkMeasurementSetup);
      expect(r.setupGenerationId, isNull);
    });

    test('expired', () {
      final r = _eval(withReadiness(
          base(expiresAt: _now.subtract(const Duration(minutes: 1)))));
      expect(r.setupState, MeasurementWorkflowSetupState.expired);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.checkMeasurementSetup);
    });

    test('stale — the chain changed since the check', () {
      // A readiness recorded against a DIFFERENT microphone than the one now
      // selected: still in date, but no longer describes this chain.
      final other = _setupReady().copyWith(
        selectedMicrophoneProfile: MeasurementMicrophoneProfile(
          id: 'other-mic',
          manufacturer: 'Other',
          model: 'Mic',
          connectionType: 'usb',
          calibrationSource: CalibrationSource.manufacturerFile,
          calibrationCurve: gateReadyCalibrationCurve(),
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final r = _eval(withReadiness(base(
          identity: MeasurementSetupReadinessProjectIdentity.forProject(other,
              policy: MeasurementQualityPolicy.proProvisional()))));
      expect(r.setupState, MeasurementWorkflowSetupState.stale);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.checkMeasurementSetup);
    });

    test('blocked — the check itself refused', () {
      final r = _eval(
          withReadiness(base(isReady: false, blockers: ['주변 소음이 너무 큽니다'])));
      expect(r.setupState, MeasurementWorkflowSetupState.blocked);
      expect(
          r.setupPrimaryBlocker, MeasurementWorkflowBlockerCode.setupRequired);
    });

    test('ready lets the ladder advance past setup', () {
      final r = _eval(_setupReady());
      expect(r.setupState, MeasurementWorkflowSetupState.ready);
      expect(r.setupGenerationId, isNotNull);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.measureFactoryDrivers);
    });
  });

  group('4. factory', () {
    test('drivers partially measured -> measureFactoryDrivers', () {
      final r = _eval(_withDrivers(_setupReady(), measured: 2));
      expect(r.requiredDriverCount, 4);
      expect(r.measuredDriverCount, 2);
      expect(r.driverMeasurementReady, isFalse);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.measureFactoryDrivers);
    });

    test('4/4 measured but no completed cycle -> runFactoryGuidedTuning', () {
      final r = _eval(_withDrivers(_setupReady(), measured: 4));
      expect(r.driverMeasurementReady, isTrue);
      expect(r.guidedTuningReady, isTrue);
      expect(r.factoryTuningCompleted, isFalse,
          reason: 'measuring drivers is not the same as finishing tuning');
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.runFactoryGuidedTuning);
    });

    test('completion needs a cycle that actually reached improvedAndComplete',
        () {
      for (final d in CorrectionCycleDecision.values) {
        final p = _withFactoryTuning(_withDrivers(_setupReady(), measured: 4),
            decision: d);
        expect(_eval(p).factoryTuningCompleted,
            d == CorrectionCycleDecision.improvedAndComplete,
            reason: d.name);
      }
    });

    test('the latest completed cycle verdict is exposed for Home copy', () {
      for (final d in CorrectionCycleDecision.values) {
        final p = _withFactoryTuning(_withDrivers(_setupReady(), measured: 4),
            decision: d);
        final r = _eval(p);
        expect(r.factoryLastCycleDecision, d, reason: d.name);
        expect(measurementWorkflowFactoryText(r), isNotEmpty, reason: d.name);
      }
      // No cycle at all -> nothing to report, never a fabricated verdict.
      expect(
          _eval(_withDrivers(_setupReady(), measured: 4))
              .factoryLastCycleDecision,
          isNull);
    });

    test('needsAnotherCycle and worsened read differently from complete', () {
      String textFor(CorrectionCycleDecision d) =>
          measurementWorkflowFactoryText(_eval(_withFactoryTuning(
              _withDrivers(_setupReady(), measured: 4),
              decision: d)));
      expect(textFor(CorrectionCycleDecision.improvedAndComplete),
          'Factory Tuning 완료');
      expect(textFor(CorrectionCycleDecision.improvedNeedsAnotherCycle),
          '추가 보정 권장');
      expect(textFor(CorrectionCycleDecision.worsened), '재검토 필요');
    });

    test('a cycle from a different project never counts', () {
      final p = _withDrivers(_setupReady(), measured: 4).copyWith(
        correctionCycles: [
          CorrectionCycle(
            projectId: 'some-other-project',
            channelId: 'ch_woofer_left',
            cycleNumber: 1,
            beforeMeasurementRef: 'b',
            peqSnapshot: const PeqChannelState(channelId: 'ch_woofer_left'),
            decision: CorrectionCycleDecision.improvedAndComplete,
            createdAt: DateTime.utc(2026, 2, 1),
          ),
        ],
      );
      expect(_eval(p).factoryTuningCompleted, isFalse);
    });
  });

  group('5. room', () {
    test('before 0/2 and 1/2 both -> measureRoomBefore', () {
      for (final n in [0, 1]) {
        final r = _eval(_withRoom(_readyForRoom(), before: n));
        expect(r.beforeCount, n);
        expect(r.beforeMeasurementComplete, isFalse);
        expect(r.nextRecommendedAction,
            MeasurementWorkflowAction.measureRoomBefore,
            reason: 'before=$n');
      }
    });

    test('before 2/2 with mismatched sides -> resolveRoomMeasurementQuality',
        () {
      final r = _eval(
          _withRoom(_readyForRoom(), before: 2, beforeQualityBroken: true));
      expect(r.beforeMeasurementComplete, isTrue);
      expect(r.beforeQualityReady, isFalse);
      expect(r.roomAutoPeqReady, isFalse);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.resolveRoomMeasurementQuality);
    });

    test('quality passes but nothing approved -> generateRoomAutoPeq', () {
      final r = _eval(_withRoom(_readyForRoom(), before: 2));
      expect(r.beforeQualityReady, isTrue);
      expect(r.roomAutoPeqReady, isTrue);
      expect(r.roomAutoPeqApproved, isFalse);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.generateRoomAutoPeq);
    });

    test('approved but not deployed -> deployRoomCorrection', () {
      final r = _eval(_withRoom(_readyForRoom(), before: 2), approved: _pkg);
      expect(r.roomAutoPeqApproved, isTrue);
      expect(r.correctionDeployedAndVerified, isFalse);
      expect(r.deployBlockedReason, isNotNull);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.deployRoomCorrection);
    });

    test('deployed and verified -> measureRoomAfter', () {
      final r = _eval(_withRoom(_readyForRoom(), before: 2),
          approved: _pkg, write: _writeResult());
      expect(r.correctionDeployedAndVerified, isTrue);
      expect(r.afterAvailable, isTrue);
      expect(r.roomCorrectionVerified, isTrue);
      expect(r.deployBlockedReason, isNull);
      expect(
          r.nextRecommendedAction, MeasurementWorkflowAction.measureRoomAfter);
    });

    test('after 1/2 -> still measureRoomAfter', () {
      final r = _eval(_withRoom(_readyForRoom(), before: 2, after: 1),
          approved: _pkg, write: _writeResult());
      expect(r.afterCount, 1);
      expect(r.afterMeasurementComplete, isFalse);
      expect(
          r.nextRecommendedAction, MeasurementWorkflowAction.measureRoomAfter);
    });

    test('after 2/2 with mismatched provenance -> resolveBeforeAfterMismatch',
        () {
      final p = _readyForRoom();
      final r = _eval(
        _withRoom(p,
            before: 2, after: 2, afterProvenance: _differentMic(_prov(p))),
        approved: _pkg,
        write: _writeResult(),
        decision: CorrectionCycleDecision.improvedAndComplete,
      );
      expect(r.afterMeasurementComplete, isTrue);
      expect(r.beforeAfterComparable, isFalse);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.resolveBeforeAfterMismatch);
      expect(r.closedLoopComplete, isFalse,
          reason: 'a blocked comparison is never a completed loop');
      expect(r.closedLoopDecision, isNull,
          reason: 'and it must not surface a verdict either');
    });

    test('comparable but no verdict yet -> reviewClosedLoop', () {
      final r = _eval(_withRoom(_readyForRoom(), before: 2, after: 2),
          approved: _pkg, write: _writeResult());
      expect(r.beforeAfterComparable, isTrue);
      expect(r.closedLoopComplete, isFalse);
      expect(
          r.nextRecommendedAction, MeasurementWorkflowAction.reviewClosedLoop);
    });

    test('a real verdict on a comparable pair -> complete', () {
      final r = _eval(_withRoom(_readyForRoom(), before: 2, after: 2),
          approved: _pkg,
          write: _writeResult(),
          decision: CorrectionCycleDecision.improvedAndComplete);
      expect(r.closedLoopComplete, isTrue);
      expect(r.closedLoopDecision, CorrectionCycleDecision.improvedAndComplete);
      expect(r.nextRecommendedAction, MeasurementWorkflowAction.complete);
      expect(r.primaryBlocker, isNull);
    });
  });

  group('6. hardware identity is never assumed', () {
    ProProject roomReady() => _withRoom(_readyForRoom(), before: 2);

    test('a write result for a DIFFERENT plan is not a deploy', () {
      final r = _eval(roomReady(),
          approved: _pkg,
          write: _writeResult(planId: 'some-other-pkg@2026-01-01T00:00:00Z'));
      expect(r.correctionDeployedAndVerified, isFalse);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.deployRoomCorrection);
    });

    test('an ACK-only write is not a verified deploy', () {
      final r = _eval(roomReady(),
          approved: _pkg,
          write: _writeResult(
              verification: HardwareParamVerification.captureProven,
              status: HardwareWriteOpStatus.ackOnly));
      expect(r.correctionDeployedAndVerified, isFalse);
    });

    test('a write that never executed is not a deploy', () {
      final r = _eval(roomReady(),
          approved: _pkg, write: _writeResult(executed: false));
      expect(r.correctionDeployedAndVerified, isFalse);
    });

    test('hardware connection is unknown, never guessed as false', () {
      expect(_eval(_setupReady()).hardwareConnected, isNull);
    });
  });

  group('7. simulated data contributes nothing', () {
    test('a project with no real measurements stays at step one', () {
      // Nothing in this model can reach MeasurementSession/simulateCapture —
      // it only reads ProProject. A project whose only "measurements" were
      // simulated is therefore indistinguishable from an empty one, which is
      // exactly the required behaviour.
      final r = _eval(_setupReady());
      expect(r.measuredDriverCount, 0);
      expect(r.beforeCount, 0);
      expect(r.roomAutoPeqReady, isFalse);
      expect(r.factoryTuningCompleted, isFalse);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.measureFactoryDrivers);
    });
  });

  group('8. legacy projects', () {
    test('legacy measurements warn, never block, and are never migrated', () {
      final p = _setupReady();
      final legacy = _withDrivers(p, measured: 4);
      final channels = [
        for (final c in legacy.acousticState.driverChannels)
          c.copyWith(
              frdData: _frd(c.id, p,
                  source: MeasurementDataSource.legacyUnknown,
                  withQuality: false)),
      ];
      final r = _eval(legacy.copyWith(
          acousticState:
              legacy.acousticState.copyWith(driverChannels: channels)));

      expect(r.warnings,
          contains(MeasurementWorkflowWarningCode.legacyMeasurementData));
      expect(r.driverMeasurementReady, isTrue,
          reason: 'existing Factory data stays usable');
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.runFactoryGuidedTuning);
    });

    test('legacy Room Before is recognised but fails the quality gate', () {
      final p = _readyForRoom();
      final room = _withRoom(p, before: 2);
      final before = room.roomState.before;
      final downgraded = RoomMeasurementSnapshot(
        leftSystemFrd: _roomM(
            p, RoomSystemSide.left, RoomMeasurementPhase.before,
            source: MeasurementDataSource.legacyUnknown, withQuality: false),
        rightSystemFrd: before.rightSystemFrd,
      );
      final r = _eval(room.copyWith(
          roomState: room.roomState.copyWith(before: downgraded)));

      expect(r.beforeMeasurementComplete, isTrue);
      expect(r.beforeQualityReady, isFalse);
      expect(r.nextRecommendedAction,
          MeasurementWorkflowAction.resolveRoomMeasurementQuality,
          reason: 'new Room corrections require freshly-measured quality '
              'data — the user is asked to re-measure, not migrated');
    });
  });

  group('9. exactly one action, and stages', () {
    test('every state returns a single action from the enum', () {
      final states = <ProProject?>[
        null,
        _bare(),
        _setupReady(),
        _withDrivers(_setupReady(), measured: 2),
        _withDrivers(_setupReady(), measured: 4),
        _readyForRoom(),
        _withRoom(_readyForRoom(), before: 2),
      ];
      for (final s in states) {
        final r = _eval(s);
        expect(MeasurementWorkflowAction.values,
            contains(r.nextRecommendedAction));
      }
    });

    test('stages advance monotonically along the flow', () {
      final empty = _eval(_setupReady());
      expect(empty.stage(MeasurementWorkflowStage.measurementSetup),
          MeasurementWorkflowStageState.complete);
      expect(empty.stage(MeasurementWorkflowStage.factoryTuning),
          MeasurementWorkflowStageState.notStarted);

      final factory = _eval(_readyForRoom());
      expect(factory.stage(MeasurementWorkflowStage.factoryTuning),
          MeasurementWorkflowStageState.complete);
      expect(factory.stage(MeasurementWorkflowStage.roomTuning),
          MeasurementWorkflowStageState.notStarted);

      final done = _eval(_withRoom(_readyForRoom(), before: 2, after: 2),
          approved: _pkg,
          write: _writeResult(),
          decision: CorrectionCycleDecision.improvedAndComplete);
      expect(done.completedStages, done.totalStages);
      expect(measurementWorkflowProgress(done).completed, 5);
    });

    test('a mismatched pair blocks the verification stage, not the room one',
        () {
      final p = _readyForRoom();
      final r = _eval(
        _withRoom(p,
            before: 2, after: 2, afterProvenance: _differentMic(_prov(p))),
        approved: _pkg,
        write: _writeResult(),
      );
      expect(r.stage(MeasurementWorkflowStage.roomTuning),
          MeasurementWorkflowStageState.complete);
      expect(r.stage(MeasurementWorkflowStage.verification),
          MeasurementWorkflowStageState.blocked);
      expect(r.completedStages, lessThan(r.totalStages),
          reason: 'progress must never report done on a blocked comparison');
    });

    test('no fabricated precision — progress is a whole-stage ratio', () {
      final r = _eval(_readyForRoom());
      final p = measurementWorkflowProgress(r);
      expect(p.total, 5);
      expect(p.completed, inInclusiveRange(0, 5));
    });
  });

  group('10. presentation (§13)', () {
    test('every action has non-empty beginner title and description', () {
      for (final a in MeasurementWorkflowAction.values) {
        expect(measurementWorkflowActionTitle(a), isNotEmpty, reason: a.name);
        expect(measurementWorkflowActionDescription(a), isNotEmpty,
            reason: a.name);
        expect(measurementWorkflowActionTitle(a), isNot(contains(a.name)));
      }
    });

    test('every blocker, warning and stage has copy', () {
      for (final c in MeasurementWorkflowBlockerCode.values) {
        expect(measurementWorkflowBlockerText(c), isNotEmpty, reason: c.name);
      }
      for (final c in MeasurementWorkflowWarningCode.values) {
        expect(measurementWorkflowWarningText(c), isNotEmpty, reason: c.name);
      }
      for (final s in MeasurementWorkflowStage.values) {
        expect(measurementWorkflowStageTitle(s), isNotEmpty, reason: s.name);
      }
    });

    test('no internal DSP terminology reaches Home copy', () {
      const forbidden = [
        'PEQ',
        'biquad',
        'Biquad',
        'FFT',
        'DSP',
        'register',
        'checksum',
        'provenance',
        'dBFS',
        'SNR',
        'IIR',
        'bin',
      ];
      final all = <String>[
        for (final a in MeasurementWorkflowAction.values) ...[
          measurementWorkflowActionTitle(a),
          measurementWorkflowActionDescription(a),
        ],
        for (final c in MeasurementWorkflowBlockerCode.values)
          measurementWorkflowBlockerText(c),
        for (final c in MeasurementWorkflowWarningCode.values)
          measurementWorkflowWarningText(c),
        for (final s in MeasurementWorkflowStage.values)
          measurementWorkflowStageTitle(s),
      ];
      for (final text in all) {
        for (final term in forbidden) {
          expect(text, isNot(contains(term)),
              reason: '"$text" leaks internal terminology "$term"');
        }
      }
    });
  });
}
