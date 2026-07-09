// TUNAI PRO — Phase R: Deploy Package Engine tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_protection_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_hardware_connection_data.dart';
import 'package:tunai_pro/core/pro_deploy_package_data.dart';
import 'package:tunai_pro/core/pro_deploy_package_engine.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

ProProject _project({
  VerificationStatus protection = VerificationStatus.passed,
  bool hasExportPackage = false,
  bool hasHardwarePlan = false,
}) {
  final now = DateTime.now();

  ProtectionProjectState protState = ProtectionProjectState.createDefault()
      .copyWith(verificationStatus: protection);

  ExportProjectState exportState = ExportProjectState.createDefault();
  if (hasExportPackage) {
    final pkg = DspExportPackage(
      id: 'exp1',
      targetPlatform: DspTargetPlatform.adau1466,
      status: ExportStatus.draftReady,
      projectName: 'Test',
    );
    exportState = exportState.copyWith(packages: [pkg], activePackageId: 'exp1');
  }

  HardwareProjectState hwState = HardwareProjectState.createDefault();
  if (hasHardwarePlan) {
    final plan = HardwareWritePlan(
      id: 'hw1',
      createdAt: now,
      targetPlatform: DspTargetPlatform.adau1466,
      transportType: HardwareTransportType.simulationOnly,
      mode: HardwareWriteMode.dryRunOnly,
      steps: const [],
      guardChecks: const [],
      warnings: const ['Hardware write disabled.'],
      summary: 'DRY RUN — 0 steps.',
      dryRunOnly: true,
    );
    hwState = hwState.copyWith(
      writePlans: [plan],
      activePlanId: 'hw1',
    );
  }

  return ProProject(
    id: 'proj1',
    name: 'Test Project',
    createdAt: now,
    updatedAt: now,
    protectionState: protState,
    exportState: exportState,
    hardwareState: hwState,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Deploy package basics', () {
    test('generates deploy package with project snapshot', () {
      final project = _project(
          protection: VerificationStatus.passed, hasExportPackage: true);
      final pkg = generateDeployPackage(project: project);
      expect(pkg.id, isNotEmpty);
      expect(pkg.version, startsWith('v'));
      expect(pkg.snapshot.projectId, project.id);
      expect(pkg.snapshot.projectName, project.name);
    });

    test('package includes safety note in snapshot warnings', () {
      final pkg = generateDeployPackage(project: _project());
      final warnings = pkg.snapshot.warnings;
      expect(
          warnings.any((w) => w.toLowerCase().contains('no hardware write')),
          isTrue);
    });

    test('package JSON includes safetyNote field', () {
      final pkg = generateDeployPackage(project: _project());
      final json = pkg.toJson();
      expect(json.containsKey('safetyNote'), isTrue);
      expect((json['safetyNote'] as String).toLowerCase(),
          contains('no hardware write'));
    });

    test('no hardware write field exists in package JSON', () {
      final pkg = generateDeployPackage(project: _project());
      final json = pkg.toJson().toString().toLowerCase();
      expect(json, isNot(contains('sendusb')));
      expect(json, isNot(contains('sendble')));
      expect(json, isNot(contains('safeloadexecute')));
      expect(json, isNot(contains('writeregister')));
    });

    test('auto-names package when name not provided', () {
      final project = _project();
      final pkg = generateDeployPackage(project: project);
      expect(pkg.name, contains(project.name));
    });

    test('uses provided name when given', () {
      final pkg = generateDeployPackage(
          project: _project(), name: 'My Custom Name');
      expect(pkg.name, 'My Custom Name');
    });

    test('notes are preserved', () {
      final pkg = generateDeployPackage(
          project: _project(), notes: 'Review these settings carefully.');
      expect(pkg.notes, 'Review these settings carefully.');
    });
  });

  group('Readiness — blocked', () {
    test('blocked when protection failed', () {
      final project = _project(
          protection: VerificationStatus.failed, hasExportPackage: true);
      final pkg = generateDeployPackage(project: project);
      expect(pkg.readinessLevel, DeployReadinessLevel.blocked);
      expect(pkg.status, DeployPackageStatus.blocked);
      expect(pkg.snapshot.blockedReason, isNotNull);
    });

    test('blocked when no export package (non-simulation kind)', () {
      final project = _project(
          protection: VerificationStatus.passed, hasExportPackage: false);
      final pkg = generateDeployPackage(project: project,
          kind: DeployPackageKind.fullProjectSnapshot);
      expect(pkg.readinessLevel, DeployReadinessLevel.blocked);
      expect(pkg.snapshot.blockedReason, isNotNull);
    });
  });

  group('Readiness — warnings', () {
    test('warning when simulation missing', () {
      final project = _project(
          protection: VerificationStatus.notReady, hasExportPackage: false);
      final pkg = generateDeployPackage(project: project,
          kind: DeployPackageKind.simulationPreset);
      final warnings = pkg.snapshot.warnings;
      expect(warnings.any((w) => w.toLowerCase().contains('simulation')),
          isTrue);
    });

    test('warning when protection not completed', () {
      final project = _project(
          protection: VerificationStatus.notReady, hasExportPackage: false);
      final pkg = generateDeployPackage(project: project,
          kind: DeployPackageKind.simulationPreset);
      final warnings = pkg.snapshot.warnings;
      expect(
          warnings.any((w) => w.toLowerCase().contains('protection')),
          isTrue);
    });

    test('warning includes hardware write disabled note', () {
      final project = _project(
          protection: VerificationStatus.passed, hasExportPackage: true);
      final pkg = generateDeployPackage(project: project);
      final warnings = pkg.snapshot.warnings;
      expect(
          warnings.any((w) => w.toLowerCase().contains('hardware write disabled')),
          isTrue);
    });

    test('warning when mappings require capture', () {
      final now = DateTime.now();
      final mappingJson = {'mappingStatus': 'requiresCapture'};
      final expPkg = DspExportPackage(
        id: 'exp1',
        targetPlatform: DspTargetPlatform.adau1466,
        status: ExportStatus.draftReady,
        projectName: 'Test',
        sigmaMappingReferenceJson: mappingJson,
      );
      final exportState = ExportProjectState.createDefault()
          .copyWith(packages: [expPkg], activePackageId: 'exp1');
      final project = ProProject(
        id: 'proj1',
        name: 'Test',
        createdAt: now,
        updatedAt: now,
        exportState: exportState,
        protectionState: ProtectionProjectState.createDefault()
            .copyWith(verificationStatus: VerificationStatus.passed),
      );
      final pkg = generateDeployPackage(project: project);
      expect(
          pkg.snapshot.warnings
              .any((w) => w.toLowerCase().contains('sigmastudio')),
          isTrue);
    });
  });

  group('Readiness — ready', () {
    test('readyForReview when protection passed and export exists', () {
      final project = _project(
          protection: VerificationStatus.passed, hasExportPackage: true);
      final pkg = generateDeployPackage(project: project);
      expect(pkg.readinessLevel, DeployReadinessLevel.readyForReview);
      expect(pkg.status, DeployPackageStatus.ready);
    });

    test('readyForDryRun when hardware plan also exists', () {
      final project = _project(
          protection: VerificationStatus.passed,
          hasExportPackage: true,
          hasHardwarePlan: true);
      final pkg = generateDeployPackage(project: project);
      expect(pkg.readinessLevel, DeployReadinessLevel.readyForDryRun);
      expect(pkg.status, DeployPackageStatus.ready);
    });
  });

  group('Linked IDs', () {
    test('active export package id captured', () {
      final project = _project(
          protection: VerificationStatus.passed, hasExportPackage: true);
      final pkg = generateDeployPackage(project: project);
      expect(pkg.exportPackageId, 'exp1');
    });

    test('active hardware plan id captured', () {
      final project = _project(
          protection: VerificationStatus.passed,
          hasExportPackage: true,
          hasHardwarePlan: true);
      final pkg = generateDeployPackage(project: project);
      expect(pkg.hardwarePlanId, 'hw1');
    });

    test('no hardware plan id when no plan', () {
      final project =
          _project(protection: VerificationStatus.passed, hasExportPackage: true);
      final pkg = generateDeployPackage(project: project);
      expect(pkg.hardwarePlanId, isNull);
    });
  });

  group('JSON round-trip', () {
    test('generated package round-trips JSON', () {
      final project = _project(
          protection: VerificationStatus.passed, hasExportPackage: true);
      final pkg = generateDeployPackage(project: project);
      final restored = DeployPackage.fromJson(pkg.toJson());
      expect(restored.id, pkg.id);
      expect(restored.version, pkg.version);
      expect(restored.readinessLevel, pkg.readinessLevel);
      expect(restored.snapshot.projectId, project.id);
      expect(restored.snapshot.warnings.length,
          pkg.snapshot.warnings.length);
    });
  });

  group('Safety restrictions', () {
    test('package has no USBi/BLE packet keys', () {
      final pkg = generateDeployPackage(project: _project());
      final json = pkg.toJson();
      expect(json.containsKey('usbPacket'), isFalse);
      expect(json.containsKey('blePacket'), isFalse);
      expect(json.containsKey('safeload'), isFalse);
      expect(json.containsKey('eepromWrite'), isFalse);
      expect(json.containsKey('selfbootWrite'), isFalse);
    });

    test('hardwareSummary hardwareWriteEnabled is false', () {
      final pkg = generateDeployPackage(project: _project());
      final hwSummary = pkg.snapshot.hardwareSummary;
      expect(hwSummary['hardwareWriteEnabled'], isFalse);
    });
  });
}
