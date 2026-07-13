import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_master_volume_executor.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_candidate.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/operational_master_volume_control.dart';

class _RealScriptedBackend implements ProUsbiNativeBackend {
  final List<List<int>?> scriptedAcks;
  final bool available;
  final List<List<int>> setupPackets = [];
  final List<List<int>> bodyPackets = [];
  int callCount = 0;

  _RealScriptedBackend({
    this.scriptedAcks = const [],
    this.available = true,
  });

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
    final index = callCount++;
    return index < scriptedAcks.length ? scriptedAcks[index] : const [0x01];
  }
}

ProAdau1466MasterVolumeExecutor _executor(_RealScriptedBackend backend) =>
    ProAdau1466MasterVolumeExecutor(
      sigmaExecutor: ProUsbiSigmaVerificationExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
      ),
    );

void main() {
  group('operational ADAU1466 linked Master Volume executor', () {
    test('8.24 conversion is exact and never uses the old 5.27 scale', () {
      expect(encodeAdau1466Linear824(1.0), 0x01000000);
      expect(encodeAdau1466Linear824(0.5), 0x00800000);
      expect(encodeAdau1466Linear824(0.0), 0x00000000);
      expect(encodeAdau1466Linear824(1.0), isNot(1 << 27));
    });

    test('both ACK success commits linked stereo at only 0x0067 and 0x0064',
        () async {
      final backend = _RealScriptedBackend();
      final result = await _executor(backend).writeLinkedStereo(
        previousLinear: 1.0,
        requestedLinear: 0.5,
        deviceOpen: true,
      );

      expect(result.confirmed, isTrue);
      expect(result.status, CandidateValidationStatus.passAck);
      expect(result.lAckOk, isTrue);
      expect(result.rAckOk, isTrue);
      expect(backend.callCount, 2);
      expect(backend.bodyPackets, [
        [0x00, 0x67, 0x00, 0x80, 0x00, 0x00],
        [0x00, 0x64, 0x00, 0x80, 0x00, 0x00],
      ]);
    });

    test('disconnected USBi blocks before any backend call', () async {
      final backend = _RealScriptedBackend();
      final result = await _executor(backend).writeLinkedStereo(
        previousLinear: 1.0,
        requestedLinear: 0.5,
        deviceOpen: false,
      );
      expect(result.status, CandidateValidationStatus.blocked);
      expect(result.confirmed, isFalse);
      expect(backend.callCount, 0);
    });

    test('unavailable real backend blocks before any backend call', () async {
      final backend = _RealScriptedBackend(available: false);
      final result = await _executor(backend).writeLinkedStereo(
        previousLinear: 1.0,
        requestedLinear: 0.5,
        deviceOpen: true,
      );
      expect(result.status, CandidateValidationStatus.blocked);
      expect(result.confirmed, isFalse);
      expect(backend.callCount, 0);
    });

    test('non-Windows platform blocks before any backend call', () async {
      final backend = _RealScriptedBackend();
      final executor = ProAdau1466MasterVolumeExecutor(
        sigmaExecutor: ProUsbiSigmaVerificationExecutor(
          backend: backend,
          isWindowsPlatform: () => false,
        ),
      );
      final result = await executor.writeLinkedStereo(
        previousLinear: 1.0,
        requestedLinear: 0.5,
        deviceOpen: true,
      );
      expect(result.status, CandidateValidationStatus.blocked);
      expect(backend.callCount, 0);
    });

    test('test/fake executor cannot perform operational writes', () async {
      final fake = ProUsbiNativeBackendFake();
      final executor = ProAdau1466MasterVolumeExecutor(
        sigmaExecutor: ProUsbiSigmaVerificationExecutor(
          backend: fake,
          isWindowsPlatform: () => true,
        ),
      );
      final result = await executor.writeLinkedStereo(
        previousLinear: 1.0,
        requestedLinear: 0.5,
        deviceOpen: true,
      );
      expect(result.status, CandidateValidationStatus.blocked);
      expect(fake.callCount, 0);
    });

    test('first write failure keeps the previous value and does not write R',
        () async {
      final backend = _RealScriptedBackend(scriptedAcks: const [[0x00]]);
      final result = await _executor(backend).writeLinkedStereo(
        previousLinear: 1.0,
        requestedLinear: 0.5,
        deviceOpen: true,
      );
      expect(result.confirmed, isFalse);
      expect(result.lAckOk, isFalse);
      expect(result.rollbackAttempted, isFalse);
      expect(backend.callCount, 1);
      expect(backend.bodyPackets.single.take(2), [0x00, 0x67]);
    });

    test('L success and R failure rolls L back to the previous value',
        () async {
      final backend = _RealScriptedBackend(
          scriptedAcks: const [[0x01], [0x00], [0x01]]);
      final result = await _executor(backend).writeLinkedStereo(
        previousLinear: 1.0,
        requestedLinear: 0.5,
        deviceOpen: true,
      );
      expect(result.confirmed, isFalse);
      expect(result.lAckOk, isTrue);
      expect(result.rAckOk, isFalse);
      expect(result.rollbackAttempted, isTrue);
      expect(result.rollbackAckOk, isTrue);
      expect(backend.bodyPackets, [
        [0x00, 0x67, 0x00, 0x80, 0x00, 0x00],
        [0x00, 0x64, 0x00, 0x80, 0x00, 0x00],
        [0x00, 0x67, 0x01, 0x00, 0x00, 0x00],
      ]);
    });

    test('unknown and SafeLoad addresses cannot reach the backend', () async {
      final backend = _RealScriptedBackend();
      final sigma = ProUsbiSigmaVerificationExecutor(
        backend: backend,
        isWindowsPlatform: () => true,
      );
      for (final address in [0x0100, 0x6000, 0x8000]) {
        final result = await sigma.writeSingleValue(
          addressInt: address,
          fixedPointValue: 0x00800000,
        );
        expect(result.resultStatus, CandidateValidationStatus.blocked);
      }
      expect(backend.callCount, 0);
    });

    test('direct writes use six-byte parameter bodies, never SafeLoad',
        () async {
      final backend = _RealScriptedBackend();
      await _executor(backend).writeLinkedStereo(
        previousLinear: 1.0,
        requestedLinear: 0.5,
        deviceOpen: true,
      );
      expect(backend.setupPackets.every((p) => p[6] == 0x06), isTrue);
      expect(backend.bodyPackets.every((p) => p.length == 6), isTrue);
      expect(backend.bodyPackets.any((p) => p[0] == 0x60), isFalse);
    });
  });

  group('operational Master Volume widget', () {
    testWidgets('drag preview does not write until onChangeEnd', (tester) async {
      final backend = _RealScriptedBackend();
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: OperationalMasterVolumeControl(
          backend: backend,
          isWindowsPlatform: () => true,
          deviceOpen: true,
        ),
      )));

      var slider = tester.widget<Slider>(
          find.byKey(const Key('operational-master-volume-slider')));
      slider.onChanged!(0.5);
      await tester.pump();
      expect(backend.callCount, 0);
      expect(find.textContaining('0.5000 linear'), findsOneWidget);

      slider = tester.widget<Slider>(
          find.byKey(const Key('operational-master-volume-slider')));
      slider.onChangeEnd!(0.5);
      await tester.pumpAndSettle();
      expect(backend.callCount, 2);
      expect(find.text('Confirmed: 0.5000'), findsOneWidget);
      expect(find.text('L ACK status: PASS_ACK'), findsOneWidget);
      expect(find.text('R ACK status: PASS_ACK'), findsOneWidget);
    });

    testWidgets('failed first write restores the UI to confirmed value',
        (tester) async {
      final backend = _RealScriptedBackend(scriptedAcks: const [[0x00]]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: OperationalMasterVolumeControl(
          backend: backend,
          isWindowsPlatform: () => true,
          deviceOpen: true,
        ),
      )));
      final slider = tester.widget<Slider>(
          find.byKey(const Key('operational-master-volume-slider')));
      slider.onChanged!(0.5);
      slider.onChangeEnd!(0.5);
      await tester.pumpAndSettle();
      expect(find.textContaining('1.0000 linear'), findsOneWidget);
      expect(find.text('Confirmed: 1.0000'), findsOneWidget);
      expect(find.text('Last write status: FAIL'), findsOneWidget);
    });

    testWidgets('closed USBi disables operational writes', (tester) async {
      final backend = _RealScriptedBackend();
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: OperationalMasterVolumeControl(
          backend: backend,
          isWindowsPlatform: () => true,
          deviceOpen: false,
        ),
      )));
      final slider = tester.widget<Slider>(
          find.byKey(const Key('operational-master-volume-slider')));
      expect(slider.onChanged, isNull);
      expect(slider.onChangeEnd, isNull);
      expect(find.text('USBi device-open status: closed'), findsOneWidget);
      expect(backend.callCount, 0);
    });
  });
}
