// Phase 3-D2 — ProProject.currentSetupReadiness: persistence, corrupt
// isolation, cross-project non-interference.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';

MeasurementSetupReadinessSnapshot _snapshot({String projectId = 'p1'}) {
  final at = DateTime.utc(2026, 1, 1, 12, 0, 0);
  return MeasurementSetupReadinessSnapshot(
    identity: MeasurementSetupReadinessIdentity(
      projectId: projectId,
      profileChecksum: 'c1',
      calibrationCurveChecksum: 'curve1',
      calibrationAngle: 'zeroDegree',
      inputDeviceIdentity: 'device:dev1',
      expectedSampleRate: 48000,
      expectedChannelCount: 1,
      qualityPolicyVersion: 'provisional-1',
    ),
    generationId: 'gen-1',
    blockers: const [],
    warnings: const [],
    checkedAt: at,
    expiresAt: at.add(const Duration(minutes: 30)),
    isReady: true,
  );
}

void main() {
  group('ProProject.currentSetupReadiness JSON round-trip', () {
    test('round-trips a ready snapshot', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        currentSetupReadiness: _snapshot(),
      );
      final decoded = ProProject.fromJson(project.toJson());
      expect(decoded.currentSetupReadiness?.generationId, 'gen-1');
      expect(decoded.currentSetupReadiness?.isReady, isTrue);
    });

    test('null by default — never fabricated', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(project.currentSetupReadiness, isNull);
    });

    test('a corrupt currentSetupReadiness does not fail project decode', () {
      final json = {
        'id': 'p1',
        'name': 'Test',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'currentSetupReadiness': 'not-a-map',
      };
      final decoded = ProProject.fromJson(json);
      expect(decoded.id, 'p1');
      expect(decoded.currentSetupReadiness, isNull);
    });
  });

  group('ProProject.copyWith(currentSetupReadiness:)', () {
    test('clearCurrentSetupReadiness actually clears it', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        currentSetupReadiness: _snapshot(),
      );
      final cleared = project.copyWith(clearCurrentSetupReadiness: true);
      expect(cleared.currentSetupReadiness, isNull);
    });
  });

  group('cross-project non-interference', () {
    test('two projects hold independent readiness snapshots', () {
      final projectA = ProProject(
        id: 'a',
        name: 'A',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        currentSetupReadiness: _snapshot(projectId: 'a'),
      );
      final projectB = ProProject(
        id: 'b',
        name: 'B',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(projectA.currentSetupReadiness, isNotNull);
      expect(projectB.currentSetupReadiness, isNull);
    });
  });

  group('ProProjectStoreNotifier.updateSetupReadiness', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('updates only the target project', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(proProjectStoreProvider.notifier);
      await notifier.addProject(ProProject(
        id: 'a',
        name: 'A',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ));
      await notifier.addProject(ProProject(
        id: 'b',
        name: 'B',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ));

      await notifier.updateSetupReadiness('a', _snapshot(projectId: 'a'));

      final state = container.read(proProjectStoreProvider);
      final a = state.projects.firstWhere((p) => p.id == 'a');
      final b = state.projects.firstWhere((p) => p.id == 'b');
      expect(a.currentSetupReadiness?.generationId, 'gen-1');
      expect(b.currentSetupReadiness, isNull);
    });

    test('passing null clears the readiness', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(proProjectStoreProvider.notifier);
      await notifier.addProject(ProProject(
        id: 'a',
        name: 'A',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        currentSetupReadiness: _snapshot(projectId: 'a'),
      ));

      await notifier.updateSetupReadiness('a', null);

      final state = container.read(proProjectStoreProvider);
      final a = state.projects.firstWhere((p) => p.id == 'a');
      expect(a.currentSetupReadiness, isNull);
    });
  });
}
