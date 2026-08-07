// ── TUNAI PRO Phase 3-C — Microphone Profile Manager edit rules ────────────
//
// Pure functions only: no I/O, no Riverpod, no Flutter widget imports. The
// Profile Manager dialog and the Measure tab status card both call into
// this module instead of re-deriving the same safety rules independently.
library;

import 'calibration_types.dart';

/// Well-known, stable id for the "Use Without Calibration" sentinel profile
/// — never present in a project's `microphoneProfiles` roster, only ever
/// assigned directly as `selectedMicrophoneProfile` so the status card can
/// tell "explicitly chose no calibration" apart from "never chose anything".
const String kUncalibratedSentinelProfileId = 'uncalibrated-explicit';

/// Builds the fixed profile object selecting "Use Without Calibration"
/// assigns. Deliberately not added to any roster — it is a quality-warning
/// state, not a reusable microphone the user owns.
MeasurementMicrophoneProfile buildUncalibratedSentinelProfile(DateTime now) =>
    MeasurementMicrophoneProfile(
      id: kUncalibratedSentinelProfileId,
      manufacturer: '—',
      model: 'No Calibration',
      connectionType: 'n/a',
      calibrationSource: CalibrationSource.uncalibrated,
      createdAt: now,
      updatedAt: now,
    );

/// True for the sentinel built by [buildUncalibratedSentinelProfile] — lets
/// callers distinguish "explicitly uncalibrated" from an ordinary custom
/// profile that merely hasn't had a calibration file imported yet.
bool isUncalibratedSentinel(MeasurementMicrophoneProfile? profile) =>
    profile?.id == kUncalibratedSentinelProfileId;

/// Produces an independent copy of [source] under a new identity — a fresh
/// `id`/`createdAt`/`updatedAt`, everything else unchanged (including the
/// calibration curve, since a duplicate legitimately starts out identically
/// calibrated to its source until the user diverges it).
MeasurementMicrophoneProfile duplicateProfile({
  required MeasurementMicrophoneProfile source,
  required String newId,
  required DateTime now,
}) =>
    MeasurementMicrophoneProfile(
      id: newId,
      manufacturer: source.manufacturer,
      model: source.model,
      serialNumber: source.serialNumber,
      connectionType: source.connectionType,
      inputDeviceId: source.inputDeviceId,
      calibrationSource: source.calibrationSource,
      calibrationCurve: source.calibrationCurve,
      sensitivityMvPa: source.sensitivityMvPa,
      splReferenceDb: source.splReferenceDb,
      createdAt: now,
      updatedAt: now,
    );

/// Applies a freshly-parsed, validated [curve] to [profile] — the ONLY
/// place a profile's calibration should transition away from
/// [CalibrationSource.uncalibrated]. Callers must have already confirmed
/// [CalibrationCurve.isStructurallyValid] (the parser only ever returns a
/// structurally valid curve on success — this function does not re-validate
/// it, matching [CalibrationApplicator]'s own "trust the typed input"
/// contract).
MeasurementMicrophoneProfile applyCalibrationImport({
  required MeasurementMicrophoneProfile profile,
  required CalibrationCurve curve,
  required CalibrationSource resultingSource,
  required DateTime now,
}) {
  assert(resultingSource != CalibrationSource.uncalibrated,
      'an import can never result in CalibrationSource.uncalibrated.');
  return profile.copyWith(
    calibrationSource: resultingSource,
    calibrationCurve: curve,
    updatedAt: now,
  );
}

/// User-facing validation for a TUNAI-serial import attempt — TUNAI
/// calibration is meaningless without an associated serial number, so an
/// import is blocked (not silently accepted) until one is present.
String? validateTunaiSerialForImport(String? serialNumber) {
  if (serialNumber == null || serialNumber.trim().isEmpty) {
    return '이 마이크는 개별 보정 파일이 필요합니다 — 먼저 일련번호를 입력하세요.';
  }
  return null;
}

