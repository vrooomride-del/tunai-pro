import 'dart:math' as math;

import '../adau1701_peq_response.dart' show PeqResponseBand;
import '../pro_acoustic_data.dart';
import '../pro_project.dart';
import '../pro_response_error.dart';
import '../pro_simulation_optimizer.dart';
import '../pro_tuning_data.dart';
import 'candidate_optimizer.dart';
import 'candidate_safety.dart';

enum FullSystemSummationMode { phaseAware, magnitudeOnly }

class FullSystemCandidateEvaluation {
  final bool accepted;
  final FullSystemSummationMode mode;
  final double beforeWeightedRmsDb;
  final double afterWeightedRmsDb;
  final Map<String, List<SelectedCandidate>> selectedByChannel;
  final int combinationsEvaluated;

  const FullSystemCandidateEvaluation({
    required this.accepted,
    required this.mode,
    required this.beforeWeightedRmsDb,
    required this.afterWeightedRmsDb,
    required this.selectedByChannel,
    required this.combinationsEvaluated,
  });
}

class FullSystemResponseMeasurement {
  final FullSystemSummationMode mode;
  final double weightedRmsDb;

  const FullSystemResponseMeasurement({
    required this.mode,
    required this.weightedRmsDb,
  });
}

abstract final class FullSystemCandidateEvaluator {
  static const requiredChannelIds = [
    'ch_tw_l',
    'ch_wf_l',
    'ch_tw_r',
    'ch_wf_r',
  ];
  static const maxCandidatesPerChannel = 3;

  static FullSystemResponseMeasurement? measure({
    required ProProject project,
    TuningProjectState? tuning,
    double? minFrequencyHz,
    double? maxFrequencyHz,
  }) {
    final drivers = <String, DriverChannel>{
      for (final driver in project.acousticState.driverChannels)
        if (requiredChannelIds.contains(driver.id) && driver.hasParsedFrd)
          driver.id: driver,
    };
    if (!requiredChannelIds.every(drivers.containsKey)) return null;
    final mode = requiredChannelIds
            .every((channelId) => drivers[channelId]!.frdData!.hasPhase)
        ? FullSystemSummationMode.phaseAware
        : FullSystemSummationMode.magnitudeOnly;
    final freqs = _commonFrequencyGrid(drivers.values)
        .where((frequency) =>
            (minFrequencyHz == null || frequency >= minFrequencyHz) &&
            (maxFrequencyHz == null || frequency <= maxFrequencyHz))
        .toList();
    if (freqs.length < 2) return null;
    final effectiveProject =
        tuning == null ? project : project.copyWith(tuningState: tuning);
    final curve = _summedResponse(
      project: effectiveProject,
      drivers: drivers,
      freqs: freqs,
      mode: mode,
      selectedByChannel: const {},
    );
    final error = ProResponseError.analyze(
      freqs: freqs,
      responseDb: curve,
      targetDb: List<double>.filled(freqs.length, 0),
      weights: ProResponseError.defaultWeights(freqs),
    );
    return FullSystemResponseMeasurement(
      mode: mode,
      weightedRmsDb: error.weightedRmsDb,
    );
  }

