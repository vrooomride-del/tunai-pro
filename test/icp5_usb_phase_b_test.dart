import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_protocol_evidence.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/workbench/tabs/transport_connection_panel.dart';

const identityRx = <int>[
  0x55,
  0x18,
  0xE0,
  0,
  0,
  0,
  0,
  0,
  0x44,
  0x53,
  0x50,
  0x31,
  0x37,
  0x30,
  0x31,
  0x2E,
  0x31,
  0x30,
  0x30,
  0x2E,
  0x30,
  0x30,
  0x2E,
  0x30,
  0x31,
  0xD9,
];
const goodAck = <int>[0x55, 0x07, 0xE1, 0, 0, 0, 0x10, 0, 0x4D];
const goodMuteAck = <int>[0x55, 0x07, 0xE1, 0, 0, 0, 0x12, 0, 0x4F];

class FakeConnection implements Icp5SerialConnection {
  final _controller = StreamController<List<int>>.broadcast(sync: true);
  final List<List<int>> writes = [];
  final void Function(FakeConnection connection, int call, List<int> bytes)
      onWrite;
  FakeConnection(this.onWrite);
  @override
  Stream<List<int>> get bytes => _controller.stream;
  void emit(List<int> bytes) => _controller.add(bytes);
  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    writes.add(List.from(bytes));
    onWrite(this, writes.length, bytes);
    return bytes.length;
  }

  @override
  Future<void> close() async => _controller.close();
}

class FakeDriver implements Icp5SerialDriver {
  final FakeConnection connection;
  final List<Icp5SerialDevice> devices;
  String? openedPort;
  FakeDriver(this.connection,
      {this.devices = const [
        Icp5SerialDevice(
            portName: 'COM27',
            vendorId: 0x1A86,
            productId: 0x55D6,
            productName: 'USB-BLE-SERIAL CH9143')
      ]});
  @override
  bool get platformSupported => true;
  String? discoveryError;
  @override
  Future<Icp5DiscoveryResult> discover() async => Icp5DiscoveryResult(
      source: 'Fake SetupAPI',
      allPorts: devices,
      matches: devices.where((device) => device.isCaptureProvenIcp5).toList(),
      error: discoveryError);
  @override
  Future<Icp5SerialConnection> open(String portName) async {
    openedPort = portName;
    return connection;
  }
}

