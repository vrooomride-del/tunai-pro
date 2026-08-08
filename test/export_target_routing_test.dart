// P0-5 — Export screen TARGET/PRECISION must reflect the project's real
// dspTarget instead of defaulting to (and staying at) "Simulation Only" /
// "Floating-Point" forever, while never overriding an explicit user choice.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/workbench/tabs/export_tab.dart';

ProProject _project({
  String id = 'proj-1',
  String dspTarget = 'ADAU1701',
  ExportProjectState? exportState,
}) =>
    ProProject(
      id: id,
      name: 'Export Routing Test',
      dspTarget: dspTarget,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      exportState: exportState ?? ExportProjectState.createDefault(),
    );

Future<ProviderContainer> _seed(ProProject project) async {
  final container = ProviderContainer();
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  return container;
}

/// The "no active package" placeholder Row in export_tab.dart has a
/// pre-existing overflow at the default 800x600 test surface (unrelated to
/// this fix) — widen the surface so these tests exercise the routing logic
/// without tripping on that separate layout issue.
void _widenSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'ADAU1701 project with untouched default target auto-syncs to '
      'TARGET=ADAU1701 / PRECISION=Fixed-Point', (tester) async {
    final container = await _seed(_project(dspTarget: 'ADAU1701'));
    addTearDown(container.dispose);
    _widenSurface(tester);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: ExportTab(projectId: 'proj-1'))),
    ));
    await tester.pump();

    final project = container
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'proj-1');
    expect(project.exportState.selectedTarget, DspTargetPlatform.adau1701);
    expect(find.text('ADAU1701'), findsWidgets);
    expect(find.text('Fixed-Point'), findsOneWidget);
  });

  testWidgets(
      'ADAU1466 project with untouched default target auto-syncs to '
      'TARGET=ADAU1466', (tester) async {
    final container = await _seed(_project(dspTarget: 'ADAU1466'));
    addTearDown(container.dispose);
    _widenSurface(tester);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: ExportTab(projectId: 'proj-1'))),
    ));
    await tester.pump();

    final project = container
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'proj-1');
    expect(project.exportState.selectedTarget, DspTargetPlatform.adau1466);
  });

  testWidgets(
      'a user explicitly choosing Simulation Only is never overridden back '
      'to the hardware target on rebuild', (tester) async {
    final container = await _seed(_project(
      dspTarget: 'ADAU1701',
      exportState:
          ExportProjectState(selectedTarget: DspTargetPlatform.simulationOnly),
    ));
    addTearDown(container.dispose);
    _widenSurface(tester);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: ExportTab(projectId: 'proj-1'))),
    ));
    await tester.pump();
    // First build auto-syncs (nothing distinguishes this from "untouched
    // default" yet) — confirm the sync happened once.
    expect(
        container
            .read(proProjectStoreProvider)
            .projects
            .first
            .exportState
            .selectedTarget,
        DspTargetPlatform.adau1701);

    // Now the user explicitly picks Simulation Only.
    await tester.tap(find.text('Simulation Only'));
    await tester.pump();
    expect(
        container
            .read(proProjectStoreProvider)
            .projects
            .first
            .exportState
            .selectedTarget,
        DspTargetPlatform.simulationOnly);

    // A further rebuild (e.g. unrelated state change) must not silently
    // flip it back to ADAU1701 — the guard is per-project, already fired.
    await tester.pump();
    expect(
        container
            .read(proProjectStoreProvider)
            .projects
            .first
            .exportState
            .selectedTarget,
        DspTargetPlatform.simulationOnly);
  });

  testWidgets('unrecognized dspTarget never guesses a hardware platform',
      (tester) async {
    final container = await _seed(_project(dspTarget: 'SomeOtherChip'));
    addTearDown(container.dispose);
    _widenSurface(tester);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: ExportTab(projectId: 'proj-1'))),
    ));
    await tester.pump();

    expect(
        container
            .read(proProjectStoreProvider)
            .projects
            .first
            .exportState
            .selectedTarget,
        DspTargetPlatform.simulationOnly);
  });

  testWidgets(
      'a project that already had an explicit target before this fix is '
      'left untouched', (tester) async {
    final container = await _seed(_project(
      dspTarget: 'ADAU1701',
      exportState:
          ExportProjectState(selectedTarget: DspTargetPlatform.genericBiquad),
    ));
    addTearDown(container.dispose);
    _widenSurface(tester);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: ExportTab(projectId: 'proj-1'))),
    ));
    await tester.pump();

    expect(
        container
            .read(proProjectStoreProvider)
            .projects
            .first
            .exportState
            .selectedTarget,
        DspTargetPlatform.genericBiquad,
        reason: 'only the untouched simulationOnly default is ever synced');
  });
}
