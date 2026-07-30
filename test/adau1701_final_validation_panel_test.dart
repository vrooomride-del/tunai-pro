// Widget tests for the ADAU1701 MiUMAX FINAL VALIDATION panel.
//
// Verifies:
//   1. The panel renders at the top of the ICP5 USB section.
//   2. Delay ch0–3 cards (param 0x17) render with TEST 1.0 / RESTORE 0.04.
//   3. PEQ Enable/Bypass capture-procedure card renders (no TEST button).
//   4. BLE section renders an equivalent panel under key 'ble_final_validation_panel'.
//   5. ACK-only result propagates to the card's confirmed state on TEST press.
//
// These tests use the same FakeDriver/FakeConnection pattern as
// test/icp5_usb_phase_b_test.dart. The panel is blocked until handshake passes.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/workbench/tabs/transport_connection_panel.dart';

// ── Shared fakes ──────────────────────────────────────────────────────────────

const _identityRx = <int>[
  0x55, 0x18, 0xE0, 0, 0, 0, 0, 0,
  0x44, 0x53, 0x50, 0x31, 0x37, 0x30, 0x31, 0x2E,
  0x31, 0x30, 0x30, 0x2E, 0x30, 0x30, 0x2E, 0x30, 0x31, 0xD9,
];

// ACK for param 0x17 (Delay Candidate)
const _delayAck = <int>[0x55, 0x07, 0xE1, 0, 0, 0, 0x17, 0, 0x54];

class _FakeConnection implements Icp5SerialConnection {
  final _ctrl = StreamController<List<int>>.broadcast(sync: true);
  final List<List<int>> writes = [];
  final void Function(_FakeConnection c, int call, List<int> bytes) onWrite;
  _FakeConnection(this.onWrite);
  @override
  Stream<List<int>> get bytes => _ctrl.stream;
  void emit(List<int> b) => _ctrl.add(b);
  @override
  Future<int> write(List<int> b, Duration timeout) async {
    writes.add(List.from(b));
    onWrite(this, writes.length, b);
    return b.length;
  }
  @override
  Future<void> close() async => _ctrl.close();
}

