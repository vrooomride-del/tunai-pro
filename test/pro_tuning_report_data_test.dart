import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_demo_project_factory.dart';
import 'package:tunai_pro/core/pro_measurement_store.dart';
import 'package:tunai_pro/core/pro_tuning_report_data.dart';

void main() {
  group('buildTuningReport', () {
    test('populates all sections from a demo project', () {
      final project = createTunaiProDemoProject();
      final report = buildTuningReport(
        project,
        const ProMeasurementStore(),
        generatedAt: DateTime(2026, 7, 19),
      );

      expect(report.schemaVersion, kTuningReportSchemaVersion);
      expect(report.generatedAt, DateTime(2026, 7, 19));
      expect(report.project.projectName, project.name);
      expect(report.project.projectId, project.id);

      // Measurement mirrors project acoustic state.
      expect(report.measurement.totalDrivers, project.acousticState.totalDrivers);
      expect(report.measurement.frdImportedCount,
          project.acousticState.importedFrdCount);

      // Target curve.
      expect(report.targetCurve.presetName,
          project.acousticState.targetCurve.selectedPreset.name);

      // Crossover + PEQ mirror tuning state.
      expect(report.crossover.configuredChannels,
          project.tuningState.configuredXoChannels);
      expect(report.peq.totalBands, project.tuningState.totalPeqBands);

      // Revisions.
      expect(report.revisions.tuning, project.tuningState.tuningRevision);
      expect(report.revisions.optimizer, project.optimizerState.revision);
    });

    test('freezes derived phase alignment (statuses are valid)', () {
      final report = buildTuningReport(
          createTunaiProDemoProject(), const ProMeasurementStore());
      for (final p in report.phaseAlignment.pairs) {
        expect(['good', 'check', 'misalign'], contains(p.status));
        expect(p.crossoverHz, greaterThan(0));
      }
      expect(report.phaseAlignment.electricalOnly, isTrue);
      expect(
          report.phaseAlignment.goodCount +
              report.phaseAlignment.checkCount +
              report.phaseAlignment.misalignCount,
          report.phaseAlignment.pairs.length);
    });

    test('freezes optimizer scores in 0–100 with a confidence', () {
      final report = buildTuningReport(
          createTunaiProDemoProject(), const ProMeasurementStore());
      final o = report.optimizer;
      expect(o.beforeScore, isNotNull);
      expect(o.afterScore, isNotNull);
      expect(o.beforeScore!, inInclusiveRange(0.0, 100.0));
      expect(o.afterScore!, inInclusiveRange(0.0, 100.0));
      expect(o.improvement, closeTo(o.afterScore! - o.beforeScore!, 1e-9));
      expect(['low', 'medium', 'high'], contains(o.confidence));
      expect(o.simulatedProjection, isTrue);
    });

    test('measurement store data flows into the report', () {
      final project = createTunaiProDemoProject();
      final report =
          buildTuningReport(project, const ProMeasurementStore(sessions: []));
      expect(report.measurement.sessionCount, 0);
      expect(report.measurement.totalPoints, 0);
      expect(report.measurement.lastSessionAt, isNull);
    });

    test('JSON round-trip preserves the snapshot', () {
      final report = buildTuningReport(
        createTunaiProDemoProject(),
        const ProMeasurementStore(),
        generatedAt: DateTime(2026, 7, 19, 12, 30),
      );
      final restored = TuningReportData.fromJson(report.toJson());

      expect(restored.schemaVersion, report.schemaVersion);
      expect(restored.generatedAt, report.generatedAt);
      expect(restored.project.projectId, report.project.projectId);
      expect(restored.measurement.totalDrivers, report.measurement.totalDrivers);
      expect(restored.targetCurve.presetName, report.targetCurve.presetName);
      expect(restored.crossover.hpfCount, report.crossover.hpfCount);
      expect(restored.peq.activeBands, report.peq.activeBands);
      expect(restored.phaseAlignment.pairs.length,
          report.phaseAlignment.pairs.length);
      expect(restored.optimizer.beforeScore, report.optimizer.beforeScore);
      expect(restored.optimizer.confidence, report.optimizer.confidence);
      expect(restored.deployment.readinessLabel, report.deployment.readinessLabel);
      expect(restored.warnings, report.warnings);
      expect(restored.revisions.tuning, report.revisions.tuning);
    });
  });
}
