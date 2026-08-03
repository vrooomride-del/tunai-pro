// Phase 5-A-3A: Custom Target Curve preset must present as "Coming soon"
// and must never become selectable through the UI, while the four
// functional presets (Flat/Studio/Warm/Nearfield) keep updating
// targetCurve exactly as before.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/workbench/tabs/target_tab.dart';

const _kProjectsKey = 'tunai_pro_projects';

ProProject _projectWithPreset(TargetCurvePreset preset) => ProProject(
      id: 'test-proj',
      name: 'Test Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      acousticState: MeasurementProjectState(
        targetCurve: TargetCurveState(selectedPreset: preset),
      ),
    );

void _seedProjects(List<ProProject> projects) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList(projects),
  });
}

Widget _targetTab() => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 900,
            child: const TargetTab(projectId: 'test-proj'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('Custom preset card shows a COMING SOON badge', (tester) async {
    _seedProjects([_projectWithPreset(TargetCurvePreset.flat)]);
    await tester.pumpWidget(_targetTab());
    await tester.pumpAndSettle();

    expect(find.text('COMING SOON'), findsOneWidget);
  });

  testWidgets(
      'Custom preset description states future PRO functionality, not '
      "the model's original 'specify manually or import' text", (tester) async {
    _seedProjects([_projectWithPreset(TargetCurvePreset.flat)]);
    await tester.pumpWidget(_targetTab());
    await tester.pumpAndSettle();

    expect(find.textContaining('Coming soon'), findsWidgets);
    expect(
        find.textContaining(
            'Specify manually or import from file.'),
        findsNothing);
  });

  testWidgets(
      'tapping the Custom preset card does not select it or write the store',
      (tester) async {
    _seedProjects([_projectWithPreset(TargetCurvePreset.flat)]);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 900,
            child: const TargetTab(projectId: 'test-proj'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    final project = container
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'test-proj');
    expect(project.acousticState.targetCurve.selectedPreset,
        TargetCurvePreset.flat,
        reason: 'Custom must never become active via a UI tap');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a project that already had custom persisted still shows it as '
      'Coming soon, not as a normal active selection', (tester) async {
    _seedProjects([_projectWithPreset(TargetCurvePreset.custom)]);
    await tester.pumpWidget(_targetTab());
    await tester.pumpAndSettle();

    expect(find.text('COMING SOON'), findsAtLeastNWidgets(1));
    expect(find.text('SELECTED'), findsNothing,
        reason:
            'the current-target summary must not present custom as a normal '
            'selected/working preset');
  });

  for (final preset in [
    TargetCurvePreset.flat,
    TargetCurvePreset.studio,
    TargetCurvePreset.warm,
    TargetCurvePreset.nearfield,
  ]) {
    testWidgets(
        '$preset still updates targetCurve.selectedPreset via updateAcousticState',
        (tester) async {
      // Start from a different preset so the tap is a genuine change.
      final start = preset == TargetCurvePreset.flat
          ? TargetCurvePreset.warm
          : TargetCurvePreset.flat;
      _seedProjects([_projectWithPreset(start)]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 900,
              child: const TargetTab(projectId: 'test-proj'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text(preset.label));
      await tester.pumpAndSettle();

      final project = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'test-proj');
      expect(project.acousticState.targetCurve.selectedPreset, preset);
      expect(tester.takeException(), isNull);
    });
  }
}
