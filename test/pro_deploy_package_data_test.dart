// TUNAI PRO — Phase R: Deploy Package Data tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_deploy_package_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';

void main() {
  group('DeployProjectState — default', () {
    late DeployProjectState state;
    setUp(() => state = DeployProjectState.createDefault());

    test('no packages by default', () {
      expect(state.packageCount, 0);
      expect(state.packages, isEmpty);
    });

    test('no presets by default', () {
      expect(state.presetCount, 0);
      expect(state.presets, isEmpty);
    });

    test('activePackage is null when no packages', () {
      expect(state.activePackage, isNull);
    });

    test('activePreset is null by default', () {
      expect(state.activePreset, isNull);
    });

    test('readyPackageCount is 0 by default', () {
      expect(state.readyPackageCount, 0);
    });

    test('blockedPackageCount is 0 by default', () {
      expect(state.blockedPackageCount, 0);
    });

    test('readinessLabel when no packages', () {
      expect(state.readinessLabel, 'No deploy package');
    });

    test('latestPackage is null when empty', () {
      expect(state.latestPackage, isNull);
    });
  });

  group('DeployProjectState — computed getters', () {
    late DeployPackage pkg1;
    late DeployPackage pkg2;
    late DeployProjectState state;

    setUp(() {
      final now = DateTime.now();
      final snap = DeployPackageSnapshot(
        projectId: 'p1',
        projectName: 'Test',
        projectStatus: 'Draft',
        createdAt: now,
      );
      pkg1 = DeployPackage(
        id: 'pkg1',
        version: 'v0.0.1-draft',
        name: 'Package 1',
        kind: DeployPackageKind.fullProjectSnapshot,
        status: DeployPackageStatus.ready,
        readinessLevel: DeployReadinessLevel.readyForReview,
        createdAt: now,
        updatedAt: now,
        snapshot: snap,
      );
      pkg2 = DeployPackage(
        id: 'pkg2',
        version: 'v0.0.2-draft',
        name: 'Package 2',
        kind: DeployPackageKind.hardwareDryRun,
        status: DeployPackageStatus.blocked,
        readinessLevel: DeployReadinessLevel.blocked,
        createdAt: now,
        updatedAt: now,
        snapshot: snap,
      );
      state = DeployProjectState(
        packages: [pkg1, pkg2],
        activePackageId: 'pkg1',
      );
    });

    test('package count is correct', () {
      expect(state.packageCount, 2);
    });

    test('activePackage returns correct package', () {
      expect(state.activePackage?.id, 'pkg1');
    });

    test('latestPackage returns last package', () {
      expect(state.latestPackage?.id, 'pkg2');
    });

    test('readyPackageCount counts ready packages', () {
      expect(state.readyPackageCount, 1);
    });

    test('blockedPackageCount counts blocked packages', () {
      expect(state.blockedPackageCount, 1);
    });

    test('readinessLabel reflects active package', () {
      expect(state.readinessLabel, pkg1.readinessLevel.label);
    });
  });

  group('Stale package consistency (Phase 4-C-4A)', () {
    late DeployPackage readyPkg;
    late DeployPackage exportedPkg;
    late DeployPackage stalePkg;
    late DeployPackage blockedPkg;

    setUp(() {
      final now = DateTime.now();
      final snap = DeployPackageSnapshot(
        projectId: 'p1',
        projectName: 'Test',
        projectStatus: 'Tuned',
        createdAt: now,
      );
      DeployPackage make(String id, DeployPackageStatus status,
              DeployReadinessLevel readiness) =>
          DeployPackage(
            id: id,
            version: 'v0.0.1',
            name: 'Package $id',
            kind: DeployPackageKind.fullProjectSnapshot,
            status: status,
            readinessLevel: readiness,
            createdAt: now,
            updatedAt: now,
            snapshot: snap,
          );

      readyPkg = make('ready1', DeployPackageStatus.ready,
          DeployReadinessLevel.readyForReview);
      exportedPkg = make('exported1', DeployPackageStatus.exported,
          DeployReadinessLevel.readyForDryRun);
      // Stale, but its readinessLevel is left as the historical
      // readyForDryRun record — exactly what rollbackTuningState() produces
      // (it only rewrites status, never readinessLevel).
      stalePkg = make('stale1', DeployPackageStatus.stale,
          DeployReadinessLevel.readyForDryRun);
      blockedPkg = make(
          'blocked1', DeployPackageStatus.blocked, DeployReadinessLevel.blocked);
    });

    test('readyPackageCount excludes a stale package even though its '
        'readinessLevel still says readyForDryRun', () {
      final state = DeployProjectState(
        packages: [readyPkg, exportedPkg, stalePkg, blockedPkg],
      );
      // Only readyPkg + exportedPkg count; stalePkg is excluded despite its
      // historical readyForDryRun readinessLevel.
      expect(state.readyPackageCount, 2);
    });

    test('readyPackageCount is 0 when the only "ready-looking" package is '
        'stale', () {
      final state = DeployProjectState(packages: [stalePkg]);
      expect(state.readyPackageCount, 0);
    });

    test('readinessLabel says "Stale" for the active package, not its '
        'historical readinessLevel', () {
      final state = DeployProjectState(
        packages: [stalePkg],
        activePackageId: 'stale1',
      );
      expect(state.readinessLabel, contains('Stale'));
      expect(state.readinessLabel, isNot(stalePkg.readinessLevel.label));
    });

    test('readinessLabel still reflects readinessLevel for a non-stale '
        'active package', () {
      final state = DeployProjectState(
        packages: [readyPkg],
        activePackageId: 'ready1',
      );
      expect(state.readinessLabel, readyPkg.readinessLevel.label);
    });

    test('activePackage still resolves to a stale package by id — the '
        'model does not hide it, only the readiness summary is corrected',
        () {
      final state = DeployProjectState(
        packages: [stalePkg],
        activePackageId: 'stale1',
      );
      expect(state.activePackage?.id, 'stale1');
      expect(state.activePackage?.status, DeployPackageStatus.stale);
    });
  });

  group('Active preset lookup', () {
    test('activePreset returns correct preset by id', () {
      final now = DateTime.now();
      final preset = PresetRecord(
        id: 'pre1',
        name: 'My Preset',
        version: 'v1',
        slotType: PresetSlotType.project,
        createdAt: now,
        updatedAt: now,
      );
      final state = DeployProjectState(
        presets: [preset],
        activePresetId: 'pre1',
      );
      expect(state.activePreset?.id, 'pre1');
      expect(state.activePreset?.name, 'My Preset');
    });

    test('activePreset returns null for missing id', () {
      final now = DateTime.now();
      final preset = PresetRecord(
        id: 'pre1',
        name: 'My Preset',
        version: 'v1',
        slotType: PresetSlotType.project,
        createdAt: now,
        updatedAt: now,
      );
      final state = DeployProjectState(
        presets: [preset],
        activePresetId: 'nonexistent',
      );
      expect(state.activePreset, isNull);
    });
  });

  group('JSON round-trip', () {
    test('DeployProjectState round-trips empty state', () {
      final state = DeployProjectState.createDefault();
      final restored = DeployProjectState.fromJson(state.toJson());
      expect(restored.packageCount, 0);
      expect(restored.presetCount, 0);
    });

    test('DeployPackage round-trips JSON', () {
      final now = DateTime.now();
      final snap = DeployPackageSnapshot(
        projectId: 'p1',
        projectName: 'Test Project',
        projectStatus: 'Draft',
        createdAt: now,
        warnings: ['Warning A', 'Warning B'],
      );
      final pkg = DeployPackage(
        id: 'pkg1',
        version: 'v1.0.0-draft',
        name: 'Test Package',
        kind: DeployPackageKind.fullProjectSnapshot,
        status: DeployPackageStatus.ready,
        readinessLevel: DeployReadinessLevel.readyForReview,
        createdAt: now,
        updatedAt: now,
        snapshot: snap,
        exportPackageId: 'exp1',
        hardwarePlanId: 'hw1',
      );
      final restored = DeployPackage.fromJson(pkg.toJson());
      expect(restored.id, pkg.id);
      expect(restored.version, pkg.version);
      expect(restored.kind, pkg.kind);
      expect(restored.status, pkg.status);
      expect(restored.readinessLevel, pkg.readinessLevel);
      expect(restored.exportPackageId, 'exp1');
      expect(restored.hardwarePlanId, 'hw1');
      expect(restored.snapshot.warnings.length, 2);
    });

    test('DeployPackage JSON includes safetyNote', () {
      final now = DateTime.now();
      final snap = DeployPackageSnapshot(
        projectId: 'p1',
        projectName: 'Test',
        projectStatus: 'Draft',
        createdAt: now,
      );
      final pkg = DeployPackage(
        id: 'pkg1',
        version: 'v1',
        name: 'Test',
        kind: DeployPackageKind.fullProjectSnapshot,
        status: DeployPackageStatus.draft,
        readinessLevel: DeployReadinessLevel.incomplete,
        createdAt: now,
        updatedAt: now,
        snapshot: snap,
      );
      final json = pkg.toJson();
      expect(json.containsKey('safetyNote'), isTrue);
      expect((json['safetyNote'] as String).toLowerCase(),
          contains('no hardware write'));
    });

    test('PresetRecord round-trips JSON', () {
      final now = DateTime.now();
      final preset = PresetRecord(
        id: 'pre1',
        name: 'My Preset',
        version: 'v1.0',
        slotType: PresetSlotType.user,
        createdAt: now,
        updatedAt: now,
        targetPlatform: DspTargetPlatform.adau1466,
        tags: ['bass', 'test'],
        locked: true,
      );
      final restored = PresetRecord.fromJson(preset.toJson());
      expect(restored.id, preset.id);
      expect(restored.slotType, PresetSlotType.user);
      expect(restored.targetPlatform, DspTargetPlatform.adau1466);
      expect(restored.tags, ['bass', 'test']);
      expect(restored.locked, isTrue);
    });

    test('DeployProjectState round-trips with packages and presets', () {
      final now = DateTime.now();
      final snap = DeployPackageSnapshot(
        projectId: 'p1',
        projectName: 'Test',
        projectStatus: 'Draft',
        createdAt: now,
      );
      final pkg = DeployPackage(
        id: 'pkg1',
        version: 'v1',
        name: 'P1',
        kind: DeployPackageKind.dspExportDraft,
        status: DeployPackageStatus.draft,
        readinessLevel: DeployReadinessLevel.warnings,
        createdAt: now,
        updatedAt: now,
        snapshot: snap,
      );
      final preset = PresetRecord(
        id: 'pre1',
        name: 'PR1',
        version: 'v1',
        slotType: PresetSlotType.project,
        createdAt: now,
        updatedAt: now,
      );
      final state = DeployProjectState(
        packages: [pkg],
        presets: [preset],
        activePackageId: 'pkg1',
        revision: 3,
      );
      final restored = DeployProjectState.fromJson(state.toJson());
      expect(restored.packageCount, 1);
      expect(restored.presetCount, 1);
      expect(restored.activePackageId, 'pkg1');
      expect(restored.revision, 3);
    });
  });

  group('Enum round-trips', () {
    test('DeployPackageStatus round-trips', () {
      for (final v in DeployPackageStatus.values) {
        expect(DeployPackageStatus.fromJson(v.toJson()), v);
      }
    });

    test('DeployPackageKind round-trips', () {
      for (final v in DeployPackageKind.values) {
        expect(DeployPackageKind.fromJson(v.toJson()), v);
      }
    });

    test('DeployReadinessLevel round-trips', () {
      for (final v in DeployReadinessLevel.values) {
        expect(DeployReadinessLevel.fromJson(v.toJson()), v);
      }
    });

    test('PresetSlotType round-trips', () {
      for (final v in PresetSlotType.values) {
        expect(PresetSlotType.fromJson(v.toJson()), v);
      }
    });
  });
}
