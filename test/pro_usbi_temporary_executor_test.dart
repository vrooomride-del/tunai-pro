// ── TUNAI PRO Phase T4A — USBi Temporary Executor Tests ──────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_usbi_executor_data.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/core/pro_usbi_temporary_executor.dart';
import 'package:tunai_pro/core/pro_transport_command_data.dart';
import 'package:tunai_pro/core/pro_hardware_transport.dart';
import 'package:tunai_pro/core/pro_export_data.dart'; // DspTargetPlatform

// ── Helpers ───────────────────────────────────────────────────────────────────

UsbiExecutionRequest _req({
  bool userConfirmed = true,
  int addressInt = kMasterVolumeLAddr,       // 0x0067
  String addressHex = '0x0067',
  double valueFloat = 0.5,
  int fixedPointInt = 0x00800000,
  HardwareTransportBackend backend =
      HardwareTransportBackend.usbiWindowsTemporary,
}) =>
    UsbiExecutionRequest(
      id:                'test_req_001',
      commandEnvelopeId: 'test_env_001',
      transportBackend:  backend,
      parameterId:       'master_volume_l',
      logicalName:       'Master Volume Left',
      addressHex:        addressHex,
      addressInt:        addressInt,
      fixedPointHex:     '0x00800000',
      fixedPointInt:     fixedPointInt,
      valueFloat:        valueFloat,
      userConfirmed:     userConfirmed,
    );