  static FullSystemCandidateEvaluation evaluate({
    required ProProject project,
    required Map<String, CandidateSafetyResult> safetyByChannel,
  }) {
    final drivers = <String, DriverChannel>{
      for (final driver in project.acousticState.driverChannels)
        if (requiredChannelIds.contains(driver.id) && driver.hasParsedFrd)
          driver.id: driver,
    };
    if (!requiredChannelIds.every(drivers.containsKey)) {
      return const FullSystemCandidateEvaluation(
        accepted: false,
        mode: FullSystemSummationMode.magnitudeOnly,
        beforeWeightedRmsDb: double.infinity,
        afterWeightedRmsDb: double.infinity,
        selectedByChannel: {},
        combinationsEvaluated: 0,
      );
    }

    final mode = requiredChannelIds
            .every((channelId) => drivers[channelId]!.frdData!.hasPhase)
        ? FullSystemSummationMode.phaseAware
        : FullSystemSummationMode.magnitudeOnly;
    final freqs = _commonFrequencyGrid(drivers.values);
    if (freqs.length < 2) {
      return FullSystemCandidateEvaluation(
        accepted: false,
        mode: mode,
        beforeWeightedRmsDb: double.infinity,
        afterWeightedRmsDb: double.infinity,
        selectedByChannel: const {},
        combinationsEvaluated: 0,
      );
    }

    final beforeCurve = _summedResponse(
      project: project,
      drivers: drivers,
      freqs: freqs,
      mode: mode,
      selectedByChannel: const {},
    );
    final target = List<double>.filled(freqs.length, 0);
    final weights = ProResponseError.defaultWeights(freqs);
    final before = ProResponseError.analyze(
      freqs: freqs,
      responseDb: beforeCurve,
      targetDb: target,
      weights: weights,
    );

    final options = <String, List<SelectedCandidate?>>{
      for (final channelId in requiredChannelIds)
        channelId: [
          null,
          ...?safetyByChannel[channelId]
              ?.verifiedCandidates
              .take(maxCandidatesPerChannel),
        ],
    };
    Map<String, List<SelectedCandidate>> best = const {};
    var bestRms = double.infinity;
    var evaluated = 0;

    void search(int index, Map<String, List<SelectedCandidate>> current) {
      if (index == requiredChannelIds.length) {
        if (current.values.every((selected) => selected.isEmpty)) return;
        evaluated++;
        final curve = _summedResponse(
          project: project,
          drivers: drivers,
          freqs: freqs,
          mode: mode,
          selectedByChannel: current,
        );
        final error = ProResponseError.analyze(
          freqs: freqs,
          responseDb: curve,
          targetDb: target,
          weights: weights,
        );
        if (error.weightedRmsDb < bestRms) {
          bestRms = error.weightedRmsDb;
          best = {
            for (final entry in current.entries)
              entry.key: List<SelectedCandidate>.unmodifiable(entry.value),
          };
        }
        return;
      }
      final channelId = requiredChannelIds[index];
      for (final candidate in options[channelId]!) {
        current[channelId] = candidate == null ? const [] : [candidate];
        search(index + 1, current);
      }
    }

    search(0, {});
    const minimumImprovementDb = 0.01;
    final accepted = bestRms <= before.weightedRmsDb - minimumImprovementDb;
    return FullSystemCandidateEvaluation(
      accepted: accepted,
      mode: mode,
      beforeWeightedRmsDb: before.weightedRmsDb,
      afterWeightedRmsDb: bestRms,
      selectedByChannel: accepted ? best : const {},
      combinationsEvaluated: evaluated,
    );
  }

  static List<double> _commonFrequencyGrid(Iterable<DriverChannel> drivers) {
    final list = drivers.toList();
    final minHz =
        list.map((driver) => driver.frdData!.minFrequencyHz).reduce(math.max);
    final maxHz =
        list.map((driver) => driver.frdData!.maxFrequencyHz).reduce(math.min);
    return list.first.frdData!.points
        .where((point) =>
            point.magnitudeDb != null &&
            point.frequencyHz >= minHz &&
            point.frequencyHz <= maxHz)
        .map((point) => point.frequencyHz)
        .toList();
  }

  static List<double> _summedResponse({
    required ProProject project,
    required Map<String, DriverChannel> drivers,
    required List<double> freqs,
    required FullSystemSummationMode mode,
    required Map<String, List<SelectedCandidate>> selectedByChannel,
  }) {
    final channelResponses = <String, List<double>>{};
    for (final channelId in requiredChannelIds) {
      final existing = project.tuningState.peqChannels
          .where((channel) => channel.channelId == channelId)
          .firstOrNull;
      final bands = <PeqResponseBand>[
        for (final band in existing?.bands ?? const [])
          if (band.enabled && band.status != PeqBandStatus.bypassed)
            PeqResponseBand(
              frequencyHz: band.frequencyHz,
              gainDb: band.gainDb,
              q: band.q,
            ),
        for (final selected in selectedByChannel[channelId] ?? const [])
          PeqResponseBand(
            frequencyHz: selected.scoredCandidate.candidate.frequencyHz,
            gainDb: selected.scoredCandidate.candidate.gainDb,
            q: selected.scoredCandidate.candidate.q,
          ),
      ];
      final response = ProSimulationOptimizer.simulatedResponse(
        driver: drivers[channelId]!,
        bands: bands,
        freqs: freqs,
      );
      final gainDb = _channelGainDb(project.tuningState, channelId);
      channelResponses[channelId] = [
        for (var i = 0; i < freqs.length; i++)
          response[i] +
              gainDb +
              _xoAttenuationDb(project.tuningState, channelId, freqs[i]),
      ];
    }

    return [
      for (var i = 0; i < freqs.length; i++)
        mode == FullSystemSummationMode.phaseAware
            ? _phaseAwareAt(project, drivers, channelResponses, freqs[i], i)
            : _magnitudeOnlyAt(channelResponses, i),
    ];
  }

