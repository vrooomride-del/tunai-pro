// Phase 3-D3B — RoomAutoPeqController.generate() quality gate wiring.
//
// Proves 2/2 completeness is no longer sufficient by itself: a complete but
// quality-blocked pair produces zero candidates and a clear error, while a
// quality-ready pair generates normally (RoomAutoPeq's own algorithm output
// is unchanged — see room_auto_peq_test.dart for that pure-algorithm
// coverage; this file only tests the gate wired in front of it).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/features/workbench/tabs/room_auto_peq_controller.dart';
import '../support/room_quality_fixtures.dart';

/// +8 dB bass bump around 80 Hz — a correctable broadPeak, same fixture
/// shape as room_auto_peq_controller_test.dart.
ParsedMeasurementData _peakFrd(
  String id, {
  String? projectId,
  bool includeQualitySnapshot = true,
}) {
  final points = <MeasurementDataPoint>[];
  for (var f = 20.0; f <= 2000; f *= 1.05) {
    final inBump = f > 60 && f < 110;
    points.add(
        MeasurementDataPoint(frequencyHz: f, magnitudeDb: inBump ? 8.0 : 0.0));
  }
  return ParsedMeasurementData(
    id: id,
    sourceFileName: '$id.frd',
    fileType: AcousticFileType.frd,
    importedAt: DateTime.utc(2025, 1, 1),
    points: points,
    calibrationStatus: CalibrationStatus.calibrated,
    microphoneSnapshot: roomQualityFixtureMicSnapshot(),
    qualitySnapshot: includeQualitySnapshot && projectId != null
        ? roomQualityFixtureSnapshot(projectId: projectId)
        : null,
  );
}

RoomSystemMeasurement _measurement(
  RoomSystemSide side,
  String projectId, {
  bool includeQualitySnapshot = true,
}) =>
    RoomSystemMeasurement(
      side: side,
      phase: RoomMeasurementPhase.before,
      frd: _peakFrd('${side.name}_before',
          projectId: projectId, includeQualitySnapshot: includeQualitySnapshot),
      capturedAt: DateTime.utc(2025, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: projectId,
    );

const _projectId = 'room-quality-gate-1';

ProProject _project({
  required RoomMeasurementSnapshot before,
}) =>
    ProProject(
      id: _projectId,
      name: 'Room Quality Gate Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      tuningState: TuningProjectState(peqChannels: const [
        PeqChannelState(channelId: 'ch_wf_l', bands: []),
      ]),
      roomState: RoomMeasurementProjectState(before: before),
    );

Future<ProviderContainer> _buildContainer(
    RoomMeasurementSnapshot before) async {
  final container = ProviderContainer();
  await container
      .read(proProjectStoreProvider.notifier)
      .addProject(_project(before: before));
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      '2/2 complete but missing quality on Left -> generate() blocked, '
      'zero candidates', () async {
    final before = RoomMeasurementSnapshot(
      leftSystemFrd: _measurement(RoomSystemSide.left, _projectId,
          includeQualitySnapshot: false),
      rightSystemFrd: _measurement(RoomSystemSide.right, _projectId),
    );
    final container = await _buildContainer(before);
    addTearDown(container.dispose);
    final ctrl =
        container.read(roomAutoPeqControllerProvider(_projectId).notifier);

    ctrl.generate();

    final state = container.read(roomAutoPeqControllerProvider(_projectId));
    expect(state.phase, RoomAutoPeqPhase.idle);
    expect(state.candidates, isEmpty);
    expect(state.error, isNotNull);
  });

  test('2/2 complete, both quality-ready -> generate() produces candidates',
      () async {
    final before = RoomMeasurementSnapshot(
      leftSystemFrd: _measurement(RoomSystemSide.left, _projectId),
      rightSystemFrd: _measurement(RoomSystemSide.right, _projectId),
    );
    final container = await _buildContainer(before);
    addTearDown(container.dispose);
    final ctrl =
        container.read(roomAutoPeqControllerProvider(_projectId).notifier);

    ctrl.generate();

    final state = container.read(roomAutoPeqControllerProvider(_projectId));
    expect(state.phase, RoomAutoPeqPhase.confirmPending);
    expect(state.candidates, isNotEmpty);
    expect(state.error, isNull);
  });

  test(
      'mismatched microphone profile between sides -> generate() blocked, '
      'zero candidates', () async {
    final leftMeasurement = _measurement(RoomSystemSide.left, _projectId);
    // Right side uses a DIFFERENT microphone profile checksum than Left —
    // built directly (not via the shared fixture) so the two provenances
    // genuinely differ.
    final rightSnapshot = roomQualityFixtureSnapshot(projectId: _projectId);
    final rightFrd = ParsedMeasurementData(
      id: 'right_before',
      sourceFileName: 'right_before.frd',
      fileType: AcousticFileType.frd,
      importedAt: DateTime.utc(2025, 1, 1),
      points: leftMeasurement.frd.points,
      calibrationStatus: CalibrationStatus.calibrated,
      microphoneSnapshot: roomQualityFixtureMicSnapshot(),
      qualitySnapshot: MeasurementQualitySnapshotBuilder.build(
        provenance: MeasurementCaptureProvenance(
          projectId: rightSnapshot.provenance.projectId,
          microphoneProfileChecksum: 'a-different-mic-checksum',
          calibrationCurveChecksum:
              rightSnapshot.provenance.calibrationCurveChecksum,
          calibrationAngle: rightSnapshot.provenance.calibrationAngle,
          inputDeviceSelectionIdentity:
              rightSnapshot.provenance.inputDeviceSelectionIdentity,
          setupReadinessGenerationId:
              rightSnapshot.provenance.setupReadinessGenerationId,
          qualityPolicyVersion: rightSnapshot.provenance.qualityPolicyVersion,
          actualSampleRate: rightSnapshot.provenance.actualSampleRate,
          actualChannelCount: rightSnapshot.provenance.actualChannelCount,
          capturedAt: rightSnapshot.provenance.capturedAt,
        ),
        readiness: roomQualityFixtureReadiness(projectId: _projectId),
      ),
    );
    final before = RoomMeasurementSnapshot(
      leftSystemFrd: leftMeasurement,
      rightSystemFrd: RoomSystemMeasurement(
        side: RoomSystemSide.right,
        phase: RoomMeasurementPhase.before,
        frd: rightFrd,
        capturedAt: DateTime.utc(2025, 1, 1),
        sampleRate: 48000,
        source: RoomMeasurementSource.live,
        projectId: _projectId,
      ),
    );
    final container = await _buildContainer(before);
    addTearDown(container.dispose);
    final ctrl =
        container.read(roomAutoPeqControllerProvider(_projectId).notifier);

    ctrl.generate();

    final state = container.read(roomAutoPeqControllerProvider(_projectId));
    expect(state.phase, RoomAutoPeqPhase.idle);
    expect(state.candidates, isEmpty);
    expect(state.error, isNotNull);
  });
}
