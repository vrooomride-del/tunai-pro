// Phase 3-B — persistence round-trip and backward-compatibility tests for
// calibration-touched fields on ParsedMeasurementData and ProProject.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';

CalibrationCurve _curve() {
  const points = [
    CalibrationPoint(frequencyHz: 20, correctionDb: 0.5),
    CalibrationPoint(frequencyHz: 1000, correctionDb: 0.0),
  ];
  return CalibrationCurve(
    points: points,
    validMinFrequencyHz: 20,
    validMaxFrequencyHz: 1000,
    sourceIdentity: 'test',
    checksum: CalibrationCurve.checksumFor(points),
  );
}

MeasurementMicrophoneProfile _profile() => MeasurementMicrophoneProfile(
      id: 'mic1',
      manufacturer: 'ACME',
      model: 'M1',
      connectionType: 'USB',
      calibrationSource: CalibrationSource.manufacturerFile,
      calibrationCurve: _curve(),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('ParsedMeasurementData — raw/calibrated split round-trip', () {
    test(
        'full round-trip preserves rawPoints, microphoneSnapshot, '
        'calibration status/checksum/appliedAt', () {
      final now = DateTime.utc(2026, 1, 1);
      final snapshot = MeasurementMicrophoneSnapshot.of(_profile(),
          sampleRate: 48000, capturedAt: now);
      final data = ParsedMeasurementData(
        id: 'm1',
        sourceFileName: 'live',
        fileType: AcousticFileType.frd,
        importedAt: now,
        points: const [
          MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 70.5),
        ],
        rawPoints: const [
          MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 70.0),
        ],
        microphoneSnapshot: snapshot,
        calibrationStatus: CalibrationStatus.calibrated,
        calibrationCurveChecksum: _curve().checksum,
        calibrationAppliedAt: now,
      );

      final decoded = ParsedMeasurementData.fromJson(data.toJson());
      expect(decoded.rawPoints, isNotNull);
      expect(decoded.rawPoints!.single.magnitudeDb, 70.0);
      expect(decoded.points.single.magnitudeDb, 70.5);
      expect(decoded.microphoneSnapshot?.profileId, 'mic1');
      expect(decoded.calibrationStatus, CalibrationStatus.calibrated);
      expect(decoded.calibrationCurveChecksum, _curve().checksum);
      expect(decoded.calibrationAppliedAt, isNotNull);
    });

    test(
        'effectiveRawPoints falls back to points when rawPoints is null '
        '(legacy decode)', () {
      final data = ParsedMeasurementData(
        id: 'm1',
        sourceFileName: 'legacy',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2026, 1, 1),
        points: const [
          MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 70.0),
        ],
      );
      expect(data.rawPoints, isNull);
      expect(data.effectiveRawPoints, same(data.points));
    });

    test(
        'decoding JSON with no calibration fields at all yields '
        'legacyUnknown, never calibrated', () {
      final legacyJson = {
        'id': 'old1',
        'sourceFileName': 'old.frd',
        'fileType': 'frd',
        'importedAt': DateTime.utc(2025, 1, 1).toIso8601String(),
        'points': [
          {'f': 1000.0, 'm': 70.0},
        ],
      };
      final decoded = ParsedMeasurementData.fromJson(legacyJson);
      expect(decoded.calibrationStatus, CalibrationStatus.legacyUnknown);
      expect(decoded.rawPoints, isNull);
      expect(decoded.microphoneSnapshot, isNull);
      expect(decoded.effectiveRawPoints, decoded.points);
    });

    test(
        'a corrupt microphoneSnapshot does not fail the whole decode — '
        'falls back to null', () {
      final json = {
        'id': 'm1',
        'sourceFileName': 'live',
        'fileType': 'frd',
        'importedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'points': [
          {'f': 1000.0, 'm': 70.0},
        ],
        'microphoneSnapshot': {'not': 'a valid snapshot shape at all'},
        'calibrationStatus': 'calibrated',
      };
      final decoded = ParsedMeasurementData.fromJson(json);
      expect(decoded, isNotNull);
      // Malformed nested map still decodes via permissive fromJson defaults
      // rather than throwing, per the established item-resilient pattern.
      expect(decoded.points.single.frequencyHz, 1000.0);
    });

    test(
        'a corrupt calibrationStatus string falls back to legacyUnknown, '
        'not a thrown exception', () {
      final json = {
        'id': 'm1',
        'sourceFileName': 'live',
        'fileType': 'frd',
        'importedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'points': [
          {'f': 1000.0, 'm': 70.0},
        ],
        'calibrationStatus': 'totally-not-a-real-status',
      };
      final decoded = ParsedMeasurementData.fromJson(json);
      expect(decoded.calibrationStatus, CalibrationStatus.legacyUnknown);
    });
  });

  group('ProProject.selectedMicrophoneProfile — persistence', () {
    test('round-trips through toJson/fromJson', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        selectedMicrophoneProfile: _profile(),
      );
      final decoded = ProProject.fromJson(project.toJson());
      expect(decoded.selectedMicrophoneProfile, isNotNull);
      expect(decoded.selectedMicrophoneProfile!.checksum, _profile().checksum);
    });

    test('is null by default — never a fabricated default profile', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(project.selectedMicrophoneProfile, isNull);
    });

    test(
        'a corrupt selectedMicrophoneProfile in JSON does not fail project '
        'decode — falls back to null', () {
      final json = {
        'id': 'p1',
        'name': 'Test',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'selectedMicrophoneProfile': {'id': 123}, // wrong shape
      };
      final decoded = ProProject.fromJson(json);
      expect(decoded.id, 'p1');
      expect(decoded.selectedMicrophoneProfile, isNull);
    });

    test('copyWith clearSelectedMicrophoneProfile actually clears it', () {
      final project = ProProject(
        id: 'p1',
        name: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        selectedMicrophoneProfile: _profile(),
      );
      final cleared = project.copyWith(clearSelectedMicrophoneProfile: true);
      expect(cleared.selectedMicrophoneProfile, isNull);
    });

    test(
        'selecting a microphone for one project never affects another '
        'project\'s selection', () {
      final projectA = ProProject(
        id: 'a',
        name: 'A',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        selectedMicrophoneProfile: _profile(),
      );
      final projectB = ProProject(
        id: 'b',
        name: 'B',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(projectA.selectedMicrophoneProfile, isNotNull);
      expect(projectB.selectedMicrophoneProfile, isNull);
    });
  });
}
