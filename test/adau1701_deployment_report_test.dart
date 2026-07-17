import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kDspIdentity = 'DSP1701.100.00.01';
const _kTransportIdentity = 'COM27';
final _kAttemptedAt = DateTime.utc(2025, 7, 1, 10);
final _kSnapshotAt = DateTime.utc(2025, 7, 1, 9, 58);

// ── Fake transport ────────────────────────────────────────────────────────────

class _FakeTransport implements Adau1701RawReadTransport {
  @override
  final bool isConnected;
  @override
  bool get handshakeComplete => true;
  @override
  String? get detectedProfile => _kDspIdentity;
  final Object? _error;

  const _FakeTransport({this.isConnected = true, Object? error})
      : _error = error;

  @override
  Future<RawDspStateSnapshot> readRawDspState() async {
    if (_error != null) throw _error!;
    return RawDspStateSnapshot(
      deviceId: _kDspIdentity,
      timestamp: _kSnapshotAt,
      blockId: 0x2202,
      payload: _validPayload(),
    );
  }
}

// Valid 513-byte payload: freq=1000 Hz, gain=0 dB, Q=1.0, property08State=0.
List<int> _validPayload() {
  final p = List<int>.filled(513, 0);
  p[19] = 0xE8;
  p[20] = 0x03;
  p[21] = 0x00;
  p[23] = 0x0A;
  p[24] = 0x00;
  p[154] = 0x01; // unique page-1 marker
  p[308] = 0x02; // unique page-2 marker
  return p;
}

// ── Write fixtures ─────────────────────────────────────────────────────────────

const _kGainPlan = Adau1701PeqWriteFields(gain: true);

const _kPassResult = Icp5PhaseCResult(
  success: true,
  wasActualWrite: true,
  writeMayHaveReachedDevice: true,
  message: 'PASS_ACK',
);

const _kFailResult = Icp5PhaseCResult(
  success: false,
  wasActualWrite: true,
  writeMayHaveReachedDevice: true,
  message: 'no ACK received',
);

const _kRollbackPassResult = Icp5PhaseCResult(
  success: true,
  wasActualWrite: true,
  writeMayHaveReachedDevice: true,
  message: 'RESTORE PASS_ACK',
);

const _kRollbackFailResult = Icp5PhaseCResult(
  success: false,
  wasActualWrite: true,
  writeMayHaveReachedDevice: true,
  message: 'RESTORE no ACK',
);

// ── Preflight helpers ─────────────────────────────────────────────────────────

