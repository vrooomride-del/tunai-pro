// Phase 3-D1 — ProProject.selectedInputDevice: persistence, corrupt
// isolation, and cross-project non-interference.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';

void main() {
  group('ProProject.selectedInputDevice JSON round-trip', () {
    test('round-trips a specific-device selection', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        selectedInputDevice: MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev1',
          labelSnapshot: 'USB Mic',
          selectedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final decoded = ProProject.fromJson(project.toJson());
      expect(decoded.selectedInputDevice?.deviceId, 'dev1');
      expect(decoded.selectedInputDevice?.useSystemDefault, isFalse);
    });

    test('round-trips a system-default selection', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        selectedInputDevice: MeasurementInputDeviceSelection.systemDefault(
            selectedAt: DateTime.utc(2026, 1, 1)),
      );
      final decoded = ProProject.fromJson(project.toJson());
      expect(decoded.selectedInputDevice?.useSystemDefault, isTrue);
      expect(decoded.selectedInputDevice?.deviceId, isNull);
    });

    test(
        'null by default — legacy/never-selected project, never '
        'fabricated', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(project.selectedInputDevice, isNull);
    });

    test(
        'a corrupt selectedInputDevice in JSON does not fail project '
        'decode — falls back to null', () {
      final json = {
        'id': 'p1',
        'name': 'Test',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'selectedInputDevice': {
          'labelSnapshot': 'x',
          'selectedAt': '2026-01-01T00:00:00Z',
          // missing both useSystemDefault and deviceId -> structurally invalid
        },
      };
      final decoded = ProProject.fromJson(json);
      expect(decoded.id, 'p1');
      expect(decoded.selectedInputDevice, isNull);
    });

    test('a non-map selectedInputDevice value does not fail project decode',
        () {
      final json = {
        'id': 'p1',
        'name': 'Test',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'selectedInputDevice': 'not-a-map',
      };
      final decoded = ProProject.fromJson(json);
      expect(decoded.id, 'p1');
      expect(decoded.selectedInputDevice, isNull);
    });
  });

  group('ProProject.copyWith(selectedInputDevice:)', () {
    test('clearSelectedInputDevice actually clears it', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        selectedInputDevice: MeasurementInputDeviceSelection.systemDefault(
            selectedAt: DateTime.utc(2026, 1, 1)),
      );
      final cleared = project.copyWith(clearSelectedInputDevice: true);
      expect(cleared.selectedInputDevice, isNull);
    });
  });

  group('cross-project non-interference', () {
    test('two projects hold independent selections', () {
      final projectA = ProProject(
        id: 'a',
        name: 'A',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        selectedInputDevice: MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev-a',
          labelSnapshot: 'Mic A',
          selectedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final projectB = ProProject(
        id: 'b',
        name: 'B',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(projectA.selectedInputDevice, isNotNull);
      expect(projectB.selectedInputDevice, isNull);
    });
  });

  group('ProProjectStoreNotifier.updateSelectedInputDevice', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('updates only the target project\'s selection', () async {
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

      await notifier.updateSelectedInputDevice(
        'a',
        MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev-a',
          labelSnapshot: 'Mic A',
          selectedAt: DateTime.now(),
        ),
      );

      final state = container.read(proProjectStoreProvider);
      final a = state.projects.firstWhere((p) => p.id == 'a');
      final b = state.projects.firstWhere((p) => p.id == 'b');
      expect(a.selectedInputDevice?.deviceId, 'dev-a');
      expect(b.selectedInputDevice, isNull);
    });

    test('passing null clears the selection', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(proProjectStoreProvider.notifier);
      await notifier.addProject(ProProject(
        id: 'a',
        name: 'A',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        selectedInputDevice: MeasurementInputDeviceSelection.systemDefault(
            selectedAt: DateTime.utc(2026, 1, 1)),
      ));

      await notifier.updateSelectedInputDevice('a', null);

      final state = container.read(proProjectStoreProvider);
      final a = state.projects.firstWhere((p) => p.id == 'a');
      expect(a.selectedInputDevice, isNull);
    });
  });
}
