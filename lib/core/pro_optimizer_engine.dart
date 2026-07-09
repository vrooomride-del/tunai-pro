// ── TUNAI PRO Phase G — Draft Optimizer Engine ────────────────────────────────
// Transparent rule-based draft suggestions only. No tuning is modified here.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_acoustic_data.dart';
import 'pro_tuning_data.dart';
import 'pro_protection_data.dart';
import 'pro_optimizer_data.dart';

OptimizerRunResult runDraftOptimizer({
  required MeasurementProjectState acousticState,
  required TuningProjectState tuningState,
  required ProtectionProjectState protectionState,
  required OptimizerRunConfig config,
}) {
  final suggestions = <OptimizerSuggestion>[];
  int seq = 0;
  String nextId() => 'sug_${DateTime.now().millisecondsSinceEpoch}_${seq++}';

  // ── Guard: critical protection issues ──────────────────────────────────────
  if (protectionState.criticalCount > 0) {
    suggestions.add(OptimizerSuggestion(
      id: nextId(),
      type: OptimizerSuggestionType.warningOnly,
      confidence: OptimizerConfidence.high,
      title: 'Critical protection issues detected',
      description: 'Resolve ${protectionState.criticalCount} critical issue(s) before applying optimizer suggestions.',
      reason: 'Optimizer suggestions may conflict with protection rules.',
    ));
  }

  // ── Guard: no driver channels ──────────────────────────────────────────────
  if (acousticState.driverChannels.isEmpty) {
    suggestions.add(OptimizerSuggestion(
      id: nextId(),
      type: OptimizerSuggestionType.warningOnly,
      confidence: OptimizerConfidence.high,
      title: 'No driver channels configured',
      description: 'No driver channels configured. Import measurements first.',
      reason: 'Driver channels are required before optimization.',
    ));
    return _buildResult(config, suggestions, seq);
  }

  // ── Guard: FRD data incomplete ─────────────────────────────────────────────
  if (acousticState.hasMissingMeasurements) {
    suggestions.add(OptimizerSuggestion(
      id: nextId(),
      type: OptimizerSuggestionType.warningOnly,
      confidence: OptimizerConfidence.high,
      title: 'FRD measurements incomplete',
      description: 'Import FRD data before optimization.',
      reason: 'Final optimization accuracy requires complete frequency response data.',
    ));
  }

  // ── Guard: no target curve ─────────────────────────────────────────────────
  if (config.targetPresetName == 'flat' &&
      acousticState.targetCurve.selectedPreset == TargetCurvePreset.flat) {
    suggestions.add(OptimizerSuggestion(
      id: nextId(),
      type: OptimizerSuggestionType.warningOnly,
      confidence: OptimizerConfidence.medium,
      title: 'No target curve selected',
      description: 'Select a target curve before final optimization.',
      reason: 'A target curve is needed to generate meaningful correction suggestions.',
    ));
  }

  // ── PEQ / Gain / XO suggestions (only if scope includes them) ─────────────
  final doPeq = config.scope == OptimizerScope.peq ||
      config.scope == OptimizerScope.fullSystem;
  final doGain = config.scope == OptimizerScope.gain ||
      config.scope == OptimizerScope.fullSystem;
  final doXo = config.scope == OptimizerScope.crossover ||
      config.scope == OptimizerScope.fullSystem;

  // PEQ draft suggestions per channel
  if (doPeq) {
    for (final driver in acousticState.driverChannels) {
      if (!driver.hasFrd) { continue; }
      final existingBands = tuningState.peqChannels
          .firstWhere((c) => c.channelId == driver.id,
              orElse: () => PeqChannelState.empty(driver.id))
          .bands
          .length;
      if (existingBands >= config.maxPeqBandsPerChannel) { continue; }

      // Role-based placeholder frequency
      final freq = _placeholderFreq(driver.role);
      final gain = _placeholderGain(config.mode);
      final confidence = acousticState.importedFrdCount == acousticState.totalDrivers
          ? OptimizerConfidence.medium
          : OptimizerConfidence.low;

      suggestions.add(OptimizerSuggestion(
        id: nextId(),
        type: OptimizerSuggestionType.addPeqBand,
        confidence: confidence,
        channelId: driver.id,
        title: 'Review response shaping for ${driver.name}',
        description: 'Draft PEQ band at ${freq.toStringAsFixed(0)} Hz '
            '(${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB, Q 1.0).',
        reason: 'Draft suggestion based on target/measurement readiness. '
            'Final optimizer will refine this.',
        proposedFrequencyHz: freq,
        proposedGainDb: gain,
        proposedQ: 1.0,
      ));
    }
  }

  // HPF suggestions for woofer channels without HPF
  if (doXo) {
    for (final driver in acousticState.driverChannels) {
      final isWoofer = driver.role == DriverRole.woofer ||
          driver.role == DriverRole.coaxWoofer ||
          driver.role == DriverRole.subwoofer;
      if (!isWoofer) { continue; }
      final xoCh = tuningState.getOrCreateCrossoverChannel(driver.id);
      if (xoCh.hasHighPass) { continue; }

      final hpfHz = _hpfPlaceholder(config.mode);
      suggestions.add(OptimizerSuggestion(
        id: nextId(),
        type: OptimizerSuggestionType.addHighPass,
        confidence: OptimizerConfidence.medium,
        channelId: driver.id,
        title: 'Add high-pass filter for ${driver.name}',
        description:
            'No HPF configured. Draft suggestion: LR24 at ${hpfHz.toStringAsFixed(0)} Hz.',
        reason: 'Woofer channels benefit from high-pass protection.',
        proposedCrossoverHz: hpfHz,
      ));
    }
  }

  // Gain trim suggestions for channels above threshold
  if (doGain) {
    for (final ctrl in tuningState.channelControls) {
      if (ctrl.gainDb <= 6.0) { continue; }
      suggestions.add(OptimizerSuggestion(
        id: nextId(),
        type: OptimizerSuggestionType.adjustGain,
        confidence: OptimizerConfidence.high,
        channelId: ctrl.channelId,
        title: 'Reduce output gain on channel ${ctrl.channelId}',
        description: 'Current gain is +${ctrl.gainDb.toStringAsFixed(1)} dB. '
            'Suggest reducing to +${(ctrl.gainDb - 2.0).toStringAsFixed(1)} dB.',
        reason: 'Output gain above +6 dB reduces headroom.',
        proposedGainDb: ctrl.gainDb - 2.0,
      ));
    }
  }

  return _buildResult(config, suggestions, seq);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

double _placeholderFreq(DriverRole role) => switch (role) {
  DriverRole.woofer          => 120.0,
  DriverRole.coaxWoofer      => 120.0,
  DriverRole.subwoofer       => 60.0,
  DriverRole.midrange        => 800.0,
  DriverRole.tweeter         => 3500.0,
  DriverRole.coaxTweeter     => 3500.0,
  DriverRole.fullrange       => 1000.0,
  DriverRole.passiveRadiator => 100.0,
  DriverRole.unknown         => 1000.0,
};

double _placeholderGain(OptimizerMode mode) => switch (mode) {
  OptimizerMode.conservative => 1.5,
  OptimizerMode.balanced     => 2.5,
  OptimizerMode.aggressive   => 3.5,
  OptimizerMode.manualReview => 0.0,
};

double _hpfPlaceholder(OptimizerMode mode) => switch (mode) {
  OptimizerMode.conservative => 40.0,
  OptimizerMode.balanced     => 50.0,
  OptimizerMode.aggressive   => 60.0,
  OptimizerMode.manualReview => 35.0,
};

OptimizerRunResult _buildResult(
    OptimizerRunConfig config, List<OptimizerSuggestion> suggestions, int seq) {
  final warnings = suggestions
      .where((s) => s.type == OptimizerSuggestionType.warningOnly)
      .length;
  final actionable = suggestions.length - warnings;
  final summary = actionable > 0
      ? '$actionable actionable suggestion(s) generated. $warnings warning(s).'
      : warnings > 0
          ? 'No actionable suggestions. $warnings warning(s).'
          : 'No suggestions generated.';

  return OptimizerRunResult(
    id: 'run_${DateTime.now().millisecondsSinceEpoch}',
    config: config,
    suggestions: suggestions,
    summary: summary,
    warningCount: warnings,
  );
}
