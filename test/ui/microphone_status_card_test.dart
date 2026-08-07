// Phase 3-C — MicrophoneStatusCard: state rendering, overflow, Manage CTA.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/calibration/microphone_profile_edit_rules.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/workbench/tabs/microphone_status_card.dart';

CalibrationCurve _validCurve() {
  const points = [
    CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
    CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
  ];
  return CalibrationCurve(
    points: points,
    validMinFrequencyHz: 20,
    validMaxFrequencyHz: 20000,
    sourceIdentity: 'test',
    checksum: CalibrationCurve.checksumFor(points),
  );
}

ProProject _project({MeasurementMicrophoneProfile? profile}) => ProProject(
      id: 'proj-status-1',
      name: 'Status Card Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      selectedMicrophoneProfile: profile,
    );

Future<ProviderContainer> _seed(ProProject project) async {
  final container = ProviderContainer();
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  return container;
}

Widget _host(ProviderContainer container, ProProject project) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: MicrophoneStatusCard(project: project)),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('display states', () {
    testWidgets('not selected', (tester) async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container, _project()));
      expect(find.text('마이크가 선택되지 않았습니다'), findsOneWidget);
      expect(find.text('선택 필요'), findsOneWidget);
    });

    testWidgets('calibrated', (tester) async {
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.userImported,
        calibrationCurve: _validCurve(),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final project = _project(profile: profile);
      final container = await _seed(project);
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container, project));
      expect(find.textContaining('ACME M1'), findsOneWidget);
      expect(find.text('보정 완료'), findsOneWidget);
    });

    testWidgets('explicitly uncalibrated', (tester) async {
      final sentinel =
          buildUncalibratedSentinelProfile(DateTime.utc(2026, 1, 1));
      final project = _project(profile: sentinel);
      final container = await _seed(project);
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container, project));
      expect(find.text('보정 없이 사용'), findsWidgets);
    });

    testWidgets('invalid (mismatched source/curve combo)', (tester) async {
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.userImported,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final project = _project(profile: profile);
      final container = await _seed(project);
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container, project));
      expect(find.text('보정 파일 확인 필요'), findsOneWidget);
    });
  });

  group('no overflow at 1280x720', () {
    testWidgets('renders cleanly', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final project = _project();
      final container = await _seed(project);
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container, project));
      expect(tester.takeException(), isNull);
    });
  });

  group('Manage CTA', () {
    testWidgets('is reachable and opens the Profile Manager dialog',
        (tester) async {
      final project = _project();
      final container = await _seed(project);
      addTearDown(container.dispose);
      await tester.pumpWidget(_host(container, project));

      final cta = find.text('마이크 설정');
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text('MEASUREMENT MICROPHONE'), findsOneWidget);
    });
  });
}
