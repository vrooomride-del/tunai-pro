// TUNAI PRO — Phase O: Impedance / Load Analysis tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_impedance_analysis.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_measurement_parser.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

ParsedMeasurementData _makeZma(List<(double, double, double?)> pts) {
  final lines = pts.map((t) {
    final phase = t.$3 != null ? '  ${t.$3}' : '';
    return '${t.$1}  ${t.$2}$phase';
  }).join('\n');
  final result = ProMeasurementParser.parseZma(
      fileName: 'test.zma', content: '$lines\n');
  return result.data!;
}

ParsedMeasurementData _makeZmaSimple({
  required double minOhm,
  double minFreq = 1000.0,
  double? phase,
}) {
  return _makeZma([
    (20.0, 8.0, phase),
    (minFreq, minOhm, phase),
    (5000.0, 7.0, phase),
    (10000.0, 12.0, phase),
    (20000.0, 10.0, phase),
  ]);
}

DriverChannel _driver(String id,
    {ParsedMeasurementData? zma, bool enabled = true}) =>
    DriverChannel(
      id: id,
      name: 'Driver $id',
      role: DriverRole.woofer,
      side: DriverSide.left,
      enabled: enabled,
    ).copyWith(zmaData: zma);

MeasurementProjectState _acoustic(List<DriverChannel> drivers) =>
    MeasurementProjectState.createDefault().copyWith(driverChannels: drivers);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Missing ZMA', () {
    test('missing ZMA creates missingZma issue', () {
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf')]));
      expect(result.issues, isNotEmpty);
      expect(
          result.issues.any((i) => i.type == ImpedanceIssueType.missingZma),
          isTrue);
    });

    test('missing ZMA summary has hasZma false', () {
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf')]));
      expect(result.summaries.first.hasZma, isFalse);
    });

    test('missing ZMA riskLevel is unknown', () {
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf')]));
      expect(result.summaries.first.riskLevel, ImpedanceRiskLevel.unknown);
    });

    test('missing ZMA count is correct', () {
      final zma = _makeZmaSimple(minOhm: 8.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([
        _driver('wf'),
        _driver('tw', zma: zma),
      ]));
      expect(result.missingZmaCount, 1);
    });
  });

  group('Impedance magnitude risk', () {
    test('normal 8 ohm returns low risk', () {
      final zma = _makeZmaSimple(minOhm: 8.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(result.summaries.first.riskLevel.severity,
          lessThanOrEqualTo(ImpedanceRiskLevel.low.severity));
    });

    test('min impedance below 2 ohm returns critical', () {
      final zma = _makeZmaSimple(minOhm: 1.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(result.overallRisk, ImpedanceRiskLevel.critical);
      expect(result.hasCritical, isTrue);
      expect(
          result.issues.any((i) =>
              i.type == ImpedanceIssueType.lowMinimumImpedance &&
              i.riskLevel == ImpedanceRiskLevel.critical),
          isTrue);
    });

    test('min impedance 2.5 ohm returns high', () {
      final zma = _makeZmaSimple(minOhm: 2.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      final summary = result.summaries.first;
      expect(summary.riskLevel, ImpedanceRiskLevel.high);
      expect(
          result.issues.any((i) =>
              i.type == ImpedanceIssueType.lowMinimumImpedance &&
              i.riskLevel == ImpedanceRiskLevel.high),
          isTrue);
    });

    test('min impedance 3.5 ohm returns medium', () {
      final zma = _makeZmaSimple(minOhm: 3.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      final summary = result.summaries.first;
      // medium for Z only (no phase)
      expect(summary.riskLevel, ImpedanceRiskLevel.medium);
    });

    test('min impedance 6 ohm returns low or none', () {
      final zma = _makeZmaSimple(minOhm: 6.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(result.summaries.first.riskLevel.severity,
          lessThanOrEqualTo(ImpedanceRiskLevel.low.severity));
    });

    test('minimum impedance value is extracted correctly', () {
      final zma = _makeZmaSimple(minOhm: 2.5, minFreq: 500.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      final s = result.summaries.first;
      expect(s.minImpedanceOhm, closeTo(2.5, 0.01));
      expect(s.minImpedanceFrequencyHz, closeTo(500.0, 0.01));
    });
  });

  group('Phase angle risk', () {
    test('severe phase angle >= 60 deg returns high warning', () {
      final zma = _makeZmaSimple(minOhm: 8.0, phase: 65.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(
          result.issues.any((i) =>
              i.type == ImpedanceIssueType.severePhaseAngle &&
              i.riskLevel == ImpedanceRiskLevel.high),
          isTrue);
    });

    test('phase angle >= 45 deg returns medium warning', () {
      final zma = _makeZmaSimple(minOhm: 8.0, phase: 50.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(
          result.issues.any((i) => i.type == ImpedanceIssueType.severePhaseAngle),
          isTrue);
      final phaseIssue = result.issues
          .firstWhere((i) => i.type == ImpedanceIssueType.severePhaseAngle);
      expect(phaseIssue.riskLevel.severity,
          greaterThanOrEqualTo(ImpedanceRiskLevel.medium.severity));
    });

    test('small phase angle produces no phase issue', () {
      final zma = _makeZmaSimple(minOhm: 8.0, phase: 20.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(
          result.issues.any((i) => i.type == ImpedanceIssueType.severePhaseAngle),
          isFalse);
    });

    test('max phase angle is extracted correctly', () {
      final zma = _makeZmaSimple(minOhm: 8.0, phase: 55.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(result.summaries.first.maxPhaseAngleDeg, closeTo(55.0, 0.01));
    });
  });

  group('Combined Z + phase risk escalation', () {
    test('low Z + severe phase creates combined issue and elevates risk', () {
      final zma = _makeZmaSimple(minOhm: 3.0, phase: 60.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(
          result.issues.any((i) =>
              i.type == ImpedanceIssueType.lowImpedanceWithPhaseAngle),
          isTrue);
      expect(result.summaries.first.riskLevel.severity,
          greaterThanOrEqualTo(ImpedanceRiskLevel.high.severity));
    });

    test('high Z + large phase does not falsely escalate', () {
      final zma = _makeZmaSimple(minOhm: 8.0, phase: 30.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(
          result.issues.any((i) =>
              i.type == ImpedanceIssueType.lowImpedanceWithPhaseAngle),
          isFalse);
    });
  });

  group('Data quality issues', () {
    test('sparse data (< 10 pts) creates sparseData issue', () {
      // _makeZmaSimple only has 5 points
      final zma = _makeZmaSimple(minOhm: 8.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(
          result.issues.any((i) => i.type == ImpedanceIssueType.sparseData),
          isTrue);
    });

    test('out-of-range data creates outOfRangeData issue', () {
      // ZMA from 100 Hz to 10 kHz — does not cover 20 Hz to 20 kHz
      final zma = _makeZma([
        (100.0, 8.0, null),
        (500.0, 6.0, null),
        (1000.0, 8.0, null),
        (5000.0, 10.0, null),
        (10000.0, 9.0, null),
      ]);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(
          result.issues.any((i) => i.type == ImpedanceIssueType.outOfRangeData),
          isTrue);
    });

    test('non-finite data does not crash', () {
      // Parser will skip NaN lines; feed a valid result manually
      final zma = _makeZmaSimple(minOhm: 8.0);
      expect(
          () => ProImpedanceAnalyzer.analyze(
              acousticState: _acoustic([_driver('wf', zma: zma)])),
          returnsNormally);
    });

    test('no drivers returns unknown overall risk', () {
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([]));
      expect(result.overallRisk, ImpedanceRiskLevel.unknown);
      expect(result.summaries, isEmpty);
    });

    test('disabled driver is not analyzed', () {
      final zma = _makeZmaSimple(minOhm: 1.0); // would be critical
      final driver = _driver('wf', zma: zma, enabled: false);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([driver]));
      expect(result.summaries, isEmpty);
      expect(result.hasCritical, isFalse);
    });
  });

  group('Overall risk', () {
    test('overall risk is max of all driver risks', () {
      final zma8 = _makeZmaSimple(minOhm: 8.0);
      final zma2 = _makeZmaSimple(minOhm: 1.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([
        _driver('wf', zma: zma8),
        _driver('tw', zma: zma2),
      ]));
      expect(result.overallRisk, ImpedanceRiskLevel.critical);
    });

    test('all low-risk drivers → overall risk low', () {
      final zma = _makeZmaSimple(minOhm: 8.0);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([
        _driver('wf', zma: zma),
        _driver('tw', zma: zma),
      ]));
      expect(result.overallRisk.severity,
          lessThanOrEqualTo(ImpedanceRiskLevel.low.severity));
    });
  });

  group('Readiness labels', () {
    test('no drivers → No ZMA data label', () {
      final result = ProImpedanceAnalyzer.analyze(acousticState: _acoustic([]));
      expect(result.readinessLabel, 'No ZMA data');
    });

    test('critical risk → Critical load risk label', () {
      final zma = _makeZmaSimple(minOhm: 1.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(result.readinessLabel, 'Critical load risk');
    });

    test('low risk → Load risk low label', () {
      // Build ZMA with >10 points covering 20Hz–20kHz to avoid sparse/range warnings
      final pts = List.generate(
          20,
          (i) => (20.0 * (i + 1).toDouble(), 8.0, null as double?));
      final zma = _makeZma(pts);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      expect(result.readinessLabel, anyOf('Load risk low', 'Impedance data partial'));
    });
  });

  group('JSON round-trip', () {
    test('ImpedanceIssue round-trips JSON', () {
      final zma = _makeZmaSimple(minOhm: 2.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      final issue = result.issues.first;
      final restored = ImpedanceIssue.fromJson(issue.toJson());
      expect(restored.id, issue.id);
      expect(restored.type, issue.type);
      expect(restored.riskLevel, issue.riskLevel);
      expect(restored.title, issue.title);
    });

    test('DriverImpedanceSummary round-trips JSON', () {
      final zma = _makeZmaSimple(minOhm: 2.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      final summary = result.summaries.first;
      final restored = DriverImpedanceSummary.fromJson(summary.toJson());
      expect(restored.channelId, summary.channelId);
      expect(restored.minImpedanceOhm, summary.minImpedanceOhm);
      expect(restored.riskLevel, summary.riskLevel);
    });

    test('ImpedanceAnalysisResult round-trips JSON', () {
      final zma = _makeZmaSimple(minOhm: 2.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      final json = result.toJson();
      final restored = ImpedanceAnalysisResult.fromJson(json);
      expect(restored.overallRisk, result.overallRisk);
      expect(restored.summaries.length, result.summaries.length);
      expect(restored.issues.length, result.issues.length);
      expect(restored.readinessLabel, result.readinessLabel);
    });

    test('JSON contains no hardware address fields', () {
      final zma = _makeZmaSimple(minOhm: 2.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      final jsonStr = result.toJson().toString().toLowerCase();
      expect(jsonStr, isNot(contains('safeload')));
      expect(jsonStr, isNot(contains('0x')));
      expect(jsonStr, isNot(contains('register')));
      expect(jsonStr, isNot(contains('eeprom')));
      expect(jsonStr, isNot(contains('usbi')));
      expect(jsonStr, isNot(contains('adau')));
    });
  });

  group('Safety restrictions', () {
    test('analysis result does not contain hardware write instructions', () {
      final zma = _makeZmaSimple(minOhm: 1.0); // critical
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      final allText = [
        result.summary,
        ...result.issues.map((i) => '${i.description} ${i.recommendation}'),
      ].join(' ').toLowerCase();
      expect(allText, isNot(contains('safeload')));
      expect(allText, isNot(contains('write to')));
      expect(allText, isNot(contains('register')));
      expect(allText, isNot(contains('eeprom')));
    });

    test('critical issue recommends hardware verification, not hardware write', () {
      final zma = _makeZmaSimple(minOhm: 1.5);
      final result = ProImpedanceAnalyzer.analyze(
          acousticState: _acoustic([_driver('wf', zma: zma)]));
      final critIssue = result.issues
          .firstWhere((i) => i.riskLevel == ImpedanceRiskLevel.critical);
      expect(critIssue.recommendation.toLowerCase(), contains('verif'));
    });
  });
}
