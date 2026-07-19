// ── Optimizer Tab — Phase G ───────────────────────────────────────────────────
// Draft suggestion engine. Accept / Reject / Lock. No DSP write.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_tuning_data.dart';
import '../../../core/pro_optimizer_data.dart';
import '../../../core/pro_optimizer_engine.dart';
import '../../../core/pro_simulation_optimizer.dart';
import '../../../core/pro_target_curve.dart';
import '../../../core/adau1701_peq_response.dart';
import '../../../shared/pro_widgets.dart';
import '../widgets/optimizer_preview_graph.dart';

class OptimizerTab extends ConsumerStatefulWidget {
  final String projectId;
  const OptimizerTab({super.key, required this.projectId});

  @override
  ConsumerState<OptimizerTab> createState() => _OptimizerTabState();
}

class _OptimizerTabState extends ConsumerState<OptimizerTab> {
  OptimizerRunConfig _config = const OptimizerRunConfig();
  bool _running = false;

  ProProject? get _project => ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == widget.projectId)
      .firstOrNull;

  Future<void> _runOptimizer() async {
    final project = _project;
    if (project == null) return;
    setState(() => _running = true);

    await Future.delayed(const Duration(milliseconds: 120));

    final result = runDraftOptimizer(
      acousticState: project.acousticState,
      tuningState: project.tuningState,
      protectionState: project.protectionState,
      config: _config,
    );

    final current = project.optimizerState;
    final updated = current.copyWith(
      runs: [...current.runs, result],
      activeRunId: result.id,
    );

    await ref
        .read(proProjectStoreProvider.notifier)
        .updateOptimizerState(widget.projectId, updated);

    if (mounted) setState(() => _running = false);
  }

  Future<void> _updateSuggestion(
      String runId, String suggestionId, OptimizerSuggestionStatus newStatus) async {
    final project = _project;
    if (project == null) return;
    final optimizer = project.optimizerState;

    final updatedRuns = optimizer.runs.map((run) {
      if (run.id != runId) return run;
      return run.copyWith(
        suggestions: run.suggestions.map((s) {
          if (s.id != suggestionId) return s;
          return s.copyWith(status: newStatus);
        }).toList(),
      );
    }).toList();

    // Accept: apply tuning change
    if (newStatus == OptimizerSuggestionStatus.accepted) {
      final run = optimizer.runs.firstWhere((r) => r.id == runId);
      final sug = run.suggestions.firstWhere((s) => s.id == suggestionId);
      await _applyAcceptedSuggestion(project, sug);
    }

    await ref
        .read(proProjectStoreProvider.notifier)
        .updateOptimizerState(
          widget.projectId,
          optimizer.copyWith(runs: updatedRuns),
        );
  }

  Future<void> _applyAcceptedSuggestion(
      ProProject project, OptimizerSuggestion sug) async {
    var tuning = project.tuningState;

    switch (sug.type) {
      case OptimizerSuggestionType.addPeqBand:
        if (sug.channelId != null &&
            sug.proposedFrequencyHz != null &&
            sug.proposedGainDb != null &&
            sug.proposedQ != null) {
          final chId = sug.channelId!;
          final existing = tuning.peqChannels.firstWhere(
            (c) => c.channelId == chId,
            orElse: () => PeqChannelState.fixed(chId),
          );
          // Fixed 10-slot model: fill the next free slot instead of appending a
          // new band, so the DSP's fixed PEQ slot count is never exceeded.
          final updatedCh = existing.fillNextFreeSlot(
            type: PeqBandType.peak,
            frequencyHz: sug.proposedFrequencyHz!,
            gainDb: sug.proposedGainDb!,
            q: sug.proposedQ!,
          );
          final hasEntry = tuning.peqChannels.any((c) => c.channelId == chId);
          final updatedChannels = hasEntry
              ? tuning.peqChannels.map((c) => c.channelId == chId ? updatedCh : c).toList()
              : [...tuning.peqChannels, updatedCh];
          tuning = tuning.copyWith(peqChannels: updatedChannels, hasManualChanges: true,
              tuningRevision: tuning.tuningRevision + 1);
        }
      case OptimizerSuggestionType.addHighPass:
        if (sug.channelId != null && sug.proposedCrossoverHz != null) {
          final xoCh = tuning.getOrCreateCrossoverChannel(sug.channelId!);
          final updated = xoCh.copyWith(
            highPass: CrossoverFilter(
              frequencyHz: sug.proposedCrossoverHz!,
              side: FilterSide.highPass,
              type: CrossoverFilterType.linkwitzRiley,
              enabled: true,
            ),
          );
          tuning = tuning.replaceCrossoverChannel(updated);
        }
      case OptimizerSuggestionType.adjustGain:
        if (sug.channelId != null && sug.proposedGainDb != null) {
          final ctrl = tuning.getOrCreateControl(sug.channelId!);
          tuning = tuning.replaceControl(
              ctrl.copyWith(gainDb: sug.proposedGainDb!));
        }
      case OptimizerSuggestionType.warningOnly:
        break;
      default:
        break;
    }

    await ref
        .read(proProjectStoreProvider.notifier)
        .updateTuningState(widget.projectId, tuning);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;
    final optimizer = project?.optimizerState ?? OptimizerProjectState.createDefault();
    final activeRun = optimizer.activeRun;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.auto_awesome_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Draft Optimizer', style: proTitle(size: 16)),
          const Spacer(),
          if (optimizer.runs.isNotEmpty)
            Text('${optimizer.runs.length} run(s)',
                style: proLabel(size: 9, color: Colors.white38, spacing: 0.5)),
        ]),
        const SizedBox(height: 4),
        Text('AI suggests draft corrections. Expert reviews and accepts each one.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        // Config panel
        _ConfigPanel(
          config: _config,
          onChanged: (c) => setState(() => _config = c),
        ),
        const SizedBox(height: 16),

        // Run button
        GestureDetector(
          onTap: _running ? null : _runOptimizer,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: _running
                  ? kProSurface
                  : kProAccent.withValues(alpha: 0.08),
              border: Border.all(
                  color: _running
                      ? kProBorder
                      : kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _running ? Icons.hourglass_empty_outlined : Icons.play_arrow_outlined,
                color: _running ? Colors.white24 : kProAccent,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                _running ? 'Running...' : 'Run Draft Optimizer',
                style: TextStyle(
                    color: _running ? Colors.white24 : kProAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        // Active run summary
        if (activeRun != null) ...[
          _RunSummary(
              run: activeRun,
              optimizer: optimizer,
              scores:
                  project == null ? null : _projectScores(project, activeRun)),
          const SizedBox(height: 12),

          // Before/After response preview
          Builder(builder: (_) {
            final curves =
                project == null ? null : _buildPreviewCurves(project, activeRun);
            if (curves == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: OptimizerPreviewGraph(
                freqs: curves.freqs,
                target: curves.target,
                before: curves.before,
                after: curves.after,
              ),
            );
          }),
          const SizedBox(height: 16),

          // Suggestion list
          if (activeRun.suggestions.isNotEmpty) ...[
            Text('SUGGESTIONS (${activeRun.suggestions.length})',
                style: proLabel(size: 9, spacing: 2)),
            const SizedBox(height: 8),
            ...activeRun.suggestions.map((sug) => _SuggestionCard(
                  suggestion: sug,
                  runId: activeRun.id,
                  onAccept: () => _updateSuggestion(
                      activeRun.id, sug.id, OptimizerSuggestionStatus.accepted),
                  onReject: () => _updateSuggestion(
                      activeRun.id, sug.id, OptimizerSuggestionStatus.rejected),
                  onLock: () => _updateSuggestion(
                      activeRun.id, sug.id, OptimizerSuggestionStatus.locked),
                )),
          ] else
            Text('No suggestions generated.', style: proSubtitle()),
        ] else
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Colors.white24, size: 13),
              const SizedBox(width: 10),
              Text('Run the optimizer to generate draft suggestions.',
                  style: proSubtitle()),
            ]),
          ),
      ]),
    );
  }
}

