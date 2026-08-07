// Phase 2 — Room Auto PEQ tests.
//
// Verifies the direct-call pipeline (RoomAutoPeq.generateForSide /
// buildWritePlan) without going through ProLocalOrchestrator:
//  1. readiness: false at 1/2, true at 2/2 (RoomAutoPeq.isReady)
//  2. Left System candidates apply to ch_wf_l only, never ch_tw_l
//  3. Right System candidates apply to ch_wf_r only, never ch_tw_r
//  4. cut-only: every applied band's gainDb <= 0
//  5. buildWritePlan produces zero writable ops until called (no write side
//     effect from generateForSide itself) and the resulting plan only
//     contains PEQ blocks for Woofer channel ids
//  6. Tweeter/XO write absence: no ExportBlockType other than peq appears

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/orchestrator/room_auto_peq.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';

ParsedMeasurementData _flatFrd(String id) {
  final points = <MeasurementDataPoint>[];
  for (var f = 20.0; f <= 2000; f *= 1.05) {
    points.add(MeasurementDataPoint(frequencyHz: f, magnitudeDb: 0.0));
  }
  return ParsedMeasurementData(
    id: id,
    sourceFileName: '$id.frd',
    fileType: AcousticFileType.frd,
    importedAt: DateTime.utc(2025, 1, 1),
    points: points,
  );
}

/// Flat response with a +8 dB bass bump around 80 Hz — a broadPeak feature
/// (excess energy) that a cut-only PEQ engine CAN correct by cutting it
/// down. A dip (missing energy) would require boost, which the cut-only
/// policy never applies — verified separately as "flat -> no change".
ParsedMeasurementData _peakFrd(String id) {
  final points = <MeasurementDataPoint>[];
  for (var f = 20.0; f <= 2000; f *= 1.05) {
    final inBump = f > 60 && f < 110;
    final mag = inBump ? 8.0 : 0.0;
    points.add(MeasurementDataPoint(frequencyHz: f, magnitudeDb: mag));
  }
  return ParsedMeasurementData(
    id: id,
    sourceFileName: '$id.frd',
    fileType: AcousticFileType.frd,
    importedAt: DateTime.utc(2025, 1, 1),
    points: points,
  );
}

