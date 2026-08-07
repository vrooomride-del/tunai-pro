// ── TUNAI PRO Phase 3-D3B — Room measurement quality gate ───────────────────
//
// Pure evaluator: is ONE Room measurement (a single RoomSystemMeasurement,
// Left or Right) trustworthy enough for Room Auto PEQ to consume? Reads only
// what Accept already persisted (MeasurementQualitySnapshot embedded on
// ParsedMeasurementData) — never re-derives thresholds, never touches
// RoomAutoPeq's own algorithm.
//
// A missing qualitySnapshot (legacy measurement, or an imported/simulated
// source) fails closed — Room Auto PEQ's whole purpose is trusting LIVE
// Room measurements, so "unknown quality" is never treated as acceptable
// here (contrast with Factory Guided AI's import policy, out of scope this
// phase).
library;

import '../calibration/calibration_frequency_coverage.dart';
import '../room_measurement_data.dart';
import 'room_auto_peq.dart' show roomAutoPeqMinHz, roomAutoPeqMaxHz;
import '../measurement/measurement_quality_policy.dart';

enum RoomMeasurementQualityBlockerCode {
  /// No measurement at all for this side (Left/Right not yet captured).
  missingMeasurement,

  /// Measurement exists but carries no quality snapshot — legacy/imported/
  /// simulated source, never trusted as Ready.
  missingQualitySnapshot,

  /// Snapshot exists but the measurement wasn't captured for the project
  /// this gate is evaluating against.
  projectMismatch,

  /// No microphone profile identity on the snapshot's provenance.
  missingMicrophoneProfile,

  /// No input device identity on the snapshot's provenance.
  missingInputDevice,

  /// The snapshot's quality policy version doesn't match the current one.
  unsupportedPolicyVersion,

  actualSampleRateMismatch,
  actualChannelCountMismatch,

  /// The setup check this capture relied on recorded clipped samples.
  clipping,

  /// The calibration curve doesn't cover the required frequency range (see
  /// [CalibrationFrequencyCoverage]).
  calibrationCoverageInsufficient,
}

class RoomMeasurementQualityBlocker {
  final RoomMeasurementQualityBlockerCode code;
  final String message;

  const RoomMeasurementQualityBlocker(this.code, this.message);

  @override
  String toString() => '${code.name}: $message';
}

class RoomMeasurementQualityResult {
  final bool isValid;
  final List<RoomMeasurementQualityBlocker> blockers;

  const RoomMeasurementQualityResult({
    required this.isValid,
    required this.blockers,
  });

  RoomMeasurementQualityBlocker? get primaryBlocker =>
      blockers.isEmpty ? null : blockers.first;

  bool hasBlocker(RoomMeasurementQualityBlockerCode code) =>
      blockers.any((b) => b.code == code);
}

abstract final class RoomMeasurementQualityGate {
  static RoomMeasurementQualityResult evaluate({
    required RoomSystemMeasurement? measurement,
    required String expectedProjectId,
    MeasurementQualityPolicy? policy,
    double minCalibrationFrequencyHz = roomAutoPeqMinHz,
    double maxCalibrationFrequencyHz = roomAutoPeqMaxHz,
  }) {
    if (measurement == null) {
      return const RoomMeasurementQualityResult(
        isValid: false,
        blockers: [
          RoomMeasurementQualityBlocker(
            RoomMeasurementQualityBlockerCode.missingMeasurement,
            '측정이 없습니다.',
          ),
        ],
      );
    }

    final snapshot = measurement.frd.qualitySnapshot;
    if (snapshot == null) {
      return const RoomMeasurementQualityResult(
        isValid: false,
        blockers: [
          RoomMeasurementQualityBlocker(
            RoomMeasurementQualityBlockerCode.missingQualitySnapshot,
            '측정의 품질 정보가 없습니다.',
          ),
        ],
      );
    }

    final blockers = <RoomMeasurementQualityBlocker>[];
    final provenance = snapshot.provenance;
    final effectivePolicy = policy ?? MeasurementQualityPolicy.proProvisional();

    if (provenance.projectId != expectedProjectId) {
      blockers.add(const RoomMeasurementQualityBlocker(
        RoomMeasurementQualityBlockerCode.projectMismatch,
        '다른 프로젝트에서 캡처된 측정입니다.',
      ));
    }
    if (provenance.microphoneProfileChecksum.isEmpty) {
      blockers.add(const RoomMeasurementQualityBlocker(
        RoomMeasurementQualityBlockerCode.missingMicrophoneProfile,
        '측정 마이크 정보가 없습니다.',
      ));
    }
    if (provenance.inputDeviceSelectionIdentity.isEmpty) {
      blockers.add(const RoomMeasurementQualityBlocker(
        RoomMeasurementQualityBlockerCode.missingInputDevice,
        '입력 장치 정보가 없습니다.',
      ));
    }
    if (provenance.qualityPolicyVersion != effectivePolicy.version) {
      blockers.add(const RoomMeasurementQualityBlocker(
        RoomMeasurementQualityBlockerCode.unsupportedPolicyVersion,
        '측정 품질 기준 버전이 다릅니다.',
      ));
    }
    if (provenance.actualSampleRate != effectivePolicy.expectedSampleRate) {
      blockers.add(const RoomMeasurementQualityBlocker(
        RoomMeasurementQualityBlockerCode.actualSampleRateMismatch,
        '실제 녹음 샘플레이트가 예상과 다릅니다.',
      ));
    }
    if (provenance.actualChannelCount != effectivePolicy.expectedChannelCount) {
      blockers.add(const RoomMeasurementQualityBlocker(
        RoomMeasurementQualityBlockerCode.actualChannelCountMismatch,
        '실제 녹음 채널 수가 예상과 다릅니다.',
      ));
    }
    if (snapshot.setupClippedSampleCount > 0) {
      blockers.add(const RoomMeasurementQualityBlocker(
        RoomMeasurementQualityBlockerCode.clipping,
        '측정 준비 확인에서 클리핑이 감지되었습니다.',
      ));
    }

    final coverageOk = CalibrationFrequencyCoverage.evaluate(
      calibrationStatus: measurement.frd.calibrationStatus,
      calibrationCurve: measurement.frd.microphoneSnapshot?.calibrationCurve,
      minFrequencyHz: minCalibrationFrequencyHz,
      maxFrequencyHz: maxCalibrationFrequencyHz,
    );
    if (!coverageOk) {
      blockers.add(const RoomMeasurementQualityBlocker(
        RoomMeasurementQualityBlockerCode.calibrationCoverageInsufficient,
        '마이크 보정이 20–300 Hz를 포함하지 않습니다.',
      ));
    }

    return RoomMeasurementQualityResult(
      isValid: blockers.isEmpty,
      blockers: List.unmodifiable(blockers),
    );
  }
}
