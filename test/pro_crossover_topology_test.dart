// TUNAI PRO — Phase K crossover topology planner sanity checks.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_crossover_topology.dart';
import 'package:tunai_pro/core/pro_biquad_engine.dart';
import 'package:tunai_pro/core/pro_dsp_target_data.dart';

CrossoverTopologyInput _input({
  CrossoverFilterFamily family = CrossoverFilterFamily.linkwitzRiley,
  XoSlope slope = XoSlope.slope24,
  CrossoverFilterShape shape = CrossoverFilterShape.highPass,
  double frequencyHz = 2000,
  double sampleRateHz = 48000,
}) =>
    CrossoverTopologyInput(
      channelId: 'ch_test',
      shape: shape,
      family: family,
      slope: slope,
      frequencyHz: frequencyHz,
      sampleRateHz: sampleRateHz,
      sourceBlockId: 'xo_test',
    );

void main() {
  group('CrossoverTopologyPlanner', () {
    // ── LR24 ────────────────────────────────────────────────────────────────

    test('LR24 HPF generates 2 stages', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope24,
        shape: CrossoverFilterShape.highPass,
      ));
      expect(plan.stages.length, 2);
      expect(plan.stageCount, 2);
    });

    test('LR24 LPF generates 2 stages', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope24,
        shape: CrossoverFilterShape.lowPass,
      ));
      expect(plan.stages.length, 2);
    });

    test('LR24 stages have Q=0.7071', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope24,
      ));
      for (final stage in plan.stages) {
        expect(stage.q, closeTo(0.7071, 1e-4));
      }
    });

    test('LR24 status is draft', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope24,
      ));
      expect(plan.status, CrossoverTopologyStatus.draft);
    });

    test('LR24 includes acoustic verification warning', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope24,
      ));
      final warnText = plan.warnings.join(' ').toLowerCase();
      expect(warnText, contains('verification'));
    });

    // ── LR48 ────────────────────────────────────────────────────────────────

    test('LR48 generates 4 stages', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope48,
      ));
      expect(plan.stages.length, 4);
    });

    test('LR48 status is requiresVerification or draft', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope48,
      ));
      expect(
        plan.status == CrossoverTopologyStatus.requiresVerification ||
            plan.status == CrossoverTopologyStatus.draft,
        isTrue,
      );
    });

    test('LR48 has at least one warning', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope48,
      ));
      expect(plan.warnings, isNotEmpty);
    });

    // ── Butterworth ──────────────────────────────────────────────────────────

    test('Butterworth12 generates 1 stage', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.butterworth,
        slope: XoSlope.slope12,
      ));
      expect(plan.stages.length, 1);
    });

    test('Butterworth24 generates 2 stages', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.butterworth,
        slope: XoSlope.slope24,
      ));
      expect(plan.stages.length, 2);
    });

    test('Butterworth24 uses exact Q values from polynomial table', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.butterworth,
        slope: XoSlope.slope24,
      ));
      expect(plan.stages[0].q, closeTo(0.5412, 1e-4));
      expect(plan.stages[1].q, closeTo(1.3066, 1e-4));
    });

    test('Butterworth48 generates 4 stages', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.butterworth,
        slope: XoSlope.slope48,
      ));
      expect(plan.stages.length, 4);
    });

    // ── Bessel ───────────────────────────────────────────────────────────────

    test('Bessel returns requiresVerification', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.bessel,
        slope: XoSlope.slope24,
      ));
      expect(plan.status, CrossoverTopologyStatus.requiresVerification);
      expect(plan.stages, isEmpty);
    });

    test('Bessel warning mentions Phase K', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.bessel,
        slope: XoSlope.slope24,
      ));
      expect(plan.warnings.join(' ').toLowerCase(), contains('bessel'));
    });

    // ── Custom ────────────────────────────────────────────────────────────────

    test('Custom returns requiresVerification', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.custom,
        slope: XoSlope.slope24,
      ));
      expect(plan.status, CrossoverTopologyStatus.requiresVerification);
    });

    // ── Invalid frequency ─────────────────────────────────────────────────────

    test('frequency at Nyquist returns unsupported', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        frequencyHz: 24000, // == Nyquist at 48 kHz
      ));
      expect(plan.status, CrossoverTopologyStatus.unsupported);
      expect(plan.stages, isEmpty);
    });

    test('frequency above Nyquist returns unsupported', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        frequencyHz: 30000,
        sampleRateHz: 48000,
      ));
      expect(plan.status, CrossoverTopologyStatus.unsupported);
    });

    test('zero frequency returns unsupported', () {
      final plan = CrossoverTopologyPlanner.plan(_input(frequencyHz: 0));
      expect(plan.status, CrossoverTopologyStatus.unsupported);
    });

    // ── Stage content ─────────────────────────────────────────────────────────

    test('stage plans have finite frequencyHz and Q', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope24,
      ));
      for (final stage in plan.stages) {
        expect(stage.frequencyHz.isFinite, isTrue);
        expect(stage.q.isFinite, isTrue);
        expect(stage.q, greaterThan(0));
      }
    });

    test('stage stageLabel is non-empty', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope24,
      ));
      for (final stage in plan.stages) {
        expect(stage.stageLabel, isNotEmpty);
      }
    });

    // ── No hardware content ───────────────────────────────────────────────────

    test('topology plan contains no hardware address fields', () {
      final plan = CrossoverTopologyPlanner.plan(_input());
      final json = plan.toJson();
      final jsonStr = json.toString().toLowerCase();
      expect(jsonStr, isNot(contains('safeload')));
      expect(jsonStr, isNot(contains('0x')));
      expect(jsonStr, isNot(contains('register')));
      expect(jsonStr, isNot(contains('eeprom')));
    });

    test('stage plans contain no hardware address fields', () {
      final plan = CrossoverTopologyPlanner.plan(_input());
      for (final stage in plan.stages) {
        final json = stage.toJson().toString().toLowerCase();
        expect(json, isNot(contains('safeload')));
        expect(json, isNot(contains('0x')));
        expect(json, isNot(contains('register')));
      }
    });

    // ── Biquad engine integration ──────────────────────────────────────────────

    test('LR24 stage plans yield finite calculatedDraft biquad coefficients', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope24,
      ));
      for (final stage in plan.stages) {
        final result = ProBiquadEngine.calculate(BiquadDesignInput(
          type: stage.filterType,
          sampleRateHz: 48000,
          frequencyHz: stage.frequencyHz,
          q: stage.q,
          enabled: true,
        ));
        expect(result.coefficients.status, BiquadDraftStatus.calculatedDraft);
        expect(result.coefficients.b0.isFinite, isTrue);
        expect(result.coefficients.b1.isFinite, isTrue);
        expect(result.coefficients.b2.isFinite, isTrue);
        expect(result.coefficients.a1.isFinite, isTrue);
        expect(result.coefficients.a2.isFinite, isTrue);
      }
    });

    // ── JSON round-trip ────────────────────────────────────────────────────────

    test('CrossoverTopologyPlan round-trips through JSON', () {
      final plan = CrossoverTopologyPlanner.plan(_input(
        family: CrossoverFilterFamily.linkwitzRiley,
        slope: XoSlope.slope24,
      ));
      final json = plan.toJson();
      final restored = CrossoverTopologyPlan.fromJson(json);
      expect(restored.stageCount, plan.stageCount);
      expect(restored.family, plan.family);
      expect(restored.slope, plan.slope);
      expect(restored.status, plan.status);
    });
  });
}
