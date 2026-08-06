import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/connect/consumer_ble_service.dart';

const _identity = <int>[
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

class _Connection implements Icp5SerialConnection {
  final _bytes = StreamController<List<int>>.broadcast(sync: true);
  final List<int>? identity;
  final writes = <List<int>>[];

  _Connection({this.identity = _identity});

  void disconnectUnexpectedly() =>
      _bytes.addError(StateError('Bluetooth disconnected'));

  @override
  Stream<List<int>> get bytes => _bytes.stream;

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    writes.add(List<int>.of(bytes));
    if (writes.length == 1 && identity != null) _bytes.add(identity!);
    return bytes.length;
  }

  @override
  Future<void> close() async {
    if (!_bytes.isClosed) await _bytes.close();
  }
}

class _Driver implements Icp5SerialDriver {
  final _Connection connection;
  final bool supported;
  final String? error;
  int discoverCalls = 0;
  int openCalls = 0;
  String? openedIdentifier;

  _Driver(this.connection, {this.supported = true, this.error});

  static const other = Icp5SerialDevice(
    portName: 'other-id',
    friendlyName: 'Other device',
    instanceId: 'other-id',
    rssi: -20,
  );
  static const icp5 = Icp5SerialDevice(
    portName: 'icp5-id',
    friendlyName: 'WONDOM ICP5',
    instanceId: 'icp5-id',
    rssi: -42,
  );

  @override
  bool get platformSupported => supported;

  @override
  Future<Icp5DiscoveryResult> discover() async {
    discoverCalls++;
    if (error != null) {
      return Icp5DiscoveryResult(
          source: 'fake BLE',
          allPorts: const [],
          matches: const [],
          error: error);
    }
    return const Icp5DiscoveryResult(
      source: 'fake BLE',
      allPorts: [other, icp5],
      matches: [other, icp5],
    );
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    openCalls++;
    openedIdentifier = portName;
    return connection;
  }
}

ConsumerBleService _service(_Driver driver,
        {Duration timeout = const Duration(milliseconds: 30)}) =>
    ConsumerBleService(
      transport: Icp5BluetoothTransport(
          driver: driver, readTimeout: timeout, writeTimeout: timeout),
    );

void main() {
  test('BLE unavailable is consumer-safe and performs no discovery', () async {
    final driver = _Driver(_Connection(), supported: false);
    final service = _service(driver);
    await service.scan();
    expect(service.state.status, ConsumerBleStatus.bluetoothUnavailable);
    expect(service.state.message, 'Bluetooth unavailable');
    expect(driver.discoverCalls, 0);
    service.dispose();
  });

  test('scan prefers WONDOM ICP5 and supports manual selection', () async {
    final driver = _Driver(_Connection());
    final service = _service(driver);
    await service.scan();
    expect(service.state.status, ConsumerBleStatus.deviceFound);
    expect(service.state.devices.map((device) => device.name),
        ['Other device', 'WONDOM ICP5']);
    expect(service.state.selectedIdentifier, 'icp5-id');
    expect(service.selectDevice('other-id'), isTrue);
    expect(service.state.selectedIdentifier, 'other-id');
    expect(service.selectDevice('not-enumerated'), isFalse);
    service.dispose();
  });

  test('connect requires shared PASS_HANDSHAKE and persists connected state',
      () async {
    final connection = _Connection();
    final driver = _Driver(connection);
    final service = _service(driver);
    await service.scan();
    await service.connect();
    expect(service.state.status, ConsumerBleStatus.connected);
    expect(service.state.connectedDeviceName, 'WONDOM ICP5');
    expect(driver.openedIdentifier, 'icp5-id');
    expect(connection.writes, [Icp5FrameCodec.identificationRequest]);
    service.refreshConnectionState();
    expect(service.state.status, ConsumerBleStatus.connected);
    await service.disconnect();
    expect(service.state.status, ConsumerBleStatus.disconnected);
    service.dispose();
  });

  test('unsupported handshake fails closed with no automatic retry', () async {
    final driver = _Driver(_Connection(identity: null));
    final service = _service(driver, timeout: const Duration(milliseconds: 5));
    await service.scan();
    await service.connect();
    expect(service.state.status, ConsumerBleStatus.deviceNotSupported);
    expect(service.state.message, 'Device not supported');
    expect(driver.openCalls, 1);
    expect(driver.discoverCalls, 1);
    service.dispose();
  });

  test('unexpected disconnect returns to disconnected without retry', () async {
    final connection = _Connection();
    final driver = _Driver(connection);
    final service = _service(driver);
    await service.scan();
    await service.connect();
    connection.disconnectUnexpectedly();
    service.refreshConnectionState();
    expect(service.state.status, ConsumerBleStatus.disconnected);
    expect(driver.openCalls, 1);
    expect(driver.discoverCalls, 1);
    service.dispose();
  });

  test('permission failure is exposed without protocol detail', () async {
    final driver = _Driver(_Connection(), error: 'permission denied by OS');
    final service = _service(driver);
    await service.scan();
    expect(service.state.status, ConsumerBleStatus.permissionRequired);
    expect(service.state.message, 'Permission required');
    service.dispose();
  });

  // Formerly a widget test that drove the now-deleted (orphaned, unreachable
  // from lib/main.dart) ConnectScreen through scan → select → connect →
  // disconnect. The ConsumerBleService behavior it exercised — auto-selecting
  // the WONDOM ICP5 match on scan, writing exactly the identification
  // request on connect, and returning to disconnected on teardown — is
  // covered at the service level by 'scan prefers WONDOM ICP5 and supports
  // manual selection' and 'connect requires shared PASS_HANDSHAKE and
  // persists connected state' above. UI-only assertions (hidden diagnostics
  // text, widget keys) do not apply once no widget renders this service.
  test(
      'full scan-select-connect-write-disconnect cycle matches the '
      'ICP5 identification handshake', () async {
    final connection = _Connection();
    final driver = _Driver(connection);
    final service = _service(driver);
    await service.scan();
    expect(service.state.selectedIdentifier, 'icp5-id');
    await service.connect();
    expect(service.state.status, ConsumerBleStatus.connected);
    expect(connection.writes, [Icp5FrameCodec.identificationRequest]);
    await service.disconnect();
    expect(service.state.status, ConsumerBleStatus.disconnected);
    service.dispose();
  });
}
