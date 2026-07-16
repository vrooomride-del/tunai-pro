import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
  _FakeGattDriver(this.connection);

  @override
  bool get platformSupported => true;

  @override
  Future<Icp5DiscoveryResult> discover() async => const Icp5DiscoveryResult(
      source: 'fake FFF0',
      allPorts: [Icp5SerialDevice(portName: 'ble-device')],
      matches: [Icp5SerialDevice(portName: 'ble-device')]);

  @override
  Future<Icp5SerialConnection> open(String portName) async => connection;
}

void main() {
  test('BLE GATT UUIDs are capture locked', () {
    expect(Icp5BluetoothGattDriver.serviceUuid, 'fff0');
    expect(Icp5BluetoothGattDriver.txCharacteristicUuid, 'fff2');
    expect(Icp5BluetoothGattDriver.rxCharacteristicUuid, 'fff1');
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
