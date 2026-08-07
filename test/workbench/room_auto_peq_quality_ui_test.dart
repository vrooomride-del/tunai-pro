// Phase 3-D3B — Room Auto PEQ card quality readiness UI.
//
// Exercises the REAL AutoPeqTab Room card through WorkbenchShell — never a
// mocked gate. Covers Ready/missing-quality/calibration/mismatch blocker
// text, the typed remediation CTA, and no-overflow at 1280x720.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/orchestrator/room_quality_presentation.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/features/mic/microphone_profile_manager_dialog.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';
import '../support/room_quality_fixtures.dart';

ParsedMeasurementData _readyFrd(String id, String projectId) {
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
    calibrationStatus: CalibrationStatus.calibrated,
    microphoneSnapshot: roomQualityFixtureMicSnapshot(),
    qualitySnapshot: roomQualityFixtureSnapshot(projectId: projectId),
  );
}

ParsedMeasurementData _noQualityFrd(String id) {
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

RoomSystemMeasurement _measurement(
  RoomSystemSide side,
  String projectId,
  ParsedMeasurementData frd,
) =>
    RoomSystemMeasurement(
      side: side,
      phase: RoomMeasurementPhase.before,
      frd: frd,
      capturedAt: DateTime.utc(2025, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: projectId,
    );

ProProject _project(String id, RoomMeasurementSnapshot before) => ProProject(
      id: id,
      name: 'Room Quality UI Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      tuningState: TuningProjectState(peqChannels: const []),
      roomState: RoomMeasurementProjectState(before: before),
    );

Future<ProviderContainer> _seed(ProProject project) async {
  final container = ProviderContainer();
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  return container;
}

Future<void> _pumpAutoPeq(
    WidgetTester tester, ProviderContainer container, String projectId,
    {Size size = const Size(1280, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  container.read(workbenchTabProvider.notifier).go(kTabAutoPeq);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: WorkbenchShell(projectId: projectId)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Ready: both sides quality-ready shows the ready text',
      (tester) async {
    const id = 'ui-ready';
    final before = RoomMeasurementSnapshot(
      leftSystemFrd: _measurement(RoomSystemSide.left, id, _readyFrd('l', id)),
      rightSystemFrd:
          _measurement(RoomSystemSide.right, id, _readyFrd('r', id)),
    );
    final container = await _seed(_project(id, before));
    addTearDown(container.dispose);
    await _pumpAutoPeq(tester, container, id);

    expect(
        find.textContaining(kRoomBeforePairQualityReadyText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing quality on Left shows the blocker + Measure tab CTA',
      (tester) async {
    const id = 'ui-missing-quality';
    final before = RoomMeasurementSnapshot(
      leftSystemFrd: _measurement(RoomSystemSide.left, id, _noQualityFrd('l')),
      rightSystemFrd:
          _measurement(RoomSystemSide.right, id, _readyFrd('r', id)),
    );
    final container = await _seed(_project(id, before));
    addTearDown(container.dispose);
    await _pumpAutoPeq(tester, container, id);

    expect(find.text('왼쪽 측정의 품질 정보가 없습니다.'), findsOneWidget);
    expect(find.text('Measure 탭으로 이동'), findsOneWidget);

    await tester.tap(find.text('Measure 탭으로 이동'));
    await tester.pumpAndSettle();
    expect(container.read(workbenchTabProvider), kTabMeasure);
  });

  testWidgets('calibration coverage problem shows blocker + manage-mic CTA',
      (tester) async {
    const id = 'ui-calibration';
    const narrowCurve = CalibrationCurve(
      points: kRoomQualityFixtureCurvePoints,
      angle: CalibrationAngle.zeroDegree,
      validMinFrequencyHz: 100,
      validMaxFrequencyHz: 20000,
      sourceIdentity: 'narrow',
      checksum: 'narrow-curve',
    );
    final leftReady = _readyFrd('l', id);
    final leftFrd = ParsedMeasurementData(
      id: leftReady.id,
      sourceFileName: leftReady.sourceFileName,
      fileType: leftReady.fileType,
      importedAt: leftReady.importedAt,
      points: leftReady.points,
      calibrationStatus: CalibrationStatus.calibrated,
      microphoneSnapshot: MeasurementMicrophoneSnapshot(
        profileId: 'mic-narrow',
        profileChecksum: 'room-quality-fixture-checksum',
        manufacturer: 'TUNAI',
        model: 'Narrow',
        calibrationSource: CalibrationSource.userImported,
        calibrationCurve: narrowCurve,
        sampleRate: 48000,
        capturedAt: DateTime.utc(2026, 1, 1),
      ),
      qualitySnapshot: leftReady.qualitySnapshot,
    );
    final before = RoomMeasurementSnapshot(
      leftSystemFrd: _measurement(RoomSystemSide.left, id, leftFrd),
      rightSystemFrd:
          _measurement(RoomSystemSide.right, id, _readyFrd('r', id)),
    );
    final container = await _seed(_project(id, before));
    addTearDown(container.dispose);
    await _pumpAutoPeq(tester, container, id);

    expect(find.text('마이크 보정이 20–300 Hz를 포함하지 않습니다.'), findsOneWidget);
    expect(find.text('마이크 관리'), findsOneWidget);

    await tester.tap(find.text('마이크 관리'));
    await tester.pumpAndSettle();
    expect(find.byType(MicrophoneProfileManagerDialog), findsOneWidget);
  });

  testWidgets('no overflow at 1280x720', (tester) async {
    const id = 'ui-overflow';
    final before = RoomMeasurementSnapshot(
      leftSystemFrd: _measurement(RoomSystemSide.left, id, _noQualityFrd('l')),
      rightSystemFrd:
          _measurement(RoomSystemSide.right, id, _readyFrd('r', id)),
    );
    final container = await _seed(_project(id, before));
    addTearDown(container.dispose);
    await _pumpAutoPeq(tester, container, id, size: const Size(1280, 720));

    expect(tester.takeException(), isNull);
  });
}