RoomSystemMeasurement _measurement(RoomSystemSide side,
        {String id = 'proj-x', bool flat = false}) =>
    RoomSystemMeasurement(
      side: side,
      phase: RoomMeasurementPhase.before,
      frd: flat
          ? _flatFrd('${side.name}_flat')
          : _peakFrd('${side.name}_before'),
      capturedAt: DateTime.utc(2025, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: id,
    );

void main() {
  group('1. readiness', () {
    test('1/2 -> not ready', () {
      final snapshot = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(RoomSystemSide.left),
      );
      expect(RoomAutoPeq.isReady(snapshot), isFalse);
    });

    test('2/2 -> ready', () {
      final snapshot = RoomMeasurementSnapshot(
        leftSystemFrd: _measurement(RoomSystemSide.left),
        rightSystemFrd: _measurement(RoomSystemSide.right),
      );
      expect(RoomAutoPeq.isReady(snapshot), isTrue);
    });
  });

  group('2-4. Left/Right woofer-only mapping, cut-only', () {
    test('Left System candidate targets ch_wf_l, never ch_tw_l', () {
      final result = RoomAutoPeq.generateForSide(
        side: RoomSystemSide.left,
        beforeMeasurement: _measurement(RoomSystemSide.left),
        currentWooferChannel: PeqChannelState.fixed('ch_wf_l'),
      );
      expect(result, isNotNull);
      expect(result!.channelId, 'ch_wf_l');
      expect(result.applyResult.channelId, 'ch_wf_l');
      expect(result.applyResult.applied, isNotEmpty,
          reason: 'The +8 dB bass peak fixture must actually produce a '
              'correction, otherwise the cut-only assertion below is vacuous.');
      for (final band in result.applyResult.applied) {
        expect(band.gainDb, lessThanOrEqualTo(0.0),
            reason: 'Room Auto PEQ must be cut-only, never boost.');
      }
    });

    test('Right System candidate targets ch_wf_r, never ch_tw_r', () {
      final result = RoomAutoPeq.generateForSide(
        side: RoomSystemSide.right,
        beforeMeasurement: _measurement(RoomSystemSide.right),
        currentWooferChannel: PeqChannelState.fixed('ch_wf_r'),
      );
      expect(result, isNotNull);
      expect(result!.channelId, 'ch_wf_r');
      expect(result.applyResult.channelId, 'ch_wf_r');
    });

    test('candidates are restricted to the verified low-end range', () {
      final result = RoomAutoPeq.generateForSide(
        side: RoomSystemSide.left,
        beforeMeasurement: _measurement(RoomSystemSide.left),
        currentWooferChannel: PeqChannelState.fixed('ch_wf_l'),
      );
      expect(result, isNotNull);
      for (final band in result!.applyResult.applied) {
        expect(band.frequencyHz, greaterThanOrEqualTo(roomAutoPeqMinHz));
        expect(band.frequencyHz, lessThanOrEqualTo(roomAutoPeqMaxHz));
      }
    });
  });

  group('5-6. buildWritePlan — approval-gated, PEQ-only, woofer-only', () {
    test('a flat response (no feature) -> no writable change -> null plan', () {
      final flatLeft = RoomAutoPeq.generateForSide(
        side: RoomSystemSide.left,
        beforeMeasurement: _measurement(RoomSystemSide.left, flat: true),
        currentWooferChannel: PeqChannelState.fixed('ch_wf_l'),
      );
      final flatRight = RoomAutoPeq.generateForSide(
        side: RoomSystemSide.right,
        beforeMeasurement: _measurement(RoomSystemSide.right, flat: true),
        currentWooferChannel: PeqChannelState.fixed('ch_wf_r'),
      );
      expect(flatLeft, isNotNull);
      expect(flatRight, isNotNull);
      expect(flatLeft!.hasChange, isFalse,
          reason: 'A flat response has nothing to correct.');
      expect(flatRight!.hasChange, isFalse);

      final plan = RoomAutoPeq.buildWritePlan(
        projectId: 'proj-x',
        packageId: 'pkg-1',
        candidates: [flatLeft, flatRight],
      );
      expect(plan, isNull);
    });

    test(
        'a real candidate produces exactly PEQ blocks, woofer channel ids only',
        () {
      final left = RoomAutoPeq.generateForSide(
        side: RoomSystemSide.left,
        beforeMeasurement: _measurement(RoomSystemSide.left),
        currentWooferChannel: PeqChannelState.fixed('ch_wf_l'),
      )!;
      final right = RoomAutoPeq.generateForSide(
        side: RoomSystemSide.right,
        beforeMeasurement: _measurement(RoomSystemSide.right),
        currentWooferChannel: PeqChannelState.fixed('ch_wf_r'),
      )!;

      expect(left.hasChange, isTrue,
          reason: 'A +8 dB bass peak must be cut-only correctable.');
      expect(right.hasChange, isTrue);

      final built = RoomAutoPeq.buildWritePlan(
        projectId: 'proj-x',
        packageId: 'pkg-2',
        candidates: [left, right],
      );

      {
        expect(built, isNotNull);
        final (package, writePlan) = built!;
        expect(package.parameterBlocks, isNotEmpty);
        for (final block in package.parameterBlocks) {
          expect(block.type, ExportBlockType.peq);
          expect(['ch_wf_l', 'ch_wf_r'], contains(block.channelId));
        }
        // Zero writes performed here — buildWritePlan only constructs the
        // plan object; HardwareWriteExecutor.execute() is a separate,
        // explicit call this test never makes.
        expect(writePlan.sourceExportPackageId, package.id);
      }
    });
  });
}
