import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/measurement_evidence.dart';

Map<String, dynamic> _cycle(Map<String, dynamic> j) =>
    jsonDecode(jsonEncode(j)) as Map<String, dynamic>;

MeasurementProvenance _prov({String? hash = 'sha256:abc'}) =>
    MeasurementProvenance(
      producer: 'ProMeasurementParser',
      producerVersion: '1',
      sourceIdentity: 'woofer.frd',
      contentHash: hash,
      label: 'left woofer',
    );

ImportedMeasurementEvidence _frd({
  bool phasePresent = false,
  Set<EvidenceMetric>? available,
  Set<EvidenceMetric>? unavailable,
  MeasurementDomain domain = MeasurementDomain.acousticResponse,
  bool magnitudePresent = true,
  MeasurementSource source = MeasurementSource.importedFrd,
}) =>
    ImportedMeasurementEvidence(
      evidenceId: 'ev1',
      projectId: 'p1',
      measurementRef: 'meas1',
      domain: domain,
      source: source,
      provenance: _prov(),
      availableMetrics: available ??
          {
            EvidenceMetric.validBandCoverage,
            if (phasePresent) EvidenceMetric.phase,
          },
      unavailableMetrics: unavailable ??
          {
            EvidenceMetric.repeatability,
            EvidenceMetric.snr,
            EvidenceMetric.clipping,
          },
      displayName: 'woofer.frd',
      originalFormat: 'FRD',
      parserSchemaVersion: '1',
      magnitudePresent: magnitudePresent,
      phasePresent: phasePresent,
      impedancePresent: false,
    );

ImportedMeasurementEvidence _zma() => ImportedMeasurementEvidence(
      evidenceId: 'ev2',
      projectId: 'p1',
      measurementRef: 'meas2',
      domain: MeasurementDomain.impedance,
      source: MeasurementSource.importedZma,
      provenance: _prov(),
      availableMetrics: {EvidenceMetric.validBandCoverage},
      unavailableMetrics: {
        EvidenceMetric.repeatability,
        EvidenceMetric.snr,
        EvidenceMetric.clipping,
      },
      displayName: 'woofer.zma',
      originalFormat: 'ZMA',
      parserSchemaVersion: '1',
      magnitudePresent: false,
      phasePresent: false,
      impedancePresent: true,
    );

MeasurementCaptureEvidence _capture({
  bool withSplitHalf = true,
  bool withSnr = true,
  bool withClip = true,
  Set<EvidenceMetric>? available,
}) =>
    MeasurementCaptureEvidence(
      evidenceId: 'evc',
      projectId: 'p1',
      measurementRef: 'sess1',
      provenance: _prov(hash: null),
      availableMetrics: available ??
          {
            EvidenceMetric.validBandCoverage,
            if (withSplitHalf) EvidenceMetric.repeatability,
            if (withSnr) EvidenceMetric.snr,
            if (withClip) EvidenceMetric.clipping,
          },
      unavailableMetrics: const {EvidenceMetric.calibration},
      sampleRate: 48000,
      channelCount: 1,
      fftSize: 65536,
      windowType: 'hann',
      averagingMethod: 'welch',
      splitHalfARef: withSplitHalf ? 'specA' : null,
      splitHalfBRef: withSplitHalf ? 'specB' : null,
      signalPower: withSnr ? 100.0 : null,
      noisePower: withSnr ? 1.0 : null,
      clippedSamples: withClip ? 2 : null,
      totalSamples: withClip ? 100000 : null,
    );