// ── Config Panel ──────────────────────────────────────────────────────────────

class _ConfigPanel extends StatelessWidget {
  final OptimizerRunConfig config;
  final ValueChanged<OptimizerRunConfig> onChanged;
  const _ConfigPanel({required this.config, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('OPTIMIZER CONFIG', style: proLabel(size: 9, spacing: 2)),
      const SizedBox(height: 12),

      // Mode
      Row(children: [
        SizedBox(width: 110, child: Text('Mode', style: proSubtitle())),
        ...OptimizerMode.values.map((m) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => onChanged(config.copyWith(mode: m)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: config.mode == m
                    ? kProAccent.withValues(alpha: 0.12)
                    : Colors.transparent,
                border: Border.all(
                    color: config.mode == m
                        ? kProAccent.withValues(alpha: 0.5)
                        : kProBorder),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(m.label,
                  style: TextStyle(
                      color: config.mode == m ? kProAccent : Colors.white38,
                      fontSize: 10)),
            ),
          ),
        )),
      ]),
      const SizedBox(height: 10),

      // Scope
      Row(children: [
        SizedBox(width: 110, child: Text('Scope', style: proSubtitle())),
        ...OptimizerScope.values.map((s) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => onChanged(config.copyWith(scope: s)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: config.scope == s
                    ? kProAccent.withValues(alpha: 0.12)
                    : Colors.transparent,
                border: Border.all(
                    color: config.scope == s
                        ? kProAccent.withValues(alpha: 0.5)
                        : kProBorder),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(s.label,
                  style: TextStyle(
                      color: config.scope == s ? kProAccent : Colors.white38,
                      fontSize: 10)),
            ),
          ),
        )),
      ]),
      const SizedBox(height: 10),

      // Max bands / boost / cut
      Wrap(spacing: 16, runSpacing: 8, children: [
        _ConfigValue(
          label: 'Max bands/ch',
          value: '${config.maxPeqBandsPerChannel}',
          onDec: config.maxPeqBandsPerChannel > 1
              ? () => onChanged(config.copyWith(
                  maxPeqBandsPerChannel: config.maxPeqBandsPerChannel - 1))
              : null,
          onInc: config.maxPeqBandsPerChannel < 16
              ? () => onChanged(config.copyWith(
                  maxPeqBandsPerChannel: config.maxPeqBandsPerChannel + 1))
              : null,
        ),
        _ConfigValue(
          label: 'Max boost dB',
          value: '+${config.maxBoostDb.toStringAsFixed(0)}',
          onDec: config.maxBoostDb > 1
              ? () => onChanged(config.copyWith(maxBoostDb: config.maxBoostDb - 1))
              : null,
          onInc: config.maxBoostDb < 12
              ? () => onChanged(config.copyWith(maxBoostDb: config.maxBoostDb + 1))
              : null,
        ),
        _ConfigValue(
          label: 'Max cut dB',
          value: '−${config.maxCutDb.toStringAsFixed(0)}',
          onDec: config.maxCutDb > 3
              ? () => onChanged(config.copyWith(maxCutDb: config.maxCutDb - 1))
              : null,
          onInc: config.maxCutDb < 24
              ? () => onChanged(config.copyWith(maxCutDb: config.maxCutDb + 1))
              : null,
        ),
      ]),
    ]),
  );
}

