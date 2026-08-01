import '../pro_project.dart';
import '../pro_tuning_data.dart';
import 'full_system_candidate_evaluator.dart';

class FullSystemAlignmentEvaluation {
  final bool accepted;
  final FullSystemSummationMode mode;
  final double beforeWeightedRmsDb;
  final double afterWeightedRmsDb;
  final TuningProjectState tuning;
  final List<String> channelIds;
  final int combinationsEvaluated;

  const FullSystemAlignmentEvaluation({
    required this.accepted,
    required this.mode,
    required this.beforeWeightedRmsDb,
    required this.afterWeightedRmsDb,
    required this.tuning,
    required this.channelIds,
    required this.combinationsEvaluated,
  });
}

/// Deterministic, bounded XO-region alignment search. No PEQ is added here.
abstract final class FullSystemAlignmentEvaluator {
  static const _minimumImprovementDb = 0.01;
  static const _xoFactors = [0.9, 1.0, 1.1];
  static const _delayOffsetsMs = [0.0, 0.1, 0.2, 0.4];
  // Keep automatic level alignment cut-only; gain recovery/boost remains a
  // manual Expert decision and cannot mask a phase/XO defect.
  static const _gainOffsetsDb = [-1.0, 0.0];
  static const _beamWidth = 8;

  static FullSystemAlignmentEvaluation evaluate({required ProProject project}) {
    final xoFrequencies = project.tuningState.crossoverChannels
        .expand((channel) => [
              if (channel.hasHighPass) channel.highPass!.frequencyHz,
              if (channel.hasLowPass) channel.lowPass!.frequencyHz,
            ])
        .toList();
    final minHz = xoFrequencies.isEmpty
        ? null
        : xoFrequencies.reduce((a, b) => a < b ? a : b) * 0.5;
    final maxHz = xoFrequencies.isEmpty
        ? null
        : xoFrequencies.reduce((a, b) => a > b ? a : b) * 2.0;
    final before = FullSystemCandidateEvaluator.measure(
      project: project,
      minFrequencyHz: minHz,
      maxFrequencyHz: maxHz,
    );
    if (before == null || before.mode != FullSystemSummationMode.phaseAware) {
      return FullSystemAlignmentEvaluation(
        accepted: false,
        mode: before?.mode ?? FullSystemSummationMode.magnitudeOnly,
        beforeWeightedRmsDb: before?.weightedRmsDb ?? double.infinity,
        afterWeightedRmsDb: before?.weightedRmsDb ?? double.infinity,
        tuning: project.tuningState,
        channelIds: const [],
        combinationsEvaluated: 0,
      );
    }

    var beam = <({TuningProjectState tuning, double rms})>[
      (tuning: project.tuningState, rms: before.weightedRmsDb),
    ];
    var evaluated = 0;
    for (final channelId in FullSystemCandidateEvaluator.requiredChannelIds) {
      final expanded = <({TuningProjectState tuning, double rms})>[];
      for (final seed in beam) {
        final baseXo = seed.tuning.getOrCreateCrossoverChannel(channelId);
        final baseControl = seed.tuning.getOrCreateControl(channelId);
        for (final factor in _xoFactors) {
          for (final invert in [
            baseXo.polarityInverted,
            !baseXo.polarityInverted
          ]) {
            for (final delayOffset in _delayOffsetsMs) {
              for (final gainOffset in _gainOffsetsDb) {
                final xo = baseXo.copyWith(
                  polarityInverted: invert,
                  highPass: baseXo.highPass?.copyWith(
                      frequencyHz: baseXo.highPass!.frequencyHz * factor),
                  lowPass: baseXo.lowPass?.copyWith(
                      frequencyHz: baseXo.lowPass!.frequencyHz * factor),
                );
                final control = baseControl.copyWith(
                  delayMs:
                      (baseControl.delayMs + delayOffset).clamp(0.0, 20.0),
                  gainDb: (baseControl.gainDb + gainOffset).clamp(-20.0, 6.0),
                );
                final tuning = seed.tuning
                    .replaceCrossoverChannel(xo)
                    .replaceControl(control);
                final measured = FullSystemCandidateEvaluator.measure(
                  project: project,
                  tuning: tuning,
                  minFrequencyHz: minHz,
                  maxFrequencyHz: maxHz,
                );
                evaluated++;
                if (measured != null) {
                  expanded.add((tuning: tuning, rms: measured.weightedRmsDb));
                }
              }
            }
          }
        }
      }
      expanded.sort((a, b) => a.rms.compareTo(b.rms));
      beam = expanded.take(_beamWidth).toList();
    }
    final bestTuning = beam.first.tuning;
    final bestRms = beam.first.rms;
    final accepted = bestRms <= before.weightedRmsDb - _minimumImprovementDb;
    return FullSystemAlignmentEvaluation(
      accepted: accepted,
      mode: before.mode,
      beforeWeightedRmsDb: before.weightedRmsDb,
      afterWeightedRmsDb: bestRms,
      tuning: accepted ? bestTuning : project.tuningState,
      channelIds: accepted
          ? List.unmodifiable(FullSystemCandidateEvaluator.requiredChannelIds)
          : const [],
      combinationsEvaluated: evaluated,
    );
  }
}
