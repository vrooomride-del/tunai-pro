// Phase 2 safety audit — RoomAutoPeqController tests.
//
// This controller had ZERO test coverage before the audit. Covers:
//  1. generate()/cancel() do not touch tuningState or exportState
//  2. approve() persists ONLY exportState — tuningState is never written
//  3. approve() mints a fresh, per-approval-unique packageId and captures a
//     fresh pre-apply TuningProjectState snapshot
//  4. cancel() after a PRIOR approval preserves that approval's
//     approvedPackageId/preApplySnapshot (only resets the in-progress
//     preview)
//  5. requestRollback(): fail-closed with no snapshot; builds and persists a
//     rollback exportState package restoring only the Room-touched Woofer
//     PEQ slots when a snapshot exists; zero writes happen in this file
//     (only ProProjectStoreNotifier.updateExportState calls, never a
//     HardwareWriteExecutor call)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/features/workbench/tabs/room_auto_peq_controller.dart';
import '../support/room_quality_fixtures.dart';

/// +8 dB bass bump around 80 Hz — a correctable broadPeak (cut-only PEQ can
/// fix excess energy; see room_auto_peq_test.dart for why a dip cannot).
ParsedMeasurementData _peakFrd(String id, String projectId) {
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
    // Phase 3-D3B: generate() now requires trustworthy quality provenance
    // on both sides — this fixture is quality-ready by construction so
    // these tests keep exercising approve()/rollback mechanics, not the
    // quality gate itself (that has its own dedicated test file).
    calibrationStatus: CalibrationStatus.calibrated,
    microphoneSnapshot: roomQualityFixtureMicSnapshot(),
    qualitySnapshot: roomQualityFixtureSnapshot(projectId: projectId),
  );
}

RoomSystemMeasurement _measurement(RoomSystemSide side, String projectId) =>
    RoomSystemMeasurement(
      side: side,
      phase: RoomMeasurementPhase.before,
      frd: _peakFrd('${side.name}_before', projectId),
      capturedAt: DateTime.utc(2025, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: projectId,
    );

ProProject _readyProject({String id = 'room-autopeq-1'}) => ProProject(
      id: id,
      name: 'Room Auto PEQ Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      tuningState: TuningProjectState(peqChannels: const [
        PeqChannelState(channelId: 'ch_wf_l', bands: [
          PeqBand(id: 'pre-existing', frequencyHz: 200, gainDb: -1.0, q: 1.0),
        ]),
      ]),
      roomState: RoomMeasurementProjectState(
        before: RoomMeasurementSnapshot(
          leftSystemFrd: _measurement(RoomSystemSide.left, id),
          rightSystemFrd: _measurement(RoomSystemSide.right, id),
        ),
      ),
    );

class _Harness {
  final ProviderContainer container;
  const _Harness(this.container);

  ProProject get project => container
      .read(proProjectStoreProvider)
      .projects
      .firstWhere((p) => p.id == 'room-autopeq-1');

  RoomAutoPeqController get ctrl =>
      container.read(roomAutoPeqControllerProvider('room-autopeq-1').notifier);

  RoomAutoPeqState get state =>
      container.read(roomAutoPeqControllerProvider('room-autopeq-1'));
}

