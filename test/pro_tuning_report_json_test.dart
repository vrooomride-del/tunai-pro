import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_demo_project_factory.dart';
import 'package:tunai_pro/core/pro_measurement_store.dart';
import 'package:tunai_pro/core/pro_tuning_report_data.dart';
import 'package:tunai_pro/core/pro_tuning_report_json.dart';

void main() {
  TuningReportData buildReport() => buildTuningReport(
        createTunaiProDemoProject(),
        const ProMeasurementStore(),
        generatedAt: DateTime(2026, 7, 19, 12, 30),
      );

  test('pretty JSON is indented and round-trips back to an equal snapshot', () {
    final report = buildReport();
    final json = encodeTuningReportJson(report);

    expect(json, contains('\n'));
    expect(json, contains('  "schemaVersion"'));

    final restored = TuningReportData.fromJson(
        jsonDecode(json) as Map<String, dynamic>);
    expect(restored.schemaVersion, report.schemaVersion);
    expect(restored.generatedAt, report.generatedAt);
    expect(restored.project.projectId, report.project.projectId);
    expect(restored.optimizer.beforeScore, report.optimizer.beforeScore);
    expect(restored.phaseAlignment.pairs.length,
        report.phaseAlignment.pairs.length);
  });

  test('compact JSON has no newlines but decodes to the same map', () {
    final report = buildReport();
    final compact = encodeTuningReportJson(report, pretty: false);
    expect(compact, isNot(contains('\n')));
    expect(jsonDecode(compact), equals(report.toJson()));
  });

  test('serializer is pure (stable output for the same snapshot)', () {
    final report = buildReport();
    expect(encodeTuningReportJson(report), encodeTuningReportJson(report));
  });

  test('filename includes slugified project name and timestamp, ends .json', () {
    final report = buildReport();
    final name = tuningReportFileName(report);
    expect(name, startsWith('tuning-report_'));
    expect(name, endsWith('.json'));
    expect(name, contains('2026-07-19'));
    expect(name, isNot(contains(':')));
  });
}
