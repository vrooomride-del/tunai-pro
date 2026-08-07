// Phase 3-C — microphone_profile_edit_rules.dart pure safety-rule tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/calibration/microphone_profile_edit_rules.dart';

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

MeasurementMicrophoneProfile _tunaiWithCurve() => MeasurementMicrophoneProfile(
      id: 'mic1',
      manufacturer: 'TUNAI',
      model: 'TUNAI Measurement Mic',
      serialNumber: 'SN-001',
      connectionType: 'USB',
      calibrationSource: CalibrationSource.tunaiSerialProfile,
      calibrationCurve: _curve(),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

MeasurementMicrophoneProfile _customUncalibrated() =>
    MeasurementMicrophoneProfile(
      id: 'mic2',
      manufacturer: 'ACME',
      model: 'M1',
      connectionType: 'USB',
      calibrationSource: CalibrationSource.uncalibrated,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('buildUncalibratedSentinelProfile / isUncalibratedSentinel', () {
    test('sentinel is always uncalibrated with a stable id', () {
      final now = DateTime.utc(2026, 1, 1);
      final sentinel = buildUncalibratedSentinelProfile(now);
      expect(sentinel.calibrationSource, CalibrationSource.uncalibrated);
      expect(sentinel.calibrationCurve, isNull);
      expect(sentinel.hasUsableCalibration, isFalse);
      expect(isUncalibratedSentinel(sentinel), isTrue);
    });

    test('an ordinary profile is never mistaken for the sentinel', () {
      expect(isUncalibratedSentinel(_customUncalibrated()), isFalse);
      expect(isUncalibratedSentinel(null), isFalse);
    });
  });

  group('duplicateProfile', () {
    test('produces a new id/timestamps but keeps calibration and other fields',
        () {
      final source = _tunaiWithCurve();
      final now = DateTime.utc(2026, 6, 1);
      final copy = duplicateProfile(source: source, newId: 'mic-dup', now: now);
      expect(copy.id, 'mic-dup');
      expect(copy.id, isNot(source.id));
      expect(copy.createdAt, now);
      expect(copy.updatedAt, now);
      expect(copy.manufacturer, source.manufacturer);
      expect(
          copy.calibrationCurve?.checksum, source.calibrationCurve?.checksum);
      expect(copy.calibrationSource, source.calibrationSource);
    });
  });

  group('applyCalibrationImport', () {
    test('sets curve and source, never leaves source uncalibrated', () {
      final profile = _customUncalibrated();
      final now = DateTime.utc(2026, 6, 1);
      final updated = applyCalibrationImport(
        profile: profile,
        curve: _curve(),
        resultingSource: CalibrationSource.userImported,
        now: now,
      );
      expect(updated.calibrationSource, CalibrationSource.userImported);
      expect(updated.calibrationCurve?.checksum, _curve().checksum);
      expect(updated.hasUsableCalibration, isTrue);
      expect(updated.updatedAt, now);
    });
  });

  group('validateTunaiSerialForImport', () {
    test('rejects null/empty/whitespace-only serial', () {
      expect(validateTunaiSerialForImport(null), isNotNull);
      expect(validateTunaiSerialForImport(''), isNotNull);
      expect(validateTunaiSerialForImport('   '), isNotNull);
    });

    test('accepts a real serial number', () {
      expect(validateTunaiSerialForImport('SN-001'), isNull);
    });
  });

  group('updateSerialNumber — TUNAI mismatch guard', () {
    test(
        'changing serial on a TUNAI profile that already has a curve '
        'clears the curve and reverts to uncalibrated', () {
      final profile = _tunaiWithCurve();
      final now = DateTime.utc(2026, 6, 1);
      final updated =
          updateSerialNumber(profile: profile, newSerial: 'SN-002', now: now);
      expect(updated.serialNumber, 'SN-002');
      expect(updated.calibrationCurve, isNull);
      expect(updated.calibrationSource, CalibrationSource.uncalibrated);
      expect(updated.hasUsableCalibration, isFalse);
    });

    test('keeping the same serial on a TUNAI profile leaves the curve intact',
        () {
      final profile = _tunaiWithCurve();
      final now = DateTime.utc(2026, 6, 1);
      final updated = updateSerialNumber(
          profile: profile, newSerial: profile.serialNumber, now: now);
      expect(updated.calibrationCurve, isNotNull);
      expect(updated.calibrationSource, CalibrationSource.tunaiSerialProfile);
    });

    test('changing serial on a non-TUNAI profile never touches calibration',
        () {
      final custom = MeasurementMicrophoneProfile(
        id: 'mic3',
        manufacturer: 'ACME',
        model: 'M1',
        serialNumber: 'A',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.userImported,
        calibrationCurve: _curve(),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final updated = updateSerialNumber(
          profile: custom, newSerial: 'B', now: DateTime.utc(2026, 6, 1));
      expect(updated.serialNumber, 'B');
      expect(updated.calibrationCurve, isNotNull);
      expect(updated.calibrationSource, CalibrationSource.userImported);
    });

    test(
        'changing serial on a TUNAI profile with no curve yet is a plain '
        'field update', () {
      final profile = MeasurementMicrophoneProfile(
        id: 'mic4',
        manufacturer: 'TUNAI',
        model: 'TUNAI Measurement Mic',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.uncalibrated,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final updated = updateSerialNumber(
          profile: profile, newSerial: 'SN-999', now: DateTime.utc(2026, 6, 1));
      expect(updated.serialNumber, 'SN-999');
      expect(updated.calibrationSource, CalibrationSource.uncalibrated);
    });
  });

  group('upsertProfileInRoster', () {
    test('appends a new profile', () {
      final roster = [_customUncalibrated()];
      final result =
          upsertProfileInRoster(roster: roster, profile: _tunaiWithCurve());
      expect(result.length, 2);
      expect(result.map((p) => p.id), containsAll(['mic1', 'mic2']));
    });

    test('replaces an existing profile with the same id, in place', () {
      final roster = [_customUncalibrated(), _tunaiWithCurve()];
      final edited = _customUncalibrated().copyWith(model: 'Edited');
      final result = upsertProfileInRoster(roster: roster, profile: edited);
      expect(result.length, 2);
      expect(result.firstWhere((p) => p.id == 'mic2').model, 'Edited');
    });

    test('never mutates the original roster list', () {
      final roster = [_customUncalibrated()];
      upsertProfileInRoster(roster: roster, profile: _tunaiWithCurve());
      expect(roster.length, 1);
    });
  });

  group('removeProfileFromRoster', () {
    test('removes the entry and clears selection when it was selected', () {
      final roster = [_customUncalibrated(), _tunaiWithCurve()];
      final result = removeProfileFromRoster(
        roster: roster,
        deletedId: 'mic2',
        currentlySelected: _customUncalibrated(),
      );
      expect(result.roster.map((p) => p.id), ['mic1']);
      expect(result.selected, isNull);
      expect(result.selectionCleared, isTrue);
    });

    test('removes the entry but preserves an unrelated selection', () {
      final roster = [_customUncalibrated(), _tunaiWithCurve()];
      final selected = _tunaiWithCurve();
      final result = removeProfileFromRoster(
        roster: roster,
        deletedId: 'mic2',
        currentlySelected: selected,
      );
      expect(result.roster.map((p) => p.id), ['mic1']);
      expect(result.selected?.id, 'mic1');
      expect(result.selectionCleared, isFalse);
    });

    test(
        'never auto-selects a replacement — deletion only ever clears or '
        'preserves, never substitutes', () {
      final roster = [_customUncalibrated()];
      final result = removeProfileFromRoster(
        roster: roster,
        deletedId: 'mic2',
        currentlySelected: null,
      );
      expect(result.selected, isNull);
      expect(result.selectionCleared, isFalse);
    });
  });

  group('deriveMicrophoneDisplayState', () {
    test('null profile -> notSelected', () {
      expect(deriveMicrophoneDisplayState(null),
          MicrophoneDisplayState.notSelected);
    });

    test('uncalibrated source -> explicitlyUncalibrated', () {
      expect(deriveMicrophoneDisplayState(_customUncalibrated()),
          MicrophoneDisplayState.explicitlyUncalibrated);
    });

    test('non-uncalibrated source with a valid curve -> calibrationReady', () {
      expect(deriveMicrophoneDisplayState(_tunaiWithCurve()),
          MicrophoneDisplayState.calibrationReady);
    });

    test('non-uncalibrated source with no curve (mismatched combo) -> invalid',
        () {
      final mismatched =
          _tunaiWithCurve().copyWith(clearCalibrationCurve: true);
      expect(deriveMicrophoneDisplayState(mismatched),
          MicrophoneDisplayState.invalid);
    });

    test('non-uncalibrated source with a structurally invalid curve -> invalid',
        () {
      const badPoints = [CalibrationPoint(frequencyHz: 100, correctionDb: 0)];
      const invalidCurve = CalibrationCurve(
        points: badPoints,
        validMinFrequencyHz: 100,
        validMaxFrequencyHz: 100,
        sourceIdentity: 'x',
        checksum: 'x',
      );
      final profile =
          _tunaiWithCurve().copyWith(calibrationCurve: invalidCurve);
      expect(deriveMicrophoneDisplayState(profile),
          MicrophoneDisplayState.invalid);
    });
  });
}
