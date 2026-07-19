import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_optimizer_data.dart';
import 'package:tunai_pro/core/pro_response_error.dart';
import 'package:tunai_pro/core/pro_simulation_optimizer.dart';
import 'package:tunai_pro/core/pro_target_curve.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

DriverChannel _driver({ParsedMeasurementData? frd}) => DriverChannel(
      id: 'wf',
      name: 'Woofer',
      role: DriverRole.woofer,
      side: DriverSide.left,
      frdData: frd,
    );

/// FRD with a +6 dB bump centered near [bumpHz] over an otherwise flat 90 dB.
ParsedMeasurementData _bumpFrd({double bumpHz = 1000}) {
  final points = <MeasurementDataPoint>[];
  for (var f = 20.0; f <= 20000; f *= 1.05) {
    final octaves = (f / bumpHz).abs();
    final x = (f / bumpHz).clamp(0.5, 2.0);
    final near = (x - 1.0).abs() < 0.25;
    points.add(MeasurementDataPoint(
      frequencyHz: f,
      magnitudeDb: 90.0 + (near ? 6.0 : 0.0),
    ));
    // silence unused
    octaves.toString();
  }
  return ParsedMeasurementData(
    id: 'm1',
    sourceFileName: 'w.frd',
    fileType: AcousticFileType.frd,
    importedAt: DateTime(2026),
    points: points,
  );
}

String Function() _ids() {
  var i = 0;
  return () => 'sug_${i++}';
}

void main() {
  group('ProTargetCurve', () {
    test('flat and custom are 0 dB everywhere', () {
      for (final f in [20.0, 100.0, 1000.0, 20000.0]) {
        expect(ProTargetCurve.db(TargetCurvePreset.flat, f), 0.0);
        expect(ProTargetCurve.db(TargetCurvePreset.custom, f), 0.0);
      }
    });

    test('warm lifts lows and rolls off highs', () {
      expect(ProTargetCurve.db(TargetCurvePreset.warm, 20), greaterThan(0));
      expect(ProTargetCurve.db(TargetCurvePreset.warm, 1000), 0.0);
      expect(ProTargetCurve.db(TargetCurvePreset.warm, 16000), lessThan(0));
    });
  });

  group('ProResponseError', () {
    final freqs = Adau1701PeqResponse.logFrequencyPoints(count: 64);

    test('identical curves → zero error, score 100', () {
      final r = ProResponseError.analyze(
        freqs: freqs,
        responseDb: List.filled(freqs.length, 0.0),
        targetDb: List.filled(freqs.length, 0.0),
      );
      expect(r.rmsDb, 0.0);
      expect(r.maxDeviationDb, 0.0);
      expect(r.score, 100.0);
    });

    test('constant offset → rms equals offset, lower score', () {
      final r = ProResponseError.analyze(
        freqs: freqs,
        responseDb: List.filled(freqs.length, 3.0),
        targetDb: List.filled(freqs.length, 0.0),
      );
      expect(r.rmsDb, closeTo(3.0, 1e-9));
      expect(r.maxDeviationDb, closeTo(3.0, 1e-9));
      expect(r.score, lessThan(100));
    });
  });

  group('ProSimulationOptimizer', () {
    test('measured bump → corrective cut suggestion that improves the score', () {
      final result = ProSimulationOptimizer.optimizeDriver(
        driver: _driver(frd: _bumpFrd(bumpHz: 1000)),
        currentPeq: PeqChannelState.empty('wf'),
        target: TargetCurvePreset.flat,
        config: const OptimizerRunConfig(mode: OptimizerMode.balanced),
        nextId: _ids(),
      );

      expect(result.suggestions, isNotEmpty);
      final first = result.suggestions.first;
      expect(first.type, OptimizerSuggestionType.addPeqBand);
      expect(first.confidence, OptimizerConfidence.medium);
      // Corrects the bump: a cut roughly in the bump region.
      expect(first.proposedGainDb, lessThan(0));
      expect(first.proposedFrequencyHz, inInclusiveRange(400.0, 2500.0));
      // Greedy pass must not make the fit worse.
      expect(result.after.weightedRmsDb,
          lessThanOrEqualTo(result.before.weightedRmsDb + 1e-9));
      expect(result.after.weightedRmsDb, lessThan(result.before.weightedRmsDb));
    });

    test('respects band budget (maxPeqBandsPerChannel)', () {
      final result = ProSimulationOptimizer.optimizeDriver(
        driver: _driver(frd: _bumpFrd()),
        currentPeq: PeqChannelState.empty('wf'),
        target: TargetCurvePreset.flat,
        config: const OptimizerRunConfig(
            mode: OptimizerMode.aggressive, maxPeqBandsPerChannel: 2),
        nextId: _ids(),
      );
      expect(result.suggestions.length, lessThanOrEqualTo(2));
    });

    test('no free band budget → no suggestions', () {
      final full = PeqChannelState(channelId: 'wf', bands: [
        for (var i = 0; i < 8; i++) PeqBand.slot(i).copyWith(enabled: true),
      ]);
      final result = ProSimulationOptimizer.optimizeDriver(
        driver: _driver(frd: _bumpFrd()),
        currentPeq: full,
        target: TargetCurvePreset.flat,
        config: const OptimizerRunConfig(maxPeqBandsPerChannel: 8),
        nextId: _ids(),
      );
      expect(result.suggestions, isEmpty);
    });

    test('clamps proposed gain to config max cut', () {
      final result = ProSimulationOptimizer.optimizeDriver(
        driver: _driver(frd: _bumpFrd()),
        currentPeq: PeqChannelState.empty('wf'),
        target: TargetCurvePreset.flat,
        config: const OptimizerRunConfig(
            mode: OptimizerMode.aggressive, maxCutDb: 2.0, maxBoostDb: 2.0),
        nextId: _ids(),
      );
      for (final s in result.suggestions) {
        expect(s.proposedGainDb!, inInclusiveRange(-2.0, 2.0));
      }
    });

    test('no FRD → flat baseline draft, low confidence', () {
      final result = ProSimulationOptimizer.optimizeDriver(
        driver: _driver(frd: null),
        currentPeq: PeqChannelState.empty('wf'),
        target: TargetCurvePreset.warm, // non-flat so there is shape to chase
        config: const OptimizerRunConfig(mode: OptimizerMode.balanced),
        nextId: _ids(),
      );
      for (final s in result.suggestions) {
        expect(s.confidence, OptimizerConfidence.low);
        expect(s.reason.toLowerCase(), contains('no measurement'));
      }
    });

    test('flat target already met → no suggestions for flat driver', () {
      final flat = <MeasurementDataPoint>[
        for (var f = 20.0; f <= 20000; f *= 1.1)
          MeasurementDataPoint(frequencyHz: f, magnitudeDb: 85.0),
      ];
      final result = ProSimulationOptimizer.optimizeDriver(
        driver: _driver(
            frd: ParsedMeasurementData(
          id: 'm',
          sourceFileName: 'f.frd',
          fileType: AcousticFileType.frd,
          importedAt: DateTime(2026),
          points: flat,
        )),
        currentPeq: PeqChannelState.empty('wf'),
        target: TargetCurvePreset.flat,
        config: const OptimizerRunConfig(mode: OptimizerMode.balanced),
        nextId: _ids(),
      );
      expect(result.suggestions, isEmpty);
    });
  });
}
