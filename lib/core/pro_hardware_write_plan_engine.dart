// ── TUNAI PRO Phase Q — Hardware Write Plan Engine (Dry-Run Only) ─────────────
// Generates dry-run hardware write plans from export packages.
// NEVER writes to hardware. NEVER sends USB or BLE packets.
// NEVER executes SafeLoad. NEVER writes EEPROM or Selfboot.
// All plans are dryRunOnly. Hardware write is disabled in Phase Q.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_project.dart';
import 'pro_export_data.dart';
import 'pro_protection_data.dart';
import 'pro_hardware_connection_data.dart';
import 'pro_dsp_address_registry.dart';
import 'pro_sigma_mapping_data.dart';

HardwareWritePlan generateHardwareWritePlan({
  required ProProject project,
  required DspExportPackage package,
}) {
  int seq = 0;
  String nextId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${seq++}';

  final platform = package.targetPlatform;
  final transportType =
      project.hardwareState.connectionState.transportType;

  final guardChecks = <HardwareGuardCheck>[];
  final steps = <HardwareWritePlanStep>[];
  final warnings = <String>[];
  String? blockedReason;
  int stepOrder = 0;

  // ── Guard A: Export package ───────────────────────────────────────────────
  guardChecks.add(const HardwareGuardCheck(
    id: 'guard_export_package',
    title: 'Export Package Present',
    status: HardwareGuardStatus.pass,
    description: 'A DSP export package has been provided for write-plan generation.',
  ));

  // ── Guard B: Protection status ────────────────────────────────────────────
  final protection = project.protectionState;
  final protectionPassed = protection.verificationStatus == VerificationStatus.passed ||
      protection.verificationStatus == VerificationStatus.passedWithWarnings;

  if (!protectionPassed) {
    guardChecks.add(HardwareGuardCheck(
      id: 'guard_protection',
      title: 'Protection Verification',
      status: HardwareGuardStatus.blocked,
      description: 'Protection verification has not passed '
          '(status: ${protection.verificationStatus.name}). '
          'Write plan is blocked.',
      recommendation: 'Run protection verification and resolve all critical issues.',
    ));
    blockedReason = 'Protection verification has not passed.';
  } else {
    guardChecks.add(HardwareGuardCheck(
      id: 'guard_protection',
      title: 'Protection Verification',
      status: protectionPassed && protection.warningCount > 0
          ? HardwareGuardStatus.warning
          : HardwareGuardStatus.pass,
      description: protection.warningCount > 0
          ? 'Protection passed with ${protection.warningCount} warning(s). Expert review required.'
          : 'Protection verification passed.',
      recommendation: protection.warningCount > 0
          ? 'Review all protection warnings before hardware deployment.'
          : null,
    ));
  }

  // ── Guard C: Target platform ──────────────────────────────────────────────
  final isAdauTarget = platform == DspTargetPlatform.adau1466 ||
      platform == DspTargetPlatform.adau1701;
  final isSimTarget = platform == DspTargetPlatform.simulationOnly ||
      platform == DspTargetPlatform.genericBiquad;

  guardChecks.add(HardwareGuardCheck(
    id: 'guard_platform',
    title: 'Target Platform',
    status: isSimTarget
        ? HardwareGuardStatus.notApplicable
        : HardwareGuardStatus.warning,
    description: isSimTarget
        ? '${platform.label} — no hardware target. Write plan is not applicable.'
        : '${platform.label} — dry-run planning only. '
            'Actual hardware write requires further phase implementation.',
    recommendation: isSimTarget
        ? null
        : 'Select verified DSP target and ensure address registry is complete.',
  ));

  // ── Guard D: Address verification ─────────────────────────────────────────
  final registry = DspAddressRegistry.createDefault();
  final hasVerifiedMV = registry.hasVerifiedMasterVolume1466 &&
      platform == DspTargetPlatform.adau1466;

  guardChecks.add(HardwareGuardCheck(
    id: 'guard_address_verification',
    title: 'Verified Address Registry',
    status: hasVerifiedMV
        ? HardwareGuardStatus.warning
        : (isAdauTarget ? HardwareGuardStatus.blocked : HardwareGuardStatus.notApplicable),
    description: hasVerifiedMV
        ? 'ADAU1466 Master Volume L (0x67) and R (0x64) are verified references. '
            'All other parameter addresses are unverified and cannot be written.'
        : isAdauTarget
            ? 'No verified addresses available for ${platform.label}. '
                'All mappings require SigmaStudio Export/Capture.'
            : 'No hardware address mapping required for ${platform.label}.',
    recommendation: isAdauTarget
        ? 'Perform SigmaStudio Export/Capture to obtain verified addresses '
            'for all required parameter blocks.'
        : null,
  ));

  // ── Guard E: Hardware write disabled ──────────────────────────────────────
  guardChecks.add(const HardwareGuardCheck(
    id: 'guard_hw_write_disabled',
    title: 'Hardware Write Disabled',
    status: HardwareGuardStatus.blocked,
    description: 'Hardware write is disabled in Phase Q. '
        'This plan is for dry-run preview only.',
    recommendation: 'Enable only after USBi/BLE transport and SafeLoad guard '
        'are implemented and verified in a later phase.',
  ));

  // ── Guard F: EEPROM/Selfboot forbidden ────────────────────────────────────
  guardChecks.add(const HardwareGuardCheck(
    id: 'guard_eeprom_selfboot',
    title: 'EEPROM/Selfboot Write Disabled',
    status: HardwareGuardStatus.pass,
    description: 'EEPROM and Selfboot write are disabled. '
        'No persistent DSP program write is performed.',
  ));

  warnings.add('Hardware write is disabled in Phase Q. Dry-run preview only.');
  warnings.add('Only verified DSP addresses may be used in production write.');
  warnings.add('All unverified mappings require SigmaStudio Export/Capture.');
  warnings.add('No USB or BLE packets are sent.');
  warnings.add('EEPROM/Selfboot write is disabled.');

  // ── Build write plan steps from SigmaStudio mapping reference ────────────
  if (package.sigmaMappingReferenceJson != null && blockedReason == null) {
    final mappingRef = SigmaMappingReference.fromJson(
        package.sigmaMappingReferenceJson!);

    for (final mapping in mappingRef.mappings) {
      final isVerified = mapping.mappingStatus == SigmaMappingStatus.mappedVerified;
      final isMV = mapping.blockKind == SigmaBlockKind.masterVolume &&
          platform == DspTargetPlatform.adau1466;

      steps.add(HardwareWritePlanStep(
        id: nextId('step'),
        order: stepOrder++,
        blockType: _blockKindToExportType(mapping.blockKind),
        logicalName: mapping.logicalName,
        parameterKind: _blockKindToParamKind(mapping.blockKind),
        channelId: mapping.channelId,
        addressHex: mapping.addressHex,
        addressVerified: isVerified,
        mode: HardwareWriteMode.dryRunOnly,
        status: isVerified
            ? HardwareGuardStatus.warning  // verified but write still disabled
            : HardwareGuardStatus.blocked,
        warning: isVerified && isMV
            ? 'Verified reference only. No write performed. '
                'Address ${mapping.addressHex} is a dry-run reference.'
            : 'Mapping requires SigmaStudio Export/Capture before hardware write.',
      ));
    }
  }

  // ── Build steps from fixed-point draft ────────────────────────────────────
  if (package.fixedPointDraftJson != null && blockedReason == null) {
    final fpDraft = package.fixedPointDraftJson!;
    final stages = fpDraft['stages'] as List? ?? [];
    if (stages.isNotEmpty) {
      steps.add(HardwareWritePlanStep(
        id: nextId('step_fp'),
        order: stepOrder++,
        blockType: ExportBlockType.peq,
        logicalName: 'Biquad Coefficients (${stages.length} stage(s))',
        parameterKind: DspParameterKind.peq,
        addressVerified: false,
        valuePreview: '${stages.length} biquad stage(s)',
        mode: HardwareWriteMode.dryRunOnly,
        status: HardwareGuardStatus.blocked,
        warning: 'Fixed-point coefficient exists but no verified DSP address mapping '
            'is available. Address requires SigmaStudio Export/Capture.',
      ));
    }
  }

  // ── If no mapping/fixed-point data, add placeholder summary ───────────────
  if (steps.isEmpty && isSimTarget) {
    steps.add(HardwareWritePlanStep(
      id: nextId('step_sim'),
      order: stepOrder++,
      blockType: ExportBlockType.gain,
      logicalName: '${platform.label} — no hardware write required',
      addressVerified: false,
      mode: HardwareWriteMode.dryRunOnly,
      status: HardwareGuardStatus.notApplicable,
      warning: 'Simulation target — no hardware write plan required.',
    ));
  }

  final verifiedCount = steps.where((s) => s.addressVerified).length;
  final blockedCount = steps.where((s) => s.status == HardwareGuardStatus.blocked).length;
  final planBlockedChecks = guardChecks
      .where((c) => c.status == HardwareGuardStatus.blocked)
      .length;

  if (blockedReason == null && planBlockedChecks > 0) {
    blockedReason = 'Hardware write is disabled in Phase Q.';
  }

  final summary = 'DRY RUN ONLY — '
      '${steps.length} step(s), '
      '$verifiedCount verified address(es), '
      '$blockedCount blocked. '
      'No hardware write is performed.';

  return HardwareWritePlan(
    id: nextId('plan'),
    targetPlatform: platform,
    transportType: transportType,
    mode: HardwareWriteMode.dryRunOnly,
    packageId: package.id,
    steps: steps,
    guardChecks: guardChecks,
    warnings: warnings,
    blockedReason: blockedReason,
    summary: summary,
    dryRunOnly: true,
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

ExportBlockType _blockKindToExportType(SigmaBlockKind kind) => switch (kind) {
  SigmaBlockKind.peq         => ExportBlockType.peq,
  SigmaBlockKind.crossover   => ExportBlockType.crossover,
  SigmaBlockKind.gain        => ExportBlockType.gain,
  SigmaBlockKind.delay       => ExportBlockType.delay,
  SigmaBlockKind.mute        => ExportBlockType.protection,
  SigmaBlockKind.output      => ExportBlockType.gain,
  SigmaBlockKind.masterVolume => ExportBlockType.gain,
  _                          => ExportBlockType.peq,
};

DspParameterKind _blockKindToParamKind(SigmaBlockKind kind) => switch (kind) {
  SigmaBlockKind.masterVolume => DspParameterKind.masterVolume,
  SigmaBlockKind.peq          => DspParameterKind.peq,
  SigmaBlockKind.crossover    => DspParameterKind.crossover,
  SigmaBlockKind.gain         => DspParameterKind.gain,
  SigmaBlockKind.delay        => DspParameterKind.delay,
  SigmaBlockKind.mute         => DspParameterKind.mute,
  SigmaBlockKind.output       => DspParameterKind.outputMapping,
  SigmaBlockKind.safeload     => DspParameterKind.safeload,
  _                           => DspParameterKind.unknown,
};
