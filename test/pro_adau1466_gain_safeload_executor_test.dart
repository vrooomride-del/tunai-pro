import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_safeload_executor.dart';
import 'package:tunai_pro/core/pro_adau1466_master_volume_executor.dart';
import 'package:tunai_pro/core/pro_adau1466_mute_validation_executor.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_candidate.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';

class _ScriptedRealBackend
    implements ProUsbiNativeBackend, ProUsbiTransactionDiagnosticsProvider {
  final bool available;
  final List<Object> outcomes;
  final List<List<int>> setupPackets = [];
  final List<List<int>> bodyPackets = [];
  final List<List<int>> ackRequests = [];
  int callCount = 0;
  UsbiNativeTransactionDiagnostics? _diagnostics;

  _ScriptedRealBackend({this.available = true, List<Object>? outcomes})
      : outcomes = outcomes ?? List<Object>.generate(6, (_) => <int>[0x01]);

  @override
  bool get isAvailable => available;
  @override
  bool get isFake => false;
  @override
  UsbiNativeTransactionDiagnostics? get lastTransactionDiagnostics =>
      _diagnostics;

  @override
  Future<List<int>?> sendPacketsAndReadAck({
    required List<int> setupPacket,
    required List<int> bodyPacket,
    required List<int> ackReadRequest,
  }) async {
    setupPackets.add(List<int>.from(setupPacket));
    bodyPackets.add(List<int>.from(bodyPacket));
    ackRequests.add(List<int>.from(ackReadRequest));
    final outcome = outcomes[callCount++];
    if (outcome is Exception) throw outcome;
    final ack = List<int>.from(outcome as List<int>);
    _diagnostics = UsbiNativeTransactionDiagnostics(
      setupPacket: List<int>.from(setupPacket),
      bodyPacket: List<int>.from(bodyPacket),
      ackRequestPacket: List<int>.from(ackReadRequest),
      setupTransferSuccess: true,
      bodyTransferSuccess: true,
      bytesTransferred: bodyPacket.length,
      ackReadSuccess: true,
      ackBytesTransferred: ack.length,
      rawAckBytes: ack,
      setupElapsedMilliseconds: callCount,
      ackElapsedMilliseconds: callCount + 1,
    );
    return ack;
  }
}

Future<Adau1466GainSafeLoadResult> _run(_ScriptedRealBackend backend,
    {int target = 0x03B8,
    int testValue = 0x00000840,
    int restoreValue = 0x0000068E,
    bool deviceOpen = true}) {
  return ProAdau1466GainSafeLoadExecutor(
    backend: backend,
    isWindowsPlatform: () => true,
  ).runDiagnostic(
    requestedTargetAddress: target,
    requestedTestValue: testValue,
    requestedRestoreValue: restoreValue,
    deviceOpen: deviceOpen,
  );
}

