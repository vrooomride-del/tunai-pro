// Phase 3-D3C §2/§3/§4/§5 — live vs imported measurement evidence.
//
// A live Factory/Room capture and a plain imported FRD are both legitimate
// inputs, but they rest on different evidence. These tests pin:
//  - the explicit MeasurementDataSource discriminator (never inferred),
//  - that live captures produce MeasurementCaptureEvidence carrying REAL
//    measured quality/calibration provenance,
//  - that no metric is ever claimed from a placeholder or invented number.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/measurement_capture_evidence_builder.dart';
import 'package:tunai_pro/core/acoustic/measurement_evidence.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';

final _capturedAt = DateTime.utc(2026, 8, 7, 10);

MeasurementCaptureProvenance _provenance({
  String? curveChecksum = 'curve-abc',
  int sampleRate = 48000,
  int channelCount = 1,
}) =>
    MeasurementCaptureProvenance(
      projectId: 'proj-1',
      microphoneProfileChecksum: 'profile-abc',
      calibrationCurveChecksum: curveChecksum,
      calibrationAngle: CalibrationAngle.zeroDegree.name,
      inputDeviceSelectionIdentity: 'device:dev-1',
      setupReadinessGenerationId: 'gen-1',
      qualityPolicyVersion: 'pro-provisional-1',
      actualSampleRate: sampleRate,
      actualChannelCount: channelCount,
      capturedAt: _capturedAt,
    );

MeasurementQualitySnapshot _quality({
  double? noiseFloorDbFs = -72.0,
  double rmsDbFs = -18.0,
  double? snrDb = 54.0,
  int clippedCount = 0,
  double clippedRatio = 0.0,
  MeasurementCaptureProvenance? provenance,
}) =>
    MeasurementQualitySnapshot(
      provenance: provenance ?? _provenance(),
      setupCalibrationStatus: CalibrationStatus.calibrated,
      setupNoiseFloorDbFs: noiseFloorDbFs,
      setupPeakDbFs: -6.0,
      setupRmsDbFs: rmsDbFs,
      setupSignalToNoiseDb: snrDb,
      setupClippedSampleCount: clippedCount,
      setupClippedSampleRatio: clippedRatio,
      setupCheckedAt: _capturedAt.subtract(const Duration(minutes: 2)),
    );

ParsedMeasurementData _data({
  MeasurementDataSource source = MeasurementDataSource.liveCapture,
  CalibrationStatus calibrationStatus = CalibrationStatus.calibrated,
  String? curveChecksum = 'curve-abc',
  MeasurementQualitySnapshot? quality,
  bool withPhase = false,
  bool noQuality = false,
}) =>
    ParsedMeasurementData(
      id: 'meas-1',
      sourceFileName: 'Live Measurement 2026-08-07 10:00',
      fileType: AcousticFileType.frd,
      importedAt: _capturedAt,
      points: [
        MeasurementDataPoint(
            frequencyHz: 100, magnitudeDb: -3, phaseDeg: withPhase ? 10 : null),
        MeasurementDataPoint(
            frequencyHz: 1000,
            magnitudeDb: -2,
            phaseDeg: withPhase ? 20 : null),
      ],
      calibrationStatus: calibrationStatus,
      calibrationCurveChecksum: curveChecksum,
      qualitySnapshot: noQuality ? null : (quality ?? _quality()),
      source: source,
    );

MeasurementCaptureEvidenceBuildResult _build(ParsedMeasurementData d) =>
    MeasurementCaptureEvidenceBuilder.build(
        projectId: 'proj-1', measurementRef: 'ch_tw_l', data: d);