void main() {
  test('exact identification and capture frames', () {
    expect(Icp5FrameCodec.identificationRequest,
        [0x55, 0x07, 0x1A, 0, 0, 0, 0, 0, 0x76]);
    expect(Icp5FrameCodec.parseIdentity(identityRx), 'DSP1701.100.00.01');
    expect(Icp5FrameCodec.buildMasterVolumeWrite(5.9),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x10, 0xCD, 0xCC, 0xBC, 0x40, 0x20]);
    expect(Icp5FrameCodec.buildMasterVolumeWrite(6.0),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x10, 0, 0, 0xC0, 0x40, 0x8B]);
    expect(
        () => Icp5FrameCodec.buildMasterVolumeWrite(5.8), throwsArgumentError);
  });

  test('checksum, ACK and parameter matching fail closed', () {
    expect(Icp5FrameCodec.checksum(goodAck.take(goodAck.length - 1)), 0x4D);
    expect(Icp5FrameCodec.parseMasterVolumeAck(goodAck), isTrue);
    final badChecksum = [...goodAck]..[8] = 0;
    expect(Icp5FrameCodec.parseMasterVolumeAck(badChecksum), isFalse);
    final wrongParameter = [...goodAck]..[6] = 0x11;
    wrongParameter[8] = Icp5FrameCodec.checksum(wrongParameter.take(8));
    expect(Icp5FrameCodec.parseMasterVolumeAck(wrongParameter), isFalse);
  });

  test('exact Master Mute State 0/1 frames and ACK are capture-locked', () {
    expect(Icp5FrameCodec.buildMasterMuteWrite(0),
        [0x55, 0x09, 0x1C, 0, 0, 0, 0x12, 0x01, 0, 0, 0x8D]);
    expect(Icp5FrameCodec.buildMasterMuteWrite(1),
        [0x55, 0x09, 0x1C, 0, 0, 0, 0x12, 0x01, 0, 1, 0x8E]);
    expect(() => Icp5FrameCodec.buildMasterMuteWrite(2), throwsArgumentError);
    expect(Icp5FrameCodec.parseMasterMuteAck(goodMuteAck), isTrue);
    final badChecksum = [...goodMuteAck]..[8] = 0;
    expect(Icp5FrameCodec.parseMasterMuteAck(badChecksum), isFalse);
    expect(Icp5FrameCodec.parseMasterMuteAck(goodAck), isFalse);
    expect(Icp5ProtocolEvidenceRegistry.usb.masterMuteParameterId, 0x12);
    expect(Icp5ProtocolEvidenceRegistry.usb.masterMutePayloadPrefix, [1, 0]);
    expect(Icp5ProtocolEvidenceRegistry.usb.capturedMasterMuteStates, [0, 1]);
    expect(Icp5ProtocolEvidenceRegistry.usb.masterMuteAckParameterId, 0x12);
    expect(Icp5ProtocolEvidenceRegistry.usb.masterMuteSuccessStatus, 0);
    expect(Icp5ProtocolEvidenceRegistry.usb.masterMutePolarityProven, isFalse);
  });

  test('partial buffering extracts complete declared-length frames', () {
    final buffer = Icp5FrameBuffer();
    expect(buffer.add(identityRx.sublist(0, 7)), isEmpty);
    expect(buffer.add(identityRx.sublist(7, 20)), isEmpty);
    expect(buffer.add(identityRx.sublist(20)), [identityRx]);
  });

  test('VID/PID discovery is exact and does not hardcode COM3', () {
    const valid = Icp5SerialDevice(
        portName: 'COM27',
        vendorId: 0x1A86,
        productId: 0x55D6,
        friendlyName: 'USB-BLE-SERIAL CH9143(COM27)');
    const wrongPid = Icp5SerialDevice(
        portName: 'COM3',
        vendorId: 0x1A86,
        productId: 0x55D4,
        productName: 'CH9143');
    expect(valid.isCaptureProvenIcp5, isTrue);
    expect(wrongPid.isCaptureProvenIcp5, isFalse);
  });

  test('SetupAPI evidence matching and COM extraction are case-insensitive',
      () {
    const exact = Icp5SerialDevice(
        portName: 'COM3',
        friendlyName: 'USB-BLE-SERIAL CH9143(COM3)',
        instanceId: r'USB\VID_1A86&PID_55D6\WCH0642C2TS1');
    const lower = Icp5SerialDevice(
        portName: 'COM10',
        friendlyName: 'usb-ble-serial ch9143(com10)',
        instanceId: r'usb\vid_1a86&pid_55d6\wch0642c2ts1');
    const unrelated = Icp5SerialDevice(
        portName: 'COM8',
        friendlyName: 'Generic USB Serial(COM8)',
        instanceId: r'USB\VID_1234&PID_5678\ABC');
    expect(exact.isCaptureProvenIcp5, isTrue);
    expect(lower.isCaptureProvenIcp5, isTrue);
    expect(unrelated.isCaptureProvenIcp5, isFalse);
    expect(Icp5SerialDevice.extractComPort(exact.friendlyName), 'COM3');
    expect(Icp5SerialDevice.extractComPort(lower.friendlyName), 'COM10');
  });

  test('handshake is required and one action emits one write', () async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 2) connection.emit(goodAck);
    });
    final driver = FakeDriver(connection);
    final transport = Icp5UsbTransport(driver: driver);
    expect((await transport.writeCapturedMasterVolume(5.9)).success, isFalse);
    expect(connection.writes, isEmpty);
    expect((await transport.open()).success, isTrue);
    expect(driver.openedPort, 'COM27');
    final result = await transport.writeCapturedMasterVolume(5.9);
    expect(result.success, isTrue);
    expect(result.message, 'PASS_ACK');
    expect(connection.writes, hasLength(2)); // handshake + exactly one action
    await transport.close();
  });

  test('identity partial reads and timeout behavior', () async {
    late FakeConnection partial;
    partial = FakeConnection((connection, call, bytes) {
      connection.emit(identityRx.sublist(0, 5));
      connection.emit(identityRx.sublist(5));
    });
    final good = Icp5UsbTransport(driver: FakeDriver(partial));
    expect((await good.open()).success, isTrue);
    await good.close();

    final silent = FakeConnection((_, __, ___) {});
    final timed = Icp5UsbTransport(
        driver: FakeDriver(silent),
        readTimeout: const Duration(milliseconds: 10));
    expect((await timed.open()).success, isFalse);
  });

  test('TEST failure restores once; restore failure activates STOP', () async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 3) connection.emit(goodAck); // test times out; restore passes
    });
    final transport = Icp5UsbTransport(
        driver: FakeDriver(connection),
        readTimeout: const Duration(milliseconds: 10));
    await transport.open();
    final outcome = await transport.runTestWithGuardedRestore();
    expect(outcome.test.success, isFalse);
    expect(outcome.restore?.success, isTrue);
    expect(connection.writes[1], Icp5FrameCodec.buildMasterVolumeWrite(5.9));
    expect(connection.writes[2], Icp5FrameCodec.buildMasterVolumeWrite(6.0));
    await transport.close();

    final stops = <String>[];
    late FakeConnection failing;
    failing = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
    });
    final stopped = Icp5UsbTransport(
        driver: FakeDriver(failing),
        readTimeout: const Duration(milliseconds: 10),
        onDspWriteStop: stops.add);
    await stopped.open();
    final failed = await stopped.runTestWithGuardedRestore();
    expect(failed.stopActivated, isTrue);
    expect(stopped.stopped, isTrue);
    expect(stops.single, contains('shared DSP STOP'));
    await stopped.close();
  });

  test('Master Mute requires handshake and one action emits one frame',
      () async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 2) connection.emit(goodMuteAck);
    });
    final transport = Icp5UsbTransport(driver: FakeDriver(connection));
    expect((await transport.writeCapturedMasterMuteState(1)).success, isFalse);
    expect(connection.writes, isEmpty);
    expect((await transport.open()).success, isTrue);
    final result = await transport.writeCapturedMasterMuteState(1);
    expect(result.success, isTrue);
    expect(result.message, 'PASS_ACK');
    expect(connection.writes, hasLength(2));
    expect(connection.writes.last, Icp5FrameCodec.buildMasterMuteWrite(1));
    await transport.close();
  });

  test('Master Mute TEST failure restores State 0 and failure activates STOP',
      () async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 3) connection.emit(goodMuteAck);
    });
    final transport = Icp5UsbTransport(
        driver: FakeDriver(connection),
        readTimeout: const Duration(milliseconds: 10));
    await transport.open();
    final outcome = await transport.runMuteTestWithGuardedRestore();
    expect(outcome.test.success, isFalse);
    expect(outcome.restore?.success, isTrue);
    expect(connection.writes[1], Icp5FrameCodec.buildMasterMuteWrite(1));
    expect(connection.writes[2], Icp5FrameCodec.buildMasterMuteWrite(0));
    await transport.close();

    final stops = <String>[];
    late FakeConnection failing;
    failing = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
    });
    final stopped = Icp5UsbTransport(
        driver: FakeDriver(failing),
        readTimeout: const Duration(milliseconds: 10),
        onDspWriteStop: stops.add);
    await stopped.open();
    final failed = await stopped.runMuteTestWithGuardedRestore();
    expect(failed.stopActivated, isTrue);
    expect(stopped.stopped, isTrue);
    expect(stops.single, contains('Master Mute restore failed'));
    await stopped.close();
  });

  testWidgets('discovery UI shows identity and enumerated-only manual ports',
      (tester) async {
    final connection = FakeConnection((_, __, ___) {});
    final driver = FakeDriver(connection, devices: const [
      Icp5SerialDevice(
          portName: 'COM10',
          friendlyName: 'USB-BLE-SERIAL CH9143(COM10)',
          instanceId: r'USB\VID_1A86&PID_55D6\WCH0642C2TS1',
          vendorId: 0x1A86,
          productId: 0x55D6),
      Icp5SerialDevice(
          portName: 'COM8',
          friendlyName: 'Other Serial(COM8)',
          instanceId: r'USB\VID_1234&PID_5678\OTHER'),
    ]);
    final transport = Icp5UsbTransport(driver: driver);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TransportConnectionPanel(
                    backend: const ProUsbiNativeBackendDisabled(),
                    deviceOpen: false,
                    icp5UsbTransport: transport)))));
    await tester.tap(find.text('ICP5 USB'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('icp5_discover_button')));
    await tester.tap(find.byKey(const Key('icp5_discover_button')));
    await tester.pumpAndSettle();
    expect(find.text('COM10'), findsWidgets);
    expect(find.text('VID 1A86 / PID 55D6'), findsOneWidget);
    expect(find.text(r'USB\VID_1A86&PID_55D6\WCH0642C2TS1'), findsOneWidget);
    final selector = tester.widget<DropdownButton<String>>(
        find.byKey(const Key('icp5_manual_port_selector')));
    expect(selector.items!.map((item) => item.value), ['COM10', 'COM8']);
    expect(find.byKey(const Key('icp5_master_mute_panel')), findsOneWidget);
    expect(find.text('TEST State 1'), findsOneWidget);
    expect(find.text('RESTORE State 0'), findsOneWidget);
  });

  testWidgets('failed discovery displays source and candidate count',
      (tester) async {
    final driver = FakeDriver(FakeConnection((_, __, ___) {}), devices: const [
      Icp5SerialDevice(
          portName: 'COM8',
          friendlyName: 'Other(COM8)',
          instanceId: r'USB\VID_1234&PID_5678\OTHER'),
    ])
      ..discoveryError =
          'No ICP5 found via Fake SetupAPI; 1 candidate port(s) enumerated.';
    final transport = Icp5UsbTransport(driver: driver);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TransportConnectionPanel(
                    backend: const ProUsbiNativeBackendDisabled(),
                    deviceOpen: false,
                    icp5UsbTransport: transport)))));
    await tester.tap(find.text('ICP5 USB'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('icp5_discover_button')));
    await tester.tap(find.byKey(const Key('icp5_discover_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('icp5_discovery_error')), findsOneWidget);
    expect(find.textContaining('Fake SetupAPI'), findsWidgets);
    expect(find.textContaining('1 candidate'), findsOneWidget);
  });

  testWidgets('Master Mute confirmed UI state is ACK-gated', (tester) async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 2) connection.emit(goodMuteAck);
    });
    final transport = Icp5UsbTransport(driver: FakeDriver(connection));
    await transport.open();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TransportConnectionPanel(
                    backend: const ProUsbiNativeBackendDisabled(),
                    deviceOpen: false,
                    icp5UsbTransport: transport)))));
    await tester.tap(find.text('ICP5 USB'));
    await tester.pump();
    expect(find.text('State 0'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const Key('icp5_mute_test_state_1_button')));
    await tester.tap(find.byKey(const Key('icp5_mute_test_state_1_button')));
    await tester.pumpAndSettle();
    expect(find.text('State 1'), findsOneWidget);
    expect(connection.writes.last, Icp5FrameCodec.buildMasterMuteWrite(1));
  });
}
