// Phase 3-E P0 — the real miniDSP UMIK-1 calibration file, end to end.
//
// The reported bug: 7018617.txt imported successfully, yet Home's System
// Readiness said "보정 안 함". The parser was never at fault — the curve was
// discarded at SAVE, by the TUNAI serial-mismatch guard in
// updateSerialNumber(). The dialog only wrote the serial field into the
// draft at save time, so the first save after an import always looked like
// "the serial changed" and invalidated the calibration that had just been
// imported for that exact unit.
//
// These tests walk the real file through every layer the bug crossed —
// parser -> profile -> serial guard -> roster/selection -> project JSON
// round-trip -> MeasurementWorkflowEvaluator -> Home copy — so a regression
// at any one of them fails here rather than only on a Mac.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_frequency_coverage.dart';
import 'package:tunai_pro/core/calibration/calibration_parser.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/calibration/microphone_profile_edit_rules.dart';
import 'package:tunai_pro/core/orchestrator/room_auto_peq.dart'
    show roomAutoPeqMinHz, roomAutoPeqMaxHz;
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_evaluator.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_presentation.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_provider.dart';
import 'package:tunai_pro/core/workflow/measurement_workflow_readiness.dart';

/// The dialog's save-time selection policy, verbatim from _saveDraft. A test
/// that skips this and simply constructs `selectedMicrophoneProfile: profile`
/// cannot see a selection bug at all — which is exactly how the first fix
/// passed its tests while the app still showed "No Calibration".
Future<void> saveProfileLikeDialog(
  ProProjectStoreNotifier store,
  ProProject project,
  MeasurementMicrophoneProfile finalDraft,
) async {
  final selected = project.selectedMicrophoneProfile;
  final wasSelected = selected?.id == finalDraft.id;
  final nothingRealSelected =
      selected == null || isUncalibratedSentinel(selected);

  await store.updateMicrophoneProfiles(
      project.id,
      upsertProfileInRoster(
          roster: project.microphoneProfiles, profile: finalDraft));
  if (wasSelected || nothingRealSelected) {
    await store.updateSelectedMicrophoneProfile(project.id, finalDraft);
  }
}

final _now = DateTime.utc(2026, 8, 7);

String _fixture() => File('test/fixtures/7018617.txt').readAsStringSync();

CalibrationParseResult _parse() => CalibrationFileParser.parse(
    content: _fixture(), sourceIdentity: '7018617.txt');

/// A brand-new profile exactly as MicrophoneProfileManagerDialog builds it.
MeasurementMicrophoneProfile _newDraft({required bool tunai}) =>
    MeasurementMicrophoneProfile(
      id: 'mic_1',
      manufacturer: tunai ? 'TUNAI' : 'miniDSP',
      model: tunai ? 'TUNAI Measurement Mic' : 'UMIK-1',
      connectionType: 'USB',
      calibrationSource: CalibrationSource.uncalibrated,
      createdAt: _now,
      updatedAt: _now,
    );

/// The dialog's real import + save sequence for [serial].
MeasurementMicrophoneProfile _importAndSave({
  required bool tunai,
  String? serial = '7018617',
}) {
  var draft = _newDraft(tunai: tunai);
  // _confirmPendingCalibration: the serial in the field is recorded WITH the
  // curve, because the curve was imported for that unit.
  draft = applyCalibrationImport(
    profile:
        draft.copyWith(serialNumber: serial, clearSerialNumber: serial == null),
    curve: _parse().curve!,
    resultingSource: tunai
        ? CalibrationSource.tunaiSerialProfile
        : CalibrationSource.userImported,
    now: _now,
  );
  // _saveDraft: the serial goes through the mismatch guard.
  return updateSerialNumber(profile: draft, newSerial: serial, now: _now);
}

ProProject _projectWith(MeasurementMicrophoneProfile profile) => ProProject(
      id: 'p1',
      name: 'UMIK Project',
      dspTarget: 'ADAU1701',
      createdAt: _now,
      updatedAt: _now,
      microphoneProfiles: [profile],
      selectedMicrophoneProfile: profile,
    );

