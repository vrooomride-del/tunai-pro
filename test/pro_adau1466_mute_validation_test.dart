import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_master_volume_executor.dart';
import 'package:tunai_pro/core/pro_adau1466_mute_validation_executor.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_candidate.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';

class _ScriptedRealBackend implements ProUsbiNativeBackend {
  final bool available;
  final List<Object> outcomes;
  final List<List<int>> setupPackets = [];
  final List<List<int>> bodyPackets = [];
  int callCount = 0;

  _ScriptedRealBackend({
    this.available = true,
    List<Object>? outcomes,
  }) : outcomes = outcomes ??
            <Object>[
              [0x01],
              [0x01]
            ];

  @override
  bool get isAvailable => available;

  @override
  bool get isFake => false;

  @override
  Future<List<int>?> sendPacketsAndReadAck({
    required List<int> setupPacket,
    required List<int> bodyPacket,
    required List<int> ackReadRequest,
  }) async {
    setupPackets.add(List<int>.from(setupPacket));
    bodyPackets.add(List<int>.from(bodyPacket));
    final outcome = outcomes[callCount++];
    if (outcome is Exception) throw outcome;
    return List<int>.from(outcome as List<int>);
  }
}

void main() {
  group('dedicated Mute1_3 validation executor', () {
    test('allowlist contains only 0x060E', () {
      expect(ProAdau1466MuteValidationExecutor.writeEnabledAddresses,
          equals({0x060E}));
    });

    test('writes raw integer 0 then restores raw integer 1', () async {
      final backend = _ScriptedRealBackend();
      final executor = ProAdau1466MuteValidationExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
      );

      final result = await executor.runSmokeTest(
        addressInt: 0x060E,
        deviceOpen: true,
      );

      expect(backend.callCount, 2);
      expect(backend.bodyPackets, [
        [0x06, 0x0E, 0x00, 0x00, 0x00, 0x00],
        [0x06, 0x0E, 0x00, 0x00, 0x00, 0x01],
      ]);
      expect(result.testAckOk, isTrue);
      expect(result.restoreAckOk, isTrue);
      expect(result.resultStatus, CandidateValidationStatus.passAck);
      expect(result.resultStatus, isNot(CandidateValidationStatus.verified));
    });

    test('rejects every address except 0x060E before backend I/O', () async {
      final backend = _ScriptedRealBackend();
      final executor = ProAdau1466MuteValidationExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
      );

      for (final address in [
        0x060F,
        0x0610,
        0x0611,
        0x0612,
        0x0613,
        0x0067,
        0x0064,
        0x6000,
        0x8000,
        0xFFFF,
      ]) {
        final result = await executor.runSmokeTest(
          addressInt: address,
          deviceOpen: true,
        );
        expect(result.resultStatus, CandidateValidationStatus.blocked,
            reason: '0x${address.toRadixString(16)}');
      }
      expect(backend.callCount, 0);
    });

    test('failed test ACK still attempts restore', () async {
      final backend = _ScriptedRealBackend(outcomes: [
        [0x00],
        [0x01],
      ]);
      final executor = ProAdau1466MuteValidationExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
      );

      final result = await executor.runSmokeTest(
        addressInt: 0x060E,
        deviceOpen: true,
      );

      expect(backend.callCount, 2);
      expect(backend.bodyPackets.last, [0x06, 0x0E, 0x00, 0x00, 0x00, 0x01]);
      expect(result.testAckOk, isFalse);
      expect(result.restoreAckOk, isTrue);
      expect(result.resultStatus, CandidateValidationStatus.fail);
    });

    test('test exception still attempts restore', () async {
      final backend = _ScriptedRealBackend(outcomes: [
        Exception('test transport failure'),
        [0x01],
      ]);
      final executor = ProAdau1466MuteValidationExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
      );

      final result = await executor.runSmokeTest(
        addressInt: 0x060E,
        deviceOpen: true,
      );

      expect(backend.callCount, 2);
      expect(result.restoreWasActualWrite, isTrue);
      expect(result.restoreAckOk, isTrue);
    });

    test('restore failure is reported prominently by result', () async {
      final backend = _ScriptedRealBackend(outcomes: [
        [0x01],
        [0x00],
      ]);
      final executor = ProAdau1466MuteValidationExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
      );

      final result = await executor.runSmokeTest(
        addressInt: 0x060E,
        deviceOpen: true,
      );

      expect(result.restoreFailed, isTrue);
      expect(result.error, contains('RESTORE FAILURE'));
      expect(result.resultStatus, CandidateValidationStatus.fail);
    });

    test('platform, device, backend, and real-executor guards block I/O',
        () async {
      final cases = <ProAdau1466MuteValidationExecutor>[
        ProAdau1466MuteValidationExecutor(
          backend: _ScriptedRealBackend(),
          isWindowsPlatform: () => false,
        ),
        ProAdau1466MuteValidationExecutor(
          backend: _ScriptedRealBackend(available: false),
          isWindowsPlatform: () => true,
        ),
        ProAdau1466MuteValidationExecutor(
          backend: ProUsbiNativeBackendFake(),
          isWindowsPlatform: () => true,
        ),
      ];

      for (final executor in cases) {
        final result = await executor.runSmokeTest(
          addressInt: 0x060E,
          deviceOpen: true,
        );
        expect(result.resultStatus, CandidateValidationStatus.blocked);
      }

      final deviceBackend = _ScriptedRealBackend();
      final deviceResult = await ProAdau1466MuteValidationExecutor(
        backend: deviceBackend,
        isWindowsPlatform: () => true,
      ).runSmokeTest(addressInt: 0x060E, deviceOpen: false);
      expect(deviceResult.resultStatus, CandidateValidationStatus.blocked);
      expect(deviceBackend.callCount, 0);
    });

    test('uses direct six-byte bodies and never a SafeLoad address', () async {
      final backend = _ScriptedRealBackend();
      await ProAdau1466MuteValidationExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
      ).runSmokeTest(addressInt: 0x060E, deviceOpen: true);

      expect(backend.setupPackets.every((p) => p.length == 8), isTrue);
      expect(backend.bodyPackets.every((p) => p.length == 6), isTrue);
      expect(backend.bodyPackets.every((p) => !(p[0] == 0x60 && p[1] <= 0x07)),
          isTrue);
    });
  });

  test('Master Volume allowlists and constants remain unchanged', () {
    expect(ProUsbiSigmaVerificationExecutor.writeEnabledAddresses,
        equals({0x0067, 0x0064}));
    expect(kOperationalMasterVolumeL, 0x0067);
    expect(kOperationalMasterVolumeR, 0x0064);
  });
}
