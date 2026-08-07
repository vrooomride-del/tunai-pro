// Phase 3-D2 — measurement_setup_readiness.dart: identity/expiry/staleness
// and JSON round-trip tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_model.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';

MeasurementSetupReadinessIdentity _identity({
  String projectId = 'p1',
  String? profileChecksum = 'checksum-a',
  String? calibrationCurveChecksum = 'curve-a',
  String? calibrationAngle = 'zeroDegree',
  String inputDeviceIdentity = 'device:dev1',
  int expectedSampleRate = 48000,
  int expectedChannelCount = 1,
  String qualityPolicyVersion = 'provisional-1',
}) =>
    MeasurementSetupReadinessIdentity(
      projectId: projectId,
      profileChecksum: profileChecksum,
      calibrationCurveChecksum: calibrationCurveChecksum,
      calibrationAngle: calibrationAngle,
      inputDeviceIdentity: inputDeviceIdentity,
      expectedSampleRate: expectedSampleRate,
      expectedChannelCount: expectedChannelCount,
      qualityPolicyVersion: qualityPolicyVersion,
    );

MeasurementQualityEvaluation _readyEvaluation() => MeasurementQualityEvaluation(
      statuses: const {MeasurementQualityStatus.ready},
      metrics: MeasurementQualityMetrics(
        peakDbFs: -10,
        rmsDbFs: -20,
        clippedSampleCount: 0,
        clippedSampleRatio: 0,
        duration: const Duration(seconds: 3),
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
      ),
    );

MeasurementSetupReadinessSnapshot _readySnapshot({
  MeasurementSetupReadinessIdentity? identity,
  DateTime? checkedAt,
  Duration validity = const Duration(minutes: 30),
}) {
  final at = checkedAt ?? DateTime.utc(2026, 1, 1, 12, 0, 0);
  return MeasurementSetupReadinessSnapshot(
    identity: identity ?? _identity(),
    generationId: 'gen-1',
    noiseFloorEvaluation: _readyEvaluation(),
    levelCheckEvaluation: _readyEvaluation(),
    blockers: const [],
    warnings: const [],
    checkedAt: at,
    expiresAt: at.add(validity),
    isReady: true,
  );
}

