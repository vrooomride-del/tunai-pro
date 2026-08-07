// Phase 3-D3C-3 §1/§15/§16 — the single Workspace Home provider.
//
// Home watches exactly one provider. These tests pin that it reflects the
// STORE'S CURRENT project, recomputes on a project switch, and never lets a
// previous project's progress leak into the next one.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_provider.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';

import '../support/capture_gate_fixtures.dart';

ProProject _project(String id, {bool setupReady = false}) {
  final base = ProProject(
    id: id,
    name: 'Project $id',
    dspTarget: 'ADAU1701',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
  return setupReady ? withGateReadySetup(base) : base;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('no current project -> createOrOpenProject', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final r = c.read(measurementWorkflowReadinessProvider);
    expect(r.hasProject, isFalse);
    expect(
        r.nextRecommendedAction, MeasurementWorkflowAction.createOrOpenProject);
  });

  test('reads the store\'s current project', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(proProjectStoreProvider.notifier);
    await store.addProject(_project('p1', setupReady: true));
    await store.setCurrentProject('p1');

    final r = c.read(measurementWorkflowReadinessProvider);
    expect(r.hasProject, isTrue);
    expect(r.projectId, 'p1');
    expect(r.setupState, MeasurementWorkflowSetupState.ready);
    expect(r.nextRecommendedAction,
        MeasurementWorkflowAction.measureFactoryDrivers);
  });

  test('switching projects recomputes and leaks nothing from the previous one',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(proProjectStoreProvider.notifier);
    await store.addProject(_project('ready', setupReady: true));
    await store.addProject(_project('fresh'));

    await store.setCurrentProject('ready');
    final first = c.read(measurementWorkflowReadinessProvider);
    expect(first.setupState, MeasurementWorkflowSetupState.ready);
    expect(first.microphoneSelected, isTrue);

    await store.setCurrentProject('fresh');
    final second = c.read(measurementWorkflowReadinessProvider);
    expect(second.projectId, 'fresh');
    expect(second.microphoneSelected, isFalse,
        reason: "the ready project's microphone must not carry over");
    expect(second.setupState, MeasurementWorkflowSetupState.notChecked);
    expect(second.nextRecommendedAction,
        MeasurementWorkflowAction.selectMicrophone);
  });

  test('the provider performs no I/O and is safe to read repeatedly', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(proProjectStoreProvider.notifier);
    await store.addProject(_project('p1', setupReady: true));
    await store.setCurrentProject('p1');

    for (var i = 0; i < 5; i++) {
      expect(c.read(measurementWorkflowReadinessProvider).projectId, 'p1');
    }
  });
}
