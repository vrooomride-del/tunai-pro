// Workbench navigation regression tests — Phase 16-B nav entry.
//
// Verifies:
//   1. "Guided AI" tab item appears in the sidebar
//   2. Selecting it renders GuidedAiScreen content (no crash)
//   3. "Optimizer" tab still renders Draft Optimizer (regression)
//   4. No crash when current project is null (no project/measurement data)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';

// ── Widget helper ─────────────────────────────────────────────────────────────

// Uses real providers with mocked SharedPreferences (both stores start empty).
// WorkbenchShell finds no project for 'test-proj' → renders idle / no-project state.
Widget _shell() => const ProviderScope(
      child: MaterialApp(
        home: WorkbenchShell(projectId: 'test-proj'),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── 1. Guided AI 탭 존재 ──────────────────────────────────────────────────

  group('1. Guided AI tab exists in sidebar', () {
    testWidgets('"Guided AI" label is visible in the sidebar', (tester) async {
      await tester.pumpWidget(_shell());
      await tester.pump();

      expect(find.text('Guided AI'), findsOneWidget);
    });

    testWidgets('"Optimizer" label is still present', (tester) async {
      await tester.pumpWidget(_shell());
      await tester.pump();

      expect(find.text('Optimizer'), findsOneWidget);
    });
  });

  // ── 2. Guided AI 선택 → GuidedAiScreen 렌더링 ────────────────────────────

  group('2. selecting Guided AI renders GuidedAiScreen content', () {
    testWidgets('tap "Guided AI" → GUIDED AI header appears', (tester) async {
      await tester.pumpWidget(_shell());
      await tester.pump();

      await tester.tap(find.text('Guided AI'));
      await tester.pump();

      expect(find.text('GUIDED AI'), findsOneWidget);
    });

    testWidgets('tap "Guided AI" → no crash when project is null',
        (tester) async {
      await tester.pumpWidget(_shell());
      await tester.pump();

      await tester.tap(find.text('Guided AI'));
      await tester.pump();

      // Screen shows idle state — "프로젝트를 먼저 선택하세요." since project is null.
      expect(find.textContaining('프로젝트'), findsAtLeastNWidgets(1));
    });
  });

  // ── 3. Optimizer 회귀 ─────────────────────────────────────────────────────

  group('3. Optimizer tab still opens Draft Optimizer (regression)', () {
    testWidgets('tap "Optimizer" → "Draft Optimizer" text appears',
        (tester) async {
      // OptimizerTab requires sufficient horizontal space (desktop width).
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell());
      await tester.pump();

      await tester.tap(find.text('Optimizer'));
      await tester.pump();

      expect(find.text('Draft Optimizer'), findsOneWidget);
    });
  });

  // ── 4. No crash without project/measurement data ──────────────────────────

  group('4. no crash with empty project/measurement state', () {
    testWidgets('shell renders without a project and without crash',
        (tester) async {
      await tester.pumpWidget(_shell());
      await tester.pump();

      // Sidebar visible — at minimum Project tab renders.
      expect(find.text('Guided AI'), findsOneWidget);
    });
  });
}
