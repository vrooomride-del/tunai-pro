// Phase 2 safety audit — Factory / Room Auto PEQ non-interference.
//
// Both readiness models (Factory 4/4 FrdReadiness vs Room 2/2
// RoomMeasurementSnapshot) and both controllers
// (guidedAiProvider-adjacent Factory readiness is stateless/derived;
// roomAutoPeqControllerProvider is a separate family-scoped StateNotifier)
// are structurally independent. This pins that down at the widget level:
// generating Room candidates must not change anything Factory's card shows,
// and vice versa is trivially true since Factory's card has no Room
// dependency at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';

DriverChannel _channelWithFrd(String id, DriverRole role, DriverSide side) =>
    DriverChannel(
      id: id,
      name: id,
      role: role,
      side: side,
      frdData: ParsedMeasurementData(
        id: '$id-frd',
        sourceFileName: '$id.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2025, 1, 1),
        points: const [
          MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 85.0)
        ],
      ),
    );

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

RoomSystemMeasurement _roomMeasurement(RoomSystemSide side, String projectId) =>
    RoomSystemMeasurement(
      side: side,
      phase: RoomMeasurementPhase.before,
      frd: _flatFrd('${side.name}_flat'),
      capturedAt: DateTime.utc(2025, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: projectId,
    );

const _projectId = 'noninterference-proj';

ProProject _bothReadyProject() => ProProject(
      id: _projectId,
      name: 'Both Ready',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      acousticState: MeasurementProjectState(driverChannels: [
        _channelWithFrd('ch_tw_l', DriverRole.tweeter, DriverSide.left),
        _channelWithFrd('ch_wf_l', DriverRole.woofer, DriverSide.left),
        _channelWithFrd('ch_tw_r', DriverRole.tweeter, DriverSide.right),
        _channelWithFrd('ch_wf_r', DriverRole.woofer, DriverSide.right),
      ]),
      roomState: RoomMeasurementProjectState(
        before: RoomMeasurementSnapshot(
          leftSystemFrd: _roomMeasurement(RoomSystemSide.left, _projectId),
          rightSystemFrd: _roomMeasurement(RoomSystemSide.right, _projectId),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'Factory 4/4 readiness and Room 2/2 readiness render independently, '
      'and generating Room candidates does not change the Factory card',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(proProjectStoreProvider.notifier)
        .addProject(_bothReadyProject());
    container.read(workbenchTabProvider.notifier).go(17); // kTabAutoPeq

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: WorkbenchShell(projectId: _projectId)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Factory readiness: 4/4, entry action enabled.
    expect(find.textContaining('4채널 FRD 준비 완료'), findsOneWidget);
    final factoryButtonTextBefore =
        tester.widget<Text>(find.text('Guided AI에서 실행')).data;

    // Room readiness: 2/2, independent provider.
    expect(find.textContaining('Before Left+Right: 2/2'), findsOneWidget);

    // Act only on Room — generate candidates.
    await tester.tap(find.text('Room Auto PEQ 후보 생성'));
    await tester.pump();

    // Factory's card must be byte-for-byte unaffected.
    expect(find.textContaining('4채널 FRD 준비 완료'), findsOneWidget);
    final factoryButtonTextAfter =
        tester.widget<Text>(find.text('Guided AI에서 실행')).data;
    expect(factoryButtonTextAfter, factoryButtonTextBefore);

    expect(tester.takeException(), isNull);
  });
}
