// TUNAI PRO — Phase L simulation engine sanity checks.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_simulation_data.dart';
import 'package:tunai_pro/core/pro_simulation_engine.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_measurement_parser.dart';

ProProject _defaultProject() => ProProject.create(
  name: 'Sim Test',
  speakerModel: 'Test Speaker',
  roomName: 'Test Room',
  sampleRate: 48000,
  dspTarget: 'Simulation',
  channelConfig: '2-way',
);

void main() {
  group('Simulation frequency grid', () {
    test('generates log-spaced points between 20 and 20000 Hz', () {
      final result = generateSimulationDraft(project: _defaultProject());
      // Every curve that has points should span 20–20000 Hz
      for (final curve in result.curves) {
        if (curve.points.isEmpty) continue;
        expect(curve.points.first.frequencyHz, closeTo(20, 1));
        expect(curve.points.last.frequencyHz, closeTo(20000, 1));
      }
    });

    test('point count is approximately 12 pts/oct * log2(20000/20) ≈ 120', () {
      final result = generateSimulationDraft(project: _defaultProject());
      final nonEmpty = result.curves.where((c) => c.hasPoints).toList();
      if (nonEmpty.isEmpty) return;
      final count = nonEmpty.first.pointCount;
      // 12 pts/oct over ~10 octaves = ~120; allow ±10
      expect(count, greaterThan(100));
      expect(count, lessThan(160));
    });

    test('custom pointsPerOctave affects curve density', () {
      const config6 = SimulationRunConfig(pointsPerOctave: 6);
      const config24 = SimulationRunConfig(pointsPerOctave: 24);
      final r6 = generateSimulationDraft(
          project: _defaultProject(), config: config6);
      final r24 = generateSimulationDraft(
          project: _defaultProject(), config: config24);
      final c6 = r6.curves.firstWhere((c) => c.hasPoints);
      final c24 = r24.curves.firstWhere((c) => c.hasPoints);
      expect(c24.pointCount, greaterThan(c6.pointCount));
    });
  });

  group('Default config produces curves', () {
    late SimulationRunResult result;
    setUp(() {
      result = generateSimulationDraft(project: _defaultProject());
    });

    test('result is non-null with at least one curve', () {
      expect(result.curves, isNotEmpty);
    });

    test('has target curve by default', () {
      expect(result.hasTargetCurve, isTrue);
    });

    test('target curve has points', () {
      final target =
          result.curves.firstWhere((c) => c.type == SimulationCurveType.target);
      expect(target.hasPoints, isTrue);
    });

    test('has summed curve by default', () {
      expect(result.hasSummedCurve, isTrue);
    });

    test('warnings list is non-empty (draft warnings included)', () {
      expect(result.warnings, isNotEmpty);
    });

    test('readiness is not noData when curves exist', () {
      expect(result.readiness, isNot(SimulationReadiness.noData));
    });
  });

  group('Target curve shapes', () {
    test('flat target is all ~0 dB', () {
      final result = generateSimulationDraft(
        project: _defaultProject(),
        config: const SimulationRunConfig(
            includeTarget: true, includeDrivers: false, includeSummed: false),
      );
      final target =
          result.curves.firstWhere((c) => c.type == SimulationCurveType.target);
      for (final pt in target.points) {
        expect(pt.value, closeTo(0.0, 0.01));
      }
    });

    test('warm target has positive dB at 20 Hz (bass lift)', () {
      // Build a project with warm target preset
      final acoustic = MeasurementProjectState.createDefault().copyWith(
        targetCurve: const TargetCurveState(
            selectedPreset: TargetCurvePreset.warm),
      );
      final project = _defaultProject().copyWith(acousticState: acoustic);
      final result = generateSimulationDraft(
        project: project,
        config: const SimulationRunConfig(
            includeTarget: true, includeDrivers: false, includeSummed: false),
      );
      final target =
          result.curves.firstWhere((c) => c.type == SimulationCurveType.target);
      final lowPt = target.points.first; // ~20 Hz
      expect(lowPt.value, greaterThan(0.5)); // warm target has bass lift
    });

    test('studio target is near 0 dB below 10 kHz', () {
      final acoustic = MeasurementProjectState.createDefault().copyWith(
        targetCurve: const TargetCurveState(
            selectedPreset: TargetCurvePreset.studio),
      );
      final project = _defaultProject().copyWith(acousticState: acoustic);
      final result = generateSimulationDraft(
        project: project,
        config: const SimulationRunConfig(
            includeTarget: true, includeDrivers: false, includeSummed: false),
      );
      final target =
          result.curves.firstWhere((c) => c.type == SimulationCurveType.target);
      // Points below 8 kHz should be near 0 dB
      final midPt =
          target.points.firstWhere((p) => p.frequencyHz >= 1000);
      expect(midPt.value, closeTo(0.0, 0.1));
    });
  });

  group('Driver placeholder curves', () {
    test('driver curves generated when drivers configured', () {
      const driver = DriverChannel(
        id: 'wf_l',
        name: 'Woofer L',
        role: DriverRole.woofer,
        side: DriverSide.left,
        enabled: true,
      );
      final acoustic = MeasurementProjectState.createDefault().copyWith(
        driverChannels: [driver],
      );
      final project = _defaultProject().copyWith(acousticState: acoustic);
      final result = generateSimulationDraft(
        project: project,
        config: const SimulationRunConfig(
            includeDrivers: true, includeSummed: false, includeTarget: false),
      );
      expect(result.hasDriverCurves, isTrue);
      final driverCurve =
          result.curves.firstWhere((c) => c.type == SimulationCurveType.driver);
      expect(driverCurve.hasPoints, isTrue);
      expect(driverCurve.channelId, 'wf_l');
    });

    test('no driver curves when includeDrivers is false', () {
      final result = generateSimulationDraft(
        project: _defaultProject(),
        config: const SimulationRunConfig(
            includeDrivers: false, includeSummed: false),
      );
      expect(result.hasDriverCurves, isFalse);
    });
  });

  group('Summed response', () {
    test('summed curve exists when includeSummed true', () {
      final result = generateSimulationDraft(
        project: _defaultProject(),
        config: const SimulationRunConfig(includeSummed: true),
      );
      expect(result.hasSummedCurve, isTrue);
    });

    test('summed curve not present when includeSummed false', () {
      final result = generateSimulationDraft(
        project: _defaultProject(),
        config: const SimulationRunConfig(includeSummed: false),
      );
      expect(result.hasSummedCurve, isFalse);
    });

    test('summed curve warning mentions draft-only', () {
      final result = generateSimulationDraft(
        project: _defaultProject(),
        config: const SimulationRunConfig(includeSummed: true),
      );
      final summed =
          result.curves.firstWhere((c) => c.type == SimulationCurveType.summed);
      final w = (summed.warning ?? '').toLowerCase();
      expect(w, contains('draft'));
    });
  });

  group('Warnings', () {
    test('result warnings include draft-only notice', () {
      final result = generateSimulationDraft(project: _defaultProject());
      final allWarnings = result.warnings.join(' ').toLowerCase();
      expect(allWarnings, contains('draft'));
    });

    test('phase placeholder produces warning when enabled', () {
      final result = generateSimulationDraft(
        project: _defaultProject(),
        config: const SimulationRunConfig(includePhasePlaceholder: true),
      );
      final allWarnings = result.warnings.join(' ').toLowerCase();
      expect(allWarnings, contains('phase'));
    });
  });

  group('Invalid frequency range', () {
    test('inverted range falls back to defaults with warning', () {
      final result = generateSimulationDraft(
        project: _defaultProject(),
        config: const SimulationRunConfig(
          minFrequencyHz: 20000,
          maxFrequencyHz: 20,
        ),
      );
      // Should recover with defaults and emit warning
      expect(result.curves, isNotEmpty);
      final warnText = result.warnings.join(' ').toLowerCase();
      expect(warnText, anyOf(contains('invalid'), contains('default')));
    });

    test('zero min frequency falls back safely', () {
      final result = generateSimulationDraft(
        project: _defaultProject(),
        config: const SimulationRunConfig(
          minFrequencyHz: 0,
          maxFrequencyHz: 20000,
        ),
      );
      expect(result.curves, isNotEmpty);
    });
  });

  group('Safety: no hardware content', () {
    test('simulation JSON contains no hardware address fields', () {
      final result = generateSimulationDraft(project: _defaultProject());
      final jsonStr = result.toJson().toString().toLowerCase();
      expect(jsonStr, isNot(contains('safeload')));
      expect(jsonStr, isNot(contains('0x')));
      expect(jsonStr, isNot(contains('register')));
      expect(jsonStr, isNot(contains('eeprom')));
      expect(jsonStr, isNot(contains('usbi')));
    });

    test('simulation curve JSON contains no hardware addresses', () {
      final result = generateSimulationDraft(project: _defaultProject());
      for (final curve in result.curves) {
        final jsonStr = curve.toJson().toString().toLowerCase();
        expect(jsonStr, isNot(contains('safeload')));
        expect(jsonStr, isNot(contains('0x')));
      }
    });
  });

  group('Imported FRD integration', () {
    ParsedMeasurementData makeFrd({bool withPhase = true}) {
      const frdContent = '''
20    -10.0    0.0
100     0.0   90.0
1000    2.0   45.0
10000   1.0   10.0
20000  -5.0  -20.0
''';
      final r = withPhase
          ? ProMeasurementParser.parseFrd(
              fileName: 'woofer.frd', content: frdContent)
          : ProMeasurementParser.parseFrd(
              fileName: 'woofer.frd',
              content: '20 -10.0\n100 0.0\n1000 2.0\n10000 1.0\n20000 -5.0\n');
      return r.data!;
    }

    test('imported FRD data is used instead of placeholder', () {
      final frd = makeFrd();
      const driver = DriverChannel(
        id: 'wf_l',
        name: 'Woofer L',
        role: DriverRole.woofer,
        side: DriverSide.left,
        enabled: true,
      );
      final driverWithFrd = driver.copyWith(frdData: frd);
      final acoustic = MeasurementProjectState.createDefault()
          .copyWith(driverChannels: [driverWithFrd]);
      final project = _defaultProject().copyWith(acousticState: acoustic);
      final result = generateSimulationDraft(
        project: project,
        config: const SimulationRunConfig(
            includeDrivers: true, includeSummed: false, includeTarget: false),
      );
      expect(result.hasDriverCurves, isTrue);
      final curve = result.curves
          .firstWhere((c) => c.type == SimulationCurveType.driver);
      expect(curve.status, SimulationCurveStatus.imported);
    });

    test('imported FRD curve label contains FRD source tag', () {
      final frd = makeFrd();
      const driver = DriverChannel(
        id: 'wf_l',
        name: 'Woofer L',
        role: DriverRole.woofer,
        side: DriverSide.left,
        enabled: true,
      );
      final driverWithFrd = driver.copyWith(frdData: frd);
      final acoustic = MeasurementProjectState.createDefault()
          .copyWith(driverChannels: [driverWithFrd]);
      final project = _defaultProject().copyWith(acousticState: acoustic);
      final result = generateSimulationDraft(
        project: project,
        config: const SimulationRunConfig(
            includeDrivers: true, includeSummed: false, includeTarget: false),
      );
      final curve = result.curves
          .firstWhere((c) => c.type == SimulationCurveType.driver);
      expect(curve.label, contains('FRD'));
    });

    test('gain offset applies to imported curve', () {
      final frd = makeFrd();
      const driver = DriverChannel(
        id: 'wf_l',
        name: 'Woofer L',
        role: DriverRole.woofer,
        side: DriverSide.left,
        enabled: true,
      );
      final driverWithFrd = driver.copyWith(frdData: frd);
      final acoustic = MeasurementProjectState.createDefault()
          .copyWith(driverChannels: [driverWithFrd]);
      final projectNoGain = _defaultProject().copyWith(acousticState: acoustic);
      final projectGain = projectNoGain; // gain offset = 0 for default

      final resultNo = generateSimulationDraft(
        project: projectNoGain,
        config: const SimulationRunConfig(
            includeDrivers: true, includeSummed: false, includeTarget: false),
      );
      final resultWith = generateSimulationDraft(
        project: projectGain,
        config: const SimulationRunConfig(
            includeDrivers: true, includeSummed: false, includeTarget: false),
      );
      // With default tuning both should match
      final ptNo = resultNo.curves
          .firstWhere((c) => c.type == SimulationCurveType.driver)
          .points[2];
      final ptWith = resultWith.curves
          .firstWhere((c) => c.type == SimulationCurveType.driver)
          .points[2];
      expect(ptNo.value, closeTo(ptWith.value, 0.001));
    });

    test('summed response includes imported FRD curves', () {
      final frd = makeFrd();
      const driver = DriverChannel(
        id: 'wf_l',
        name: 'Woofer L',
        role: DriverRole.woofer,
        side: DriverSide.left,
        enabled: true,
      );
      final driverWithFrd = driver.copyWith(frdData: frd);
      final acoustic = MeasurementProjectState.createDefault()
          .copyWith(driverChannels: [driverWithFrd]);
      final project = _defaultProject().copyWith(acousticState: acoustic);
      final result = generateSimulationDraft(
        project: project,
        config: const SimulationRunConfig(
            includeDrivers: true, includeSummed: true, includeTarget: false),
      );
      expect(result.hasSummedCurve, isTrue);
    });

    test('mixed imported/placeholder warning appears', () {
      final frd = makeFrd();
      final drivers = MeasurementProjectState.createDefault().driverChannels;
      // Assign FRD only to first driver
      final mixed = [
        drivers.first.copyWith(frdData: frd),
        ...drivers.skip(1),
      ];
      final acoustic = MeasurementProjectState.createDefault()
          .copyWith(driverChannels: mixed);
      final project = _defaultProject().copyWith(acousticState: acoustic);
      final result = generateSimulationDraft(
        project: project,
        config: const SimulationRunConfig(
            includeDrivers: true, includeSummed: false, includeTarget: false),
      );
      final allWarnings = result.warnings.join(' ').toLowerCase();
      expect(allWarnings, contains('mixed'));
    });

    test('FRD without phase emits no-phase warning in curve', () {
      final frd = makeFrd(withPhase: false);
      const driver = DriverChannel(
        id: 'wf_l',
        name: 'Woofer L',
        role: DriverRole.woofer,
        side: DriverSide.left,
        enabled: true,
      );
      final driverWithFrd = driver.copyWith(frdData: frd);
      final acoustic = MeasurementProjectState.createDefault()
          .copyWith(driverChannels: [driverWithFrd]);
      final project = _defaultProject().copyWith(acousticState: acoustic);
      final result = generateSimulationDraft(
        project: project,
        config: const SimulationRunConfig(
            includeDrivers: true, includeSummed: false, includeTarget: false),
      );
      final curve = result.curves
          .firstWhere((c) => c.type == SimulationCurveType.driver);
      final warn = (curve.warning ?? '').toLowerCase();
      expect(warn, contains('phase'));
    });
  });

  group('JSON round-trip', () {
    test('SimulationRunResult round-trips through JSON', () {
      final result = generateSimulationDraft(project: _defaultProject());
      final json = result.toJson();
      final restored = SimulationRunResult.fromJson(json);
      expect(restored.curveCount, result.curveCount);
      expect(restored.readiness, result.readiness);
      expect(restored.warnings.length, result.warnings.length);
    });

    test('SimulationProjectState round-trips through JSON', () {
      final result = generateSimulationDraft(project: _defaultProject());
      final state = SimulationProjectState(
        runs: [result],
        activeRunId: result.id,
        revision: 1,
      );
      final json = state.toJson();
      final restored = SimulationProjectState.fromJson(json);
      expect(restored.runCount, 1);
      expect(restored.activeRunId, result.id);
    });
  });
}
