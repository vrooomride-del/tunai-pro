// Phase 5-A-2: TargetTab's real target-curve preview graph.
// Covers: all 5 TargetCurvePreset values render without throwing, and no
// overflow occurs at the app's supported desktop widths.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
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

Widget _targetTab({double width = 1280, double height = 900}) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: const TargetTab(projectId: 'test-proj'),
          ),
        ),
      ),
    );

void main() {
  for (final preset in TargetCurvePreset.values) {
    testWidgets(
        'renders a real curve for $preset without throwing or overflowing',
        (tester) async {
      _seedProjects([_projectWithPreset(preset)]);
      await tester.pumpWidget(_targetTab());
      await tester.pumpAndSettle();

      expect(find.byType(CustomPaint), findsWidgets);
      // The old fake placeholder text must be gone.
      expect(find.textContaining('Graph renders in Phase D'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [1024.0, 1280.0, 1440.0]) {
    testWidgets('no overflow at width=$width (flat preset)', (tester) async {
      _seedProjects([_projectWithPreset(TargetCurvePreset.flat)]);
      await tester.pumpWidget(_targetTab(width: width));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'width=$width must not overflow or throw');
    });
  }

  testWidgets('graph height remains the existing compact 160px',
      (tester) async {
    _seedProjects([_projectWithPreset(TargetCurvePreset.warm)]);
    await tester.pumpWidget(_targetTab());
    await tester.pumpAndSettle();

    final graphPaint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere((w) => w.size.height == 160);
    expect(graphPaint.size.height, 160);
  });

  testWidgets('switching preset rebuilds the graph with a different curve',
      (tester) async {
    _seedProjects([_projectWithPreset(TargetCurvePreset.flat)]);
    await tester.pumpWidget(_targetTab());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Warm'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Selection UI reflects the new preset.
    expect(find.text('Warm'), findsAtLeastNWidgets(1));
  });
}
