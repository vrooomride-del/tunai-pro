import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/full_system_closed_loop_evaluator.dart';
import 'package:tunai_pro/core/orchestrator/full_system_after_frd_input.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';

const _ids = ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'];

ParsedMeasurementData _frd(String id, double magnitude) =>
    ParsedMeasurementData(
      id: id,
      sourceFileName: '$id.frd',
      fileType: AcousticFileType.frd,
      importedAt: DateTime(2026, 8, 1),
      points: [
        for (final frequency in [100.0, 1000.0, 10000.0])
          MeasurementDataPoint(
              frequencyHz: frequency, magnitudeDb: magnitude, phaseDeg: 0),
      ],
    );

ParsedMeasurementData _zma(String id) => ParsedMeasurementData(
      id: id,
      sourceFileName: '$id.zma',
      fileType: AcousticFileType.zma,
      importedAt: DateTime(2026, 8, 1),
      points: const [MeasurementDataPoint(frequencyHz: 100, impedanceOhm: 8)],
    );

ProProject _factoryProject() {
  final now = DateTime(2026, 8, 1);
  return ProProject(
    id: 'project',
    name: 'project',
    createdAt: now,
    updatedAt: now,
    safetyStatus: SafetyStatus.verified,
    acousticState: MeasurementProjectState(
      driverChannels: [
        for (var i = 0; i < _ids.length; i++)
          DriverChannel(
            id: _ids[i],
            name: _ids[i],
            role: i.isEven ? DriverRole.tweeter : DriverRole.woofer,
            side: i < 2 ? DriverSide.left : DriverSide.right,
            frdData: _frd('factory-${_ids[i]}', -8),
            zmaData: _zma('zma-${_ids[i]}'),
          ),
      ],
    ),
  );
}

void main() {
  group('four-channel After FRD input', () {
    test('preserves Factory Before and maps four After channels separately',
        () {
      final factory = _factoryProject();
      final input = FullSystemAfterFrdInput(factory);
      for (final id in _ids) {
        input.add(channelId: id, afterFrd: _frd('after-$id', -10));
      }

      final after = input.buildAfterProject();
      for (final id in _ids) {
        expect(
            factory.acousticState.driverChannels
                .singleWhere((channel) => channel.id == id)
                .frdData!
                .id,
            'factory-$id');
        final afterChannel = after.acousticState.driverChannels
            .singleWhere((channel) => channel.id == id);
        expect(afterChannel.frdData!.id, 'after-$id');
        expect(afterChannel.zmaData!.id, 'zma-$id');
      }
    });

    test('missing and duplicate channels fail closed', () {
      final input = FullSystemAfterFrdInput(_factoryProject());
      input.add(channelId: 'ch_tw_l', afterFrd: _frd('after-tw-l', -10));
      expect(() => input.buildAfterProject(), throwsStateError);
      expect(
          () => input.add(
              channelId: 'ch_tw_l', afterFrd: _frd('after-tw-l-2', -10)),
          throwsStateError);
    });

    test('same spectrum is rejected even when the FRD name changes', () {
      final factory = _factoryProject();
      final input = FullSystemAfterFrdInput(factory);
      final original = factory.acousticState.driverChannels.first.frdData!;
      final renamed = ParsedMeasurementData(
        id: 'renamed-after',
        sourceFileName: 'new-name.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime(2030, 1, 1),
        points: original.points,
      );
      expect(
          () => input.add(channelId: 'ch_tw_l', afterFrd: renamed),
          throwsA(predicate((e) => e.toString().contains(
              FullSystemAfterFrdInput.identicalMeasurementMessage))));
    });

    test('one identical channel blocks a complete four-channel set', () {
      final factory = _factoryProject();
      final input = FullSystemAfterFrdInput(factory);
      final same = factory.acousticState.driverChannels.first.frdData!;
      expect(() => input.add(channelId: 'ch_tw_l', afterFrd: same), throwsStateError);
      expect(input.afterByChannel, isEmpty);
    });

    test('complete set invokes existing closed-loop verdict with no write', () {
      var hardwareWrites = 0;
      final factory = _factoryProject();
      final input = FullSystemAfterFrdInput(factory);
      for (final id in _ids) {
        input.add(channelId: id, afterFrd: _frd('after-$id', -10));
      }

      final result = FullSystemClosedLoopEvaluator.evaluate(
        beforeProject: factory,
        afterProject: input.buildAfterProject(),
        previousTuningState: factory.tuningState,
        deployedTuningState: factory.tuningState,
        cycleNumber: 1,
        safetyPassed: true,
        beforeEvidenceRefs: input.beforeEvidenceRefs,
        afterEvidenceRefs: input.afterEvidenceRefs,
      );

      expect(result.approved, isTrue);
      expect(hardwareWrites, 0,
          reason: 'measurement evaluation must not write before approval');
    });
  });
}
