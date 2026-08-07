// Phase 3-E §15 — the simulated MeasurementSession surface is not part of the
// production guided workflow.
//
// Home's Continue Tuning sends beginners to the Measure tab, so synthetic
// session data must not be sitting there looking like a real measurement.
// It is hidden by default and revealed only by an explicit user action —
// hidden, not deleted.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/diagnostics_visibility.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/workbench/tabs/measure_tab.dart';

import '../support/capture_gate_fixtures.dart';

const _pid = 'diag-1';

Future<ProviderContainer> _seed() async {
  final c = ProviderContainer();
  await c.read(proProjectStoreProvider.notifier).addProject(
        withGateReadySetup(ProProject(
          id: _pid,
          name: 'Diagnostics',
          dspTarget: 'ADAU1701',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        )),
      );
  return c;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: MeasureTab(projectId: _pid))),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the simulated session surface is hidden by default',
      (tester) async {
    final c = await _seed();
    addTearDown(c.dispose);
    await _pump(tester, c);

    expect(c.read(diagnosticsVisibleProvider), isFalse);
    expect(find.text('SIMULATED DATA'), findsNothing);
    expect(find.text('Sessions'), findsNothing);
    // The real capture path is still there — this hides diagnostics, not
    // measurement.
    expect(find.textContaining('MEASUREMENT'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an explicit toggle brings it back unchanged', (tester) async {
    final c = await _seed();
    addTearDown(c.dispose);
    await _pump(tester, c);

    await tester.tap(find.text('진단 도구 (시뮬레이션 세션)'));
    await tester.pump();

    expect(c.read(diagnosticsVisibleProvider), isTrue);
    expect(find.text('SIMULATED DATA'), findsOneWidget);
    expect(find.text('진단 도구 숨기기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