Future<Adau1701PreflightResult> _preflight({
  bool isConnected = true,
  Object? readError,
}) async {
  final transport = _FakeTransport(
    isConnected: isConnected,
    error: readError,
  );
  return Adau1701DeploymentPreflight(transport: transport)
      .run(writePlan: _kGainPlan);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Adau1701DeploymentReport — preflight pass', () {
    test('passing preflight + successful write → all fields populated',
        () async {
      final pre = await _preflight();
      const outcome = Icp5PhaseCOutcome(
        test: _kPassResult,
        stopActivated: false,
      );

      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: _kTransportIdentity,
        outcome: outcome,
        attemptedAt: _kAttemptedAt,
      );

      expect(r.attemptedAt, _kAttemptedAt);
      expect(r.dspIdentity, _kDspIdentity);
      expect(r.transportIdentity, _kTransportIdentity);
      expect(r.snapshotCapturedAt, _kSnapshotAt);
      expect(r.originalStateAvailable, isTrue);
      expect(r.coverageResult, isTrue);
      expect(r.preflightStatus, Adau1701PreflightStatus.passed);
      expect(r.preflightFailureReason, isNull);
      expect(r.deploymentAllowed, isTrue);
      expect(r.deploymentResult, same(_kPassResult));
      expect(r.rollbackResult, isNull);
      expect(r.deploymentSucceeded, isTrue);
      expect(r.rollbackRequired, isFalse);
    });

    test('passing preflight + write failure + rollback pass', () async {
      final pre = await _preflight();
      const outcome = Icp5PhaseCOutcome(
        test: _kFailResult,
        restore: _kRollbackPassResult,
        stopActivated: false,
      );

      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: _kTransportIdentity,
        outcome: outcome,
        attemptedAt: _kAttemptedAt,
      );

      expect(r.deploymentAllowed, isTrue);
      expect(r.deploymentSucceeded, isFalse);
      expect(r.rollbackRequired, isTrue);
      expect(r.rollbackSucceeded, isTrue);
      expect(r.rollbackResult, same(_kRollbackPassResult));
    });

    test('preflightFailureReason is null when preflight passed', () async {
      final pre = await _preflight();
      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: _kTransportIdentity,
        outcome: const Icp5PhaseCOutcome(
          test: _kPassResult,
          stopActivated: false,
        ),
        attemptedAt: _kAttemptedAt,
      );
      expect(r.preflightFailureReason, isNull);
    });
  });

  group('Adau1701DeploymentReport — preflight failure', () {
    test('transportNotReady → deployment blocked, identity absent', () async {
      final pre = await _preflight(isConnected: false);

      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: _kTransportIdentity,
        outcome: null,
        attemptedAt: _kAttemptedAt,
      );

      expect(r.preflightStatus, Adau1701PreflightStatus.transportNotReady);
      expect(r.preflightFailureReason, isNotEmpty);
      expect(r.deploymentAllowed, isFalse);
      expect(r.dspIdentity, isNull);
      expect(r.snapshotCapturedAt, isNull);
      expect(r.originalStateAvailable, isFalse);
      expect(r.coverageResult, isNull);
      expect(r.deploymentResult, isNull);
      expect(r.rollbackResult, isNull);
      expect(r.deploymentSucceeded, isFalse);
    });

    test('transportNotReady → preflightFailureReason is non-empty', () async {
      final pre = await _preflight(isConnected: false);
      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: null,
        outcome: null,
        attemptedAt: _kAttemptedAt,
      );
      expect(r.preflightFailureReason, isNotNull);
      expect(r.preflightFailureReason, isNotEmpty);
      expect(r.transportIdentity, isNull);
    });
  });

  group('Adau1701DeploymentReport — raw read failure', () {
    test('rawReadFailed → dspIdentity present, snapshot absent', () async {
      final pre = await _preflight(readError: StateError('port disconnected'));

      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: _kTransportIdentity,
        outcome: null,
        attemptedAt: _kAttemptedAt,
      );

      expect(r.preflightStatus, Adau1701PreflightStatus.rawReadFailed);
      expect(r.preflightFailureReason, contains('port disconnected'));
      expect(r.deploymentAllowed, isFalse);
      expect(r.dspIdentity, _kDspIdentity);
      expect(r.snapshotCapturedAt, isNull);
      expect(r.originalStateAvailable, isFalse);
      expect(r.coverageResult, isNull);
      expect(r.deploymentResult, isNull);
    });

    test('preflightFailureReason contains the error message', () async {
      final pre = await _preflight(readError: StateError('USB timeout'));
      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: _kTransportIdentity,
        outcome: null,
        attemptedAt: _kAttemptedAt,
      );
      expect(r.preflightFailureReason, contains('USB timeout'));
    });
  });

  group('Adau1701DeploymentReport — rollback failure', () {
    test('write fails + rollback fails → rollbackSucceeded false', () async {
      final pre = await _preflight();
      const outcome = Icp5PhaseCOutcome(
        test: _kFailResult,
        restore: _kRollbackFailResult,
        stopActivated: true,
      );

      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: _kTransportIdentity,
        outcome: outcome,
        attemptedAt: _kAttemptedAt,
      );

      expect(r.deploymentAllowed, isTrue);
      expect(r.deploymentSucceeded, isFalse);
      expect(r.rollbackRequired, isTrue);
      expect(r.rollbackSucceeded, isFalse);
      expect(r.rollbackResult!.success, isFalse);
      expect(r.rollbackResult!.message, 'RESTORE no ACK');
    });

    test('rollback failure message is preserved verbatim', () async {
      final pre = await _preflight();
      const restore = Icp5PhaseCResult(
        success: false,
        wasActualWrite: true,
        writeMayHaveReachedDevice: true,
        message: 'RESTORE FAILED · STOP',
      );
      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: _kTransportIdentity,
        outcome: const Icp5PhaseCOutcome(
          test: _kFailResult,
          restore: restore,
          stopActivated: true,
        ),
        attemptedAt: _kAttemptedAt,
      );
      expect(r.rollbackResult!.message, 'RESTORE FAILED · STOP');
    });
  });

  group('Adau1701DeploymentReport — field invariants', () {
    test('attemptedAt is preserved exactly', () async {
      final ts = DateTime.utc(2025, 12, 31, 23, 59, 59);
      final pre = await _preflight();
      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: null,
        outcome: null,
        attemptedAt: ts,
      );
      expect(r.attemptedAt, ts);
    });

    test('rollbackRequired false when no rollback in outcome', () async {
      final pre = await _preflight();
      final r = Adau1701DeploymentReport.fromAttempt(
        preflight: pre,
        transportIdentity: _kTransportIdentity,
        outcome: const Icp5PhaseCOutcome(
          test: _kPassResult,
          stopActivated: false,
        ),
        attemptedAt: _kAttemptedAt,
      );
      expect(r.rollbackRequired, isFalse);
      expect(r.rollbackSucceeded, isFalse);
    });
  });
}
