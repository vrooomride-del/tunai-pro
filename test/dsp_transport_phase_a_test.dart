import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/core/transport/dsp_command.dart';
import 'package:tunai_pro/core/transport/dsp_board_executor.dart';
import 'package:tunai_pro/core/transport/dsp_transport.dart';
import 'package:tunai_pro/core/transport/icp5_protocol_evidence.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/core/transport/usbi_dsp_transport.dart';
import 'package:tunai_pro/features/workbench/tabs/transport_connection_panel.dart';

void main() {
  group('ICP5 Phase A transport architecture', () {
    test('USBi adapter preserves proven setup/body/ACK framing', () async {
      final backend = ProUsbiNativeBackendFake(overrideAckPayload: [0x01]);
      final transport = UsbiDspTransport(backend: backend, deviceOpen: () => true);
      final command = DspCommand(
        boardId: 'ADAU1466',
        label: 'neutral direct write',
        kind: DspCommandKind.directParameterWrite,
        writes: [DspWriteBody(startAddress: 0x1234, dataBytes: [0, 0, 0, 1])],
      );

      final result = await transport.execute(command);

      expect(result.success, isTrue);
      expect(result.wasActualWrite, isTrue);
      expect(backend.capturedSetupPackets.single,
          [0x40, 0xB2, 0, 0, 1, 1, 6, 0]);
      expect(backend.capturedBodyPackets.single, [0x12, 0x34, 0, 0, 0, 1]);
    });

    test('USBi reports only capabilities proven by current paths', () {
      final transport = UsbiDspTransport(
          backend: ProUsbiNativeBackendFake(), deviceOpen: () => true);
      expect(transport.capabilities.directParameterWrite, isTrue);
      expect(transport.capabilities.oneWordSafeLoad, isTrue);
      expect(transport.capabilities.fiveWordSafeLoad, isTrue);
      expect(transport.capabilities.ackSupport, isTrue);
      expect(transport.capabilities.readbackSupport, isFalse);
      expect(transport.capabilities.maximumPayloadSize, 22);
    });

    for (final entry in <String, DspTransport>{
      'ICP5 USB': const Icp5UsbTransport(),
      'ICP5 Bluetooth': const Icp5BluetoothTransport(),
    }.entries) {
      test('${entry.key} rejects commands with zero hardware writes', () async {
        final command = DspCommand(
          boardId: 'ADAU1466',
          label: 'must remain blocked',
          kind: DspCommandKind.directParameterWrite,
          writes: [DspWriteBody(startAddress: 1, dataBytes: [0, 0, 0, 0])],
        );
        final result = await entry.value.execute(command);
        expect(result.success, isFalse);
        expect(result.wasActualWrite, isFalse);
        expect(result.failure, DspTransportFailure.protocolEvidenceMissing);
        expect(entry.value.capabilities, same(DspTransportCapabilities.unproven));
      });
    }

    test('all ICP5 evidence starts unknown rather than guessed', () {
      for (final evidence in [
        Icp5ProtocolEvidenceRegistry.usb,
        Icp5ProtocolEvidenceRegistry.bluetooth
      ]) {
        expect(evidence.usbVendorId, isNull);
        expect(evidence.usbProductId, isNull);
        expect(evidence.bluetoothServiceUuid, isNull);
        expect(evidence.framing, isNull);
        expect(evidence.maximumPayload, isNull);
        expect(evidence.ackFormat, isNull);
        expect(evidence.safeLoadSequence, isNull);
        expect(evidence.isProtocolProven, isFalse);
      }
    });

    test('router never falls back from selected ICP5 transport', () async {
      final usbiBackend = ProUsbiNativeBackendFake();
      final unusedUsbi = UsbiDspTransport(backend: usbiBackend, deviceOpen: () => true);
      expect(unusedUsbi.identity, DspTransportIdentity.usbi);
      const router = DspTransportRouter(Icp5UsbTransport());
      final result = await router.execute(DspCommand(
        boardId: 'ADAU1466',
        label: 'no fallback',
        kind: DspCommandKind.directParameterWrite,
        writes: [DspWriteBody(startAddress: 2, dataBytes: [0, 0, 0, 0])],
      ));
      expect(result.failure, DspTransportFailure.protocolEvidenceMissing);
      expect(usbiBackend.callCount, 0);
    });

    test('board executor policy is transport-independent', () async {
      final command = DspCommand(
        boardId: 'test-board',
        label: 'same neutral command',
        kind: DspCommandKind.directParameterWrite,
        writes: [DspWriteBody(startAddress: 0x1234, dataBytes: [0, 0, 0, 1])],
      );
      final registry = DspBoardCommandRegistry(
          boardId: 'test-board', writableAddresses: {0x1234});
      final backend = ProUsbiNativeBackendFake(overrideAckPayload: [1]);
      final usbiExecutor = DspBoardExecutor(
        registry: registry,
        router: DspTransportRouter(
            UsbiDspTransport(backend: backend, deviceOpen: () => true)),
      );
      final icp5Executor = DspBoardExecutor(
        registry: registry,
        router: const DspTransportRouter(Icp5BluetoothTransport()),
      );

      expect((await usbiExecutor.execute(command)).success, isTrue);
      expect((await icp5Executor.execute(command)).failure,
          DspTransportFailure.protocolEvidenceMissing);
      expect(backend.callCount, 1);
    });

    testWidgets('visible Workbench panel exposes all three transports',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TransportConnectionPanel(
              backend: ProUsbiNativeBackendDisabled(),
              deviceOpen: false,
            ),
          ),
        ),
      ));
      expect(find.byKey(const Key('workbench_transport_connection_panel')), findsOneWidget);
      expect(find.text('USBi'), findsOneWidget);
      expect(find.text('ICP5 USB'), findsOneWidget);
      expect(find.text('ICP5 Bluetooth'), findsOneWidget);
      await tester.tap(find.text('ICP5 USB'));
      await tester.pump();
      expect(find.text('PROTOCOL EVIDENCE REQUIRED — WRITES BLOCKED'), findsOneWidget);
      expect(find.text('NO AUTOMATIC FALLBACK DURING ACTIVE WRITES'), findsOneWidget);
    });
  });
}
