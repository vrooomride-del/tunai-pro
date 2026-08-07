// ── TUNAI PRO Phase 3-B — Calibration file parser ────────────────────────
//
// Pure text parser: no file I/O, no platform channel. Reuses the same
// defensive parsing shape as lib/core/pro_measurement_parser.dart (isolate
// each line, collect line-numbered warnings, fail closed on insufficient
// valid data) but is a SEPARATE parser with separate semantics — a
// calibration curve (microphone correction, frequency + correction dB) is
// never a driver/system FRD (frequency + SPL). Do not merge these parsers or
// their result types.

import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'calibration_types.dart';

/// Result of parsing one calibration file's text content.
class CalibrationParseResult {
  final CalibrationCurve? curve;
  final List<String> errors;
  final List<String> warnings;

  /// sha256 of the raw input content (before any parsing) — provenance only,
  /// distinct from [CalibrationCurve.checksum] (which hashes the parsed
  /// point list, so two byte-different files that parse to the same points
  /// share a curve checksum but not a source checksum).
  final String sourceChecksum;

  /// Non-null only when a clearly-labeled angle metadata line was found
  /// (e.g. "# angle: 0deg", "; 90 degree"). [CalibrationAngle.unspecified]
  /// otherwise — never guessed.
  final CalibrationAngle detectedAngle;

  /// Raw text of a clearly-labeled sensitivity metadata line, if found (e.g.
  /// "# sensitivity: -38.5 dBV"). Informational only — this parser never
  /// infers units or writes it into a profile's typed sensitivityMvPa field;
  /// a human (or a future importer) must interpret and confirm it.
  final String? detectedSensitivityNote;

  const CalibrationParseResult({
    this.curve,
    this.errors = const [],
    this.warnings = const [],
    required this.sourceChecksum,
    this.detectedAngle = CalibrationAngle.unspecified,
    this.detectedSensitivityNote,
  });

  bool get isSuccess => curve != null && errors.isEmpty;
}

// ── Comment / header / metadata detection ──────────────────────────────────

bool _isComment(String line) {
  final t = line.trimLeft();
  return t.startsWith('#') || t.startsWith(';') || t.startsWith('//');
}

bool _isBlank(String line) => line.trim().isEmpty;

final RegExp _anglePattern =
    RegExp(r'(?:^|[^0-9])(0|90)\s*(?:deg(?:ree)?s?|°)', caseSensitive: false);

final RegExp _sensitivityPattern =
    RegExp(r'sensitivit(?:y|ies)\s*[:=]', caseSensitive: false);

CalibrationAngle? _detectAngle(String line) {
  final m = _anglePattern.firstMatch(line);
  if (m == null) return null;
  return m.group(1) == '0'
      ? CalibrationAngle.zeroDegree
      : CalibrationAngle.ninetyDegree;
}

/// Recognizes a header row: the first token fails to parse as a finite
/// number (e.g. "Frequency,Correction" or "Freq(Hz)\tdB"). A genuine data
/// row's first column is always a frequency.
bool _looksLikeHeader(List<String> tokens) {
  if (tokens.isEmpty) return false;
  return double.tryParse(tokens.first) == null;
}

double? _parseFinite(String s) {
  final v = double.tryParse(s);
  if (v == null || !v.isFinite) return null;
  return v;
}

// ── Parser ────────────────────────────────────────────────────────────────

abstract final class CalibrationFileParser {
  /// Parses [content] as a two-column (frequency Hz, correction dB)
  /// calibration file.
  ///
  /// Separator policy: whitespace, tab, or comma between columns — the same
  /// set [ProMeasurementParser] already uses for FRD/ZMA
  /// (`[\s,\t]+`). Semicolon is deliberately NOT a column separator here: it
  /// is already this parser's comment marker (matching
  /// [ProMeasurementParser]'s convention), and treating it as both would be
  /// ambiguous.
  static CalibrationParseResult parse({
    required String content,
    String? sourceIdentity,
  }) {
    final sourceChecksum = sha256.convert(utf8.encode(content)).toString();
    final warnings = <String>[];
    final errors = <String>[];
    final points = <CalibrationPoint>[];
    CalibrationAngle detectedAngle = CalibrationAngle.unspecified;
    String? detectedSensitivityNote;

    final lines = content.split(RegExp(r'\r?\n'));
    var sawAnyDataRow = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_isBlank(line)) continue;

