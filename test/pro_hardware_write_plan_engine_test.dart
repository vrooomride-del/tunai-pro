// TUNAI PRO — Phase Q: Hardware Write Plan Engine tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_protection_data.dart';
import 'package:tunai_pro/core/pro_hardware_connection_data.dart';
import 'package:tunai_pro/core/pro_hardware_write_plan_engine.dart';
import 'package:tunai_pro/core/pro_sigma_mapping_data.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

ProProject _baseProject({
  VerificationStatus verificationStatus = VerificationStatus.passed,
  DspTargetPlatform platform = DspTargetPlatform.adau1466,
}) {
  final now = DateTime.now();
  final protection = ProtectionProjectState.createDefault().copyWith(
    verificationStatus: verificationStatus,
  );
  final exportState = ExportProjectState.createDefault();
  return ProProject(
    id: '1',
    name: 'Test',
    createdAt: now,
    updatedAt: now,
    protectionState: protection,
    exportState: exportState.copyWith(selectedTarget: platform),
  );
}

DspExportPackage _pkg({
  DspTargetPlatform platform = DspTargetPlatform.adau1466,
  Map<String, dynamic>? sigmaMappingReferenceJson,
  Map<String, dynamic>? fixedPointDraftJson,
}) {
  final mapping = SigmaMappingReference(
    id: 'ref1',
    platform: platform,
    mappings: [
      const SigmaParameterMapping(
        id: 'mv_l',
        platform: DspTargetPlatform.adau1466,
        blockKind: SigmaBlockKind.masterVolume,
        logicalName: 'Master Volume L',
        addressHex: '0x67',
        mappingStatus: SigmaMappingStatus.mappedVerified,
      ),
      const SigmaParameterMapping(
        id: 'mv_r',
        platform: DspTargetPlatform.adau1466,
        blockKind: SigmaBlockKind.masterVolume,
        logicalName: 'Master Volume R',
        addressHex: '0x64',
        mappingStatus: SigmaMappingStatus.mappedVerified,
      ),
      const SigmaParameterMapping(
        id: 'peq_all',
        platform: DspTargetPlatform.adau1466,
        blockKind: SigmaBlockKind.peq,
        logicalName: 'PEQ (all channels)',
        mappingStatus: SigmaMappingStatus.requiresCapture,
      ),
    ],
    warnings: [],
    summary: '3 blocks. 2 verified.',
    status: SigmaMappingStatus.partiallyMapped,
  );

  return DspExportPackage(
    id: 'pkg1',
    targetPlatform: platform,
    status: ExportStatus.draftReady,
    projectName: 'Test',
    sigmaMappingReferenceJson: sigmaMappingReferenceJson ?? mapping.toJson(),
    fixedPointDraftJson: fixedPointDraftJson,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Write plan basics', () {
    test('plan is always dryRunOnly', () {
      final project = _baseProject();
      final plan = generateHardwareWritePlan(project: project, package: _pkg());
      expect(plan.dryRunOnly, isTrue);
    });

    test('mode is dryRunOnly or guardedWriteDisabled', () {
      final project = _baseProject();
      final plan = generateHardwareWritePlan(project: project, package: _pkg());
      expect([HardwareWriteMode.dryRunOnly, HardwareWriteMode.guardedWriteDisabled],
          contains(plan.mode));
    });

    test('isHardwareWriteEnabled on HardwareProjectState is always false', () {
      expect(HardwareProjectState.createDefault().isHardwareWriteEnabled, isFalse);
    });
  });

  group('Guard checks', () {
    test('protection not passed blocks plan', () {
      final project = _baseProject(
          verificationStatus: VerificationStatus.notReady);
      final plan = generateHardwareWritePlan(project: project, package: _pkg());
      expect(plan.blockedReason, isNotNull);
      final check = plan.guardChecks
          .firstWhere((c) => c.id == 'guard_protection');
      expect(check.status, HardwareGuardStatus.blocked);
    });

    test('protection passed produces pass/warning guard', () {
      final project = _baseProject(verificationStatus: VerificationStatus.passed);
      final plan = generateHardwareWritePlan(project: project, package: _pkg());
      final check = plan.guardChecks
          .firstWhere((c) => c.id == 'guard_protection');
      expect([HardwareGuardStatus.pass, HardwareGuardStatus.warning],
          contains(check.status));
    });

    test('hardware write disabled guard is always blocked', () {
      final project = _baseProject();
      final plan = generateHardwareWritePlan(project: project, package: _pkg());
      final check = plan.guardChecks
          .firstWhere((c) => c.id == 'guard_hw_write_disabled');
      expect(check.status, HardwareGuardStatus.blocked);
    });

    test('EEPROM/Selfboot guard is pass', () {
      final project = _baseProject();
      final plan = generateHardwareWritePlan(project: project, package: _pkg());
      final check = plan.guardChecks
          .firstWhere((c) => c.id == 'guard_eeprom_selfboot');
      expect(check.status, HardwareGuardStatus.pass);
    });

    test('simulationOnly platform marks guard as notApplicable', () {
      final project = _baseProject(platform: DspTargetPlatform.simulationOnly);
      final pkg = _pkg(platform: DspTargetPlatform.simulationOnly);
      final plan = generateHardwareWritePlan(project: project, package: pkg);
      final check = plan.guardChecks
          .firstWhere((c) => c.id == 'guard_platform');
      expect(check.status, HardwareGuardStatus.notApplicable);
    });
  });

  group('Write plan steps — ADAU1466 verified addresses', () {
    late HardwareWritePlan plan;

    setUp(() {
      plan = generateHardwareWritePlan(
        project: _baseProject(),
        package: _pkg(),
      );
    });

    test('Master Volume L step uses 0x67', () {
      final step = plan.steps
          .where((s) => s.logicalName.contains('Master Volume L'))
          .firstOrNull;
      expect(step, isNotNull);
      expect(step!.addressHex, '0x67');
    });

    test('Master Volume R step uses 0x64', () {
      final step = plan.steps
          .where((s) => s.logicalName.contains('Master Volume R'))
          .firstOrNull;
      expect(step, isNotNull);
      expect(step!.addressHex, '0x64');
    });

    test('verified Master Volume steps have addressVerified true', () {
      final mvSteps = plan.steps
          .where((s) => s.logicalName.contains('Master Volume'));
      for (final step in mvSteps) {
        expect(step.addressVerified, isTrue,
            reason: '${step.logicalName} must be verified');
      }
    });

    test('unverified PEQ step has addressVerified false and is blocked', () {
      final peq = plan.steps
          .where((s) => s.logicalName.contains('PEQ'))
          .firstOrNull;
      expect(peq, isNotNull);
      expect(peq!.addressVerified, isFalse);
      expect(peq.status, HardwareGuardStatus.blocked);
    });

    test('all steps have mode dryRunOnly', () {
      for (final step in plan.steps) {
        expect(step.mode, HardwareWriteMode.dryRunOnly,
            reason: '${step.logicalName} must be dryRunOnly');
      }
    });
  });

  group('Fixed-point biquad steps', () {
    test('fixed-point stages without verified address are blocked', () {
      final fpDraft = {
        'format': 'format824',
        'stageCount': 2,
        'stages': [
          {'stageId': 's1', 'coefficients': []},
          {'stageId': 's2', 'coefficients': []},
        ],
      };
      final plan = generateHardwareWritePlan(
        project: _baseProject(),
        package: _pkg(fixedPointDraftJson: fpDraft),
      );
      final fpStep = plan.steps
          .where((s) => s.logicalName.contains('Biquad'))
          .firstOrNull;
      expect(fpStep, isNotNull);
      expect(fpStep!.addressVerified, isFalse);
      expect(fpStep.status, HardwareGuardStatus.blocked);
    });
  });

  group('Warnings', () {
    test('plan warnings mention no hardware write', () {
      final plan = generateHardwareWritePlan(
          project: _baseProject(), package: _pkg());
      final warnText = plan.warnings.join(' ').toLowerCase();
      expect(warnText, contains('hardware write'));
    });

    test('plan summary mentions DRY RUN', () {
      final plan = generateHardwareWritePlan(
          project: _baseProject(), package: _pkg());
      expect(plan.summary.toUpperCase(), contains('DRY RUN'));
    });
  });

  group('JSON round-trip', () {
    test('HardwareWritePlan round-trips JSON', () {
      final plan = generateHardwareWritePlan(
          project: _baseProject(), package: _pkg());
      final restored = HardwareWritePlan.fromJson(plan.toJson());
      expect(restored.dryRunOnly, isTrue);
      expect(restored.steps.length, plan.steps.length);
      expect(restored.guardChecks.length, plan.guardChecks.length);
      expect(restored.warnings.length, plan.warnings.length);
    });

    test('JSON does not contain actual write execution fields', () {
      final plan = generateHardwareWritePlan(
          project: _baseProject(), package: _pkg());
      final json = plan.toJson().toString().toLowerCase();
      // Guard: no fields indicating actual write execution
      expect(json, isNot(contains('sendusb')));
      expect(json, isNot(contains('sendble')));
      expect(json, isNot(contains('safeloadexecute')));
      expect(json, isNot(contains('writeregister')));
      expect(json, isNot(contains('usbipacket')));
      expect(json, isNot(contains('blepacket')));
    });

    test('no USBi/BLE packet fields in plan JSON', () {
      final plan = generateHardwareWritePlan(
          project: _baseProject(), package: _pkg());
      final json = plan.toJson();
      expect(json.containsKey('usbPacket'), isFalse);
      expect(json.containsKey('blePacket'), isFalse);
      expect(json.containsKey('safeload'), isFalse);
    });
  });

  group('Safety restrictions', () {
    test('blockedReason is always set (hardware write always blocked)', () {
      final plan = generateHardwareWritePlan(
          project: _baseProject(), package: _pkg());
      // Even with protection passed, Phase Q always blocks write
      expect(plan.blockedReason, isNotNull);
    });

    test('guard_hw_write_disabled is always present', () {
      final plan = generateHardwareWritePlan(
          project: _baseProject(), package: _pkg());
      final ids = plan.guardChecks.map((c) => c.id).toList();
      expect(ids, contains('guard_hw_write_disabled'));
    });

    test('guard_eeprom_selfboot is always present and passes', () {
      final plan = generateHardwareWritePlan(
          project: _baseProject(), package: _pkg());
      final check = plan.guardChecks
          .firstWhere((c) => c.id == 'guard_eeprom_selfboot');
      expect(check.status, HardwareGuardStatus.pass);
      expect(check.description.toLowerCase(), contains('eeprom'));
      expect(check.description.toLowerCase(), contains('selfboot'));
    });
  });
}