MeasurementWorkflowReadiness _readiness(ProProject p) =>
    MeasurementWorkflowEvaluator.evaluate(
      project: p,
      roomApprovedPackageId: null,
      lastHardwareWriteResult: null,
      now: _now,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. the real file parses', () {
    test('the quoted header is metadata, never a data point', () {
      final r = _parse();
      expect(r.isSuccess, isTrue, reason: r.errors.join('; '));
      expect(r.warnings.first, contains('header row detected'));
      // 2.0268 would be a nonsense frequency; it must not appear as one.
      expect(r.curve!.points.any((p) => p.frequencyHz == 2.0268), isFalse);
      expect(r.curve!.points.any((p) => p.frequencyHz == 7018617), isFalse);
    });

    test('first calibration point is 10.054 Hz / -6.0106 dB', () {
      final first = _parse().curve!.points.first;
      expect(first.frequencyHz, closeTo(10.054, 1e-9));
      expect(first.correctionDb, closeTo(-6.0106, 1e-9));
    });

    test('the curve spans ~10 Hz to beyond 20 kHz', () {
      final c = _parse().curve!;
      expect(c.validMinFrequencyHz, closeTo(10.054, 1e-9));
      expect(c.validMaxFrequencyHz, greaterThanOrEqualTo(20000));
      expect(c.validMaxFrequencyHz, closeTo(20016.816, 1e-9));
      expect(c.isStructurallyValid, isTrue);
      expect(c.points.length, greaterThan(500));
    });

    test('20–300 Hz — the Room Auto PEQ band — is fully covered', () {
      expect(
        CalibrationFrequencyCoverage.evaluate(
          calibrationStatus: CalibrationStatus.calibrated,
          calibrationCurve: _parse().curve,
          minFrequencyHz: roomAutoPeqMinHz,
          maxFrequencyHz: roomAutoPeqMaxHz,
        ),
        isTrue,
      );
    });

    test('SERNO and Sens Factor are present in the header line', () {
      // The parser deliberately does not type these into the profile (a
      // human confirms sensitivity), but the identifying text must survive
      // in the source file this fixture pins.
      final header = _fixture().split(RegExp(r'\r?\n')).first;
      expect(header, contains('SERNO: 7018617'));
      expect(header, contains('2.0268'));
    });
  });

  group('2. import + save keeps the curve (the P0)', () {
    test('a TUNAI profile keeps its curve through the first save', () {
      final saved = _importAndSave(tunai: true);
      expect(saved.calibrationCurve, isNotNull,
          reason: 'setting a serial for the first time is not a mismatch');
      expect(saved.calibrationSource, CalibrationSource.tunaiSerialProfile);
      expect(saved.serialNumber, '7018617');
    });

    test('a custom/manufacturer profile keeps its curve too', () {
      final saved = _importAndSave(tunai: false);
      expect(saved.calibrationCurve, isNotNull);
      expect(saved.calibrationSource, CalibrationSource.userImported);
    });

    test('re-saving without touching the serial keeps the curve', () {
      final saved = _importAndSave(tunai: true);
      final again =
          updateSerialNumber(profile: saved, newSerial: '7018617', now: _now);
      expect(again.calibrationCurve, isNotNull);
      expect(again.calibrationSource, CalibrationSource.tunaiSerialProfile);
    });

    test('the mismatch guard STILL fires when the serial really changes', () {
      final saved = _importAndSave(tunai: true);
      final swapped =
          updateSerialNumber(profile: saved, newSerial: '9999999', now: _now);
      expect(swapped.calibrationCurve, isNull,
          reason: 'a curve must never follow a serial onto a different unit');
      expect(swapped.calibrationSource, CalibrationSource.uncalibrated);
    });

    test('clearing the serial also invalidates a TUNAI curve', () {
      final saved = _importAndSave(tunai: true);
      final cleared =
          updateSerialNumber(profile: saved, newSerial: null, now: _now);
      expect(cleared.calibrationCurve, isNull,
          reason: 'an unattributed curve cannot be tied to a physical unit');
    });
  });

  group('3. persistence', () {
    test('the curve survives a project JSON round-trip', () {
      final decoded = ProProject.fromJson(
          _projectWith(_importAndSave(tunai: true)).toJson());
      final profile = decoded.selectedMicrophoneProfile!;
      expect(profile.calibrationCurve, isNotNull);
      expect(profile.calibrationCurve!.points.length, 615);
      expect(
          profile.calibrationCurve!.validMinFrequencyHz, closeTo(10.054, 1e-6));
      expect(profile.serialNumber, '7018617');
    });

    test('the selected profile is the same one that carries the curve', () {
      final saved = _importAndSave(tunai: true);
      final decoded = ProProject.fromJson(_projectWith(saved).toJson());
      expect(decoded.selectedMicrophoneProfile!.id,
          decoded.microphoneProfiles.single.id);
      expect(decoded.microphoneProfiles.single.calibrationCurve, isNotNull,
          reason: 'the roster copy must not diverge from the selection');
    });
  });

  group('4. workflow readiness + Home copy', () {
    test('readiness reports calibrated, not uncalibrated', () {
      final r = _readiness(_projectWith(_importAndSave(tunai: true)));
      expect(
          r.calibrationStatus, MeasurementWorkflowCalibrationState.calibrated);
      expect(r.microphoneSelected, isTrue);
    });

    test('Home shows "보정 완료" — never "보정 안 함"', () {
      final r = _readiness(_projectWith(_importAndSave(tunai: true)));
      final text = measurementWorkflowCalibrationText(r.calibrationStatus);
      expect(text, '보정 완료');
      expect(text, isNot('보정 안 함'));
      expect(text, isNot(contains('No Calibration')));
    });

    test('and still after a reopen (JSON round-trip)', () {
      final decoded = ProProject.fromJson(
          _projectWith(_importAndSave(tunai: true)).toJson());
      expect(
          measurementWorkflowCalibrationText(
              _readiness(decoded).calibrationStatus),
          '보정 완료');
    });

    test('through the real provider, from the store', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final store = c.read(proProjectStoreProvider.notifier);
      await store.addProject(_projectWith(_importAndSave(tunai: true)));
      await store.setCurrentProject('p1');

      final r = c.read(measurementWorkflowReadinessProvider);
      expect(
          r.calibrationStatus, MeasurementWorkflowCalibrationState.calibrated);
    });

    test('importing calibration updates Home without reselecting the profile',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final store = c.read(proProjectStoreProvider.notifier);

      // Start with the profile selected but NOT yet calibrated.
      final bare = _newDraft(tunai: true);
      await store.addProject(ProProject(
        id: 'p1',
        name: 'UMIK Project',
        dspTarget: 'ADAU1701',
        createdAt: _now,
        updatedAt: _now,
        microphoneProfiles: [bare],
        selectedMicrophoneProfile: bare,
      ));
      await store.setCurrentProject('p1');
      expect(c.read(measurementWorkflowReadinessProvider).calibrationStatus,
          MeasurementWorkflowCalibrationState.explicitlyUncalibrated);

      // Import + save, exactly as the dialog does.
      final calibrated = _importAndSave(tunai: true);
      await store.updateMicrophoneProfiles('p1', [calibrated]);
      await store.updateSelectedMicrophoneProfile('p1', calibrated);

      expect(c.read(measurementWorkflowReadinessProvider).calibrationStatus,
          MeasurementWorkflowCalibrationState.calibrated,
          reason: 'Home must reflect the import immediately — no reselect, '
              'no re-entry');
    });
  });

  group('5. saving actually selects the microphone (the second P0)', () {
    /// Drives the real save path against a real store, starting from the
    /// state the user was actually in.
    Future<MeasurementWorkflowReadiness> saveInto(
        MeasurementMicrophoneProfile? initiallySelected,
        {List<MeasurementMicrophoneProfile> roster = const []}) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final store = c.read(proProjectStoreProvider.notifier);
      await store.addProject(ProProject(
        id: 'p1',
        name: 'Real',
        dspTarget: 'ADAU1701',
        createdAt: _now,
        updatedAt: _now,
        microphoneProfiles: roster,
        selectedMicrophoneProfile: initiallySelected,
      ));
      await store.setCurrentProject('p1');

      final project = c
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1');
      await saveProfileLikeDialog(store, project, _importAndSave(tunai: false));
      return c.read(measurementWorkflowReadinessProvider);
    }

    test(
        'with the "No Calibration" sentinel selected, saving selects the '
        'calibrated profile', () async {
      final r = await saveInto(buildUncalibratedSentinelProfile(_now));
      expect(
          r.calibrationStatus, MeasurementWorkflowCalibrationState.calibrated,
          reason: 'the roster held a calibrated mic while every screen still '
              'read "보정 없이 사용 — No Calibration"');
      expect(measurementWorkflowCalibrationText(r.calibrationStatus), '보정 완료');
      expect(r.microphoneLabel, contains('UMIK-1'));
    });

    test('with nothing selected, saving selects the new profile', () async {
      final r = await saveInto(null);
      expect(
          r.calibrationStatus, MeasurementWorkflowCalibrationState.calibrated);
    });

    test('re-saving the already-selected profile keeps it selected', () async {
      final existing = _importAndSave(tunai: false);
      final r = await saveInto(existing, roster: [existing]);
      expect(
          r.calibrationStatus, MeasurementWorkflowCalibrationState.calibrated);
    });

    test('another real microphone is never hijacked', () async {
      final other = MeasurementMicrophoneProfile(
        id: 'mic_other',
        manufacturer: 'ACME',
        model: 'REF-1',
        connectionType: 'USB',
        calibrationSource: CalibrationSource.uncalibrated,
        createdAt: _now,
        updatedAt: _now,
      );
      final r = await saveInto(other, roster: [other]);
      expect(r.microphoneLabel, contains('REF-1'),
          reason: 'switching between real microphones stays an explicit '
              'choice in the list');
    });
  });

  group('6. the other calibration states stay distinguishable', () {
    test('a narrow curve that misses 20–300 Hz reads as partial', () {
      const narrow = CalibrationCurve(
        points: [
          CalibrationPoint(frequencyHz: 500, correctionDb: 0.1),
          CalibrationPoint(frequencyHz: 8000, correctionDb: -0.2),
        ],
        angle: CalibrationAngle.zeroDegree,
        validMinFrequencyHz: 500,
        validMaxFrequencyHz: 8000,
        sourceIdentity: 'narrow.txt',
        checksum: 'narrow',
      );
      final profile = _newDraft(tunai: false).copyWith(
        calibrationSource: CalibrationSource.userImported,
        calibrationCurve: narrow,
      );
      final r = _readiness(_projectWith(profile));
      expect(r.calibrationStatus,
          MeasurementWorkflowCalibrationState.partiallyCalibrated);
      expect(measurementWorkflowCalibrationText(r.calibrationStatus), '부분 보정');
    });

    test('the explicit no-calibration sentinel reads as such', () {
      final r =
          _readiness(_projectWith(buildUncalibratedSentinelProfile(_now)));
      expect(r.calibrationStatus,
          MeasurementWorkflowCalibrationState.explicitlyUncalibrated);
      expect(
          measurementWorkflowCalibrationText(r.calibrationStatus), '보정 없이 사용');
    });

    test('a calibrated source with no curve reads as unknown, not calibrated',
        () {
      final profile = _newDraft(tunai: false)
          .copyWith(calibrationSource: CalibrationSource.manufacturerFile);
      final r = _readiness(_projectWith(profile));
      expect(r.calibrationStatus,
          MeasurementWorkflowCalibrationState.legacyUnknown);
      expect(measurementWorkflowCalibrationText(r.calibrationStatus),
          '보정 상태 확인 필요');
    });

    test('no microphone at all is distinct from uncalibrated', () {
      final r = _readiness(ProProject(
        id: 'p1',
        name: 'x',
        dspTarget: 'ADAU1701',
        createdAt: _now,
        updatedAt: _now,
      ));
      expect(r.calibrationStatus, MeasurementWorkflowCalibrationState.none);
    });
  });
}
