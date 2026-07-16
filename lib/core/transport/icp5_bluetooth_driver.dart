import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'icp5_serial_driver.dart';

/// Capture-proven ICP5 BLE GATT byte channel.
///
/// This adapter knows only how to move bytes through FFF2/FFF1. ICP5 framing,
/// handshake, ACK parsing, diagnostics, rollback, and STOP remain owned by the
/// shared ICP5 session transport.
class Icp5BluetoothGattDriver implements Icp5SerialDriver {
  static const serviceUuid = 'fff0';
  static const txCharacteristicUuid = 'fff2';
  static const rxCharacteristicUuid = 'fff1';
  final Duration scanTimeout;

  Icp5BluetoothGattDriver({this.scanTimeout = const Duration(seconds: 10)});

  final Map<String, BluetoothDevice> _discoveredDevices = {};

  @override
  bool get platformSupported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isLinux);

  @override
  Future<Icp5DiscoveryResult> discover() async {
    const source = 'BLE GATT advertised service FFF0';
    _discoveredDevices.clear();
    if (!platformSupported) {
      return const Icp5DiscoveryResult(
          source: source,
          allPorts: [],
          matches: [],
          error: 'ICP5 BLE GATT is unavailable on this platform.');
    }
    try {
      if (await FlutterBluePlus.adapterState.first !=
          BluetoothAdapterState.on) {
        return const Icp5DiscoveryResult(
            source: source,
            allPorts: [],
            matches: [],
            error: 'Bluetooth adapter is not on.');
      }
      await FlutterBluePlus.startScan(
          withServices: [Guid(serviceUuid)], timeout: scanTimeout);
      final results = await FlutterBluePlus.scanResults
          .where((results) => results.any(_advertisesIcp5Service))
          .first
          .timeout(scanTimeout);
      final matches = results.where(_advertisesIcp5Service).map((result) {
        final id = result.device.remoteId.str;
        _discoveredDevices[id] = result.device;
        final name = result.device.advName.trim();
        return Icp5SerialDevice(
            portName: id,
            productName: name.isEmpty ? null : name,
            friendlyName: name.isEmpty ? 'Unnamed BLE device' : name,
            instanceId: id,
            enumerationSource: source);
      }).toList(growable: false);
      return Icp5DiscoveryResult(
          source: source, allPorts: matches, matches: matches);
    } on TimeoutException {
      return const Icp5DiscoveryResult(
          source: source,
          allPorts: [],
          matches: [],
          error: 'No device advertising BLE service FFF0 was found.');
    } catch (error) {
      return Icp5DiscoveryResult(
          source: source,
          allPorts: const [],
          matches: const [],
          error: 'ICP5 BLE discovery failed: $error');
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  bool _advertisesIcp5Service(ScanResult result) =>
      result.advertisementData.serviceUuids
          .any((uuid) => uuid.str128.toLowerCase().contains(serviceUuid));

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    final device = _discoveredDevices[portName];
    if (device == null) {
      throw StateError('Selected ICP5 BLE device was not discovered.');
    }
    await device.connect(timeout: const Duration(seconds: 10));
    final services = await device.discoverServices();
    final service = services
        .where((candidate) =>
            candidate.uuid.str128.toLowerCase().contains(serviceUuid))
        .firstOrNull;
    if (service == null) {
      await device.disconnect();
      throw StateError('Service discovery failed: FFF0 was not found.');
    }
    BluetoothCharacteristic? tx;
    BluetoothCharacteristic? rx;
    for (final characteristic in service.characteristics) {
      final uuid = characteristic.uuid.str128.toLowerCase();
      if (uuid.contains(txCharacteristicUuid)) tx = characteristic;
      if (uuid.contains(rxCharacteristicUuid)) rx = characteristic;
    }
    if (tx == null ||
        !(tx.properties.write || tx.properties.writeWithoutResponse)) {
      await device.disconnect();
      throw StateError(
          'Service discovery failed: writable FFF2 was not found.');
    }
    if (rx == null || !rx.properties.notify) {
      await device.disconnect();
      throw StateError(
          'Notify subscription failed: notifiable FFF1 was not found.');
    }
    try {
      await rx.setNotifyValue(true);
    } catch (error) {
      await device.disconnect();
      throw StateError('Notify subscription failed for FFF1: $error');
    }
    return _Icp5BluetoothGattConnection(device: device, tx: tx, rx: rx);
  }
}

class _Icp5BluetoothGattConnection implements Icp5SerialConnection {
  final BluetoothDevice device;
  final BluetoothCharacteristic tx;
  final BluetoothCharacteristic rx;
  final StreamController<List<int>> _bytes =
      StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _stateSubscription;
  bool _closing = false;

  _Icp5BluetoothGattConnection(
      {required this.device, required this.tx, required this.rx}) {
    _notifySubscription = rx.onValueReceived.listen(
        (value) => _bytes.add(List<int>.unmodifiable(value)),
        onError: _bytes.addError);
    _stateSubscription = device.connectionState.listen((state) {
      if (!_closing && state == BluetoothConnectionState.disconnected) {
        _bytes.addError(StateError('ICP5 BLE Notify disconnected.'));
      }
    });
  }

  @override
  Stream<List<int>> get bytes => _bytes.stream;

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    await tx
        .write(bytes, withoutResponse: false, timeout: timeout.inSeconds)
        .timeout(timeout);
    return bytes.length;
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _notifySubscription?.cancel();
    await _stateSubscription?.cancel();
    if (rx.isNotifying) await rx.setNotifyValue(false);
    await device.disconnect();
    await _bytes.close();
  }
}
