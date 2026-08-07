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

    test(
        'checksum changes when the calibration curve\'s ORIENTATION alone '
        'changes — CalibrationCurve.checksum hashes points only, so the '
        'profile checksum must fold in angle separately or a stale-preview '
        'guard comparing profile checksums would miss an orientation-only '
        'edit', () {
      final points = [
        const CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
        const CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
      ];
      final curveUnspecified = CalibrationCurve(
        points: points,
        angle: CalibrationAngle.unspecified,
        validMinFrequencyHz: 20,
        validMaxFrequencyHz: 20000,
        sourceIdentity: 'test',
        checksum: CalibrationCurve.checksumFor(points),
      );
      final curveZeroDeg = CalibrationCurve(
        points: points,
        angle: CalibrationAngle.zeroDegree,
        validMinFrequencyHz: 20,
        validMaxFrequencyHz: 20000,
        sourceIdentity: 'test',
        checksum: CalibrationCurve.checksumFor(points),
      );
      // The curve-level checksum is identical (points-only hash) — this is
      // the exact trap the profile checksum must not fall into.
      expect(curveUnspecified.checksum, curveZeroDeg.checksum);

      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.userImported,
        calibrationCurve: curveUnspecified,
        createdAt: now,
        updatedAt: now,
      );
      final reoriented = profile.copyWith(calibrationCurve: curveZeroDeg);
      expect(reoriented.checksum, isNot(profile.checksum));
    });

    test('checksum changes when serialNumber alone changes', () {
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        serialNumber: 'SN-1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.uncalibrated,
        createdAt: now,
        updatedAt: now,
      );
      final resernaled = profile.copyWith(serialNumber: 'SN-2');
      expect(resernaled.checksum, isNot(profile.checksum));
    });

    test('checksum changes when inputDeviceId alone changes', () {
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        inputDeviceId: 'device-a',
        calibrationSource: CalibrationSource.uncalibrated,
        createdAt: now,
        updatedAt: now,
      );
      final moved = profile.copyWith(inputDeviceId: 'device-b');
      expect(moved.checksum, isNot(profile.checksum));
    });

    test('checksum changes when calibrationSource alone changes', () {
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
      final resourced = profile.copyWith(
          calibrationSource: CalibrationSource.manufacturerFile);
      expect(resourced.checksum, isNot(profile.checksum));
    });

    test(
        'checksum changes when the calibration curve\'s POINTS change '
        '(re-imported file)', () {
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
      const newPoints = [
        CalibrationPoint(frequencyHz: 20, correctionDb: 2.0),
        CalibrationPoint(frequencyHz: 20000, correctionDb: -2.0),
      ];
      final newCurve = CalibrationCurve(
        points: newPoints,
        validMinFrequencyHz: 20,
        validMaxFrequencyHz: 20000,
        sourceIdentity: 'test2',
        checksum: CalibrationCurve.checksumFor(newPoints),
      );
      final reimported = profile.copyWith(calibrationCurve: newCurve);
      expect(reimported.checksum, isNot(profile.checksum));
    });

    test(
        'checksum changes when sensitivityMvPa or splReferenceDb alone '
        'changes', () {
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.uncalibrated,
        sensitivityMvPa: 10.0,
        splReferenceDb: 94.0,
        createdAt: now,
        updatedAt: now,
      );
      expect(profile.copyWith(sensitivityMvPa: 20.0).checksum,
          isNot(profile.checksum));
      expect(profile.copyWith(splReferenceDb: 104.0).checksum,
          isNot(profile.checksum));
    });

    test(
        'checksum is UNCHANGED by display/audit-only curve metadata — '
        'sourceIdentity and parserWarnings never affect what correction is '
        'actually applied, so they are deliberately excluded (this is the '
        'closest analog to a "notes-only" field on this type — '
        'MeasurementMicrophoneProfile has no separate notes field)', () {
      const points = [
        CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
        CalibrationPoint(frequencyHz: 20000, correctionDb: -1.0),
      ];
      final curveA = CalibrationCurve(
        points: points,
        validMinFrequencyHz: 20,
        validMaxFrequencyHz: 20000,
        sourceIdentity: 'file_a.cal',
        checksum: CalibrationCurve.checksumFor(points),
        parserWarnings: const ['warning A'],
      );
      final curveB = CalibrationCurve(
        points: points,
        validMinFrequencyHz: 20,
        validMaxFrequencyHz: 20000,
        sourceIdentity: 'file_b.cal',
        checksum: CalibrationCurve.checksumFor(points),
        parserWarnings: const ['different warning B', 'and another'],
      );
      final profile = MeasurementMicrophoneProfile(
        id: 'mic1',
        manufacturer: 'ACME',
        model: 'M1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.userImported,
        calibrationCurve: curveA,
        createdAt: now,
        updatedAt: now,
      );
      final relabeled = profile.copyWith(calibrationCurve: curveB);
      expect(relabeled.checksum, profile.checksum);
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