void main() {
  group('Round-trip', () {
    test('1. FRD evidence', () {
      final a = _frd(phasePresent: true);
      final b = ImportedMeasurementEvidence.fromJson(_cycle(a.toJson()));
      expect(b.toJson(), a.toJson());
      expect(b.domain, MeasurementDomain.acousticResponse);
    });
    test('2. ZMA evidence', () {
      final a = _zma();
      final b = ImportedMeasurementEvidence.fromJson(_cycle(a.toJson()));
      expect(b.toJson(), a.toJson());
      expect(b.domain, MeasurementDomain.impedance);
    });
    test('3. Live capture evidence', () {
      final a = _capture();
      final b = MeasurementCaptureEvidence.fromJson(_cycle(a.toJson()));
      expect(b.toJson(), a.toJson());
    });
    test('base dispatch via MeasurementEvidence.fromJson', () {
      expect(MeasurementEvidence.fromJson(_cycle(_frd().toJson())),
          isA<ImportedMeasurementEvidence>());
      expect(MeasurementEvidence.fromJson(_cycle(_capture().toJson())),
          isA<MeasurementCaptureEvidence>());
    });
  });

  group('Strict parsing', () {
    test('4. unsupported schema rejected', () {
      final j = _frd().toJson()..['schemaVersion'] = 9;
      expect(() => ImportedMeasurementEvidence.fromJson(j),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('5. unknown key / unknown enum rejected', () {
      final j1 = _frd().toJson()..['surprise'] = 1;
      expect(() => ImportedMeasurementEvidence.fromJson(j1),
          throwsA(isA<MeasurementEvidenceException>()));
      final j2 = _frd().toJson()..['source'] = 'importedXyz';
      expect(() => ImportedMeasurementEvidence.fromJson(j2),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('6. empty projectId/evidenceId/measurementRef rejected', () {
      for (final key in ['projectId', 'evidenceId', 'measurementRef']) {
        final j = _frd().toJson()..[key] = '';
        expect(() => ImportedMeasurementEvidence.fromJson(j),
            throwsA(isA<MeasurementEvidenceException>()),
            reason: 'empty $key');
      }
    });
  });

  group('Domain / source invariants', () {
    test('7. FRD must be acousticResponse', () {
      expect(() => _frd(domain: MeasurementDomain.impedance),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('8. ZMA must be impedance (acoustic rejected)', () {
      expect(
          () => ImportedMeasurementEvidence(
                evidenceId: 'x',
                projectId: 'p',
                measurementRef: 'm',
                domain: MeasurementDomain.acousticResponse, // wrong for ZMA
                source: MeasurementSource.importedZma,
                provenance: _prov(),
                availableMetrics: {EvidenceMetric.validBandCoverage},
                unavailableMetrics: const {},
                displayName: 'x.zma',
                originalFormat: 'ZMA',
                parserSchemaVersion: '1',
                magnitudePresent: false,
                phasePresent: false,
                impedancePresent: true,
              ),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('9. FRD magnitude required', () {
      expect(() => _frd(magnitudePresent: false),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('10. FRD phase optional (present and absent both valid)', () {
      expect(_frd(phasePresent: false).phasePresent, isFalse);
      expect(_frd(phasePresent: true).phasePresent, isTrue);
    });
    test('11. ZMA impedance required', () {
      expect(
          () => ImportedMeasurementEvidence(
                evidenceId: 'x',
                projectId: 'p',
                measurementRef: 'm',
                domain: MeasurementDomain.impedance,
                source: MeasurementSource.importedZma,
                provenance: _prov(),
                availableMetrics: {EvidenceMetric.validBandCoverage},
                unavailableMetrics: const {},
                displayName: 'x.zma',
                originalFormat: 'ZMA',
                parserSchemaVersion: '1',
                magnitudePresent: false,
                phasePresent: false,
                impedancePresent: false, // missing
              ),
          throwsA(isA<MeasurementEvidenceException>()));
    });
  });

  group('Import cannot fabricate metrics', () {
    test('12/13/14. repeatability/SNR/clipping available claim rejected', () {
      for (final m in [
        EvidenceMetric.repeatability,
        EvidenceMetric.snr,
        EvidenceMetric.clipping,
      ]) {
        expect(() => _frd(available: {EvidenceMetric.validBandCoverage, m}),
            throwsA(isA<MeasurementEvidenceException>()),
            reason: m.name);
      }
    });
  });

  group('Capture invariants', () {
    test('15. SNR available needs both signal and noise power', () {
      expect(
          () => _capture(withSnr: false, available: {
                EvidenceMetric.validBandCoverage,
                EvidenceMetric.snr, // claimed but powers null
              }),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('16. clipping available needs both counts', () {
      expect(
          () => _capture(withClip: false, available: {
                EvidenceMetric.validBandCoverage,
                EvidenceMetric.clipping, // claimed but counts null
              }),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('17. clipped > total rejected', () {
      expect(
          () => MeasurementCaptureEvidence(
                evidenceId: 'e',
                projectId: 'p',
                measurementRef: 'm',
                provenance: _prov(hash: null),
                availableMetrics: const {},
                unavailableMetrics: const {},
                clippedSamples: 200,
                totalSamples: 100,
              ),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('18. single spectrum claiming repeatability rejected', () {
      expect(
          () => _capture(withSplitHalf: false, available: {
                EvidenceMetric.validBandCoverage,
                EvidenceMetric.repeatability, // no A/B, no >=2 repeats
              }),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('19. split-half A and B present → repeatability allowed', () {
      final c = _capture(); // withSplitHalf true, repeatability available
      expect(c.availableMetrics.contains(EvidenceMetric.repeatability), isTrue);
    });
    test('a metric both available and unavailable is rejected', () {
      expect(
          () => _capture(available: {
                EvidenceMetric.validBandCoverage,
                EvidenceMetric.calibration, // also in unavailable set
              }),
          throwsA(isA<MeasurementEvidenceException>()));
    });
  });

  group('Boundaries / provenance / determinism', () {
    test('20. no raw PCM/spectrum field in JSON, and such keys are rejected',
        () {
      final json = _capture().toJson();
      final text = jsonEncode(json).toLowerCase();
      for (final k in [
        'spectra',
        'spectrum',
        'pcm',
        'samples"',
        'magnitudes'
      ]) {
        expect(text.contains('"$k'), isFalse, reason: k);
      }
      final poisoned = _frd().toJson()
        ..['spectraDb'] = [
          [1, 2, 3]
        ];
      expect(() => ImportedMeasurementEvidence.fromJson(poisoned),
          throwsA(isA<MeasurementEvidenceException>()));
    });
    test('21. contentHash / provenance preserved', () {
      final b = ImportedMeasurementEvidence.fromJson(_cycle(_frd().toJson()));
      expect(b.provenance.contentHash, 'sha256:abc');
      expect(b.provenance.producer, 'ProMeasurementParser');
      expect(b.provenance.label, 'left woofer');
    });
    test('22. no confidence policy id/version stored on evidence', () {
      final text = jsonEncode(_frd().toJson()).toLowerCase();
      expect(text.contains('policyid'), isFalse);
      expect(text.contains('policyversion'), isFalse);
      expect(text.contains('confidence'), isFalse);
    });
    test('23. round-trip is deterministic', () {
      final a = _capture().toJson();
      final b = _capture().toJson();
      expect(a, b);
    });
    test('placeholder/demo are not production-usable', () {
      final cap = _capture();
      expect(cap.isProductionUsable, isTrue);
      // A source that is placeholder/demo would not be — asserted via enum.
      expect(MeasurementSource.placeholder.isRealMeasurement, isFalse);
      expect(MeasurementSource.generatedDemo.isRealMeasurement, isFalse);
      expect(MeasurementSource.importedFrd.isRealMeasurement, isTrue);
    });
    test('imported evidence requires a contentHash', () {
      expect(
          () => ImportedMeasurementEvidence(
                evidenceId: 'e',
                projectId: 'p',
                measurementRef: 'm',
                domain: MeasurementDomain.acousticResponse,
                source: MeasurementSource.importedFrd,
                provenance: _prov(hash: null),
                availableMetrics: {EvidenceMetric.validBandCoverage},
                unavailableMetrics: const {},
                displayName: 'x.frd',
                originalFormat: 'FRD',
                parserSchemaVersion: '1',
                magnitudePresent: true,
                phasePresent: false,
                impedancePresent: false,
              ),
          throwsA(isA<MeasurementEvidenceException>()));
    });
  });
}
