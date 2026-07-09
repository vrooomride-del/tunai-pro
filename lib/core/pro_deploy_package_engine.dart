// ── TUNAI PRO Phase R — Deploy Package Engine ─────────────────────────────────
// Generates versioned review/dry-run packages. No hardware write of any kind.
// DO NOT write to hardware. DO NOT send USB/BLE packets. DO NOT execute SafeLoad.
// DO NOT write EEPROM/Selfboot. DO NOT guess DSP addresses.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_project.dart';
import 'pro_protection_data.dart';
import 'pro_export_data.dart';
import 'pro_deploy_package_data.dart';

const _kSafetyNote =
    'This deploy package is a review/dry-run package. No hardware write has been performed.';

DeployPackage generateDeployPackage({
  required ProProject project,
  DeployPackageKind kind = DeployPackageKind.fullProjectSnapshot,
  String? name,
  String? notes,
}) {
  final now = DateTime.now();
  final id = 'deploy_${now.millisecondsSinceEpoch}_${project.id.hashCode.abs()}';

  // ── Version string ──────────────────────────────────────────────────────────
  final tuningRev = project.tuningState.tuningRevision;
  final exportRev = project.exportState.revision;
  final version = 'v$tuningRev.$exportRev.0-draft';

  // ── Gather sub-state references ─────────────────────────────────────────────
  final acoustic = project.acousticState;
  final tuning = project.tuningState;
  final simulation = project.simulationState;
  final protection = project.protectionState;
  final export = project.exportState;
  final hardware = project.hardwareState;

  final activeExportPkg = export.activePackage;
  final activeHwPlan = hardware.activePlan;

  // ── Build snapshot summaries ────────────────────────────────────────────────

  final measurementSummary = <String, dynamic>{
    'driverCount': acoustic.totalDrivers,
    'frdCount': acoustic.importedFrdCount,
    'zmaCount': acoustic.importedZmaCount,
    'readyDriverCount': acoustic.readyDriverCount,
    'readinessLabel': acoustic.readinessLabel,
  };

  final tuningSummary = <String, dynamic>{
    'revision': tuning.tuningRevision,
    'totalPeqBands': tuning.totalPeqBands,
    'activePeqBands': tuning.activePeqBands,
    'configuredXoChannels': tuning.configuredXoChannels,
    'hasManualChanges': tuning.hasManualChanges,
  };

  final simulationSummary = <String, dynamic>{
    'revision': simulation.revision,
    'runCount': simulation.runs.length,
    'hasResults': simulation.runs.isNotEmpty,
    'readinessLabel': simulation.readinessLabel,
  };

  final protectionSummary = <String, dynamic>{
    'revision': protection.revision,
    'verificationStatus': protection.verificationStatus.name,
    'readinessLabel': protection.readinessLabel,
    'issueCount': protection.issues.length,
    'criticalCount': protection.issues
        .where((i) => i.severity == ProtectionSeverity.critical)
        .length,
  };

  final exportSummary = <String, dynamic>{
    'revision': export.revision,
    'packageCount': export.packageCount,
    'activePackageId': activeExportPkg?.id,
    'activeStatus': activeExportPkg?.status.name,
    'selectedTarget': export.selectedTarget.label,
    'readinessLabel': export.readinessLabel,
  };

  final hardwareSummary = <String, dynamic>{
    'revision': hardware.revision,
    'planCount': hardware.planCount,
    'activePlanId': activeHwPlan?.id,
    'dryRunOnly': activeHwPlan?.dryRunOnly ?? true,
    'blockedCheckCount': hardware.blockedCheckCount,
    'warningCheckCount': hardware.warningCheckCount,
    'readinessLabel': hardware.readinessLabel,
    'hardwareWriteEnabled': hardware.isHardwareWriteEnabled,
    'safetyNote': _kSafetyNote,
  };

  // ── Warnings and block reasons ──────────────────────────────────────────────
  final warnings = <String>[];
  String? blockedReason;

  final exportBlocked = activeExportPkg?.status == ExportStatus.blocked ||
      activeExportPkg?.status == ExportStatus.notReady;

  if (protection.verificationStatus == VerificationStatus.failed) {
    blockedReason = 'Protection verification failed. Resolve before deploy.';
  } else if (activeExportPkg == null &&
      kind != DeployPackageKind.simulationPreset) {
    blockedReason = 'No export package found. Generate export first.';
  } else if (exportBlocked && activeExportPkg != null) {
    blockedReason = 'Export package is blocked.';
  }

  if (acoustic.importedFrdCount < acoustic.totalDrivers) {
    warnings.add('Some channels are missing FRD measurement data.');
  }
  if (acoustic.importedZmaCount < acoustic.totalDrivers) {
    warnings.add('Some channels are missing ZMA impedance data.');
  }
  if (simulation.runs.isEmpty) {
    warnings.add('Simulation has not been run.');
  }
  if (protection.verificationStatus == VerificationStatus.notReady) {
    warnings.add('Protection verification not completed.');
  }
  if (protection.verificationStatus == VerificationStatus.passedWithWarnings) {
    warnings.add('Protection passed with warnings — review before deployment.');
  }
  if (activeExportPkg?.sigmaMappingReferenceJson != null) {
    warnings.add('Some DSP parameter mappings require SigmaStudio capture.');
  }
  if (activeExportPkg?.fixedPointDraftJson != null) {
    warnings.add('Fixed-point coefficient draft requires expert verification.');
  }
  warnings.add('Hardware write disabled. Dry-run planning only.');
  if (activeHwPlan != null && activeHwPlan.blockedCheckCount > 0) {
    warnings.add(
        'Hardware dry-run plan has ${activeHwPlan.blockedCheckCount} blocked guard check(s).');
  }
  warnings.add(_kSafetyNote);

  // ── Determine readiness level ───────────────────────────────────────────────
  final DeployReadinessLevel readinessLevel;
  if (blockedReason != null) {
    readinessLevel = DeployReadinessLevel.blocked;
  } else if (activeHwPlan != null &&
      activeExportPkg != null &&
      (protection.verificationStatus == VerificationStatus.passed ||
          protection.verificationStatus ==
              VerificationStatus.passedWithWarnings) &&
      activeHwPlan.dryRunOnly) {
    readinessLevel = DeployReadinessLevel.readyForDryRun;
  } else if (activeExportPkg != null &&
      (protection.verificationStatus == VerificationStatus.passed ||
          protection.verificationStatus ==
              VerificationStatus.passedWithWarnings)) {
    readinessLevel = DeployReadinessLevel.readyForReview;
  } else if (warnings.isNotEmpty) {
    readinessLevel = DeployReadinessLevel.warnings;
  } else {
    readinessLevel = DeployReadinessLevel.incomplete;
  }

  // ── Determine package status ────────────────────────────────────────────────
  final DeployPackageStatus status;
  if (readinessLevel == DeployReadinessLevel.blocked) {
    status = DeployPackageStatus.blocked;
  } else if (readinessLevel == DeployReadinessLevel.readyForReview ||
      readinessLevel == DeployReadinessLevel.readyForDryRun) {
    status = DeployPackageStatus.ready;
  } else {
    status = DeployPackageStatus.draft;
  }

  // ── Build snapshot ──────────────────────────────────────────────────────────
  final snapshot = DeployPackageSnapshot(
    projectId: project.id,
    projectName: project.name,
    projectStatus: project.profileStatus.label,
    createdAt: now,
    tuningRevision: tuning.tuningRevision,
    protectionRevision: protection.revision,
    exportRevision: export.revision,
    hardwareRevision: hardware.revision,
    simulationRevision: simulation.revision,
    measurementSummary: measurementSummary,
    tuningSummary: tuningSummary,
    simulationSummary: simulationSummary,
    protectionSummary: protectionSummary,
    exportSummary: exportSummary,
    hardwareSummary: hardwareSummary,
    warnings: warnings,
    blockedReason: blockedReason,
  );

  final resolvedName = name?.isNotEmpty == true
      ? name!
      : '${project.name} — ${kind.label} $version';

  return DeployPackage(
    id: id,
    version: version,
    name: resolvedName,
    kind: kind,
    status: status,
    readinessLevel: readinessLevel,
    createdAt: now,
    updatedAt: now,
    snapshot: snapshot,
    exportPackageId: activeExportPkg?.id,
    hardwarePlanId: activeHwPlan?.id,
    notes: notes,
  );
}