      if (_isComment(line)) {
        // Metadata may live in comment lines — scan, then skip as a row.
        if (detectedAngle == CalibrationAngle.unspecified) {
          detectedAngle = _detectAngle(line) ?? detectedAngle;
        }
        if (detectedSensitivityNote == null &&
            _sensitivityPattern.hasMatch(line)) {
          detectedSensitivityNote = line.trim();
        }
        continue;
      }

      final tokens = line.trim().split(RegExp(r'[\s,\t]+'))
        ..removeWhere((t) => t.isEmpty);
      if (tokens.length < 2) {
        warnings.add(
            'Line ${i + 1}: too few columns (${tokens.length}) — skipped.');
        continue;
      }

      if (!sawAnyDataRow && _looksLikeHeader(tokens)) {
        warnings.add('Line ${i + 1}: header row detected — skipped.');
        continue;
      }

      final freq = _parseFinite(tokens[0]);
      final correction = _parseFinite(tokens[1]);

      if (freq == null) {
        warnings.add(
            'Line ${i + 1}: invalid or non-finite frequency "${tokens[0]}" — skipped.');
        continue;
      }
      if (freq <= 0) {
        warnings.add('Line ${i + 1}: frequency must be > 0 Hz — skipped.');
        continue;
      }
      if (correction == null) {
        warnings.add(
            'Line ${i + 1}: invalid or non-finite correction "${tokens[1]}" — skipped.');
        continue;
      }
      if (correction.abs() > kCalibrationMaxAbsCorrectionDb) {
        warnings.add(
            'Line ${i + 1}: correction ${correction.toStringAsFixed(2)} dB '
            'exceeds the +/-${kCalibrationMaxAbsCorrectionDb.toStringAsFixed(0)} dB '
            'sanity bound — skipped.');
        continue;
      }

      sawAnyDataRow = true;
      points.add(CalibrationPoint(frequencyHz: freq, correctionDb: correction));
    }

    // ── Duplicate frequency resolution ───────────────────────────────────
    points.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    final resolved = <CalibrationPoint>[];
    var conflictFound = false;
    for (final p in points) {
      if (resolved.isNotEmpty && resolved.last.frequencyHz == p.frequencyHz) {
        if (resolved.last.correctionDb == p.correctionDb) {
          warnings.add(
              'Duplicate frequency ${p.frequencyHz} Hz with identical correction — collapsed.');
          continue;
        }
        errors.add(
            'Frequency ${p.frequencyHz} Hz has conflicting correction values '
            '(${resolved.last.correctionDb} dB vs ${p.correctionDb} dB).');
        conflictFound = true;
        continue;
      }
      resolved.add(p);
    }

    if (conflictFound) {
      return CalibrationParseResult(
        errors: errors,
        warnings: warnings,
        sourceChecksum: sourceChecksum,
        detectedAngle: detectedAngle,
        detectedSensitivityNote: detectedSensitivityNote,
      );
    }

    if (resolved.length < 2) {
      errors.add(resolved.isEmpty
          ? 'No valid calibration data rows found.'
          : 'Only ${resolved.length} valid distinct frequency — need at least 2.');
      return CalibrationParseResult(
        errors: errors,
        warnings: warnings,
        sourceChecksum: sourceChecksum,
        detectedAngle: detectedAngle,
        detectedSensitivityNote: detectedSensitivityNote,
      );
    }

    final curve = CalibrationCurve(
      points: List.unmodifiable(resolved),
      angle: detectedAngle,
      validMinFrequencyHz: resolved.first.frequencyHz,
      validMaxFrequencyHz: resolved.last.frequencyHz,
      sourceIdentity: sourceIdentity ?? 'unknown',
      checksum: CalibrationCurve.checksumFor(resolved),
      parserWarnings: List.unmodifiable(warnings),
    );

    return CalibrationParseResult(
      curve: curve,
      errors: errors,
      warnings: warnings,
      sourceChecksum: sourceChecksum,
      detectedAngle: detectedAngle,
      detectedSensitivityNote: detectedSensitivityNote,
    );
  }
}
