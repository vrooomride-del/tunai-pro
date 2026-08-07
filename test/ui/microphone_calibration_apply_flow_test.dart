// Phase 3-E P0 #3 — applying a calibration file, through the real UI.
//
// The runtime trace showed the file parsing perfectly (615 points) and then
// being thrown away: the parsed curve waits in _pendingParse until the user
// applies it, but that apply button lives inside the scrolling form while
// Save sits outside it. Pressing Save first silently persisted an
// UNCALIBRATED profile.
//
// These tests drive the actual widgets — real file picker call, real preview,
// real buttons, real store — because a test that calls
// _confirmPendingCalibration() directly cannot see this class of bug at all.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/calibration/microphone_profile_edit_rules.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_presentation.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_provider.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';
import 'package:tunai_pro/features/mic/microphone_profile_manager_dialog.dart';

const _pid = 'cal-apply-1';

/// Returns the real 7018617.txt for any pick — the production code path
/// (File(path).readAsString + CalibrationFileParser) runs unchanged.
class _FakeFilePicker extends FilePicker {
  int pickCount = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pickCount++;
    final path = File('test/fixtures/7018617.txt').absolute.path;
    return FilePickerResult([
      PlatformFile(
        path: path,
        name: '7018617.txt',
        size: File(path).lengthSync(),
      ),
    ]);
  }
}

Future<ProviderContainer> _seed() async {
  final c = ProviderContainer();
  await c.read(proProjectStoreProvider.notifier).addProject(ProProject(
        id: _pid,
        name: 'Cal Apply',
        dspTarget: 'ADAU1701',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ));
  await c.read(proProjectStoreProvider.notifier).setCurrentProject(_pid);
  return c;
}

Future<void> _openManager(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(
      home: Scaffold(body: MicrophoneProfileManagerDialog(projectId: _pid)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Creates a Supported-microphone draft and imports the real file, stopping
/// BEFORE the calibration is applied.
Future<void> _importWithoutApplying(WidgetTester tester) async {
  await tester.tap(find.text('Supported Microphone'));
  await tester.pumpAndSettle();

  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'miniDSP');
  await tester.enterText(fields.at(1), 'UMIK-1');
  await tester.pumpAndSettle();

  // The import button lives at the bottom of the scrolling form — the very
  // reason a user can press Save without ever reaching the apply step.
  await tester.ensureVisible(find.text('Import Calibration File'));
  await tester.pumpAndSettle();
  // The production path does real file I/O (File.readAsString), which needs
  // a live async zone in a widget test.
  await tester.runAsync(() async {
    await tester.tap(find.text('Import Calibration File'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

ProProject _project(ProviderContainer c) =>
    c.read(proProjectStoreProvider).projects.firstWhere((p) => p.id == _pid);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeFilePicker picker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    picker = _FakeFilePicker();
    FilePicker.platform = picker;
  });

  testWidgets('import -> apply -> save produces a calibrated selected profile',
      (tester) async {
    final c = await _seed();
    addTearDown(c.dispose);
    await _openManager(tester, c);
    await _importWithoutApplying(tester);

    expect(picker.pickCount, 1);
    expect(find.textContaining('아직 적용되지 않았습니다'), findsWidgets,
        reason: 'the outstanding action must be visible');

    // Apply, using the affordance next to Save (no scrolling required).
    // .last is the affordance in the action row, next to Save — reachable
    // without scrolling, which is exactly the property under test.
    await tester.tap(find.text('보정 파일 적용').last);
    await tester.pumpAndSettle();

    // §3 — the confirm success contract.
    expect(find.textContaining('아직 적용되지 않았습니다'), findsNothing,
        reason: 'nothing is pending once it has been applied');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final selected = _project(c).selectedMicrophoneProfile!;
    expect(selected.model, 'UMIK-1');
    expect(selected.manufacturer, 'miniDSP');
    expect(selected.calibrationCurve, isNotNull);
    expect(selected.calibrationCurve!.points.length, 615);
    expect(selected.calibrationCurve!.isStructurallyValid, isTrue);
    expect(selected.calibrationSource, isNot(CalibrationSource.uncalibrated));

    // Display + Home both read calibrated.
    expect(deriveMicrophoneDisplayState(selected),
        MicrophoneDisplayState.calibrationReady);
    final r = c.read(measurementWorkflowReadinessProvider);
    expect(r.calibrationStatus, MeasurementWorkflowCalibrationState.calibrated);
    expect(measurementWorkflowCalibrationText(r.calibrationStatus), '보정 완료');
  });

  testWidgets('saving with an unapplied import is refused, and changes nothing',
      (tester) async {
    final c = await _seed();
    addTearDown(c.dispose);
    await _openManager(tester, c);
    await _importWithoutApplying(tester);

    final before = _project(c);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Fail closed: nothing written, nothing selected, dialog still open.
    final after = _project(c);
    expect(after.microphoneProfiles, isEmpty,
        reason: 'no roster write on a refused save');
    expect(after.selectedMicrophoneProfile, isNull,
        reason: 'no selection change on a refused save');
    expect(after.updatedAt, before.updatedAt);
    expect(find.text('가져온 보정 파일을 먼저 확인해 주세요.'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget,
        reason: 'the editor stays open so the user can apply the file');

    // The imported calibration is still there to apply — never discarded.
    // .last is the affordance in the action row, next to Save — reachable
    // without scrolling, which is exactly the property under test.
    await tester.tap(find.text('보정 파일 적용').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
        _project(c).selectedMicrophoneProfile!.calibrationCurve!.points.length,
        615);
  });

  testWidgets('an explicitly uncalibrated profile stays uncalibrated',
      (tester) async {
    final c = await _seed();
    addTearDown(c.dispose);
    await _openManager(tester, c);

    // Save a profile without importing anything at all.
    await tester.tap(find.text('Custom Microphone'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'ACME');
    await tester.enterText(fields.at(1), 'Flat');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final selected = _project(c).selectedMicrophoneProfile!;
    expect(selected.calibrationSource, CalibrationSource.uncalibrated);
    expect(selected.calibrationCurve, isNull,
        reason: 'uncalibrated and a curve must never coexist');
    expect(deriveMicrophoneDisplayState(selected),
        MicrophoneDisplayState.explicitlyUncalibrated);
    expect(
        measurementWorkflowCalibrationText(
            c.read(measurementWorkflowReadinessProvider).calibrationStatus),
        '보정 없이 사용');
  });

  testWidgets(
      'the saved profile never holds a curve with an uncalibrated '
      'source', (tester) async {
    final c = await _seed();
    addTearDown(c.dispose);
    await _openManager(tester, c);
    await _importWithoutApplying(tester);
    // .last is the affordance in the action row, next to Save — reachable
    // without scrolling, which is exactly the property under test.
    await tester.tap(find.text('보정 파일 적용').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The invariant, checked over everything the project persisted.
    final project = _project(c);
    for (final p in [
      ...project.microphoneProfiles,
      if (project.selectedMicrophoneProfile != null)
        project.selectedMicrophoneProfile!,
    ]) {
      final contradictory =
          p.calibrationSource == CalibrationSource.uncalibrated &&
              p.calibrationCurve != null;
      expect(contradictory, isFalse,
          reason: 'uncalibrated + curve is a broken storage invariant');
    }
  });
}