void main() {
  const setup6 = [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00];
  const setup14 = [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x0E, 0x00];
  const slew = [0x03, 0xB9, 0x00, 0x00, 0x20, 0x8A];
  const block = [
    0x60,
    0x05,
    0x00,
    0x00,
    0x03,
    0xB8,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
  ];

  group('capture-locked Gain Single 1 SafeLoad executor', () {
    test('emits exact TEST and RESTORE packet order and setup lengths',
        () async {
      final backend = _ScriptedRealBackend();
      final result = await _run(backend);

      expect(backend.setupPackets,
          [setup6, setup6, setup14, setup6, setup6, setup14]);
      expect(backend.bodyPackets, [
        slew,
        [0x60, 0x00, 0x00, 0x00, 0x08, 0x40],
        block,
        slew,
        [0x60, 0x00, 0x00, 0x00, 0x06, 0x8E],
        block,
      ]);
      expect(
          backend.ackRequests.every(
              (p) => p.toString() == [0xC0, 0xB5, 0, 0, 0, 0, 1, 0].toString()),
          isTrue);
      expect(result.resultStatus, CandidateValidationStatus.passAck);
      expect(result.resultStatus, isNot(CandidateValidationStatus.verified));
      expect(result.wasActualWrite, isTrue);
      expect(result.allRestoreStagesReturnedRawAck01, isTrue);
    });

    test('accepts only target 0x03B8 and exact test/restore values', () async {
      for (final target in [0x03B7, 0x03B9, 0x03C4, 0x0067, 0x060E, 0x6000]) {
        final backend = _ScriptedRealBackend();
        expect((await _run(backend, target: target)).resultStatus,
            CandidateValidationStatus.blocked);
        expect(backend.callCount, 0);
      }
      for (final values in [
        (0x00000841, 0x0000068E),
        (0x00000840, 0x0000068F),
        (0, 0)
      ]) {
        final backend = _ScriptedRealBackend();
        expect(
            (await _run(backend, testValue: values.$1, restoreValue: values.$2))
                .resultStatus,
            CandidateValidationStatus.blocked);
        expect(backend.callCount, 0);
      }
      expect(ProAdau1466GainSafeLoadExecutor.writeEnabledTargets,
          equals({0x03B8}));
    });

    test('all restore stages run after test failure and exceptions', () async {
      final backend = _ScriptedRealBackend(outcomes: [
        [0x00],
        Exception('test stage 2 failed'),
        [0x00],
        [0x01],
        [0x01],
        [0x01],
      ]);
      final result = await _run(backend);

      expect(backend.callCount, 6);
      expect(result.testStages.every((stage) => !stage.ackOk), isTrue);
      expect(result.allRestoreStagesReturnedRawAck01, isTrue);
      expect(result.resultStatus, CandidateValidationStatus.fail);
    });

    test('any restore failure requests the session interlock', () async {
      final backend = _ScriptedRealBackend(outcomes: [
        [0x01],
        [0x01],
        [0x01],
        [0x01],
        [0x00],
        [0x01],
      ]);
      final result = await _run(backend);

      expect(backend.callCount, 6);
      expect(result.restoreFailed, isTrue);
      expect(result.allRestoreStagesReturnedRawAck01, isFalse);
      expect(result.resultStatus, CandidateValidationStatus.fail);
    });

    test('platform, device, backend, and real executor guards block I/O',
        () async {
      final notWindows = _ScriptedRealBackend();
      final result = await ProAdau1466GainSafeLoadExecutor(
        backend: notWindows,
        isWindowsPlatform: () => false,
      ).runDiagnostic(
        requestedTargetAddress: 0x03B8,
        requestedTestValue: 0x00000840,
        requestedRestoreValue: 0x0000068E,
        deviceOpen: true,
      );
      expect(result.resultStatus, CandidateValidationStatus.blocked);
      expect(notWindows.callCount, 0);

      final disconnected = _ScriptedRealBackend();
      expect((await _run(disconnected, deviceOpen: false)).resultStatus,
          CandidateValidationStatus.blocked);
      expect(disconnected.callCount, 0);

      final unavailable = _ScriptedRealBackend(available: false);
      expect((await _run(unavailable)).resultStatus,
          CandidateValidationStatus.blocked);
      expect(unavailable.callCount, 0);

      final fake = ProUsbiNativeBackendFake();
      expect(
          (await ProAdau1466GainSafeLoadExecutor(
                      backend: fake, isWindowsPlatform: () => true)
                  .runDiagnostic(
                      requestedTargetAddress: 0x03B8,
                      requestedTestValue: 0x00000840,
                      requestedRestoreValue: 0x0000068E,
                      deviceOpen: true))
              .resultStatus,
          CandidateValidationStatus.blocked);
      expect(fake.callCount, 0);
    });
  });

  test('Master Volume and Mute allowlists remain unchanged', () {
    expect(ProUsbiSigmaVerificationExecutor.writeEnabledAddresses,
        equals({0x0067, 0x0064}));
    expect(kOperationalMasterVolumeL, 0x0067);
    expect(kOperationalMasterVolumeR, 0x0064);
    expect(ProAdau1466MuteValidationExecutor.writeEnabledAddresses,
        equals({0x060E}));
  });

  test('dedicated executor has no legacy or ADAU1701 SafeLoad dependency', () {
    final source = File('lib/core/pro_adau1466_gain_safeload_executor.dart')
        .readAsStringSync();
    expect(source, isNot(contains('buildSafeLoadWriteSequence')));
    expect(source, isNot(contains('Adau1466Adapter')));
    expect(source, isNot(contains('Adau1466UsbSpiTransport')));
    expect(source, isNot(contains('ADAU1701')));
    expect(source, isNot(contains('buildGainFrame1466')));
    expect(source, contains('sendPacketsAndReadAck'));
  });
}
