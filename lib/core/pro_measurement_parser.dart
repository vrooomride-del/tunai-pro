// ── TUNAI PRO Phase M — FRD / ZMA Text Parser ────────────────────────────────
// Parses whitespace-delimited acoustic measurement text files.
// No hardware write. No DSP addresses. Data-layer only.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_acoustic_data.dart';

// ── Comment / blank detection ─────────────────────────────────────────────────

bool _isComment(String line) {
  final t = line.trimLeft();
  return t.startsWith('#') ||
      t.startsWith('*') ||
      t.startsWith(';') ||
      t.startsWith('//');
}

bool _isSkippable(String line) => line.trim().isEmpty || _isComment(line);

// ── Token parser helper ───────────────────────────────────────────────────────

double? _parseNum(String s) {
  final v = double.tryParse(s);
  if (v == null || !v.isFinite) return null;
  return v;
}

// ── Public parser class ───────────────────────────────────────────────────────

class ProMeasurementParser {
  ProMeasurementParser._();

  /// Parse FRD text content.
  ///
  /// Expected columns: frequency [Hz]  magnitude [dB]  [phase [deg]]
  static MeasurementParseResult parseFrd({
    required String fileName,
    required String content,
  }) {
    return _parse(
      fileName: fileName,
      content: content,
      fileType: AcousticFileType.frd,
      columnParser: _parseFrdRow,
      minColumns: 2,
      dataLabel: 'FRD',
    );
  }

  /// Parse ZMA text content.
  ///
  /// Expected columns: frequency [Hz]  impedance [Ω]  [phase [deg]]
  static MeasurementParseResult parseZma({
    required String fileName,
    required String content,
  }) {
    return _parse(
      fileName: fileName,
      content: content,
      fileType: AcousticFileType.zma,
      columnParser: _parseZmaRow,
      minColumns: 2,
      dataLabel: 'ZMA',
    );
  }

  // ── Internal generic parser ───────────────────────────────────────────────

  static MeasurementParseResult _parse({
    required String fileName,
    required String content,
    required AcousticFileType fileType,
    required MeasurementDataPoint? Function(List<String> tokens, int lineNo,
            List<String> warnings)
        columnParser,
    required int minColumns,
    required String dataLabel,
  }) {
    try {
      final warnings = <String>[];
      final errors = <String>[];
      final points = <MeasurementDataPoint>[];
      int skipped = 0;

      final lines = content.split(RegExp(r'\r?\n'));

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (_isSkippable(line)) continue;

        final tokens = line.trim().split(RegExp(r'[\s,\t]+'))
          ..removeWhere((t) => t.isEmpty);

        if (tokens.length < minColumns) {
          skipped++;
          warnings.add('Line ${i + 1}: too few columns (${tokens.length}) — skipped.');
          continue;
        }

        final pt = columnParser(tokens, i + 1, warnings);
        if (pt == null) {
          skipped++;
          continue;
        }

        if (pt.frequencyHz <= 0) {
          skipped++;
          warnings.add('Line ${i + 1}: frequency ≤ 0 Hz — skipped.');
          continue;
        }

        points.add(pt);
      }

      if (points.length < 2) {
        final reason = points.isEmpty
            ? 'No valid data rows found.'
            : 'Only ${points.length} valid point — need at least 2.';
        errors.add(reason);
        return MeasurementParseResult(
          status: MeasurementParseStatus.failed,
          warnings: warnings,
          errors: errors,
          summary: '$dataLabel parse failed: $reason',
        );
      }

      // Sort ascending by frequency
      points.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));

      // Duplicate frequency check
      final seen = <double>{};
      for (final pt in points) {
        if (!seen.add(pt.frequencyHz)) {
          warnings.add('Duplicate frequency ${pt.frequencyHz} Hz — keeping all occurrences.');
        }
      }

      if (skipped > 0) {
        warnings.add('$skipped row(s) skipped due to invalid data.');
      }

      final id = '${fileType.name}_${DateTime.now().millisecondsSinceEpoch}';
      final data = ParsedMeasurementData(
        id: id,
        sourceFileName: fileName,
        fileType: fileType,
        importedAt: DateTime.now(),
        points: points,
        warning: warnings.isNotEmpty ? warnings.first : null,
      );

      final status = warnings.isEmpty
          ? MeasurementParseStatus.parsed
          : MeasurementParseStatus.parsedWithWarnings;

      return MeasurementParseResult(
        status: status,
        data: data,
        warnings: warnings,
        errors: errors,
        summary: '$dataLabel parsed: ${points.length} points  '
            '${_hzLabel(data.minFrequencyHz)} – ${_hzLabel(data.maxFrequencyHz)}'
            '${data.hasMagnitude ? "  mag" : ""}${data.hasPhase ? "+phase" : ""}'
            '${data.hasImpedance ? "  Z" : ""}${data.hasImpedance && data.points.any((p) => p.impedancePhaseDeg != null) ? "+phase" : ""}',
      );
    } catch (e) {
      return MeasurementParseResult(
        status: MeasurementParseStatus.failed,
        warnings: const [],
        errors: ['Unexpected parse error: $e'],
        summary: 'Parse failed due to unexpected error.',
      );
    }
  }

  // ── FRD row parser ────────────────────────────────────────────────────────

  static MeasurementDataPoint? _parseFrdRow(
      List<String> tokens, int lineNo, List<String> warnings) {
    final freq = _parseNum(tokens[0]);
    final mag = _parseNum(tokens[1]);

    if (freq == null) {
      warnings.add('Line $lineNo: invalid frequency "${tokens[0]}" — skipped.');
      return null;
    }
    if (mag == null) {
      warnings.add('Line $lineNo: invalid magnitude "${tokens[1]}" — skipped.');
      return null;
    }

    double? phase;
    if (tokens.length >= 3) {
      phase = _parseNum(tokens[2]);
      if (phase == null) {
        warnings.add('Line $lineNo: invalid phase "${tokens[2]}" — ignored.');
      }
    }

    return MeasurementDataPoint(
      frequencyHz: freq,
      magnitudeDb: mag,
      phaseDeg: phase,
    );
  }

  // ── ZMA row parser ────────────────────────────────────────────────────────

  static MeasurementDataPoint? _parseZmaRow(
      List<String> tokens, int lineNo, List<String> warnings) {
    final freq = _parseNum(tokens[0]);
    final imp = _parseNum(tokens[1]);

    if (freq == null) {
      warnings.add('Line $lineNo: invalid frequency "${tokens[0]}" — skipped.');
      return null;
    }
    if (imp == null) {
      warnings.add('Line $lineNo: invalid impedance "${tokens[1]}" — skipped.');
      return null;
    }

    double? phase;
    if (tokens.length >= 3) {
      phase = _parseNum(tokens[2]);
      if (phase == null) {
        warnings.add('Line $lineNo: invalid impedance phase "${tokens[2]}" — ignored.');
      }
    }

    return MeasurementDataPoint(
      frequencyHz: freq,
      impedanceOhm: imp,
      impedancePhaseDeg: phase,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _hzLabel(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)} kHz' : '${v.toStringAsFixed(0)} Hz';
}