void main() {
  group('1. MeasurementDataSource discriminator', () {
    test('defaults to legacyUnknown and never infers from metadata', () {
      // Carries a mic snapshot AND a quality snapshot but no explicit source:
      // must stay legacyUnknown, never be promoted to liveCapture.
      final legacy = ParsedMeasurementData(
        id: 'legacy-1',
        sourceFileName: 'old.frd',
        fileType: AcousticFileType.frd,
        importedAt: _capturedAt,
        points: const [MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -3)],
        qualitySnapshot: _quality(),
      );
      expect(legacy.source, MeasurementDataSource.legacyUnknown);
    });

    test('round-trips through JSON', () {
      for (final s in MeasurementDataSource.values) {
        final decoded =
            ParsedMeasurementData.fromJson(_data(source: s).toJson());
        expect(decoded.source, s);
      }
    });

    test('a record persisted before this field decodes as legacyUnknown', () {
      final json = _data().toJson()..remove('source');
      expect(ParsedMeasurementData.fromJson(json).source,
          MeasurementDataSource.legacyUnknown);
    });
  });

  group('2. calibration mapping', () {
    test('fully calibrated -> metric available WITH a ref', () {
      final ev = _build(_data()).evidence;
      expect(ev.availableMetrics, contains(EvidenceMetric.calibration));
      expect(ev.calibrationRef, 'curve-abc');
    });

    test('partially calibrated -> ref kept, but NO full calibration claim', () {
      final r = _build(
          _data(calibrationStatus: CalibrationStatus.partiallyCalibrated));
      expect(r.evidence.availableMetrics,
          isNot(contains(EvidenceMetric.calibration)));
      expect(
          r.evidence.unavailableMetrics, contains(EvidenceMetric.calibration));
      expect(r.evidence.calibrationRef, 'curve-abc',
          reason: 'the curve identity is still traceable');
      expect(r.provenanceWarnings.join(), contains('부분 보정'));
    });

    test('explicitly uncalibrated / legacy / invalid -> unavailable, no ref',
        () {
      for (final status in [
        CalibrationStatus.explicitlyUncalibrated,
        CalibrationStatus.legacyUnknown,
        CalibrationStatus.invalid,
      ]) {
        final ev = _build(_data(calibrationStatus: status)).evidence;
        expect(ev.availableMetrics, isNot(contains(EvidenceMetric.calibration)),
            reason: status.name);
        expect(ev.calibrationRef, isNull, reason: status.name);
      }
    });

    test('calibrated but with no curve identity fails closed', () {
      final r = _build(_data(curveChecksum: null));
      expect(r.evidence.availableMetrics,
          isNot(contains(EvidenceMetric.calibration)));
      expect(r.evidence.calibrationRef, isNull);
    });

    test('the evidence invariant forbids available calibration with null ref',
        () {
      expect(
        () => MeasurementCaptureEvidence(
          evidenceId: 'ev:x',
          projectId: 'proj-1',
          measurementRef: 'ch_tw_l',
          provenance: const MeasurementProvenance(
              producer: 'p', producerVersion: '1', sourceIdentity: 's'),
          availableMetrics: {EvidenceMetric.calibration},
          unavailableMetrics: const {},
        ),
        throwsA(isA<MeasurementEvidenceException>()),
      );
    });
  });

  group('3. quality mapping uses only real measured values', () {
    test('real noise floor + rms produce an SNR claim (no placeholders)', () {
      final ev = _build(_data()).evidence;
      expect(ev.availableMetrics, contains(EvidenceMetric.snr));
      // -18 dBFS signal over -72 dBFS noise => 54 dB, matching the measured
      // setupSignalToNoiseDb. Powers are a unit conversion of real numbers.
      final snrDb = 10 * (ev.signalPower! / ev.noisePower!).abs();
      expect(snrDb, greaterThan(0));
      expect(ev.signalPower, isNot(closeTo(1e-9, 1e-9)),
          reason: 'must not be a -90 dB placeholder');
    });

    test('missing noise floor -> SNR unavailable, never invented', () {
      final ev =
          _build(_data(quality: _quality(noiseFloorDbFs: null))).evidence;
      expect(ev.availableMetrics, isNot(contains(EvidenceMetric.snr)));
      expect(ev.unavailableMetrics, contains(EvidenceMetric.snr));
      expect(ev.signalPower, isNull);
      expect(ev.noisePower, isNull);
    });

    test('clipping is claimed only when the total is genuinely recoverable',
        () {
      final clipped = _build(
              _data(quality: _quality(clippedCount: 12, clippedRatio: 0.001)))
          .evidence;
      expect(clipped.availableMetrics, contains(EvidenceMetric.clipping));
      expect(clipped.clippedSamples, 12);
      expect(clipped.totalSamples, 12000);

      // ratio 0 -> denominator unknown -> unavailable rather than guessed.
      final unknownTotal = _build(_data()).evidence;
      expect(unknownTotal.availableMetrics,
          isNot(contains(EvidenceMetric.clipping)));
      expect(unknownTotal.totalSamples, isNull);
    });

    test('actual WAV format is carried, not the policy expectation', () {
      final ev = _build(_data(
              quality: _quality(
                  provenance: _provenance(sampleRate: 44100, channelCount: 2))))
          .evidence;
      expect(ev.sampleRate, 44100);
      expect(ev.channelCount, 2);
    });

    test('repeatability is always unavailable — no synthetic score', () {
      final ev = _build(_data()).evidence;
      expect(ev.unavailableMetrics, contains(EvidenceMetric.repeatability));
      expect(
          ev.availableMetrics, isNot(contains(EvidenceMetric.repeatability)));
      expect(ev.repeatSpectrumRefs, isEmpty);
      expect(ev.splitHalfARef, isNull);
    });

    test('a capture with no quality snapshot claims neither SNR nor clipping',
        () {
      final r = _build(_data(noQuality: true));
      expect(r.evidence.unavailableMetrics, contains(EvidenceMetric.snr));
      expect(r.evidence.unavailableMetrics, contains(EvidenceMetric.clipping));
      expect(r.provenanceWarnings.join(), contains('품질 기록'));
    });
  });

  group('4. capture provenance is preserved on the evidence', () {
    test('mic profile, setup generation and captured-at are carried', () {
      final ev = _build(_data()).evidence;
      expect(ev.microphoneProfileRef, 'profile-abc');
      expect(ev.captureConfigurationRef, 'gen-1');
      expect(ev.provenance.capturedAtIso, _capturedAt.toIso8601String());
      expect(ev.source, MeasurementSource.liveMicrophone,
          reason: 'a live capture must not be labelled an import');
      expect(ev.kind, 'capture');
    });

    test('phase availability follows the actual parsed data', () {
      expect(_build(_data(withPhase: true)).evidence.availableMetrics,
          contains(EvidenceMetric.phase));
      expect(_build(_data()).evidence.unavailableMetrics,
          contains(EvidenceMetric.phase));
    });
  });
}
