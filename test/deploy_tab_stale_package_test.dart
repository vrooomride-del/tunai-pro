// Phase 4-C-4A: the Deploy tab must show a persistent, clear warning when
// the active deploy package is stale (tuning changed since it was built,
// e.g. after a software rollback) — no automatic rebuild, no automatic
// deploy, just a visible call-to-action.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_deploy_package_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/features/workbench/tabs/deploy_tab.dart';

const _kProjectsKey = 'tunai_pro_projects';

DeployPackage _pkg(String id, DeployPackageStatus status) => DeployPackage(
      id: id,
      version: 'v0.0.1',
      name: 'Package $id',
      kind: DeployPackageKind.fullProjectSnapshot,
      status: status,
      readinessLevel: DeployReadinessLevel.readyForDryRun,
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      snapshot: DeployPackageSnapshot(
        projectId: 'test-proj',
        projectName: 'Test',
        projectStatus: 'Tuned',
        createdAt: DateTime.utc(2025, 1, 1),
      ),
    );

ProProject _projectWithActivePackage(DeployPackageStatus status) => ProProject(
      id: 'test-proj',
      name: 'Test Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      deployState: DeployProjectState(
        packages: [_pkg('pkg1', status)],
        activePackageId: 'pkg1',
      ),
    );

void _seedProjects(List<ProProject> projects) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList(projects),
  });
}

Widget _deployTab() => ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: DeployTab(projectId: 'test-proj')),
      ),
    );

void main() {
  testWidgets(
      'active stale package shows the persistent "Stale package" warning',
      (tester) async {
    _seedProjects([_projectWithActivePackage(DeployPackageStatus.stale)]);
    await tester.pumpWidget(_deployTab());
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
          'Stale package — tuning changed after this package was created.'),
      findsOneWidget,
    );
    expect(find.textContaining('Build or select a current package'),
        findsOneWidget);
  });

  testWidgets(
      'active ready package shows no stale warning', (tester) async {
    _seedProjects([_projectWithActivePackage(DeployPackageStatus.ready)]);
    await tester.pumpWidget(_deployTab());
    await tester.pumpAndSettle();

    expect(find.textContaining('Stale package'), findsNothing);
  });
}