Future<_Harness> _buildHarness({ProProject? seedProject}) async {
  final container = ProviderContainer();
  await container
      .read(proProjectStoreProvider.notifier)
      .addProject(seedProject ?? _readyProject());
  return _Harness(container);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. generate()/cancel() touch nothing persisted', () {
    test('generate() does not write tuningState or exportState', () async {
      final h = await _buildHarness();
      final beforeTuning = h.project.tuningState;
      final beforeExport = h.project.exportState;
      h.ctrl.generate();
      expect(h.project.tuningState, same(beforeTuning));
      expect(h.project.exportState, same(beforeExport));
      expect(h.state.phase, RoomAutoPeqPhase.confirmPending);
    });

    test('cancel() after generate() clears the preview but persists nothing',
        () async {
      final h = await _buildHarness();
      h.ctrl.generate();
      h.ctrl.cancel();
      expect(h.state.phase, RoomAutoPeqPhase.idle);
      expect(h.state.candidates, isEmpty);
      expect(h.project.tuningState.peqChannels.first.bands.length, 1);
    });
  });

  group('2-3. approve() persistence and identity', () {
    test('approve() persists ONLY exportState — tuningState never written',
        () async {
      final h = await _buildHarness();
      h.ctrl.generate();
      expect(h.state.phase, RoomAutoPeqPhase.confirmPending);
      final beforeTuning = h.project.tuningState;

      final ok = await h.ctrl.approve();

      expect(ok, isTrue);
      expect(h.project.tuningState, same(beforeTuning),
          reason: 'Room Auto PEQ approval must never write tuningState — '
              'the actual PEQ change only exists in the exportState package '
              'until Deploy writes it to hardware.');
      expect(h.project.exportState.activePackageId, h.state.approvedPackageId);
    });

    test('approve() mints a fresh packageId each time (not a fixed constant)',
        () async {
      final h = await _buildHarness();
      h.ctrl.generate();
      await h.ctrl.approve();
      final firstId = h.state.approvedPackageId;
      expect(firstId, isNotNull);

      h.ctrl.generate();
      await h.ctrl.approve();
      final secondId = h.state.approvedPackageId;

      expect(secondId, isNotNull);
      expect(secondId, isNot(firstId),
          reason: 'A fixed per-project id would make every Room Auto PEQ '
              'generation indistinguishable from the last, breaking the '
              'After-gate\'s stale-plan rejection.');
    });

    test(
        'approve() captures a pre-apply snapshot equal to the live '
        'tuningState at approval time', () async {
      final h = await _buildHarness();
      h.ctrl.generate();
      await h.ctrl.approve();

      expect(h.state.preApplySnapshot, isNotNull);
      expect(h.state.preApplySnapshot!.peqChannels.first.bands.single.id,
          'pre-existing');
    });
  });

  group('4. cancel()/generate() preserve a prior approval\'s identity', () {
    test(
        'generate() after a completed approval keeps approvedPackageId/'
        'preApplySnapshot intact', () async {
      final h = await _buildHarness();
      h.ctrl.generate();
      await h.ctrl.approve();
      final approvedId = h.state.approvedPackageId;
      final snapshot = h.state.preApplySnapshot;

      h.ctrl.generate(); // start a fresh preview without approving it

      expect(h.state.approvedPackageId, approvedId);
      expect(h.state.preApplySnapshot, snapshot);
    });

    test(
        'cancel() after a completed approval keeps approvedPackageId/'
        'preApplySnapshot intact', () async {
      final h = await _buildHarness();
      h.ctrl.generate();
      await h.ctrl.approve();
      final approvedId = h.state.approvedPackageId;

      h.ctrl.generate();
      h.ctrl.cancel();

      expect(h.state.approvedPackageId, approvedId);
    });
  });

  group('5. requestRollback()', () {
    test('fail-closed: no prior approval -> no rollback package, error set',
        () async {
      final h = await _buildHarness();
      final ok = await h.ctrl.requestRollback();
      expect(ok, isFalse);
      expect(h.state.rollbackPhase, RoomRollbackPhase.none);
      expect(h.state.error, isNotNull);
    });

    test(
        'with a snapshot: builds and persists a rollback exportState '
        'package restoring the pre-apply Woofer PEQ', () async {
      final h = await _buildHarness();
      h.ctrl.generate();
      await h.ctrl.approve();
      final correctionPackageId = h.state.approvedPackageId;

      final ok = await h.ctrl.requestRollback();

      expect(ok, isTrue);
      expect(h.state.rollbackPhase, RoomRollbackPhase.approved);
      expect(h.state.rollbackApprovedPackageId, isNotNull);
      expect(h.state.rollbackApprovedPackageId, isNot(correctionPackageId),
          reason: 'The rollback package must have its own identity, '
              'independent of the original correction package.');
      expect(h.project.exportState.activePackageId,
          h.state.rollbackApprovedPackageId);

      final pkg = h.project.exportState.packages
          .firstWhere((p) => p.id == h.state.rollbackApprovedPackageId);
      for (final block in pkg.parameterBlocks) {
        expect(block.type, ExportBlockType.peq);
        expect(block.channelId, anyOf('ch_wf_l', 'ch_wf_r'));
      }
    });

    test(
        'rollback never calls a hardware write executor — only '
        'exportState is touched', () async {
      final h = await _buildHarness();
      h.ctrl.generate();
      await h.ctrl.approve();
      final beforeConnection = h.project.connection;
      final beforeHardwareState = h.project.hardwareState;

      await h.ctrl.requestRollback();

      expect(h.project.connection, beforeConnection);
      expect(h.project.hardwareState, same(beforeHardwareState));
    });
  });
}