class _ConfigValue extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onDec;
  final VoidCallback? onInc;
  const _ConfigValue(
      {required this.label, required this.value, this.onDec, this.onInc});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: proLabel(size: 9, spacing: 0.5)),
      const SizedBox(height: 4),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _SmallBtn('−', onDec),
        Container(
          width: 44,
          alignment: Alignment.center,
          child: Text(value, style: proValue(size: 11)),
        ),
        _SmallBtn('+', onInc),
      ]),
    ],
  );
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _SmallBtn(this.label, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: onTap != null ? kProBorder : Colors.white10),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: TextStyle(
              color: onTap != null ? Colors.white60 : Colors.white24,
              fontSize: 13)),
    ),
  );
}

// ── Score projection (UI/reporting only) ─────────────────────────────────────
// Recomputes the aggregate before/after target-match scores from current
// project state via the deterministic ProSimulationOptimizer. Read-only: it
// does not alter the engine, the run, or the suggestion lifecycle.

class _ScoreProjection {
  final double before;
  final double after;
  final OptimizerConfidence? confidence;
  const _ScoreProjection(
      {required this.before, required this.after, this.confidence});

  double get delta => after - before;
  bool get hasData => before != after || confidence != null;
}

_ScoreProjection? _projectScores(ProProject project, OptimizerRunResult run) {
  // Scores are meaningful only when PEQ was in the run's scope.
  final scope = run.config.scope;
  final peqInScope =
      scope == OptimizerScope.peq || scope == OptimizerScope.fullSystem;
  if (!peqInScope) return null;

  final drivers = project.acousticState.driverChannels;
  if (drivers.isEmpty) return null;

  var sumBefore = 0.0;
  var sumAfter = 0.0;
  var n = 0;
  for (final driver in drivers) {
    final currentPeq = project.tuningState.peqChannels.firstWhere(
        (c) => c.channelId == driver.id,
        orElse: () => PeqChannelState.empty(driver.id));
    final result = ProSimulationOptimizer.optimizeDriver(
      driver: driver,
      currentPeq: currentPeq,
      target: project.acousticState.targetCurve.selectedPreset,
      config: run.config,
      nextId: () => 'proj',
    );
    sumBefore += result.before.score;
    sumAfter += result.after.score;
    n++;
  }
  if (n == 0) return null;

  // Overall confidence = the weakest confidence among this run's PEQ
  // suggestions (matches what the suggestion cards report).
  OptimizerConfidence? confidence;
  for (final s in run.suggestions) {
    if (s.type != OptimizerSuggestionType.addPeqBand) continue;
    if (confidence == null || s.confidence.index < confidence.index) {
      confidence = s.confidence;
    }
  }

  return _ScoreProjection(
    before: sumBefore / n,
    after: sumAfter / n,
    confidence: confidence,
  );
}

