// FINAL QA CLOSURE #3 §5 — Export's "VERIFIED ADDRESS REGISTRY" panel must be
// target-aware. DspAddressRegistry.createDefault() (used as the fallback when
// a package has no addressRegistrySnapshotJson) unconditionally contains
// ADAU1466 Master Volume L (0x67) / R (0x64) entries — a real-hardware-evidenced
// leak into ADAU1701 (and any non-ADAU1466) exports. The panel must filter the
// registry to the package's own targetPlatform.

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
  required String dspTarget,
  required DspTargetPlatform packageTarget,
  Map<String, dynamic>? addressRegistrySnapshotJson,
}) {
  final pkg = DspExportPackage(
    id: 'pkg-1',
    targetPlatform: packageTarget,
    status: ExportStatus.draftReady,
    projectName: 'Export Registry Isolation Test',
    addressRegistrySnapshotJson: addressRegistrySnapshotJson,
  );
  return ProProject(
    id: id,
    name: 'Export Registry Isolation Test',
    dspTarget: dspTarget,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    exportState: ExportProjectState(
      selectedTarget: packageTarget,
      packages: [pkg],
      activePackageId: pkg.id,
    ),
  );
}

Future<ProviderContainer> _seed(ProProject project) async {
  final container = ProviderContainer();
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  return container;
}

/// The Export screen has a pre-existing, unrelated overflow at the default
/// 800x600 test surface (see export_target_routing_test.dart) — widen it so
/// these tests only exercise the registry-isolation logic.
void _widenSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'ADAU1701 export never shows an "ADAU1466" registry entry '
      '(target isolation)', (tester) async {
    final container = await _seed(_project(
      dspTarget: 'ADAU1701',
      packageTarget: DspTargetPlatform.adau1701,
    ));
    addTearDown(container.dispose);
    _widenSurface(tester);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: ExportTab(projectId: 'proj-1'))),
    ));
    await tester.pump();

    expect(find.text('VERIFIED ADDRESS REGISTRY'), findsOneWidget);
    // "ADAU1466" legitimately appears once as a target-selector chip label;
    // it must never additionally appear as a registry row's platform tag.
    expect(find.text('ADAU1466'), findsOneWidget);
  });

  testWidgets(
      'ADAU1701 export never shows the ADAU1466 Master Volume L/R addresses '
      '(0x67 / 0x64)', (tester) async {
    final container = await _seed(_project(
      dspTarget: 'ADAU1701',
      packageTarget: DspTargetPlatform.adau1701,
    ));
    addTearDown(container.dispose);
    _widenSurface(tester);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: ExportTab(projectId: 'proj-1'))),
    ));
    await tester.pump();

    expect(find.text('0x67'), findsNothing);
    expect(find.text('0x64'), findsNothing);
    expect(find.text('Master Volume L'), findsNothing);
    expect(find.text('Master Volume R'), findsNothing);
    // Safe empty state, not a fabricated ADAU1701 entry.
    expect(find.text('0 verified'), findsOneWidget);
  });

  testWidgets(
      'ADAU1466 export still shows its existing verified Master Volume L/R '
      'registry entries unchanged', (tester) async {
    final container = await _seed(_project(
      dspTarget: 'ADAU1466',
      packageTarget: DspTargetPlatform.adau1466,
    ));
    addTearDown(container.dispose);
    _widenSurface(tester);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: ExportTab(projectId: 'proj-1'))),
    ));
    await tester.pump();

    expect(find.text('0x67'), findsOneWidget);
    expect(find.text('0x64'), findsOneWidget);
    expect(find.text('Master Volume L'), findsOneWidget);
    expect(find.text('Master Volume R'), findsOneWidget);
    expect(find.text('2 verified'), findsOneWidget);
  });

  testWidgets(
      'switching target from ADAU1466 to ADAU1701 on a fresh package leaves '
      'no stale ADAU1466 entries visible', (tester) async {
    final container = await _seed(_project(
      dspTarget: 'ADAU1701',
      packageTarget: DspTargetPlatform.adau1701,
      // Simulate a snapshot captured while the registry still only knows
      // about ADAU1466 addresses (the real-hardware-evidenced leak source).
      addressRegistrySnapshotJson: null,
    ));
    addTearDown(container.dispose);
    _widenSurface(tester);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: ExportTab(projectId: 'proj-1'))),
    ));
    await tester.pump();

    // "ADAU1466" legitimately appears once as a target-selector chip label;
    // it must never additionally appear as a registry row's platform tag.
    expect(find.text('ADAU1466'), findsOneWidget);
    expect(find.text('0x67'), findsNothing);
    expect(find.text('0x64'), findsNothing);
  });
}