void main() {
  group('MeasurementSetupReadinessIdentity equality', () {
    test('two identical identities are equal', () {
      expect(_identity(), _identity());
      expect(_identity().hashCode, _identity().hashCode);
    });

    test('differing profileChecksum makes identities unequal', () {
      expect(_identity(profileChecksum: 'checksum-a'),
          isNot(_identity(profileChecksum: 'checksum-b')));
    });

    test('differing calibrationAngle makes identities unequal', () {
      expect(_identity(calibrationAngle: 'zeroDegree'),
          isNot(_identity(calibrationAngle: 'ninetyDegree')));
    });

    test('differing inputDeviceIdentity makes identities unequal', () {
      expect(_identity(inputDeviceIdentity: 'device:dev1'),
          isNot(_identity(inputDeviceIdentity: 'device:dev2')));
    });

    test('system-default vs specific device differ even with same base id', () {
      expect(
          _identity(
              inputDeviceIdentity: MeasurementSetupReadinessIdentity
                  .kSystemDefaultInputDeviceIdentity),
          isNot(_identity(
              inputDeviceIdentity:
                  MeasurementSetupReadinessIdentity.specificInputDeviceIdentity(
                      'dev1'))));
    });

    test('differing qualityPolicyVersion makes identities unequal', () {
      expect(_identity(qualityPolicyVersion: 'v1'),
          isNot(_identity(qualityPolicyVersion: 'v2')));
    });

    test('differing projectId makes identities unequal', () {
      expect(_identity(projectId: 'a'), isNot(_identity(projectId: 'b')));
    });
  });

  group('MeasurementSetupReadinessSnapshot.isExpired', () {
    test('not expired well before expiresAt', () {
      final snapshot = _readySnapshot(checkedAt: DateTime.utc(2026, 1, 1));
      expect(snapshot.isExpired(now: DateTime.utc(2026, 1, 1, 0, 5)), isFalse);
    });

    test('expired after expiresAt', () {
      final snapshot = _readySnapshot(
          checkedAt: DateTime.utc(2026, 1, 1),
          validity: const Duration(minutes: 30));
      expect(snapshot.isExpired(now: DateTime.utc(2026, 1, 1, 1, 0)), isTrue);
    });

    test('expired exactly at expiresAt (inclusive boundary)', () {
      final checkedAt = DateTime.utc(2026, 1, 1);
      final snapshot = _readySnapshot(
          checkedAt: checkedAt, validity: const Duration(minutes: 30));
      expect(
          snapshot.isExpired(now: checkedAt.add(const Duration(minutes: 30))),
          isTrue);
    });

    test(
        'a checkedAt implausibly in the future fails safe to expired '
        '(system clock anomaly)', () {
      final now = DateTime.utc(2026, 1, 1);
      final snapshot = _readySnapshot(
          checkedAt: now.add(const Duration(hours: 5)),
          validity: const Duration(hours: 10));
      // Without the clock-anomaly guard this would read as "not expired"
      // (now is before expiresAt) -- the guard must override that.
      expect(snapshot.isExpired(now: now), isTrue);
    });

    test(
        'a checkedAt only slightly in the future (clock skew tolerance) '
        'is not treated as an anomaly', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final snapshot = _readySnapshot(
          checkedAt: now.add(const Duration(seconds: 10)),
          validity: const Duration(minutes: 30));
      expect(snapshot.isExpired(now: now), isFalse);
    });
  });

  group('MeasurementSetupReadinessSnapshot.isStaleFor', () {
    test('same identity is not stale', () {
      final snapshot = _readySnapshot();
      expect(snapshot.isStaleFor(_identity()), isFalse);
    });

    test('a different identity is stale', () {
      final snapshot = _readySnapshot();
      expect(snapshot.isStaleFor(_identity(profileChecksum: 'other')), isTrue);
    });
  });

  group('MeasurementSetupReadinessSnapshot.isUsableNow', () {
    test('ready + not expired + not stale -> usable', () {
      final snapshot =
          _readySnapshot(checkedAt: DateTime.utc(2026, 1, 1, 12, 0, 0));
      expect(
          snapshot.isUsableNow(_identity(),
              now: DateTime.utc(2026, 1, 1, 12, 5, 0)),
          isTrue);
    });

    test('ready but expired -> not usable', () {
      final snapshot =
          _readySnapshot(checkedAt: DateTime.utc(2026, 1, 1, 12, 0, 0));
      expect(
          snapshot.isUsableNow(_identity(),
              now: DateTime.utc(2026, 1, 1, 13, 0, 0)),
          isFalse);
    });

    test('ready but identity changed -> not usable', () {
      final snapshot = _readySnapshot();
      expect(
          snapshot.isUsableNow(_identity(profileChecksum: 'changed')), isFalse);
    });

    test('not ready -> never usable regardless of expiry/identity', () {
      final at = DateTime.utc(2026, 1, 1);
      final snapshot = MeasurementSetupReadinessSnapshot(
        identity: _identity(),
        generationId: 'gen-2',
        blockers: const ['Select an input device.'],
        warnings: const [],
        checkedAt: at,
        expiresAt: at.add(const Duration(minutes: 30)),
        isReady: false,
      );
      expect(snapshot.isUsableNow(_identity(), now: at), isFalse);
    });
  });

  group('JSON round-trip', () {
    test('a full ready snapshot round-trips including evaluations', () {
      final snapshot = _readySnapshot();
      final decoded =
          MeasurementSetupReadinessSnapshot.fromJson(snapshot.toJson());
      expect(decoded.identity, snapshot.identity);
      expect(decoded.generationId, snapshot.generationId);
      expect(decoded.isReady, isTrue);
      expect(decoded.noiseFloorEvaluation?.metrics.rmsDbFs,
          snapshot.noiseFloorEvaluation?.metrics.rmsDbFs);
      expect(decoded.levelCheckEvaluation?.statuses,
          {MeasurementQualityStatus.ready});
    });

    test(
        'a snapshot with no evaluations yet (blocked, pre-check) '
        'round-trips', () {
      final at = DateTime.utc(2026, 1, 1);
      final snapshot = MeasurementSetupReadinessSnapshot(
        identity: _identity(),
        generationId: 'gen-3',
        blockers: const ['Select an input device.'],
        warnings: const [],
        checkedAt: at,
        expiresAt: at.add(const Duration(minutes: 30)),
        isReady: false,
      );
      final decoded =
          MeasurementSetupReadinessSnapshot.fromJson(snapshot.toJson());
      expect(decoded.noiseFloorEvaluation, isNull);
      expect(decoded.levelCheckEvaluation, isNull);
      expect(decoded.blockers, ['Select an input device.']);
      expect(decoded.isReady, isFalse);
    });

    test('a deviceSnapshot round-trips', () {
      final device = MeasurementInputDeviceSnapshot(
        deviceId: 'dev1',
        label: 'USB Mic',
        isSystemDefault: false,
        platform: 'macos',
        actualSampleRate: 48000,
        actualChannelCount: 1,
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final at = DateTime.utc(2026, 1, 1);
      final snapshot = MeasurementSetupReadinessSnapshot(
        identity: _identity(),
        generationId: 'gen-4',
        deviceSnapshot: device,
        blockers: const [],
        warnings: const [],
        checkedAt: at,
        expiresAt: at.add(const Duration(minutes: 30)),
        isReady: true,
      );
      final decoded =
          MeasurementSetupReadinessSnapshot.fromJson(snapshot.toJson());
      expect(decoded.deviceSnapshot?.deviceId, 'dev1');
    });

    test('malformed identity map falls back to defaults, never throws', () {
      final decoded = MeasurementSetupReadinessIdentity.fromJson(const {});
      expect(decoded.projectId, '');
      expect(decoded.profileChecksum, isNull);
    });
  });

  group('MeasurementQualityEvaluationResult defensive decode', () {
    test(
        'a corrupt noiseFloorMetrics blob does not throw — falls back to '
        'null evaluation', () {
      final at = DateTime.utc(2026, 1, 1);
      final json = {
        'identity': _identity().toJson(),
        'generationId': 'gen-5',
        'noiseFloorMetrics': {'not': 'valid metrics shape'},
        'blockers': <String>[],
        'warnings': <String>[],
        'checkedAt': at.toIso8601String(),
        'expiresAt': at.add(const Duration(minutes: 30)).toIso8601String(),
        'isReady': false,
      };
      final decoded = MeasurementSetupReadinessSnapshot.fromJson(json);
      expect(decoded.generationId, 'gen-5');
    });
  });
}
