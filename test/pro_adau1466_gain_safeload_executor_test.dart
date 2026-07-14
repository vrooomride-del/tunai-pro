import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_channel_registry.dart';
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
    );
    return ack;
  }
}

Future<Adau1466GainSafeLoadResult> _run(
  _ScriptedRealBackend backend,
  Adau1466MappedGainChannel channel, {
  bool deviceOpen = true,
  bool windows = true,
}) =>
    ProAdau1466GainSafeLoadExecutor(
      backend: backend,
      isWindowsPlatform: () => windows,
    ).runDiagnostic(channel: channel, deviceOpen: deviceOpen);

void main() {
  const setup6 = [0x40, 0xB2, 0, 0, 1, 1, 0x06, 0];
  const setup14 = [0x40, 0xB2, 0, 0, 1, 1, 0x0E, 0];
  const ackRequest = [0xC0, 0xB5, 0, 0, 0, 0, 1, 0];

  group('capture-locked six-channel Gain SafeLoad executor', () {
    test('emits exact TEST and RESTORE packet order for every mapped channel',
        () async {
      for (final channel in ProAdau1466GainChannelRegistry.channels) {
        final backend = _ScriptedRealBackend();
        final result = await _run(backend, channel);
        final slewHigh = (channel.slewAddress >> 8) & 0xFF;
        final slewLow = channel.slewAddress & 0xFF;
        final targetHigh = (channel.targetAddress >> 8) & 0xFF;
        final targetLow = channel.targetAddress & 0xFF;
        final block = [
          0x60,
          0x05,
          0,
          0,
          targetHigh,
          targetLow,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
        ];
        List<int> dataBody(int value) => [
              0x60,
              0x00,
              (value >> 24) & 0xFF,
              (value >> 16) & 0xFF,
              (value >> 8) & 0xFF,
              value & 0xFF,
            ];

        expect(backend.setupPackets,
            [setup6, setup6, setup14, setup6, setup6, setup14],
            reason: channel.channel);
        expect(
            backend.bodyPackets,
            [
              [slewHigh, slewLow, 0, 0, 0x20, 0x8A],
              dataBody(channel.testWord),
              block,
              [slewHigh, slewLow, 0, 0, 0x20, 0x8A],
              dataBody(channel.exportedRestoreWord),
              block,
            ],
            reason: channel.channel);
        expect(
            backend.ackRequests
                .every((packet) => packet.toString() == ackRequest.toString()),
            isTrue);
        expect(result.resultStatus, CandidateValidationStatus.passAck);
        expect(result.resultStatus, isNot(CandidateValidationStatus.verified));
        expect(result.allRestoreStagesReturnedRawAck01, isTrue);
      }
    });

    test('write allowlist is exactly the six mapped targets', () {
      expect(ProAdau1466GainSafeLoadExecutor.writeEnabledTargets,
          equals({0x03B8, 0x03C4, 0x03C7, 0x03BB, 0x03CA, 0x03CD}));
    });

    test('rejects a lookalike channel object before backend I/O', () async {
      final backend = _ScriptedRealBackend();
      const arbitrary = Adau1466MappedGainChannel(
        channel: 'UNKNOWN',
        sigmaCellName: 'Unknown',
        sigmaParameterName: 'Unknown',
        targetAddress: 0x03B8,
        testWord: 0x00000840,
        exportedRestoreWord: 0x0000068E,
        sigmaOutputCell: 'Unknown',
        plannedPhysicalOutput: 'Unknown',
      );
      final result = await _run(backend, arbitrary);
      expect(result.resultStatus, CandidateValidationStatus.blocked);
      expect(backend.callCount, 0);
    });

    test('all restore stages run after TEST failures and exceptions', () async {
      final backend = _ScriptedRealBackend(outcomes: [
        [0x00],
        Exception('test stage 2 failed'),
        [0x00],
        [0x01],
        [0x01],
        [0x01],
      ]);
      final channel = ProAdau1466GainChannelRegistry.findByChannel('MID_L')!;
      final result = await _run(backend, channel);
      expect(backend.callCount, 6);
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
      final channel = ProAdau1466GainChannelRegistry.findByChannel('TWR')!;
      final result = await _run(backend, channel);
      expect(backend.callCount, 6);
      expect(result.restoreFailed, isTrue);
      expect(result.resultStatus, CandidateValidationStatus.fail);
    });

    test('platform, device, backend, and real-executor guards block I/O',
        () async {
      final channel = ProAdau1466GainChannelRegistry.channels.first;
      final notWindows = _ScriptedRealBackend();
      expect((await _run(notWindows, channel, windows: false)).resultStatus,
          CandidateValidationStatus.blocked);
      final disconnected = _ScriptedRealBackend();
      expect(
          (await _run(disconnected, channel, deviceOpen: false)).resultStatus,
          CandidateValidationStatus.blocked);
      final unavailable = _ScriptedRealBackend(available: false);
      expect((await _run(unavailable, channel)).resultStatus,
          CandidateValidationStatus.blocked);
      expect(
          notWindows.callCount + disconnected.callCount + unavailable.callCount,
          0);

      final fake = ProUsbiNativeBackendFake();
      final fakeResult = await ProAdau1466GainSafeLoadExecutor(
        backend: fake,
        isWindowsPlatform: () => true,
      ).runDiagnostic(channel: channel, deviceOpen: true);
      expect(fakeResult.resultStatus, CandidateValidationStatus.blocked);
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

  test('executor exposes no arbitrary value/address or legacy SafeLoad path',
      () {
    final source = File('lib/core/pro_adau1466_gain_safeload_executor.dart')
        .readAsStringSync();
    expect(source, isNot(contains('required int requestedTargetAddress')));
    expect(source, isNot(contains('required int requestedTestValue')));
    expect(source, isNot(contains('required int requestedRestoreValue')));
    expect(source, isNot(contains('buildSafeLoadWriteSequence')));
    expect(source, isNot(contains('Adau1466Adapter')));
    expect(source, isNot(contains('Adau1466UsbSpiTransport')));
    expect(source, isNot(contains('ADAU1701')));
    expect(source, contains('sendPacketsAndReadAck'));
  });
}
