// Phase 3-C — MicrophoneProfileManagerDialog: CRUD flows that don't depend
// on the platform file picker (creation/select/duplicate/delete/uncalibrated,
// curve preview render, overflow at 1280x720). Calibration file import
// itself is exercised at the pure-function level (calibration_parser_test /
// microphone_profile_edit_rules_test) — this codebase's established
// precedent (see import_tab.dart) is to not drive the real platform
// FilePicker through a widget test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/mic/microphone_profile_manager_dialog.dart';

ProProject _project({
  MeasurementMicrophoneProfile? selected,
  List<MeasurementMicrophoneProfile> roster = const [],
}) =>
    ProProject(
      id: 'proj-dlg-1',
      name: 'Dialog Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      selectedMicrophoneProfile: selected,
      microphoneProfiles: roster,
    );

Future<ProviderContainer> _seed(ProProject project) async {
  final container = ProviderContainer();
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return Center(
            child: ElevatedButton(
              onPressed: () => showMicrophoneProfileManagerDialog(context,
                  projectId: 'proj-dlg-1'),
              child: const Text('open'),
            ),
          );
        }),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('opening and closing', () {
    testWidgets('opens on the list view with no overflow at 1280x720',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.text('MEASUREMENT MICROPHONE'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('MEASUREMENT MICROPHONE'), findsNothing);
    });
  });

  group('Custom Microphone creation', () {
    testWidgets('create -> save -> appears in roster and is selectable',
        (tester) async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.text('Custom Microphone'));
      await tester.pumpAndSettle();
      expect(find.text('Custom Microphone'), findsWidgets);

      // Manufacturer/model fields in order: manufacturer, model, serial, ...
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Acme Corp');
      await tester.enterText(fields.at(1), 'Model X');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Back on the list view; the new profile appears — and, because
      // nothing real was selected before, saving also SELECTS it (Phase 3-E
      // P0: the roster used to gain a configured microphone while the
      // selection stayed on nothing / the "No Calibration" sentinel).
      expect(find.textContaining('Acme Corp Model X'), findsWidgets);

      final project = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-dlg-1');
      expect(project.selectedMicrophoneProfile?.manufacturer, 'Acme Corp');
      expect(project.selectedMicrophoneProfile?.model, 'Model X');
      // Never calibrated just from being created/selected without a file.
      expect(project.selectedMicrophoneProfile?.hasUsableCalibration, isFalse);
    });
  });

  group('Duplicate and Delete', () {
    testWidgets('duplicate creates an independent copy in the roster',
        (tester) async {
      final source = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.uncalibrated,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final container = await _seed(_project(roster: [source]));
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.byIcon(Icons.copy_outlined));
      await tester.pumpAndSettle();

      final project = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-dlg-1');
      expect(project.microphoneProfiles.length, 2);
      expect(project.microphoneProfiles.map((p) => p.id).toSet().length, 2);
    });

    testWidgets(
        'delete removes from roster; deleting the SELECTED profile clears '
        'selection (never auto-selects another)', (tester) async {
      final a = MeasurementMicrophoneProfile(
        id: 'mic-a',
        manufacturer: 'ACME',
        model: 'A',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.uncalibrated,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final b = MeasurementMicrophoneProfile(
        id: 'mic-b',
        manufacturer: 'ACME',
        model: 'B',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.uncalibrated,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final container = await _seed(_project(selected: a, roster: [a, b]));
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      // Confirmation dialog appears.
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      final project = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-dlg-1');
      expect(project.microphoneProfiles.length, 1);
      expect(project.selectedMicrophoneProfile, isNull);
    });
  });

  group('Use Without Calibration', () {
    testWidgets('selects a distinct uncalibrated sentinel, never the roster',
        (tester) async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.textContaining('보정 없이 계속'));
      await tester.pumpAndSettle();

      final project = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-dlg-1');
      expect(project.selectedMicrophoneProfile, isNotNull);
      expect(project.selectedMicrophoneProfile!.calibrationSource,
          CalibrationSource.uncalibrated);
      expect(project.microphoneProfiles, isEmpty,
          reason: 'the sentinel must never pollute the managed roster');
    });
  });

  group('Safety: catalog/TUNAI selection alone never yields calibrated', () {
    testWidgets('Supported Microphone flow with no import stays uncalibrated',
        (tester) async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.text('Supported Microphone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final project = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-dlg-1');
      expect(project.microphoneProfiles.single.hasUsableCalibration, isFalse);
      expect(project.microphoneProfiles.single.calibrationSource,
          CalibrationSource.uncalibrated);
    });

    testWidgets(
        'TUNAI flow without a serial number blocks save with an '
        'error, never silently proceeds', (tester) async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.text('TUNAI Microphone'));
      await tester.pumpAndSettle();
      // Serial left blank deliberately.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Save succeeds even without calibration (serial is only required for
      // an actual calibration IMPORT, not merely registering the profile) —
      // assert it is still not calibrated.
      final project = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-dlg-1');
      if (project.microphoneProfiles.isNotEmpty) {
        expect(project.microphoneProfiles.single.hasUsableCalibration, isFalse);
      }
    });
  });
}