ProUsbiTemporaryExecutor _executor({
  bool isWindows = true,
  bool backendAvailable = true,
  bool simulateAckSuccess = true,
}) {
  final backend = backendAvailable
      ? ProUsbiNativeBackendFake(simulateAckSuccess: simulateAckSuccess)
      : const ProUsbiNativeBackendDisabled();
  return ProUsbiTemporaryExecutor(
    isWindowsPlatform: () => isWindows,
    backend: backend,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Guard D1 — platform must be Windows', () {
    test('non-Windows blocks with unsupportedPlatform status', () async {
      final ex = _executor(isWindows: false);
      final result = await ex.execute(_req());
      expect(result.status, UsbiExecutionStatus.unsupportedPlatform);
      expect(result.wasActualWrite, false);
    });

    test('non-Windows result has platformNotWindows guard code', () async {
      final ex = _executor(isWindows: false);
      final result = await ex.execute(_req());
      final failed = result.guardResults.firstWhere((g) => !g.passed);
      expect(failed.code, UsbiExecutionGuardCode.platformNotWindows);
    });

    test('non-Windows wasActualWrite is always false', () async {
      final ex = _executor(isWindows: false);
      final r = await ex.execute(_req());
      expect(r.wasActualWrite, false);
    });

    test('non-Windows ackReceived is always false', () async {
      final ex = _executor(isWindows: false);
      final r = await ex.execute(_req());
      expect(r.ackReceived, false);
    });
  });

  group('Guard D2 — transport must be usbiWindowsTemporary', () {
    test('simulation transport blocks execution', () async {
      final ex = _executor();
      final r = await ex.execute(
          _req(backend: HardwareTransportBackend.simulation));
      expect(r.wasActualWrite, false);
      expect(r.status, isNot(UsbiExecutionStatus.ackReceived));
    });

    test('bleMacos transport blocks execution', () async {
      final ex = _executor();
      final r = await ex.execute(
          _req(backend: HardwareTransportBackend.bleMacos));
      expect(r.wasActualWrite, false);
    });

    test('icp5 transport blocks execution', () async {
      final ex = _executor();
      final r = await ex.execute(
          _req(backend: HardwareTransportBackend.icp5));
      expect(r.wasActualWrite, false);
    });

    test('wrong transport returns transportUnavailable status', () async {
      final ex = _executor();
      final r = await ex.execute(
          _req(backend: HardwareTransportBackend.bleMacos));
      expect(r.status, UsbiExecutionStatus.transportUnavailable);
    });
  });

  group('Guard D3/D4 — address must be Master Volume L/R', () {
    test('non-master-volume address blocks with blocked status', () async {
      final ex = _executor();
      final r = await ex.execute(
          _req(addressInt: 0x0010, addressHex: '0x0010'));
      expect(r.wasActualWrite, false);
      expect(r.status, UsbiExecutionStatus.blocked);
    });

    test('non-MV address guard code is commandNotMasterVolume', () async {
      final ex = _executor();
      final r = await ex.execute(
          _req(addressInt: 0x0010, addressHex: '0x0010'));
      final failed = r.guardResults.firstWhere((g) => !g.passed);
      expect(failed.code, UsbiExecutionGuardCode.commandNotMasterVolume);
    });

    test('address 0x0067 (L) passes D3/D4', () async {
      final ex = _executor(backendAvailable: true);
      final r = await ex.execute(_req(addressInt: 0x0067, addressHex: '0x0067'));
      // All D3/D4 guards pass — may proceed to backend
      final mvGuards = r.guardResults.where((g) =>
          g.code == UsbiExecutionGuardCode.commandNotMasterVolume ||
          g.code == UsbiExecutionGuardCode.addressNotVerifiedMasterVolume);
      expect(mvGuards.every((g) => g.passed), true);
    });

    test('address 0x0064 (R) passes D3/D4', () async {
      final ex = _executor();
      final r = await ex.execute(
          _req(addressInt: 0x0064, addressHex: '0x0064'));
      final mvGuard = r.guardResults.firstWhere((g) =>
          g.code == UsbiExecutionGuardCode.commandNotMasterVolume);
      expect(mvGuard.passed, true);
    });
  });

  group('Guard D5 — value range [0.0, 1.0]', () {
    test('value 1.1 blocks execution', () async {
      final ex = _executor();
      final r = await ex.execute(_req(valueFloat: 1.1));
      expect(r.wasActualWrite, false);
    });

    test('value -0.1 blocks execution', () async {
      final ex = _executor();
      final r = await ex.execute(_req(valueFloat: -0.1));
      expect(r.wasActualWrite, false);
    });

    test('value 0.0 passes D5', () async {
      final ex = _executor(backendAvailable: true);
      final r = await ex.execute(
          _req(valueFloat: 0.0, fixedPointInt: 0x00000000));
      final vGuard = r.guardResults.firstWhere(
          (g) => g.code == UsbiExecutionGuardCode.valueOutOfRange);
      expect(vGuard.passed, true);
    });

    test('value 1.0 passes D5', () async {
      final ex = _executor(backendAvailable: true);
      final r = await ex.execute(
          _req(valueFloat: 1.0, fixedPointInt: 0x01000000));
      final vGuard = r.guardResults.firstWhere(
          (g) => g.code == UsbiExecutionGuardCode.valueOutOfRange);
      expect(vGuard.passed, true);
    });
  });

  group('Guard D6 — user confirmation', () {
    test('userConfirmed=false returns awaitingUserConfirmation', () async {
      final ex = _executor();
      final r = await ex.execute(_req(userConfirmed: false));
      expect(r.status, UsbiExecutionStatus.awaitingUserConfirmation);
      expect(r.wasActualWrite, false);
    });

    test('no backend call when user confirmation missing', () async {
      final fake = ProUsbiNativeBackendFake();
      final ex = ProUsbiTemporaryExecutor(
        isWindowsPlatform: () => true,
        backend: fake,
      );
      await ex.execute(_req(userConfirmed: false));
      expect(fake.callCount, 0);
    });
  });

  group('Guard D7 — native backend availability', () {
    test('disabled backend blocks with blocked status', () async {
      final ex = _executor(backendAvailable: false);
      final r = await ex.execute(_req());
      expect(r.status, UsbiExecutionStatus.blocked);
      expect(r.wasActualWrite, false);
    });

    test('disabled backend guard code is writeBackendDisabled', () async {
      final ex = _executor(backendAvailable: false);
      final r = await ex.execute(_req());
      final failed = r.guardResults.firstWhere((g) => !g.passed);
      expect(failed.code, UsbiExecutionGuardCode.writeBackendDisabled);
    });

    test('disabled backend error message mentions "pending"', () async {
      final ex = _executor(backendAvailable: false);
      final r = await ex.execute(_req());
      expect(r.error, contains('pending'));
    });

    test('production .disabled() constructor returns blocked result', () async {
      final ex = ProUsbiTemporaryExecutor.disabled();
      final r = await ex.execute(_req());
      expect(r.wasActualWrite, false);
      expect(r.status, isNot(UsbiExecutionStatus.ackReceived));
    });
  });

  group('Successful execution (fake backend, ACK success)', () {
    test('returns ackReceived status', () async {
      final ex = _executor();
      final r = await ex.execute(_req());
      expect(r.status, UsbiExecutionStatus.ackReceived);
    });

    test('wasActualWrite = true on success', () async {
      final ex = _executor();
      final r = await ex.execute(_req());
      expect(r.wasActualWrite, true);
    });

    test('ackReceived = true on success', () async {
      final ex = _executor();
      final r = await ex.execute(_req());
      expect(r.ackReceived, true);
    });

    test('ackByteHex is set on success', () async {
      final ex = _executor();
      final r = await ex.execute(_req());
      expect(r.ackByteHex, isNotNull);
    });

    test('all guards pass on success', () async {
      final ex = _executor();
      final r = await ex.execute(_req());
      expect(r.guardResults.every((g) => g.passed), true);
    });

    test('executedAt is set', () async {
      final ex = _executor();
      final r = await ex.execute(_req());
      expect(r.executedAt, isNotNull);
    });

    test('backend sendPacketsAndReadAck called once', () async {
      final fake = ProUsbiNativeBackendFake();
      final ex = ProUsbiTemporaryExecutor(
          isWindowsPlatform: () => true, backend: fake);
      await ex.execute(_req());
      expect(fake.callCount, 1);
    });

    test('setup packet sent matches known format', () async {
      final fake = ProUsbiNativeBackendFake();
      final ex = ProUsbiTemporaryExecutor(
          isWindowsPlatform: () => true, backend: fake);
      await ex.execute(_req());
      expect(fake.capturedSetupPackets.first,
          [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00]);
    });

    test('body packet for 0x0067+0.5 matches test vector', () async {
      final fake = ProUsbiNativeBackendFake();
      final ex = ProUsbiTemporaryExecutor(
          isWindowsPlatform: () => true, backend: fake);
      await ex.execute(
          _req(addressInt: 0x0067, fixedPointInt: 0x00800000));
      expect(fake.capturedBodyPackets.first,
          [0x00, 0x67, 0x00, 0x80, 0x00, 0x00]);
    });

    test('body packet for 0x0064+1.0 matches test vector', () async {
      final fake = ProUsbiNativeBackendFake();
      final ex = ProUsbiTemporaryExecutor(
          isWindowsPlatform: () => true, backend: fake);
      await ex.execute(
          _req(addressInt: 0x0064, addressHex: '0x0064',
              valueFloat: 1.0, fixedPointInt: 0x01000000));
      expect(fake.capturedBodyPackets.first,
          [0x00, 0x64, 0x01, 0x00, 0x00, 0x00]);
    });

    test('body packet for 0x0064+0.0 matches test vector', () async {
      final fake = ProUsbiNativeBackendFake();
      final ex = ProUsbiTemporaryExecutor(
          isWindowsPlatform: () => true, backend: fake);
      await ex.execute(
          _req(addressInt: 0x0064, addressHex: '0x0064',
              valueFloat: 0.0, fixedPointInt: 0x00000000));
      expect(fake.capturedBodyPackets.first,
          [0x00, 0x64, 0x00, 0x00, 0x00, 0x00]);
    });
  });

  group('ACK failure path', () {
    test('ackFailed backend returns ackFailed status', () async {
      final ex = _executor(simulateAckSuccess: false);
      final r = await ex.execute(_req());
      expect(r.status, UsbiExecutionStatus.ackFailed);
    });

    test('wasActualWrite = true even on ACK failure (write was sent)', () async {
      final ex = _executor(simulateAckSuccess: false);
      final r = await ex.execute(_req());
      expect(r.wasActualWrite, true);
    });

    test('ackReceived = false on ACK failure', () async {
      final ex = _executor(simulateAckSuccess: false);
      final r = await ex.execute(_req());
      expect(r.ackReceived, false);
    });
  });

  group('isEnvelopeEligible', () {
    final ex = ProUsbiTemporaryExecutor.disabled();

    TransportCommandEnvelope _env({
      int addrInt = kMasterVolumeLAddr,
      TransportCommandStatus status = TransportCommandStatus.dryRunReady,
      double value = 0.5,
    }) =>
        TransportCommandEnvelope(
          id:              'env_001',
          commandType:     TransportCommandType.writeParameter,
          status:          status,
          transportBackend: HardwareTransportBackend.usbiWindowsTemporary,
          targetPlatform:  DspTargetPlatform.adau1466,
          parameterId:     'master_volume_l',
          logicalName:     'Master Volume Left',
          addressHex:      '0x0067',
          addressInt:      addrInt,
          valueFloat:      value,
          fixedPointInt:   0x00800000,
          fixedPointHex:   '0x00800000',
          byteOrder:       'big-endian',
          writeMode:       TransportWriteMode.volatileOnly,
          requiresUserConfirmation: true,
        );

    test('eligible when MV address + dryRunReady + valid value', () {
      expect(ex.isEnvelopeEligible(_env()), true);
    });

    test('not eligible when non-MV address', () {
      expect(ex.isEnvelopeEligible(_env(addrInt: 0x0010)), false);
    });

    test('not eligible when status is blocked', () {
      expect(ex.isEnvelopeEligible(
          _env(status: TransportCommandStatus.blocked)), false);
    });

    test('not eligible when value is null-equivalent (>1.0)', () {
      expect(ex.isEnvelopeEligible(_env(value: 1.1)), false);
    });

    test('eligible for 0x0064 (R)', () {
      expect(ex.isEnvelopeEligible(_env(addrInt: kMasterVolumeRAddr)), true);
    });
  });

  group('eligibleForTemporaryUsbiExecution getter', () {
    TransportCommandEnvelope _env({
      int addrInt = kMasterVolumeLAddr,
      TransportCommandStatus status = TransportCommandStatus.dryRunReady,
      double value = 0.5,
    }) =>
        TransportCommandEnvelope(
          id:              'env_002',
          commandType:     TransportCommandType.writeParameter,
          status:          status,
          transportBackend: HardwareTransportBackend.simulation,
          targetPlatform:  DspTargetPlatform.adau1466,
          parameterId:     'mv_l',
          logicalName:     'Master Volume L',
          addressHex:      '0x0067',
          addressInt:      addrInt,
          valueFloat:      value,
          fixedPointInt:   0x00800000,
          fixedPointHex:   '0x00800000',
          byteOrder:       'big-endian',
          writeMode:       TransportWriteMode.volatileOnly,
          requiresUserConfirmation: true,
        );

    test('true for valid MV L dryRunReady envelope', () {
      expect(_env().eligibleForTemporaryUsbiExecution, true);
    });

    test('false when status is blocked', () {
      expect(
          _env(status: TransportCommandStatus.blocked)
              .eligibleForTemporaryUsbiExecution,
          false);
    });

    test('false when non-MV address', () {
      expect(_env(addrInt: 0x0010).eligibleForTemporaryUsbiExecution, false);
    });

    test('false when value out of range', () {
      expect(_env(value: 1.5).eligibleForTemporaryUsbiExecution, false);
    });

    test('isExecutableNow always false even for eligible envelope', () {
      expect(_env().isExecutableNow, false);
    });

    test('actualWriteAllowed always false even for eligible envelope', () {
      expect(_env().actualWriteAllowed, false);
    });
  });

  group('ProUsbiNativeBackendDisabled', () {
    test('isAvailable is false', () {
      const b = ProUsbiNativeBackendDisabled();
      expect(b.isAvailable, false);
    });

    test('isFake is false', () {
      const b = ProUsbiNativeBackendDisabled();
      expect(b.isFake, false);
    });

    test('sendPacketsAndReadAck returns null', () async {
      const b = ProUsbiNativeBackendDisabled();
      final r = await b.sendPacketsAndReadAck(
        setupPacket:    [0x40, 0xB2],
        bodyPacket:     [0x00, 0x67, 0x01, 0x00, 0x00, 0x00],
        ackReadRequest: [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00],
      );
      expect(r, isNull);
    });
  });

  group('ProUsbiNativeBackendFake', () {
    test('isAvailable is true', () {
      final b = ProUsbiNativeBackendFake();
      expect(b.isAvailable, true);
    });

    test('isFake is true', () {
      final b = ProUsbiNativeBackendFake();
      expect(b.isFake, true);
    });

    test('simulates ACK success response', () async {
      final b = ProUsbiNativeBackendFake(simulateAckSuccess: true);
      final r = await b.sendPacketsAndReadAck(
        setupPacket:    [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00],
        bodyPacket:     [0x00, 0x67, 0x00, 0x80, 0x00, 0x00],
        ackReadRequest: [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00],
      );
      expect(r, isNotNull);
      expect(r![6], 0x01);
    });

    test('simulates ACK failure when simulateAckSuccess=false', () async {
      final b = ProUsbiNativeBackendFake(simulateAckSuccess: false);
      final r = await b.sendPacketsAndReadAck(
        setupPacket:    [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00],
        bodyPacket:     [0x00, 0x67, 0x00, 0x80, 0x00, 0x00],
        ackReadRequest: [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00],
      );
      expect(r, isNotNull);
      expect(r![6], isNot(0x01));
    });

    test('captures setup packet', () async {
      final b = ProUsbiNativeBackendFake();
      await b.sendPacketsAndReadAck(
        setupPacket:    [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00],
        bodyPacket:     [0x00, 0x67, 0x00, 0x80, 0x00, 0x00],
        ackReadRequest: [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00],
      );
      expect(b.capturedSetupPackets.length, 1);
    });
  });

  group('wasActualWrite safety invariants', () {
    test('wasActualWrite is false by default in UsbiExecutionResult', () {
      final r = UsbiExecutionResult(
        id: 'r1', requestId: 'q1', status: UsbiExecutionStatus.blocked);
      expect(r.wasActualWrite, false);
    });

    test('ackReceived is false by default in UsbiExecutionResult', () {
      final r = UsbiExecutionResult(
        id: 'r1', requestId: 'q1', status: UsbiExecutionStatus.blocked);
      expect(r.ackReceived, false);
    });

    test('disabled executor never returns wasActualWrite=true', () async {
      final ex = ProUsbiTemporaryExecutor.disabled();
      final r = await ex.execute(_req());
      expect(r.wasActualWrite, false);
    });

    test('non-Windows never returns wasActualWrite=true', () async {
      final ex = _executor(isWindows: false, backendAvailable: true);
      final r = await ex.execute(_req());
      expect(r.wasActualWrite, false);
    });

    test('wrong transport never returns wasActualWrite=true', () async {
      final ex = _executor();
      final r = await ex
          .execute(_req(backend: HardwareTransportBackend.simulation));
      expect(r.wasActualWrite, false);
    });

    test('non-MV address never returns wasActualWrite=true', () async {
      final ex = _executor();
      final r = await ex.execute(
          _req(addressInt: 0x0010, addressHex: '0x0010'));
      expect(r.wasActualWrite, false);
    });

    test('unconfirmed request never returns wasActualWrite=true', () async {
      final ex = _executor();
      final r = await ex.execute(_req(userConfirmed: false));
      expect(r.wasActualWrite, false);
    });
  });

  group('JSON round-trips', () {
    test('UsbiExecutionStatus round-trip', () {
      for (final s in UsbiExecutionStatus.values) {
        expect(UsbiExecutionStatus.fromJson(s.toJson()), s);
      }
    });

    test('UsbiExecutionGuardCode round-trip', () {
      for (final c in UsbiExecutionGuardCode.values) {
        expect(UsbiExecutionGuardCode.fromJson(c.toJson()), c);
      }
    });

    test('UsbiExecutionResult toJson includes wasActualWrite=false', () {
      final r = UsbiExecutionResult(
        id: 'r1', requestId: 'q1', status: UsbiExecutionStatus.blocked);
      expect(r.toJson()['wasActualWrite'], false);
    });

    test('UsbiExecutionResult toJson includes safetyNote', () {
      final r = UsbiExecutionResult(
        id: 'r1', requestId: 'q1', status: UsbiExecutionStatus.blocked);
      expect(r.toJson()['safetyNote'], contains('ADAU1466'));
    });

    test('UsbiExecutionRequest round-trip', () {
      final req = _req();
      final json = req.toJson();
      final restored = UsbiExecutionRequest.fromJson(json);
      expect(restored.addressInt, req.addressInt);
      expect(restored.valueFloat, req.valueFloat);
      expect(restored.userConfirmed, req.userConfirmed);
    });
  });
}
