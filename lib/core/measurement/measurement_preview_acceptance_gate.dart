// ── TUNAI PRO Phase 3-D3A-2 — Accept-time provenance gate ────────────────────
//
// ONE pure evaluator for "may this Preview actually be persisted?". Factory
// (LiveMeasurementController) and Room (RoomMeasurementController) both call
// this instead of each re-deriving their own identity comparison — the
// existing Phase 3-C stale-preview guard (a single profileChecksum compare)
// is superseded by this wider, still fail-closed set of checks, not
// duplicated alongside it.
//
// Pure and synchronous: no I/O, no provider reads. A capture's provenance
// was pinned once, at capture time, by MeasurementCaptureProvenanceBuilder;
// this only compares that frozen snapshot against the CURRENT project state
// handed to it by the caller. It never re-reads the project store itself and
// never re-enumerates input devices — runtime device availability is a
// capture-time concern (MeasurementCapturePreflight), not an accept-time one
// (Phase 3-D3A-2 §11): Accept only asks "is this the same identity that was
// true when Capture succeeded", not "is the device still physically present
// right now".
library;

import '../pro_project.dart';
import 'measurement_capture_provenance.dart';
import 'measurement_quality_policy.dart';

enum MeasurementPreviewAcceptanceBlockerCode {
  /// No provenance was ever pinned for this preview (e.g. a preview from
  /// before this phase existed, or a code path that skipped capture()'s
  /// normal success branch). Fails closed rather than assuming Accept-safe.
  missingProvenance,
  projectChanged,
  microphoneProfileChanged,
  calibrationCurveChanged,
  calibrationOrientationChanged,
  inputDeviceChanged,
  setupGenerationChanged,
  qualityPolicyChanged,
  actualSampleRateMismatch,
  actualChannelCountMismatch,
}

class MeasurementPreviewAcceptanceBlocker {
  final MeasurementPreviewAcceptanceBlockerCode code;
  final String message;

  const MeasurementPreviewAcceptanceBlocker(this.code, this.message);

  @override
  String toString() => '${code.name}: $message';
}

class MeasurementPreviewAcceptanceResult {
  final bool canAccept;

  /// True whenever [canAccept] is false — every blocker here means the
  /// preview no longer describes what Accept would persist under.
  final bool stale;

  final List<MeasurementPreviewAcceptanceBlocker> blockers;

  const MeasurementPreviewAcceptanceResult({
    required this.canAccept,
    required this.stale,
    required this.blockers,
  });

  MeasurementPreviewAcceptanceBlocker? get primaryBlocker =>
      blockers.isEmpty ? null : blockers.first;

  bool hasBlocker(MeasurementPreviewAcceptanceBlockerCode code) =>
      blockers.any((b) => b.code == code);
}

abstract final class MeasurementPreviewAcceptanceGate {
  static MeasurementPreviewAcceptanceResult evaluate({
    required MeasurementCaptureProvenance? provenance,
    required ProProject? currentProject,
    MeasurementQualityPolicy? policy,
  }) {
    if (provenance == null) {
      return const MeasurementPreviewAcceptanceResult(
        canAccept: false,
        stale: true,
        blockers: [
          MeasurementPreviewAcceptanceBlocker(
            MeasurementPreviewAcceptanceBlockerCode.missingProvenance,
            '이 측정에는 캡처 시점 정보가 없습니다. 다시 측정하세요.',
          ),
        ],
      );
    }

    final blockers = <MeasurementPreviewAcceptanceBlocker>[];

    if (currentProject == null || currentProject.id != provenance.projectId) {
      blockers.add(const MeasurementPreviewAcceptanceBlocker(
        MeasurementPreviewAcceptanceBlockerCode.projectChanged,
        '측정 이후 프로젝트가 변경되었습니다.',
      ));
    }

    final effectivePolicy = policy ?? MeasurementQualityPolicy.proProvisional();
    final currentProfile = currentProject?.selectedMicrophoneProfile;
    final currentCurve = currentProfile?.calibrationCurve;

    if (provenance.microphoneProfileChecksum !=
        (currentProfile?.checksum ?? '')) {
      blockers.add(const MeasurementPreviewAcceptanceBlocker(
        MeasurementPreviewAcceptanceBlockerCode.microphoneProfileChanged,
        '측정 이후 마이크 프로필이 변경되었습니다.',
      ));
    }
    if (provenance.calibrationCurveChecksum != currentCurve?.checksum) {
      blockers.add(const MeasurementPreviewAcceptanceBlocker(
        MeasurementPreviewAcceptanceBlockerCode.calibrationCurveChanged,
        '측정 이후 보정 커브가 변경되었습니다.',
      ));
    }
    if (provenance.calibrationAngle != currentCurve?.angle.name) {
      blockers.add(const MeasurementPreviewAcceptanceBlocker(
        MeasurementPreviewAcceptanceBlockerCode.calibrationOrientationChanged,
        '측정 이후 마이크 방향 설정이 변경되었습니다.',
      ));
    }

    final currentDeviceIdentity = currentProject == null
        ? ''
        : measurementInputDeviceSelectionIdentity(
            currentProject.selectedInputDevice);
    if (provenance.inputDeviceSelectionIdentity != currentDeviceIdentity) {
      blockers.add(const MeasurementPreviewAcceptanceBlocker(
        MeasurementPreviewAcceptanceBlockerCode.inputDeviceChanged,
        '측정 이후 입력 장치가 변경되었습니다.',
      ));
    }

    final currentGenerationId =
        currentProject?.currentSetupReadiness?.generationId;
    if (provenance.setupReadinessGenerationId != currentGenerationId) {
      blockers.add(const MeasurementPreviewAcceptanceBlocker(
        MeasurementPreviewAcceptanceBlockerCode.setupGenerationChanged,
        '측정 이후 측정 준비 확인이 다시 실행되었습니다.',
      ));
    }
    if (provenance.qualityPolicyVersion != effectivePolicy.version) {
      blockers.add(const MeasurementPreviewAcceptanceBlocker(
        MeasurementPreviewAcceptanceBlockerCode.qualityPolicyChanged,
        '측정 품질 기준이 변경되었습니다.',
      ));
    }

    // Actual-format checks are independent of current project state — a
    // capture recorded at the wrong sample rate/channel count is never
    // Accept-safe no matter what the project looks like now.
    if (provenance.actualSampleRate != effectivePolicy.expectedSampleRate) {
      blockers.add(const MeasurementPreviewAcceptanceBlocker(
        MeasurementPreviewAcceptanceBlockerCode.actualSampleRateMismatch,
        '실제 녹음 샘플레이트가 예상과 다릅니다.',
      ));
    }
    if (provenance.actualChannelCount != effectivePolicy.expectedChannelCount) {
      blockers.add(const MeasurementPreviewAcceptanceBlocker(
        MeasurementPreviewAcceptanceBlockerCode.actualChannelCountMismatch,
        '실제 녹음 채널 수가 예상과 다릅니다.',
      ));
    }

    return MeasurementPreviewAcceptanceResult(
      canAccept: blockers.isEmpty,
      stale: blockers.isNotEmpty,
      blockers: List.unmodifiable(blockers),
    );
  }
}
