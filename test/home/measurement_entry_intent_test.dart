// Phase 3-E P0 §5/§9 — the one-shot measurement entry intent.
//
// The failure this guards against is a dialog that reopens forever: a Home
// CTA that survives a rebuild, re-fires after the user closes the dialog, or
// leaks onto the next project. consume() is therefore compare-and-clear, and
// these tests pin that contract directly as well as through the Measure tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/measurement_entry_intent.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';
import 'package:tunai_pro/features/home/home_navigation.dart';
import 'package:tunai_pro/features/workbench/tabs/measure_tab.dart';

import '../support/capture_gate_fixtures.dart';

const _pid = 'intent-1';

ProProject _project(String id, {bool setupReady = false}) {
  final base = ProProject(
    id: id,
    name: 'Intent $id',
    dspTarget: 'ADAU1701',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
  return setupReady ? withGateReadySetup(base) : base;
}

Future<ProviderContainer> _seed({String id = _pid}) async {
  final c = ProviderContainer();
  await c.read(proProjectStoreProvider.notifier).addProject(_project(id));
  return c;
}

Future<void> _pumpMeasure(WidgetTester tester, ProviderContainer c,
    {String id = _pid}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // A distinct key per project forces a fresh State, matching production:
  // Home pushes a new WorkbenchShell route per project, so MeasureTab's
  // initState (where the intent is consumed) really does run again.
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(body: MeasureTab(key: ValueKey(id), projectId: id)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. the one-shot contract', () {
    test('consume returns the intent once, then null', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(measurementEntryIntentProvider.notifier);

      n.request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);
      expect(n.consume(_pid), MeasurementEntryIntent.manageMicrophone);
      expect(n.consume(_pid), isNull, reason: 'never a second time');
      expect(c.read(measurementEntryIntentProvider), isNull);
    });

    test('a request for another project is discarded, not held', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(measurementEntryIntentProvider.notifier);

      n.request(MeasurementEntryIntent.runSetupCheck, projectId: 'other');
      expect(n.consume(_pid), isNull, reason: 'must not leak across projects');
      expect(c.read(measurementEntryIntentProvider), isNull,
          reason: 'a navigation command does not survive a context change');
      expect(n.consume('other'), isNull,
          reason: 'and it must not fire late when that project reopens');
    });

    test('with no project open, a project-bound request is dropped', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(measurementEntryIntentProvider.notifier);

      n.request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);
      expect(n.consume(null), isNull);
      expect(c.read(measurementEntryIntentProvider), isNull);
      expect(n.consume(_pid), isNull, reason: 'never revives');
    });

    test('a fresh request after a discard still runs normally', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(measurementEntryIntentProvider.notifier);

      n.request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);
      n.consume('other'); // discards it
      n.request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);
      expect(n.consume(_pid), MeasurementEntryIntent.manageMicrophone);
    });

    test('a newer request replaces an unconsumed one', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(measurementEntryIntentProvider.notifier);

      n.request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);
      n.request(MeasurementEntryIntent.runSetupCheck, projectId: _pid);
      expect(n.consume(_pid), MeasurementEntryIntent.runSetupCheck);
      expect(n.consume(_pid), isNull);
    });

    test('the same intent twice is still two distinct requests', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(measurementEntryIntentProvider.notifier);

      n.request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);
      final first = c.read(measurementEntryIntentProvider)!.id;
      n.consume(_pid);
      n.request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);
      expect(c.read(measurementEntryIntentProvider)!.id, greaterThan(first));
      expect(n.consume(_pid), MeasurementEntryIntent.manageMicrophone);
    });
  });

  group('2. the Measure tab acts on it exactly once', () {
    testWidgets('manageMicrophone opens the Microphone Manager',
        (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);

      await _pumpMeasure(tester, c);

      expect(find.byType(Dialog), findsOneWidget);
      expect(c.read(measurementEntryIntentProvider), isNull,
          reason: 'consumed on arrival');
    });

    testWidgets('fixCalibration opens the same manager', (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.manageCalibration, projectId: _pid);

      await _pumpMeasure(tester, c);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('runSetupCheck opens Guided Measurement Setup', (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.runSetupCheck, projectId: _pid);

      await _pumpMeasure(tester, c);
      expect(find.byType(Dialog), findsOneWidget);
      expect(c.read(measurementEntryIntentProvider), isNull);
    });

    testWidgets('selectInputDevice opens Guided Measurement Setup too',
        (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.selectInputDevice, projectId: _pid);

      await _pumpMeasure(tester, c);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('no intent opens no dialog', (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      await _pumpMeasure(tester, c);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('closing the dialog does not reopen it', (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);

      await _pumpMeasure(tester, c);
      expect(find.byType(Dialog), findsOneWidget);

      Navigator.of(tester.element(find.byType(MeasureTab))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      // And a rebuild still does not bring it back.
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an intent for a different project opens nothing here',
        (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      await c
          .read(proProjectStoreProvider.notifier)
          .addProject(_project('other'));
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.manageMicrophone, projectId: 'other');

      await _pumpMeasure(tester, c);
      expect(find.byType(Dialog), findsNothing,
          reason: 'stale intent from another project must not fire');
      expect(c.read(measurementEntryIntentProvider), isNull,
          reason: 'and it is discarded, so it cannot fire late either');
    });

    testWidgets(
        'returning to the original project does not revive its old intent',
        (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      await c
          .read(proProjectStoreProvider.notifier)
          .addProject(_project('other'));

      // Project A raises an intent...
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);

      // ...but the user detours into project B first.
      await _pumpMeasure(tester, c, id: 'other');
      expect(find.byType(Dialog), findsNothing);

      // Coming back to A must NOT replay the instruction they moved on from.
      await _pumpMeasure(tester, c);
      expect(find.byType(Dialog), findsNothing,
          reason: 'a one-shot navigation command never fires late');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new intent after a project switch still works',
        (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      await c
          .read(proProjectStoreProvider.notifier)
          .addProject(_project('other'));

      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);
      await _pumpMeasure(tester, c, id: 'other'); // discards it

      // Asking again is a brand-new request and behaves normally.
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.manageMicrophone, projectId: _pid);
      await _pumpMeasure(tester, c);
      expect(find.byType(Dialog), findsOneWidget);
      expect(c.read(measurementEntryIntentProvider), isNull);
    });

    testWidgets('room intents switch the view without opening a dialog',
        (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.roomBefore, projectId: _pid);

      await _pumpMeasure(tester, c);
      expect(find.byType(Dialog), findsNothing);
      expect(c.read(measureModeIsRoomProvider(_pid)), isTrue);
      expect(c.read(measurementEntryIntentProvider), isNull);
    });

    testWidgets('factory intent selects the Factory view', (tester) async {
      final c = await _seed();
      addTearDown(c.dispose);
      c.read(measureModeIsRoomProvider(_pid).notifier).state = true;
      c
          .read(measurementEntryIntentProvider.notifier)
          .request(MeasurementEntryIntent.factoryMeasurement, projectId: _pid);

      await _pumpMeasure(tester, c);
      expect(c.read(measureModeIsRoomProvider(_pid)), isFalse);
    });
  });

  group('3. every Home CTA carries the right intent (§4)', () {
    MeasurementEntryIntent? intentOf(MeasurementWorkflowAction a) {
      final d = homeActionDestination(a);
      return d is HomeWorkbenchDestination ? d.intent : null;
    }

    test('the microphone/setup actions deep-link, not just switch tabs', () {
      expect(intentOf(MeasurementWorkflowAction.selectMicrophone),
          MeasurementEntryIntent.manageMicrophone);
      expect(intentOf(MeasurementWorkflowAction.fixCalibration),
          MeasurementEntryIntent.manageCalibration);
      expect(intentOf(MeasurementWorkflowAction.selectInputDevice),
          MeasurementEntryIntent.selectInputDevice);
      expect(intentOf(MeasurementWorkflowAction.checkMeasurementSetup),
          MeasurementEntryIntent.runSetupCheck);
    });

    test('a failed Before pair sends the user to the measurement chain', () {
      expect(intentOf(MeasurementWorkflowAction.resolveRoomMeasurementQuality),
          MeasurementEntryIntent.manageMicrophone,
          reason: 're-capturing with the same mismatched chain would just '
              'reproduce the failure');
    });

    test('the capture actions carry their own phase', () {
      expect(intentOf(MeasurementWorkflowAction.measureFactoryDrivers),
          MeasurementEntryIntent.factoryMeasurement);
      expect(intentOf(MeasurementWorkflowAction.measureRoomBefore),
          MeasurementEntryIntent.roomBefore);
      expect(intentOf(MeasurementWorkflowAction.measureRoomAfter),
          MeasurementEntryIntent.roomAfter);
      expect(intentOf(MeasurementWorkflowAction.resolveBeforeAfterMismatch),
          MeasurementEntryIntent.roomAfter);
      expect(intentOf(MeasurementWorkflowAction.reviewClosedLoop),
          MeasurementEntryIntent.closedLoopReview);
    });

    test('actions that leave the Measure tab carry no intent', () {
      for (final a in [
        MeasurementWorkflowAction.runFactoryGuidedTuning,
        MeasurementWorkflowAction.generateRoomAutoPeq,
        MeasurementWorkflowAction.deployRoomCorrection,
        MeasurementWorkflowAction.complete,
      ]) {
        expect(intentOf(a), isNull, reason: a.name);
      }
      expect(
          homeActionDestination(MeasurementWorkflowAction.createOrOpenProject),
          isA<HomeProjectListDestination>());
    });
  });
}