// ── Before/After preview curves (UI/reporting only) ──────────────────────────
// Builds three magnitude curves for the preview graph, reusing ProTargetCurve
// and ProSimulationOptimizer. Read-only: no optimization or lifecycle change.

class _PreviewCurves {
  final List<double> freqs;
  final List<double> target;
  final List<double> before;
  final List<double> after;
  const _PreviewCurves(
      {required this.freqs,
      required this.target,
      required this.before,
      required this.after});
}

_PreviewCurves? _buildPreviewCurves(ProProject project, OptimizerRunResult run) {
  final scope = run.config.scope;
  final peqInScope =
      scope == OptimizerScope.peq || scope == OptimizerScope.fullSystem;
  if (!peqInScope) return null;

  final drivers = project.acousticState.driverChannels;
  if (drivers.isEmpty) return null;

  final freqs = ProSimulationOptimizer.previewFrequencies();
  final target =
      ProTargetCurve.curve(project.acousticState.targetCurve.selectedPreset, freqs);

  final beforeSum = List<double>.filled(freqs.length, 0.0);
  final afterSum = List<double>.filled(freqs.length, 0.0);
  var n = 0;

  for (final driver in drivers) {
    final currentPeq = project.tuningState.peqChannels.firstWhere(
        (c) => c.channelId == driver.id,
        orElse: () => PeqChannelState.empty(driver.id));

    final currentBands = <PeqResponseBand>[
      for (final b in currentPeq.bands)
        if (b.enabled)
          PeqResponseBand(frequencyHz: b.frequencyHz, gainDb: b.gainDb, q: b.q),
    ];

    final result = ProSimulationOptimizer.optimizeDriver(
      driver: driver,
      currentPeq: currentPeq,
      target: project.acousticState.targetCurve.selectedPreset,
      config: run.config,
      nextId: () => 'preview',
    );
    final proposedBands = <PeqResponseBand>[
      for (final s in result.suggestions)
        if (s.type == OptimizerSuggestionType.addPeqBand &&
            s.proposedFrequencyHz != null &&
            s.proposedGainDb != null)
          PeqResponseBand(
              frequencyHz: s.proposedFrequencyHz!,
              gainDb: s.proposedGainDb!,
              q: s.proposedQ ?? 1.0),
    ];

    final before = ProSimulationOptimizer.simulatedResponse(
        driver: driver, bands: currentBands, freqs: freqs);
    final after = ProSimulationOptimizer.simulatedResponse(
        driver: driver, bands: [...currentBands, ...proposedBands], freqs: freqs);

    for (var i = 0; i < freqs.length; i++) {
      beforeSum[i] += before[i];
      afterSum[i] += after[i];
    }
    n++;
  }
  if (n == 0) return null;

  return _PreviewCurves(
    freqs: freqs,
    target: target,
    before: [for (final v in beforeSum) v / n],
    after: [for (final v in afterSum) v / n],
  );
}

// ── Run Summary ───────────────────────────────────────────────────────────────

class _RunSummary extends StatelessWidget {
  final OptimizerRunResult run;
  final OptimizerProjectState optimizer;
  final _ScoreProjection? scores;
  const _RunSummary(
      {required this.run, required this.optimizer, this.scores});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ACTIVE RUN', style: proLabel(size: 9, spacing: 2)),
      const SizedBox(height: 8),
      Text(run.summary, style: proSubtitle(size: 10)),
      if (scores != null && scores!.hasData) ...[
        const SizedBox(height: 10),
        Text('SIMULATED TARGET MATCH', style: proLabel(size: 8, spacing: 1.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 8, children: [
          _ScoreChip(label: 'BEFORE', value: scores!.before.round().toString()),
          _ScoreChip(
              label: 'AFTER',
              value: scores!.after.round().toString(),
              color: kProGreen),
          _ScoreChip(
              label: 'IMPROVEMENT',
              value:
                  '${scores!.delta >= 0 ? '+' : ''}${scores!.delta.round()}',
              color: scores!.delta > 0.5
                  ? kProGreen
                  : (scores!.delta < -0.5 ? kProAmber : null)),
          if (scores!.confidence != null)
            _ScoreChip(
                label: 'CONFIDENCE',
                value: scores!.confidence!.label.toUpperCase(),
                color: switch (scores!.confidence!) {
                  OptimizerConfidence.high => kProGreen,
                  OptimizerConfidence.medium => kProAmber,
                  OptimizerConfidence.low => null,
                }),
        ]),
        const SizedBox(height: 6),
        Text('Simulation projection (electrical + measured magnitude). '
            'Not a measured verification.',
            style: proSubtitle(size: 9, color: Colors.white30)),
      ],
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _SmallChip(label: 'TOTAL', value: '${optimizer.totalSuggestionCount}'),
        _SmallChip(label: 'PENDING',
            value: '${optimizer.pendingSuggestionCount}',
            color: optimizer.pendingSuggestionCount > 0 ? kProAmber : null),
        _SmallChip(label: 'ACCEPTED',
            value: '${optimizer.acceptedSuggestionCount}',
            color: optimizer.acceptedSuggestionCount > 0 ? kProGreen : null),
        _SmallChip(label: 'REJECTED',
            value: '${optimizer.rejectedSuggestionCount}'),
        _SmallChip(label: 'LOCKED',
            value: '${optimizer.lockedSuggestionCount}'),
      ]),
    ]),
  );
}

