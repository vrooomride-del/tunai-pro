// P0 fix regression guard: ProProject.decodeList / MeasurementSession.decodeList
// must isolate each list entry's parse so one corrupt or pre-migration entry
// cannot wipe every other saved project/session. Also covers
// ProProjectStoreNotifier._load() cleaning up a dangling currentProjectId
// when the entry it pointed at was dropped by decodeList.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_measurement.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';

Map<String, dynamic> _validProjectJson(String id) => {
      'id': id,
      'name': 'Project $id',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
    };

Map<String, dynamic> _validSessionJson(String id, String projectId) => {
      'id': id,
      'projectId': projectId,
      'name': 'Session $id',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
    };

void main() {
  group('ProProject.decodeList resilience', () {
    test('2 valid + 1 corrupt (missing required id) -> 2 preserved', () {
      final raw = jsonEncode([
        _validProjectJson('a'),
        {'name': 'no id field'}, // missing required 'id' -> fromJson throws
        _validProjectJson('b'),
      ]);
      final result = ProProject.decodeList(raw);
      expect(result.map((p) => p.id), ['a', 'b']);
    });

    test('corrupt entry as first item is skipped, rest preserved', () {
      final raw = jsonEncode([
        {'name': 'no id'},
        _validProjectJson('a'),
        _validProjectJson('b'),
      ]);
      final result = ProProject.decodeList(raw);
      expect(result.map((p) => p.id), ['a', 'b']);
    });

    test('corrupt entry in the middle is skipped, rest preserved', () {
      final raw = jsonEncode([
        _validProjectJson('a'),
        {'name': 'no id'},
        _validProjectJson('b'),
      ]);
      final result = ProProject.decodeList(raw);
      expect(result.map((p) => p.id), ['a', 'b']);
    });

    test('corrupt entry as last item is skipped, rest preserved', () {
      final raw = jsonEncode([
        _validProjectJson('a'),
        _validProjectJson('b'),
        {'name': 'no id'},
      ]);
      final result = ProProject.decodeList(raw);
      expect(result.map((p) => p.id), ['a', 'b']);
    });

    test('every entry corrupt -> empty list, no throw', () {
      final raw = jsonEncode([
        {'name': 'no id'},
        {'also': 'no id'},
        123, // not even a map
      ]);
      expect(() => ProProject.decodeList(raw), returnsNormally);
      expect(ProProject.decodeList(raw), isEmpty);
    });

    test('root JSON is not a list -> empty list, no throw', () {
      final raw = jsonEncode({'id': 'a', 'name': 'not a list root'});
      expect(() => ProProject.decodeList(raw), returnsNormally);
      expect(ProProject.decodeList(raw), isEmpty);
    });

    test('invalid JSON entirely -> empty list, no throw', () {
      expect(() => ProProject.decodeList('{not valid json'), returnsNormally);
      expect(ProProject.decodeList('{not valid json'), isEmpty);
    });

    test('legacy entry missing optional fields mixes fine with a full entry',
        () {
      final legacyMinimal = {
        'id': 'legacy',
        // name/createdAt/updatedAt intentionally absent — all have fallbacks
        // in fromJson (name -> 'Untitled', dates -> DateTime.now()).
      };
      final raw = jsonEncode([legacyMinimal, _validProjectJson('full')]);
      final result = ProProject.decodeList(raw);
      expect(result.map((p) => p.id), ['legacy', 'full']);
      expect(result.first.name, 'Untitled');
    });
  });

  group('MeasurementSession.decodeList resilience', () {
    test('2 valid + 1 corrupt (missing required id) -> 2 preserved', () {
      final raw = jsonEncode([
        _validSessionJson('s1', 'p1'),
        {'name': 'no id field'},
        _validSessionJson('s2', 'p1'),
      ]);
      final result = MeasurementSession.decodeList(raw);
      expect(result.map((s) => s.id), ['s1', 's2']);
    });

    test('corrupt entry in the middle is skipped, rest preserved', () {
      final raw = jsonEncode([
        _validSessionJson('s1', 'p1'),
        {'name': 'no id'},
        _validSessionJson('s2', 'p1'),
      ]);
      final result = MeasurementSession.decodeList(raw);
      expect(result.map((s) => s.id), ['s1', 's2']);
    });

    test('every entry corrupt -> empty list, no throw', () {
      final raw = jsonEncode([
        {'name': 'no id'},
        'not a map',
      ]);
      expect(() => MeasurementSession.decodeList(raw), returnsNormally);
      expect(MeasurementSession.decodeList(raw), isEmpty);
    });

    test('root JSON is not a list -> empty list, no throw', () {
      final raw = jsonEncode({'id': 's1'});
      expect(() => MeasurementSession.decodeList(raw), returnsNormally);
      expect(MeasurementSession.decodeList(raw), isEmpty);
    });

    test('legacy entry missing optional fields mixes fine with a full entry',
        () {
      final legacyMinimal = {'id': 'legacy-s', 'projectId': 'p1'};
      final raw =
          jsonEncode([legacyMinimal, _validSessionJson('full-s', 'p1')]);
      final result = MeasurementSession.decodeList(raw);
      expect(result.map((s) => s.id), ['legacy-s', 'full-s']);
      expect(result.first.name, 'Session');
    });
  });

  group('ProProjectStoreNotifier._load() dangling currentProjectId cleanup',
      () {
    test('currentProjectId pointing at a surviving project is preserved',
        () async {
      SharedPreferences.setMockInitialValues({
        'tunai_pro_projects':
            jsonEncode([_validProjectJson('a'), _validProjectJson('b')]),
        'tunai_pro_current_project_id': 'b',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();
      final store = container.read(proProjectStoreProvider);
      expect(store.currentProjectId, 'b');
      expect(store.currentProject?.id, 'b');
    });

    test(
        'currentProjectId pointing at a project dropped by decodeList '
        'resolves to null, not a crash', () async {
      SharedPreferences.setMockInitialValues({
        'tunai_pro_projects': jsonEncode([
          _validProjectJson('a'),
          {'name': 'corrupt, was the current project'},
        ]),
        // Persisted current id refers to an entry that fromJson cannot parse
        // (no 'id' field) -- decodeList drops it, so this id no longer names
        // any project in the decoded list.
        'tunai_pro_current_project_id': 'dangling-id-that-never-decoded',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();
      final store = container.read(proProjectStoreProvider);
      expect(store.currentProjectId, isNull);
      expect(store.currentProject, isNull);
      expect(store.projects.map((p) => p.id), ['a']);
    });

    test(
        'no additional data loss: surviving projects are re-persisted '
        'intact on the next mutating call', () async {
      SharedPreferences.setMockInitialValues({
        'tunai_pro_projects': jsonEncode([
          _validProjectJson('a'),
          {'name': 'corrupt'},
          _validProjectJson('b'),
        ]),
        'tunai_pro_current_project_id': 'a',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();
      // Trigger a persist via any mutating call.
      await container
          .read(proProjectStoreProvider.notifier)
          .renameProject('b', 'Renamed B');

      final prefs = await SharedPreferences.getInstance();
      final rewritten =
          ProProject.decodeList(prefs.getString('tunai_pro_projects')!);
      expect(rewritten.map((p) => p.id), ['a', 'b']);
      expect(rewritten.firstWhere((p) => p.id == 'b').name, 'Renamed B');
    });
  });
}
