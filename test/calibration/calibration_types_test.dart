// Phase 3-B — calibration_types.dart pure model tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';

CalibrationCurve _curve({
  List<CalibrationPoint>? points,
  String sourceIdentity = 'test.txt',
}) {
  final pts = points ??
      const [
        CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
        CalibrationPoint(frequencyHz: 1000, correctionDb: 0.0),
        CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
      ];
  return CalibrationCurve(
    points: pts,
    validMinFrequencyHz: pts.first.frequencyHz,
    validMaxFrequencyHz: pts.last.frequencyHz,
    sourceIdentity: sourceIdentity,
    checksum: CalibrationCurve.checksumFor(pts),
  );
}

void main() {
  group('CalibrationPoint.isPlausible', () {
    test('true for a normal correction value', () {
      expect(
          const CalibrationPoint(frequencyHz: 1000, correctionDb: 1.5)
              .isPlausible,
          isTrue);
    });

    test('false for non-finite frequency or correction', () {
      expect(
          const CalibrationPoint(frequencyHz: double.nan, correctionDb: 0)
              .isPlausible,
          isFalse);
      expect(
          const CalibrationPoint(
                  frequencyHz: 1000, correctionDb: double.infinity)
              .isPlausible,
          isFalse);
    });

    test('false for zero or negative frequency', () {
      expect(
          const CalibrationPoint(frequencyHz: 0, correctionDb: 0).isPlausible,
          isFalse);
      expect(
          const CalibrationPoint(frequencyHz: -10, correctionDb: 0).isPlausible,
          isFalse);
    });

    test('false for correction beyond the +/-20dB sanity bound', () {
      expect(
          const CalibrationPoint(frequencyHz: 1000, correctionDb: 20.001)
              .isPlausible,
          isFalse);
      expect(
          const CalibrationPoint(frequencyHz: 1000, correctionDb: -20.001)
              .isPlausible,
          isFalse);
      // exactly at the bound is still plausible
      expect(
          const CalibrationPoint(frequencyHz: 1000, correctionDb: 20.0)
              .isPlausible,
          isTrue);
    });
  });

  group('CalibrationCurve.isStructurallyValid', () {
    test('true for a well-formed ascending curve', () {
      expect(_curve().isStructurallyValid, isTrue);
    });

    test('false with fewer than 2 points', () {
      const curve = CalibrationCurve(
        points: [CalibrationPoint(frequencyHz: 100, correctionDb: 0)],
        validMinFrequencyHz: 100,
        validMaxFrequencyHz: 100,
        sourceIdentity: 'x',
        checksum: 'x',
      );
      expect(curve.isStructurallyValid, isFalse);
    });

    test('false when points are not strictly ascending', () {
      final curve = _curve(points: const [
        CalibrationPoint(frequencyHz: 1000, correctionDb: 0),
        CalibrationPoint(frequencyHz: 500, correctionDb: 1),
      ]);
      expect(curve.isStructurallyValid, isFalse);
    });

    test('false on duplicate frequency', () {
      final curve = _curve(points: const [
        CalibrationPoint(frequencyHz: 1000, correctionDb: 0),
        CalibrationPoint(frequencyHz: 1000, correctionDb: 1),
      ]);
      expect(curve.isStructurallyValid, isFalse);
    });

    test('false when validMax <= validMin', () {
      const curve = CalibrationCurve(
        points: [
          CalibrationPoint(frequencyHz: 100, correctionDb: 0),
          CalibrationPoint(frequencyHz: 200, correctionDb: 1),
        ],
        validMinFrequencyHz: 500,
        validMaxFrequencyHz: 500,
        sourceIdentity: 'x',
        checksum: 'x',
      );
      expect(curve.isStructurallyValid, isFalse);
    });

    test('false when an implausible point is present', () {
      final curve = _curve(points: const [
        CalibrationPoint(frequencyHz: 100, correctionDb: 0),
        CalibrationPoint(frequencyHz: 200, correctionDb: 99),
      ]);
      expect(curve.isStructurallyValid, isFalse);
    });
  });

  group('CalibrationCurve.checksumFor', () {
    test('is deterministic for the same points', () {
      const pts = [
        CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
        CalibrationPoint(frequencyHz: 1000, correctionDb: 0.0),
      ];
      expect(
          CalibrationCurve.checksumFor(pts), CalibrationCurve.checksumFor(pts));
    });

    test('differs when a correction value changes', () {
      const a = [CalibrationPoint(frequencyHz: 20, correctionDb: 0.5)];
      const b = [CalibrationPoint(frequencyHz: 20, correctionDb: 0.6)];
      expect(CalibrationCurve.checksumFor(a),
          isNot(CalibrationCurve.checksumFor(b)));
    });
  });

  group('CalibrationCurve JSON round-trip', () {
    test('toJson -> fromJson preserves points/angle/checksum/range', () {
      final curve = _curve();
      final decoded = CalibrationCurve.fromJson(curve.toJson());
      expect(decoded.points.length, curve.points.length);
      expect(decoded.checksum, curve.checksum);
      expect(decoded.angle, curve.angle);
      expect(decoded.validMinFrequencyHz, curve.validMinFrequencyHz);
      expect(decoded.validMaxFrequencyHz, curve.validMaxFrequencyHz);
      expect(decoded.sourceIdentity, curve.sourceIdentity);
    });

    test('fromJson on missing fields falls back safely (never throws)', () {
      final decoded = CalibrationCurve.fromJson(const {});
      expect(decoded.points, isEmpty);
      expect(decoded.angle, CalibrationAngle.unspecified);
      expect(decoded.isStructurallyValid, isFalse);
    });
  });

  group('MeasurementMicrophoneProfile', () {
    final now = DateTime.utc(2026, 1, 1);

    test(
        'hasUsableCalibration requires both a non-uncalibrated source AND '
        'a curve', () {
      final withCurve = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.manufacturerFile,
        calibrationCurve: _curve(),
        createdAt: now,
        updatedAt: now,
      );
      expect(withCurve.hasUsableCalibration, isTrue);

      final sourceOnly = withCurve.copyWith(clearCalibrationCurve: true);
      expect(sourceOnly.hasUsableCalibration, isFalse);

      final uncalibrated = MeasurementMicrophoneProfile(
        id: 'mic2',
        manufacturer: 'ACME',
        model: 'M2',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.uncalibrated,
        calibrationCurve: _curve(),
        createdAt: now,
        updatedAt: now,
      );
      expect(uncalibrated.hasUsableCalibration, isFalse);
    });

    test(
        'checksum changes when a meaning-affecting field changes, but not '
        'when only updatedAt changes', () {
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.uncalibrated,
        createdAt: now,
        updatedAt: now,
      );
      final touchedTimestampOnly =
          profile.copyWith(updatedAt: now.add(const Duration(days: 1)));
      expect(touchedTimestampOnly.checksum, profile.checksum);

      final renamed = profile.copyWith(model: 'M2');
      expect(renamed.checksum, isNot(profile.checksum));
    });

    test('JSON round-trip preserves calibration curve', () {
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.userImported,
        calibrationCurve: _curve(),
        createdAt: now,
        updatedAt: now,
      );
      final decoded = MeasurementMicrophoneProfile.fromJson(profile.toJson());
      expect(decoded.checksum, profile.checksum);
      expect(decoded.calibrationCurve?.checksum,
          profile.calibrationCurve?.checksum);
    });
  });

  group('MeasurementMicrophoneSnapshot.of', () {
    test('embeds the curve itself, not just a reference', () {
      final now = DateTime.utc(2026, 1, 1);
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.manufacturerFile,
        calibrationCurve: _curve(),
        createdAt: now,
        updatedAt: now,
      );
      final snapshot =
          MeasurementMicrophoneSnapshot.of(profile, sampleRate: 48000);
      expect(snapshot.calibrationCurve, isNotNull);
      expect(snapshot.calibrationCurve!.checksum,
          profile.calibrationCurve!.checksum);
      expect(snapshot.profileChecksum, profile.checksum);

      // Editing the profile afterwards must not retroactively change the
      // already-taken snapshot.
      final edited = profile.copyWith(model: 'M2-edited');
      expect(snapshot.model, 'M1');
      expect(edited.checksum, isNot(snapshot.profileChecksum));
    });

    test('JSON round-trip preserves everything needed to re-apply', () {
      final now = DateTime.utc(2026, 1, 1);
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.manufacturerFile,
        calibrationCurve: _curve(),
        createdAt: now,
        updatedAt: now,
      );
      final snapshot = MeasurementMicrophoneSnapshot.of(profile,
          sampleRate: 48000, capturedAt: now);
      final decoded = MeasurementMicrophoneSnapshot.fromJson(snapshot.toJson());
      expect(decoded.profileId, snapshot.profileId);
      expect(decoded.profileChecksum, snapshot.profileChecksum);
      expect(decoded.calibrationCurve?.checksum,
          snapshot.calibrationCurve?.checksum);
      expect(decoded.sampleRate, snapshot.sampleRate);
    });
  });
}
