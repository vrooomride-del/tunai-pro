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
      final transport =
          UsbiDspTransport(backend: backend, deviceOpen: () => true);
      final command = DspCommand(
        boardId: 'ADAU1466',
        label: 'neutral direct write',
        kind: DspCommandKind.directParameterWrite,
        writes: [
          DspWriteBody(startAddress: 0x1234, dataBytes: [0, 0, 0, 1])
        ],
      );

      final result = await transport.execute(command);

      expect(result.success, isTrue);
      expect(result.wasActualWrite, isTrue);
      expect(
          backend.capturedSetupPackets.single, [0x40, 0xB2, 0, 0, 1, 1, 6, 0]);
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
      'ICP5 Bluetooth': Icp5BluetoothTransport(),
    }.entries) {
      test('${entry.key} rejects commands with zero hardware writes', () async {
        final command = DspCommand(
          boardId: 'ADAU1466',
          label: 'must remain blocked',
          kind: DspCommandKind.directParameterWrite,
          writes: [
            DspWriteBody(startAddress: 1, dataBytes: [0, 0, 0, 0])
          ],
        );
        final result = await entry.value.execute(command);
        expect(result.success, isFalse);
        expect(result.wasActualWrite, isFalse);
        expect(result.failure, DspTransportFailure.unsupportedCapability);
        expect(entry.value.capabilities.directParameterWrite, isTrue);
        expect(entry.value.capabilities.ackSupport, isTrue);
      });
    }

    test('Phase B USB evidence is proven while Bluetooth stays unknown', () {
      expect(Icp5ProtocolEvidenceRegistry.usb.usbVendorId, 0x1A86);
      expect(Icp5ProtocolEvidenceRegistry.usb.usbProductId, 0x55D6);
      expect(Icp5ProtocolEvidenceRegistry.usb.isProtocolProven, isTrue);
      final bluetooth = Icp5ProtocolEvidenceRegistry.bluetooth;
      expect(bluetooth.bluetoothServiceUuid, isNull);
      expect(bluetooth.framing, isNull);
      expect(bluetooth.ackFormat, isNull);
      expect(bluetooth.safeLoadSequence, isNull);
      expect(bluetooth.isProtocolProven, isFalse);
    });

    test('router never falls back from selected ICP5 transport', () async {
      final usbiBackend = ProUsbiNativeBackendFake();
      final unusedUsbi =
          UsbiDspTransport(backend: usbiBackend, deviceOpen: () => true);
      expect(unusedUsbi.identity, DspTransportIdentity.usbi);
      final router = DspTransportRouter(Icp5BluetoothTransport());
      final result = await router.execute(DspCommand(
        boardId: 'ADAU1466',
        label: 'no fallback',
        kind: DspCommandKind.directParameterWrite,
        writes: [
          DspWriteBody(startAddress: 2, dataBytes: [0, 0, 0, 0])
        ],
      ));
      expect(result.failure, DspTransportFailure.unsupportedCapability);
      expect(usbiBackend.callCount, 0);
    });

    test('board executor policy is transport-independent', () async {
      final command = DspCommand(
        boardId: 'test-board',
        label: 'same neutral command',
        kind: DspCommandKind.directParameterWrite,
        writes: [
          DspWriteBody(startAddress: 0x1234, dataBytes: [0, 0, 0, 1])
        ],
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
        router: DspTransportRouter(Icp5BluetoothTransport()),
      );

      expect((await usbiExecutor.execute(command)).success, isTrue);
      expect((await icp5Executor.execute(command)).failure,
          DspTransportFailure.unsupportedCapability);
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
      expect(find.byKey(const Key('workbench_transport_connection_panel')),
          findsOneWidget);
      expect(find.text('USBi'), findsOneWidget);
      expect(find.text('ICP5 USB'), findsOneWidget);
      expect(find.text('ICP5 Bluetooth'), findsOneWidget);
      await tester.tap(find.text('ICP5 USB'));
      await tester.pump();
      expect(
          find.byKey(const Key('icp5_usb_operational_panel')), findsOneWidget);
      expect(find.text('TEST internal value 5.9'), findsOneWidget);
      expect(find.text('RESTORE internal value 6.0'), findsOneWidget);
      await tester.tap(find.text('ICP5 Bluetooth'));
      await tester.pump();
      expect(find.textContaining('physical command QA remains pending'),
          findsOneWidget);
      expect(find.text('NO AUTOMATIC FALLBACK DURING ACTIVE WRITES'),
          findsOneWidget);
    });
  });
}
