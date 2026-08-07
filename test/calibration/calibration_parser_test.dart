// Phase 3-B — calibration_parser.dart pure text-parsing tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_parser.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';

void main() {
  group('CalibrationFileParser.parse — happy path', () {
    test('parses whitespace-separated frequency/correction pairs', () {
      final result = CalibrationFileParser.parse(content: '''
20 0.5
1000 0.0
20000 -1.0
''');
      expect(result.isSuccess, isTrue);
      expect(result.curve!.points.length, 3);
      expect(result.curve!.validMinFrequencyHz, 20);
      expect(result.curve!.validMaxFrequencyHz, 20000);
    });

    test('parses comma-separated and tab-separated rows', () {
      final commaResult =
          CalibrationFileParser.parse(content: '20,0.5\n1000,0.0');
      expect(commaResult.isSuccess, isTrue);

      final tabResult =
          CalibrationFileParser.parse(content: '20\t0.5\n1000\t0.0');
      expect(tabResult.isSuccess, isTrue);
    });

    test('skips a header row and still parses the data', () {
      final result = CalibrationFileParser.parse(content: '''
Frequency,Correction
20,0.5
1000,0.0
''');
      expect(result.isSuccess, isTrue);
      expect(result.curve!.points.length, 2);
      expect(result.warnings.any((w) => w.contains('header')), isTrue);
    });

    test('ignores blank lines', () {
      final result = CalibrationFileParser.parse(content: '''
20 0.5

1000 0.0
''');
      expect(result.isSuccess, isTrue);
      expect(result.curve!.points.length, 2);
    });
  });

  group('CalibrationFileParser.parse — comment handling', () {
    test('# and ; and // lines are comments, not data', () {
      final result = CalibrationFileParser.parse(content: '''
# leading comment
; another comment
// yet another
20 0.5
1000 0.0
''');
      expect(result.isSuccess, isTrue);
      expect(result.curve!.points.length, 2);
    });

    test(
        'a leading * is NOT a comment marker (differs from FrdParser) — it '
        'is treated as a non-numeric first row (header-like) and skipped, '
        'not silently consumed as a comment', () {
      final result = CalibrationFileParser.parse(content: '''
* not a comment here
20 0.5
1000 0.0
''');
      expect(result.isSuccess, isTrue);
      expect(result.curve!.points.length, 2);
      expect(result.warnings, isNotEmpty);
    });

    test('semicolon is the comment marker, not a column separator', () {
      // "20;0.5" is a comment line (starts with none, but the whole line
      // does not start with ';' here) -- verify a genuine leading-semicolon
      // comment line is skipped entirely, not parsed as columns.
      final result = CalibrationFileParser.parse(content: '''
;20;0.5
1000 0.0
20000 -1.0
''');
      expect(result.isSuccess, isTrue);
      expect(result.curve!.points.length, 2);
    });
  });

  group('CalibrationFileParser.parse — angle detection', () {
    test('detects "0 degree" / "90 deg" style metadata in comments', () {
      final zero = CalibrationFileParser.parse(content: '''
# calibration angle: 0 degree
20 0.5
1000 0.0
''');
      expect(zero.detectedAngle, CalibrationAngle.zeroDegree);

      final ninety = CalibrationFileParser.parse(content: '''
# measured at 90deg
20 0.5
1000 0.0
''');
      expect(ninety.detectedAngle, CalibrationAngle.ninetyDegree);
    });

    test('unspecified when no angle metadata is present', () {
      final result = CalibrationFileParser.parse(content: '20 0.5\n1000 0');
      expect(result.detectedAngle, CalibrationAngle.unspecified);
    });
  });

  group(
      'CalibrationFileParser.parse — sensitivity detection (informational '
      'only)', () {
    test(
        'captures a sensitivity line verbatim, never parses it into a '
        'number', () {
      final result = CalibrationFileParser.parse(content: '''
# Sensitivity: -38.5 dBV
20 0.5
1000 0.0
''');
      expect(result.detectedSensitivityNote, contains('Sensitivity'));
    });
  });

  group('CalibrationFileParser.parse — sanity bounds', () {
    test(
        'rejects a correction beyond +/-20dB with a skip warning, but '
        'still succeeds if enough other rows are valid', () {
      final result = CalibrationFileParser.parse(content: '''
20 0.5
500 99.0
1000 0.0
''');
      expect(result.isSuccess, isTrue);
      expect(result.curve!.points.length, 2);
      expect(result.warnings.any((w) => w.contains('sanity bound')), isTrue);
    });

    test('rejects zero/negative frequency rows', () {
      final result = CalibrationFileParser.parse(content: '''
0 0.5
-100 0.2
20 0.5
1000 0.0
''');
      expect(result.isSuccess, isTrue);
      expect(result.curve!.points.length, 2);
    });
  });

  group('CalibrationFileParser.parse — duplicate frequency resolution', () {
    test(
        'collapses duplicate rows with identical correction, with a '
        'warning', () {
      final result = CalibrationFileParser.parse(content: '''
20 0.5
20 0.5
1000 0.0
''');
      expect(result.isSuccess, isTrue);
      expect(result.curve!.points.length, 2);
      expect(result.warnings.any((w) => w.contains('collapsed')), isTrue);
    });

    test('fails the whole parse on conflicting duplicate frequency', () {
      final result = CalibrationFileParser.parse(content: '''
20 0.5
20 0.8
1000 0.0
''');
      expect(result.isSuccess, isFalse);
      expect(result.curve, isNull);
      expect(result.errors.any((e) => e.contains('conflicting')), isTrue);
    });
  });

  group('CalibrationFileParser.parse — insufficient data', () {
    test('fails with fewer than 2 valid distinct points', () {
      final empty = CalibrationFileParser.parse(content: '# nothing here');
      expect(empty.isSuccess, isFalse);
      expect(empty.errors.any((e) => e.contains('No valid')), isTrue);

      final onePoint = CalibrationFileParser.parse(content: '20 0.5');
      expect(onePoint.isSuccess, isFalse);
      expect(onePoint.errors.any((e) => e.contains('at least 2')), isTrue);
    });
  });

  group('CalibrationFileParser.parse — provenance', () {
    test('sourceChecksum is deterministic for identical content', () {
      const content = '20 0.5\n1000 0.0';
      final a = CalibrationFileParser.parse(content: content);
      final b = CalibrationFileParser.parse(content: content);
      expect(a.sourceChecksum, b.sourceChecksum);
    });

    test('curve carries the caller-supplied sourceIdentity', () {
      final result = CalibrationFileParser.parse(
          content: '20 0.5\n1000 0.0', sourceIdentity: 'my_mic.cal');
      expect(result.curve!.sourceIdentity, 'my_mic.cal');
    });

    test('result curve is structurally valid and points are ascending', () {
      final result = CalibrationFileParser.parse(content: '''
1000 0.0
20 0.5
20000 -1.0
''');
      expect(result.curve!.isStructurallyValid, isTrue);
      final freqs = result.curve!.points.map((p) => p.frequencyHz).toList();
      expect(freqs, [20, 1000, 20000]);
    });
  });
}
