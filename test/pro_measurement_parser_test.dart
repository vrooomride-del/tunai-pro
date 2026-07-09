// TUNAI PRO — Phase M: FRD / ZMA parser tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_measurement_parser.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';

void main() {
  // ── FRD parsing ────────────────────────────────────────────────────────────

  group('FRD parser — basic cases', () {
    test('parses basic FRD with frequency magnitude phase', () {
      const content = '''
20    -3.2   180.0
100    0.1    90.5
1000   2.5    45.0
10000 -1.0   -30.0
20000 -8.5  -120.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.status, MeasurementParseStatus.parsed);
      expect(result.data, isNotNull);
      expect(result.data!.pointCount, 5);
      expect(result.data!.hasMagnitude, isTrue);
      expect(result.data!.hasPhase, isTrue);
      expect(result.data!.hasImpedance, isFalse);
    });

    test('parses FRD with frequency magnitude only (no phase)', () {
      const content = '''
20    -3.2
100    0.1
1000   2.5
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.status, MeasurementParseStatus.parsed);
      expect(result.data!.hasMagnitude, isTrue);
      expect(result.data!.hasPhase, isFalse);
      expect(result.data!.pointCount, 3);
    });

    test('ignores comments starting with #', () {
      const content = '''
# This is a comment
20    -3.2   180.0
100    0.1    90.5
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.data!.pointCount, 2);
    });

    test('ignores comments starting with *', () {
      const content = '''
* REW export
* Version 5
20    -3.2   180.0
1000   2.5    45.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.data!.pointCount, 2);
    });

    test('ignores comments starting with ;', () {
      const content = '''
; arta file
100    0.1    90.5
1000   2.5    45.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.data!.pointCount, 2);
    });

    test('ignores comments starting with //', () {
      const content = '''
// frequency response
100    0.1    90.5
1000   2.5    45.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.data!.pointCount, 2);
    });

    test('ignores blank lines', () {
      const content = '''

20    -3.2   180.0

1000   2.5    45.0

''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.data!.pointCount, 2);
    });

    test('skips invalid rows with warnings (non-numeric token)', () {
      const content = '''
20    -3.2   180.0
bad   data   here
1000   2.5    45.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.status, MeasurementParseStatus.parsedWithWarnings);
      expect(result.data!.pointCount, 2);
      expect(result.warnings, isNotEmpty);
    });

    test('fails gracefully with fewer than 2 valid rows', () {
      const content = '''
# only comments
# and blanks

''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.status, MeasurementParseStatus.failed);
      expect(result.data, isNull);
      expect(result.errors, isNotEmpty);
    });

    test('fails when only one valid data row', () {
      const content = '1000  2.5  45.0\n';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.status, MeasurementParseStatus.failed);
    });

    test('sorts frequencies ascending', () {
      const content = '''
20000  -8.5  -120.0
1000    2.5    45.0
100     0.1    90.5
20     -3.2   180.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.status, MeasurementParseStatus.parsed);
      final freqs = result.data!.points.map((p) => p.frequencyHz).toList();
      expect(freqs, equals([20.0, 100.0, 1000.0, 20000.0]));
    });

    test('warns on duplicate frequency but keeps points', () {
      const content = '''
1000   2.5    45.0
1000   3.0    50.0
2000   1.0    20.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.data!.pointCount, 3);
      final hasWarn = result.warnings
          .any((w) => w.toLowerCase().contains('duplicate'));
      expect(hasWarn, isTrue);
    });

    test('skips rows with frequency <= 0', () {
      const content = '''
-20    -3.2   180.0
0      0.0     0.0
1000   2.5    45.0
2000   1.0    20.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.data!.pointCount, 2);
    });

    test('FRD data fields are correct', () {
      const content = '100  -2.5  45.0\n200  1.0  30.0\n';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'woofer.frd', content: content);
      expect(result.data!.sourceFileName, 'woofer.frd');
      expect(result.data!.fileType, AcousticFileType.frd);
      expect(result.data!.points.first.frequencyHz, 100.0);
      expect(result.data!.points.first.magnitudeDb, -2.5);
      expect(result.data!.points.first.phaseDeg, 45.0);
    });

    test('minFrequencyHz and maxFrequencyHz computed correctly', () {
      const content = '''
100   0.0  0.0
500   1.0  10.0
8000  2.0  20.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.data!.minFrequencyHz, 100.0);
      expect(result.data!.maxFrequencyHz, 8000.0);
    });
  });

  // ── ZMA parsing ────────────────────────────────────────────────────────────

  group('ZMA parser', () {
    test('parses ZMA with frequency impedance phase', () {
      const content = '''
# impedance data
20     8.0   -30.0
100    6.5    12.0
1000  10.2    45.0
5000   4.8   -20.0
''';
      final result = ProMeasurementParser.parseZma(
          fileName: 'test.zma', content: content);
      expect(result.status, MeasurementParseStatus.parsed);
      expect(result.data!.pointCount, 4);
      expect(result.data!.hasImpedance, isTrue);
      expect(result.data!.hasMagnitude, isFalse);
    });

    test('parses ZMA with frequency impedance only (no phase)', () {
      const content = '''
100   8.0
1000  6.5
''';
      final result = ProMeasurementParser.parseZma(
          fileName: 'test.zma', content: content);
      expect(result.status, MeasurementParseStatus.parsed);
      expect(result.data!.hasImpedance, isTrue);
      expect(result.data!.points.first.impedancePhaseDeg, isNull);
    });

    test('ZMA points have impedanceOhm set', () {
      const content = '100  8.0  -5.0\n500  12.4  10.0\n';
      final result = ProMeasurementParser.parseZma(
          fileName: 'imp.zma', content: content);
      expect(result.data!.points.first.impedanceOhm, 8.0);
      expect(result.data!.points.first.impedancePhaseDeg, -5.0);
    });

    test('ZMA fails on empty content', () {
      final result = ProMeasurementParser.parseZma(
          fileName: 'test.zma', content: '');
      expect(result.status, MeasurementParseStatus.failed);
    });

    test('ZMA sorts frequencies ascending', () {
      const content = '''
5000   4.8   -20.0
100    6.5    12.0
20     8.0   -30.0
''';
      final result = ProMeasurementParser.parseZma(
          fileName: 'test.zma', content: content);
      final freqs = result.data!.points.map((p) => p.frequencyHz).toList();
      expect(freqs, equals([20.0, 100.0, 5000.0]));
    });
  });

  // ── Edge cases ─────────────────────────────────────────────────────────────

  group('Parser safety', () {
    test('rejects NaN values safely', () {
      const content = '''
100   NaN  45.0
200   1.0  45.0
300   2.0  30.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      // NaN row should be skipped or cause warning
      expect(result.data!.pointCount, 2);
    });

    test('handles very large values without crashing', () {
      const content = '''
100   1e30   45.0
200   1.0    30.0
300   2.0    20.0
''';
      // Should parse — 1e30 is finite even if extreme
      final result = ProMeasurementParser.parseFrd(
          fileName: 'test.frd', content: content);
      expect(result.data, isNotNull);
    });

    test('parsing never throws on garbage input', () {
      const garbage = 'not a file at all\n@@@@\n####\n';
      expect(
        () => ProMeasurementParser.parseFrd(
            fileName: 'garbage.frd', content: garbage),
        returnsNormally,
      );
    });

    test('parsing never throws on empty string', () {
      expect(
        () => ProMeasurementParser.parseFrd(
            fileName: 'empty.frd', content: ''),
        returnsNormally,
      );
    });

    test('Windows line endings (CRLF) handled correctly', () {
      const content = '100\t0.0\t90.0\r\n1000\t1.0\t45.0\r\n';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'win.frd', content: content);
      expect(result.data!.pointCount, 2);
    });

    test('tab-separated values parse correctly', () {
      const content = '100\t-2.5\t45.0\n1000\t1.0\t30.0\n';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'tab.frd', content: content);
      expect(result.data!.pointCount, 2);
      expect(result.data!.points.first.frequencyHz, 100.0);
    });
  });

  // ── JSON round-trip ────────────────────────────────────────────────────────

  group('ParsedMeasurementData JSON round-trip', () {
    test('round-trips all fields correctly', () {
      const content = '''
100   -2.5   45.0
1000   1.0   30.0
10000 -3.0  -15.0
''';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'round_trip.frd', content: content);
      final data = result.data!;
      final json = data.toJson();
      final restored = ParsedMeasurementData.fromJson(json);

      expect(restored.id, data.id);
      expect(restored.sourceFileName, data.sourceFileName);
      expect(restored.fileType, data.fileType);
      expect(restored.pointCount, data.pointCount);
      expect(restored.hasMagnitude, data.hasMagnitude);
      expect(restored.hasPhase, data.hasPhase);
      expect(restored.points.first.frequencyHz,
          data.points.first.frequencyHz);
      expect(restored.points.first.magnitudeDb,
          data.points.first.magnitudeDb);
      expect(restored.points.first.phaseDeg,
          data.points.first.phaseDeg);
    });

    test('JSON contains no hardware address fields', () {
      const content = '100  0.0  0.0\n1000  1.0  10.0\n';
      final result = ProMeasurementParser.parseFrd(
          fileName: 'hw_check.frd', content: content);
      final jsonStr = result.data!.toJson().toString().toLowerCase();
      expect(jsonStr, isNot(contains('safeload')));
      expect(jsonStr, isNot(contains('0x')));
      expect(jsonStr, isNot(contains('register')));
      expect(jsonStr, isNot(contains('eeprom')));
      expect(jsonStr, isNot(contains('usbi')));
    });
  });
}