  static double _magnitudeOnlyAt(Map<String, List<double>> responses, int i) {
    var power = 0.0;
    for (final response in responses.values) {
      power += math.pow(10, response[i] / 10).toDouble();
    }
    return power > 1e-12 ? 10 * math.log(power) / math.ln10 : -120;
  }

  static double _phaseAwareAt(
    ProProject project,
    Map<String, DriverChannel> drivers,
    Map<String, List<double>> responses,
    double frequencyHz,
    int index,
  ) {
    var real = 0.0;
    var imaginary = 0.0;
    for (final channelId in requiredChannelIds) {
      var phase =
          _interpolatePhase(drivers[channelId]!.frdData!.points, frequencyHz);
      final xo = project.tuningState.crossoverChannels
          .where((channel) => channel.channelId == channelId)
          .firstOrNull;
      if (xo?.polarityInverted == true) phase += 180;
      final control = project.tuningState.channelControls
          .where((channel) => channel.channelId == channelId)
          .firstOrNull;
      phase -= 360 * frequencyHz * ((control?.delayMs ?? 0) / 1000);
      final offset = drivers[channelId]!.acousticOffset;
      if (offset != null) {
        phase -= 360 * frequencyHz * offset.pathDelaySeconds;
      }
      final linear = math.pow(10, responses[channelId]![index] / 20).toDouble();
      final radians = phase * math.pi / 180;
      real += linear * math.cos(radians);
      imaginary += linear * math.sin(radians);
    }
    final magnitude = math.sqrt(real * real + imaginary * imaginary);
    return magnitude > 1e-12 ? 20 * math.log(magnitude) / math.ln10 : -120;
  }

  static double _channelGainDb(TuningProjectState tuning, String channelId) {
    final control = tuning.channelControls
        .where((channel) => channel.channelId == channelId)
        .firstOrNull;
    return control?.hasGainTrim == true ? control!.gainDb : 0;
  }

  static double _xoAttenuationDb(
      TuningProjectState tuning, String channelId, double frequencyHz) {
    final xo = tuning.crossoverChannels
        .where((channel) => channel.channelId == channelId)
        .firstOrNull;
    if (xo == null || xo.bypassed) return 0;
    var attenuation = 0.0;
    if (xo.hasHighPass && frequencyHz < xo.highPass!.frequencyHz) {
      attenuation -= _slopeDb(xo.highPass!.slope) *
          (math.log(xo.highPass!.frequencyHz / frequencyHz) / math.ln2);
    }
    if (xo.hasLowPass && frequencyHz > xo.lowPass!.frequencyHz) {
      attenuation -= _slopeDb(xo.lowPass!.slope) *
          (math.log(frequencyHz / xo.lowPass!.frequencyHz) / math.ln2);
    }
    return attenuation;
  }

  static double _slopeDb(CrossoverSlope slope) => switch (slope) {
        CrossoverSlope.db12 => 12,
        CrossoverSlope.db24 => 24,
        CrossoverSlope.db36 => 36,
        CrossoverSlope.db48 => 48,
      };

  static double _interpolatePhase(
      List<MeasurementDataPoint> points, double frequencyHz) {
    final valid = points.where((point) => point.phaseDeg != null).toList();
    if (valid.isEmpty) return 0;
    if (frequencyHz <= valid.first.frequencyHz) return valid.first.phaseDeg!;
    if (frequencyHz >= valid.last.frequencyHz) return valid.last.phaseDeg!;
    for (var i = 0; i < valid.length - 1; i++) {
      final a = valid[i];
      final b = valid[i + 1];
      if (frequencyHz <= b.frequencyHz) {
        final t = (math.log(frequencyHz) - math.log(a.frequencyHz)) /
            (math.log(b.frequencyHz) - math.log(a.frequencyHz));
        return a.phaseDeg! + (b.phaseDeg! - a.phaseDeg!) * t;
      }
    }
    return valid.last.phaseDeg!;
  }
}