class _SmallChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SmallChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: kProBg,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 8, spacing: 1)),
      const SizedBox(height: 2),
      Text(value, style: proValue(size: 11, color: color ?? Colors.white54)),
    ]),
  );
}

class _ScoreChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _ScoreChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: kProBg,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 8, spacing: 1)),
      const SizedBox(height: 3),
      Text(value, style: proValue(size: 15, color: color ?? Colors.white70)),
    ]),
  );
}

// ── Suggestion Card ───────────────────────────────────────────────────────────

class _SuggestionCard extends StatelessWidget {
  final OptimizerSuggestion suggestion;
  final String runId;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onLock;
  const _SuggestionCard({
    required this.suggestion,
    required this.runId,
    required this.onAccept,
    required this.onReject,
    required this.onLock,
  });

  Color _confidenceColor() => switch (suggestion.confidence) {
    OptimizerConfidence.high   => kProGreen,
    OptimizerConfidence.medium => kProAmber,
    OptimizerConfidence.low    => Colors.white38,
  };

  Color _statusColor() => switch (suggestion.status) {
    OptimizerSuggestionStatus.accepted => kProGreen,
    OptimizerSuggestionStatus.rejected => kProRed,
    OptimizerSuggestionStatus.locked   => kProAccent,
    OptimizerSuggestionStatus.pending  => Colors.white24,
  };

  @override
  Widget build(BuildContext context) {
    final isWarning = suggestion.type == OptimizerSuggestionType.warningOnly;
    final isPending = suggestion.status == OptimizerSuggestionStatus.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(
            color: suggestion.status == OptimizerSuggestionStatus.accepted
                ? kProGreen.withValues(alpha: 0.3)
                : kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Text(suggestion.type.label,
                  style: proLabel(size: 9, spacing: 0.5, color: Colors.white54)),
              const SizedBox(width: 8),
              ProStatusPill(
                  label: suggestion.confidence.label,
                  color: _confidenceColor()),
              if (suggestion.channelId != null) ...[
                const SizedBox(width: 6),
                Text('ch: ${suggestion.channelId}',
                    style: proLabel(size: 8, color: Colors.white24, spacing: 0.3)),
              ],
            ]),
          ),
          ProStatusPill(
              label: suggestion.status.label, color: _statusColor()),
        ]),
        const SizedBox(height: 6),
        Text(suggestion.title,
            style: proTitle(size: 11,
                color: isWarning ? kProAmber : Colors.white)),
        const SizedBox(height: 3),
        Text(suggestion.description, style: proSubtitle(size: 10)),
        const SizedBox(height: 3),
        Text('Why: ${suggestion.reason}',
            style: proSubtitle(size: 9, color: Colors.white24)),

        // Action buttons (pending only, non-warning)
        if (isPending && !isWarning) ...[
          const SizedBox(height: 10),
          Row(children: [
            _ActionBtn(label: 'Accept', color: kProGreen, onTap: onAccept),
            const SizedBox(width: 8),
            _ActionBtn(label: 'Reject', color: kProRed, onTap: onReject),
            const SizedBox(width: 8),
            _ActionBtn(label: 'Lock', color: kProAccent, onTap: onLock),
          ]),
        ] else if (isPending && isWarning) ...[
          const SizedBox(height: 10),
          Row(children: [
            _ActionBtn(label: 'Dismiss', color: kProRed, onTap: onReject),
          ]),
        ],
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500)),
    ),
  );
}