/// Changes [profile]'s serial number, applying the TUNAI mismatch guard: if
/// this is a TUNAI-serial profile that already carries a calibration curve
/// and the serial is actually changing, the curve can no longer be trusted
/// to match the (now different) unit — it is cleared and the source reverts
/// to [CalibrationSource.uncalibrated] rather than silently keeping a
/// curve that may belong to a different physical microphone.
MeasurementMicrophoneProfile updateSerialNumber({
  required MeasurementMicrophoneProfile profile,
  required String? newSerial,
  required DateTime now,
}) {
  final serialChanged = newSerial != profile.serialNumber;
  final isTunaiWithCurve =
      profile.calibrationSource == CalibrationSource.tunaiSerialProfile &&
          profile.calibrationCurve != null;

  if (serialChanged && isTunaiWithCurve) {
    return profile.copyWith(
      serialNumber: newSerial,
      clearSerialNumber: newSerial == null,
      calibrationSource: CalibrationSource.uncalibrated,
      clearCalibrationCurve: true,
      updatedAt: now,
    );
  }
  return profile.copyWith(
    serialNumber: newSerial,
    clearSerialNumber: newSerial == null,
    updatedAt: now,
  );
}

/// Inserts [profile] into [roster] (replacing any existing entry with the
/// same id) or appends it as new. Never mutates [roster] in place.
List<MeasurementMicrophoneProfile> upsertProfileInRoster({
  required List<MeasurementMicrophoneProfile> roster,
  required MeasurementMicrophoneProfile profile,
}) {
  final idx = roster.indexWhere((p) => p.id == profile.id);
  if (idx < 0) return [...roster, profile];
  final copy = [...roster];
  copy[idx] = profile;
  return copy;
}

/// Result of removing a profile from the roster: the new roster, plus what
/// the project's selection should become. Deleting the currently-selected
/// profile clears the selection outright — it is NEVER replaced with
/// another roster entry automatically.
class RosterDeletionResult {
  final List<MeasurementMicrophoneProfile> roster;
  final MeasurementMicrophoneProfile? selected;
  final bool selectionCleared;

  const RosterDeletionResult({
    required this.roster,
    required this.selected,
    required this.selectionCleared,
  });
}

RosterDeletionResult removeProfileFromRoster({
  required List<MeasurementMicrophoneProfile> roster,
  required String deletedId,
  required MeasurementMicrophoneProfile? currentlySelected,
}) {
  final newRoster = roster.where((p) => p.id != deletedId).toList();
  final wasSelected = currentlySelected?.id == deletedId;
  return RosterDeletionResult(
    roster: newRoster,
    selected: wasSelected ? null : currentlySelected,
    selectionCleared: wasSelected,
  );
}

// ── Pre-capture display state (Measure tab status card) ────────────────────

/// The Measure tab's Microphone status card reflects the SELECTED PROFILE's
/// own readiness, not any specific past capture's [CalibrationStatus] —
/// there may not have been a capture yet, and a profile's readiness is
/// knowable before one happens. This enum intentionally has no
/// `partiallyCalibrated`/`legacyUnknown` counterpart: those describe how a
/// specific already-captured measurement's frequency range related to a
/// curve, which cannot be known before that measurement exists — see
/// [CalibrationStatus] for the (separate) post-capture states, which
/// continue to be shown per-measurement exactly as Phase 3-B wired them.
enum MicrophoneDisplayState {
  notSelected,
  calibrationReady,
  explicitlyUncalibrated,
  invalid,
}

MicrophoneDisplayState deriveMicrophoneDisplayState(
  MeasurementMicrophoneProfile? profile,
) {
  if (profile == null) return MicrophoneDisplayState.notSelected;
  if (profile.calibrationSource == CalibrationSource.uncalibrated) {
    return MicrophoneDisplayState.explicitlyUncalibrated;
  }
  final curve = profile.calibrationCurve;
  if (curve == null || !curve.isStructurallyValid) {
    return MicrophoneDisplayState.invalid;
  }
  return MicrophoneDisplayState.calibrationReady;
}
