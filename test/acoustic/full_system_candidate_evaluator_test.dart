import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';
import 'package:tunai_pro/core/acoustic/full_system_candidate_evaluator.dart';
import 'package:tunai_pro/core/acoustic/hybrid_xo_feasibility.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_target_curve.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _ids = ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'];

ProProject _project({
  required double magnitudeDb,
  required bool withPhase,
  bool cancellingPhase = false,
  bool oneInvertedPhase = false,
  double channelGainDb = 0,
}) {
  final now = DateTime(2026, 8, 1);
  return ProProject(
    id: 'p',
    name: 'p',
    createdAt: now,
    updatedAt: now,
    acousticState: MeasurementProjectState(
      driverChannels: [
        for (var i = 0; i < _ids.length; i++)
          DriverChannel(
            id: _ids[i],
            name: _ids[i],
            role: i.isEven ? DriverRole.coaxTweeter : DriverRole.coaxWoofer,
            side: i < 2 ? DriverSide.left : DriverSide.right,
            frdData: ParsedMeasurementData(
              id: 'frd-${_ids[i]}',
              sourceFileName: '${_ids[i]}.frd',
              fileType: AcousticFileType.frd,
              importedAt: now,
              points: [
                for (final frequency in [100.0, 1000.0, 10000.0])
                  MeasurementDataPoint(
                    frequencyHz: frequency,
                    magnitudeDb: magnitudeDb,
                    phaseDeg: withPhase
                        ? ((cancellingPhase && i >= 2) ||
                                (oneInvertedPhase && i == 3)
                            ? 180
                            : 0)
                        : null,
                  ),
              ],
            ),
          ),
      ],
    ),
    tuningState: TuningProjectState(
      channelControls: [
        for (final id in _ids)
          ChannelControlState(channelId: id, gainDb: channelGainDb),
      ],
    ),
  );
}

SelectedCandidate _selected(String channelId, {double gainDb = -6}) {
  final candidate = PeqCandidate(
    candidateId: 'candidate:$channelId',
    featureId: 'peak:$channelId',
    featureType: AcousticFeatureType.narrowPeak,
    channelId: channelId,
    frequencyHz: 1000,
    gainDb: gainDb,
    q: 1,
    intent: CorrectionIntent.cut,
    reason: 'test',
  );
  return SelectedCandidate(
    scoredCandidate: ScoredCandidate(
      candidate: candidate,
      prominenceDb: 6,
      prominenceScore: 40,
      magnitudeConsistencyScore: 30,
      qualityFactor: 1,
      compositeScore: 90,
      rank: 1,
      grade: CandidateScoreGrade.excellent,
      reasons: const [],
    ),
    applicationOrder: 1,
    selectionReason: 'test',
  );
}

Map<String, CandidateSafetyResult> _safety() => {
      for (final id in _ids)
        id: CandidateSafetyResult(
          applyPermitted: true,
          issues: const [],
          verifiedCandidates: [_selected(id)],
          policyId: 'safe',
          policyVersion: 1,
          evidenceRefs: const [],
        ),
    };

