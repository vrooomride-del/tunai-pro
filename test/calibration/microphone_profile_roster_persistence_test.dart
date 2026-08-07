// Phase 3-C — ProProject.microphoneProfiles roster: persistence, corrupt
// isolation, and cross-project non-interference.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';

MeasurementMicrophoneProfile _profile(String id) =>
    MeasurementMicrophoneProfile(
      id: id,
      manufacturer: 'ACME',
      model: 'M-$id',
      connectionType: 'USB',
      calibrationSource: CalibrationSource.uncalibrated,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('ProProject.microphoneProfiles JSON round-trip', () {
    test('round-trips the full roster', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        microphoneProfiles: [_profile('a'), _profile('b')],
      );
      final decoded = ProProject.fromJson(project.toJson());
      expect(decoded.microphoneProfiles.map((p) => p.id), ['a', 'b']);
    });

    test('empty roster by default — never fabricated entries', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(project.microphoneProfiles, isEmpty);
    });

    test('one corrupt roster entry does not wipe the rest', () {
      final json = {
        'id': 'p1',
        'name': 'Test',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'microphoneProfiles': [
          _profile('a').toJson(),
          {'id': 123}, // malformed — id must be a String
          _profile('b').toJson(),
        ],
      };
      final decoded = ProProject.fromJson(json);
      expect(decoded.microphoneProfiles.map((p) => p.id), ['a', 'b']);
    });

    test(
        'a non-list microphoneProfiles value falls back to empty, does not '
        'throw', () {
      final json = {
        'id': 'p1',
        'name': 'Test',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'microphoneProfiles': 'not-a-list',
      };
      final decoded = ProProject.fromJson(json);
      expect(decoded.microphoneProfiles, isEmpty);
    });
  });

  group('ProProject.copyWith(microphoneProfiles:)', () {
    test('replaces the roster wholesale', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        microphoneProfiles: [_profile('a')],
      );
      final updated =
          project.copyWith(microphoneProfiles: [_profile('a'), _profile('b')]);
      expect(updated.microphoneProfiles.map((p) => p.id), ['a', 'b']);
    });
  });

  group('cross-project non-interference', () {
    test('two projects hold independent rosters', () {
      final projectA = ProProject(
        id: 'a',
        name: 'A',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        microphoneProfiles: [_profile('mic-a')],
      );
      final projectB = ProProject(
        id: 'b',
        name: 'B',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(projectA.microphoneProfiles, isNotEmpty);
      expect(projectB.microphoneProfiles, isEmpty);
    });
  });

  group('ProProjectStoreNotifier.updateMicrophoneProfiles', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('updates only the target project\'s roster', () async {
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

      await notifier.updateMicrophoneProfiles('a', [_profile('mic-a')]);

      final state = container.read(proProjectStoreProvider);
      final a = state.projects.firstWhere((p) => p.id == 'a');
      final b = state.projects.firstWhere((p) => p.id == 'b');
      expect(a.microphoneProfiles.map((p) => p.id), ['mic-a']);
      expect(b.microphoneProfiles, isEmpty);
    });

    test(
        'selecting a roster profile for one project never selects it for '
        'another', () async {
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

      await notifier.updateSelectedMicrophoneProfile('a', _profile('mic-a'));

      final state = container.read(proProjectStoreProvider);
      final a = state.projects.firstWhere((p) => p.id == 'a');
      final b = state.projects.firstWhere((p) => p.id == 'b');
      expect(a.selectedMicrophoneProfile?.id, 'mic-a');
      expect(b.selectedMicrophoneProfile, isNull);
    });
  });
}
