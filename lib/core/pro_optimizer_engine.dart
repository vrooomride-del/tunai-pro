// ── TUNAI PRO Phase G — Draft Optimizer Engine ────────────────────────────────
// Transparent rule-based draft suggestions only. No tuning is modified here.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_acoustic_data.dart';
import 'pro_tuning_data.dart';
import 'pro_protection_data.dart';
import 'pro_optimizer_data.dart';
import 'pro_simulation_optimizer.dart';

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

  // PEQ suggestions per channel — error-driven simulation optimizer.
  // (Falls back to a role-based placeholder only if the optimizer engine
  // yields nothing, e.g. an exhausted band budget on an unmeasured channel.)
  if (doPeq) {
    for (final driver in acousticState.driverChannels) {
      final currentPeq = tuningState.peqChannels.firstWhere(
          (c) => c.channelId == driver.id,
          orElse: () => PeqChannelState.empty(driver.id));

      final result = ProSimulationOptimizer.optimizeDriver(
        driver: driver,
        currentPeq: currentPeq,
        target: acousticState.targetCurve.selectedPreset,
        config: config,
        nextId: nextId,
      );
      suggestions.addAll(result.suggestions);
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