void main() {
  ListeningPositionFrdSet position(String id, ProProject source) =>
      ListeningPositionFrdSet(
        positionId: id,
        label: id,
        channels: {
          for (final channel in source.acousticState.driverChannels)
            channel.id: channel.frdData!,
        },
      );

  test('primary improvement plus other-position worsening is rejected', () {
    final primary =
        _project(magnitudeDb: 12, withPhase: false, channelGainDb: -6.0206);
    final other =
        _project(magnitudeDb: 0, withPhase: false, channelGainDb: -6.0206);
    final result = FullSystemCandidateEvaluator.evaluate(
      project: primary,
      safetyByChannel: _safety(),
      listeningPositions: [position('right-seat', other)],
    );
    expect(result.accepted, isFalse);
    expect(result.rejectedReasons, isNotEmpty);
    expect(result.positionMetrics['right-seat'], isNotNull);
  });

  test(
      'all supplied positions improve: lowest average weighted RMS is accepted',
      () {
    final primary = _project(magnitudeDb: 0, withPhase: false);
    final result = FullSystemCandidateEvaluator.evaluate(
      project: primary,
      safetyByChannel: _safety(),
      listeningPositions: [position('left-seat', primary)],
    );
    expect(result.accepted, isTrue);
    expect(result.positionMetrics['left-seat']!.improvement, greaterThan(0));
  });

  test('no listening positions preserves the primary result exactly', () {
    final project = _project(magnitudeDb: 0, withPhase: false);
    final baseline = FullSystemCandidateEvaluator.evaluate(
        project: project, safetyByChannel: _safety());
    final noPositions = FullSystemCandidateEvaluator.evaluate(
        project: project,
        safetyByChannel: _safety(),
        listeningPositions: const []);
    expect(noPositions.accepted, baseline.accepted);
    expect(noPositions.afterWeightedRmsDb, baseline.afterWeightedRmsDb);
  });

  test('position input maps four channels without mixing repeat sweeps', () {
    final project = _project(magnitudeDb: 0, withPhase: false);
    final input = ListeningPositionFrdInput(
        positionId: 'secondary', label: 'Secondary seat');
    for (final channel in project.acousticState.driverChannels) {
      input.add(channelId: channel.id, frd: channel.frdData!);
    }
    final set = input.build();
    expect(set.isComplete, isTrue);
    expect(set.channels.keys.toSet(), _ids.toSet());
    expect(
        project.acousticState.driverChannels
            .every((channel) => channel.additionalFrdSweeps.isEmpty),
        isTrue);
  });

  test('individual cuts that worsen the full sum are rejected', () {
    final result = FullSystemCandidateEvaluator.evaluate(
      project: _project(
        magnitudeDb: 0,
        withPhase: true,
        oneInvertedPhase: true,
        channelGainDb: -6.0206,
      ),
      safetyByChannel: {'ch_tw_l': _safety()['ch_tw_l']!},
    );

    expect(result.mode, FullSystemSummationMode.phaseAware);
    expect(result.accepted, isFalse,
        reason: 'before=${result.beforeWeightedRmsDb}, '
            'after=${result.afterWeightedRmsDb}');
    expect(result.afterWeightedRmsDb,
        greaterThanOrEqualTo(result.beforeWeightedRmsDb));
    expect(result.selectedByChannel, isEmpty);
  });

  test('lowest-RMS improving full-system combination is selected', () {
    final result = FullSystemCandidateEvaluator.evaluate(
      project: _project(magnitudeDb: 0, withPhase: false),
      safetyByChannel: _safety(),
    );

    expect(result.accepted, isTrue);
    expect(result.afterWeightedRmsDb, lessThan(result.beforeWeightedRmsDb));
    expect(result.combinationsEvaluated, 15);
    expect(result.selectedByChannel.keys.toSet(), _ids.toSet());
    for (final id in _ids) {
      expect(
          result.selectedByChannel[id]!.single.scoredCandidate.candidate
              .channelId,
          id);
    }
  });

  test('phase-aware is used only when all four FRDs carry phase', () {
    final phaseAware = FullSystemCandidateEvaluator.evaluate(
      project: _project(magnitudeDb: 0, withPhase: true),
      safetyByChannel: _safety(),
    );
    final magnitudeOnly = FullSystemCandidateEvaluator.evaluate(
      project: _project(magnitudeDb: 0, withPhase: false),
      safetyByChannel: _safety(),
    );

    expect(phaseAware.mode, FullSystemSummationMode.phaseAware);
    expect(magnitudeOnly.mode, FullSystemSummationMode.magnitudeOnly);
  });

  test('selected target changes weighted RMS and is reported', () {
    final base = _project(magnitudeDb: 0, withPhase: false);
    final warm = base.copyWith(
      acousticState: base.acousticState.copyWith(
        targetCurve: base.acousticState.targetCurve
            .copyWith(selectedPreset: TargetCurvePreset.warm),
      ),
    );
    final flat = FullSystemCandidateEvaluator.evaluate(
        project: base, safetyByChannel: _safety());
    final warmResult = FullSystemCandidateEvaluator.evaluate(
        project: warm, safetyByChannel: _safety());
    expect(warmResult.targetName, 'Warm');
    expect(warmResult.beforeWeightedRmsDb,
        isNot(equals(flat.beforeWeightedRmsDb)));
  });

  group('Target curve consistency (Phase 5-A-1)', () {
    // Regression: the evaluator's internal target values must come from
    // exactly the same ProTargetCurve.db formula the Optimizer already
    // uses, not a separate (previously divergent) approximation. Proven via
    // the public measure() API: each channel's raw FRD is built so the
    // magnitude-only combination of 4 identical channels (a coherent power
    // sum, +10*log10(4) dB) exactly equals ProTargetCurve.db(preset, f) at
    // every fixture frequency. This can only measure as a perfect on-target
    // result (weightedRmsDb ≈ 0) if the evaluator is truly using
    // ProTargetCurve.db internally — any divergent formula (e.g. the old,
    // now-removed TargetCurveState.targetDbAt step-function approximation)
    // would show a non-zero residual for warm/studio/nearfield.
    const freqs = [100.0, 1000.0, 10000.0];
    final fourChannelSumOffsetDb = 10 * math.log(4) / math.ln10;

    ProProject projectMatchingTarget(TargetCurvePreset preset) {
      final now = DateTime(2026, 8, 1);
      return ProProject(
        id: 'p',
        name: 'p',
        createdAt: now,
        updatedAt: now,
        acousticState: MeasurementProjectState(
          targetCurve: TargetCurveState(selectedPreset: preset),
          driverChannels: [
            for (var i = 0; i < _ids.length; i++)
              DriverChannel(
                id: _ids[i],
                name: _ids[i],
                role: i.isEven ? DriverRole.coaxTweeter : DriverRole.coaxWoofer,
                side: i < 2 ? DriverSide.left : DriverSide.right,
                frdData: ParsedMeasurementData(
                  id: 'frd-${_ids[i]}',
                  sourceFileName: '${_ids[i]}.frd',
                  fileType: AcousticFileType.frd,
                  importedAt: now,
                  points: [
                    for (final f in freqs)
                      MeasurementDataPoint(
                        frequencyHz: f,
                        magnitudeDb: ProTargetCurve.db(preset, f) -
                            fourChannelSumOffsetDb,
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    for (final preset in TargetCurvePreset.values) {
      test(
          'measure() scores a response matching ProTargetCurve.db($preset) '
          'as perfectly on-target', () {
        final project = projectMatchingTarget(preset);
        final result = FullSystemCandidateEvaluator.measure(
            project: project, applyTuning: false);

        expect(result, isNotNull, reason: 'preset=$preset');
        expect(result!.weightedRmsDb, closeTo(0.0, 1e-6),
            reason: 'preset=$preset');
      });
    }
  });

  test('hybrid XO feasibility fails closed without phase/ZMA and preserves sides', () {
    final result = HybridXoFeasibilityEvaluator.evaluate(
        project: _project(magnitudeDb: 0, withPhase: false));
    expect(result.verdict, HybridXoVerdict.insufficientEvidence);
    expect(result.pairs.map((p) => p.side), ['L', 'R']);
    expect(result.pairs.every((p) => p.missingEvidence.isNotEmpty), isTrue);
  });

  test('phase plus ZMA with overlap is DSP-only suitable', () {
    final source = _project(magnitudeDb: 0, withPhase: true);
    final now = DateTime(2026, 8, 1);
    final ready = source.copyWith(
      acousticState: source.acousticState.copyWith(
        driverChannels: [
          for (final channel in source.acousticState.driverChannels)
            channel.copyWith(
              zmaData: ParsedMeasurementData(
                id: 'zma-${channel.id}',
                sourceFileName: '${channel.id}.zma',
                fileType: AcousticFileType.zma,
                importedAt: now,
                points: [
                  for (final frequency in [100.0, 1000.0, 10000.0])
                    MeasurementDataPoint(
                        frequencyHz: frequency, impedanceOhm: 8),
                ],
              ),
            ),
        ],
      ),
    );
    final result = HybridXoFeasibilityEvaluator.evaluate(project: ready);
    expect(result.verdict, HybridXoVerdict.dspOnlySuitable);
  });
}
