// ── TUNAI PRO Phase H/I — DSP Export Engine ──────────────────────────────────
// Generates draft export packages from project state.
// No hardware write. No USBi. No SafeLoad. No DSP register addresses.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_project.dart';
import 'pro_protection_data.dart';
import 'pro_export_data.dart';
import 'pro_dsp_target_data.dart';

DspExportPackage generateDspExportDraft({required ProProject project}) {
  final acoustic = project.acousticState;
  final tuning = project.tuningState;
  final protection = project.protectionState;
  final optimizer = project.optimizerState;
  final exportState = project.exportState;

  int seq = 0;
  String nextId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${seq++}';

  // ── Target profile ────────────────────────────────────────────────────────

  final targetProfile = DspTargetProfile.forPlatform(exportState.selectedTarget);

  DspExportPackage blocked(String reason) => DspExportPackage(
    id: nextId('pkg'),
    targetPlatform: exportState.selectedTarget,
    format: exportState.selectedFormat,
    status: ExportStatus.blocked,
    projectName: project.name,
    tuningRevision: tuning.tuningRevision,
    protectionRevision: protection.revision,
    optimizerRevision: optimizer.revision,
    blockedReason: reason,
    implementationDraftJson: DspImplementationDraft(
      targetProfile: targetProfile,
      warnings: [reason],
    ).toJson(),
  );

  // ── Guards ────────────────────────────────────────────────────────────────

  if (protection.verificationStatus == VerificationStatus.notReady) {
    return blocked('Protection verification has not been run.');
  }
  if (protection.verificationStatus == VerificationStatus.failed) {
    return blocked('Critical protection issues block export.');
  }
  if (acoustic.driverChannels.isEmpty) {
    return blocked('No driver channels configured.');
  }

  // ── Target capability checks ──────────────────────────────────────────────

  final channelCount = acoustic.driverChannels.length;
  if (channelCount > targetProfile.maxChannels) {
    return blocked(
      'Channel count ($channelCount) exceeds target maximum '
      '(${targetProfile.maxChannels}) for ${targetProfile.displayName}.',
    );
  }

  for (final ch in tuning.peqChannels) {
    final enabled = ch.bands.where((b) => b.enabled).length;
    if (enabled > targetProfile.maxPeqBandsPerChannel) {
      return blocked(
        'Channel ${ch.channelId} has $enabled active PEQ bands, '
        'exceeding target limit of ${targetProfile.maxPeqBandsPerChannel} '
        'for ${targetProfile.displayName}.',
      );
    }
  }

  // ── Channel maps ──────────────────────────────────────────────────────────

  final channelMaps = acoustic.driverChannels.map((d) => ExportChannelMap(
    channelId: d.id,
    logicalName: d.name,
    role: d.role.name,
    side: d.side.name,
    outputIndex: d.dspOutputIndex,
  )).toList();

  // ── Parameter blocks ──────────────────────────────────────────────────────

  final blocks = <ExportParameterBlock>[];

  // PEQ blocks
  for (final ch in tuning.peqChannels) {
    final enabledBands = ch.bands.where((b) => b.enabled).toList();
    if (enabledBands.isEmpty) continue;
    final bandsJson = enabledBands.asMap().map((i, b) => MapEntry('band_$i', {
      'freq_hz': b.frequencyHz,
      'gain_db': b.gainDb,
      'q': b.q,
      'type': b.type.name,
    }));
    blocks.add(ExportParameterBlock(
      id: nextId('blk'),
      type: ExportBlockType.peq,
      channelId: ch.channelId,
      title: 'PEQ — ${ch.channelId}',
      summary: '${enabledBands.length} enabled band(s)',
      parameters: {'bands': bandsJson, 'bandCount': enabledBands.length},
    ));
  }

  // XO blocks
  for (final xo in tuning.crossoverChannels) {
    if (!xo.isConfigured) continue;
    final params = <String, dynamic>{};
    if (xo.hasHighPass) {
      final hp = xo.highPass!;
      params['highPass'] = {
        'freq_hz': hp.frequencyHz,
        'type': hp.type.name,
        'slope': hp.slope.name,
        'enabled': hp.enabled,
      };
    }
    if (xo.hasLowPass) {
      final lp = xo.lowPass!;
      params['lowPass'] = {
        'freq_hz': lp.frequencyHz,
        'type': lp.type.name,
        'slope': lp.slope.name,
        'enabled': lp.enabled,
      };
    }
    if (xo.polarityInverted) params['polarityInverted'] = true;
    blocks.add(ExportParameterBlock(
      id: nextId('blk'),
      type: ExportBlockType.crossover,
      channelId: xo.channelId,
      title: 'Crossover — ${xo.channelId}',
      summary: [
        if (xo.hasHighPass) 'HPF ${xo.highPass!.frequencyHz.toStringAsFixed(0)} Hz',
        if (xo.hasLowPass)  'LPF ${xo.lowPass!.frequencyHz.toStringAsFixed(0)} Hz',
        if (xo.polarityInverted) 'Polarity inverted',
      ].join(', '),
      parameters: params,
    ));
  }

  // Channel control blocks (gain / delay / phase)
  for (final ctrl in tuning.channelControls) {
    if (!ctrl.isControlActive) continue;
    final params = <String, dynamic>{};
    String summary = '';

    if (ctrl.hasGainTrim) {
      params['gainDb'] = ctrl.gainDb;
      summary += 'Gain ${ctrl.gainDb >= 0 ? '+' : ''}${ctrl.gainDb.toStringAsFixed(1)} dB  ';
    }
    if (ctrl.hasDelay) {
      params['delayMs'] = ctrl.delayMs;
      params['distanceCm'] = ctrl.delayDistanceCm;
      summary += 'Delay ${ctrl.delayMs.toStringAsFixed(2)} ms  ';
    }
    if (ctrl.phaseOffsetDeg != 0.0) {
      params['phaseOffsetDeg'] = ctrl.phaseOffsetDeg;
      summary +=
          'Phase ${ctrl.phaseOffsetDeg >= 0 ? '+' : ''}${ctrl.phaseOffsetDeg.toStringAsFixed(0)}°  ';
    }
    if (ctrl.muted) params['muted'] = true;
    if (ctrl.solo) params['solo'] = true;

    final blockType = ctrl.hasDelay
        ? ExportBlockType.delay
        : ctrl.phaseOffsetDeg != 0.0
            ? ExportBlockType.phase
            : ExportBlockType.gain;

    blocks.add(ExportParameterBlock(
      id: nextId('blk'),
      type: blockType,
      channelId: ctrl.channelId,
      title: '${blockType.label} — ${ctrl.channelId}',
      summary: summary.trim(),
      parameters: params,
    ));
  }

  // Protection summary block
  blocks.add(ExportParameterBlock(
    id: nextId('blk'),
    type: ExportBlockType.protection,
    channelId: 'system',
    title: 'Protection Summary',
    summary: '${protection.activeRuleCount} active rules · '
        '${protection.triggeredIssueCount} issue(s) · '
        '${protection.verificationStatus.label}',
    parameters: {
      'verificationStatus': protection.verificationStatus.name,
      'activeRules': protection.activeRuleCount,
      'warnings': protection.warningCount,
      'critical': protection.criticalCount,
      'exportLocked': protection.exportLocked,
      'revision': protection.revision,
    },
    warning: protection.exportLocked ? 'Export is locked by protection rules.' : null,
  ));

  // ── Parameter slots (Phase I) ─────────────────────────────────────────────

  final slots = <DspParameterSlot>[];
  int slotIdx = 0;
  for (final blk in blocks) {
    slots.add(DspParameterSlot(
      id: nextId('slot'),
      channelId: blk.channelId,
      blockType: blk.type,
      logicalName: blk.title,
      slotIndex: slotIdx++,
      addressPlaceholder: '0x????',
      notes: 'Address requires SigmaStudio capture for '
          '${targetProfile.displayName}.',
    ));
  }

  // ── Biquad draft stages (Phase I) ─────────────────────────────────────────

  const coeffPlaceholderWarning =
      'Coefficient placeholder only. Final biquad calculation will be added later.';
  const placeholderCoeffs = BiquadCoefficientSet(
    b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0,
    status: BiquadDraftStatus.placeholder,
    warning: coeffPlaceholderWarning,
  );

  final biquadStages = <BiquadDraftStage>[];

  // PEQ bands → biquad stages
  for (final ch in tuning.peqChannels) {
    int bandIdx = 0;
    for (final band in ch.bands.where((b) => b.enabled)) {
      biquadStages.add(BiquadDraftStage(
        id: nextId('bq'),
        channelId: ch.channelId,
        sourceBlockId: 'peq_${ch.channelId}',
        title: 'PEQ Band ${bandIdx + 1} — ${ch.channelId}',
        filterSummary: '${band.type.name.toUpperCase()}  '
            '${band.frequencyHz.toStringAsFixed(0)} Hz  '
            '${band.gainDb >= 0 ? '+' : ''}${band.gainDb.toStringAsFixed(1)} dB  '
            'Q${band.q.toStringAsFixed(2)}',
        coefficients: placeholderCoeffs,
      ));
      bandIdx++;
    }
  }

  // XO filters → biquad stages
  for (final xo in tuning.crossoverChannels) {
    if (xo.hasHighPass) {
      final hp = xo.highPass!;
      biquadStages.add(BiquadDraftStage(
        id: nextId('bq'),
        channelId: xo.channelId,
        sourceBlockId: 'xo_${xo.channelId}',
        title: 'HPF — ${xo.channelId}',
        filterSummary: 'HPF  ${hp.frequencyHz.toStringAsFixed(0)} Hz  '
            '${hp.type.name}  ${hp.slope.name}',
        coefficients: placeholderCoeffs,
      ));
    }
    if (xo.hasLowPass) {
      final lp = xo.lowPass!;
      biquadStages.add(BiquadDraftStage(
        id: nextId('bq'),
        channelId: xo.channelId,
        sourceBlockId: 'xo_${xo.channelId}',
        title: 'LPF — ${xo.channelId}',
        filterSummary: 'LPF  ${lp.frequencyHz.toStringAsFixed(0)} Hz  '
            '${lp.type.name}  ${lp.slope.name}',
        coefficients: placeholderCoeffs,
      ));
    }
  }

  // ── Collect warnings ──────────────────────────────────────────────────────

  final warnings = <String>[];
  if (protection.verificationStatus == VerificationStatus.passedWithWarnings) {
    warnings.add(
        'Verification passed with ${protection.warningCount} warning(s). Expert review required.');
  }
  if (acoustic.hasMissingMeasurements) {
    warnings.add(
        'FRD data missing on ${acoustic.totalDrivers - acoustic.importedFrdCount} channel(s).');
  }
  if (optimizer.acceptedSuggestionCount > 0) {
    warnings.add(
        '${optimizer.acceptedSuggestionCount} optimizer suggestion(s) accepted. Re-verify before export.');
  }
  if (biquadStages.isNotEmpty) {
    warnings.add(
        'Biquad coefficients are placeholders and must not be used for hardware write.');
  }
  if (targetProfile.warning != null) {
    warnings.add(targetProfile.warning!);
  }
  for (final blk in blocks) {
    if (blk.warning != null) warnings.add(blk.warning!);
  }

  // ── Implementation draft ──────────────────────────────────────────────────

  final draftWarnings = <String>[];
  if (biquadStages.isNotEmpty) {
    draftWarnings.add(coeffPlaceholderWarning);
  }
  if (targetProfile.warning != null) {
    draftWarnings.add(targetProfile.warning!);
  }

  final implDraft = DspImplementationDraft(
    targetProfile: targetProfile,
    parameterSlots: slots,
    biquadStages: biquadStages,
    warnings: draftWarnings,
  );

  return DspExportPackage(
    id: nextId('pkg'),
    targetPlatform: exportState.selectedTarget,
    format: exportState.selectedFormat,
    status: ExportStatus.draftReady,
    projectName: project.name,
    tuningRevision: tuning.tuningRevision,
    protectionRevision: protection.revision,
    optimizerRevision: optimizer.revision,
    channelMaps: channelMaps,
    parameterBlocks: blocks,
    warnings: warnings,
    implementationDraftJson: implDraft.toJson(),
  );
}