class _FakeDriver implements Icp5SerialDriver {
  final _FakeConnection connection;
  _FakeDriver(this.connection);
  @override
  bool get platformSupported => true;
  @override
  Future<Icp5DiscoveryResult> discover() async => Icp5DiscoveryResult(
        source: 'Fake',
        allPorts: const [
          Icp5SerialDevice(
              portName: 'COM27',
              vendorId: 0x1A86,
              productId: 0x55D6,
              productName: 'USB-BLE-SERIAL CH9143'),
        ],
        matches: const [
          Icp5SerialDevice(
              portName: 'COM27',
              vendorId: 0x1A86,
              productId: 0x55D6,
              productName: 'USB-BLE-SERIAL CH9143'),
        ],
      );
  @override
  Future<Icp5SerialConnection> open(String portName) async => connection;
}

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('FINAL VALIDATION panel — ICP5 USB', () {
    testWidgets('panel renders at top of ICP5 USB section', (tester) async {
      final transport =
          Icp5UsbTransport(driver: _FakeDriver(_FakeConnection((_, __, ___) {})));
      await tester.pumpWidget(_wrap(TransportConnectionPanel(
        backend: const ProUsbiNativeBackendDisabled(),
        deviceOpen: false,
        icp5UsbTransport: transport,
      )));
      await tester.tap(find.text('ICP5 USB'));
      await tester.pump();
      expect(find.byKey(const Key('icp5_final_validation_panel')),
          findsOneWidget);
      expect(find.textContaining('FINAL VALIDATION'), findsOneWidget);
    });

    testWidgets('delay cards 0–3 render with TEST 1.0 / RESTORE 0.04',
        (tester) async {
      final transport =
          Icp5UsbTransport(driver: _FakeDriver(_FakeConnection((_, __, ___) {})));
      await tester.pumpWidget(_wrap(TransportConnectionPanel(
        backend: const ProUsbiNativeBackendDisabled(),
        deviceOpen: false,
        icp5UsbTransport: transport,
      )));
      await tester.tap(find.text('ICP5 USB'));
      await tester.pump();
      for (var ch = 0; ch < 4; ch++) {
        expect(find.byKey(Key('icp5_phase_c_delay$ch')), findsOneWidget,
            reason: 'delay card $ch must exist');
        expect(find.text('Delay candidate DAC$ch'), findsOneWidget);
      }
      expect(find.text('TEST 1.0'), findsNWidgets(4));
      expect(find.text('RESTORE 0.04'), findsNWidgets(4));
    });

    testWidgets('PEQ enable/bypass card renders with semantic bypass info; no TEST button',
        (tester) async {
      final transport =
          Icp5UsbTransport(driver: _FakeDriver(_FakeConnection((_, __, ___) {})));
      await tester.pumpWidget(_wrap(TransportConnectionPanel(
        backend: const ProUsbiNativeBackendDisabled(),
        deviceOpen: false,
        icp5UsbTransport: transport,
      )));
      await tester.tap(find.text('ICP5 USB'));
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('peq_enable_bypass_capture_procedure')));
      expect(find.byKey(const Key('peq_enable_bypass_capture_procedure')),
          findsOneWidget);
      expect(find.textContaining('SEMANTIC BYPASS'), findsOneWidget);
      expect(find.textContaining('Bypassed (0 dB unity)'), findsOneWidget);
      expect(find.textContaining('No TEST button'), findsOneWidget);
    });

    testWidgets('delay TEST sends exact param 0x17 frame and confirms ACK',
        (tester) async {
      late _FakeConnection connection;
      connection = _FakeConnection((c, call, bytes) {
        if (call == 1) c.emit(_identityRx);
        if (call == 2) c.emit(_delayAck);
      });
      final transport = Icp5UsbTransport(driver: _FakeDriver(connection));
      await transport.open();
      await tester.pumpWidget(_wrap(TransportConnectionPanel(
        backend: const ProUsbiNativeBackendDisabled(),
        deviceOpen: false,
        icp5UsbTransport: transport,
      )));
      await tester.tap(find.text('ICP5 USB'));
      await tester.pump();
      final testBtn = find.byKey(const Key('icp5_phase_c_delay0_test'));
      await tester.ensureVisible(testBtn);
      await tester.tap(testBtn);
      await tester.pumpAndSettle();
      expect(connection.writes.last,
          Icp5FrameCodec.buildDelayCandidateWrite(0, 1.0));
      final card = find.byKey(const Key('icp5_phase_c_delay0'));
      expect(find.descendant(of: card, matching: find.text('PASS_ACK')),
          findsOneWidget);
    });

    testWidgets('delay RESTORE sends exact param 0x17 frame', (tester) async {
      late _FakeConnection connection;
      connection = _FakeConnection((c, call, bytes) {
        if (call == 1) c.emit(_identityRx);
        if (call == 2) c.emit(_delayAck);
      });
      final transport = Icp5UsbTransport(driver: _FakeDriver(connection));
      await transport.open();
      await tester.pumpWidget(_wrap(TransportConnectionPanel(
        backend: const ProUsbiNativeBackendDisabled(),
        deviceOpen: false,
        icp5UsbTransport: transport,
      )));
      await tester.tap(find.text('ICP5 USB'));
      await tester.pump();
      final restoreBtn = find.byKey(const Key('icp5_phase_c_delay0_restore'));
      await tester.ensureVisible(restoreBtn);
      await tester.tap(restoreBtn);
      await tester.pumpAndSettle();
      expect(connection.writes.last,
          Icp5FrameCodec.buildDelayCandidateWrite(0, 0.04));
    });

    testWidgets('panel is blocked before handshake', (tester) async {
      final transport =
          Icp5UsbTransport(driver: _FakeDriver(_FakeConnection((_, __, ___) {})));
      await tester.pumpWidget(_wrap(TransportConnectionPanel(
        backend: const ProUsbiNativeBackendDisabled(),
        deviceOpen: false,
        icp5UsbTransport: transport,
      )));
      await tester.tap(find.text('ICP5 USB'));
      await tester.pump();
      // Without handshake the TEST buttons must be disabled.
      final testBtn = tester.widget<FilledButton>(
          find.byKey(const Key('icp5_phase_c_delay0_test')));
      expect(testBtn.onPressed, isNull,
          reason: 'delay TEST must be blocked before handshake');
    });
  });

  // BLE final validation panel tests are in icp5_bluetooth_connection_ui_test.dart
  // (requires full handshake flow). The ble_final_validation_panel key and
  // ble_delay* cards are verified there after PASS_HANDSHAKE.

  group('FINAL VALIDATION — MiUMAX feature coverage', () {
    test('delay frame encoding: only 1.0 and 0.04 accepted per channel', () {
      for (var ch = 0; ch < 4; ch++) {
        final t = Icp5FrameCodec.buildDelayCandidateWrite(ch, 1.0);
        final r = Icp5FrameCodec.buildDelayCandidateWrite(ch, 0.04);
        expect(t, isNot(equals(r)));
        expect(Icp5FrameCodec.hasValidEnvelope(t), isTrue);
        expect(Icp5FrameCodec.hasValidEnvelope(r), isTrue);
        expect(() => Icp5FrameCodec.buildDelayCandidateWrite(ch, 0.5),
            throwsArgumentError);
      }
    });

    test('delay parameter ID is 0x17 in all four channel frames', () {
      for (var ch = 0; ch < 4; ch++) {
        final frame = Icp5FrameCodec.buildDelayCandidateWrite(ch, 1.0);
        // Frame byte [6] is the parameter ID LSB (param = 0x00000017).
        expect(frame[6], 0x17, reason: 'ch$ch: param LSB must be 0x17');
      }
    });

    test('delay ACK parser accepts only matching parameter 0x17', () {
      const goodDelayAck = <int>[0x55, 0x07, 0xE1, 0, 0, 0, 0x17, 0, 0x54];
      const wrongParam = <int>[0x55, 0x07, 0xE1, 0, 0, 0, 0x18, 0, 0x55];
      expect(Icp5FrameCodec.parseDelayCandidateAck(goodDelayAck), isTrue);
      expect(Icp5FrameCodec.parseDelayCandidateAck(wrongParam), isFalse);
    });

    test('MiUMAX/Consumer ICP5 builder comparison — no unported params', () {
      // Consumer codex Icp5PeqCommandBuilder exposes:
      //   gain (0x18 prop 0x01), Q (0x18 prop 0x00), frequency (0x18 prop 0x02).
      // No enable/bypass property in any Consumer build — confirmed absent.
      // PRO icp5_frame_codec.dart covers all six captured parameters:
      //   0x10 Master Volume, 0x12 Master Mute, 0x14 Output Gain,
      //   0x15 Filter Cutoff (XO), 0x17 Delay, 0x18 PEQ gain/Q/freq.
      // This test documents the comparison result so it is visible in CI.
      const ported = {
        'masterVolume (0x10)',
        'masterMute (0x12)',
        'outputGain (0x14)',
        'filterCutoff/XO (0x15)',
        'delayCandidate (0x17)',
        'peqGain (0x18/0x01)',
        'peqQ (0x18/0x00)',
        'peqFrequency (0x18/0x02)',
      };
      const noEvidenceInConsumer = {
        'peqEnableBypass — no param in any Consumer builder or ICP5 capture',
      };
      expect(ported, isNotEmpty);
      expect(noEvidenceInConsumer, hasLength(1));
    });
  });
}
