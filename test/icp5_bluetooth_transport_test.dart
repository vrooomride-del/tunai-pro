import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:tunai_pro/core/transport/dsp_transport.dart';
import 'package:tunai_pro/core/transport/icp5_bluetooth_driver.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

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
const volumeAck = <int>[0x55, 0x07, 0xE1, 0, 0, 0, 0x10, 0, 0x4D];

class _FakeGattConnection implements Icp5SerialConnection {
  final _controller = StreamController<List<int>>.broadcast(sync: true);
  final writes = <List<int>>[];
  final void Function(_FakeGattConnection connection, int call, List<int> bytes)
      onWrite;

  _FakeGattConnection(this.onWrite);

  @override
  Stream<List<int>> get bytes => _controller.stream;

  void notify(List<int> bytes) => _controller.add(bytes);
  void disconnectNotify() =>
      _controller.addError(StateError('ICP5 BLE Notify disconnected.'));

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    writes.add(List<int>.of(bytes));
    onWrite(this, writes.length, bytes);
    return bytes.length;
  }

  @override
  Future<void> close() => _controller.close();
}

class _FakeGattDriver implements Icp5SerialDriver {
  final _FakeGattConnection connection;
  int discoverCalls = 0;
  String? openedPort;
  _FakeGattDriver(this.connection);

  @override
  bool get platformSupported => true;

  @override
  Future<Icp5DiscoveryResult> discover() async {
    discoverCalls++;
    return const Icp5DiscoveryResult(source: 'fake FFF0', allPorts: [
      Icp5SerialDevice(portName: 'ble-device'),
      Icp5SerialDevice(portName: 'ble-selected')
    ], matches: [
      Icp5SerialDevice(portName: 'ble-device'),
      Icp5SerialDevice(portName: 'ble-selected')
    ]);
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    openedPort = portName;
    return connection;
  }
}

void main() {
  test('BLE GATT UUIDs are capture locked', () {
    expect(Icp5BluetoothGattDriver.serviceUuid, 'fff0');
    expect(Icp5BluetoothGattDriver.txCharacteristicUuid, 'fff2');
    expect(Icp5BluetoothGattDriver.rxCharacteristicUuid, 'fff1');
  });

  test('BLE scan source does not claim FFF0 advertisement filtering', () {
    const source = Icp5BluetoothGattDriver.discoverySource;
    expect(source, isNot(contains('advertised service FFF0')));
    expect(source, contains('verified after connect'));
  });

  test('short and Bluetooth Base FFF0 UUIDs match exactly', () {
    expect(
        Icp5BluetoothGattDriver.isExpectedUuid(Guid('fff0'), 'fff0'), isTrue);
    expect(
        Icp5BluetoothGattDriver.isExpectedUuid(
            Guid('0000fff0-0000-1000-8000-00805f9b34fb'), 'fff0'),
        isTrue);
    expect(
        Icp5BluetoothGattDriver.isExpectedUuid(Guid('fff1'), 'fff0'), isFalse);
    expect(
        Icp5BluetoothGattDriver.isExpectedUuid(
            Guid('1234fff0-1111-2222-3333-444455556666'), 'fff0'),
        isFalse);
  });

  test('selected and connecting identifiers must match exactly', () {
    expect(
        Icp5BluetoothGattDriver.identifiersMatch('ABC-123', 'ABC-123'), isTrue);
    expect(Icp5BluetoothGattDriver.identifiersMatch('ABC-123', 'DEF-456'),
        isFalse);
    expect(Icp5BluetoothGattDriver.identifiersMatch('ABC-123', 'abc-123'),
        isFalse);
  });

  test('BLE open preserves selection and does not rescan', () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) connection.notify(identityRx);
    });
    final driver = _FakeGattDriver(connection);
    final transport = Icp5BluetoothTransport(
        driver: driver, readTimeout: const Duration(milliseconds: 50));

    await transport.discover();
    expect(transport.selectEnumeratedPort('ble-selected'), isTrue);
    final result = await transport.open();

    expect(result.success, isTrue);
    expect(driver.discoverCalls, 1);
    expect(driver.openedPort, 'ble-selected');
    await transport.close();
  });

  test('missing exact BLE selection fails closed without substitute', () async {
    final driver = _FakeGattDriver(_FakeGattConnection((_, __, ___) {}));
    final transport = Icp5BluetoothTransport(driver: driver);

    final result = await transport.open();

    expect(result.success, isFalse);
    expect(driver.discoverCalls, 0);
    expect(driver.openedPort, isNull);
  });

  test('BLE uses unchanged handshake codec and reassembles Notify chunks',
      () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) {
        connection.notify(identityRx.sublist(0, 6));
        connection.notify(identityRx.sublist(6));
      }
    });
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(milliseconds: 50));

    await transport.discover();
    final result = await transport.open();

    expect(result.success, isTrue);
    expect(transport.identity, DspTransportIdentity.icp5Bluetooth);
    expect(transport.handshakeComplete, isTrue);
    expect(transport.detectedProfile, Icp5FrameCodec.expectedProfile);
    expect(connection.writes.single, Icp5FrameCodec.identificationRequest);
    await transport.close();
  });

  test('BLE diagnostics reuse ACK-gated transaction logic unchanged', () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) connection.notify(identityRx);
      if (call == 2) connection.notify(volumeAck);
    });
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(milliseconds: 50));
    await transport.discover();
    await transport.open();

    final result = await transport.writeCapturedMasterVolume(5.9);

    expect(result.success, isTrue);
    expect(result.message, 'PASS_ACK');
    expect(connection.writes[1], Icp5FrameCodec.buildMasterVolumeWrite(5.9));
    await transport.close();
  });

  test('BLE Notify disconnect fails closed and subsequent write times out',
      () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) connection.notify(identityRx);
      if (call == 2) connection.disconnectNotify();
    });
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(milliseconds: 10));
    await transport.discover();
    await transport.open();

    final result = await transport.writeCapturedMasterVolume(5.9);

    expect(result.success, isFalse);
    expect(result.writeMayHaveReachedDevice, isTrue);
    expect(result.message, anyOf(contains('timeout'), contains('ACK')));
    await transport.close();
  });

  test('BLE reuses guarded restore and shared STOP after ACK timeouts',
      () async {
    late _FakeGattConnection connection;
    connection = _FakeGattConnection((connection, call, bytes) {
      if (call == 1) connection.notify(identityRx);
    });
    final warnings = <String>[];
    final transport = Icp5BluetoothTransport(
        driver: _FakeGattDriver(connection),
        readTimeout: const Duration(milliseconds: 10),
        onDspWriteStop: warnings.add);
    await transport.discover();
    await transport.open();

    final outcome = await transport.runTestWithGuardedRestore();

    expect(outcome.test.success, isFalse);
    expect(outcome.restore?.success, isFalse);
    expect(outcome.stopActivated, isTrue);
    expect(transport.stopped, isTrue);
    expect(connection.writes[1], Icp5FrameCodec.buildMasterVolumeWrite(5.9));
    expect(connection.writes[2], Icp5FrameCodec.buildMasterVolumeWrite(6.0));
    expect(warnings.single, contains('shared DSP STOP'));
    await transport.close();
  });
}
