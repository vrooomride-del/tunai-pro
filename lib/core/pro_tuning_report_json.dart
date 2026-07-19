// ── TUNAI PRO — Tuning Report JSON serializer (pure) ──────────────────────────
// Turns a frozen TuningReportData snapshot into a formatted JSON artifact
// string. Pure and side-effect free: no file I/O, no DSP, no transport.
// Does not modify TuningReportData, the builder, or any export/deploy model.

import 'dart:convert';

import 'pro_tuning_report_data.dart';

/// Serializes [report] to a JSON string. Pretty-printed (2-space indent) by
/// default for a human-readable artifact; pass [pretty] = false for compact.
String encodeTuningReportJson(TuningReportData report, {bool pretty = true}) {
  final map = report.toJson();
  return pretty
      ? const JsonEncoder.withIndent('  ').convert(map)
      : jsonEncode(map);
}

/// Suggested artifact filename for a report, e.g.
/// `tuning-report_my-project_2026-07-19T12-30-00.json`. Pure string helper.
String tuningReportFileName(TuningReportData report) {
  final slug = report.project.projectName.trim().isEmpty
      ? 'project'
      : report.project.projectName
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
  final ts = report.generatedAt
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  return 'tuning-report_${slug}_$ts.json';
}
